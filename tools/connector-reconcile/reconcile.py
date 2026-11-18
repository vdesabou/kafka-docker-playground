#!/usr/bin/env python3
"""Record by record comparison of the two sides of a connector, for 'playground connector reconcile'.

  --records <file>     records of the topic, one json object per line, as printed by 'playground topic consume --json'
                       (partition, offset, key, value...)
  --rows <file>        rows of the table / documents of the collection, one json object per line
  --direction          sink (the topic is the truth, the table should match it) or source (the table is the truth)
  --key-fields a,b     columns that identify a row. Empty: the fields of the record key when it is an object, else
                       no key (the records and the rows are compared as multisets of values)
  --key-source         where the key fields of a record are read: auto (record key if it is an object holding them,
                       else value), key, value, coordinates (pk.mode=kafka: __connect_topic, __connect_partition,
                       __connect_offset)
  --key-origin         where --key-fields come from, for the report
  --primitive-key-field  name of the column holding a record key that is not an object (pk.mode=record_key)
  --deletes            true: a tombstone (or a delete event of a CDC envelope) removes the row
  --ignore-fields a,b  fields never compared (columns added by the sink, by an SMT...)
  --allow-duplicates   duplicated records are reported but are not a failure (JDBC source in bulk mode)
  --topic / --table    labels
  --max-examples N     examples printed per category
  --json               one json document on stdout instead of the report

Exit code: 0 complete, 1 records lost, duplicated, different or not deleted, 2 usage / input error.

Untrusted data: records and rows are only parsed, compared and printed, never evaluated.
"""
import argparse
import base64
import datetime
import decimal
import json
import re
import sys

AVRO_UNION_TYPES = {'string', 'int', 'long', 'float', 'double', 'boolean', 'bytes', 'null', 'array', 'map'}
COORDINATE_FIELDS = ['__connect_topic', '__connect_partition', '__connect_offset']
EXTENDED_JSON = {'$oid', '$date', '$numberLong', '$numberInt', '$numberDouble', '$numberDecimal', '$uuid'}


def die(message):
    print('❌ ' + message, file=sys.stderr)
    sys.exit(2)


def read_json_lines(path, what):
    items = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for number, line in enumerate(f, 1):
            line = line.strip()
            if not line or line[0] not in '{[':
                continue
            try:
                items.append(json.loads(line, parse_float=decimal.Decimal))
            except ValueError:
                print('⚠️ %s line %d is not valid json, ignored: %s' % (what, number, line[:120]), file=sys.stderr)
    return items


def unwrap(value):
    """Avro unions as printed by the avro console consumer ({"string": "x"}, {"io.x.Record": {...}}) and MongoDB
    extended json ({"$oid": ".."}, {"$date": ".."}) become plain values."""
    if isinstance(value, dict):
        if len(value) == 1:
            (k, v), = value.items()
            if k in AVRO_UNION_TYPES or k in EXTENDED_JSON or (('.' in k) and isinstance(v, dict)):
                if k == '$date' and isinstance(v, dict):
                    v = v.get('$numberLong', v)
                return unwrap(v)
        return {k: unwrap(v) for k, v in value.items()}
    if isinstance(value, list):
        return [unwrap(v) for v in value]
    return value


def lower_keys(d):
    return {str(k).lower(): v for k, v in d.items()} if isinstance(d, dict) else d


# ---- value comparison ------------------------------------------------------------------------------------------

EPOCH = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
DATETIME_RE = re.compile(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}(:\d{2}(\.\d+)?)?)\s*(Z|[+-]\d{2}:?\d{2}|UTC)?$')
ORACLE_DATE_RE = re.compile(r'^\d{2}-[A-Z]{3}-\d{2,4}')


def as_number(v):
    if isinstance(v, bool):
        return decimal.Decimal(int(v))
    if isinstance(v, (int, decimal.Decimal)):
        return decimal.Decimal(v)
    if isinstance(v, float):
        return decimal.Decimal(repr(v))
    if isinstance(v, str):
        s = v.strip()
        if s.lower() in ('true', 'false'):
            return decimal.Decimal(1 if s.lower() == 'true' else 0)
        try:
            return decimal.Decimal(s)
        except decimal.InvalidOperation:
            return None
    return None


