#!/usr/bin/env python3
"""Q458 (D213): generate the real-shaped PDF reading fixtures. Synthetic, fictional text only.

    python3 test-fixtures/pdf/generate.py

Writes into this directory, for each fixture <name>:
  <name>.pdf        the PDF
  <name>.expect.md  the reading text a careful human wants: order, `#`/`##` headings, a figure's
                    place as `[figure: caption]`, a table as `| a | b |` rows, no headers/footers
and fixtures.json: per fixture, the running header/footer/page-number strings that must not
reach the reading view (`leaks`). Output is byte-stable (reportlab invariant mode).

Needs reportlab and Pillow (pip install reportlab pillow).
"""
import io
import json
import os
import re

from reportlab import rl_config

rl_config.invariant = 1  # no timestamps or random ids: same bytes every run

from PIL import Image, ImageDraw, ImageFont
from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4, LETTER
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as pdfcanvas
from reportlab.platypus import (BaseDocTemplate, Frame, FrameBreak, NextPageTemplate, PageTemplate,
                                Paragraph, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))

BODY = ParagraphStyle("body", fontName="Times-Roman", fontSize=10.5, leading=13.5, alignment=TA_JUSTIFY,
                      spaceAfter=6)
H1 = ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=17, leading=21, alignment=TA_CENTER, spaceAfter=6)
H2 = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=12, leading=15, spaceBefore=6, spaceAfter=4)
BYLINE = ParagraphStyle("byline", fontName="Times-Italic", fontSize=11, leading=14, alignment=TA_CENTER,
                        spaceAfter=10)
CAPTION = ParagraphStyle("caption", fontName="Times-Italic", fontSize=9.5, leading=12, alignment=TA_CENTER,
                         spaceBefore=4, spaceAfter=10)


# Content is a list of (kind, text) with kind in h1, h2, byline, p, figure, row.
def expect_md(content):
    out = []
    for kind, text in content:
        if kind == "h1":
            out.append("# " + text)
        elif kind == "h2":
            out.append("## " + text)
        elif kind == "figure":
            out.append("[figure: " + text + "]")
        elif kind == "row":
            out.append("| " + " | ".join(text) + " |")
        else:
            out.append(text)
    # Table rows sit on consecutive lines; everything else is a paragraph of its own.
    md = ""
    for i, line in enumerate(out):
        if i > 0:
            md += "\n" if (content[i][0] == "row" and content[i - 1][0] == "row") else "\n\n"
        md += line
    return md + "\n"


def flowables(content, figure=None, table_style=None):
    styles = {"h1": H1, "h2": H2, "byline": BYLINE, "p": BODY}
    out, rows = [], []

    def flush_rows():
        if rows:
            t = Table(list(rows), hAlign="CENTER")
            t.setStyle(table_style)
            out.append(t)
            out.append(Spacer(1, 10))
            rows.clear()

    for kind, text in content:
        if kind == "row":
            rows.append(text)
            continue
        flush_rows()
        if kind == "figure":
            out.append(figure)
            out.append(Paragraph(text, CAPTION))
        else:
            out.append(Paragraph(text, styles[kind]))
    flush_rows()
    return out


def check_leaks(name, content, leaks):
    text = " ".join(t if isinstance(t, str) else " ".join(t) for _, t in content)
    for leak in leaks:
        if re.search(r"(?<!\w)" + re.escape(leak) + r"(?!\w)", text):
            raise SystemExit(f"{name}: leak string {leak!r} also occurs in the body text")


def write(name, content, leaks):
    check_leaks(name, content, leaks)
    with open(os.path.join(HERE, name + ".expect.md"), "w") as f:
        f.write(expect_md(content))
    return {"leaks": leaks}


# ---------------------------------------------------------------------------------------------
# 1. Two-column paper: full-width title block, two columns, running head + page number.

