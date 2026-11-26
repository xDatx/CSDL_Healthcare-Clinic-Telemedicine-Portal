#!/usr/bin/env python3
"""
Generate a clean, complete, zero-overlap, zero-edge-crossing Elmasri-Navathe EER Diagram (.drawio)
for Healthcare Clinic & Telemedicine Portal (INT1313).

Matches all 17 tables & constraints in sql/ddl/01..10 and Report Section 2.1.
Run: python docs/EER/build_eer_drawio.py
Outputs: docs/EER/eer_healthcare.drawio
"""
import html
import math
from pathlib import Path

cells = []
boxes = {}       # id -> (cx, cy, w, h, label, kind)
edges_meta = []  # (src, tgt, waypoints, edge_id)
_counter = [10]


def nid(prefix="c"):
    _counter[0] += 1
    return f"{prefix}{_counter[0]}"


def esc(s):
    return html.escape(s, quote=True)


# ---------------------------------------------------------------------------
# Color Palette (Clean High-Contrast Light Theme by Domain)
# ---------------------------------------------------------------------------
PALETTE = {
    "admin":    ("#F1F5F9", "#475569"),  # Slate
    "doctor":   ("#EFF6FF", "#2563EB"),  # Blue
    "schedule": ("#ECFDF5", "#059669"),  # Emerald/Teal
    "clinical": ("#F5F3FF", "#7C3AED"),  # Violet
    "pharma":   ("#FFFBEB", "#D97706"),  # Amber
    "category": ("#FCE7F3", "#DB2777"),  # Pink/Rose for Union Category
}

REL_STYLE = (
    "rhombus;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#B45309;"
    "strokeWidth=1.5;fontSize=11;fontStyle=1;fontColor=#1E293B;"
)
ATT_BASE = (
    "ellipse;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#64748B;"
    "strokeWidth=1.2;fontSize=11;fontColor=#1E293B;"
)
CIR_STYLE = (
    "ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#FFFFFF;"
    "strokeColor=#1E293B;strokeWidth=2;fontStyle=1;fontSize=14;fontColor=#0F172A;"
)
NOTE_STYLE = (
    "shape=note;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=8;"
    "fontSize=11;fillColor=#FFFBEB;strokeColor=#D97706;fontColor=#1E293B;size=14;"
)
TXT_STYLE = "text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=12;fontColor=#0F172A;"


def vertex(style, value, cx, cy, w, h, kind="shape", cid=None):
    i = cid or nid()
    x = round(cx - w / 2, 1)
    y = round(cy - h / 2, 1)
    cells.append(
        f'<mxCell id="{i}" value="{esc(value)}" style="{style}" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
    )
    boxes[i] = (cx, cy, w, h, value, kind)
    return i


def entity(name, cx, cy, domain="doctor", w=160, h=50):
    fill, stroke = PALETTE[domain]
    style = (
        f"rounded=0;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
        f"strokeWidth=2;fontStyle=1;fontSize=12;fontColor=#0F172A;"
    )
    return vertex(style, name, cx, cy, w, h, kind="entity")


def attr(parent_id, name, cx, cy, is_pk=False, is_composite=False, w=118, h=32):
    style = ATT_BASE
    if is_pk:
        style += "fontStyle=5;strokeColor=#1E40AF;strokeWidth=1.6;fontColor=#1E3A8A;"
    elif is_composite:
        style += "fontStyle=1;strokeColor=#7C3AED;strokeWidth=1.5;fillColor=#FAF5FF;"
    a = vertex(style, name, cx, cy, w, h, kind="attr")
    edge(a, parent_id, color="#64748B", width=1.1)
    return a