def as_epoch_nanos(v):
    """A date / timestamp string as epoch nanoseconds (UTC when there is no offset), None when it is not one."""
    if not isinstance(v, str):
        return None
    s = v.strip()
    if DATE_RE.match(s):
        try:
            d = datetime.datetime.strptime(s, '%Y-%m-%d').replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            return None
        return int((d - EPOCH).total_seconds()) * 10 ** 9
    m = DATETIME_RE.match(s)
    if not m:
        return None
    date, time, _, fraction, zone = m.groups()
    base = time.split('.')[0]
    if base.count(':') == 1:
        base += ':00'
    try:
        d = datetime.datetime.strptime(date + ' ' + base, '%Y-%m-%d %H:%M:%S')
    except ValueError:
        return None
    if zone in (None, 'Z', 'UTC'):
        d = d.replace(tzinfo=datetime.timezone.utc)
    else:
        zone = zone.replace(':', '')
        sign = 1 if zone[0] == '+' else -1
        offset = datetime.timedelta(hours=int(zone[1:3]), minutes=int(zone[3:5]))
        d = d.replace(tzinfo=datetime.timezone(sign * offset))
    nanos = int((d - EPOCH).total_seconds()) * 10 ** 9
    if fraction:
        nanos += int((fraction[1:] + '000000000')[:9])
    return nanos


def fraction_digits(v):
    m = DATETIME_RE.match(v.strip())
    return len(m.group(4)) - 1 if m and m.group(4) else 0


def as_epoch_millis(v):
    n = as_epoch_nanos(v)
    return None if n is None else n // 10 ** 6


def epoch_number_matches(n, nanos, text):
    """an epoch number (millis, micros or nanos, possibly truncated) or a number of days (Connect Date) against the
    nanoseconds of a date / timestamp string"""
    for scale in (10 ** 6, 10 ** 3, 1):
        if n == nanos // scale and (n * scale == nanos or len(str(abs(n))) >= 12):
            return True
    if DATE_RE.match(text.strip()) and n * 86400 * 10 ** 9 == nanos:
        return True
    # time of day in millis (Connect Time) against a full timestamp
    if 0 <= n < 86400000 and (nanos // 10 ** 6) % 86400000 == n:
        return True
    return False


def same(a, b):
    """True when a record value and a column value mean the same thing, across the representations the converters and
    the databases use: 1 / 1.0 / "1", true / 1, epoch millis or days / date strings, json text / object, CHAR
    padding, base64 bytes."""
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, (dict, list)) or isinstance(b, (dict, list)):
        if isinstance(a, str):
            a = parse_json_text(a)
        if isinstance(b, str):
            b = parse_json_text(b)
        if isinstance(a, dict) and isinstance(b, dict):
            a, b = lower_keys(a), lower_keys(b)
            return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
        if isinstance(a, list) and isinstance(b, list):
            return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
        return False
    if isinstance(a, str) and isinstance(b, str):
        if a.rstrip() == b.rstrip():
            return True
        ta, tb = as_epoch_nanos(a), as_epoch_nanos(b)
        if ta is not None and tb is not None:
            # the less precise side decides: 2026-11-18 15:43:39.913 and 15:43:39.913254
            scale = 10 ** (9 - min(fraction_digits(a), fraction_digits(b), 9))
            return ta // scale == tb // scale
        na, nb = as_number(a), as_number(b)
        if na is not None and nb is not None:
            return numbers_equal(na, nb)
        return base64_text(a) == b or base64_text(b) == a
    # one side is a number or a boolean
    na, nb = as_number(a), as_number(b)
    if na is not None and nb is not None:
        return numbers_equal(na, nb)
    for number, text in ((a, b), (b, a)):
        if isinstance(number, (int, decimal.Decimal)) and not isinstance(number, bool) and isinstance(text, str):
            t = as_epoch_nanos(text)
            if t is not None and epoch_number_matches(int(number), t, text):
                return True
    return False


def numbers_equal(a, b):
    """Exact for integers; 6 significant digits otherwise, what a float (real) column keeps of a double"""
    if a == b:
        return True
    if a == a.to_integral_value() and b == b.to_integral_value():
        return False
    return significant(a) == significant(b)


def significant(n):
    return plain(decimal.Decimal('%.6g' % n))


def parse_json_text(s):
    try:
        return json.loads(s, parse_float=decimal.Decimal)
    except ValueError:
        return s


def base64_text(s):
    try:
        return base64.b64decode(s, validate=True).decode('utf-8')
    except Exception:
        return None


