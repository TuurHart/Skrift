#!/usr/bin/env python3
"""Byte-stable synthetic ePub fixtures (no real books). Run: python3 generate.py

skip-report.epub (C289, EpubSkipReportTests):
  cover.xhtml     image only, well-formed            -> read, no text, NOT a skip
  chapter1.xhtml  fine                               -> read
  chapter2.xhtml  bytes flipped after zipping (CRC)  -> skipped: damaged inside the ePub file
  chapter3.xhtml  malformed XML (unclosed tags)      -> read by the lenient pass
  chapter4.xhtml  in the manifest, not in the zip    -> skipped: missing from the ePub file
  idref "ghost"   in the spine, not in the manifest  -> skipped: missing from the manifest
"""
import zipfile, os

HERE = os.path.dirname(os.path.abspath(__file__))
STAMP = (2026, 10, 23, 0, 0, 0)

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

OPF = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>The Skip Report</dc:title></metadata>
<manifest>
<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
<item id="c3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
<item id="c4" href="chapter4.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine><itemref idref="cover"/><itemref idref="c1"/><itemref idref="c2"/><itemref idref="ghost"/><itemref idref="c3"/><itemref idref="c4"/></spine>
</package>"""

def page(body):
    return f'<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><body>{body}</body></html>'

FILES = [
    ("mimetype", "application/epub+zip"),
    ("META-INF/container.xml", CONTAINER),
    ("OEBPS/content.opf", OPF),
    ("OEBPS/cover.xhtml", page('<img src="cover.png" alt=""/>')),
    ("OEBPS/chapter1.xhtml", page("<h1>Chapter One</h1><p>The lighthouse keeper counted every ship that passed.</p>")),
    ("OEBPS/chapter2.xhtml", page("<h1>Chapter Two</h1><p>DAMAGEDMARKER the harbour froze over that winter.</p>")),
    ("OEBPS/chapter3.xhtml", '<html><body><h1>Chapter Three<p>Spring came late &nbsp; and the boats went out again.<p>The end.</body>'),
]

def build(name, files, corrupt_marker=None):
    path = os.path.join(HERE, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        for arc, text in files:
            info = zipfile.ZipInfo(arc, date_time=STAMP)
            info.compress_type = zipfile.ZIP_STORED
            z.writestr(info, text.encode("utf-8"))
    if corrupt_marker:
        data = bytearray(open(path, "rb").read())
        i = data.index(corrupt_marker.encode())
        data[i:i + len(corrupt_marker)] = b"X" * len(corrupt_marker)
        open(path, "wb").write(bytes(data))

build("skip-report.epub", FILES, corrupt_marker="DAMAGEDMARKER")
print("wrote skip-report.epub")