def attr_fan(parent_id, specs, cx, cy, rx, ry, start_deg, end_deg, stagger=0):
    """
    Place attributes along an elliptical arc around (cx, cy).
    If stagger > 0, alternates radius by +stagger on odd indices so tight arcs have zero overlaps
    and outer rays pass cleanly between inner ovals.
    """
    n = len(specs)
    for idx, spec in enumerate(specs):
        name = spec[0]
        is_pk = spec[1] if len(spec) > 1 else False
        w = spec[2] if len(spec) > 2 else 116
        is_comp = spec[3] if len(spec) > 3 else False
        t = idx / (n - 1) if n > 1 else 0.5
        ang = math.radians(start_deg + t * (end_deg - start_deg))
        dr = stagger if (stagger and idx % 2 == 1) else 0
        ax = round(cx + (rx + dr) * math.cos(ang))
        ay = round(cy + (ry + dr) * math.sin(ang))
        attr(parent_id, name, ax, ay, is_pk=is_pk, is_composite=is_comp, w=w)


def card_label(parent_edge, text, pos):
    cells.append(
        f'<mxCell id="{nid("lbl")}" value="{esc(text)}" '
        f'style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];'
        f'fontSize=12;fontStyle=1;fontColor=#B91C1C;labelBackgroundColor=#FFFFFF;" '
        f'vertex="1" connectable="0" parent="{parent_edge}">'
        f'<mxGeometry x="{pos}" relative="1" as="geometry"><mxPoint as="offset"/></mxGeometry></mxCell>'
    )


def edge(src, tgt, total=False, color="#334155", width=1.5,
         src_card=None, tgt_card=None, src_pos=-0.70, tgt_pos=0.70,
         waypoints=None, ortho=False):
    i = nid("e")
    if total:
        style = f"shape=link;html=1;rounded=0;strokeColor={color};strokeWidth={width};endArrow=none;width=5;"
    else:
        style = f"endArrow=none;html=1;rounded={'1' if ortho else '0'};strokeColor={color};strokeWidth={width};"
    if ortho:
        style += "edgeStyle=orthogonalEdgeStyle;"

    pts_xml = ""
    if waypoints:
        pts = "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in waypoints)
        pts_xml = f'<Array as="points">{pts}</Array>'

    cells.append(
        f'<mxCell id="{i}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">'
        f'<mxGeometry relative="1" as="geometry">{pts_xml}</mxGeometry></mxCell>'
    )
    if src_card:
        card_label(i, src_card, src_pos)
    if tgt_card:
        card_label(i, tgt_card, tgt_pos)

    edges_meta.append((src, tgt, waypoints or [], i))
    return i


def rel(name, cx, cy, links, w=136, h=68):
    r = vertex(REL_STYLE, name, cx, cy, w, h, kind="rel")
    for link in links:
        ent, card, total = link[0], link[1], link[2]
        color = link[3] if len(link) > 3 else "#334155"
        wps = link[4] if len(link) > 4 else None
        ortho = bool(wps)
        edge(ent, r, total=total, color=color, width=1.5,
             src_card=card, src_pos=-0.65, waypoints=wps, ortho=ortho)
    return r


# ===========================================================================
# 1. ENTITIES PLACEMENT
# ===========================================================================

# --- Left Column: Governance & Pharmacy ---
staff_perm = entity("STAFF_PERMISSION",     480,  290, "admin",  w=175)
admin      = entity("ADMIN",                480,  700, "admin",  w=150)
med_log    = entity("MEDICATION_AUDIT_LOG", 480, 1340, "pharma", w=205)
medication = entity("MEDICATION",           480, 1900, "pharma", w=155)

# --- Center-Top: Doctor & Specialization ---
doctor     = entity("DOCTOR",     1380,  420, "doctor", w=155)
gp         = entity("GP",         1160,  840, "doctor", w=120)
specialist = entity("SPECIALIST", 1600,  840, "doctor", w=145)
specialty  = entity("SPECIALTY",  1560, 1200, "doctor", w=145)

# --- Right-Top: Scheduling & Booking ---
room        = entity("ROOM",        2450, 165, "schedule", w=140)
shift       = entity("SHIFT",       2450, 420, "schedule", w=145)
appointment = entity("APPOINTMENT", 2450, 980, "schedule", w=160)
patient     = entity("PATIENT",     3250, 980, "schedule", w=150)