def display(v):
    if isinstance(v, decimal.Decimal):
        return str(v)
    if isinstance(v, (dict, list)):
        return json.dumps(v, default=str, ensure_ascii=False)
    return json.dumps(v, default=str, ensure_ascii=False)


def short(v, width=60):
    s = display(v)
    return s if len(s) <= width else s[:width - 1] + '…'


# ---- records ---------------------------------------------------------------------------------------------------

class Record(object):
    __slots__ = ('partition', 'offset', 'key', 'fields', 'deleted', 'raw_value', 'topic')

    def __init__(self, raw, args):
        self.topic = raw.get('topic', args.topic)
        self.partition = raw.get('partition')
        self.offset = raw.get('offset')
        key = unwrap(raw.get('key'))
        value = unwrap(raw.get('value'))
        self.raw_value = value
        self.deleted = False
        # JsonConverter with schemas.enable: {"schema": .., "payload": ..}
        for side in ('key', 'value'):
            v = key if side == 'key' else value
            if isinstance(v, dict) and set(v.keys()) == {'schema', 'payload'}:
                v = v['payload']
                if side == 'key':
                    key = v
                else:
                    value = v
        # CDC envelope (Debezium, Oracle CDC): {"before", "after", "op"}: the row is "after", a "d" is a delete
        if isinstance(value, dict) and 'op' in value and ('after' in value or 'before' in value):
            if value.get('op') == 'd' or value.get('after') is None:
                self.deleted = True
                value = None
            else:
                value = value.get('after')
        if value is None:
            self.deleted = True
        elif isinstance(value, dict):
            # ExtractNewRecordState with delete.handling.mode=rewrite
            if str(value.get('__deleted', '')).lower() == 'true' or value.get('__op') == 'd':
                self.deleted = True
        self.key = key
        if isinstance(value, dict):
            fields = dict(value)
        elif value is None:
            fields = {}
        else:
            fields = {'value': value}
        if args.key_source in ('auto', 'key'):
            if isinstance(key, dict):
                for k, v in key.items():
                    fields.setdefault(k, v)
            elif key is not None and args.primitive_key_field:
                fields.setdefault(args.primitive_key_field, key)
        if args.key_source == 'coordinates':
            fields.update({'__connect_topic': self.topic, '__connect_partition': self.partition,
                           '__connect_offset': self.offset})
        self.fields = lower_keys(fields)

    def where(self):
        return 'p%s@%s' % (self.partition, self.offset)


def key_of(fields, key_fields):
    values = []
    for k in key_fields:
        if k not in fields:
            return None
        v = fields[k]
        n = as_number(v) if not isinstance(v, str) or re.match(r'^-?\d+(\.\d+)?$', v.strip()) else None
        values.append(plain(n) if n is not None else (v.rstrip() if isinstance(v, str) else display(v)))
    return tuple(values)


def plain(n):
    """1, 1.0, 1E+3 and 1000.00 all print the same way"""
    s = format(n.normalize(), 'f')
    return s[:-2] if s.endswith('.0') else s


def key_label(key):
    return ', '.join(key) if len(key) > 1 else key[0]


