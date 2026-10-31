# -*- coding: utf-8 -*-
"""把视频拍摄脚本 md 转成可打印的 docx（供拍摄现场打印）。"""
import os
import re
import sys
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

SRC = sys.argv[1]
DST = sys.argv[2]

doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
sec.top_margin = sec.bottom_margin = Cm(2.0)
sec.left_margin = sec.right_margin = Cm(2.0)

st = doc.styles['Normal']
st.font.name = 'Times New Roman'
st.font.size = Pt(10)
st.element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
st.paragraph_format.space_after = Pt(0)
st.paragraph_format.line_spacing = 1.25


def run(p, text, bold=False, size=10, mono=False, color=None):
    # 去掉 md 强调标记
    text = text.replace('**', '').replace('`', '')
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.name = 'Consolas' if mono else 'Times New Roman'
    r._element.get_or_add_rPr().append(_ea(r.font.name))
    if color:
        r.font.color.rgb = color


def _ea(name):
    e = OxmlElement('w:rFonts')
    e.set(qn('w:eastAsia'), '宋体')
    e.set(qn('w:ascii'), name)
    e.set(qn('w:hAnsi'), name)
    return e


lines = open(SRC, encoding='utf-8').read().split('\n')
i = 0
in_code = False
while i < len(lines):
    ln = lines[i].rstrip()
    if ln.startswith('```'):
        in_code = not in_code
        i += 1
        continue
    if in_code:
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.0
        run(p, ln, size=9, mono=True)
        i += 1
        continue
    if not ln.strip() or re.match(r'^-{3,}$', ln.strip()):
        i += 1
        continue
    if ln.startswith('# '):
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after = Pt(6)
        run(p, ln[2:], bold=True, size=16)
    elif ln.startswith('## '):
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(3)
        run(p, ln[3:], bold=True, size=12)
    elif ln.startswith('|'):
        rows = []
        while i < len(lines) and lines[i].strip().startswith('|'):
            cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
            if not re.match(r'^[-: ]+$', ''.join(cells)):
                rows.append(cells)
            i += 1
        if rows:
            t = doc.add_table(rows=0, cols=len(rows[0]))
            t.style = 'Table Grid'
            t.alignment = WD_TABLE_ALIGNMENT.CENTER
            for ri, cells in enumerate(rows):
                cells_row = t.add_row().cells
                for ci, c in enumerate(cells[:len(rows[0])]):
                    cells_row[ci].text = ''
                    p = cells_row[ci].paragraphs[0]
                    p.paragraph_format.line_spacing = 1.0
                    p.paragraph_format.space_before = Pt(1)
                    p.paragraph_format.space_after = Pt(1)
                    run(p, c, bold=(ri == 0), size=8.5)
            W = {3: [3.2, 9.0, 3.2], 5: [1.0, 2.2, 4.2, 2.8, 6.6], 2: [8.0, 9.0]}
            hdr = ''.join(rows[0])
            if '怎么按' in hdr:
                W = {3: [1.6, 3.2, 10.4]}
            elif '处理' in hdr:
                W = {2: [6.0, 10.6]}
            ws = W.get(len(rows[0]))
            if ws:
                for ci, w in enumerate(ws):
                    for r in t.rows:
                        r.cells[ci].width = Cm(w)
            doc.add_paragraph()
        continue
    elif ln.startswith('> '):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.6)
        p.paragraph_format.space_after = Pt(2)
        run(p, ln[2:], size=10, color=RGBColor(0x44, 0x44, 0x44))
    else:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(3)
        run(p, ln, size=10)
    i += 1

doc.save(DST)
print('saved', DST)
