#!/usr/bin/env python3
"""Format census of a topic, for 'playground topic check-format'.

Reads the RAW_RECORD lines of DlqTool (raw mode): partition, offset, the first bytes of the key and of the value in
base64, the header names and the value of the __key_schema_id / __value_schema_id headers. Recognises the format of
each key and value from its bytes (Schema Registry wire format, schema id in a header, JSON with or without the
JsonConverter envelope, string, binary, tombstone...), groups consecutive records of the same format into ranges per
partition, and tells what each converter does with them.

  ids     --records <file>                           the schema ids and guids to look up, one per line
  report  --records <file> --summary <json> --schemas <file> --subjects <file> --topic <topic>
          [--sides key,value] [--samples] [--json] [--status-out <file>]

--schemas: {"ids": {"<id>": {"found": bool, "schemaType": .., "schema": .., "versions": [{subject, version}]}},
            "guids": {"<guid>": {...same...}}, "unreachable": "<error>"}
--subjects: {"key": {"subject": .., "id": .., "version": .., "schemaType": ..} or null, "value": ...}

Untrusted data: the records are only decoded and printed, never evaluated.
"""
import argparse
import base64
import json
import re
import sys
import uuid

CONVERTERS = {
    'AVRO': 'io.confluent.connect.avro.AvroConverter',
    'PROTOBUF': 'io.confluent.connect.protobuf.ProtobufConverter',
    'JSON': 'io.confluent.connect.json.JsonSchemaConverter',
}
TYPE_NAMES = {'AVRO': 'Avro', 'PROTOBUF': 'Protobuf', 'JSON': 'JSON Schema'}

# families: two records of the same family are read by the same converter
FAMILY_NAMES = {
    'sr': 'Schema Registry wire format',
    'sr-header': 'schema id in a header',
    'json-envelope': 'JSON with the schema/payload envelope',
    'json': 'JSON, no schema',
    'string': 'string',
    'binary': 'binary',
    'avro-file': 'Avro container file',
}
NEUTRAL = ('null', 'empty')
# '<n> values are …'
FAMILY_PHRASES = {
    'sr': 'in the Schema Registry wire format',
    'sr-header': 'in a Schema Registry format with the schema id in a header',
    'json-envelope': 'JSON with the schema/payload envelope',
    'json': 'plain JSON (no schema)',
    'string': 'strings',
    'binary': 'binary',
    'avro-file': 'Avro container files',
}


def plural(n, word):
    return '%d %s%s' % (n, word, '' if n == 1 else 's')


def load_records(path):
    records = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    records.sort(key=lambda r: (r['partition'], r['offset']))
    return records


def b64(s):
    return None if s is None else base64.b64decode(s)


def header_schema_ref(raw):
    """__value_schema_id header: 0x01 + 16 bytes guid, or 0x00 + 4 bytes id"""
    if not raw:
        return None
    if raw[0] == 1 and len(raw) >= 17:
        return ('guid', str(uuid.UUID(bytes=raw[1:17])))
    if raw[0] == 0 and len(raw) >= 5:
        return ('id', int.from_bytes(raw[1:5], 'big'))
    return None


def decode_text(data, truncated):
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError as e:
        # a multi-byte character cut by the truncation
        if truncated and e.start >= len(data) - 3:
            try:
                return data[:e.start].decode('utf-8')
            except UnicodeDecodeError:
                return None
        return None


def is_printable(text):
    return all(c in '\t\n\r' or ord(c) >= 0x20 for c in text) and '�' not in text


