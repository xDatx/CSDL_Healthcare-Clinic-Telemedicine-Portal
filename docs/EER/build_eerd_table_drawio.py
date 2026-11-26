#!/usr/bin/env python3
"""
Generate the Enhanced Entity-Relationship Diagram (EERD) in Table/UML-Hybrid Style (.drawio)
matching the team's ERD.png convention, fixed with:
  - Light high-contrast theme for Word/PDF printing
  - Zero truncated text (wide columns, full constraints)
  - Zero overlapping boxes and zero edges crossing through any table
  - 100% alignment with sql/ddl/01..10.sql, Report Section 2.1/2.2, and Appendix A

Run: python docs/EER/build_eerd_table_drawio.py
Outputs: docs/EER/EERD.drawio
"""
import html
from pathlib import Path

cells = []
boxes = {}       # id -> (x, y, w, h, name)
edges_meta = []  # (src, tgt, wps, label)
_n = [10]
nid = lambda p="e": (_n.__setitem__(0, _n[0] + 1) or f"{p}{_n[0]}")
esc = lambda s: html.escape(s, quote=True)

THEMES = {
    "admin":    ("#475569", "#F8FAFC"),
    "doctor":   ("#2563EB", "#EFF6FF"),
    "schedule": ("#059669", "#ECFDF5"),
    "clinical": ("#7C3AED", "#F5F3FF"),
    "pharma":   ("#D97706", "#FFFBEB"),
}

TAG_COLORS = {
    "PK":      "#B45309",
    "PK,FK":   "#B45309",
    "PK,UQ2":  "#B45309",
    "FK":      "#1D4ED8",
    "FK,UQ":   "#1D4ED8",
    "FK,UQ1":  "#1D4ED8",
    "FK,CHK":  "#1D4ED8",
    "UQ":      "#047857",
    "UQ1,CHK": "#047857",
    "UQ2,CHK": "#047857",
    "CHK":     "#6D28D9",
    "":        "#64748B",
}


def entity_table(name, x, y, w, theme, cols, subtitle=None):
    hdr, body = THEMES[theme]
    row_h = 26
    hdr_h = 30
    h = hdr_h + len(cols) * row_h
    title = f"<b>{esc(name)}</b>  <font color='#FEF08A'>{esc(subtitle)}</font>" if subtitle else f"<b>{esc(name)}</b>"
    tid = nid("tbl")
    cells.append(
        f'<mxCell id="{tid}" value="{esc(title)}" style="swimlane;html=1;fontStyle=0;childLayout=stackLayout;'
        f'horizontal=1;startSize={hdr_h};horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;'
        f'collapsible=0;marginBottom=0;fillColor={hdr};strokeColor={hdr};fontColor=#FFFFFF;fontSize=12.5;'
        f'rounded=1;arcSize=4;swimlaneFillColor={body};" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
    )
    boxes[tid] = (x, y, w, h, name)

    for idx, (tag, col, typ) in enumerate(cols):
        tc = TAG_COLORS.get(tag, "#475569")
        col_fmt = f"<u><b>{esc(col)}</b></u>" if "PK" in tag else f"<b>{esc(col)}</b>"
        tag_html = f'<font color="{tc}"><b>{esc(tag)}</b></font>' if tag else ""
        val = (
            f'<span style="display:inline-block;width:68px">{tag_html}</span>'
            f'{col_fmt} <font color="#475569">: {esc(typ)}</font>'
        )
        rid = nid("row")
        cells.append(
            f'<mxCell id="{rid}" value="{esc(val)}" style="text;html=1;strokeColor=none;fillColor=none;'
            f'align=left;verticalAlign=middle;spacingLeft=8;spacingRight=6;overflow=hidden;rotatable=0;'
            f'points=[[0,0.5],[1,0.5]];portConstraint=eastwest;fontSize=10.5;fontColor=#0F172A;whiteSpace=nowrap;" '
            f'vertex="1" parent="{tid}"><mxGeometry y="{hdr_h + idx * row_h}" width="{w}" height="{row_h}" as="geometry"/></mxCell>'
        )
    return tid