PAPER = [
    ("h1", "Tidal Drift in Low-Cost Harbour Sensors"),
    ("byline", "Mira Okafor and Jonas Velde, Institute for Coastal Instruments"),
    ("h2", "Abstract"),
    ("p", "Cheap pressure sensors are now common in small harbours, but their readings wander over "
          "weeks. We logged eleven units beside a reference gauge for one winter and describe how the "
          "drift grows with water temperature, how much of it a weekly zero check removes, and what "
          "remains that only a second sensor can catch."),
    ("h2", "1 Introduction"),
    ("p", "A harbour master wants to know the water level at the quay, not the level at a tide station "
          "twenty kilometres away. Small pressure loggers make that possible for the price of a good "
          "pair of boots. The trouble starts after the first month, when a logger that agreed with the "
          "reference to a centimetre begins to read high on cold mornings and low after a warm spell."),
    ("p", "Earlier work blamed the drift on fouling of the sensor port. Our loggers were cleaned every "
          "week, so fouling cannot explain what we saw. The pattern follows the water temperature "
          "instead, with a lag of about two days that matches the time the housing takes to settle."),
    ("h2", "2 Methods"),
    ("p", "Eleven loggers of three makes were tied to the same ladder as the reference gauge at the "
          "north quay. Each recorded pressure and temperature every ten minutes from November to March. "
          "A diver checked the ports each Monday and noted any growth, which stayed light all season."),
    ("p", "We removed the air pressure using the harbour weather mast, then compared each logger with "
          "the reference over sliding windows of one week. A logger's drift is the slope of that "
          "difference against time, and its temperature response is the slope against the mean water "
          "temperature over the previous two days."),
    ("h2", "3 Results"),
    ("p", "Every logger drifted, the worst by nine centimetres over the winter and the best by under "
          "two. Nearly all of the drift tracked temperature: a cold week pushed the readings up and a "
          "mild week pulled them back. A weekly zero check against the reference removed most of the "
          "error, leaving a residual that rarely passed one centimetre."),
    ("p", "One unit behaved differently. Its error rose steadily whatever the weather, and the zero "
          "check hid the trend until the diver found a cracked seal in February. Only the comparison "
          "with a second logger on the same ladder had shown it early."),
    ("h2", "4 Discussion"),
    ("p", "For a small harbour the lesson is simple. Correct for temperature, check the zero once a "
          "week, and hang two loggers rather than one. The second unit costs little and turns a slow "
          "silent failure into an obvious disagreement that anyone on the quay can see."),
    ("p", "There is a cost to the second logger beyond its price. Someone has to read both records, "
          "notice when they part, and decide which one to trust. In our harbour that job fell to the "
          "volunteer who already checked the tide board each evening, and it added a few minutes to "
          "the round. Where nobody has those minutes, a simple alarm on the difference between the "
          "two units would do the same work, and we sketch one in the appendix."),
    ("p", "The temperature correction itself is cheap to apply. Each logger already records the "
          "water temperature, so the correction needs no extra hardware, only a coefficient fitted "
          "over the first fortnight beside a reference. We found that coefficient stable across the "
          "winter for every unit of the same make, which means a harbour could fit it once for a "
          "batch rather than for every logger it buys."),
    ("h2", "5 Conclusion"),
    ("p", "Low-cost loggers can watch a small harbour well enough for daily use, provided their drift "
          "is treated as a known habit rather than a fault. Fit a temperature coefficient, zero the "
          "units weekly, and compare two of them, and the remaining error stays near one centimetre."),
    ("p", "We did not test summer conditions, when warm water and heavy growth may change the picture, "
          "and we plan to repeat the study from June with the same ladder and the same divers."),
]
PAPER_HEAD = "Journal of Quiet Harbours 7 (2025)"
PAPER_FOLIOS = ["113", "114", "115"]


