#!/usr/bin/env python3
"""Unit tests of upgrade_check.py: python3 -I tools/connector-upgrade-check/test_upgrade_check.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import upgrade_check as uc  # noqa: E402


def defs(*items):
    return {'name': 'x', 'configs': [{'definition': dict({'type': 'STRING', 'required': False, 'default_value': None,
                                                          'importance': 'LOW', 'documentation': '', 'valid_values': None}, **i)}
                                     for i in items]}


class Checks(unittest.TestCase):
    def run_config(self, old, new, config):
        findings = []
        uc.check_config(uc.definitions(old), uc.definitions(new), config, findings)
        return findings

    def test_removed_key_set_is_breaking(self):
        f = self.run_config(defs({'name': 'a'}, {'name': 'b'}), defs({'name': 'b'}), {'a': '1'})
        self.assertEqual([(x[0], x[1]) for x in f], [('breaking', 'a')])

    def test_framework_or_unknown_keys_are_ignored(self):
        f = self.run_config(defs({'name': 'b'}), defs({'name': 'b'}), {'topics': 't', 'transforms.x.type': 'y'})
        self.assertEqual(f, [])

    def test_unknown_keys_are_info_and_framework_keys_are_not_listed(self):
        findings = []
        unknown = uc.check_unknown_keys(uc.definitions(defs({'name': 'b'})), uc.definitions(defs({'name': 'b'})),
                                        {'b': '1', 'type.name': '_doc', 'topics': 't', 'name': 'n',
                                         'transforms.x.type': 'y', 'errors.tolerance': 'all',
                                         'consumer.override.max.poll.records': '10', 'tpyo.key': 'z',
                                         '_comment': 'commented out', '_transforms': 'unwrap'}, findings)
        self.assertEqual(unknown, ['tpyo.key', 'type.name'])
        self.assertEqual([(x[0], x[1]) for x in findings], [('info', 'unknown keys')])
        self.assertIn('type.name', findings[0][2])

    def test_no_unknown_keys_no_finding(self):
        findings = []
        uc.check_unknown_keys(uc.definitions(defs({'name': 'b'})), uc.definitions(defs({'name': 'b'})),
                              {'b': '1', 'connector.class': 'x', 'tasks.max': '1'}, findings)
        self.assertEqual(findings, [])

    def test_value_no_longer_valid(self):
        f = self.run_config(defs({'name': 'c', 'valid_values': '[none, gzip, lz4]'}),
                            defs({'name': 'c', 'valid_values': '[[none, gzip]]'}), {'c': 'lz4'})
        self.assertEqual(f[0][0], 'breaking')
        self.assertIn('lz4', f[0][2])

    def test_value_still_valid_and_reformatted_list_is_no_change(self):
        f = self.run_config(defs({'name': 'c', 'valid_values': '[none, gzip]'}),
                            defs({'name': 'c', 'valid_values': '[[none, gzip]]'}), {'c': 'GZIP'})
        self.assertEqual(f, [])

    def test_range_is_not_a_list(self):
        f = self.run_config(defs({'name': 'p', 'type': 'INT', 'valid_values': '[5242880,...,2147483647]'}),
                            defs({'name': 'p', 'type': 'INT', 'valid_values': '[5242880,...,2147483647]'}), {'p': '52428801'})
        self.assertEqual(f, [])

    def test_out_of_range(self):
        f = self.run_config(defs({'name': 'p', 'type': 'INT', 'valid_values': '[1,...,100]'}),
                            defs({'name': 'p', 'type': 'INT', 'valid_values': '[10,...,100]'}), {'p': '5'})
        self.assertEqual(f[0][0], 'breaking')

    def test_default_changed_on_unset_key_is_review(self):
        f = self.run_config(defs({'name': 'd', 'default_value': 'fail'}), defs({'name': 'd', 'default_value': 'ignore'}), {})
        self.assertEqual((f[0][0], f[0][1]), ('review', 'd'))
        self.assertIn('fail → ignore', f[0][2])

    def test_default_changed_on_set_key_is_not_reported(self):
        f = self.run_config(defs({'name': 'd', 'default_value': 'fail'}), defs({'name': 'd', 'default_value': 'ignore'}),
                            {'d': 'write'})
        self.assertEqual(f, [])

    def test_password_default_masked(self):
        f = self.run_config(defs({'name': 'p.password', 'type': 'PASSWORD', 'default_value': 'a'}),
                            defs({'name': 'p.password', 'type': 'PASSWORD', 'default_value': 'b'}), {})
        self.assertIn('••• → •••', f[0][2])

    def test_new_required_key_without_default(self):
        f = self.run_config(defs({'name': 'a'}), defs({'name': 'a'}, {'name': 'n', 'required': True}), {})
        self.assertEqual((f[0][0], f[0][1]), ('breaking', 'n'))

    def test_type_change_on_set_key(self):
        f = self.run_config(defs({'name': 't', 'type': 'INT'}), defs({'name': 't', 'type': 'LONG'}), {'t': '3'})
        self.assertEqual(f[0][0], 'review')

    def test_changelog_mentions_key_and_risk_words(self):
        findings = []
        changelog = {'feeds': ['x'], 'versions': [
            {'version': '2.0.0', 'changes': ['CC-1: flush.size now applies per partition', 'CC-2: Bumped jackson for CVE-2025-1',
                                             'CC-3: Changed the default of behavior.on.null.values']},
            {'version': '1.9.0', 'changes': ['CC-1: flush.size now applies per partition']}]}
        uc.check_changelog(changelog, {'flush.size': '3'}, ['flush.size'], findings, 10)
        self.assertEqual([x[1] for x in findings], ['changelog 2.0.0', 'changelog 2.0.0'])
        self.assertTrue(all(x[0] == 'review' for x in findings))
        self.assertIn('mentions flush.size', findings[0][2])

    def test_no_feed(self):
        self.assertIn('no changelog feed', uc.check_changelog({'feeds': [], 'versions': []}, {}, [], [], 10))

    def test_dependencies_major_and_family_swap(self):
        findings = []
        deps = {'changes': [
            {'artifact': 'jackson-databind', 'group': 'com.fasterxml.jackson.core', 'change': 'upgraded', 'from': '2.15.2', 'to': '2.21.7'},
            {'artifact': 'avro', 'group': 'org.apache.avro', 'change': 'upgraded', 'from': '1.11.3', 'to': '2.0.0'},
            {'artifact': 'aws-java-sdk-core', 'group': 'com.amazonaws', 'change': 'removed', 'from': '1.12.524', 'to': None},
            {'artifact': 's3', 'group': 'software.amazon.awssdk', 'change': 'added', 'from': None, 'to': '2.28.23'},
            {'artifact': 'netty-common', 'group': 'io.netty', 'change': 'added', 'from': None, 'to': '4.2.17.Final'}]}
        uc.check_dependencies(deps, findings)
        self.assertEqual(sorted(x[1] for x in findings), ['AWS SDK v1', 'AWS SDK v2', 'Avro'])

    def test_versions(self):
        self.assertTrue(uc.version_lt('1.7.9', '1.7.10'))
        self.assertTrue(uc.version_lt('3.2.6', '3.2.6-4'))
        self.assertFalse(uc.version_lt('10.6.0', '10.6.0'))

    def test_cp8_table_from_the_examples(self):
        table = uc.cp8_minimums(os.path.join(HERE, '..', '..'))
        self.assertEqual(table.get('confluentinc-kafka-connect-s3'), '10.6.0')
        self.assertEqual(table.get('confluentinc-kafka-connect-jdbc'), '10.8.0')
        # connect-testing-smt installs http and its guard is for connect-transforms: not attributed to http
        self.assertNotEqual(table.get('confluentinc-kafka-connect-http'), '2.5.0')


class EndToEnd(unittest.TestCase):
    def test_cli_verdicts_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            def w(name, doc):
                path = os.path.join(d, name)
                with open(path, 'w') as f:
                    json.dump(doc, f)
                return path
            old = w('old.json', defs({'name': 'a', 'valid_values': '[x, y]'}, {'name': 'b', 'default_value': '1'}))
            new_same = w('new_same.json', defs({'name': 'a', 'valid_values': '[x, y]'}, {'name': 'b', 'default_value': '1'}))
            new_review = w('new_review.json', defs({'name': 'a', 'valid_values': '[x, y]'}, {'name': 'b', 'default_value': '2'}))
            new_break = w('new_break.json', defs({'name': 'a', 'valid_values': '[y]'}, {'name': 'b', 'default_value': '1'}))
            config = w('config.json', {'connector.class': 'c', 'a': 'x'})
            base = [sys.executable, '-I', os.path.join(HERE, 'upgrade_check.py'), '--old', old, '--config', config,
                    '--plugin', 'o/p', '--from', '1.0.0', '--to', '2.0.0', '--repo', d]
            for new, code, verdict in ((new_same, 0, 'safe'), (new_review, 1, 'review'), (new_break, 1, 'breaking')):
                r = subprocess.run(base + ['--new', new, '--json'], capture_output=True, text=True)
                self.assertEqual(r.returncode, code, r.stderr)
                self.assertEqual(json.loads(r.stdout)['verdict'], verdict)
            r = subprocess.run(base + ['--new', os.path.join(d, 'missing.json')], capture_output=True, text=True)
            self.assertEqual(r.returncode, 2)


if __name__ == '__main__':
    unittest.main()