def compare_fields(expected, actual, ignore):
    """(differences, fields only in expected, fields only in actual)"""
    differences = []
    common = [k for k in expected if k in actual and k not in ignore]
    for k in common:
        if not same(expected[k], actual[k]):
            differences.append((k, expected[k], actual[k]))
    only_expected = [k for k in expected if k not in actual and k not in ignore]
    only_actual = [k for k in actual if k not in expected and k not in ignore]
    return differences, only_expected, only_actual


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--records', required=True)
    p.add_argument('--rows', required=True)
    p.add_argument('--direction', choices=['sink', 'source'], required=True)
    p.add_argument('--key-fields', default='')
    p.add_argument('--key-source', choices=['auto', 'key', 'value', 'coordinates'], default='auto')
    p.add_argument('--primitive-key-field', default='')
    p.add_argument('--key-origin', default='given')
    p.add_argument('--deletes', default='true')
    p.add_argument('--ignore-fields', default='')
    p.add_argument('--allow-duplicates', action='store_true')
    p.add_argument('--topic', default='topic')
    p.add_argument('--table', default='table')
    p.add_argument('--table-kind', default='table', help='table, collection or rows (--rows-file), for the report')
    p.add_argument('--max-examples', type=int, default=10)
    p.add_argument('--json', action='store_true')
    args = p.parse_args()
    args.primitive_key_field = args.primitive_key_field.lower()
    deletes = args.deletes.lower() == 'true'
    ignore = set(f.strip().lower() for f in args.ignore_fields.split(',') if f.strip())

    records = [Record(r, args) for r in read_json_lines(args.records, 'topic')]
    rows = [lower_keys(unwrap(r)) for r in read_json_lines(args.rows, 'table')]

    key_fields = [f.strip().lower() for f in args.key_fields.split(',') if f.strip()]
    key_origin = args.key_origin
    if args.key_source == 'coordinates':
        key_fields = list(COORDINATE_FIELDS)
        key_origin = 'kafka coordinates (pk.mode=kafka)'
    if not key_fields:
        sample = next((r.key for r in records if isinstance(r.key, dict)), None)
        if sample:
            key_fields = [str(k).lower() for k in sample.keys()]
            key_origin = 'fields of the record key'
        elif args.primitive_key_field:
            key_fields = [args.primitive_key_field]
            key_origin = 'record key'

    result = {
        'direction': args.direction, 'topic': args.topic, 'table': args.table,
        'key_fields': key_fields, 'key_origin': key_origin if key_fields else 'none',
        'records': len(records), 'rows': len(rows),
    }

    if key_fields:
        report = compare_by_key(records, rows, key_fields, deletes, ignore, args)
    else:
        report = compare_as_multisets(records, rows, ignore, args)
    result.update(report)

    failures = [c for c in ('lost', 'different', 'not_deleted') if result.get(c)]
    if result.get('duplicated') and not args.allow_duplicates:
        failures.append('duplicated')
    result['verdict'] = ','.join(failures) if failures else 'complete'

    if args.json:
        print(json.dumps(result, default=str, ensure_ascii=False))
    else:
        print_report(result, args)
    sys.exit(1 if failures else 0)


def compare_by_key(records, rows, key_fields, deletes, ignore, args):
    out = {'lost': [], 'extra': [], 'different': [], 'duplicated': [], 'not_deleted': [], 'deleted_ok': 0,
           'no_key_records': 0, 'no_key_rows': 0, 'matching': 0, 'only_in_topic_fields': {}, 'only_in_table_fields': {}}

    # last record of each key (offset order inside a partition; a key lives in one partition)
    last = {}
    occurrences = {}
    for r in records:
        if r.deleted and not deletes and args.direction == 'sink':
            continue
        if r.deleted and not r.fields:
            # tombstone: the key comes from the record key only
            fields = {}
            if isinstance(r.key, dict):
                fields = lower_keys(r.key)
            elif r.key is not None and args.primitive_key_field:
                fields = {args.primitive_key_field: r.key}
            if args.key_source == 'coordinates':
                fields = {}
            k = key_of(fields, key_fields)
        else:
            k = key_of(r.fields, key_fields)
        if k is None:
            out['no_key_records'] += 1
            continue
        last[k] = r
        if not r.deleted:
            signature = json.dumps({f: display(v) for f, v in r.fields.items()}, sort_keys=True)
            occurrences.setdefault((k, signature), []).append(r)

    table = {}
    for row in rows:
        k = key_of(row, key_fields)
        if k is None:
            out['no_key_rows'] += 1
            continue
        table.setdefault(k, []).append(row)

    for k, found in table.items():
        if len(found) > 1:
            out['duplicated'].append({'key': key_label(k), 'side': 'table', 'count': len(found)})

    for (k, _), found in occurrences.items():
        if len(found) > 1 and args.direction == 'source':
            out['duplicated'].append({'key': key_label(k), 'side': 'topic', 'count': len(found),
                                      'records': [r.where() for r in found[:5]]})

    for k, r in last.items():
        found = table.get(k)
        if r.deleted:
            if found:
                out['not_deleted'].append({'key': key_label(k), 'record': r.where()})
            else:
                out['deleted_ok'] += 1
            continue
        if not found:
            if args.direction == 'sink':
                out['lost'].append({'key': key_label(k), 'record': r.where()})
            else:
                out['extra'].append({'key': key_label(k), 'record': r.where(),
                                     'why': 'in the topic, not in the table'})
            continue
        differences, only_expected, only_actual = compare_fields(r.fields, found[-1], ignore)
        for f in only_expected:
            out['only_in_topic_fields'][f] = out['only_in_topic_fields'].get(f, 0) + 1
        for f in only_actual:
            out['only_in_table_fields'][f] = out['only_in_table_fields'].get(f, 0) + 1
        if differences:
            out['different'].append({'key': key_label(k), 'record': r.where(),
                                     'fields': [{'field': f, 'topic': display(a), 'table': display(b)}
                                                for f, a, b in differences]})
        else:
            out['matching'] += 1

    for k in table:
        if k not in last:
            if args.direction == 'source':
                out['lost'].append({'key': key_label(k), 'record': None})
            else:
                out['extra'].append({'key': key_label(k), 'record': None, 'why': 'in the table, not in the topic'})

    out['keys_in_topic'] = len(last)
    out['keys_in_table'] = len(table)
    for c in ('lost', 'extra', 'different', 'duplicated', 'not_deleted'):
        out[c].sort(key=lambda e: e['key'])
    return out