def paper():
    path = os.path.join(HERE, "two-column-paper.pdf")
    w, h = A4
    margin, gap = 0.75 * inch, 0.3 * inch
    col_w = (w - 2 * margin - gap) / 2
    title_h = 2.5 * inch
    body_top = h - margin - 0.2 * inch

    def decorate(c, doc):
        c.saveState()
        c.setFont("Helvetica", 8.5)
        c.drawString(margin, h - 0.5 * inch, PAPER_HEAD)
        c.drawRightString(w - margin, h - 0.5 * inch, "Okafor and Velde")
        c.drawCentredString(w / 2, 0.5 * inch, PAPER_FOLIOS[doc.page - 1])
        c.restoreState()

    col_h_first = body_top - title_h - margin
    first = [Frame(margin, h - margin - 0.2 * inch - title_h, w - 2 * margin, title_h, id="title"),
             Frame(margin, margin, col_w, col_h_first, id="c1"),
             Frame(margin + col_w + gap, margin, col_w, col_h_first, id="c2")]
    later = [Frame(margin, margin, col_w, body_top - margin, id="c1"),
             Frame(margin + col_w + gap, margin, col_w, body_top - margin, id="c2")]
    doc = BaseDocTemplate(path, pagesize=A4, title="Tidal Drift in Low-Cost Harbour Sensors", author="Fixture",
                          creator="Skrift test fixture")
    doc.addPageTemplates([PageTemplate("first", first, onPage=decorate),
                          PageTemplate("later", later, onPage=decorate)])
    story = [NextPageTemplate("later")]
    fl = flowables(PAPER)
    story += fl[:4] + [FrameBreak()] + fl[4:]  # title, byline, abstract heading + text full width
    doc.build(story)
    assert doc.page == 2, f"paper should be 2 pages, got {doc.page}"
    leaks = [PAPER_HEAD, "Okafor and Velde"] + PAPER_FOLIOS[:doc.page]
    return write("two-column-paper", PAPER, leaks)


# ---------------------------------------------------------------------------------------------
# 2. Report: single column, running header both sides, "Page N of M" footer, a paragraph that
#    crosses a page break.

REPORT = [
    ("h1", "North Quay Survey: Annual Report"),
    ("h2", "Summary"),
    ("p", "The north quay survey ran for its third full year. Visits rose, the new ladder held up "
          "through two storms, and the volunteer rota covered every weekend but one. This report "
          "sets out what was measured, what went wrong, and what the board is asked to approve for "
          "the coming season."),
    ("h2", "Visits and rota"),
    ("p", "Volunteers logged four hundred and twelve visits, up from three hundred and sixty the year "
          "before. Most of the growth came on weekday evenings after the lighting was repaired in "
          "April. The rota relied on a core of nine people; two of them carried almost a third of all "
          "shifts, which the board should treat as a risk rather than a strength."),
    ("p", "The one missed weekend fell in August, when three volunteers were away at once and the "
          "standby list had not been kept up to date. A shared calendar with a named standby for each "
          "month would have caught the gap a fortnight in advance."),
    ("h2", "Equipment"),
    ("p", "The ladder installed last spring came through the October and January storms without "
          "damage. The older railing on the east steps did not: two posts worked loose and were tied "
          "off until the council crew could replace them. The tide board was repainted in June and "
          "remains easy to read from the car park. The logbook box leaked twice and its contents were "
          "dried out by hand both times, so a new sealed box is part of this year's request."),
    ("p", "The survey's two pressure loggers were swapped in rotation every month and cleaned before "
          "each deployment. Neither unit failed. Their records agree with the paper log to within a few "
          "centimetres on every day both were read, which is better than the survey needs for its own "
          "purposes and good enough to share with the harbour office."),
    ("h2", "Money"),
    ("p", "Spending stayed inside the agreed budget. The largest single cost was the ladder, paid in "
          "the previous year and now fully depreciated in the accounts. Paint, rope and the replacement "
          "logbook pages came to a little under the allowance for consumables, and the small surplus is "
          "carried forward rather than returned."),
    ("h2", "Requests to the board"),
    ("p", "The survey asks the board to approve a sealed logbook box, a shared rota calendar with a "
          "named monthly standby, and a modest training evening in March so that newer volunteers can "
          "read the tide board and the loggers without help. None of these needs new money beyond the "
          "surplus already carried forward."),
    ("p", "The survey also asks the board to raise the east railing with the council again before the "
          "autumn storms, since the temporary ties will not last another winter on their own."),
]
REPORT_HEAD_L, REPORT_HEAD_R = "Harbour Survey Annual Report 2025", "Draft for board review"


