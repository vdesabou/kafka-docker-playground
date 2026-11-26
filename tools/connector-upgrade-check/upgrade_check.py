#!/usr/bin/env python3
"""What changes for one connector config when its plugin is upgraded, for 'playground connector upgrade-check'.

Inputs (all JSON, written by the playground commands):
  --old / --new      config definitions of the connector class in each version (config-<class>.json of
                     get_connector_plugin_configs, the format of the connect config/validate endpoint)
  --config           the connector config of the customer (flat JSON object)
  --changelog        'connector-plugin changelog --json' between the two versions (optional)
  --dependencies     'connector-plugin dependencies --json' with the two versions (optional)
  --info             'connector-plugin info --json --from <from>' (optional)
  --cve              'connector-plugin cve-scan --json --compare-with <to>' (optional)
  --repo             root of kafka-docker-playground: the CP 8 minimum versions are read from the guards of the
                     connect/ examples ("minimal supported connector version is X for CP 8.0")

Each finding is ❌ breaking, ⚠️ review or ℹ️ info. A changelog line is never breaking: it is printed for a human to
judge. Exit code: 0 safe, 1 review or breaking, 2 could not check.

Untrusted data: configs, definitions and release notes are only parsed, compared and printed, never evaluated.
"""
import argparse
import glob
import json
import os
import re
import sys

# libraries whose major version change (or removal) can break custom code next to the plugin (credentials providers,
# SMTs, converters, partitioners compiled against them) or the data written
WATCHED_GROUPS = {
    'com.fasterxml.jackson.core': 'Jackson',
    'org.apache.avro': 'Avro',
    'com.google.protobuf': 'Protobuf',
    'com.amazonaws': 'AWS SDK v1',
    'software.amazon.awssdk': 'AWS SDK v2',
    'io.netty': 'Netty',
    'org.apache.kafka': 'Kafka clients',
    'org.apache.parquet': 'Parquet',
    'com.google.cloud': 'Google Cloud client',
    'com.azure': 'Azure SDK',
    'org.apache.hadoop': 'Hadoop',
}
RISK_WORDS = re.compile(r'\b(default|behaviou?r|deprecat\w*|remov\w*|breaking|no longer|incompatib\w*|migrat\w*|renam\w*)\b',
                        re.IGNORECASE)
# release note lines about dependencies and CVEs: not a behaviour change of the connector
DEPENDENCY_HYGIENE = re.compile(r'\b(CVE-\d+|bump\w*|upgrad\w* (the )?(version|dependenc)|dependenc\w*|librar\w*|'
                                r'unused|test\w*)\b', re.IGNORECASE)
SEVERITY_ORDER = {'breaking': 0, 'review': 1, 'info': 2}
# keys of the Kafka Connect framework (ConnectorConfig, SinkConnectorConfig, SourceConnectorConfig, KIP-891): valid in
# every connector config, not in the definitions of the connector class
FRAMEWORK_KEYS = {
    'name', 'connector.class', 'tasks.max', 'tasks.max.enforce', 'key.converter', 'value.converter', 'header.converter',
    'config.action.reload', 'transforms', 'predicates', 'topics', 'topics.regex', 'topic.creation.groups',
    'exactly.once.support', 'transaction.boundary', 'transaction.boundary.interval.ms', 'offsets.storage.topic',
    'plugin.version', 'key.converter.plugin.version', 'value.converter.plugin.version',
    'header.converter.plugin.version',
}
FRAMEWORK_PREFIXES = ('key.converter.', 'value.converter.', 'header.converter.', 'transforms.', 'predicates.',
                      'errors.', 'consumer.override.', 'producer.override.', 'admin.override.', 'topic.creation.')


def load(path):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    with open(path, encoding='utf-8') as f:
        try:
            return json.load(f)
        except ValueError:
            return None


def definitions(doc):
    if not doc:
        return {}
    return {c['definition']['name']: c['definition'] for c in doc.get('configs', []) if 'definition' in c}


def version_key(v):
    """1.7.10 > 1.7.9; 3.2.6-4 > 3.2.6; non numeric parts compared as text"""
    parts = re.split(r'[.\-+]', str(v))
    return [(0, int(p), '') if p.isdigit() else (1, 0, p) for p in parts]