def classify(record, side):
    """(family, schema ref or None, detail) of the key or the value of a record"""
    length = record[side + '_bytes']
    if length < 0:
        return 'null', None, None
    if length == 0:
        return 'empty', None, None
    data = b64(record[side])
    truncated = len(data) < length
    ref = header_schema_ref(b64(record.get('schema_id_headers', {}).get('__%s_schema_id' % side)))
    if ref:
        return 'sr-header', ref, None
    if data[0] == 0 and len(data) >= 5:
        return 'sr', ('id', int.from_bytes(data[1:5], 'big')), None
    if data.startswith(b'Obj\x01'):
        return 'avro-file', None, None
    text = decode_text(data, truncated)
    if text is None or not is_printable(text):
        return 'binary', None, None
    stripped = text.lstrip()
    if stripped[:1] in ('{', '['):
        if truncated:
            # too long to parse: the beginning decides
            if re.match(r'\s*\{\s*"(schema|payload)"\s*:', text):
                return 'json-envelope', None, 'first %d bytes' % len(data)
            return 'json', None, 'first %d bytes' % len(data)
        try:
            doc = json.loads(text)
        except ValueError:
            return 'string', None, 'starts with %s but is not valid JSON' % stripped[0]
        if isinstance(doc, dict) and set(doc.keys()) == {'schema', 'payload'}:
            return 'json-envelope', None, None
        return 'json', None, None
    return 'string', None, None


def protobuf_indexes(data):
    """message indexes after the schema id (zigzag varints): [0] when the byte is 0"""
    pos = 5

    def varint():
        nonlocal pos
        shift = result = 0
        while pos < len(data):
            b = data[pos]
            pos += 1
            result |= (b & 0x7f) << shift
            if not b & 0x80:
                return (result >> 1) ^ -(result & 1)
            shift += 7
        return None

    count = varint()
    if count is None or count < 0 or count > 100:
        return None
    if count == 0:
        return [0]
    indexes = []
    for _ in range(count):
        i = varint()
        if i is None:
            return None
        indexes.append(i)
    return indexes


def top_level_messages(schema):
    names, depth = [], 0
    for token in re.finditer(r'\bmessage\s+(\w+)|[{}]', schema or ''):
        t = token.group(0)
        if t == '{':
            depth += 1
        elif t == '}':
            depth -= 1
        elif depth == 0:
            names.append(token.group(1))
    return names


def schema_info(ref, schemas):
    if ref is None:
        return None
    kind, key = ref
    return schemas.get('ids' if kind == 'id' else 'guids', {}).get(str(key))


def ref_text(ref):
    return 'schema id %s' % ref[1] if ref[0] == 'id' else 'schema guid %s' % ref[1]


def describe(entry, schemas, subject):
    """label of a range, and whether it is a problem"""
    family, ref = entry['family'], entry['ref']
    if family == 'null':
        return 'tombstone (null)' if entry['side'] == 'value' else 'null key', False
    if family == 'empty':
        return 'empty (0 bytes)', False
    if family in ('sr', 'sr-header'):
        where = '' if family == 'sr' else ', in the __%s_schema_id header' % entry['side']
        if schemas.get('unreachable'):
            return '%s%s (Schema Registry not reachable)' % (ref_text(ref), where), False
        info = schema_info(ref, schemas)
        if not info or not info.get('found'):
            return '%s%s (not in this Schema Registry)' % (ref_text(ref), where), True
        stype = info.get('schemaType') or 'AVRO'
        versions = info.get('versions') or []
        names = ', '.join('%s v%s' % (v['subject'], v['version']) for v in versions[:3])
        if len(versions) > 3:
            names += ', …'
        label = '%s, %s (%s)%s' % (TYPE_NAMES.get(stype, stype), ref_text(ref), names or 'no subject', where)
        if stype == 'PROTOBUF' and entry.get('message'):
            label += ', message %s' % entry['message']
        return label, False
    label = FAMILY_NAMES[family]
    if family == 'string':
        label = 'string (UTF-8)'
    if entry.get('detail'):
        label += ' (%s)' % entry['detail']
    return label, False


def sample_text(data):
    text = decode_text(data, True)
    if text is not None and is_printable(text):
        return text.replace('\n', '\\n')[:120]
    return ''.join(chr(b) if 0x20 <= b < 0x7f else '.' for b in data[:64])


