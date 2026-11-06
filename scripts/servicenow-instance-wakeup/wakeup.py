"""Wake up a hibernating ServiceNow Personal Developer Instance (PDI).

Logs in to https://developer.servicenow.com with the developer account (ServiceNow ID), opens
"Manage my instance", reads the status of the instance, and, when it is not Online, clicks the
button whose label contains "wake" (and nothing else: never Actions, reset, release or upgrade),
then clicks Refresh until the status is Online.

Run by servicenow_wake_up_instance (scripts/utils.sh) in mcr.microsoft.com/playwright/python:
    USERNAME=... PASSWORD=... python3 wakeup.py <output dir for screenshots> [timeout in seconds]

Exit codes: 0 Online, 1 failure (screenshots and the visible buttons are left in the output dir).
"""
import os
import re
import sys
import time

from playwright.sync_api import sync_playwright

LOGIN_URL = ("https://developer.servicenow.com/userlogin.do?relayState="
             "https%3A%2F%2Fdeveloper.servicenow.com%2Fdev.do%23!%2Fmanage-instance")
MANAGE_URL = "https://developer.servicenow.com/dev.do#!/manage-instance"
# legacy wake up trigger of the old portal, tried as a last resort
LEGACY_WAKE_URL = "https://developer.servicenow.com/dev.do#!/home?wu=true"

# the text of the page, shadow DOMs included (the portal is made of web components)
DEEP_TEXT_JS = """() => {
  const parts = [];
  const walk = (root) => {
    for (const node of root.childNodes) {
      if (node.nodeType === Node.TEXT_NODE) { const t = node.textContent.trim(); if (t) parts.push(t); }
      else if (node.nodeType === Node.ELEMENT_NODE) {
        if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) continue;
        if (node.shadowRoot) walk(node.shadowRoot);
        walk(node);
      }
    }
  };
  walk(document.body);
  return parts.join(' ');
}"""

BUTTONS_JS = """() => {
  const r = [];
  const walk = (root) => {
    root.querySelectorAll('button,a,[role=button]').forEach(e => {
      const t = (e.innerText || '').trim().replace(/\\s+/g, ' ');
      if (t && t.length < 80) r.push(t);
    });
    root.querySelectorAll('*').forEach(e => { if (e.shadowRoot) walk(e.shadowRoot); });
  };
  walk(document);
  return [...new Set(r)];
}"""

STATUS_RE = re.compile(r"\bStatus\s+([A-Za-z][A-Za-z ]{1,30}?)\s+(?:Refresh|Build agent|Wake)", re.S)


def log(msg):
    print(f"🛌 {msg}", flush=True)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp"
    timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    username, password = os.environ.get("USERNAME", ""), os.environ.get("PASSWORD", "")
    if not username or not password:
        log("USERNAME and PASSWORD (developer account) are required")
        return 1

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        ctx = browser.new_context(viewport={"width": 1600, "height": 1100})
        # pre-accept the TrustArc cookie banner, which otherwise covers the page
        expires = int(time.time()) + 180 * 86400
        ctx.add_cookies([{"name": n, "value": v, "domain": ".servicenow.com", "path": "/", "expires": expires}
                         for n, v in [("notice_preferences", "0:"), ("notice_gdpr_prefs", "0:"),
                                      ("cmapi_cookie_privacy", "permit 1 required"),
                                      ("notice_behavior", "implied,eu")]])
        page = ctx.new_page()
        step = [0]

        def snap(name):
            step[0] += 1
            path = f"{out}/servicenow-wakeup-{step[0]:02d}-{name}.png"
            try:
                page.screenshot(path=path)
            except Exception:
                pass
            return path

        def status():
            text = page.evaluate(DEEP_TEXT_JS)
            m = STATUS_RE.search(text)
            return m.group(1).strip() if m else ""

        def fail(msg):
            path = snap("failure")
            log(f"❌ {msg}")
            log(f"url: {page.url}")
            log(f"visible buttons: {' | '.join(page.evaluate(BUTTONS_JS))[:1500]}")
            log(f"screenshot: {path}")
            browser.close()
            return 1

        try:
            log("logging in to https://developer.servicenow.com")
            page.goto(LOGIN_URL, timeout=90000)
            page.wait_for_selector("#username", timeout=90000)
            page.fill("#username", username)
            page.click("#identify-submit")
            page.wait_for_selector("#password", state="visible", timeout=60000)
            page.fill("#password", password)
            page.click("#challenge-authenticator-submit")
            page.wait_for_url(re.compile(r"developer\.servicenow\.com/dev\.do"), timeout=90000)
        except Exception as e:
            return fail(f"login failed (wrong SERVICENOW_DEVELOPER_USERNAME / SERVICENOW_DEVELOPER_PASSWORD, MFA or new login page?): {e}")

        if "manage-instance" not in page.url:
            page.goto(MANAGE_URL, timeout=90000)
        deadline = time.time() + 90
        current = ""
        while time.time() < deadline and not current:
            time.sleep(5)
            current = status()
        if not current:
            return fail("could not read the status of the instance on 'Manage my instance' (portal changed?)")
        log(f"instance status: {current}")
        if current.lower() == "online":
            browser.close()
            return 0

        snap("before-wake")
        wake = page.get_by_role("button", name=re.compile(r"wake", re.I))
        if wake.count() > 0:
            label = " ".join(wake.first.inner_text().split())
            log(f"clicking '{label}'")
            wake.first.click(timeout=15000)
        else:
            log("no button with 'wake' in its label, trying the legacy wake up link")
            page.goto(LEGACY_WAKE_URL, timeout=90000)
            time.sleep(20)
            page.goto(MANAGE_URL, timeout=90000)

        deadline = time.time() + timeout
        while time.time() < deadline:
            time.sleep(20)
            refresh = page.get_by_role("button", name=re.compile(r"^\s*Refresh\s*$", re.I))
            if refresh.count() > 0:
                try:
                    refresh.first.click(timeout=10000)
                    time.sleep(5)
                except Exception:
                    pass
            new = status()
            if new and new != current:
                log(f"instance status: {new}")
                current = new
            if current.lower() == "online":
                snap("online")
                browser.close()
                return 0
        return fail(f"instance still '{current}' after {timeout} seconds")


if __name__ == "__main__":
    sys.exit(main())
