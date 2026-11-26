#!/usr/bin/env python3
"""Listing and decoding of the objects written by an object store sink connector, for 'playground storage'.

  select  --listing <rclone lsjson file> [--topic t] [--include regex] [--max-objects N] [--newest]
          --selected <file>         objects kept (one path per line, in topic / partition / offset order)
          [--report table|json|count] [--label text]
  decode  --dir <folder with the downloaded objects> --selected <file> [--output records|objects|summary|json]

The object names of the Confluent storage sinks are <topic>+<partition>+<start offset>.<format> (S3, GCS, Azure Blob,
ADLS, SFTP) and <topic>+<partition>+<start offset>+<end offset>.<format> (HDFS): they give the topic, the partition
and the first offset of each object. Avro and Parquet objects are converted to json lines (<object>.jsonl) by the
caller before 'decode'.

Untrusted data: objects are only parsed and printed, never evaluated.
"""
import argparse
import csv
import datetime
import gzip
import io
import json
import os
import re
import sys

NAME_RE = re.compile(r'^(?P<topic>.+)\+(?P<partition>\d+)\+(?P<start>\d+)(?:\+(?P<end>\d+))?\.(?P<ext>[A-Za-z0-9.]+)$')


def parse_name(path):
    base = path.rsplit('/', 1)[-1]
    m = NAME_RE.match(base)
    if not m:
        return None
    return {
        'topic': m.group('topic'), 'partition': int(m.group('partition')), 'start': int(m.group('start')),
        'end': int(m.group('end')) if m.group('end') is not None else None, 'ext': m.group('ext').lower(),
    }


def topic_root(path, topic):
    """the folder before the topic folder (topics.dir when the bucket root is listed): objects of the same
    topic-partition under two roots come from two connectors / runs, while the folders after the topic (partition=0/,
    year=2026/month=11/... of a time based partitioner) belong to the same partition"""
    p = '/' + path
    i = p.find('/%s/' % topic)
    return p[1:i] if i > 0 else ''


def group_label(root, topic, partition, roots_of):
    label = '%s-%d' % (topic, partition)
    if len(roots_of.get((topic, partition), ())) > 1:
        label += ' (%s/)' % (root or '.')
    return label


def object_format(path):
    p = path.lower()
    for suffix, fmt in (('.avro', 'avro'), ('.parquet', 'parquet'), ('.snappy.parquet', 'parquet'),
                        ('.json.gz', 'json'), ('.json', 'json'), ('.jsonl', 'json'), ('.csv.gz', 'csv'),
                        ('.csv', 'csv'), ('.txt', 'text'), ('.bin', 'bytes'), ('.orc', 'orc')):
        if p.endswith(suffix):
            return fmt
    return 'other'


def sort_key(obj):
    n = obj.get('name_info')
    if n:
        return (0, topic_root(obj['Path'], n['topic']), n['topic'], n['partition'], n['start'], obj['Path'])
    return (1, '', '', 0, 0, obj['Path'])