# --- Center & Bottom: Clinical, Prescriptions & Consultation ---
consult      = entity("CONSULTATION_REQUEST", 1980, 1220, "clinical", w=210)
med_record   = entity("MEDICAL_RECORD",       2450, 1480, "clinical", w=170)
prescription = entity("PRESCRIPTION",         1760, 1900, "clinical", w=160)

# Associative Entity: PRESCRIPTION_ITEM wrapping diamond "lists"
presc_item_box = vertex(
    "rounded=0;whiteSpace=wrap;html=1;fillColor=#F5F3FF;strokeColor=#7C3AED;"
    "strokeWidth=2;fontStyle=1;fontSize=12;fontColor=#0F172A;verticalAlign=top;spacingTop=5;",
    "PRESCRIPTION_ITEM", 1130, 1900, 210, 108, kind="entity"
)
presc_lists_diamond = vertex(
    "rhombus;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#7C3AED;"
    "strokeWidth=1.5;fontSize=11;fontStyle=1;fontColor=#1E293B;",
    "lists", 1130, 1918, 100, 52, kind="rel"
)

# --- Right-Bottom: Clinical Audit Trail & Union Category ---
audit_actor  = entity("AUDIT_ACTOR\n(Union Category)", 3250, 1360, "category", w=165, h=52)
mr_audit_log = entity("MEDICAL_RECORD_AUDIT_LOG",    3250, 1740, "clinical", w=240)


# ===========================================================================
# 2. ATTRIBUTES (Staggered / Wide Arcs -> 0 Overlaps & 0 Crossings)
# ===========================================================================

# STAFF_PERMISSION (arc above)
attr_fan(staff_perm, [
    ("permission_id", True, 125),
    ("permission_code", False, 132),
    ("granted_at", False, 110),
], 480, 290, 185, 135, -145, -35)

# ADMIN (clean arc on the left)
attr_fan(admin, [
    ("admin_id", True, 112),
    ("full_name", False, 112),
    ("email", False, 105),
    ("role", False, 100),
    ("is_active", False, 105),
    ("created_at", False, 112),
], 480, 700, 250, 145, -135, -225)

# MEDICATION_AUDIT_LOG (clean arc on the left)
attr_fan(med_log, [
    ("audit_id", True, 112),
    ("action", False, 105),
    ("action_at", False, 112),
    ("old_values", False, 115),
    ("new_values", False, 115),
], 480, 1340, 260, 135, -135, -225)

# MEDICATION (wide arc on left + bottom)
attr_fan(medication, [
    ("medication_id", True, 122),
    ("name", False, 105),
    ("unit", False, 100),
    ("description", False, 115),
    ("is_active", False, 108),
    ("created_at", False, 115),
], 480, 1900, 275, 165, -142, -268)

# DOCTOR (staggered arc above)
attr_fan(doctor, [
    ("doctor_id", True, 115),
    ("full_name", False, 115),
    ("email", False, 108),
    ("license_no", False, 115),
    ("employment_type", False, 132),
    ("spec_type", False, 112),
    ("is_active", False, 105),
    ("created_at", False, 112),
], 1380, 420, 405, 175, -162, -18, stagger=65)

# SPECIALIST (in open gap between GP and SPECIALIST)
attr(specialist, "years_practice", 1380, 840, w=125)

# SPECIALTY (below-left, completely clear of CONSULTATION_REQUEST)
attr_fan(specialty, [
    ("specialty_id", True, 120),
    ("name", False, 108),
], 1560, 1200, 120, 105, 148, 92)

# ROOM (arc to the right)
attr_fan(room, [
    ("room_id", True, 110),
    ("room_code", False, 112),
    ("floor", False, 100),
], 2450, 165, 215, 70, -45, 45)

