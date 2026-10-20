"""
Environment inventory and change timeline of a CFK support bundle.

- inventory: Kubernetes version, CFK operator version, application / init images of every component, read from
  `cluster-details.txt` (written by `kubectl confluent support-bundle`) and completed with the CR specs and the
  operator Deployment.
- compatibility: Kubernetes, Confluent Platform and Control Center versions against the CFK support matrix, and
  `confluent-init-container` tags against the operator version.
- timeline: who changed what and when (managedFields of the CRs and StatefulSets, pod (re)starts, container
  terminations), newest first. Changes made by hand (kubectl edit / apply, helm, Argo CD…) are what usually
  explains "it broke after X".
"""

import re
from typing import Dict, List, Optional, Tuple

# https://docs.confluent.io/operator/current/co-supported-environments.html
# minor -> (CP range, Control Center (next gen) range, Kubernetes range, OpenShift range)
# The Kubernetes column is the range of the first release of the minor, patch releases can extend it (release notes).
CFK_MATRIX = {
    '3.3': (('7.5', '8.3'), ('2.4', '2.6'), ('1.28', '1.36'), ('4.15', '4.22')),
    '3.2': (('7.4', '8.2'), ('2.4', '2.6'), ('1.27', '1.35'), ('4.14', '4.21')),
    '3.1': (('7.3', '8.1'), ('2.3', '2.3'), ('1.26', '1.34'), ('4.13', '4.20')),
    '3.0': (('7.2', '8.0'), ('2.2', '2.2'), ('1.25', '1.33'), ('4.12', '4.20')),
    '2.11': (('7.1', '7.9'), ('2.0', '2.1'), ('1.25', '1.32'), ('4.12', '4.19')),
    '2.10': (('7.1', '7.8'), None, ('1.25', '1.31'), ('4.12', '4.18')),
}
CFK_SUPPORT_DOC = 'https://docs.confluent.io/operator/current/co-supported-environments.html'

# operator image tag (0.<build>.<patch>) -> CFK release, "CFK image tags" table of the same page
_OPERATOR_TAGS = {
    '0.1718.99': '3.3.1', '0.1718.10': '3.3.0',
    '0.1514.158': '3.2.4', '0.1514.76': '3.2.3', '0.1514.40': '3.2.2', '0.1514.19': '3.2.1', '0.1514.1': '3.2.0',
    '0.1351.220': '3.1.4', '0.1351.147': '3.1.3', '0.1351.103': '3.1.2', '0.1351.59': '3.1.1', '0.1351.24': '3.1.0',
    '0.1263.243': '3.0.6', '0.1263.163': '3.0.5', '0.1263.124': '3.0.4', '0.1263.105': '3.0.3',
    '0.1263.79': '3.0.2', '0.1263.34': '3.0.1', '0.1263.8': '3.0.0',
    '0.1193.264': '2.11.7', '0.1193.192': '2.11.6', '0.1193.151': '2.11.5', '0.1193.108': '2.11.4',
    '0.1193.70': '2.11.3', '0.1193.47': '2.11.2', '0.1193.34': '2.11.1', '0.1193.1': '2.11.0',
}
# unknown patch of a known build line still gives the minor
_OPERATOR_BUILD_MINOR = {'0.1718': '3.3', '0.1514': '3.2', '0.1351': '3.1', '0.1263': '3.0', '0.1193': '2.11',
                         '0.1145': '2.10', '0.1033': '2.9'}

# Field managers of controllers: their writes are reconciliations, not changes someone made
_CONTROLLER_MANAGERS = {'manager', 'kube-controller-manager', 'kubelet', 'kube-scheduler', 'confluent-operator',
                        'cfk-operator', 'Go-http-client'}

_VERSION_RE = re.compile(r'(?<![\d.])(\d+)\.(\d+)(?:\.(\d+))?')


def _version_tuple(text: str) -> Optional[Tuple[int, ...]]:
    m = _VERSION_RE.search(text or '')
    if not m:
        return None
    return tuple(int(g) for g in m.groups() if g is not None)


def _minor(text: str) -> Optional[str]:
    v = _version_tuple(text)
    return f"{v[0]}.{v[1]}" if v else None


def _in_range(minor: str, bounds: Tuple[str, str]) -> bool:
    key = _version_tuple(minor)[:2]
    return _version_tuple(bounds[0])[:2] <= key <= _version_tuple(bounds[1])[:2]


def image_tag(image: str) -> str:
    """registry/repo/name:tag@sha -> tag ('' when there is none)"""
    image = (image or '').split('@')[0]
    last = image.rsplit('/', 1)[-1]
    return last.split(':', 1)[1] if ':' in last else ''


def image_version(image: str) -> Optional[str]:
    """CP / CFK version in an image tag: 8.3.2-1-ubi9.amd64 -> 8.3.2, a custom tag without a version -> None"""
    m = re.match(r'v?(\d+\.\d+\.\d+)', image_tag(image))
    return m.group(1) if m else None


def operator_release(tag_or_version: str) -> Optional[str]:
    """0.1718.99 -> 3.3.1, 3.3.1 -> 3.3.1, 0.1718.200 -> 3.3 (minor only)"""
    m = re.search(r'\d+\.\d+\.\d+', tag_or_version or '')
    if not m:
        return None
    value = m.group(0)
    if value in _OPERATOR_TAGS:
        return _OPERATOR_TAGS[value]
    if value.startswith('0.'):
        return _OPERATOR_BUILD_MINOR.get('.'.join(value.split('.')[:2]))
    return value