def rel(src, tgt, label, color="#334155", dashed=False, wps=None,
        exit_xy=None, entry_xy=None, lbl_pos=0.0, width=1.6):
    eid = nid("rel")
    dash = "dashed=1;dashPattern=6 4;" if dashed else ""
    ports = ""
    if exit_xy:
        ports += f"exitX={exit_xy[0]};exitY={exit_xy[1]};exitDx=0;exitDy=0;"
    if entry_xy:
        ports += f"entryX={entry_xy[0]};entryY={entry_xy[1]};entryDx=0;entryDy=0;"

    style = (
        f"edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;"
        f"strokeColor={color};strokeWidth={width};fontColor=#0F172A;fontSize=10;fontStyle=1;"
        f"labelBackgroundColor=#FFFFFF;endArrow=classic;endFill=1;{dash}{ports}"
    )
    pts = ""
    if wps:
        pts = '<Array as="points">' + "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in wps) + "</Array>"
    cells.append(
        f'<mxCell id="{eid}" value="{esc(label)}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">'
        f'<mxGeometry x="{lbl_pos}" relative="1" as="geometry">{pts}</mxGeometry></mxCell>'
    )
    edges_meta.append((src, tgt, wps or [], exit_xy, entry_xy, label))
    return eid


# ===========================================================================
# TITLE & LEGEND
# ===========================================================================
cells.append(
    f'<mxCell id="{nid("t")}" value="{esc("Enhanced Entity-Relationship Diagram (EERD) — Healthcare Clinic & Telemedicine Portal")}" '
    f'style="text;html=1;align=left;verticalAlign=middle;fontSize=20;fontStyle=1;fontColor=#0F172A;" '
    f'vertex="1" parent="1"><mxGeometry x="70" y="16" width="1100" height="36" as="geometry"/></mxCell>'
)

legend_html = (
    "<b>EERD Notation &amp; Business Rules Summary</b><br>"
    "• <b>d</b> circle (double line): Disjoint, total specialization (DOCTOR → GP | SPECIALIST, BR-01) &nbsp;|&nbsp; "
    "• <b>[AES-256]</b>: Storage-level TDE (NFR-04)<br>"
    "• <b>Solid arrow</b>: Mandatory / standard FK relationship &nbsp;|&nbsp; "
    "<b>Dashed arrow</b>: Optional / Exclusive-Arc nullable FK (NFR-04, BR-03/26)<br>"
    "• <b>vital_signs</b>: Composite EER attribute flattened to 5 atomic columns in MEDICAL_RECORD (1NF)"
)
cells.append(
    f'<mxCell id="{nid("lg")}" value="{esc(legend_html)}" '
    f'style="shape=note;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=8;fontSize=10.5;'
    f'fillColor=#FFFBEB;strokeColor=#D97706;fontColor=#0F172A;size=14;" vertex="1" parent="1">'
    f'<mxGeometry x="1210" y="10" width="940" height="76" as="geometry"/></mxCell>'
)