def build(records, sides, schemas, subjects):
    census = {}
    for side in sides:
        rows = []
        for r in records:
            family, ref, detail = classify(r, side)
            message = None
            if family == 'sr':
                info = schema_info(ref, schemas)
                if info and info.get('schemaType') == 'PROTOBUF':
                    indexes = protobuf_indexes(b64(r[side]))
                    tops = top_level_messages(info.get('schema'))
                    if indexes and len(indexes) == 1 and indexes[0] < len(tops):
                        message = tops[indexes[0]]
                    elif indexes:
                        message = 'indexes %s' % indexes
            label_key = (family, ref, detail, message)
            last = rows[-1] if rows else None
            if last and last['partition'] == r['partition'] and last['_key'] == label_key:
                last['last_offset'] = r['offset']
                last['records'] += 1
                continue
            entry = {'side': side, 'family': family, 'ref': ref, 'detail': detail, 'message': message}
            label, problem = describe(entry, schemas, subjects.get(side))
            sample = None
            if r[side] is not None:
                data = b64(r[side])
                sample = {'offset': r['offset'], 'text': sample_text(data),
                          'hex': ' '.join('%02x' % b for b in data[:24]) + (' …' if r[side + '_bytes'] > 24 else '')}
            rows.append({'_key': label_key, 'partition': r['partition'], 'first_offset': r['offset'],
                         'last_offset': r['offset'], 'records': 1, 'family': family,
                         'schema_ref': None if ref is None else {ref[0]: ref[1]}, 'format': label,
                         'problem': problem, 'sample': sample})
        census[side] = rows
    return census


def converter_for(side, families, refs, schemas):
    prefix = side + '.converter'
    family = families[0]
    if family in ('sr', 'sr-header'):
        types = {(schema_info(r, schemas) or {}).get('schemaType') or 'AVRO' for r in refs
                 if (schema_info(r, schemas) or {}).get('found')}
        if len(types) != 1:
            return None
        lines = ['%s=%s' % (prefix, CONVERTERS[types.pop()]), '%s.schema.registry.url=<url>' % prefix]
        return lines
    if family == 'json-envelope':
        return ['%s=org.apache.kafka.connect.json.JsonConverter' % prefix, '%s.schemas.enable=true' % prefix]
    if family == 'json':
        return ['%s=org.apache.kafka.connect.json.JsonConverter' % prefix, '%s.schemas.enable=false' % prefix]
    if family == 'string':
        return ['%s=org.apache.kafka.connect.storage.StringConverter' % prefix]
    if family in ('binary', 'avro-file'):
        return ['%s=org.apache.kafka.connect.converters.ByteArrayConverter' % prefix]
    return None


def ranges_text(rows, limit=4):
    parts = ['partition %s offset%s' % (r['partition'], ' %s' % r['first_offset'] if r['first_offset'] == r['last_offset']
                                         else 's %s-%s' % (r['first_offset'], r['last_offset'])) for r in rows[:limit]]
    if len(rows) > limit:
        parts.append('%d more range(s)' % (len(rows) - limit))
    return ', '.join(parts)


def failure_message(expected, bad, side):
    """what the converter of the expected family does with records of the bad family"""
    if expected in ('sr', 'sr-header'):
        if bad in ('sr', 'sr-header'):
            return None
        return "a sink with %s.converter=AvroConverter (or Protobuf / JsonSchema) fails with 'Unknown magic byte!'" % side
    if expected in ('json', 'json-envelope'):
        if bad == 'json' and expected == 'json-envelope':
            return ('JsonConverter with schemas.enable=true fails with \'JsonConverter with schemas.enable requires '
                    '"schema" and "payload" fields and may not contain additional fields\'')
        if bad == 'json-envelope':
            return 'JsonConverter with schemas.enable=false reads them, but the schema and payload become fields of the record'
        return "JsonConverter fails with 'Converting byte[] to Kafka Connect data failed due to serialization error'"
    if expected == 'string':
        return 'StringConverter does not fail, but writes them as garbled text'
    return None


