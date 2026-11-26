#!/usr/bin/env python3
"""
Generate Appendix A Visual Mapping Diagram (EER -> Physical/DDL) in draw.io format.
Explains the 4 key structural/behavioral differences between the Elmasri EER and MySQL DDL:
  1. Composite attribute `vital_signs` -> 5 flattened atomic columns + CHECKs (Step 1 / 1NF)
  2. Union category `AUDIT_ACTOR` (U) -> 3 nullable FKs + Exclusive-Arc CHECK (Step 9)
  3. Associative entity `PRESCRIPTION_ITEM` -> Separate table with Composite PK (Step 5 / BR-16)
  4. `ROOM used for SHIFT (GP only)` -> Nullable FK + Trigger `sp_validate_shift` (BR-03 / BR-26)

Run: python docs/EER/build_mapping_drawio.py
Outputs: docs/EER/eer_to_physical_mapping.drawio
"""
import html
from pathlib import Path

cells = []
_n = [10]
nid = lambda p="m": (_n.__setitem__(0, _n[0] + 1) or f"{p}{_n[0]}")
esc = lambda s: html.escape(s, quote=True)


def box(style, val, x, y, w, h, parent="1"):
    i = nid()
    cells.append(
        f'<mxCell id="{i}" value="{esc(val)}" style="{style}" vertex="1" parent="{parent}">'
        f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
    )
    return i


def edge(src, tgt, style, label="", wps=None):
    i = nid("e")
    pts = ""
    if wps:
        pts = '<Array as="points">' + "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in wps) + "</Array>"
    cells.append(
        f'<mxCell id="{i}" value="{esc(label)}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">'
        f'<mxGeometry relative="1" as="geometry">{pts}</mxGeometry></mxCell>'
    )
    return i


def table_card(title, x, y, w, header_color, body_color, rows):
    row_h = 22
    h = 30 + len(rows) * row_h
    tid = box(
        f"swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=30;horizontalStack=0;"
        f"resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=0;marginBottom=0;"
        f"fillColor={header_color};strokeColor={header_color};fontColor=#FFFFFF;fontSize=12;rounded=0;"
        f"swimlaneFillColor={body_color};",
        title, x, y, w, h
    )
    for idx, (badge, col, typ, bcolor) in enumerate(rows):
        val = (
            f'<span style="display:inline-block;width:54px"><b><font color="{bcolor}">{badge}</font></b></span>'
            f'<b>{esc(col)}</b> <font color="#475569">: {esc(typ)}</font>'
        )
        box(
            "text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;"
            "spacingLeft=6;spacingRight=4;overflow=hidden;fontSize=10.5;fontColor=#0F172A;whiteSpace=nowrap;",
            val, 0, 30 + idx * row_h, w, row_h, parent=tid
        )
    return tid


# Styles
ENT_CLIN = "rounded=0;whiteSpace=wrap;html=1;fillColor=#F5F3FF;strokeColor=#7C3AED;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
ENT_SCH  = "rounded=0;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#059669;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
ENT_DOC  = "rounded=0;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#2563EB;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
ENT_ADM  = "rounded=0;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#475569;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
ENT_PHM  = "rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFBEB;strokeColor=#D97706;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
ENT_CAT  = "rounded=0;whiteSpace=wrap;html=1;fillColor=#FCE7F3;strokeColor=#DB2777;strokeWidth=2;fontStyle=1;fontSize=11;fontColor=#0F172A;"
OVAL     = "ellipse;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#64748B;strokeWidth=1.2;fontSize=10;fontColor=#1E293B;"
COMP     = "ellipse;whiteSpace=wrap;html=1;fillColor=#FAF5FF;strokeColor=#7C3AED;strokeWidth=1.5;fontStyle=1;fontSize=10.5;fontColor=#0F172A;"
DIAMOND  = "rhombus;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#B45309;strokeWidth=1.5;fontSize=10.5;fontStyle=1;fontColor=#1E293B;"
CIRCLE   = "ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#FFFFFF;strokeColor=#1E293B;strokeWidth=2;fontStyle=1;fontSize=13;fontColor=#0F172A;"
RULE_BOX = "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#2563EB;strokeWidth=1.5;fontSize=11;fontColor=#0F172A;align=center;spacing=6;"
LINE     = "endArrow=none;html=1;strokeColor=#334155;strokeWidth=1.3;"
DOUBLE   = "shape=link;html=1;strokeColor=#7C3AED;strokeWidth=1.4;endArrow=none;width=4;"
ARROW    = "endArrow=block;endFill=1;html=1;strokeColor=#2563EB;strokeWidth=2.5;"
CF_1M    = "edgeStyle=orthogonalEdgeStyle;html=1;startArrow=ERmandOne;endArrow=ERzeroToMany;startFill=0;endFill=0;strokeColor=#334155;strokeWidth=1.5;"
CF_OPT_M = "edgeStyle=orthogonalEdgeStyle;html=1;startArrow=ERzeroToOne;endArrow=ERzeroToMany;startFill=0;endFill=0;strokeColor=#334155;strokeWidth=1.5;dashed=1;"
CF_ID_1M = "edgeStyle=orthogonalEdgeStyle;html=1;startArrow=ERmandOne;endArrow=ERoneToMany;startFill=0;endFill=0;strokeColor=#7C3AED;strokeWidth=1.6;"
CF_ID_0M = "edgeStyle=orthogonalEdgeStyle;html=1;startArrow=ERmandOne;endArrow=ERzeroToMany;startFill=0;endFill=0;strokeColor=#D97706;strokeWidth=1.6;"

