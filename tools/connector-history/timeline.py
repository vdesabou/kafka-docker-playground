#!/usr/bin/env python3
"""Session log and merged timeline of a connector, for 'playground history --session' and
'playground connector history --with-logs'.

  session --file playground-session.log [--json]
        the playground commands that changed the environment since it started
  merge   --history <connector history --json> --timeline <analyze logs --json --json-sections timeline>
          --session playground-session.log [--connector c] [--since-ms N] [--json]
        one time-ordered list per connector: 📋 states and configs from the internal topics, 📜 the incident timeline of
        the logs (the events of this connector, and the ones of the workers, brokers and controllers without connector),
        🛠️ the playground actions. Text, or the history JSON with a "timeline" list added to each connector.

The times of the logs of the containers are UTC (the log4j pattern of the images has no zone). Untrusted data: log lines
and configs are only parsed and printed, never evaluated.
"""
import argparse
import datetime
import json
import re
import shlex
import sys

UTC = datetime.timezone.utc
ICON_SOURCE = {'topics': '📋', 'logs': '📜', 'playground': '🛠️ '}
# components whose events matter to a connector even without connector context
RELEVANT_FILE = re.compile(r'^(connect|broker|controller|kafka|zookeeper)', re.IGNORECASE)
RELEVANT_KINDS = {'infra', 'lifecycle', 'start', 'known_cause', 'config_change', 'first_error'}


def read_session(path):
    started, started_by, actions = None, None, []
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.rstrip('\n')
                if not line:
                    continue
                if line.startswith('#'):
                    m = re.match(r'# session started (\S+) by playground (.+)$', line)
                    if m:
                        started, started_by = m.group(1), m.group(2)
                    continue
                parts = line.split('\t', 4)
                if len(parts) < 5:
                    continue
                try:
                    epoch, duration, code = int(parts[1]), int(parts[2]), int(parts[3])
                except ValueError:
                    continue
                actions.append({'time': parts[0], 'epoch': epoch, 'duration_seconds': duration, 'exit_code': code,
                                'command': parts[4]})
    except OSError:
        return None
    return {'started': started, 'started_by': started_by, 'actions': actions}


