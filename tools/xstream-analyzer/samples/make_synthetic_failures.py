# Builds samples/orclcdc_diag_synthetic_failures.html from samples/orclcdc_diag_healthy.html, to exercise the
# CRITICAL / HIGH paths a playground database does not produce: NOARCHIVELOG, no supplemental logging, capture
# ABORTED with ORA-01291, PAUSED FOR FLOW CONTROL, LogMiner memory at 97%, streams pool advice with spills,
# alerts and events with errors.
#
#   python3 -I samples/make_synthetic_failures.py samples/orclcdc_diag_healthy.html samples/orclcdc_diag_synthetic_failures.html

import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
EMPTY = r'<td[^>]*>\s*(?:&nbsp;)?\s*</td>'

def section_bounds(s, section):
    start = s.index(f'<h3>{section}</h3>')
    end = s.find('<h3>', start + 5)
    return start, (len(s) if end < 0 else end)

def in_section(s, section, old, new):
    a, b = section_bounds(s, section)
    assert old in s[a:b], (section, old)
    return s[:a] + s[a:b].replace(old, new, 1) + s[b:]

s = in_section(s, 'Overview: Database', '\nARCHIVELOG\n', '\nNOARCHIVELOG\n')
s = in_section(s, 'Overview: Database', '\nIMPLICIT\n', '\nNO\n')
s = in_section(s, 'Capture Process: Status', '\nENABLED\n', '\nABORTED\n')
a, b = section_bounds(s, 'Capture Process: Status')
body = s[a:b]
cells = list(re.finditer(EMPTY, body))
assert len(cells) >= 2, 'empty error cells'
e1, e2 = cells[-2], cells[-1]
body = body[:e1.start()] + '<td align="right">\n1291\n</td>' + body[e1.end():e2.start()] + '<td>\nORA-01291: missing logfile\n</td>' + body[e2.end():]
s = s[:a] + body + s[b:]
s = in_section(s, 'Capture Process: Statistics', '\nWAITING FOR TRANSACTION\n', '\nPAUSED FOR FLOW CONTROL\n')
s = in_section(s, 'LogMiner: Statistics', '18.52', '97.10')

# streams pool advice: 5000 estimated spills up to the current size (factor <= 1)
a, b = section_bounds(s, 'Streams Pool: Size advice')
rows = s[a:b].split('<tr>')
out = rows[:2]
for r in rows[2:]:
    tds = re.findall(r'<td[^>]*>\s*(.*?)\s*</td>', r, re.S)
    spills = 5000 if len(tds) > 2 and float(tds[2]) <= 1 else 0
    n = [0]
    def sub(m):
        n[0] += 1
        return f'<td align="right">\n{spills}\n</td>' if n[0] == 4 else m.group(0)
    out.append(re.sub(r'<td[^>]*>.*?</td>', sub, r, flags=re.S))
s = s[:a] + '<tr>'.join(out) + s[b:]

def table(headers, rows):
    h = ''.join(f'<th scope="col">{x}</th>' for x in headers)
    r = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in row) + '</tr>\n' for row in rows)
    return f"<p>\n<table border='1' width='90%' align='center'>\n<tr>{h}</tr>\n{r}</table>\n<p>\n"

alerts = table(['Message Type', 'Creation Time', 'Module', 'Reason', 'Suggested<br>Action', 'Resolution'],
               [['Warning', '2026-10-14 09:10:00', 'STREAMS', 'STREAMS capture process CAP$_XOUT_1 aborted with ORA-01291', 'Restore the missing archived log', ''],
                ['Warning', '2026-10-14 09:15:00', 'STREAMS', 'STREAMS capture process CAP$_XOUT_1 aborted with ORA-01291', 'Restore the missing archived log', '']])
events = table(['Event Time', 'Streams Name', 'Event Name', 'Description', 'Error Number', 'Error Message'],
               [['2026-10-14 09:10:00', 'CAP$_XOUT_1', 'ABORT', 'capture aborted', '1291', 'ORA-01291: missing logfile']])
for section, t in (('Alerts: In last 7 days', alerts), ('Events: Recent history (last 7 days)', events)):
    a, b = section_bounds(s, section)
    s = s[:a] + f'<h3>{section}</h3>\n<br>\n' + t + s[b:] if '<table' not in s[a:b] else s
open(sys.argv[2], 'w', encoding='utf-8').write(s)