# Header Banner
box("text;html=1;align=left;verticalAlign=middle;fontSize=20;fontStyle=1;fontColor=#0F172A;",
    "Appendix A — Visual Mapping: Elmasri EER Constructs → Physical Diagram & MySQL DDL", 40, 20, 1250, 36)

# Column Headers
box("rounded=0;fillColor=#E2E8F0;strokeColor=#94A3B8;fontStyle=1;fontSize=13;fontColor=#0F172A;",
    "1. Conceptual EER Model (Elmasri Notation)", 40, 70, 560, 34)
box("rounded=0;fillColor=#DBEAFE;strokeColor=#3B82F6;fontStyle=1;fontSize=13;fontColor=#1E3A8A;",
    "2. Elmasri Mapping & Transformation Rule", 630, 70, 320, 34)
box("rounded=0;fillColor=#D1FAE5;strokeColor=#059669;fontStyle=1;fontSize=13;fontColor=#065F46;",
    "3. Physical Diagram (IE Crow's Foot) & SQL DDL", 980, 70, 580, 34)

# ===========================================================================
# BAND 1: Composite Attribute vital_signs (y = 120 .. 370)
# ===========================================================================
box("rounded=1;fillColor=#FAFAFA;strokeColor=#CBD5E1;dashed=1;", "", 40, 120, 1520, 240)
e_mr = box(ENT_CLIN, "MEDICAL_RECORD", 80, 165, 145, 44)
o_vs = box(COMP, "vital_signs", 270, 170, 105, 32)
edge(e_mr, o_vs, LINE)
for idx, nm in enumerate(["systolic_bp", "diastolic_bp", "heart_rate", "temperature_c", "oxygen_saturation"]):
    ox = 420 if idx % 2 == 0 else 435
    oy = 135 + idx * 42
    ov = box(OVAL, nm, ox, oy, 130, 28)
    edge(o_vs, ov, LINE)

r1 = box(RULE_BOX,
         "<b>Elmasri Step 1: Flatten Composite Attribute</b><br><br>"
         "• <code>vital_signs</code> node disappears on Physical Diagram<br>"
         "• Expanded into <b>5 atomic columns</b> for 1NF compliance<br>"
         "• Enables range <code>CHECK</code>s &amp; numeric SQL filtering",
         645, 160, 290, 130)
edge(o_vs, r1, ARROW, wps=[(595, 186), (620, 225)])

t_mr = table_card("medical_record", 1040, 135, 460, "#7C3AED", "#F5F3FF", [
    ("PK",  "record_id",         "INT AUTO_INCREMENT", "#B45309"),
    ("CHK", "systolic_bp",       "INT NULL CHECK (60..250)", "#7C3AED"),
    ("CHK", "diastolic_bp",      "INT NULL CHECK (30..150, < sys)", "#7C3AED"),
    ("CHK", "heart_rate",        "INT NULL CHECK (20..250)", "#7C3AED"),
    ("CHK", "temperature_c",     "DECIMAL(4,1) NULL CHECK (30..45)", "#7C3AED"),
    ("CHK", "oxygen_saturation", "INT NULL CHECK (50..100)", "#7C3AED"),
    ("",    "diagnosis / notes", "TEXT (remaining cols...)", "#475569"),
])
edge(r1, t_mr, ARROW)