def version_lt(a, b):
    return version_key(a) < version_key(b)


def major(v):
    m = re.match(r'\s*(\d+)', str(v or ''))
    return int(m.group(1)) if m else None


def value_list(valid_values):
    """[none, gzip] (or the [[none, gzip]] of newer versions) → ['none', 'gzip']; None when it is a description"""
    if not isinstance(valid_values, str):
        return None
    v = valid_values.strip()
    while v.startswith('[') and v.endswith(']'):
        v = v[1:-1].strip()
    if not v or '[' in v or ']' in v:
        return None
    items = [i.strip() for i in v.split(',')]
    if '...' in items:
        return None
    # a sentence is not a list of values
    if any(' ' in i for i in items) or any(not i for i in items):
        return None
    return items


def value_range(valid_values):
    """[5242880,...,2147483647] (a numeric range of a Range validator) → (5242880, 2147483647), else None"""
    if not isinstance(valid_values, str):
        return None
    m = re.match(r'^\[*\s*(-?[\d.]+|null)?\s*,\s*\.\.\.\s*,\s*(-?[\d.]+|null)?\s*\]*$', valid_values.strip())
    if not m:
        return None
    lo = float(m.group(1)) if m.group(1) not in (None, 'null') else None
    hi = float(m.group(2)) if m.group(2) not in (None, 'null') else None
    return lo, hi


def same_valid_values(a, b):
    la, lb = value_list(a), value_list(b)
    if la is not None and lb is not None:
        return set(x.lower() for x in la) == set(x.lower() for x in lb)
    return (a or None) == (b or None)


def as_text(v):
    if v is None:
        return 'none'
    if isinstance(v, (list, dict)):
        return json.dumps(v)
    return str(v)


def secret_like(key, definition=None):
    if definition and definition.get('type') == 'PASSWORD':
        return True
    return bool(re.search(r'(password|secret|token|access\.key|private\.key)', key, re.IGNORECASE))


def short_value(key, value, definition=None):
    if value is not None and secret_like(key, definition):
        return '•••'
    t = as_text(value)
    return t if len(t) <= 60 else t[:57] + '…'


# ---- the checks ---------------------------------------------------------------------------------------------------

def check_config(old, new, config, findings):
    set_keys = [k for k in config if k in old or k in new]
    for key in set_keys:
        o, n = old.get(key), new.get(key)
        value = config.get(key)
        if o is not None and n is None:
            findings.append(('breaking', key, 'set to %s, removed in the target version (the worker rejects or ignores it)'
                             % short_value(key, value), 'config'))
            continue
        if n is None:
            continue
        if o is not None and o.get('type') != n.get('type'):
            findings.append(('review', key, 'type changes %s → %s (value %s)' % (o.get('type'), n.get('type'),
                                                                               short_value(key, value)), 'config'))
        allowed = value_list(n.get('valid_values'))
        bounds = value_range(n.get('valid_values'))
        if bounds and value is not None and re.match(r'^-?[\d.]+$', str(value).strip()):
            lo, hi = bounds
            number = float(str(value).strip())
            if (lo is not None and number < lo) or (hi is not None and number > hi):
                findings.append(('breaking', key, 'value %s is out of the range of the target version: %s'
                                 % (value, n.get('valid_values')), 'config'))
                continue
        if allowed is not None and value is not None and not isinstance(value, (list, dict)):
            if str(value).strip().lower() not in [a.lower() for a in allowed]:
                findings.append(('breaking', key, 'value %s is not a valid value of the target version: %s'
                                 % (short_value(key, value), ', '.join(allowed)), 'config'))
                continue
        if o is not None and not same_valid_values(o.get('valid_values'), n.get('valid_values')) and allowed is None \
                and not (bounds and value_range(o.get('valid_values'))):
            findings.append(('review', key, 'the rule for its value changes: %s → %s (value %s)' % (
                as_text(o.get('valid_values'))[:90], as_text(n.get('valid_values'))[:90], short_value(key, value)), 'config'))

    # keys the customer does not set: their default is what they run with
    for key in sorted(set(old) & set(new)):
        if key in config:
            continue
        o, n = old[key], new[key]
        if o.get('default_value') != n.get('default_value'):
            findings.append(('review', key, 'not set: default changes %s → %s' % (
                short_value(key, o.get('default_value'), n), short_value(key, n.get('default_value'), n)), 'default'))

    # keys added as required, without a default, that the config does not set: the validation fails
    added = sorted(set(new) - set(old))
    for key in added:
        n = new[key]
        if n.get('required') and n.get('default_value') is None and key not in config:
            findings.append(('breaking', key, 'new required key without default, not set in the config', 'config'))
    return set_keys, added