def report():
    path = os.path.join(HERE, "report-headers.pdf")
    w, h = LETTER
    margin = 1.25 * inch
    style = ParagraphStyle("report", parent=BODY, fontSize=12, leading=17, spaceAfter=8)
    pages = {"total": 0}

    def decorate(c, doc):
        c.saveState()
        c.setFont("Helvetica", 9)
        c.drawString(margin, h - 0.6 * inch, REPORT_HEAD_L)
        c.drawRightString(w - margin, h - 0.6 * inch, REPORT_HEAD_R)
        c.setLineWidth(0.4)
        c.line(margin, h - 0.68 * inch, w - margin, h - 0.68 * inch)
        c.drawCentredString(w / 2, 0.55 * inch, f"Page {doc.page} of {pages['total']}")
        c.restoreState()

    def build(target):
        frame = Frame(margin, 1.0 * inch, w - 2 * margin, h - 2.0 * inch, id="body")
        doc = BaseDocTemplate(target, pagesize=LETTER, title="North Quay Survey", author="Fixture",
                              creator="Skrift test fixture")
        doc.addPageTemplates([PageTemplate("p", [frame], onPage=decorate)])
        fl = [Paragraph(t, style) if k == "p" else f for (k, t), f in zip(REPORT, flowables(REPORT))]
        doc.build(fl)
        return doc.page

    pages["total"] = build(io.BytesIO())  # first pass counts the pages for "Page N of M"
    assert build(path) == pages["total"] >= 2, "report should run over at least 2 pages"
    total = pages["total"]
    leaks = [REPORT_HEAD_L, REPORT_HEAD_R] + [f"Page {i} of {total}" for i in range(1, total + 1)]
    return write("report-headers", REPORT, leaks)


# ---------------------------------------------------------------------------------------------
# 3. A figure with labels inside it and a caption below, between two paragraphs.

FIGURE_CAPTION = "Figure 1. Monthly visits to the north pier in 2025, counted from the volunteer logbook."
FIGURE = [
    ("h2", "Visits through the year"),
    ("p", "Visits follow the light more than the weather. The count climbs from February as the evenings "
          "lengthen, holds through the summer, and falls away quickly once the clocks change in October. "
          "The dip in August is the missed weekend described in the rota section, not a quiet month."),
    ("figure", FIGURE_CAPTION),
    ("p", "The winter months are thin but never empty. A handful of regular walkers come down to the pier "
          "whatever the conditions, and their visits alone keep the logbook from going a week without an "
          "entry. Any plan to close the pier for repairs should avoid the long summer weekends and aim for "
          "the first weeks of the year instead."),
]


def bar_chart():
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    values = [14, 19, 27, 36, 44, 49, 51, 33, 45, 31, 17, 12]
    d = Drawing(6.0 * inch, 2.6 * inch)
    x0, y0, plot_w, plot_h = 0.6 * inch, 0.4 * inch, 5.2 * inch, 2.0 * inch
    d.add(Line(x0, y0, x0 + plot_w, y0, strokeColor=colors.black))
    d.add(Line(x0, y0, x0, y0 + plot_h, strokeColor=colors.black))
    for tick in (0, 20, 40, 60):
        y = y0 + plot_h * tick / 60
        d.add(Line(x0 - 3, y, x0, y, strokeColor=colors.black))
        d.add(String(x0 - 6, y - 3, str(tick), fontName="Helvetica", fontSize=7, textAnchor="end"))
    bw = plot_w / len(months)
    for i, (m, v) in enumerate(zip(months, values)):
        bx = x0 + i * bw + bw * 0.15
        d.add(Rect(bx, y0, bw * 0.7, plot_h * v / 60, fillColor=colors.HexColor("#5a7fa8"), strokeColor=None))
        d.add(String(bx + bw * 0.35, y0 - 11, m, fontName="Helvetica", fontSize=7, textAnchor="middle"))
    d.add(String(x0 - 30, y0 + plot_h + 6, "Visits", fontName="Helvetica", fontSize=7))
    return d