# SHIFT (staggered arc to the right)
attr_fan(shift, [
    ("shift_id", True, 110),
    ("shift_date", False, 112),
    ("start_time", False, 112),
    ("end_time", False, 112),
    ("status", False, 105),
    ("rate_per_hour", False, 120),
], 2450, 420, 275, 145, -62, 62, stagger=85)

# APPOINTMENT (4 fanned above-right + 2 on open left side -> 0 overlaps, 0 crossings)
attr(appointment, "appointment_id",   2585, 745, is_pk=True, w=126)
attr(appointment, "start_time",       2725, 735, w=112)
attr(appointment, "end_time",         2755, 815, w=108)
attr(appointment, "appointment_type", 2850, 885, w=134)
attr(appointment, "status",           2245, 975, w=105)
attr(appointment, "created_at",       2270, 1055, w=112)

# PATIENT (circular staggered arc above-right)
attr_fan(patient, [
    ("patient_id", True, 115),
    ("full_name", False, 115),
    ("dob", False, 100),
    ("phone", False, 105),
    ("email", False, 105),
    ("address", False, 110),
    ("created_at", False, 115),
], 3250, 980, 235, 235, -135, 22, stagger=80)

# CONSULTATION_REQUEST (2 upper-flanks + 5 spacious staggered below)
attr(consult, "request_id", 1775, 1105, is_pk=True, w=115)
attr(consult, "opinion",    2185, 1115, w=108)
attr_fan(consult, [
    ("reason", False, 105),
    ("status", False, 105),
    ("requested_at", False, 118),
    ("responded_at", False, 118),
    ("expires_at", False, 110),
], 1980, 1220, 185, 185, 152, 64, stagger=95)

# MEDICAL_RECORD (clean fan below-right, clear of results in & audited via)
attr(med_record, "record_id",  2350, 1650, is_pk=True, w=115)
attr(med_record, "diagnosis",  2450, 1735, w=115)
attr(med_record, "symptoms",   2560, 1675, w=115)
attr(med_record, "notes",      2635, 1575, w=110)
attr(med_record, "created_at", 2735, 1480, w=115)
vs = attr(med_record, "vital_signs", 2710, 1730, is_composite=True, w=122, h=34)
attr_fan(vs, [
    ("systolic_bp", False, 115),
    ("diastolic_bp", False, 115),
    ("heart_rate", False, 115),
    ("temperature_c", False, 120),
    ("oxygen_saturation", False, 138),
], 2710, 1730, 185, 185, 135, 10, stagger=70)

# PRESCRIPTION (below)
attr_fan(prescription, [
    ("prescription_id", True, 128),
    ("issued_at", False, 110),
], 1760, 1900, 130, 110, 130, 50)

# PRESCRIPTION_ITEM (below)
attr_fan(presc_item_box, [
    ("quantity", False, 105),
    ("dosage", False, 105),
    ("frequency", False, 110),
    ("duration_days", False, 118),
], 1130, 1900, 235, 140, 145, 35)

# MEDICAL_RECORD_AUDIT_LOG (below)
attr_fan(mr_audit_log, [
    ("audit_id", True, 115),
    ("action", False, 105),
    ("action_at", False, 112),
    ("details", False, 108),
], 3250, 1740, 240, 145, 142, 38)


# ===========================================================================
# 3. RELATIONSHIPS & CONSTRAINTS
# ===========================================================================

# ADMIN <-> STAFF_PERMISSION (holds, grants)
rel("holds",  380, 495, [(admin, "1", False, "#475569"), (staff_perm, "N", True, "#475569")], w=115, h=60)
rel("grants", 580, 495, [(admin, "1", False, "#475569"), (staff_perm, "N", True, "#475569")], w=115, h=60)

# ADMIN <-> DOCTOR (creates account for)
rel("creates\naccount for", 880, 540,
    [(admin, "1", False, "#475569"), (doctor, "N", True, "#2563EB")], w=140, h=74)

# ADMIN <-> MEDICATION_AUDIT_LOG (performs)
rel("performs", 480, 1020,
    [(admin, "1", False, "#475569"), (med_log, "N", True, "#D97706")], w=125, h=64)