def check_unknown_keys(old, new, config, findings):
    """keys the config sets that neither version knows (and that are not framework keys): an obsolete key removed
    before the version in use (type.name of the Elasticsearch sink), a typo, or a pass-through property that the
    connector hands to a client without declaring it. Information only: the connector ignores most of them today"""
    # a key starting with _ is a key commented out (_comment, _transforms...): Kafka Connect ignores it too
    unknown = sorted(k for k in config
                     if k not in old and k not in new and k not in FRAMEWORK_KEYS and not k.startswith(FRAMEWORK_PREFIXES)
                     and not k.startswith('_'))
    if unknown:
        findings.append(('info', 'unknown keys', '%d key(s) of the config in neither version (obsolete, a typo, or a '
                         'pass-through property, check the docs): %s%s' % (
                             len(unknown), ', '.join(unknown[:8]), ' …' if len(unknown) > 8 else ''), 'config'))
    return unknown


def check_changelog(changelog, config, set_keys, findings, max_lines):
    if not changelog:
        return None
    if not changelog.get('feeds'):
        return 'no changelog feed for this plugin (only the Confluent self-managed plugins documented on docs.confluent.io have one)'
    matched = []
    seen = set()
    words = sorted(set_keys, key=len, reverse=True)
    for v in changelog.get('versions', []):
        for line in v.get('changes', []):
            # the same fix released on several minor lines (12.1.15, 12.0.12, 11.0.22...): the newest one only
            text = re.sub(r'^(PR-\d+\s*-\s*)?', '', line.strip())
            if text in seen:
                continue
            hit = [k for k in words if re.search(r'(?<![\w.])' + re.escape(k) + r'(?![\w])', line)]
            if hit:
                matched.append((v['version'], line, 'mentions %s' % hit[0]))
                seen.add(text)
            elif RISK_WORDS.search(line) and not DEPENDENCY_HYGIENE.search(line):
                matched.append((v['version'], line, RISK_WORDS.search(line).group(1).lower()))
                seen.add(text)
    for version, line, why in matched[:max_lines]:
        findings.append(('review', 'changelog %s' % version, '%s (%s)' % (line.strip(), why), 'changelog'))
    if len(matched) > max_lines:
        findings.append(('info', 'changelog', '%d more matching line(s) not shown (--json for all)' % (len(matched) - max_lines),
                         'changelog'))
    return None


def check_dependencies(deps, findings):
    if not deps:
        return
    by_group = {}
    for c in deps.get('changes', []):
        group = c.get('group') or ''
        label = next((v for g, v in WATCHED_GROUPS.items() if group == g or group.startswith(g + '.')), None)
        if not label:
            continue
        kind = c.get('change')
        if kind in ('upgraded', 'downgraded') and major(c.get('from')) is not None and major(c.get('from')) != major(c.get('to')):
            by_group.setdefault(label, []).append('%s %s → %s' % (c['artifact'], c['from'], c['to']))
        elif kind == 'removed':
            by_group.setdefault(label, []).append('%s %s removed' % (c['artifact'], c['from']))
        elif kind == 'added':
            by_group.setdefault(label + ' (added)', []).append('%s %s' % (c['artifact'], c['to']))
    removed_labels = {l for l, items in by_group.items() if any(i.endswith('removed') for i in items)}
    for label, items in sorted(by_group.items()):
        if label.endswith('(added)'):
            # only worth a line when it replaces a removed family (AWS SDK v1 → v2)
            base = label[:-len(' (added)')]
            family = base.rsplit(' v', 1)[0]
            if not any(r != base and r.rsplit(' v', 1)[0] == family for r in removed_labels):
                continue
            findings.append(('review', base, 'added: %s%s' % (', '.join(items[:3]), ' …' if len(items) > 3 else ''),
                             'dependencies'))
            continue
        findings.append(('review', label, '%s%s: custom classes built against it (credentials providers, SMTs, '
                         'converters) must be rebuilt and tested' % (', '.join(items[:3]), ' …' if len(items) > 3 else ''),
                         'dependencies'))