def compare_as_multisets(records, rows, ignore, args):
    """No key: count each distinct value on both sides."""
    out = {'lost': [], 'extra': [], 'different': [], 'duplicated': [], 'not_deleted': [], 'matching': 0,
           'only_in_topic_fields': {}, 'only_in_table_fields': {}}
    live = [r for r in records if not r.deleted]
    common = None
    if live and rows:
        common = set(live[0].fields.keys()) & set(rows[0].keys())
        common -= ignore
    if not common:
        out['error'] = ('no key and no common field between the records and the rows: pass --key-field')
        return out
    common = sorted(common)

    def signature(d):
        return tuple(normalized(d.get(f)) for f in common)

    topic_counts, table_counts, where = {}, {}, {}
    for r in live:
        s = signature(r.fields)
        topic_counts[s] = topic_counts.get(s, 0) + 1
        where.setdefault(s, r.where())
    for row in rows:
        s = signature(row)
        table_counts[s] = table_counts.get(s, 0) + 1
    for s in set(topic_counts) | set(table_counts):
        t, d = topic_counts.get(s, 0), table_counts.get(s, 0)
        label = ', '.join('%s=%s' % (f, short(v, 30)) for f, v in zip(common, s))
        out['matching'] += min(t, d)
        expected, actual = (t, d) if args.direction == 'sink' else (d, t)
        if actual < expected:
            out['lost'].append({'what': 'record', 'key': label, 'record': where.get(s), 'count': expected - actual})
        elif actual > expected:
            if expected > 0:
                out['duplicated'].append({'what': 'record', 'key': label, 'side': 'table' if args.direction == 'sink' else 'topic',
                                          'count': actual})
            else:
                out['extra'].append({'what': 'record', 'key': label, 'record': where.get(s), 'why': 'only on one side',
                                     'count': actual})
    out['compared_fields'] = common
    for c in ('lost', 'extra', 'duplicated'):
        out[c].sort(key=lambda e: e['key'])
    return out


def normalized(v):
    n = as_number(v) if not isinstance(v, str) else None
    if n is not None:
        return plain(n) if n == n.to_integral_value() else significant(n)
    if isinstance(v, str):
        t = as_epoch_millis(v)
        if t is not None:
            return str(t)
        n = as_number(v)
        if n is not None:
            return plain(n) if n == n.to_integral_value() else significant(n)
        return v.rstrip()
    return display(v)


def with_date(value, other):
    """an epoch in milliseconds compared with a date column, with its date: 1763485200000 (2025-11-18 17:00:00 UTC)"""
    text = short(value)
    n = as_number(value) if isinstance(value, (int, decimal.Decimal)) and not isinstance(value, bool) else None
    if n is not None and isinstance(other, str) and as_epoch_millis(other) is not None and abs(n) < 10 ** 14:
        d = EPOCH + datetime.timedelta(milliseconds=int(n))
        text += ' (%s UTC)' % d.strftime('%Y-%m-%d %H:%M:%S')
    return text