def human_size(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if n < 1024 or unit == 'GB':
            return ('%d %s' % (n, unit)) if unit == 'B' else ('%.1f %s' % (n, unit))
        n /= 1024.0


def short_time(t):
    # 2026-11-26T10:12:13.123456789Z -> 2026-11-26 10:12:13
    if not t:
        return ''
    return t[:19].replace('T', ' ')


def load_listing(path):
    with open(path, encoding='utf-8') as f:
        text = f.read().strip() or '[]'
    data = json.loads(text)
    out = []
    for o in data:
        if o.get('IsDir'):
            continue
        o['name_info'] = parse_name(o['Path'])
        out.append(o)
    return out


def select(args):
    objects = load_listing(args.listing)
    total = len(objects)
    if args.topic:
        topics = set(t.strip() for t in args.topic.split(',') if t.strip())
        objects = [o for o in objects
                   if (o['name_info'] and o['name_info']['topic'] in topics)
                   or any(('/%s/' % t) in ('/' + o['Path']) for t in topics)]
    if args.include:
        rx = re.compile(args.include)
        objects = [o for o in objects if rx.search(o['Path'])]
    # temporary files of the sinks (S3 multipart uploads are not listed; HDFS writes +tmp folders)
    objects = [o for o in objects if '/+tmp/' not in ('/' + o['Path'])]
    objects.sort(key=sort_key)
    matched = len(objects)
    all_matched = list(objects)
    if args.newest and args.max_objects and matched > args.max_objects:
        objects = sorted(objects, key=lambda o: o.get('ModTime', ''))[-args.max_objects:]
        objects.sort(key=sort_key)
    elif args.max_objects and matched > args.max_objects:
        objects = objects[:args.max_objects]
    if args.selected:
        with open(args.selected, 'w', encoding='utf-8') as f:
            for o in objects:
                f.write(o['Path'] + '\n')

    if args.report == 'count':
        print(matched)
        return 0
    partitions = {}
    for o in all_matched:
        n = o['name_info']
        if not n:
            continue
        p = partitions.setdefault((topic_root(o['Path'], n['topic']), n['topic'], n['partition']), {'objects': 0, 'bytes': 0, 'first_offset': None,
                                                                 'last_start_offset': None, 'last_modified': ''})
        p['objects'] += 1
        p['bytes'] += o.get('Size', 0)
        p['first_offset'] = n['start'] if p['first_offset'] is None else min(p['first_offset'], n['start'])
        p['last_start_offset'] = n['start'] if p['last_start_offset'] is None else max(p['last_start_offset'], n['start'])
        p['last_modified'] = max(p['last_modified'], o.get('ModTime', ''))
    if args.report == 'json':
        print(json.dumps({
            'location': args.label, 'objects_total': total, 'objects_matched': matched, 'objects_shown': len(objects),
            'objects': [{'path': o['Path'], 'size': o.get('Size', 0), 'modified': o.get('ModTime', ''),
                         'format': object_format(o['Path']),
                         'topic': (o['name_info'] or {}).get('topic'),
                         'partition': (o['name_info'] or {}).get('partition'),
                         'start_offset': (o['name_info'] or {}).get('start'),
                         'end_offset': (o['name_info'] or {}).get('end')} for o in objects],
            'partitions': [dict(root=k[0], topic=k[1], partition=k[2], **v) for k, v in sorted(partitions.items())],
        }, indent=2))
        return 0

    if not objects:
        print('🫙 no object%s under %s (%d object(s) in total)' % (
            (' for topic ' + args.topic) if args.topic else '', args.label, total))
        return 0
    width = min(max(len(o['Path']) for o in objects), 90)
    print('%-*s  %10s  %-19s' % (width, 'object', 'size', 'modified'))
    for o in objects:
        path = o['Path']
        if len(path) > width:
            path = '…' + path[-(width - 1):]
        print('%-*s  %10s  %-19s' % (width, path, human_size(o.get('Size', 0)), short_time(o.get('ModTime'))))
    if matched > len(objects):
        print('… %d more object(s) not shown (--max-objects %d)' % (matched - len(objects), args.max_objects))
    roots_of = {}
    for (root, topic, part) in partitions:
        roots_of.setdefault((topic, part), set()).add(root)
    if partitions:
        print()
        print('%-40s %9s %8s %10s %12s  %-19s' % ('topic-partition', 'objects', 'size', 'first off.', 'last start', 'last modified'))
        for (root, topic, part), p in sorted(partitions.items()):
            print('%-40s %9d %8s %10d %12d  %-19s' % (group_label(root, topic, part, roots_of), p['objects'], human_size(p['bytes']),
                                                     p['first_offset'], p['last_start_offset'],
                                                     short_time(p['last_modified'])))
    print()
    print('🪣 %d object(s)%s, %s' % (matched, (' of %d' % total) if matched != total else '',
                                     human_size(sum(o.get('Size', 0) for o in all_matched))))
    return 0


# ---- decode -----------------------------------------------------------------------------------------------------

AVRO_UNION_TYPES = {'null', 'boolean', 'int', 'long', 'float', 'double', 'bytes', 'string', 'array', 'map'}


def unwrap_avro(value):
    """avro-tools prints a union value as {"<type>": value}: keep the value only"""
    if isinstance(value, dict):
        if len(value) == 1:
            (k, v), = value.items()
            if k in AVRO_UNION_TYPES or ('.' in k and isinstance(v, dict)):
                return unwrap_avro(v)
        return {k: unwrap_avro(v) for k, v in value.items()}
    if isinstance(value, list):
        return [unwrap_avro(v) for v in value]
    return value


def read_records(folder, path):
    """records of one object, as python values, and the format"""
    fmt = object_format(path)
    full = os.path.join(folder, path)
    if fmt in ('avro', 'parquet'):
        converted = full + '.jsonl'
        if not os.path.exists(converted):
            return fmt, None, 'not converted (see the error above)'
        records = []
        with open(converted, encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    return fmt, records, 'unreadable line: %s' % line[:120]
                records.append(unwrap_avro(record) if fmt == 'avro' else record)
        return fmt, records, None
    if not os.path.exists(full):
        return fmt, None, 'not downloaded'
    with open(full, 'rb') as f:
        data = f.read()
    if path.lower().endswith('.gz'):
        try:
            data = gzip.decompress(data)
        except OSError as e:
            return fmt, None, 'not gzip: %s' % e
    text = data.decode('utf-8', errors='replace')
    if fmt == 'json':
        records = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except ValueError:
                records.append(line)
        return fmt, records, None
    if fmt == 'csv':
        rows = list(csv.reader(io.StringIO(text)))
        return fmt, rows, None
    if fmt in ('text', 'other'):
        return fmt, [l for l in text.splitlines() if l != ''], None
    if fmt == 'bytes':
        # ByteArrayFormat: records separated by format.bytearray.separator (a line separator by default)
        return fmt, [l for l in text.splitlines() if l != ''], None
    return fmt, None, 'format %s is not decoded' % fmt


def decode(args):
    with open(args.selected, encoding='utf-8') as f:
        paths = [l.rstrip('\n') for l in f if l.strip()]
    results = []
    for path in paths:
        fmt, records, error = read_records(args.dir, path)
        results.append({'path': path, 'format': fmt, 'records': records, 'error': error, 'name_info': parse_name(path)})

    if args.output == 'records':
        # one json line per record: what 'connector reconcile' reads
        for r in results:
            for rec in r['records'] or []:
                print(json.dumps(rec, ensure_ascii=False))
            if r['error']:
                print('⚠️ %s: %s' % (r['path'], r['error']), file=sys.stderr)
        return 0 if not any(r['error'] for r in results) else 1

    summary = offsets_summary(results)
    if args.output == 'json':
        print(json.dumps({
            'objects': [{'path': r['path'], 'format': r['format'], 'error': r['error'],
                         'records': r['records'] if r['records'] is not None else [],
                         'record_count': len(r['records']) if r['records'] is not None else None} for r in results],
            'partitions': summary,
        }, indent=2, ensure_ascii=False))
        return 0 if not any(r['error'] for r in results) else 1

    if args.output == 'objects':
        for r in results:
            n = len(r['records']) if r['records'] is not None else 0
            print('📄 %s (%s, %d record(s))' % (r['path'], r['format'], n))
            if r['error']:
                print('   ⚠️ %s' % r['error'])
            for rec in r['records'] or []:
                if isinstance(rec, (dict, list)):
                    print('   ' + json.dumps(rec, ensure_ascii=False))
                else:
                    print('   ' + str(rec))
        print()

    print_summary(results, summary)
    return 0 if not any(r['error'] for r in results) else 1


def offsets_summary(results):
    """per topic-partition: the offsets covered by the objects (start offset of the name + number of records), with
    the gaps and the overlaps between consecutive objects"""
    parts = {}
    for r in results:
        n = r['name_info']
        if not n or r['records'] is None:
            continue
        parts.setdefault((topic_root(r['path'], n['topic']), n['topic'], n['partition']), []).append(
            (n['start'], len(r['records']), r['path'], n['end']))
    roots_of = {}
    for (root, topic, part) in parts:
        roots_of.setdefault((topic, part), set()).add(root)
    out = []
    for (root, topic, part), objs in sorted(parts.items()):
        objs.sort()
        gaps, overlaps = [], []
        for (s1, c1, p1, e1), (s2, c2, p2, e2) in zip(objs, objs[1:]):
            end1 = s1 + c1  # first offset after object 1 (compacted topics or skipped tombstones can leave holes)
            if s2 > end1:
                gaps.append({'from': end1, 'to': s2 - 1, 'after': p1, 'before': p2})
            elif s2 < end1:
                overlaps.append({'from': s2, 'to': min(end1, s2 + c2) - 1, 'object': p1, 'object2': p2})
        first = objs[0][0]
        last = objs[-1][0] + objs[-1][1] - 1
        out.append({'root': root, 'label': group_label(root, topic, part, roots_of), 'topic': topic, 'partition': part,
                    'objects': len(objs),
                    'records': sum(c for _, c, _, _ in objs), 'first_offset': first, 'last_offset': last,
                    'gaps': gaps, 'overlaps': overlaps})
    return out


def offset_range(a, b):
    return ('offset %d is' % a) if a == b else ('offsets %d-%d are' % (a, b))


def print_summary(results, summary):
    total = sum(len(r['records']) for r in results if r['records'] is not None)
    errors = [r for r in results if r['error']]
    if summary:
        print('%-40s %8s %9s %22s  %s' % ('topic-partition', 'objects', 'records', 'offsets', 'continuity'))
        for p in summary:
            if p['overlaps']:
                state = '🔁 %d overlap(s)' % len(p['overlaps'])
            elif p['gaps']:
                state = '🕳️ %d gap(s)' % len(p['gaps'])
            else:
                state = '✅ contiguous'
            if p['overlaps'] and p['gaps']:
                state += ', 🕳️ %d gap(s)' % len(p['gaps'])
            print('%-40s %8d %9d %22s  %s' % (p['label'], p['objects'], p['records'],
                                              '%d → %d' % (p['first_offset'], p['last_offset']), state))
        for p in summary:
            for g in p['gaps'][:5]:
                print('   🕳️ %s: %s in no object (between %s and %s)' % (
                    p['label'], offset_range(g['from'], g['to']), g['after'].rsplit('/', 1)[-1],
                    g['before'].rsplit('/', 1)[-1]))
            for o in p['overlaps'][:5]:
                print('   🔁 %s: %s in two objects (%s and %s): duplicates' % (
                    p['label'], offset_range(o['from'], o['to']), o['object'].rsplit('/', 1)[-1],
                    o['object2'].rsplit('/', 1)[-1]))
        if any(p['gaps'] for p in summary):
            print('   🎓 a gap is expected on a compacted topic, with transactions (markers use offsets), after a'
                  ' retention deletion, or when an SMT / errors.tolerance dropped records')
    for r in errors:
        print('⚠️ %s: %s' % (r['path'], r['error']))
    print('📦 %d record(s) in %d object(s)' % (total, len(results) - len(errors)))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('select')
    s.add_argument('--listing', required=True)
    s.add_argument('--selected')
    s.add_argument('--topic', default='')
    s.add_argument('--include', default='')
    s.add_argument('--max-objects', type=int, default=0)
    s.add_argument('--newest', action='store_true')
    s.add_argument('--report', choices=['table', 'json', 'count', 'none'], default='table')
    s.add_argument('--label', default='')
    d = sub.add_parser('decode')
    d.add_argument('--dir', required=True)
    d.add_argument('--selected', required=True)
    d.add_argument('--output', choices=['records', 'objects', 'summary', 'json'], default='objects')
    args = p.parse_args()
    if args.cmd == 'select':
        if args.report == 'none':
            args.report = 'count'
            with open(os.devnull, 'w') as devnull:
                old = sys.stdout
                sys.stdout = devnull
                try:
                    return select(args)
                finally:
                    sys.stdout = old
        return select(args)
    return decode(args)


if __name__ == '__main__':
    sys.exit(main())