def read_text(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def cp8_minimums(repo):
    """{owner-name: minimum version for CP 8} from the guards of the connect/ examples. A folder with several plugins
    counts only when one of them is named like the folder (connect-aws-s3-sink → kafka-connect-s3)"""
    table = {}
    for sh in glob.glob(os.path.join(repo, 'connect', '*', '*.sh')):
        try:
            text = read_text(sh)
        except OSError:
            continue
        m = re.search(r'minimal supported connector version is ([0-9][^ "]*) for CP 8', text)
        if not m:
            continue
        folder = os.path.dirname(sh)
        plugins = set()
        for y in glob.glob(os.path.join(folder, 'docker-compose*.yml')):
            plugins |= set(re.findall(r'confluent-hub-components/([A-Za-z0-9_.]+-[A-Za-z0-9_.-]+?)(?=[\s:,"/]|$)',
                                      read_text(y)))
        if len(plugins) > 1:
            words = set(re.split(r'[-_]', os.path.basename(folder))) - {'connect'}
            scored = sorted(plugins, key=lambda p: (-len(words & set(re.split(r'[-_]', p))), len(p)))
            best = scored[0]
            if not words & set(re.split(r'[-_]', best)):
                continue
            if len(scored) > 1 and len(words & set(re.split(r'[-_]', scored[1]))) == len(words & set(re.split(r'[-_]', best))) \
                    and len(scored[1]) == len(best):
                continue
            plugins = {best}
        for p in plugins:
            if p not in table or version_lt(table[p], m.group(1)):
                table[p] = m.group(1)
    return table


def check_cp(plugin, to, cp_version, repo, findings):
    if not cp_version:
        return
    if (major(cp_version) or 0) < 8:
        findings.append(('info', 'CP %s' % cp_version, 'no minimum plugin version known for CP 7 and older', 'cp'))
        return
    table = cp8_minimums(repo)
    key = plugin.replace('/', '-', 1)
    minimum = table.get(key)
    if not minimum:
        findings.append(('info', 'CP %s' % cp_version, 'no CP 8 minimum version known for %s (from the guards of the '
                         'connect/ examples)' % plugin, 'cp'))
        return
    if version_lt(to, minimum):
        findings.append(('breaking', 'CP %s' % cp_version, '%s is below %s, the minimum version of %s supported on CP 8'
                         % (to, minimum, plugin), 'cp'))
    else:
        findings.append(('info', 'CP %s' % cp_version, '%s ≥ %s, the minimum version of %s for CP 8' % (to, minimum, plugin),
                         'cp'))


def check_info(info, cve, findings):
    if info and info.get('versions_behind') is not None:
        findings.append(('info', 'versions', '%s version(s) behind the latest (%s%s)' % (
            info['versions_behind'], info.get('latest'),
            (', %s' % info['latest_release_date']) if info.get('latest_release_date') else ''), 'info'))
    if cve and isinstance(cve.get('fixed'), list):
        findings.append(('info', 'CVE', '%d fixed, %d still there, %d new (connector-plugin cve-scan --compare-with)' % (
            len(cve['fixed']), len(cve.get('still') or []), len(cve.get('new') or [])), 'cve'))


# ---- report ---------------------------------------------------------------------------------------------------------

ICON = {'breaking': '❌', 'review': '⚠️ ', 'info': 'ℹ️ '}
TITLE = {'breaking': '❌ BREAKING', 'review': '⚠️  REVIEW', 'info': 'ℹ️  INFO'}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--old', required=True)
    p.add_argument('--new', required=True)
    p.add_argument('--config', required=True)
    p.add_argument('--changelog')
    p.add_argument('--dependencies')
    p.add_argument('--info')
    p.add_argument('--cve')
    p.add_argument('--repo', default='.')
    p.add_argument('--plugin', required=True)
    p.add_argument('--connector-class', default='')
    p.add_argument('--from', dest='from_version', required=True)
    p.add_argument('--to', required=True)
    p.add_argument('--cp-version', default='')
    p.add_argument('--name', default='connector')
    p.add_argument('--max-changelog-lines', type=int, default=10)
    p.add_argument('--json', action='store_true')
    a = p.parse_args()

    old, new = definitions(load(a.old)), definitions(load(a.new))
    config = load(a.config)
    if isinstance(config, dict) and isinstance(config.get('config'), dict):
        config = config['config']
    if not isinstance(config, dict):
        print('❌ the config is not a JSON object', file=sys.stderr)
        return 2
    if not old or not new:
        print('❌ could not read the configuration of %s in %s' % (a.connector_class or 'the connector class',
              a.from_version if not old else a.to), file=sys.stderr)
        return 2

    findings = []
    set_keys, added = check_config(old, new, config, findings)
    check_unknown_keys(old, new, config, findings)
    unavailable = []
    changelog = load(a.changelog)
    note = check_changelog(changelog, config, set_keys, findings, a.max_changelog_lines)
    if note:
        unavailable.append(note)
        if major(a.from_version) != major(a.to):
            doc = (changelog or {}).get('documentation_url') or (load(a.info) or {}).get('documentation_url')
            findings.append(('review', 'major version', '%s → %s with no release notes to check here: read the upgrade '
                             'notes of the vendor%s' % (a.from_version, a.to, (' (%s)' % doc) if doc else ''), 'changelog'))
    elif a.changelog and load(a.changelog) is None:
        unavailable.append('the changelog could not be read')
    check_dependencies(load(a.dependencies), findings)
    if a.dependencies and load(a.dependencies) is None:
        unavailable.append('the dependencies could not be compared')
    check_cp(a.plugin, a.to, a.cp_version, a.repo, findings)
    check_info(load(a.info), load(a.cve), findings)
    if added:
        findings.append(('info', 'new keys', '%d key(s) added (defaults apply): %s%s' % (
            len(added), ', '.join(added[:6]), ' …' if len(added) > 6 else ''), 'config'))

    findings.sort(key=lambda f: SEVERITY_ORDER[f[0]])
    verdict = 'breaking' if any(f[0] == 'breaking' for f in findings) else \
        'review' if any(f[0] == 'review' for f in findings) else 'safe'

    if a.json:
        print(json.dumps({
            'connector': a.name, 'connector_class': a.connector_class, 'connector_plugin': a.plugin,
            'from': a.from_version, 'to': a.to, 'cp_version': a.cp_version or None, 'verdict': verdict,
            'keys_set': len(set_keys), 'unavailable': unavailable,
            'findings': [{'severity': s, 'subject': k, 'message': m, 'source': src} for s, k, m, src in findings],
        }, indent=2, ensure_ascii=False))
    else:
        print('🔼 %s %s → %s%s, %s%s' % (a.plugin, a.from_version, a.to,
                                       (' on CP %s' % a.cp_version) if a.cp_version else '',
                                       ('connector %s, ' % a.name) if a.name not in ('', 'connector') else '',
                                       a.connector_class.rsplit('.', 1)[-1]))
        print('   %d key(s) of the plugin set in the config, %d key(s) in %s, %d in %s' % (
            len(set_keys), len(old), a.from_version, len(new), a.to))
        for u in unavailable:
            print('   ℹ️  %s' % u)
        for sev in ('breaking', 'review', 'info'):
            items = [f for f in findings if f[0] == sev]
            if not items:
                continue
            print('')
            print(TITLE[sev])
            width = min(max(len(f[1]) for f in items), 38)
            for _, subject, message, _src in items:
                print('   %-*s  %s' % (width, subject, message))
        print('')
        label = {'breaking': '❌ breaking: the config needs changes before the upgrade',
                 'review': '⚠️  review: behaviour changes to check, the config still validates',
                 'safe': '✅ safe: nothing in the config or the defaults changes' +
                         ('' if unavailable else ', nothing in the release notes')}[verdict]
        print('Verdict: %s' % label)
    return 0 if verdict == 'safe' else 1


if __name__ == '__main__':
    sys.exit(main())
