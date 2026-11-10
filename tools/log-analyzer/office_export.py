#!/usr/bin/env python3
"""
Logs a customer sent in an office document, back to log lines for playground analyze logs: a Word (.docx) or
LibreOffice Writer (.odt) document they were pasted in, an Excel (.xlsx) or LibreOffice Calc (.ods) sheet a log tool
exported (Splunk, Kibana, Datadog: time, level, message columns). Standard library only: these files are zips of XML.

  office_export.py <document> <output .log> [<folder for its pictures>]

Prints "<format>\\t<lines or events>\\t<images>" (Word, Writer, Excel export, Excel, Calc export, Calc) and exits 0;
exits 2 when the document holds no text, 1 when it cannot be read. <images>: the pictures inside it (screenshots of a
log, not analyzed).

- Word / Writer: a paragraph is a line, a line break inside it a new line, a tab a tab; the non-breaking spaces of
  Word become spaces. The tables are read cell by cell (a log pasted in a table cell stays a line).
- Excel / Calc: the sheet with the most rows (the others are summaries or pivots); a sheet with the columns of a log
  export (message / log / _raw, time, level…) goes through json_log_export.py (oldest first, the level and logger of
  their columns in front of the message), any other sheet gives its rows as lines (its cells joined by a tab). The
  dates of Excel (days since 1899-12-30, a cell with a date format) become ISO times.
"""

import csv
import os
import re
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from xml.etree import ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json_log_export  # noqa: E402

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"
ODF_TEXT = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"
ODF_TABLE = "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}"
ODF_OFFICE = "{urn:oasis:names:tc:opendocument:xmlns:office:1.0}"
IMAGE_RE = re.compile(r"^(?:word/media|xl/media|ppt/media|Pictures)/.+\.(?:png|jpe?g|gif|bmp|tiff?|emf|wmf|svg|heic)$", re.I)
# a zip of XML: a document of more than this many bytes uncompressed is not read (a zip bomb)
MAX_XML_BYTES = 1024 ** 3
# built-in number formats of Excel that are dates or times
DATE_FORMAT_IDS = set(range(14, 23)) | set(range(27, 37)) | set(range(45, 48)) | set(range(50, 59))


def images(z: zipfile.ZipFile) -> int:
    return sum(1 for n in z.namelist() if IMAGE_RE.match(n))


def extract_images(path: str, folder: str) -> List[str]:
    """the pictures of the document (screenshots of a log) in folder, by their file name only (never a path of the
    zip): the paths written"""
    out = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if not IMAGE_RE.match(info.filename) or info.file_size > MAX_XML_BYTES:
                continue
            os.makedirs(folder, exist_ok=True)
            dest = os.path.join(folder, os.path.basename(info.filename))
            with z.open(info) as src, open(dest, "wb") as dst:
                dst.write(src.read())
            out.append(dest)
    return out


def read_xml(z: zipfile.ZipFile, name: str) -> Optional[ET.Element]:
    try:
        info = z.getinfo(name)
    except KeyError:
        return None
    if info.file_size > MAX_XML_BYTES:
        raise ValueError(f"{name} is {info.file_size} bytes uncompressed")
    with z.open(name) as fh:
        return ET.parse(fh).getroot()


# ── Word ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
def word_lines(root: ET.Element) -> List[str]:
    out: List[str] = []
    for p in root.iter(W + "p"):
        parts: List[str] = []
        for el in p.iter():
            if el.tag == W + "t" and el.text:
                parts.append(el.text)
            elif el.tag == W + "tab":
                parts.append("\t")
            elif el.tag in (W + "br", W + "cr"):
                parts.append("\n")
        out += "".join(parts).replace("\u00a0", " ").split("\n")
    return out


