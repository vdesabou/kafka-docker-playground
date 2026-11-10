#!/usr/bin/env python3
"""Tests of share_dialog.py (📤 Share of the playground HTML reports): python3 -I tools/report-common/test_share_dialog.py"""

import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report_html as rh  # noqa: E402
import share_dialog as sd  # noqa: E402


def body_with_findings():
    return (rh.verdict_html("danger", "🚨 1 critical finding: start with the deadlock")
            + rh.findings_html([{"severity": "CRITICAL", "text": "Deadlock between t-1 and t-2", "details": ["a detail"]},
                                {"severity": "MEDIUM", "text": "8 threads wait on <0x1> | a pipe"}]))


class ShareDialogTest(unittest.TestCase):
    def test_page_gets_one_dialog_with_summary_and_ticket(self):
        page = rh.page("Thread dump report — x.txt", "🧵 Thread dumps", [], body_with_findings(), "playground analyze thread-dump")
        self.assertEqual(page.count("<dialog class='share-dlg'"), 1)
        for needed in ("id='pg-share-summary'", "id='pg-share-ticket'", "id='pg-share-slack'", "id='pg-share-html'",
                       "data-share='download'", "data-share='path'", "data-share='mail'", "⚠️ Internal to Confluent"):
            self.assertIn(needed, page)
        self.assertLess(page.index("share-dlg"), page.rindex("</body>"))
        # adding it again keeps a single dialog
        self.assertEqual(sd.add_share(page).count("<dialog class='share-dlg'"), 1)

    def test_from_page_reads_verdict_and_findings(self):
        page = rh.page("T", "H", [], body_with_findings(), "f")
        title, verdict, findings = sd.from_page(page)
        self.assertEqual(title, "T")
        self.assertIn("start with the deadlock", verdict)
        self.assertEqual(findings, [("CRITICAL", "Deadlock between t-1 and t-2"), ("MEDIUM", "8 threads wait on <0x1> | a pipe")])

    def test_ticket_markdown_escapes_pipes_and_names_the_command(self):
        md = sd.ticket_markdown("Title", "ok", [("HIGH", "a | b")], ["Files: 2"], command="playground analyze gc-logs")
        self.assertIn("| 🟠 HIGH | a \\| b |", md)
        self.assertIn("- Files: 2", md)
        self.assertIn("`playground analyze gc-logs`", md)

    def test_embedded_texts_cannot_close_the_script(self):
        block = sd.share_block("t", "a line with </script><!--<script> in it", "## t\n\n| a | </script> |")
        for chunk in block.split("<script type='text/plain'")[1:]:
            text = chunk.split(">", 1)[1].split("</script>", 1)[0]
            self.assertNotIn("<", text)

    def test_given_summary_wins(self):
        page = rh.with_share("<html><head><title>X</title></head><body><p>x</p></body></html>", summary="DIGEST\n")
        self.assertIn("id='pg-share-summary'>DIGEST\n</script>", page)
        self.assertNotIn("id='pg-share-ticket'", page)  # no verdict, no finding: no Markdown

    def test_log_report_and_progress_page_keep_their_own(self):
        # a whole header (.lr-title): the analyze logs report has a dialog of its own, the progress page needs none
        page = rh.page("Log", "<span class='lr-title'>🔥 Log Analysis</span>", [], body_with_findings(), "f")
        self.assertNotIn("share-dlg", page)
        self.assertNotIn("share-dlg", rh.page("x", "y", [], "", "f", share=False))

    def test_brand_page_adds_the_dialog(self):
        page = ("<!doctype html><html><head><title>Bench</title></head><body><header><div><h1>🏎️ B</h1></div>"
                "<button class='theme-toggle'>Toggle theme</button></header><div class=\"card verdict\">🚀 1 records/s</div>"
                "</body></html>")
        out = rh.brand_page(page)
        self.assertEqual(out.count("<dialog class='share-dlg'"), 1)
        self.assertIn("Verdict: 🚀 1 records/s", out)
        self.assertNotIn("share-dlg", rh.brand_page(page, share=False))

    def test_embedded_text_round_trip(self):
        """a \\u003c of the text itself (a Jackson-escaped log line) comes back as it was, never as a live <"""
        import re
        fn = re.search(r'function unembed\(t\) \{ return t\.replace\(/(.*?)/g, .*?\); \}', sd.SHARE_SCRIPT)
        self.assertIsNotNone(fn, "unembed() of the dialog script")
        # the same replacement as the script, in Python (the regex of the script is valid for re as it is)
        js_regex = re.compile(fn.group(1))
        unembed = lambda t: js_regex.sub(lambda m: "<" if m.group(1) == "3c" else "\\", t)  # noqa: E731
        for text in ["thread \\u003cimg src=x onerror=alert(1)// x", "a <b> & </script> <!--<script>",
                     "C:\\path\\u005c\\\\x", "\\u003c\\u005c\\\\u003c"]:
            embedded = sd.embed_text(text)
            self.assertNotIn("<", embedded)
            self.assertEqual(unembed(embedded), text)


if __name__ == "__main__":
    unittest.main()