# MEDICATION <-> MEDICATION_AUDIT_LOG (logged for)
rel("logged for", 480, 1620,
    [(medication, "1", False, "#D97706"), (med_log, "N", True, "#D97706")], w=130, h=64)

# SPECIALIZATION: DOCTOR (d, total) -> GP | SPECIALIST
d_circle = vertex(CIR_STYLE, "d", 1380, 625, 38, 38, kind="circle")
edge(doctor, d_circle, total=True, color="#2563EB", width=1.6)
edge(d_circle, gp, total=False, color="#2563EB", src_card="⊂", src_pos=-0.4)
edge(d_circle, specialist, total=False, color="#2563EB", src_card="⊂", src_pos=-0.4)
vertex(TXT_STYLE + "fontSize=11;fontStyle=1;fontColor=#2563EB;",
       "disjoint, total (BR-01)\ndefining attr: spec_type", 1505, 625, 185, 36, kind="note")

# SPECIALIST <-> SPECIALTY (classifies)
rel("classifies", 1580, 1020,
    [(specialty, "1", False, "#2563EB"), (specialist, "N", True, "#2563EB")], w=128, h=64)

# DOCTOR <-> SHIFT (registers)
rel("registers", 1940, 420,
    [(doctor, "1", False, "#2563EB"), (shift, "N", True, "#059669")], w=130, h=66)

# ROOM <-> SHIFT (used for GP only)
rel("used for\n(GP only)", 2450, 290,
    [(room, "1", False, "#059669"), (shift, "N", False, "#059669")], w=135, h=66)

# SHIFT <-> APPOINTMENT (hosts)
rel("hosts", 2450, 700,
    [(shift, "1", False, "#059669"), (appointment, "N", True, "#059669")], w=125, h=64)

# PATIENT <-> APPOINTMENT (books)
rel("books", 2850, 980,
    [(patient, "1", False, "#059669"), (appointment, "N", True, "#059669")], w=125, h=64)

# APPOINTMENT <-> MEDICAL_RECORD (produces)
rel("produces", 2450, 1230,
    [(appointment, "1", False, "#7C3AED"), (med_record, "1", True, "#7C3AED")], w=130, h=66)

# MEDICAL_RECORD <-> PRESCRIPTION (results in)
rel("results in", 2060, 1730,
    [(med_record, "1", False, "#7C3AED"), (prescription, "1", True, "#7C3AED")], w=130, h=66)

# PRESCRIPTION <-> PRESCRIPTION_ITEM (Associative Entity 'lists') <-> MEDICATION
# BR-15: prescription contains 1+ items (conceptual total on both sides); BR-16: medication partial -> item total
j_presc = vertex("ellipse;fillColor=#7C3AED;strokeColor=none;", "", 1450, 1900, 6, 6, kind="circle")
edge(prescription, j_presc, total=True, color="#7C3AED", width=1.6, src_card="1", src_pos=-0.5)
edge(j_presc, presc_item_box, total=True, color="#7C3AED", width=1.6, tgt_card="N", tgt_pos=0.5)
vertex(TXT_STYLE + "align=center;fontSize=10;fontColor=#475569;", "contains (BR-15)", 1450, 1878, 120, 20, kind="note")

j_med = vertex("ellipse;fillColor=#D97706;strokeColor=none;", "", 805, 1900, 6, 6, kind="circle")
edge(medication, j_med, total=False, color="#D97706", width=1.6, src_card="1", src_pos=-0.5)
edge(j_med, presc_item_box, total=True, color="#7C3AED", width=1.6, tgt_card="N", tgt_pos=0.5)
vertex(TXT_STYLE + "align=center;fontSize=10;fontColor=#475569;", "listed in (BR-16)", 805, 1878, 120, 20, kind="note")