def findings_for(side, rows, schemas, subject, topic, total_read):
    findings = []
    data_rows = [r for r in rows if r['family'] not in NEUTRAL]
    families = []
    for r in data_rows:
        if r['family'] not in families:
            families.append(r['family'])
    counts = {}
    for r in data_rows:
        counts[r['family']] = counts.get(r['family'], 0) + r['records']
    sr_families = [f for f in families if f in ('sr', 'sr-header')]

    # the format the converter is expected to read: the subject's when there is one, else the most frequent
    expected = None
    if subject and sr_families:
        expected = max(sr_families, key=lambda f: counts[f])
    elif families:
        expected = max(families, key=lambda f: counts[f])

    # 1. mixed formats (two schema registry families are read by the same converter on CP 8.1+)
    others = [f for f in families if f != expected and not (f in ('sr', 'sr-header') and expected in ('sr', 'sr-header'))]
    for bad in others:
        bad_rows = [r for r in data_rows if r['family'] == bad]
        n = sum(r['records'] for r in bad_rows)
        msg = failure_message(expected, bad, side)
        first = bad_rows[0]
        message = '%s %s %s, the others are %s: %s' % (plural(n, side), 'is' if n == 1 else 'are', FAMILY_PHRASES[bad],
                                                        FAMILY_PHRASES[expected], ranges_text(bad_rows))
        hint = ''
        if msg:
            hint = '%s at partition %s offset %s' % (msg, first['partition'], first['first_offset'])
        severity = '❌' if expected != 'string' else '⚠️'
        findings.append({'severity': severity, 'kind': 'mixed-formats', 'side': side, 'records': n,
                         'family': bad, 'expected': expected, 'message': message,
                         'hints': [h for h in [hint, 'send them to a dead letter queue (errors.tolerance=all + '
                                                     'errors.deadletterqueue.topic.name), or skip them '
                                                     '(playground connector offsets alter)'] if h]})

    # 2. schema ids not found
    if schemas.get('unreachable'):
        if sr_families:
            findings.append({'severity': '⚠️', 'kind': 'schema-registry-unreachable', 'side': side,
                             'message': 'could not read the Schema Registry, the schema ids were not checked: %s' % schemas['unreachable'],
                             'hints': []})
    else:
        missing = {}
        for r in data_rows:
            if r['family'] in ('sr', 'sr-header'):
                ref = tuple(r['schema_ref'].items())[0]
                info = schema_info(ref, schemas)
                if not info or not info.get('found'):
                    missing.setdefault(ref, []).append(r)
        for ref, mrows in missing.items():
            n = sum(r['records'] for r in mrows)
            findings.append({'severity': '❌', 'kind': 'unknown-schema-id', 'side': side, 'records': n,
                             'message': '%s (%s, %s) is not in this Schema Registry' % (ref_text(ref), plural(n, side), ranges_text(mrows)),
                             'hints': ["the converter fails with 'Error retrieving Avro schema for id %s' (or 'Schema not found'): "
                                       'the producer used another Schema Registry (a copy of the topic from another cluster, '
                                       'a different schema.registry.url), or the schema was hard deleted '
                                       '(playground schema history --subject %s-%s)' % (ref[1], topic, side)]})

        # 3. subject mismatch: ids that are not a version of <topic>-<side>
        expected_subject = '%s-%s' % (topic, side)
        foreign = {}
        for r in data_rows:
            if r['family'] in ('sr', 'sr-header'):
                ref = tuple(r['schema_ref'].items())[0]
                info = schema_info(ref, schemas)
                if info and info.get('found'):
                    subjects = [v['subject'] for v in info.get('versions') or []]
                    if expected_subject not in subjects:
                        foreign.setdefault(ref, (subjects, []))[1].append(r)
        for ref, (subjects, frows) in foreign.items():
            n = sum(r['records'] for r in frows)
            findings.append({'severity': '⚠️', 'kind': 'subject-mismatch', 'side': side, 'records': n,
                             'message': '%s (%s) is not a version of subject %s, it belongs to %s' % (
                                 ref_text(ref), plural(n, side), expected_subject, ', '.join(subjects) or 'no subject'),
                             'hints': ['the producer uses RecordNameStrategy / TopicRecordNameStrategy, or a schema of another subject: '
                                       'set %s.converter.%s.subject.name.strategy the same way, or the converter registers / '
                                       'looks up %s' % (side, side, expected_subject)]})

    # 4. a subject, but no record in the wire format
    if subject and data_rows and not sr_families:
        n = sum(r['records'] for r in data_rows)
        findings.append({'severity': '❌', 'kind': 'subject-without-wire-format', 'side': side, 'records': n,
                         'message': 'subject %s exists (%s), but the %ss are %s' % (
                             subject['subject'], TYPE_NAMES.get(subject.get('schemaType') or 'AVRO', 'Avro'), side,
                             ' and '.join(FAMILY_PHRASES[f] for f in families)),
                         'hints': ["the producer does not use the Schema Registry serializer: a sink with the %s converter "
                                   "fails with 'Unknown magic byte!'" % TYPE_NAMES.get(subject.get('schemaType') or 'AVRO', 'Avro')]})

    # 5. schema id in a header
    if 'sr-header' in families:
        findings.append({'severity': 'ℹ️', 'kind': 'schema-id-in-header', 'side': side, 'records': counts['sr-header'],
                         'message': '%s carry their schema id in the __%s_schema_id header, not in the first bytes' % (
                             plural(counts['sr-header'], side), side),
                         'hints': ["needs a converter of CP 8.1+ (its default DualSchemaIdDeserializer reads the header); "
                                   "an older converter fails with 'Unknown magic byte!'"]})

    # 6. avro container file
    if 'avro-file' in families:
        findings.append({'severity': '⚠️', 'kind': 'avro-container-file', 'side': side, 'records': counts['avro-file'],
                         'message': '%s: Avro container files (Obj\\x01 header), not Avro records' % plural(counts['avro-file'], side),
                         'hints': ['the producer wrote whole files: AvroConverter cannot read them, only ByteArrayConverter']})

    # 7. JSON envelope / no envelope
    if expected == 'json-envelope' and len(families) == 1:
        findings.append({'severity': 'ℹ️', 'kind': 'json-envelope', 'side': side,
                         'message': 'the %ss are JSON with the {"schema":…,"payload":…} envelope' % side,
                         'hints': ['%s.converter.schemas.enable=true' % side]})

    # 8. tombstones and null keys
    nulls = [r for r in rows if r['family'] == 'null']
    if nulls:
        n = sum(r['records'] for r in nulls)
        if side == 'value':
            hint = ('a JDBC sink deletes the row with delete.enabled=true and pk.mode=record_key; other sinks need '
                    'behavior.on.null.values, or a Filter on tombstones (playground connector snippets)')
            findings.append({'severity': 'ℹ️', 'kind': 'tombstones', 'side': side, 'records': n,
                             'message': '%s: %s' % (plural(n, 'tombstone'), ranges_text(nulls)), 'hints': [hint]})
        else:
            all_null = n == total_read
            findings.append({'severity': 'ℹ️', 'kind': 'null-keys', 'side': side, 'records': n,
                             'message': ('all keys are null' if all_null else '%s: %s' % (plural(n, 'null key'), ranges_text(nulls))),
                             'hints': ['a sink keyed on the record key (JDBC pk.mode=record_key, upserts, document id = key) '
                                       'cannot use them']})

    # 9. the converter to use
    converter = None
    if len(families) == 1 or (sr_families and set(families) <= {'sr', 'sr-header'}):
        refs = [tuple(r['schema_ref'].items())[0] for r in data_rows if r['schema_ref']]
        converter = converter_for(side, families, refs, schemas) if families else None
        problems = any(f['severity'] == '❌' for f in findings)
        if converter and not problems:
            findings.append({'severity': '✅', 'kind': 'converter', 'side': side,
                             'message': '%ss: all %s → %s' % (side, FAMILY_PHRASES[families[0]], converter[0].split('=', 1)[1]),
                             'hints': [], 'converter': converter})
    return findings, converter


