#!/usr/bin/env python3
"""Helpers of 'playground mq put|get|wait' (standard library only).

  messages     --template T --nb N | --file F       messages to send, one per line (%g replaced by 1..N in --template)
  curl-config  --broker rabbitmq|activemq|solace --dest D --dest-type queue|topic --messages F [--header k=v]...
               [--user U --password P --vhost V]    a curl config (curl -K -) with one request per message
  parse        --broker ibmmq|rabbitmq|activemq|solace|mqtt --max N   the output of a browse (stdin) as json lines
                                                    {"id", "body", "headers"}
  show         [--json] --dest D                    prints json lines (stdin) as a list, or as a json array

Untrusted data: message bodies are only parsed and printed, never evaluated.
"""
import argparse
import base64
import json
import re
import sys
import urllib.parse


def curl_quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'


def read_messages(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return [line.rstrip('\n') for line in f if line.rstrip('\n') != '']


def headers_dict(items):
    out = {}
    for item in items or []:
        if '=' not in item:
            raise SystemExit('❌ --header %s: expected key=value' % item)
        k, v = item.split('=', 1)
        out[k] = v
    return out


def cmd_messages(a):
    if a.template is not None:
        n = a.nb or 1
        for i in range(1, n + 1):
            print(a.template.replace('%g', str(i)))
        return 0
    lines = read_messages(a.file)
    if a.nb:
        if len(lines) != 1:
            raise SystemExit('❌ --nb-messages needs one message (a template with %g): got ' + str(len(lines)) + ' lines')
        for i in range(1, a.nb + 1):
            print(lines[0].replace('%g', str(i)))
    else:
        for line in lines:
            print(line)
    return 0


def cmd_curl_config(a):
    messages = read_messages(a.messages)
    headers = headers_dict(a.header)
    out = []
    for body in messages:
        req = []
        if a.broker == 'rabbitmq':
            vhost = urllib.parse.quote(a.vhost, safe='')
            payload = {'properties': {'headers': headers} if headers else {}, 'routing_key': a.dest,
                       'payload': body, 'payload_encoding': 'string'}
            req.append('url = ' + curl_quote('http://localhost:15672/api/exchanges/%s/amq.default/publish' % vhost))
            req.append('user = ' + curl_quote('%s:%s' % (a.user, a.password)))
            req.append('header = "Content-Type: application/json"')
            req.append('data = ' + curl_quote(json.dumps(payload)))
            req.append('write-out = "\\n"')
        elif a.broker == 'activemq':
            query = {'type': a.dest_type}
            query.update(headers)
            req.append('url = ' + curl_quote('http://localhost:8161/api/message/%s?%s' % (
                urllib.parse.quote(a.dest, safe=''), urllib.parse.urlencode(query))))
            req.append('user = ' + curl_quote('%s:%s' % (a.user, a.password)))
            req.append('data-urlencode = ' + curl_quote('body=' + body))
            req.append('output = "/dev/null"')
            req.append('write-out = "%{http_code}\\n"')
        elif a.broker == 'solace':
            path = 'Queue' if a.dest_type == 'queue' else 'TOPIC'
            req.append('url = ' + curl_quote('http://localhost:9000/%s/%s' % (path, urllib.parse.quote(a.dest, safe='/'))))
            req.append('header = "Content-Type: text/plain"')
            req.append('data-binary = ' + curl_quote(body))
            req.append('output = "/dev/null"')
            req.append('write-out = "%{http_code}\\n"')
        out.append('\n'.join(req))
    print('\nnext\n'.join(out))
    return 0


# ---- parse ------------------------------------------------------------------------------------------------------

def parse_amqsbcg(text):
    """amqsbcg prints, for each message, its MQMD then a dump: 00000000:  4D65 7373 6167 6520 31   'Message 1 '"""
    messages = []
    for block in re.split(r'\*{4}\s*Message descriptor\s*\*{4}', text)[1:]:
        msg_id = re.search(r"MsgId : X'([0-9A-F]+)'", block)
        fmt = re.search(r"Format : '([^']*)'", block)
        put = re.search(r"PutDate\s*:\s*'(\d+)'\s+PutTime\s*:\s*'(\d+)'", block)
        length = re.search(r'length - (\d+) of (\d+) bytes', block)
        raw = bytearray()
        for m in re.finditer(r'^[0-9A-F]{8}:\s+((?:[0-9A-F]{2,4} )+)', block, re.M):
            hexpart = m.group(1).replace(' ', '')
            raw.extend(bytes.fromhex(hexpart[:len(hexpart) // 2 * 2]))
        if length:
            raw = raw[:int(length.group(1))]
        headers = {}
        if fmt and fmt.group(1).strip():
            headers['format'] = fmt.group(1).strip()
        if put:
            d, t = put.group(1), put.group(2)
            headers['put_time'] = '%s-%s-%s %s:%s:%s' % (d[:4], d[4:6], d[6:8], t[:2], t[2:4], t[4:6])
        messages.append({'id': msg_id.group(1) if msg_id else None, 'body': raw.decode('utf-8', errors='replace'),
                         'headers': headers})
    return messages


def cmd_parse(a):
    text = sys.stdin.read()
    out = []
    if a.broker == 'ibmmq':
        out = parse_amqsbcg(text)
    elif a.broker == 'rabbitmq':
        data = json.loads(text or '[]')
        if isinstance(data, dict):
            raise SystemExit('❌ %s' % (data.get('reason') or data.get('error') or data))
        for m in data:
            body = m.get('payload')
            if m.get('payload_encoding') == 'base64':
                try:
                    body = base64.b64decode(body).decode('utf-8', errors='replace')
                except ValueError:
                    pass
            props = m.get('properties') or {}
            headers = dict(props.get('headers') or {})
            if m.get('exchange'):
                headers['exchange'] = m['exchange']
            if m.get('routing_key'):
                headers['routing_key'] = m['routing_key']
            out.append({'id': props.get('message_id'), 'body': body, 'headers': headers,
                        'redelivered': m.get('redelivered')})
    elif a.broker == 'activemq':
        data = json.loads(text or '{}')
        if data.get('status') != 200:
            raise SystemExit('❌ jolokia: %s' % (data.get('error') or data))
        for m in data.get('value') or []:
            body = m.get('Text')
            if body is None and m.get('BodyPreview') is not None:
                body = bytes((b + 256) % 256 for b in m['BodyPreview']).decode('utf-8', errors='replace')
            headers = {}
            for key in ('StringProperties', 'IntProperties', 'LongProperties', 'BooleanProperties', 'DoubleProperties'):
                for k, v in (m.get(key) or {}).items():
                    headers[k] = v
            out.append({'id': m.get('JMSMessageID'), 'body': body, 'headers': headers})
    elif a.broker == 'solace':
        data = json.loads(text or '{}')
        err = (data.get('meta') or {}).get('error')
        if err:
            raise SystemExit('❌ SEMP: %s' % err.get('description', err))
        for m in data.get('data') or []:
            out.append({'id': m.get('msgId'), 'body': None,
                        'headers': {k: m[k] for k in ('spooledTime', 'attachmentSize', 'contentSize', 'priority',
                                                      'redeliveryCount', 'replicationGroupMsgId') if k in m}})
    elif a.broker == 'mqtt':
        for line in text.splitlines():
            out.append({'id': None, 'body': line, 'headers': {}})
    for m in out[:a.max] if a.max else out:
        print(json.dumps(m, ensure_ascii=False))
    return 0


def cmd_show(a):
    msgs = [json.loads(line) for line in sys.stdin if line.strip()]
    if a.json:
        print(json.dumps(msgs, indent=2, ensure_ascii=False))
        return 0
    for i, m in enumerate(msgs, 1):
        body = m.get('body')
        print('#%d %s' % (i, body if body is not None else '(body not available)'))
        extras = dict(m.get('headers') or {})
        if m.get('id'):
            extras = dict([('id', m['id'])] + list(extras.items()))
        if extras:
            print('   ' + ', '.join('%s=%s' % (k, v) for k, v in extras.items()))
    print('📬 %d message(s) in %s' % (len(msgs), a.dest))
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('messages')
    s.add_argument('--template')
    s.add_argument('--file')
    s.add_argument('--nb', type=int, default=0)
    s = sub.add_parser('curl-config')
    s.add_argument('--broker', required=True)
    s.add_argument('--dest', required=True)
    s.add_argument('--dest-type', default='queue')
    s.add_argument('--messages', required=True)
    s.add_argument('--header', action='append')
    s.add_argument('--user', default='')
    s.add_argument('--password', default='')
    s.add_argument('--vhost', default='/')
    s = sub.add_parser('parse')
    s.add_argument('--broker', required=True)
    s.add_argument('--max', type=int, default=0)
    s = sub.add_parser('show')
    s.add_argument('--json', action='store_true')
    s.add_argument('--dest', default='')
    a = p.parse_args()
    return {'messages': cmd_messages, 'curl-config': cmd_curl_config, 'parse': cmd_parse, 'show': cmd_show}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