def print_report(r, args):
    sink = r['direction'] == 'sink'
    kind = args.table_kind
    truth, other = ('topic ' + r['topic'], kind + ' ' + r['table']) if sink else (kind + ' ' + r['table'], 'topic ' + r['topic'])
    print('🔎 %s connector: is every record of the %s in the %s?' % ('Sink' if sink else 'Source', truth, other))
    print('')
    print('   📥 %-36s %d record(s)%s' % ('topic ' + r['topic'], r['records'],
                                                 (', %d key(s)' % r['keys_in_topic']) if 'keys_in_topic' in r else ''))
    print('   🛢️  %-36s %d row(s)%s' % (kind + ' ' + r['table'], r['rows'],
                                                (', %d key(s)' % r['keys_in_table']) if 'keys_in_table' in r else ''))
    if r['key_fields']:
        print('   🔑 key: %s (%s)' % (', '.join(r['key_fields']), r['key_origin']))
    else:
        print('   🔑 no key: records and rows compared as multisets of (%s)' % ', '.join(r.get('compared_fields', [])))
    print('')
    if r.get('error'):
        print('❌ ' + r['error'])
        return
    n = args.max_examples

    def section(title, items, fmt):
        if not items:
            return
        print('%s: %d' % (title, len(items)))
        for e in items[:n]:
            print('   ' + fmt(e))
        if len(items) > n:
            print('   … %d more (--max-examples, or --json for all of them)' % (len(items) - n))
        print('')

    lost_title = '❌ Lost, in the %s but not in the %s' % (truth.split()[0], other.split()[0])
    section(lost_title, r['lost'], lambda e: '%s %s%s%s' % (
        e.get('what', 'key'), e['key'], (' (record %s)' % e['record']) if e.get('record') else '',
        (' x%d' % e['count']) if e.get('count', 1) > 1 else ''))
    section('❌ Not deleted, the last record is a tombstone or a delete event but the row is still there',
            r['not_deleted'], lambda e: 'key %s (record %s)' % (e['key'], e['record']))
    section('❌ Duplicated', r['duplicated'], lambda e: '%s %s: %d times in the %s%s' % (
        e.get('what', 'key'), e['key'], e['count'], e['side'], (' (%s)' % ', '.join(e['records'])) if e.get('records') else ''))

    def fmt_diff(e):
        parts = ['%s: topic %s, table %s' % (f['field'], with_date(parse_json_text(f['topic']), parse_json_text(f['table'])),
                                             short(parse_json_text(f['table']))) for f in e['fields'][:4]]
        more = ' (+%d fields)' % (len(e['fields']) - 4) if len(e['fields']) > 4 else ''
        return 'key %s (record %s): %s%s' % (e['key'], e['record'], '; '.join(parts), more)
    section('❌ Different, the row does not match the last record of its key', r['different'], fmt_diff)
    extra_title = ('⚠️ Extra, only in the ' + kind + ': written before, or by another client (not a failure)' if sink else
                   '⚠️ Extra, only in the topic: deleted from the table without a delete event, or filtered (not a failure)')
    section(extra_title, r['extra'],
            lambda e: '%s %s%s%s' % (e.get('what', 'key'), e['key'], (' (record %s)' % e['record']) if e.get('record') else '',
                                     (' x%d' % e['count']) if e.get('count', 1) > 1 else ''))

    if r.get('only_in_topic_fields'):
        print('ℹ️ fields of the records with no column of the same name (not compared): %s' %
              ', '.join(sorted(r['only_in_topic_fields'])))
    if r.get('only_in_table_fields'):
        print('ℹ️ columns with no field of the same name in the records (not compared): %s' %
              ', '.join(sorted(r['only_in_table_fields'])))
    if r.get('no_key_records'):
        print('⚠️ %d record(s) without the key field(s) %s, not compared' % (r['no_key_records'], ', '.join(r['key_fields'])))
    if r.get('no_key_rows'):
        print('⚠️ %d row(s) without the key column(s) %s, not compared' % (r['no_key_rows'], ', '.join(r['key_fields'])))
    if r.get('deleted_ok'):
        print('🗑️ %d key(s) deleted on both sides' % r['deleted_ok'])
    print('✅ %d matching' % r['matching'])
    print('')
    verdicts = {
        'complete': '✅ complete: every record is on the other side, with the same values',
        'lost': '❌ lost: records of the %s are missing in the %s' % (truth.split()[0], other.split()[0]),
        'different': '❌ different: rows do not match the last record of their key (converter, SMT, column type?)',
        'not_deleted': '❌ not deleted: tombstones / delete events were not applied',
        'duplicated': '❌ duplicated: the same record is there several times',
    }
    for v in r['verdict'].split(','):
        print(verdicts[v])


if __name__ == '__main__':
    main()