def human_duration(seconds):
    seconds = int(seconds)
    if seconds < 120:
        return '%ds' % seconds
    if seconds < 7200:
        return '%dmin' % (seconds // 60)
    if seconds < 172800:
        return '%dh' % (seconds // 3600)
    return '%dd' % (seconds // 86400)


def utc_text(ms, with_date=True):
    d = datetime.datetime.fromtimestamp(ms / 1000.0, tz=UTC)
    return d.strftime('%Y-%m-%d %H:%M:%S UTC' if with_date else '%H:%M:%S UTC')


def cmd_session(a):
    s = read_session(a.file)
    if s is None:
        s = {'started': None, 'started_by': None, 'actions': []}
    if a.json:
        print(json.dumps(s, indent=2, ensure_ascii=False))
        return 0 if s['actions'] else 1
    if s['started']:
        print('🛠️  Session started %s by playground %s: %d action(s)' % (
            s['started'].replace('T', ' ').replace('Z', ' UTC'), s['started_by'], len(s['actions'])))
    else:
        print('🛠️  %d action(s) recorded' % len(s['actions']))
    if not s['actions']:
        print('💤 no playground command changed the environment since it started')
        return 1
    for x in s['actions']:
        ok = '✅' if x['exit_code'] == 0 else '❌'
        print('%s  %s %5s  %s%s' % (utc_text(x['epoch'] * 1000, with_date=False), ok, human_duration(x['duration_seconds']),
                                    x['command'], '' if x['exit_code'] == 0 else '   (exit code %d)' % x['exit_code']))
    return 0


# ---- merge ------------------------------------------------------------------------------------------------------

def log_time_ms(t):
    """2026-11-26T12:30:27 (or with milliseconds, a space, a zone) → epoch ms, UTC when there is no zone"""
    if not t:
        return None
    t = t.strip().replace(' ', 'T', 1).replace(',', '.')
    m = re.match(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$', t)
    if not m:
        return None
    d = datetime.datetime.strptime(m.group(1), '%Y-%m-%dT%H:%M:%S')
    zone = m.group(3)
    if zone and zone != 'Z':
        sign = 1 if zone[0] == '+' else -1
        hh, mm = int(zone[1:3]), int(zone[-2:])
        d = d.replace(tzinfo=datetime.timezone(sign * datetime.timedelta(hours=hh, minutes=mm)))
    else:
        d = d.replace(tzinfo=UTC)
    ms = int(d.timestamp() * 1000)
    if m.group(2):
        ms += int(float(m.group(2)) * 1000)
    return ms


def command_connector(command):
    """the --connector / -c of a playground command line, None when there is none"""
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    for i, w in enumerate(words):
        if w in ('--connector', '-c') and i + 1 < len(words):
            return words[i + 1]
        if w.startswith('--connector='):
            return w.split('=', 1)[1]
    return None


def log_events(timeline, connector):
    out = []
    for ev in timeline or []:
        ms = log_time_ms(ev.get('time'))
        if ms is None:
            continue
        ev_connector = ev.get('connector')
        f = ev.get('file') or ''
        if ev_connector:
            if connector and ev_connector != connector:
                continue
        else:
            # the events of the other components (control center, schema registry...) say nothing about the connector
            if not RELEVANT_FILE.match(f.rsplit('/', 1)[-1]) or ev.get('kind') not in RELEVANT_KINDS:
                continue
            # a WARN without connector is noise here (deprecated configs, a broker not up yet at startup)
            if ev.get('kind') == 'first_error' and (ev.get('level') or '').upper() not in ('ERROR', 'FATAL'):
                continue
        where = ev.get('broker') or f.rsplit('/', 1)[-1].replace('.log', '')
        text = ev.get('text') or ''
        if ev.get('kind') == 'first_error':
            text = '%s %s%s' % ('🛑' if (ev.get('level') or '').upper() in ('ERROR', 'FATAL') else '⚠️ ',
                                text, (' (×%d)' % ev['count']) if ev.get('count') and ev['count'] > 1 else '')
        out.append({'ts': ms, 'source': 'logs', 'what': where, 'text': text[:220], 'kind': ev.get('kind'),
                    'details': []})
    return out


def topic_events(history_entry):
    out = []
    icons = {'created': '🆕', 'deleted': '🗑️ ', 'config': '⚙️ ', 'commit': '🧵', 'topic': '📚', 'target-state': '🎯'}
    states = {'RUNNING': '🟢', 'FAILED': '🛑', 'PAUSED': '⏸️ ', 'STOPPED': '⏹️ ', 'UNASSIGNED': '⌛', 'RESTARTING': '🔄',
              'REMOVED': '🗑️ '}
    for e in history_entry.get('events') or []:
        icon = states.get(e.get('state')) if e.get('kind') == 'status' else icons.get(e.get('kind'), '• ')
        details = list(e.get('changes') or [])
        if e.get('trace'):
            details.append('↳ ' + e['trace'])
        out.append({'ts': e['ts'], 'source': 'topics', 'what': e.get('what') or '',
                    'text': '%s %s' % (icon or '• ', e.get('text') or ''), 'kind': e.get('kind'), 'details': details})
    return out


def session_events(session, connector):
    out = []
    for x in (session or {}).get('actions') or []:
        target = command_connector(x['command'])
        if connector and target and target != connector:
            continue
        status = '' if x['exit_code'] == 0 else ' ❌ exit code %d' % x['exit_code']
        took = '' if x['duration_seconds'] < 2 else ' (%s)' % human_duration(x['duration_seconds'])
        out.append({'ts': x['epoch'] * 1000, 'source': 'playground', 'what': 'playground',
                    'text': x['command'] + took + status, 'kind': 'action', 'details': []})
    return out


def merged(history_entry, timeline, session, since_ms):
    c = history_entry.get('connector')
    events = topic_events(history_entry) + log_events(timeline, c) + session_events(session, c)
    order = {'playground': 0, 'topics': 1, 'logs': 2}
    events = [e for e in events if e['ts'] >= since_ms]
    # the log times have no milliseconds: within one second, the playground action, then the topics, then the logs
    events.sort(key=lambda e: (e['ts'] // 1000, order[e['source']], e['ts']))
    previous = None
    for e in events:
        e['time'] = utc_text(e['ts'])
        e['delta_ms'] = None if previous is None else e['ts'] - previous
        previous = e['ts']
    return events


def delta_text(ms):
    if ms is None:
        return ''
    s = ms / 1000.0
    if s < 1:
        return '+0s'
    if s < 120:
        return '+%ds' % s
    if s < 7200:
        return '+%dmin' % (s // 60)
    return '+%dh' % (s // 3600)


def cmd_merge(a):
    history = json.load(open(a.history, encoding='utf-8'))
    try:
        tl = json.load(open(a.timeline, encoding='utf-8')).get('timeline') if a.timeline else []
    except (OSError, ValueError, AttributeError):
        tl = []
    session = read_session(a.session) if a.session else None
    for h in history:
        h['timeline'] = merged(h, tl, session, a.since_ms)
    if a.json:
        print(json.dumps(history, indent=2, ensure_ascii=False))
        return 0
    # text: the lines of the connector given by --only (one at a time, the caller prints the header and the summary)
    for h in history:
        if a.only and h.get('connector') != a.only:
            continue
        counts = {k: sum(1 for e in h['timeline'] if e['source'] == k) for k in ('topics', 'logs', 'playground')}
        print('   %d event(s): 📋 %d from the internal topics, 📜 %d from the logs, 🛠️  %d playground action(s)' % (
            len(h['timeline']), counts['topics'], counts['logs'], counts['playground']))
        for e in h['timeline']:
            print('%s %7s  %s %-10s  %s' % (e['time'], delta_text(e['delta_ms']), ICON_SOURCE[e['source']],
                                           (e['what'] or '')[:10], e['text']))
            for d in e['details']:
                print('%s%s' % (' ' * 47, d))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('session')
    s.add_argument('--file', required=True)
    s.add_argument('--json', action='store_true')
    m = sub.add_parser('merge')
    m.add_argument('--history', required=True)
    m.add_argument('--timeline')
    m.add_argument('--session')
    m.add_argument('--since-ms', type=int, default=0)
    m.add_argument('--only', default='')
    m.add_argument('--json', action='store_true')
    a = p.parse_args()
    return cmd_session(a) if a.cmd == 'session' else cmd_merge(a)


if __name__ == '__main__':
    sys.exit(main())