def print_census(side, rows, samples, total_read):
    print('')
    print('   ' + side)
    families = {(r['format']) for r in rows}
    if len(families) == 1 and rows:
        print('   %-10s %-12s %-8s %s' % ('all', '', total_read, rows[0]['format'] + ('  ❌' if rows[0]['problem'] else '')))
        if samples and rows[0]['sample']:
            print_sample(rows[0]['sample'])
        return
    print('   %-10s %-12s %-8s %s' % ('partition', 'offsets', 'records', 'format'))
    for r in rows:
        offsets = '%s-%s' % (r['first_offset'], r['last_offset']) if r['first_offset'] != r['last_offset'] else str(r['first_offset'])
        problem = r['problem'] or r.get('flagged')
        print('   %-10s %-12s %-8s %s%s' % (r['partition'], offsets, r['records'], r['format'], '  ❌' if problem else ''))
        if samples and r['sample']:
            print_sample(r['sample'])


def print_sample(sample):
    print('      sample offset %s: %s' % (sample['offset'], sample['text']))
    print('      %s %s' % (' ' * len('sample offset %s:' % sample['offset']), sample['hex']))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['ids', 'report'])
    parser.add_argument('--records', required=True)
    parser.add_argument('--summary')
    parser.add_argument('--schemas')
    parser.add_argument('--subjects')
    parser.add_argument('--topic')
    parser.add_argument('--sides', default='key,value')
    parser.add_argument('--samples', action='store_true')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--status-out')
    a = parser.parse_args()

    records = load_records(a.records)
    sides = [s for s in a.sides.split(',') if s]

    if a.mode == 'ids':
        seen = set()
        for r in records:
            for side in sides:
                family, ref, _ = classify(r, side)
                if ref and ref not in seen:
                    seen.add(ref)
                    print('%s %s' % ref)
        return 0

    summary = json.loads(a.summary)
    with open(a.schemas, encoding='utf-8') as f:
        schemas = json.load(f)
    with open(a.subjects, encoding='utf-8') as f:
        subjects = json.load(f)
    total_read = len(records)
    census = build(records, sides, schemas, subjects)

    findings, converters = [], {}
    for side in sides:
        side_findings, converter = findings_for(side, census[side], schemas, subjects.get(side), a.topic, total_read)
        findings.extend(side_findings)
        if converter:
            converters[side] = converter
        # mark the ranges of a mixed side that are not in the expected format
        for f in side_findings:
            if f['kind'] == 'mixed-formats':
                for r in census[side]:
                    if r['family'] == f['family']:
                        r['flagged'] = True

    order = {'❌': 0, '⚠️': 1, 'ℹ️': 2, '✅': 3}
    findings.sort(key=lambda f: order[f['severity']])
    problems = sum(1 for f in findings if f['severity'] == '❌')
    warnings = sum(1 for f in findings if f['severity'] == '⚠️')

    if a.status_out:
        with open(a.status_out, 'w', encoding='utf-8') as f:
            json.dump({'problems': problems, 'warnings': warnings}, f)

    if a.json:
        for side in sides:
            for r in census[side]:
                r.pop('_key', None)
                r['problem'] = bool(r['problem'] or r.pop('flagged', False))
        print(json.dumps({'topic': a.topic, 'total': summary['total'], 'read': summary['read'],
                          'partitions': summary['partitions'], 'subjects': subjects, 'census': census,
                          'findings': findings, 'converters': converters, 'problems': problems,
                          'warnings': warnings}, indent=2))
        return 0

    for side in sides:
        print_census(side, census[side], a.samples, total_read)
    print('')
    for f in findings:
        pad = '  ' if f['severity'] in ('ℹ️', '⚠️') else ' '
        print('   %s%s%s' % (f['severity'], pad, f['message']))
        for h in f['hints']:
            print('      👉 %s' % h)
        if f['kind'] == 'converter':
            for line in f['converter'][1:]:
                print('      %s' % line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