def writer_lines(root: ET.Element) -> List[str]:
    out: List[str] = []

    def text_of(el: ET.Element) -> str:
        parts = [el.text or ""]
        for child in el:
            if child.tag == ODF_TEXT + "s":
                parts.append(" " * int(child.get(ODF_TEXT + "c", "1")))
            elif child.tag == ODF_TEXT + "tab":
                parts.append("\t")
            elif child.tag == ODF_TEXT + "line-break":
                parts.append("\n")
            else:
                parts.append(text_of(child))
            parts.append(child.tail or "")
        return "".join(parts)
    for el in root.iter():
        if el.tag in (ODF_TEXT + "p", ODF_TEXT + "h"):
            out += text_of(el).replace("\u00a0", " ").split("\n")
    return out


# ── Excel ────────────────────────────────────────────────────────────────────────────────────────────────────────────
# the last column of Excel (XFD): a crafted cell reference (r="ZZZZZZZZZZ1") made a row of 10^14 cells
MAX_COLUMNS = 16384


def col_index(ref: str) -> int:
    n = 0
    for ch in ref:
        if not ("A" <= ch.upper() <= "Z"):
            break
        n = n * 26 + ord(ch.upper()) - 64
        if n > MAX_COLUMNS:
            return MAX_COLUMNS - 1
    return n - 1


def date_styles(z: zipfile.ZipFile) -> set:
    """the indexes of the cell formats (s="…" of a cell) that show a date or a time"""
    root = read_xml(z, "xl/styles.xml")
    if root is None:
        return set()
    custom: Dict[int, bool] = {}
    for f in root.iter(S + "numFmt"):
        code = re.sub(r'"[^"]*"|\[[^\]]*\]|\\.', "", f.get("formatCode", "")).lower()
        custom[int(f.get("numFmtId", "0"))] = bool(re.search(r"[ydh]|m.*s|s.*m", code)) and "0.0" not in code
    out = set()
    xfs = root.find(S + "cellXfs")
    for i, xf in enumerate(xfs if xfs is not None else []):
        fid = int(xf.get("numFmtId", "0"))
        if fid in DATE_FORMAT_IDS or custom.get(fid):
            out.add(i)
    return out


def excel_time(value: float, date1904: bool) -> str:
    base = datetime(1904, 1, 1) if date1904 else datetime(1899, 12, 30)
    t = base + timedelta(days=value)
    return t.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] if value % 1 else t.strftime("%Y-%m-%d")


def excel_sheets(z: zipfile.ZipFile) -> List[List[List[str]]]:
    shared: List[str] = []
    root = read_xml(z, "xl/sharedStrings.xml")
    if root is not None:
        for si in root.iter(S + "si"):
            shared.append("".join(t.text or "" for t in si.iter(S + "t")))
    workbook = read_xml(z, "xl/workbook.xml")
    date1904 = workbook is not None and any(p.get("date1904") in ("1", "true") for p in workbook.iter(S + "workbookPr"))
    rels = read_xml(z, "xl/_rels/workbook.xml.rels")
    targets = {r.get("Id"): r.get("Target") for r in (rels.iter(REL + "Relationship") if rels is not None else [])}
    names = []
    for sh in (workbook.iter(S + "sheet") if workbook is not None else []):
        target = targets.get(sh.get(R + "id"), "")
        names.append("xl/" + target.lstrip("/").replace("xl/", "", 1) if target else "")
    if not any(names):
        names = sorted(n for n in z.namelist() if re.match(r"xl/worksheets/sheet\d+\.xml$", n))
    dates = date_styles(z)
    sheets = []
    for name in names:
        root = read_xml(z, name) if name else None
        if root is None:
            continue
        rows: List[List[str]] = []
        for row in root.iter(S + "row"):
            cells: Dict[int, str] = {}
            for i, c in enumerate(row.iter(S + "c")):
                kind, v = c.get("t"), c.find(S + "v")
                if kind == "inlineStr":
                    value = "".join(t.text or "" for t in c.iter(S + "t"))
                elif v is None or v.text is None:
                    continue
                elif kind == "s":
                    value = shared[int(v.text)] if v.text.isdigit() and int(v.text) < len(shared) else ""
                elif kind in ("str", "e", "b"):
                    value = v.text
                else:
                    value = v.text
                    if c.get("s") and int(c.get("s")) in dates:
                        try:
                            value = excel_time(float(v.text), date1904)
                        except ValueError:
                            pass
                cells[col_index(c.get("r", "")) if c.get("r") else i] = value
            if cells:
                width = max(cells) + 1
                rows.append([cells.get(k, "") for k in range(width)])
        sheets.append(rows)
    return sheets


