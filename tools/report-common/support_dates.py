"""
End of support of Confluent Platform and Confluent for Kubernetes versions, for playground analyze logs (🏷️ CP and 🛠️ CFK
tiles, the summary, the summary for a ticket): a version past its end of support is marked.

Copied from the tables of the docs (update them with each release):
  CP:  https://docs.confluent.io/platform/current/installation/versions-interoperability.html (Supported versions)
  CFK: https://docs.confluent.io/operator/current/co-supported-environments.html (Standard End of Support)
A version older than the oldest row of a table is out of support (the docs drop it).
"""

from datetime import date, datetime
from typing import Dict, Optional, Tuple

FETCHED = "2026-11-07"
CP_DOC = "https://docs.confluent.io/platform/current/installation/versions-interoperability.html"
CFK_DOC = "https://docs.confluent.io/operator/current/co-supported-environments.html"

# minor: (release date, Confluent Community Software end of support, Enterprise Standard, Enterprise Platinum)
CP_SUPPORT = {
    "8.4": ("2026-10-27", "2027-10-27", "2028-10-27", "2029-10-27"),
    "8.3": ("2026-06-17", "2027-06-17", "2028-06-17", "2029-06-17"),
    "8.2": ("2026-03-04", "2027-03-04", "2028-03-04", "2029-03-04"),
    "8.1": ("2025-10-15", "2026-10-15", "2027-10-15", "2028-10-15"),
    "8.0": ("2025-06-11", "2026-06-11", "2027-06-11", "2028-06-11"),
    "7.9": ("2025-02-19", "2027-02-19", "2027-02-19", "2028-02-19"),
    "7.8": ("2024-12-02", "2026-12-02", "2026-12-02", "2027-12-02"),
    "7.7": ("2024-07-26", "2026-07-26", "2026-07-26", "2027-07-26"),
    "7.6": ("2024-02-09", "2026-02-09", "2026-02-09", "2027-02-09"),
}
# minor: (release date, Standard end of support)
CFK_SUPPORT = {
    "3.4": ("2026-10-28", "2028-10-28"),
    "3.3": ("2026-06-23", "2028-06-23"),
    "3.2": ("2026-03-11", "2028-03-11"),
    "3.1": ("2025-10-15", "2027-10-15"),
    "3.0": ("2025-06-13", "2027-06-13"),
    "2.11": ("2025-02-21", "2027-02-21"),
    "2.10": ("2024-12-04", "2026-12-04"),
}
# support ending within this many days: ⏳
SOON_DAYS = 180


def _minor(version: str) -> Optional[Tuple[int, int]]:
    parts = (version or "").lstrip("v").split(".")
    try:
        return int(parts[0]), int(parts[1])
    except (IndexError, ValueError):
        return None


def _d(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def _status(version: str, table: Dict[str, tuple], dates: Tuple[int, int], what: str, today: Optional[date]) -> dict:
    """state: supported | ending | standard_ended | ended | unknown; text: the short line for a tile"""
    today = today or date.today()
    m = _minor(version)
    if not m:
        return {"state": "unknown", "text": ""}
    key = f"{m[0]}.{m[1]}"
    known = sorted((_minor(k), k) for k in table)
    if key not in table:
        if m < known[0][0]:
            return {"state": "ended", "text": f"⛔ end of support: older than {known[0][1]}, the oldest {what} the docs still support"}
        return {"state": "unknown", "text": ""}
    row = table[key]
    standard, last = _d(row[dates[0]]), _d(row[dates[1]])
    if today > last:
        return {"state": "ended", "text": f"⛔ end of support since {last.isoformat()}", "until": last.isoformat()}
    if today > standard:
        return {"state": "standard_ended", "text": f"⚠️ Standard support ended {standard.isoformat()}, Platinum until {last.isoformat()}",
                "until": last.isoformat()}
    if (standard - today).days <= SOON_DAYS:
        return {"state": "ending", "text": f"⏳ support ends {standard.isoformat()}", "until": standard.isoformat()}
    return {"state": "supported", "text": f"supported until {standard.isoformat()}", "until": standard.isoformat()}


def cp_status(version: str, today: Optional[date] = None) -> dict:
    """a Confluent Platform version (8.1.0, 7.6.3): Enterprise Standard end of support, then Platinum"""
    return _status(version, CP_SUPPORT, (2, 3), "Confluent Platform version", today)


def cfk_status(version: str, today: Optional[date] = None) -> dict:
    """a CFK operator version (3.1.0): Standard end of support (no extended support in the table)"""
    return _status(version, CFK_SUPPORT, (1, 1), "CFK version", today)


TILE_CLASS = {"ended": "danger", "standard_ended": "warn", "ending": "warn", "supported": "", "unknown": ""}