def figure():
    path = os.path.join(HERE, "figure-caption.pdf")
    w, h = LETTER
    margin = 1.1 * inch
    frame = Frame(margin, margin, w - 2 * margin, h - 2 * margin, id="body")
    doc = BaseDocTemplate(path, pagesize=LETTER, title="Visits", author="Fixture", creator="Skrift test fixture")
    doc.addPageTemplates([PageTemplate("p", [frame])])
    doc.build(flowables(FIGURE, figure=bar_chart()))
    assert doc.page == 1
    return write("figure-caption", FIGURE, [])


# ---------------------------------------------------------------------------------------------
# 4. A 5-column table between paragraphs.

TABLE = [
    ("h2", "Site costs for the season"),
    ("p", "The table below lists each survey site with its visits, the volunteer hours it took, what it "
          "cost to keep running, and a short note on its state at the end of the season."),
    ("row", ["Site", "Visits", "Hours", "Cost (EUR)", "Notes"]),
    ("row", ["North quay", "412", "690", "1,840", "Ladder sound"]),
    ("row", ["East steps", "158", "240", "2,310", "Railing loose"]),
    ("row", ["Fish market", "96", "130", "420", "Board faded"]),
    ("row", ["Old slipway", "71", "115", "380", "Logbook wet"]),
    ("row", ["South mole", "203", "305", "960", "Light repaired"]),
    ("row", ["Total", "940", "1,480", "5,910", "Within budget"]),
    ("p", "The east steps cost the most for the fewest visits because of the railing repairs, and should "
          "fall back into line once the council replaces the posts. Every other site came in under its "
          "share of the allowance."),
]


def table():
    path = os.path.join(HERE, "table-5col.pdf")
    w, h = LETTER
    margin = 1.1 * inch
    frame = Frame(margin, margin, w - 2 * margin, h - 2 * margin, id="body")
    style = TableStyle([
        ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 9.5),
        ("FONT", (0, 1), (-1, -1), "Helvetica", 9.5),
        ("FONT", (0, -1), (-1, -1), "Helvetica-Bold", 9.5),
        ("ALIGN", (1, 0), (3, -1), "RIGHT"),
        ("LINEABOVE", (0, 0), (-1, 0), 0.8, colors.black),
        ("LINEBELOW", (0, 0), (-1, 0), 0.5, colors.black),
        ("LINEABOVE", (0, -1), (-1, -1), 0.5, colors.black),
        ("LINEBELOW", (0, -1), (-1, -1), 0.8, colors.black),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ])
    doc = BaseDocTemplate(path, pagesize=LETTER, title="Site costs", author="Fixture", creator="Skrift test fixture")
    doc.addPageTemplates([PageTemplate("p", [frame])])
    doc.build(flowables(TABLE, table_style=style))
    assert doc.page == 1
    return write("table-5col", TABLE, [])


# ---------------------------------------------------------------------------------------------
# 5. Scanned page: the text exists only as pixels in an image, no text layer at all.

SCAN = [
    ("h2", "Letter to the harbour office"),
    ("p", "Dear harbour office, we write on behalf of the north quay survey to ask whether the council "
          "crew could look at the east steps before the autumn storms. Two railing posts worked loose in "
          "January and are held only by rope ties."),
    ("p", "The survey has kept a daily log of the water level at the quay for three years and would be "
          "glad to share it with your office. The readings agree with the harbour gauge to within a few "
          "centimetres and may help when planning the repairs."),
    ("p", "With thanks from the volunteers of the north quay survey."),
]