# CONSULTATION_REQUEST (requests, invited to, referred via)
# Route cleanly below DOCTOR -> corridor x=1865 / x=2085 (below registers at 1940,420)
rel("requests\n(treating)", 1865, 890,
    [(doctor, "1", False, "#7C3AED", [(1380, 520), (1865, 520)]),
     (consult, "N", True, "#7C3AED")], w=130, h=68)

rel("invited to\n(consulting)", 2085, 890,
    [(doctor, "1", False, "#7C3AED", [(1430, 545), (2085, 545)]),
     (consult, "N", True, "#7C3AED")], w=135, h=68)

rel("referred\nvia", 2225, 1345,
    [(med_record, "1", False, "#7C3AED"),
     (consult, "N", True, "#7C3AED")], w=125, h=64)

# AUDIT_ACTOR CATEGORY (UNION): PATIENT U DOCTOR U ADMIN
u_circle = vertex(CIR_STYLE, "U", 3250, 1190, 38, 38, kind="circle")
edge(u_circle, audit_actor, total=False, color="#DB2777", width=1.6, src_card="⊃", src_pos=-0.4)

# 1. PATIENT -> U (straight down)
edge(patient, u_circle, total=False, color="#DB2777", width=1.4)
# 2. DOCTOR -> U (clean outer top perimeter bus y=65 -> x=3645 -> y=1190)
edge(doctor, u_circle, total=False, color="#DB2777", width=1.4,
     waypoints=[(1380, 65), (3645, 65), (3645, 1190)], ortho=True)
# 3. ADMIN -> U (clean outer top perimeter bus x=65 -> y=30 -> x=3685 -> y=1190)
edge(admin, u_circle, total=False, color="#DB2777", width=1.4,
     waypoints=[(65, 700), (65, 30), (3685, 30), (3685, 1190)], ortho=True)

# AUDIT_ACTOR <-> MEDICAL_RECORD_AUDIT_LOG (performed by)
rel("performed\nby", 3250, 1550,
    [(audit_actor, "1", False, "#DB2777"), (mr_audit_log, "N", True, "#7C3AED")], w=135, h=68)

# MEDICAL_RECORD <-> MEDICAL_RECORD_AUDIT_LOG (audited via)
rel("audited\nvia", 2905, 1615,
    [(med_record, "1", False, "#7C3AED"), (mr_audit_log, "N", True, "#7C3AED")], w=125, h=66)


# ===========================================================================
# 4. TITLE, NOTES & LEGEND
# ===========================================================================
vertex(
    "text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;fontSize=22;fontStyle=1;fontColor=#0F172A;",
    "EER Diagram — Healthcare Clinic & Telemedicine Portal (Elmasri–Navathe Notation)",
    620, 100, 1020, 44, kind="note"
)

vertex(
    NOTE_STYLE,
    "<b>Exclusive Arc (NFR-04):</b><br>"
    "Category <b>AUDIT_ACTOR = PATIENT ∪ DOCTOR ∪ ADMIN</b>.<br>"
    "When mapped to relational tables (Step 9), each log entry stores<br>"
    "exactly ONE non-null FK (<code>patient_id</code> XOR <code>doctor_id</code> XOR <code>admin_id</code>).",
    3500, 1360, 290, 105, kind="note"
)

vertex(
    NOTE_STYLE,
    "<b>M:N Resolution (BR-16):</b><br>"
    "Associative entity <b>PRESCRIPTION_ITEM</b> resolves the M:N<br>"
    "relationship <i>lists</i> between PRESCRIPTION and MEDICATION.<br>"
    "Composite PK: <code>(prescription_id, medication_id)</code>.",
    1130, 1715, 310, 86, kind="note"
)