# ===========================================================================
# BAND 2: Union Category AUDIT_ACTOR (y = 380 .. 690)
# ===========================================================================
box("rounded=1;fillColor=#FAFAFA;strokeColor=#CBD5E1;dashed=1;", "", 40, 380, 1520, 300)
e_p = box(ENT_SCH, "PATIENT", 65, 405, 100, 36)
e_d = box(ENT_DOC, "DOCTOR",  190, 405, 100, 36)
e_a = box(ENT_ADM, "ADMIN",   315, 405, 100, 36)
c_u = box(CIRCLE, "U", 190, 470, 34, 34)
edge(e_p, c_u, LINE)
edge(e_d, c_u, LINE)
edge(e_a, c_u, LINE)
e_act = box(ENT_CAT, "AUDIT_ACTOR\n(Category)", 135, 535, 145, 44)
edge(c_u, e_act, LINE, "⊃")
d_perf = box(DIAMOND, "performed\nby", 325, 527, 105, 58)
e_log = box(ENT_CLIN, "MEDICAL_RECORD_\nAUDIT_LOG", 445, 535, 140, 44)
edge(e_act, d_perf, LINE, "1")
edge(d_perf, e_log, DOUBLE, "N")

r2 = box(RULE_BOX,
         "<b>Elmasri Step 9: Union Category (Distinct Keys)</b><br><br>"
         "• 3 superclasses have different PKs (no common key)<br>"
         "• Mapped without extra <code>audit_actor</code> table<br>"
         "• Uses <b>3 nullable FKs</b> + Exclusive-Arc <code>CHECK</code>:<br>"
         "<code>(pat IS NOT NULL)+(doc IS NOT NULL)+(adm IS NOT NULL) = 1</code>",
         645, 445, 290, 155)
edge(e_log, r2, ARROW, wps=[(610, 557), (610, 522)])

tp = box(ENT_SCH, "patient", 1000, 405, 105, 34)
td = box(ENT_DOC, "doctor",  1000, 480, 105, 34)
ta = box(ENT_ADM, "admin",   1000, 555, 105, 34)
t_log = table_card("medical_record_audit_log", 1200, 415, 340, "#7C3AED", "#F5F3FF", [
    ("PK",     "audit_id",   "BIGINT AUTO_INCREMENT", "#B45309"),
    ("FK",     "record_id",  "INT NOT NULL -> medical_record", "#2563EB"),
    ("FK,CHK", "patient_id", "INT NULL -> patient", "#2563EB"),
    ("FK,CHK", "doctor_id",  "INT NULL -> doctor", "#2563EB"),
    ("FK,CHK", "admin_id",   "INT NULL -> admin", "#2563EB"),
    ("CHK",    "ck_mr_audit_one_actor", "Exactly 1 actor NOT NULL", "#7C3AED"),
])
edge(tp, t_log, CF_OPT_M, "exactly 1")
edge(td, t_log, CF_OPT_M)
edge(ta, t_log, CF_OPT_M)
edge(r2, t_log, ARROW)

# ===========================================================================
# BAND 3: Associative Entity PRESCRIPTION_ITEM (y = 700 .. 940)
# ===========================================================================
box("rounded=1;fillColor=#FAFAFA;strokeColor=#CBD5E1;dashed=1;", "", 40, 700, 1520, 230)
e_pr = box(ENT_CLIN, "PRESCRIPTION", 65, 760, 125, 42)
e_pi_box = box("rounded=0;whiteSpace=wrap;html=1;fillColor=#F5F3FF;strokeColor=#7C3AED;strokeWidth=2;fontStyle=1;fontSize=10.5;verticalAlign=top;spacingTop=3;",
               "PRESCRIPTION_ITEM", 230, 745, 155, 82)
box("rhombus;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#7C3AED;strokeWidth=1.4;fontSize=10;fontStyle=1;",
    "lists", 268, 775, 78, 42)
e_med = box(ENT_PHM, "MEDICATION", 430, 760, 120, 42)
edge(e_pr, e_pi_box, DOUBLE, "1 : N")
edge(e_med, e_pi_box, LINE, "1 : N")
for idx, nm in enumerate(["quantity", "dosage", "frequency", "duration_days"]):
    ox = 110 + idx * 115
    ov = box(OVAL, nm, ox, 865, 102, 28)
    edge(e_pi_box, ov, LINE)

