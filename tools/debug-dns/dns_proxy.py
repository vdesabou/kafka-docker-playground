"""DNS proxy of 'playground debug dns'.

Runs in a sidecar container sharing the network namespace of the target container
(docker run --network container:<c>), listens on LISTEN (udp and tcp, port 53), and the
/etc/resolv.conf of the target container points to it. For each query:

- a name matching a rule of RULES_FILE gets the faked answer of the rule;
- any other name is forwarded to UPSTREAM (the nameservers of the original resolv.conf,
  127.0.0.11 for the embedded DNS of docker), unchanged.

RULES_FILE is read again when it changes, one rule per line: '<host> <mode> [<value>]'
  nxdomain            NXDOMAIN (UnknownHostException in a JVM)
  resolve-to <ip>     an A record with this ip (empty answer for the other types: AAAA...)
  delay <seconds>     the real answer, sent after this delay
  servfail            SERVFAIL (a resolver that fails: temporary failure in name resolution)
A rule matches the name itself and the name with a search domain appended (broker.<domain>).

Only the standard library: no dependency to install in the sidecar.
"""

import os
import socket
import struct
import sys
import threading
import time

LISTEN = os.environ.get("LISTEN", "127.0.0.53")
UPSTREAM = [u for u in os.environ.get("UPSTREAM", "127.0.0.11").split(",") if u]
RULES_FILE = os.environ.get("RULES_FILE", "/rules")
UPSTREAM_TIMEOUT = 5.0

_rules = {}
_rules_mtime = None
_lock = threading.Lock()


def log(msg):
    print(time.strftime("%H:%M:%S") + " " + msg, flush=True)


def load_rules():
    global _rules, _rules_mtime
    try:
        mtime = os.stat(RULES_FILE).st_mtime
    except OSError:
        mtime = None
    with _lock:
        if mtime == _rules_mtime:
            return _rules
        rules = {}
        if mtime is not None:
            with open(RULES_FILE) as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 2 and not parts[0].startswith("#"):
                        rules[parts[0].lower().rstrip(".")] = (parts[1], parts[2] if len(parts) > 2 else "")
        _rules, _rules_mtime = rules, mtime
        return rules


def parse_question(data):
    """(name, qtype, end offset of the question) of the first question, None if malformed."""
    if len(data) < 12 or struct.unpack(">H", data[4:6])[0] < 1:
        return None
    labels, i = [], 12
    while i < len(data):
        n = data[i]
        if n == 0:
            i += 1
            break
        if n & 0xC0:  # no compression pointer in a question
            return None
        labels.append(data[i + 1:i + 1 + n].decode("ascii", "replace"))
        i += 1 + n
    if i + 4 > len(data):
        return None
    qtype = struct.unpack(">H", data[i:i + 2])[0]
    return ".".join(labels).lower(), qtype, i + 4


def find_rule(name, rules):
    for host, rule in rules.items():
        if name == host or name.startswith(host + "."):
            return host, rule
    return None, None


def build_answer(query, end, rcode, ip=None, qtype=None):
    """Answer with the question of the query, rcode, and an A record when ip is set and qtype is A (1)."""
    flags = struct.unpack(">H", query[2:4])[0]
    # QR, the opcode and RD of the query, RA, rcode
    flags = 0x8000 | (flags & 0x7900) | 0x0080 | rcode
    ancount = 1 if (ip and qtype == 1) else 0
    header = query[0:2] + struct.pack(">HHHHH", flags, 1, ancount, 0, 0)
    body = query[12:end]
    if ancount:
        body += b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 0, 4) + socket.inet_aton(ip)
    return header + body


def forward(query, tcp):
    for upstream in UPSTREAM:
        try:
            if tcp:
                with socket.create_connection((upstream, 53), timeout=UPSTREAM_TIMEOUT) as s:
                    s.sendall(struct.pack(">H", len(query)) + query)
                    length = struct.unpack(">H", recv_exact(s, 2))[0]
                    return recv_exact(s, length)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(UPSTREAM_TIMEOUT)
                s.sendto(query, (upstream, 53))
                return s.recvfrom(65535)[0]
        except (OSError, struct.error):
            continue
    return None


def recv_exact(s, n):
    data = b""
    while len(data) < n:
        chunk = s.recv(n - len(data))
        if not chunk:
            raise OSError("connection closed")
        data += chunk
    return data


def handle(query, tcp=False):
    q = parse_question(query)
    if q is None:
        return forward(query, tcp)
    name, qtype, end = q
    host, rule = find_rule(name, load_rules())
    if rule is None:
        return forward(query, tcp)
    mode, value = rule
    log("%s %s (type %d): %s %s" % (name, "tcp" if tcp else "udp", qtype, mode, value))
    if mode == "nxdomain":
        return build_answer(query, end, 3)
    if mode == "servfail":
        return build_answer(query, end, 2)
    if mode == "resolve-to":
        return build_answer(query, end, 0, ip=value, qtype=qtype)
    if mode == "delay":
        try:
            time.sleep(float(value))
        except ValueError:
            pass
        return forward(query, tcp)
    return forward(query, tcp)


def serve_udp(sock):
    while True:
        query, addr = sock.recvfrom(65535)

        def reply(query=query, addr=addr):
            answer = handle(query)
            if answer:
                sock.sendto(answer, addr)

        threading.Thread(target=reply, daemon=True).start()


def serve_tcp(sock):
    while True:
        conn, _ = sock.accept()

        def reply(conn=conn):
            with conn:
                try:
                    conn.settimeout(30)
                    length = struct.unpack(">H", recv_exact(conn, 2))[0]
                    answer = handle(recv_exact(conn, length), tcp=True)
                    if answer:
                        conn.sendall(struct.pack(">H", len(answer)) + answer)
                except (OSError, struct.error):
                    pass

        threading.Thread(target=reply, daemon=True).start()


def main():
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind((LISTEN, 53))
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind((LISTEN, 53))
    tcp.listen(64)
    log("listening on %s:53, upstream %s, rules %s" % (LISTEN, ",".join(UPSTREAM), RULES_FILE))
    threading.Thread(target=serve_tcp, args=(tcp,), daemon=True).start()
    serve_udp(udp)


if __name__ == "__main__":
    sys.exit(main())