def wrap(draw, text, font, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=font) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def scan():
    path = os.path.join(HERE, "scanned-page.pdf")
    dpi = 150
    pw, ph = int(8.5 * dpi), int(11 * dpi)
    img = Image.new("L", (pw, ph), 246)  # off-white paper
    draw = ImageDraw.Draw(img)
    body = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman.ttf", 30)
    bold = ImageFont.truetype("/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf", 38)
    x, y, width = int(1.1 * dpi), int(1.3 * dpi), pw - int(2.2 * dpi)
    for kind, text in SCAN:
        font = bold if kind == "h2" else body
        for line in wrap(draw, text, font, width):
            draw.text((x, y), line, font=font, fill=28)
            y += int(font.size * 1.35)
        y += int(body.size * 0.9)
    img = img.rotate(0.6, resample=Image.BICUBIC, fillcolor=246)  # a slightly crooked scan
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    buf.seek(0)
    c = pdfcanvas.Canvas(path, pagesize=LETTER, invariant=1)
    c.setTitle("Scan")
    c.setCreator("Skrift test fixture")
    c.drawImage(ImageReader(buf), 0, 0, width=LETTER[0], height=LETTER[1])
    c.showPage()
    c.save()
    return write("scanned-page", SCAN, [])


# ---------------------------------------------------------------------------------------------
# 6. Control: a plain single-column book page pair, no running heads, no page numbers.

BOOK = [
    ("h1", "Chapter Three"),
    ("h2", "The Keeper's Ledger"),
    ("p", "The ledger lived on a shelf above the stove, where the damp could not reach it. Every evening "
          "Ana took it down, wiped her hands on her apron, and wrote the day in the same square letters "
          "her father had taught her: the wind, the sea, the ships that passed, and anything that broke."),
    ("p", "Most days there was little to write. A trawler going out before dawn, the same trawler coming "
          "back with the gulls behind it, a wind that backed to the west by noon. She liked those days "
          "best. The pages filled slowly and evenly, like a tide coming in over flat sand."),
    ("p", "It was on one of those quiet evenings that she noticed the gap. Three days in the spring of "
          "the year before were missing, not torn out but simply never written, and the next entry began "
          "in a hand she did not know. Someone else had kept the light while her father was away, and "
          "nobody had ever told her who."),
    ("p", "She sat with the ledger open on her knees until the lamp needed trimming. Then she climbed the "
          "stairs, saw to the light, and came down again to read the strange entries one more time, "
          "slowly, as if the handwriting itself might give up a name."),
    ("p", "The stranger wrote small and leaned hard on the pen. Where her father noted a ship by its name "
          "and nothing more, this keeper had added the colour of its hull, the number of men on deck, and "
          "once, in the margin, a single line about a woman waving from the stern of a ferry. Ana read "
          "that line four times before she closed the book and put it back on the shelf above the stove."),
]


def book():
    path = os.path.join(HERE, "book-page.pdf")
    size = (5 * inch, 8 * inch)
    margin = 0.6 * inch
    frame = Frame(margin, margin, size[0] - 2 * margin, size[1] - 2 * margin, id="body")
    doc = BaseDocTemplate(path, pagesize=size, title="Chapter Three", author="Fixture", creator="Skrift test fixture")
    doc.addPageTemplates([PageTemplate("p", [frame])])
    style = ParagraphStyle("book", parent=BODY, fontName="Times-Roman", fontSize=12, leading=16,
                           firstLineIndent=14, spaceAfter=2)
    doc.build([Paragraph(t, style) if k == "p" else f for (k, t), f in zip(BOOK, flowables(BOOK))])
    assert doc.page == 2, f"book should be 2 pages, got {doc.page}"
    return write("book-page", BOOK, [])


def main():
    manifest = {
        "_schema": "fixture -> {leaks: strings (running header, footer, page number) that must not "
                   "appear in the reading view}. Written by generate.py.",
    }
    for name, fn in [("two-column-paper", paper), ("report-headers", report), ("figure-caption", figure),
                     ("table-5col", table), ("scanned-page", scan), ("book-page", book)]:
        manifest[name] = fn()
    with open(os.path.join(HERE, "fixtures.json"), "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
