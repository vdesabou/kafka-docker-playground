#!/usr/bin/env python3
"""Unit tests of timeline.py: python3 -I tools/connector-history/test_timeline.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import timeline as tl  # noqa: E402

T0 = 1795700000  # 2026-11-26T13:33:20Z


def history(connector='orders-sink'):
    return [{'connector': connector, 'events': [
        {'ts': (T0 + 10) * 1000 + 600, 'kind': 'status', 'what': 'task 0', 'state': 'FAILED', 'text': 'RUNNING → FAILED on connect:8083',
         'trace': 'org.apache.kafka.connect.errors.ConnectException: boom'},
        {'ts': T0 * 1000 + 100, 'kind': 'created', 'what': 'config', 'text': 'created (HttpSinkConnector, tasks.max=1)'},
    ], 'summary': {}}]


def timeline():
    return {'timeline': [
        {'time': '2026-11-26T13:33:25', 'kind': 'lifecycle', 'level': None, 'text': '🔄 rebalance of the worker group connect-cluster',
         'file': 'connect.log', 'connector': None},
        {'time': '2026-11-26T13:33:30', 'kind': 'first_error', 'level': 'ERROR', 'text': 'Task threw an uncaught exception',
         'file': 'connect.log', 'connector': 'orders-sink', 'count': 3},
        {'time': '2026-11-26T13:33:30', 'kind': 'first_error', 'level': 'ERROR', 'text': 'another connector failed',
         'file': 'connect.log', 'connector': 'other-sink'},
        {'time': '2026-11-26T13:33:22', 'kind': 'first_error', 'level': 'WARN', 'text': 'deprecated config', 'file': 'control-center.log',
         'connector': None},
        {'time': '2026-11-26T13:33:23', 'kind': 'first_error', 'level': 'WARN', 'text': 'broker not up yet', 'file': 'broker.log',
         'connector': None},
        {'time': '2026-11-26T13:33:29', 'kind': 'infra', 'level': None, 'text': '👑 a new active controller (epoch 2)',
         'file': 'controller.log', 'connector': None, 'broker': 'controller 4'},
    ]}


SESSION = ('# session started 2026-11-26T13:30:00Z by playground run\n'
           '2026-11-26T13:33:28Z\t%d\t0\t0\tplayground debug block-traffic --container connect --destination broker --action start\n'
           '2026-11-26T13:33:29Z\t%d\t1\t1\tplayground connector restart --connector other-sink\n'
           '2026-11-26T13:33:40Z\t%d\t5\t0\tplayground connector restart --connector orders-sink\n'
           'garbage line\n') % (T0 + 8, T0 + 9, T0 + 20)


class Merge(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.session = os.path.join(self.dir.name, 'playground-session.log')
        with open(self.session, 'w') as f:
            f.write(SESSION)

    def tearDown(self):
        self.dir.cleanup()

    def test_order_sources_and_filters(self):
        events = tl.merged(history()[0], timeline()['timeline'], tl.read_session(self.session), 0)
        texts = [(e['source'], e['text']) for e in events]
        self.assertEqual([s for s, _ in texts], ['topics', 'logs', 'playground', 'logs', 'topics', 'logs', 'playground'])
        self.assertIn('block-traffic', texts[2][1])
        self.assertTrue(texts[3][1].startswith('👑'))
        self.assertTrue(texts[4][1].startswith('🛑 RUNNING → FAILED'))
        self.assertIn('(×3)', texts[5][1])
        # another connector's error and its playground action, the WARN without connector, control center: left out
        self.assertFalse(any('other' in t for _, t in texts))
        self.assertFalse(any('deprecated' in t or 'not up yet' in t for _, t in texts))
        self.assertEqual(events[0]['delta_ms'], None)
        self.assertEqual(events[1]['delta_ms'], 5000 - 100)
        self.assertIn('(5s)', texts[6][1])

    def test_since(self):
        events = tl.merged(history()[0], timeline()['timeline'], tl.read_session(self.session), (T0 + 9) * 1000)
        self.assertEqual(events[0]['source'], 'logs')

    def test_session_json_and_missing_file(self):
        s = tl.read_session(self.session)
        self.assertEqual(s['started_by'], 'run')
        self.assertEqual([a['exit_code'] for a in s['actions']], [0, 1, 0])
        self.assertIsNone(tl.read_session(os.path.join(self.dir.name, 'nope')))

    def test_command_connector(self):
        self.assertEqual(tl.command_connector('playground connector restart --connector a'), 'a')
        self.assertEqual(tl.command_connector('playground connector restart -c b'), 'b')
        self.assertEqual(tl.command_connector("playground topic produce --forced-value '{\"id\": %g}'"), None)

    def test_cli_merge_json(self):
        h = os.path.join(self.dir.name, 'h.json')
        t = os.path.join(self.dir.name, 't.json')
        json.dump(history(), open(h, 'w'))
        json.dump(timeline(), open(t, 'w'))
        out = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'timeline.py'), 'merge', '--history', h, '--timeline', t,
                              '--session', self.session, '--json'], capture_output=True, text=True, check=True).stdout
        doc = json.loads(out)
        self.assertEqual(len(doc[0]['timeline']), 7)
        self.assertIn('summary', doc[0])
        self.assertEqual({e['source'] for e in doc[0]['timeline']}, {'topics', 'logs', 'playground'})


if __name__ == '__main__':
    unittest.main()
