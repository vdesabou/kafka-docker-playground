#!/usr/bin/env python3
"""Adapt a customer's cp-ansible inventory (hosts.yml) to the hosts of environment/ansible.

Run by environment/ansible/start.sh in the ansible-controller image (python and the yaml loader of ansible, which reads
the !vault values): python3 inventory_overlay.py <customer hosts.yml>. Prints a json document on stdout:

  inventory     the adapted inventory (the variables of the customer, the hosts of the playground)
  hosts         the playground hosts to start, in the order of the groups
  version       confluent_package_version of the customer, if set
  method        installation_method of the customer, if set
  changes       what was changed, one line each (values masked)
  warnings      what cannot be reproduced as is, one line each

The variables of the customer are kept (all.vars, group vars, host vars). Only these are changed:
  - the hosts: the n-th host of a group becomes the n-th playground host of that group (broker, broker2, broker3...)
  - the connection: ansible_host, ansible_user, ansible_ssh_*, ansible_become*... are removed (docker connection, root)
  - the host names (and ansible_host addresses) of the customer, in any variable, become the playground host names
  - the vault values (no vault password here), the customer certificates (files on the customer's controller) and the
    customer package mirrors are replaced
"""

import json
import re
import sys

from ansible.parsing.yaml.loader import AnsibleLoader
from ansible.parsing.yaml.objects import AnsibleVaultEncryptedUnicode

# cp-ansible group -> playground hosts, in order
GROUPS = [
    ("zookeeper", ["zookeeper", "zookeeper2", "zookeeper3"]),
    ("kafka_controller", ["controller", "controller2", "controller3"]),
    ("kafka_broker", ["broker", "broker2", "broker3"]),
    ("schema_registry", ["schema-registry"]),
    ("kafka_connect", ["connect", "connect2", "connect3"]),
    ("ksql", ["ksqldb-server"]),
    ("kafka_rest", ["rest-proxy"]),
    ("control_center_next_gen", ["control-center"]),
]
GROUP_NAMES = {g for g, _ in GROUPS}

CONNECTION_VARS = re.compile(
    r"^ansible_(host|port|user|password|ssh_.*|become.*|connection|private_key_file|python_interpreter|shell_.*)$"
)
# variables that point to the package repositories / files of the customer: removed, the public ones are used
MIRROR_VARS = re.compile(
    r"^(confluent_common_repository_baseurl|confluent_.*archive.*_file_source|confluent_archive_file_remote"
    r"|custom_(yum|apt)_repo.*|repository_configuration|jmxexporter_url_remote|jolokia_url_remote"
    r"|confluent_cli_(archive_file_source|base_url|repository_baseurl).*)$"
)
CERT_FLAGS = ["ssl_custom_certs", "ssl_provided_keystore_and_truststore"]
VAULT_PLACEHOLDER = "playground-vault-value"

changes = []
warnings = []


def plain(value, path, vault_keys):
    """yaml objects of ansible -> plain python, vault values replaced"""
    if isinstance(value, AnsibleVaultEncryptedUnicode):
        vault_keys.append(path)
        return VAULT_PLACEHOLDER
    if isinstance(value, dict):
        return {str(k): plain(v, f"{path}.{k}" if path else str(k), vault_keys) for k, v in value.items()}
    if isinstance(value, list):
        return [plain(v, f"{path}[{i}]", vault_keys) for i, v in enumerate(value)]
    if isinstance(value, str):
        return str(value)
    return value


def group_hosts(groups, name):
    """hosts of a group, its child groups included, in order, with their host vars"""
    group = groups.get(name) or {}
    hosts = list((group.get("hosts") or {}).items())
    for child in (group.get("children") or {}):
        hosts += group_hosts(groups, child)
    return hosts


def collect_groups(node, groups):
    """every group of the inventory, at any depth, by name"""
    for name, group in (node or {}).items():
        group = group or {}
        groups[name] = group
        collect_groups(group.get("children"), groups)