r3 = box(RULE_BOX,
         "<b>Elmasri Step 5: Binary M:N → Associative Table</b><br><br>"
         "• Separate table <code>prescription_item</code> (no surrogate PK)<br>"
         "• <b>Composite PK</b> <code>(prescription_id, medication_id)</code><br>"
         "• Dual role: both 2 FKs &amp; PK enforcing <b>BR-16</b>",
         645, 745, 290, 130)
edge(e_med, r3, ARROW)

t_pr = table_card("prescription", 995, 730, 150, "#7C3AED", "#F5F3FF", [
    ("PK", "prescription_id", "INT", "#B45309"),
    ("FK", "record_id", "INT UQ", "#2563EB"),
])
t_pi = table_card("prescription_item", 1200, 725, 215, "#7C3AED", "#F5F3FF", [
    ("PK,FK", "prescription_id", "INT NN", "#B45309"),
    ("PK,FK", "medication_id",   "INT NN", "#B45309"),
    ("CHK",   "quantity",        "INT > 0", "#7C3AED"),
    ("",      "dosage/freq",     "VARCHAR(120)", "#475569"),
    ("CHK",   "duration_days",   "INT > 0", "#7C3AED"),
])
t_md = table_card("medication", 1445, 730, 105, "#D97706", "#FFFBEB", [
    ("PK", "medication_id", "INT", "#B45309"),
    ("",   "name",          "VARCHAR", "#475569"),
])
edge(t_pr, t_pi, CF_ID_1M)
edge(t_md, t_pi, CF_ID_0M)
edge(r3, t_pr, ARROW)

# ===========================================================================
# BAND 4: Behavioral Rule ROOM used for SHIFT (GP only) (y = 950 .. 1150)
# ===========================================================================
box("rounded=1;fillColor=#FAFAFA;strokeColor=#CBD5E1;dashed=1;", "", 40, 950, 1520, 190)
e_rm = box(ENT_SCH, "ROOM", 80, 1020, 115, 42)
d_uf = box(DIAMOND, "used for\n(GP only)", 260, 1010, 115, 62)
e_sh = box(ENT_SCH, "SHIFT", 440, 1020, 120, 42)
edge(e_rm, d_uf, LINE, "1")
edge(d_uf, e_sh, LINE, "N")

r4 = box(RULE_BOX,
         "<b>Behavioral Trigger vs Structural FK</b><br><br>"
         "• DDL has <b>no structural constraint</b> forcing GP-only<br>"
         "• <code>shift.room_id</code> is structurally nullable FK<br>"
         "• Trigger <code>sp_validate_shift</code> enforces <b>BR-03 &amp; BR-26</b>",
         645, 980, 290, 125)
edge(e_sh, r4, ARROW)

t_rm = table_card("room", 1005, 985, 160, "#059669", "#ECFDF5", [
    ("PK", "room_id",   "INT", "#B45309"),
    ("UQ", "room_code", "VARCHAR(20)", "#059669"),
])
t_sh = table_card("shift", 1265, 975, 275, "#059669", "#ECFDF5", [
    ("PK", "shift_id",  "INT AUTO_INCREMENT", "#B45309"),
    ("FK", "doctor_id", "INT NOT NULL -> doctor", "#2563EB"),
    ("FK", "room_id",   "INT NULL -> room (Trigger!)", "#2563EB"),
    ("TRG","BR-03/26",  "GP: NOT NULL | SPEC: NULL", "#DC2626"),
])
edge(t_rm, t_sh, CF_OPT_M)
edge(r4, t_rm, ARROW)


xml = (
    '<mxfile host="app.diagrams.net">'
    '<diagram name="Appendix A - EER to Physical Mapping" id="eer-to-physical-mapping">'
    '<mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" '
    'connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="1620" '
    'pageHeight="1200" background="#FFFFFF" math="0" shadow="0">'
    '<root><mxCell id="0"/><mxCell id="1" parent="0"/>'
    + "".join(cells) +
    '</root></mxGraphModel></diagram></mxfile>'
)
out = Path(__file__).with_name("eer_to_physical_mapping.drawio")
out.write_text(xml, encoding="utf-8")
print(f"Generated cleanly: {out} ({len(cells)} cells)")