# ===========================================================================
# COLUMN 1 (x = 70, w = 420)
# ===========================================================================
t_admin = entity_table("ADMIN", 70, 110, 420, "admin", [
    ("PK",  "admin_id",   "INT AUTO_INCREMENT"),
    ("",    "full_name",  "VARCHAR(100) NOT NULL"),
    ("UQ",  "email",      "VARCHAR(120) NOT NULL UNIQUE"),
    ("CHK", "role",       "VARCHAR(20) ('RECEPTIONIST','SYSTEM_ADMIN')"),
    ("",    "is_active",  "BOOLEAN DEFAULT TRUE"),
    ("",    "created_at", "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

t_perm = entity_table("STAFF_PERMISSION", 70, 385, 420, "admin", [
    ("PK",      "permission_id",   "INT AUTO_INCREMENT"),
    ("FK,UQ1",  "admin_id",        "INT NOT NULL -> ADMIN(admin_id)"),
    ("UQ1,CHK", "permission_code", "VARCHAR(50) UQ(admin_id, permission_code)"),
    ("FK",      "granted_by",      "INT NOT NULL -> ADMIN(admin_id)"),
    ("",        "granted_at",      "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

t_patient = entity_table("PATIENT", 70, 645, 420, "schedule", [
    ("PK",  "patient_id", "INT AUTO_INCREMENT"),
    ("",    "full_name",  "VARCHAR(100) NOT NULL"),
    ("",    "dob",        "DATE NOT NULL"),
    ("CHK", "phone",      "VARCHAR(20) NULL* (BR-00: phone OR email)"),
    ("CHK", "email",      "VARCHAR(120) NULL* (BR-00: phone OR email)"),
    ("",    "address",    "TEXT NULL"),
    ("",    "created_at", "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

t_med_log = entity_table("MEDICATION_AUDIT_LOG", 70, 1380, 420, "pharma", [
    ("PK",  "audit_id",      "BIGINT AUTO_INCREMENT"),
    ("FK",  "medication_id", "INT NOT NULL -> MEDICATION(medication_id)"),
    ("FK",  "admin_id",      "INT NOT NULL -> ADMIN(admin_id)"),
    ("CHK", "action",        "VARCHAR(15) ('INSERT','UPDATE','DEACTIVATE')"),
    ("",    "action_at",     "DATETIME DEFAULT CURRENT_TIMESTAMP"),
    ("",    "old_values",    "JSON NULL"),
    ("",    "new_values",    "JSON NULL"),
])

# ===========================================================================
# COLUMN 2 (x = 590, w = 460)
# ===========================================================================
t_doctor = entity_table("DOCTOR", 590, 110, 460, "doctor", [
    ("PK,UQ2",  "doctor_id",       "INT AUTO_INCREMENT"),
    ("",        "full_name",       "VARCHAR(100) NOT NULL"),
    ("UQ",      "email",           "VARCHAR(120) NOT NULL UNIQUE"),
    ("UQ",      "license_no",      "VARCHAR(50) NOT NULL UNIQUE"),
    ("CHK",     "employment_type", "VARCHAR(10) ('FULL_TIME','PART_TIME')"),
    ("UQ2,CHK", "spec_type",       "VARCHAR(10) ('GP','SPECIALIST')"),
    ("",        "is_active",       "BOOLEAN DEFAULT FALSE (BR-01)"),
    ("FK",      "created_by",      "INT NOT NULL -> ADMIN(admin_id)"),
    ("",        "created_at",      "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

# EER Specialization circle 'd'
eer_d = nid("eer_d")
cells.append(
    f'<mxCell id="{eer_d}" value="{esc("<b>d</b>")}" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;'
    f'fillColor=#FFFFFF;strokeColor=#2563EB;strokeWidth=2.5;fontColor=#1E3A8A;fontSize=14;" '
    f'vertex="1" parent="1"><mxGeometry x="802" y="420" width="36" height="36" as="geometry"/></mxCell>'
)
boxes[eer_d] = (802, 420, 36, 36, "d")
cells.append(
    f'<mxCell id="{nid()}" value="{esc("<i>disjoint, total (BR-01)<br>attr: spec_type</i>")}" '
    f'style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;fontColor=#1D4ED8;fontSize=10.5;fontStyle=1;" '
    f'vertex="1" parent="1"><mxGeometry x="844" y="422" width="145" height="32" as="geometry"/></mxCell>'
)

t_gp = entity_table("GP", 590, 500, 210, "doctor", [
    ("PK,FK",  "doctor_id", "INT -> DOCTOR"),
    ("FK,CHK", "spec_type", "VARCHAR(10) = 'GP'"),
])

t_spec = entity_table("SPECIALIST", 820, 500, 245, "doctor", [
    ("PK,FK",  "doctor_id",      "INT -> DOCTOR"),
    ("FK,CHK", "spec_type",      "VARCHAR(10) = 'SPECIALIST'"),
    ("FK",     "specialty_id",   "INT NOT NULL -> SPECIALTY"),
    ("CHK",    "years_practice", "INT NOT NULL (>= 0)"),
])

t_appt = entity_table("APPOINTMENT", 590, 705, 460, "schedule", [
    ("PK",  "appointment_id",   "INT AUTO_INCREMENT"),
    ("FK",  "patient_id",       "INT NOT NULL -> PATIENT(patient_id)"),
    ("FK",  "shift_id",         "INT NOT NULL -> SHIFT(shift_id)"),
    ("",    "start_time",       "DATETIME NOT NULL"),
    ("CHK", "end_time",         "DATETIME NOT NULL (> start_time)"),
    ("CHK", "appointment_type", "VARCHAR(15) ('IN_PERSON','TELEMEDICINE')"),
    ("CHK", "status",           "VARCHAR(15) DEFAULT 'PENDING' (5 states)"),
    ("",    "created_at",       "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

t_mr = entity_table("MEDICAL_RECORD", 590, 1020, 460, "clinical", [
    ("PK",    "record_id",         "INT AUTO_INCREMENT"),
    ("FK,UQ", "appointment_id",    "INT NOT NULL UNIQUE -> APPOINTMENT"),
    ("CHK",   "systolic_bp",       "INT NULL (60..250) [vital_signs]"),
    ("CHK",   "diastolic_bp",      "INT NULL (30..150, < systolic) [vital_signs]"),
    ("CHK",   "heart_rate",        "INT NULL (20..250) [vital_signs]"),
    ("CHK",   "temperature_c",     "DECIMAL(4,1) NULL (30..45) [vital_signs]"),
    ("CHK",   "oxygen_saturation", "INT NULL (50..100) [vital_signs]"),
    ("",      "symptoms",          "TEXT NULL"),
    ("",      "diagnosis",         "TEXT NOT NULL"),
    ("",      "notes",             "TEXT NULL"),
    ("",      "created_at",        "DATETIME DEFAULT CURRENT_TIMESTAMP"),
], subtitle="[AES-256]")

t_presc = entity_table("PRESCRIPTION", 590, 1445, 460, "clinical", [
    ("PK",    "prescription_id", "INT AUTO_INCREMENT"),
    ("FK,UQ", "record_id",       "INT NOT NULL UNIQUE -> MEDICAL_RECORD"),
    ("",      "issued_at",       "DATETIME DEFAULT CURRENT_TIMESTAMP"),
], subtitle="[AES-256]")

# ===========================================================================
# COLUMN 3 (x = 1210, w = 470)
# ===========================================================================
t_room = entity_table("ROOM", 1210, 110, 470, "schedule", [
    ("PK",  "room_id",   "INT AUTO_INCREMENT"),
    ("UQ",  "room_code", "VARCHAR(20) NOT NULL UNIQUE"),
    ("CHK", "floor",     "INT NOT NULL (1..20)"),
])

t_shift = entity_table("SHIFT", 1210, 290, 470, "schedule", [
    ("PK",  "shift_id",      "INT AUTO_INCREMENT"),
    ("FK",  "doctor_id",     "INT NOT NULL -> DOCTOR(doctor_id)"),
    ("FK",  "room_id",       "INT NULL -> ROOM (Trigger BR-03/26: GP only)"),
    ("",    "shift_date",    "DATE NOT NULL"),
    ("",    "start_time",    "TIME NOT NULL"),
    ("CHK", "end_time",      "TIME NOT NULL (> start_time)"),
    ("CHK", "rate_per_hour", "DECIMAL(10,2) NULL (> 0, BR-24)"),
    ("CHK", "status",        "VARCHAR(10) DEFAULT 'ACTIVE'"),
])

t_specialty = entity_table("SPECIALTY", 1210, 585, 470, "doctor", [
    ("PK", "specialty_id", "INT AUTO_INCREMENT"),
    ("UQ", "name",         "VARCHAR(80) NOT NULL UNIQUE"),
])

t_consult = entity_table("CONSULTATION_REQUEST", 1210, 735, 470, "clinical", [
    ("PK",     "request_id",           "INT AUTO_INCREMENT"),
    ("FK",     "record_id",            "INT NOT NULL -> MEDICAL_RECORD"),
    ("FK,CHK", "requesting_doctor_id", "INT NOT NULL -> DOCTOR (<> consulting)"),
    ("FK,CHK", "consulting_doctor_id", "INT NOT NULL -> DOCTOR"),
    ("",       "reason",               "TEXT NOT NULL"),
    ("CHK",    "status",               "VARCHAR(15) DEFAULT 'PENDING' (4 states)"),
    ("",       "requested_at",         "DATETIME DEFAULT CURRENT_TIMESTAMP"),
    ("CHK",    "responded_at",         "DATETIME NULL"),
    ("CHK",    "expires_at",           "DATETIME NULL (> requested_at)"),
    ("CHK",    "opinion",              "TEXT NULL (req if COMPLETED)"),
])

t_mr_log = entity_table("MEDICAL_RECORD_AUDIT_LOG", 1210, 1110, 470, "clinical", [
    ("PK",     "audit_id",   "BIGINT AUTO_INCREMENT"),
    ("FK",     "record_id",  "INT NOT NULL -> MEDICAL_RECORD"),
    ("FK,CHK", "patient_id", "INT NULL -> PATIENT (Exclusive Arc)"),
    ("FK,CHK", "doctor_id",  "INT NULL -> DOCTOR (Exclusive Arc)"),
    ("FK,CHK", "admin_id",   "INT NULL -> ADMIN (Exclusive Arc)"),
    ("CHK",    "action",     "VARCHAR(10) ('SELECT','INSERT','UPDATE')"),
    ("",       "action_at",  "DATETIME DEFAULT CURRENT_TIMESTAMP"),
    ("",       "details",    "JSON NULL"),
], subtitle="[Exclusive Arc | NFR-04]")

t_pitem = entity_table("PRESCRIPTION_ITEM", 1210, 1445, 470, "clinical", [
    ("PK,FK", "prescription_id", "INT NOT NULL -> PRESCRIPTION (CASCADE)"),
    ("PK,FK", "medication_id",   "INT NOT NULL -> MEDICATION (RESTRICT)"),
    ("CHK",   "quantity",        "INT NOT NULL (> 0)"),
    ("",      "dosage",          "VARCHAR(120) NOT NULL"),
    ("",      "frequency",       "VARCHAR(120) NOT NULL"),
    ("CHK",   "duration_days",   "INT NOT NULL (> 0)"),
], subtitle="[Associative | AES-256]")

# ===========================================================================
# COLUMN 4 (x = 1790, w = 390): MEDICATION (Cleanly beside PRESCRIPTION_ITEM)
# ===========================================================================
t_med = entity_table("MEDICATION", 1790, 1445, 390, "pharma", [
    ("PK", "medication_id", "INT AUTO_INCREMENT"),
    ("",   "name",          "VARCHAR(120) NOT NULL"),
    ("",   "unit",          "VARCHAR(20) NOT NULL"),
    ("",   "description",   "TEXT NULL"),
    ("",   "is_active",     "BOOLEAN DEFAULT TRUE (BR-19)"),
    ("",   "created_at",    "DATETIME DEFAULT CURRENT_TIMESTAMP"),
])

# ===========================================================================
# RELATIONSHIPS (Clean Corridors -> ZERO Box Crossings)
# ===========================================================================
# Admin <-> Doctor / Permission / Med Log
rel(t_admin, t_doctor, "creates account for\n1:N mandatory (BR-18)", color="#475569",
    exit_xy=(1, 0.35), entry_xy=(0, 0.25))
rel(t_admin, t_perm, "holds / grants\n1:N mandatory (BR-20)", color="#475569",
    exit_xy=(0.5, 1), entry_xy=(0.5, 0))
rel(t_admin, t_med_log, "performs\n1:N mandatory (BR-25)", color="#475569",
    exit_xy=(0, 0.5), entry_xy=(0, 0.45), wps=[(28, 250), (28, 1495)], lbl_pos=-0.35)

# Specialization: DOCTOR ==(d)==> GP | SPECIALIST
eid_d = nid("rel")
cells.append(
    f'<mxCell id="{eid_d}" value="" style="shape=link;html=1;strokeColor=#2563EB;strokeWidth=1.8;'
    f'endArrow=none;width=5;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" '
    f'edge="1" parent="1" source="{t_doctor}" target="{eer_d}"><mxGeometry relative="1" as="geometry"/></mxCell>'
)
edges_meta.append((t_doctor, eer_d, [], (0.5, 1), (0.5, 0), "d"))
rel(eer_d, t_gp,   "⊂", color="#2563EB", exit_xy=(0, 0.5), entry_xy=(0.5, 0))
rel(eer_d, t_spec, "⊂", color="#2563EB", exit_xy=(1, 0.5), entry_xy=(0.5, 0))

# Specialty -> Specialist
rel(t_specialty, t_spec, "classifies\n1:N mandatory (BR-02)", color="#2563EB",
    exit_xy=(0, 0.5), entry_xy=(1, 0.72), wps=[(1140, 632), (1140, 604)])

# Doctor -> Shift, Room -> Shift
rel(t_doctor, t_shift, "registers\n1:N mandatory (BR-04)", color="#059669",
    exit_xy=(1, 0.80), entry_xy=(0, 0.28), wps=[(1130, 342), (1130, 363)])
rel(t_room, t_shift, "used for (GP only, Trigger BR-03/26)\n1:N optional (nullable FK)", color="#059669",
    dashed=True, exit_xy=(0.5, 1), entry_xy=(0.5, 0))

# Shift -> Appointment, Patient -> Appointment
rel(t_shift, t_appt, "hosts (derives doctor)\n1:N mandatory (BR-07,08)", color="#059669",
    exit_xy=(0, 0.78), entry_xy=(1, 0.25), wps=[(1135, 494), (1135, 770)])
rel(t_patient, t_appt, "books\n1:N mandatory (BR-06)", color="#059669",
    exit_xy=(1, 0.45), entry_xy=(0, 0.25))

# Appointment -> Medical Record -> Prescription -> Prescription Item <- Medication
rel(t_appt, t_mr, "produces\n1:0..1 optional (BR-12)", color="#7C3AED",
    exit_xy=(0.5, 1), entry_xy=(0.5, 0))
rel(t_mr, t_presc, "results in\n1:0..1 optional (BR-14)", color="#7C3AED",
    exit_xy=(0.5, 1), entry_xy=(0.5, 0))
rel(t_presc, t_pitem, "contains\n1:N mandatory (BR-15)", color="#7C3AED",
    exit_xy=(1, 0.5), entry_xy=(0, 0.35))
rel(t_med, t_pitem, "listed in\nM:N via PRESCRIPTION_ITEM (BR-16)", color="#D97706",
    exit_xy=(0, 0.45), entry_xy=(1, 0.45))

# Medication -> Medication Audit Log (clean bottom corridor y=1705)
rel(t_med, t_med_log, "logged for\n1:N mandatory (BR-25)", color="#D97706",
    exit_xy=(0.5, 1), entry_xy=(0.5, 1), wps=[(1985, 1705), (280, 1705)])

# Medical Record & Doctor (x2) -> Consultation Request
rel(t_mr, t_consult, "referred via\n1:N optional (BR-22)", color="#7C3AED",
    exit_xy=(1, 0.12), entry_xy=(0, 0.85), wps=[(1135, 1062), (1135, 1005)])
rel(t_doctor, t_consult, "requests (treating)\n1:N mandatory (BR-23)", color="#7C3AED",
    exit_xy=(1, 0.46), entry_xy=(1, 0.25), wps=[(1735, 243), (1735, 815)], lbl_pos=0.38)
rel(t_doctor, t_consult, "invited as consulting\n1:N mandatory (BR-21,22)", color="#7C3AED",
    exit_xy=(1, 0.52), entry_xy=(1, 0.48), wps=[(1795, 261), (1795, 888)], lbl_pos=0.38)

# Medical Record & Exclusive Arc Actors -> Medical Record Audit Log
rel(t_mr, t_mr_log, "audited via\n1:N mandatory (NFR-04)", color="#7C3AED",
    exit_xy=(1, 0.55), entry_xy=(0, 0.42), wps=[(1135, 1210), (1135, 1220)])
rel(t_patient, t_mr_log, "actor FK (Exclusive Arc NFR-04)", color="#DB2777", dashed=True,
    exit_xy=(0.5, 1), entry_xy=(0, 0.78), wps=[(280, 995), (540, 995), (540, 1406), (1150, 1406), (1150, 1314)], lbl_pos=0.1)
rel(t_doctor, t_mr_log, "actor FK (Exclusive Arc NFR-04)", color="#DB2777", dashed=True,
    exit_xy=(1, 0.58), entry_xy=(1, 0.40), wps=[(1855, 278), (1855, 1215)], lbl_pos=0.4)
rel(t_admin, t_mr_log, "actor FK (Exclusive Arc NFR-04)", color="#DB2777", dashed=True,
    exit_xy=(0.5, 0), entry_xy=(1, 0.65), wps=[(280, 75), (1920, 75), (1920, 1280)], lbl_pos=0.35)


# ===========================================================================
# GEOMETRY VERIFICATION (0 Overlaps & 0 Edge-Through-Box Crossings)
# ===========================================================================
def seg_intersects_rect(x1, y1, x2, y2, rx, ry, rw, rh):
    # Shrink slightly inside border so touching boundary at exit/entry isn't flagged
    left, right = rx + 2, rx + rw - 2
    top, bottom = ry + 2, ry + rh - 2
    for i in range(1, 60):
        t = i / 60.0
        px = x1 + (x2 - x1) * t
        py = y1 + (y2 - y1) * t
        if left <= px <= right and top <= py <= bottom:
            return True
    return False


ov = 0
items = list(boxes.items())
for i in range(len(items)):
    _, (x1, y1, w1, h1, n1) = items[i]
    for j in range(i + 1, len(items)):
        _, (x2, y2, w2, h2, n2) = items[j]
        if x1 < x2 + w2 and x1 + w1 > x2 and y1 < y2 + h2 and y1 + h1 > y2:
            print(f"[OVERLAP] {n1} <-> {n2}")
            ov += 1

cross = 0
for src, tgt, wps, ex, en, lbl in edges_meta:
    sx, sy, sw, sh, sn = boxes[src]
    tx, ty, tw, th, tn = boxes[tgt]
    p0 = (sx + sw * (ex[0] if ex else 0.5), sy + sh * (ex[1] if ex else 0.5))
    pN = (tx + tw * (en[0] if en else 0.5), ty + th * (en[1] if en else 0.5))
    pts = [p0] + wps + [pN]
    for k in range(len(pts) - 1):
        a, b = pts[k], pts[k + 1]
        for bid, (bx, by, bw, bh, bn) in boxes.items():
            if bid in (src, tgt):
                continue
            if seg_intersects_rect(a[0], a[1], b[0], b[1], bx, by, bw, bh):
                print(f"[BOX CROSS] {sn} -> {tn} crosses {bn}")
                cross += 1

print(f"Tables/circles: {len(boxes)}, Overlaps: {ov}, Box crossings: {cross}")

xml = (
    '<mxfile host="app.diagrams.net">'
    '<diagram name="EERD - Healthcare Clinic" id="eerd-healthcare-table">'
    '<mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" '
    'connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="2240" '
    'pageHeight="1760" background="#FFFFFF" math="0" shadow="0">'
    '<root><mxCell id="0"/><mxCell id="1" parent="0"/>'
    + "".join(cells) +
    '</root></mxGraphModel></diagram></mxfile>'
)
out = Path(__file__).with_name("EERD.drawio")
out.write_text(xml, encoding="utf-8")
print(f"Generated cleanly: {out}")