def parse_cluster_details(text: str) -> Dict:
    """Parse the cluster-details.txt of `kubectl confluent support-bundle`"""
    env: Dict = {'components': {}}
    git_version = re.search(r'^gitVersion:\s*"?([^"\s]+)', text, re.MULTILINE)
    if git_version:
        env['kubernetes_version'] = git_version.group(1)
    operator = re.search(r'^Operator Version:\s*(\S+)', text, re.MULTILINE)
    if operator:
        env['operator_image_tag'] = operator.group(1)
    current = None
    for line in text.splitlines():
        header = re.match(r'^([a-z][\w-]*):\s*$', line)
        if header:
            current = header.group(1)
            continue
        image = re.match(r'^\s+(Application|Init) Image:\s*(\S+)', line)
        if image and current:
            key = 'image' if image.group(1) == 'Application' else 'init_image'
            env['components'].setdefault(current, {})[key] = image.group(2)
    crd = re.search(r'^\S+\.platform\.confluent\.io\s*\|\|\s*(\S+)\s*\|\|', text, re.MULTILINE)
    if crd:
        env['crd_version'] = crd.group(1)
    return env


def compatibility_findings(env: Dict) -> List[Dict]:
    """[{severity, message, instance}] for the versions outside the support matrix of the CFK version"""
    findings = []
    release = env.get('cfk_version')
    minor = _minor(release) if release else None
    matrix = CFK_MATRIX.get(minor) if minor else None

    k8s = env.get('kubernetes_version')
    if matrix and k8s:
        k8s_minor = _minor(k8s)
        openshift = 'openshift' in k8s.lower()
        bounds = matrix[3] if openshift else matrix[2]
        if k8s_minor and not _in_range(k8s_minor, bounds):
            findings.append({
                'severity': 'high',
                'message': f"{'OpenShift' if openshift else 'Kubernetes'} {k8s_minor} ({k8s}) is outside the range "
                           f"supported by CFK {release}: {bounds[0]} - {bounds[1]}. Check the release notes of the "
                           f"patch release, else upgrade CFK before (or roll back) the Kubernetes upgrade.",
            })

    versions = {}
    for name, info in sorted((env.get('components') or {}).items()):
        image = info.get('image', '')
        version = image_version(image)
        is_c3_next_gen = 'next-gen' in image or name.endswith('nextgen')
        if matrix and version:
            bounds = matrix[1] if is_c3_next_gen else matrix[0]
            label = 'Control Center' if is_c3_next_gen else 'Confluent Platform'
            if bounds and not _in_range(_minor(version), bounds):
                findings.append({
                    'severity': 'high', 'instance': name,
                    'message': f"{name} runs {label} {version}, outside the range supported by CFK {release}: "
                               f"{bounds[0]} - {bounds[1]} ({image_tag(image)})",
                })
        if version and not is_c3_next_gen:
            versions.setdefault(version, []).append(name)

        init = info.get('init_image', '')
        init_version = image_version(init)
        if release and init_version and _version_tuple(release) and len(_version_tuple(release)) == 3 \
                and init_version != release:
            findings.append({
                'severity': 'medium', 'instance': name,
                'message': f"{name} uses confluent-init-container {init_version} with CFK operator {release}: "
                           f"the init container must be on the same version as the operator",
            })
    if len(versions) > 1:
        detail = ', '.join(f"{v} ({', '.join(names)})" for v, names in
                           sorted(versions.items(), key=lambda kv: _version_tuple(kv[0])))
        findings.append({
            'severity': 'low',
            'message': f"Components run different Confluent Platform versions: {detail}",
        })
    return findings


def managed_field_changes(obj: Dict, kind: str, name: str) -> List[Dict]:
    """Changes recorded in metadata.managedFields (not the status, not the controllers on their own CR)"""
    changes = []
    for entry in (obj.get('metadata') or {}).get('managedFields') or []:
        if not isinstance(entry, dict) or not entry.get('time') or entry.get('subresource') == 'status':
            continue
        manager = entry.get('manager', '')
        fields = entry.get('fieldsV1') or {}
        spec = fields.get('f:spec') if isinstance(fields.get('f:spec'), dict) else {}
        top = sorted(k[2:] for k in spec if k.startswith('f:'))
        if manager in _CONTROLLER_MANAGERS:
            # the operator writing a StatefulSet spec is a rollout; anything else is housekeeping
            if not (kind == 'StatefulSet' and top):
                continue
            what = f"StatefulSet spec updated by {manager} (rolling restart of the pods)"
        else:
            if not top and not fields.get('f:metadata') and not fields.get('f:data'):
                continue
            touched = ', '.join(f"spec.{t}" for t in top) if top else (
                'data' if fields.get('f:data') else 'metadata')
            what = f"{entry.get('operation', 'Update')} by {manager}: {touched}"
        changes.append({'time': entry['time'], 'kind': kind, 'name': name, 'manager': manager, 'what': what})
    return changes


def pod_changes(pod: Dict, name: str) -> List[Dict]:
    """Pod creation and container terminations"""
    changes = []
    metadata = pod.get('metadata') or {}
    status = pod.get('status') or {}
    if metadata.get('creationTimestamp'):
        node = (pod.get('spec') or {}).get('nodeName')
        changes.append({'time': metadata['creationTimestamp'], 'kind': 'Pod', 'name': name,
                        'what': 'Pod created' + (f" on {node}" if node else '')})
    for container in (status.get('containerStatuses') or []):
        last = (container.get('lastState') or {}).get('terminated') or {}
        if last.get('finishedAt'):
            changes.append({'time': last['finishedAt'], 'kind': 'Pod', 'name': name,
                            'what': f"container {container.get('name')} terminated: {last.get('reason', '')} "
                                    f"exitCode={last.get('exitCode')} (restarts={container.get('restartCount', 0)})"})
    return changes