def calc_sheets(root: ET.Element) -> List[List[List[str]]]:
    sheets = []
    for table in root.iter(ODF_TABLE + "table"):
        rows = []
        for row in table.iter(ODF_TABLE + "table-row"):
            cells: List[str] = []
            for cell in row:
                if cell.tag not in (ODF_TABLE + "table-cell", ODF_TABLE + "covered-table-cell"):
                    continue
                value = cell.get(ODF_OFFICE + "date-value") or "\n".join(
                    "".join(p.itertext()) for p in cell.iter(ODF_TEXT + "p"))
                repeat = min(int(cell.get(ODF_TABLE + "number-columns-repeated", "1")), 50)
                cells += [value] * repeat
            while cells and not cells[-1]:
                cells.pop()
            if cells:
                rows.append(cells)
        sheets.append(rows)
    return sheets


def sheet_to_log(rows: List[List[str]], out: str) -> Tuple[bool, int]:
    """(export, count): a log export through json_log_export (its header names the message column), else every row
    as a line, its non empty cells joined by a tab"""
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8", newline="") as tmp:
        csv.writer(tmp).writerows(rows)
    try:
        nb = json_log_export.write_events(json_log_export.events_of(json_log_export.load_csv(tmp.name)), out)
    finally:
        os.unlink(tmp.name)
    if nb:
        return True, nb
    lines = ["\t".join(c for c in r if c != "") for r in rows]
    lines = [x for x in lines if x.strip()]
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + ("\n" if lines else ""))
    return False, len(lines)


def convert(path: str, out: str) -> Tuple[str, int, int]:
    """(format, lines or events, images)"""
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        pictures = images(z)
        if "word/document.xml" in names:
            lines = word_lines(read_xml(z, "word/document.xml"))
            fmt = "Word"
        elif "xl/workbook.xml" in names:
            sheets = excel_sheets(z)
            rows = max(sheets, key=len) if sheets else []
            export, nb = sheet_to_log(rows, out)
            return ("Excel export" if export else "Excel"), nb, pictures
        elif "content.xml" in names:
            content = read_xml(z, "content.xml")
            mime = z.read("mimetype").decode("ascii", "replace") if "mimetype" in names else ""
            if "spreadsheet" in mime:
                sheets = calc_sheets(content)
                rows = max(sheets, key=len) if sheets else []
                export, nb = sheet_to_log(rows, out)
                return ("Calc export" if export else "Calc"), nb, pictures
            lines = writer_lines(content)
            fmt = "Writer"
        else:
            raise ValueError("not a Word, Excel, Writer or Calc document")
    # the empty paragraphs between blocks of a pasted log are kept (they are blank lines of the log), not at the ends
    while lines and not lines[-1].strip():
        lines.pop()
    while lines and not lines[0].strip():
        lines.pop(0)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + ("\n" if lines else ""))
    return fmt, sum(1 for x in lines if x.strip()), pictures


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 1
    try:
        fmt, nb, pictures = convert(sys.argv[1], sys.argv[2])
        if pictures and len(sys.argv) == 4:
            extract_images(sys.argv[1], sys.argv[3])
    except (OSError, zipfile.BadZipFile, ET.ParseError, ValueError, KeyError) as ex:
        print(f"cannot read {sys.argv[1]}: {ex}", file=sys.stderr)
        return 1
    print(f"{fmt}\t{nb}\t{pictures}")
    return 0 if nb else 2


if __name__ == "__main__":
    sys.exit(main())