def main(path):
    with open(path) as f:
        text = f.read()
    try:
        data = AnsibleLoader(text).get_single_data()
    except Exception as e:  # an INI inventory, or invalid yaml
        print(json.dumps({"error": f"cannot read {path} as a yaml inventory: {e}"}))
        return 1
    if not isinstance(data, dict):
        print(json.dumps({"error": f"{path} is not a yaml inventory (an INI inventory? convert it with ansible-inventory -i <file> --list -y)"}))
        return 1
    vault_keys = []
    data = plain(data, "", vault_keys)
    root = data.get("all") if "all" in data else {"children": data}
    root = root or {}
    all_vars = dict(root.get("vars") or {})
    groups = {}
    collect_groups(root.get("children"), groups)

    # customer host -> playground host, and the host vars of each playground host
    host_map = {}
    playground_hosts = []
    host_vars = {}
    for group, targets in GROUPS:
        hosts = group_hosts(groups, group)
        if len(hosts) > len(targets):
            dropped = ", ".join(h for h, _ in hosts[len(targets):])
            warnings.append(f"{group}: {len(hosts)} hosts, only the first {len(targets)} are kept ({dropped} left out)")
        for (host, hv), target in zip(hosts, targets):
            hv = dict(hv or {})
            if host in host_map and host_map[host] != target:
                warnings.append(f"{host} is in several groups: its components are on separate hosts here ({host_map[host]}, {target})")
            else:
                host_map[host] = target
            address = hv.get("ansible_host")
            if address and address not in host_map:
                host_map[str(address)] = target
            removed = sorted(k for k in hv if CONNECTION_VARS.match(k))
            for k in removed:
                del hv[k]
            if removed:
                changes.append(f"{host} -> {target}: connection variables removed ({', '.join(removed)})")
            else:
                changes.append(f"{host} -> {target}")
            if "hostname" in hv:
                hv["hostname"] = target
                changes.append(f"{target}: hostname set to {target}")
            playground_hosts.append(target)
            host_vars[target] = (group, hv)
    if not playground_hosts:
        print(json.dumps({"error": f"no host in the groups of cp-ansible ({', '.join(GROUP_NAMES)}) in {path}"}))
        return 1
    for name in groups:
        if name not in GROUP_NAMES and name not in ("all", "ungrouped") and group_hosts(groups, name):
            if not any(name in (groups.get(g) or {}).get("children", {}) or {} for g in GROUP_NAMES):
                warnings.append(f"group {name} is not deployed here (not a group of the playground)")

    # short names of the fqdn of the customer, when they are unique
    shorts = {}
    for host, target in list(host_map.items()):
        if "." in host and not re.match(r"^\d+\.\d+\.\d+\.\d+$", host):
            shorts.setdefault(host.split(".")[0], set()).add(target)
    for short, targets in shorts.items():
        if short not in host_map and len(targets) == 1:
            host_map[short] = targets.pop()

    # group vars, without the connection variables of the customer
    group_vars = {}
    for name, group in groups.items():
        gv = dict(group.get("vars") or {})
        removed = sorted(k for k in gv if CONNECTION_VARS.match(k))
        for k in removed:
            del gv[k]
        if removed:
            changes.append(f"group {name}: connection variables removed ({', '.join(removed)})")
        if gv and (name in GROUP_NAMES):
            group_vars[name] = gv
        elif gv and name not in ("all", "ungrouped"):
            # vars of a child group of a cp-ansible group, or of another group: kept on the cp-ansible group
            parents = [g for g in GROUP_NAMES if name in ((groups.get(g) or {}).get("children") or {})]
            for parent in parents:
                group_vars.setdefault(parent, {}).update(gv)
    removed = sorted(k for k in all_vars if CONNECTION_VARS.match(k))
    for k in removed:
        del all_vars[k]
    if removed:
        changes.append(f"all: connection variables removed ({', '.join(removed)})")

    # customer certificates: files on the customer's controller
    for scope, scope_vars in [("all", all_vars)] + list(group_vars.items()):
        for flag in CERT_FLAGS:
            if str(scope_vars.get(flag, "")).lower() in ("true", "yes", "1"):
                scope_vars[flag] = False
                warnings.append(f"{scope}: {flag} set to false, the certificates are generated by cp-ansible (the customer's are files on their controller: use playground tools cert inspect on them)")
        for scope_name, scope_v in [(scope, scope_vars)]:
            for k in sorted(scope_v):
                if MIRROR_VARS.match(k):
                    del scope_v[k]
                    changes.append(f"{scope_name}: {k} removed (package repository or file of the customer, the public ones are used)")
    for target, (group, hv) in host_vars.items():
        for flag in CERT_FLAGS:
            if str(hv.get(flag, "")).lower() in ("true", "yes", "1"):
                hv[flag] = False
                warnings.append(f"{target}: {flag} set to false, the certificates are generated by cp-ansible")
    if "custom_java_path" in all_vars:
        changes.append("all: custom_java_path replaced by the JDK of the hosts")
    for key in ("kerberos_kafka_broker_primary", "kerberos_configure"):
        if key in all_vars:
            warnings.append(f"all: {key} is set, kerberos needs a KDC that is not part of this environment")
            break
    for key, value in all_vars.items():
        if key.endswith("_url") and isinstance(value, str) and re.match(r"^ldaps?://", value):
            warnings.append(f"all: {key} points to an LDAP server ({re.sub(r'://([^/:]+)', '://<host>', value)}) that is not part of this environment")
    if vault_keys:
        warnings.append(f"{len(vault_keys)} vault value(s) replaced by '{VAULT_PLACEHOLDER}' (no vault password): {', '.join(vault_keys[:8])}")

    # host names of the customer in the variables -> playground host names (the longest first: fqdn before short name)
    names = sorted(host_map, key=len, reverse=True)

    def rename(value):
        if isinstance(value, dict):
            return {k: rename(v) for k, v in value.items()}
        if isinstance(value, list):
            return [rename(v) for v in value]
        if isinstance(value, str):
            for name in names:
                value = re.sub(r"(?<![\w.-])" + re.escape(name) + r"(?![\w-]|\.[A-Za-z0-9])", host_map[name], value)
        return value

    renamed = set()
    before = json.dumps([all_vars, group_vars, {t: hv for t, (_, hv) in host_vars.items()}])
    all_vars = rename(all_vars)
    group_vars = rename(group_vars)
    host_vars = {t: (g, rename(hv)) for t, (g, hv) in host_vars.items()}
    after = json.dumps([all_vars, group_vars, {t: hv for t, (_, hv) in host_vars.items()}])
    for name in names:
        if re.search(r"(?<![\w.-])" + re.escape(name) + r"(?![\w-]|\.[A-Za-z0-9])", before):
            renamed.add(f"{name} -> {host_map[name]}")
    if renamed:
        changes.append(f"host names in the variables: {', '.join(sorted(renamed))}")
    if before != after:
        pass

    children = {}
    for group, targets in GROUPS:
        group_targets = [t for t in targets if t in host_vars and host_vars[t][0] == group]
        if not group_targets:
            continue
        children[group] = {"hosts": {t: (host_vars[t][1] or None) for t in group_targets}}
        if group in group_vars:
            children[group]["vars"] = group_vars[group]
    inventory = {"all": {"vars": all_vars, "children": children}}
    print(json.dumps({
        "inventory": inventory,
        "hosts": playground_hosts,
        "version": str(all_vars.get("confluent_package_version") or ""),
        "method": str(all_vars.get("installation_method") or ""),
        "changes": changes,
        "warnings": warnings,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