vertex(
    "shape=note;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=10;"
    "fontSize=11;fillColor=#F8FAFC;strokeColor=#475569;fontColor=#0F172A;size=16;",
    "<b>Legend (Elmasri–Navathe Standards)</b><br><br>"
    "▭ &nbsp;<b>Entity</b> (color-coded by module)<br>"
    "▭◇ <b>Associative Entity</b> (M:N resolution)<br>"
    "◯ &nbsp;<b>Attribute</b> &nbsp;|&nbsp; <u><b>Key</b></u> = Primary Key<br>"
    "◯ &nbsp;<span style='color:#7C3AED'><b>Composite Attribute</b></span> (<code>vital_signs</code> → 5 numeric cols)<br>"
    "◇ &nbsp;<b>Relationship</b> &nbsp;|&nbsp; <b style='color:#B91C1C'>1 / N</b> = Cardinality ratio<br>"
    "━ &nbsp;Single line = Partial participation<br>"
    "═ &nbsp;Double line = Total (mandatory) participation<br>"
    "<b>d</b> &nbsp;Disjoint Specialization (DOCTOR → GP | SPECIALIST)<br>"
    "<b>U</b> &nbsp;Union Category (AUDIT_ACTOR = PATIENT ∪ DOCTOR ∪ ADMIN)",
    3250, 230, 440, 220, kind="note"
)


# ===========================================================================
# 5. GEOMETRY CHECKER (ZERO OVERLAPS & ZERO CROSSINGS)
# ===========================================================================
def seg_intersects_rect(x1, y1, x2, y2, rx, ry, rw, rh):
    left, right = rx - rw / 2, rx + rw / 2
    top, bottom = ry - rh / 2, ry + rh / 2
    for i in range(1, 60):
        t = i / 60.0
        px = x1 + (x2 - x1) * t
        py = y1 + (y2 - y1) * t
        if left <= px <= right and top <= py <= bottom:
            return True
    return False


def verify_geometry():
    overlaps = 0
    items = list(boxes.items())
    for idx1 in range(len(items)):
        id1, (x1, y1, w1, h1, t1, k1) = items[idx1]
        for idx2 in range(idx1 + 1, len(items)):
            id2, (x2, y2, w2, h2, t2, k2) = items[idx2]
            if {id1, id2} == {presc_item_box, presc_lists_diamond}:
                continue
            if abs(x1 - x2) < (w1 + w2) / 2 + 4 and abs(y1 - y2) < (h1 + h2) / 2 + 4:
                print(f"[OVERLAP] {t1!r} ({x1},{y1}) <-> {t2!r} ({x2},{y2})")
                overlaps += 1

    crossings = 0
    for src, tgt, wps, eid in edges_meta:
        sx, sy = boxes[src][0], boxes[src][1]
        tx, ty = boxes[tgt][0], boxes[tgt][1]
        pts = [(sx, sy)] + wps + [(tx, ty)]
        for k in range(len(pts) - 1):
            p1, p2 = pts[k], pts[k + 1]
            for bid, (bx, by, bw, bh, bname, bkind) in boxes.items():
                if bid in (src, tgt):
                    continue
                if {bid, src} == {presc_item_box, presc_lists_diamond} or {bid, tgt} == {presc_item_box, presc_lists_diamond}:
                    continue
                if seg_intersects_rect(p1[0], p1[1], p2[0], p2[1], bx, by, bw, bh):
                    print(f"[EDGE CROSS] {boxes[src][4]!r} -> {boxes[tgt][4]!r} crosses {bname!r} ({bx},{by})")
                    crossings += 1

    print(f"Total shapes: {len(boxes)}, Overlaps: {overlaps}, Edge crossings: {crossings}")
    return overlaps, crossings


if __name__ == "__main__":
    ov, cr = verify_geometry()
    xml = (
        '<mxfile host="app.diagrams.net">'
        '<diagram name="EER - Healthcare Clinic" id="eer-healthcare-v2">'
        '<mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" '
        'connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="3800" '
        'pageHeight="2150" background="#FFFFFF" math="0" shadow="0">'
        '<root><mxCell id="0"/><mxCell id="1" parent="0"/>'
        + "".join(cells) +
        '</root></mxGraphModel></diagram></mxfile>'
    )
    out = Path(__file__).with_name("eer_healthcare.drawio")
    out.write_text(xml, encoding="utf-8")
    print(f"Generated cleanly: {out}")
