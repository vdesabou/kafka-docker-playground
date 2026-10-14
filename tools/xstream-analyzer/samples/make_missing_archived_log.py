# Builds samples/orclcdc_diag_missing_archived_log.html from samples/orclcdc_diag_healthy.html: the capture is
# WAITING FOR REDO on an archived log that is already registered and complete (thread 1 sequence 3), so it cannot
# read it (deleted, or not readable from the capture instance). Its captured SCN stays in that log, nothing is captured.
#
#   python3 -I samples/make_missing_archived_log.py samples/orclcdc_diag_healthy.html samples/orclcdc_diag_missing_archived_log.html

import sys
s = open(sys.argv[1], encoding='utf-8').read()

def section_bounds(s, section):
    start = s.index(f'<h3>{section}</h3>')
    end = s.find('<h3>', start + 5)
    return start, (len(s) if end < 0 else end)

def in_section(s, section, old, new):
    a, b = section_bounds(s, section)
    assert old in s[a:b], (section, old)
    return s[:a] + s[a:b].replace(old, new, 1) + s[b:]

s = in_section(s, 'Capture Process: Status', ' 1220736\n', ' 1183500\n')
s = in_section(s, 'Capture Process: Statistics',
               '\nWAITING FOR TRANSACTION\n</td>\n<td>\n2026-10-14 09:20:07\n',
               '\nWAITING FOR REDO: FILE /opt/oracle/product/19c/dbhome_1/dbs/arch1_3_1144424433.dbf, THREAD 1, SEQUENCE 3, '
               'SCN 0x0000000000120e0c\n</td>\n<td>\n2026-10-14 09:16:40\n')
s = in_section(s, 'Capture Process: Statistics', '             17\n', '\n')
s = in_section(s, 'Capture Process: Statistics', ' 32454\n', ' 0\n')
open(sys.argv[2], 'w', encoding='utf-8').write(s)
