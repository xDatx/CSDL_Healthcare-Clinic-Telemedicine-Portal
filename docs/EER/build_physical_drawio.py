#!/usr/bin/env python3
"""
Generate a clean, light-theme, 100% DDL-accurate IE Crow's Foot Physical Diagram (.drawio)
matching sql/ddl/01..10.sql, sql/02_indexes.sql, and Appendix A of database_project_report.docx.

Run: python docs/EER/build_physical_drawio.py
Outputs: docs/EER/physical_diagram_crows_foot.drawio
"""
import html
from pathlib import Path

cells = []
boxes = {}
_n = [10]
nid = lambda p="p": (_n.__setitem__(0, _n[0] + 1) or f"{p}{_n[0]}")
esc = lambda s: html.escape(s, quote=True)

# Color Themes (Matching EER Module Colors)
THEMES = {
    "admin":    ("#475569", "#F8FAFC"),
    "doctor":   ("#2563EB", "#EFF6FF"),
    "schedule": ("#059669", "#ECFDF5"),
    "clinical": ("#7C3AED", "#F5F3FF"),
    "pharma":   ("#D97706", "#FFFBEB"),
}

BADGE_COLOR = {
    "PK":     "#B45309",
    "PK,FK":  "#B45309",
    "PK,UQ2": "#B45309",
    "FK":     "#1D4ED8",
    "FK,UQ":  "#1D4ED8",
    "FK,UQ1": "#1D4ED8",
    "FK,IDX1":"#1D4ED8",
    "FK,IDX2":"#1D4ED8",
    "FK,CHK": "#1D4ED8",
    "UQ":     "#047857",
    "UQ1":    "#047857",
    "UQ1,CHK":"#047857",
    "IDX1":   "#0369A1",
    "IDX2":   "#0369A1",
    "CHK":    "#6D28D9",
    "":       "#64748B",
}


def table(name, x, y, w, theme, cols, subtitle=None):
    hdr, body = THEMES[theme]
    row_h = 22
    h = 30 + len(cols) * row_h
    title = f"{name}  {subtitle}" if subtitle else name
    tid = nid("t")
    cells.append(
        f'<mxCell id="{tid}" value="{esc(title)}" style="swimlane;fontStyle=1;childLayout=stackLayout;'
        f'horizontal=1;startSize=30;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;'
        f'collapsible=0;marginBottom=0;fillColor={hdr};strokeColor={hdr};fontColor=#FFFFFF;fontSize=12.5;'
        f'rounded=0;swimlaneFillColor={body};" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>'
    )
    boxes[tid] = (x, y, w, h, name)

    for idx, (badge, col, typ) in enumerate(cols):
        bc = BADGE_COLOR.get(badge, "#475569")
        is_pk = "PK" in badge
        col_disp = f"<u><b>{esc(col)}</b></u>" if is_pk else f"<b>{esc(col)}</b>"
        val = (
            f'<span style="display:inline-block;width:64px"><b><font color="{bc}">{esc(badge)}</font></b></span>'
            f'{col_disp} <font color="#475569">: {esc(typ)}</font>'
        )
        rid = nid("r")
        cells.append(
            f'<mxCell id="{rid}" value="{esc(val)}" style="text;html=1;strokeColor=none;fillColor=none;'
            f'align=left;verticalAlign=middle;spacingLeft=6;spacingRight=4;overflow=hidden;rotatable=0;'
            f'points=[[0,0.5],[1,0.5]];portConstraint=eastwest;fontSize=10.5;fontColor=#0F172A;whiteSpace=nowrap;" '
            f'vertex="1" parent="{tid}"><mxGeometry y="{30 + idx * row_h}" width="{w}" height="{row_h}" as="geometry"/></mxCell>'
        )
    return tid


def rel(src, tgt, start_arrow, end_arrow, label="", dashed=False, color="#334155", wps=None):
    eid = nid("cf")
    dash = "dashed=1;dashPattern=6 4;" if dashed else ""
    style = (
        f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;startArrow={start_arrow};endArrow={end_arrow};"
        f"startFill=0;endFill=0;startSize=10;endSize=10;strokeColor={color};strokeWidth=1.5;{dash}"
        f"fontSize=10;fontStyle=1;fontColor=#1E293B;labelBackgroundColor=#FFFFFF;"
    )
    pts = ""
    if wps:
        pts = '<Array as="points">' + "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in wps) + "</Array>"
    cells.append(
        f'<mxCell id="{eid}" value="{esc(label)}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">'
        f'<mxGeometry relative="1" as="geometry">{pts}</mxGeometry></mxCell>'
    )
    return eid


# ===========================================================================
# HEADER & LEGEND
# ===========================================================================
title_text = esc("Physical Database Diagram — IE Crow's Foot Notation (MySQL 8.0 DDL)")
cells.append(
    f'<mxCell id="{nid()}" value="{title_text}" '
    f'style="text;html=1;align=left;verticalAlign=middle;fontSize=21;fontStyle=1;fontColor=#0F172A;" '
    f'vertex="1" parent="1"><mxGeometry x="70" y="20" width="900" height="36" as="geometry"/></mxCell>'
)

legend_html = (
    "<b>IE Crow's Foot Physical Legend (Appendix A / 17 Tables)</b><br>"
    "• <b>Solid line</b>: Identifying / Mandatory non-null FK &nbsp;|&nbsp; "
    "<b>Dashed line</b>: Optional (nullable) FK<br>"
    "• <b>||</b> One &amp; only one &nbsp;|&nbsp; <b>o|</b> Zero or one &nbsp;|&nbsp; "
    "<b>|{</b> One or many &nbsp;|&nbsp; <b>o{</b> Zero or many<br>"
    "• <b>[AES-256]</b>: Storage-level TDE tablespace (NFR-04) &nbsp;|&nbsp; "
    "<b>vital_signs</b> flattened to 5 columns (1NF)<br>"
    "• <b>Exclusive Arc (NFR-04)</b>: 3 nullable actor FKs + <code>ck_mr_audit_one_actor (= 1)</code>"
)
cells.append(
    f'<mxCell id="{nid()}" value="{esc(legend_html)}" '
    f'style="shape=note;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=8;fontSize=10.5;'
    f'fillColor=#FFFBEB;strokeColor=#D97706;fontColor=#0F172A;size=14;" vertex="1" parent="1">'
    f'<mxGeometry x="1060" y="15" width="580" height="92" as="geometry"/></mxCell>'
)

# ===========================================================================
# COLUMN 1 (x = 70): Admin, Patient, Medication Audit
# ===========================================================================
t_admin = table("admin", 70, 80, 410, "admin", [
    ("PK",  "admin_id",   "INT AUTO_INCREMENT"),
    ("",    "full_name",  "VARCHAR(100) NOT NULL"),
    ("UQ",  "email",      "VARCHAR(120) NOT NULL UNIQUE"),
    ("CHK", "role",       "VARCHAR(20) NOT NULL (RECEPTIONIST|SYSTEM_ADMIN)"),
    ("",    "is_active",  "BOOLEAN NOT NULL DEFAULT TRUE"),
    ("",    "created_at", "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

t_perm = table("staff_permission", 70, 290, 410, "admin", [
    ("PK",      "permission_id",   "INT AUTO_INCREMENT"),
    ("FK,UQ1",  "admin_id",        "INT NOT NULL -> admin(admin_id)"),
    ("UQ1,CHK", "permission_code", "VARCHAR(50) NOT NULL (4 codes)"),
    ("FK",      "granted_by",      "INT NOT NULL -> admin(admin_id)"),
    ("",        "granted_at",      "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

t_patient = table("patient", 70, 480, 410, "schedule", [
    ("PK",  "patient_id", "INT AUTO_INCREMENT"),
    ("",    "full_name",  "VARCHAR(100) NOT NULL"),
    ("",    "dob",        "DATE NOT NULL"),
    ("CHK", "phone",      "VARCHAR(20) NULL (BR-00: phone OR email)"),
    ("CHK", "email",      "VARCHAR(120) NULL (BR-00: phone OR email)"),
    ("",    "address",    "TEXT NULL"),
    ("",    "created_at", "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

t_med_audit = table("medication_audit_log", 70, 1450, 410, "pharma", [
    ("PK",  "audit_id",      "BIGINT AUTO_INCREMENT"),
    ("FK",  "medication_id", "INT NOT NULL -> medication(medication_id)"),
    ("FK",  "admin_id",      "INT NOT NULL -> admin(admin_id)"),
    ("CHK", "action",        "VARCHAR(15) NOT NULL (INSERT|UPDATE|DEACTIVATE)"),
    ("",    "action_at",     "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
    ("",    "old_values",    "JSON NULL"),
    ("",    "new_values",    "JSON NULL"),
])

# ===========================================================================
# COLUMN 2 (x = 580): Doctor Spine -> Appointment -> Record -> Prescription
# ===========================================================================
t_doctor = table("doctor", 580, 75, 440, "doctor", [
    ("PK,UQ2",  "doctor_id",       "INT AUTO_INCREMENT"),
    ("",        "full_name",       "VARCHAR(100) NOT NULL"),
    ("UQ",      "email",           "VARCHAR(120) NOT NULL UNIQUE"),
    ("UQ",      "license_no",      "VARCHAR(50) NOT NULL UNIQUE"),
    ("CHK",     "employment_type", "VARCHAR(10) NOT NULL (FULL_TIME|PART_TIME)"),
    ("UQ2,CHK", "spec_type",       "VARCHAR(10) NOT NULL (GP|SPECIALIST)"),
    ("",        "is_active",       "BOOLEAN NOT NULL DEFAULT FALSE"),
    ("FK",      "created_by",      "INT NOT NULL -> admin(admin_id)"),
    ("",        "created_at",      "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

t_gp = table("gp", 580, 345, 200, "doctor", [
    ("PK,FK",  "doctor_id", "INT -> doctor"),
    ("FK,CHK", "spec_type", "VARCHAR(10) = 'GP'"),
])

t_spec = table("specialist", 805, 345, 245, "doctor", [
    ("PK,FK",  "doctor_id",      "INT -> doctor"),
    ("FK,CHK", "spec_type",      "VARCHAR(10) = 'SPECIALIST'"),
    ("FK",     "specialty_id",   "INT NOT NULL -> specialty"),
    ("CHK",    "years_practice", "INT NOT NULL (>= 0)"),
])

t_appt = table("appointment", 580, 520, 440, "schedule", [
    ("PK",      "appointment_id",   "INT AUTO_INCREMENT"),
    ("FK,IDX2", "patient_id",       "INT NOT NULL -> patient(patient_id)"),
    ("FK,IDX1", "shift_id",         "INT NOT NULL -> shift(shift_id)"),
    ("IDX1",    "start_time",       "DATETIME NOT NULL"),
    ("CHK",     "end_time",         "DATETIME NOT NULL (> start_time)"),
    ("CHK",     "appointment_type", "VARCHAR(15) NOT NULL (IN_PERSON|TELEMED)"),
    ("CHK",     "status",           "VARCHAR(15) NOT NULL DEFAULT 'PENDING'"),
    ("",        "created_at",       "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

t_mr = table("medical_record", 580, 775, 440, "clinical", [
    ("PK",    "record_id",         "INT AUTO_INCREMENT"),
    ("FK,UQ", "appointment_id",    "INT NOT NULL UNIQUE -> appointment"),
    ("CHK",   "systolic_bp",       "INT NULL (60..250)"),
    ("CHK",   "diastolic_bp",      "INT NULL (30..150, < systolic_bp)"),
    ("CHK",   "heart_rate",        "INT NULL (20..250)"),
    ("CHK",   "temperature_c",     "DECIMAL(4,1) NULL (30.0..45.0)"),
    ("CHK",   "oxygen_saturation", "INT NULL (50..100)"),
    ("",      "symptoms",          "TEXT NULL"),
    ("",      "diagnosis",         "TEXT NOT NULL"),
    ("",      "notes",             "TEXT NULL"),
    ("",      "created_at",        "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
], subtitle="[AES-256]")

t_presc = table("prescription", 580, 1110, 440, "clinical", [
    ("PK",    "prescription_id", "INT AUTO_INCREMENT"),
    ("FK,UQ", "record_id",       "INT NOT NULL UNIQUE -> medical_record"),
    ("",      "issued_at",       "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
], subtitle="[AES-256]")

t_pitem = table("prescription_item", 580, 1265, 440, "clinical", [
    ("PK,FK", "prescription_id", "INT NOT NULL -> prescription (CASCADE)"),
    ("PK,FK", "medication_id",   "INT NOT NULL -> medication (RESTRICT)"),
    ("CHK",   "quantity",        "INT NOT NULL (> 0)"),
    ("",      "dosage",          "VARCHAR(120) NOT NULL"),
    ("",      "frequency",       "VARCHAR(120) NOT NULL"),
    ("CHK",   "duration_days",   "INT NOT NULL (> 0)"),
], subtitle="[Composite PK | AES-256]")

# ===========================================================================
# COLUMN 3 (x = 1140): Room, Shift, Specialty, Consultation, MR Audit, Medication
# ===========================================================================
t_room = table("room", 1140, 125, 450, "schedule", [
    ("PK",  "room_id",   "INT AUTO_INCREMENT"),
    ("UQ",  "room_code", "VARCHAR(20) NOT NULL UNIQUE"),
    ("CHK", "floor",     "INT NOT NULL (1..20)"),
])

t_shift = table("shift", 1140, 265, 450, "schedule", [
    ("PK",      "shift_id",      "INT AUTO_INCREMENT"),
    ("FK,IDX1", "doctor_id",     "INT NOT NULL -> doctor(doctor_id)"),
    ("IDX1",    "shift_date",    "DATE NOT NULL"),
    ("IDX1",    "start_time",    "TIME NOT NULL"),
    ("CHK",     "end_time",      "TIME NOT NULL (> start_time)"),
    ("CHK",     "status",        "VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'"),
    ("FK,IDX2", "room_id",       "INT NULL -> room(room_id) [BR-03/26 Trigger]"),
    ("CHK",     "rate_per_hour", "DECIMAL(10,2) NULL (> 0)"),
])

t_specialty = table("specialty", 1140, 515, 450, "doctor", [
    ("PK", "specialty_id", "INT AUTO_INCREMENT"),
    ("UQ", "name",         "VARCHAR(80) NOT NULL UNIQUE"),
])

t_consult = table("consultation_request", 1140, 640, 450, "clinical", [
    ("PK",      "request_id",           "INT AUTO_INCREMENT"),
    ("FK,IDX1", "record_id",            "INT NOT NULL -> medical_record"),
    ("FK,CHK",  "requesting_doctor_id", "INT NOT NULL -> doctor"),
    ("FK,IDX1", "consulting_doctor_id", "INT NOT NULL -> doctor (<> req)"),
    ("",        "reason",               "TEXT NOT NULL"),
    ("IDX1,CHK","status",               "VARCHAR(15) NOT NULL DEFAULT 'PENDING'"),
    ("",        "requested_at",         "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
    ("CHK",     "responded_at",         "DATETIME NULL"),
    ("IDX2,CHK","expires_at",           "DATETIME NULL (> requested_at)"),
    ("CHK",     "opinion",              "TEXT NULL (req if COMPLETED)"),
])

t_mr_audit = table("medical_record_audit_log", 1140, 945, 450, "clinical", [
    ("PK",      "audit_id",   "BIGINT AUTO_INCREMENT"),
    ("FK,IDX1", "record_id",  "INT NOT NULL -> medical_record"),
    ("FK,CHK",  "patient_id", "INT NULL -> patient (Exclusive Arc)"),
    ("FK,CHK",  "doctor_id",  "INT NULL -> doctor (Exclusive Arc)"),
    ("FK,CHK",  "admin_id",   "INT NULL -> admin (Exclusive Arc)"),
    ("CHK",     "action",     "VARCHAR(10) NOT NULL (INSERT|UPDATE|SELECT)"),
    ("IDX1",    "action_at",  "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
    ("",        "details",    "JSON NULL"),
], subtitle="[Exclusive Arc]")

t_med = table("medication", 1140, 1265, 450, "pharma", [
    ("PK", "medication_id", "INT AUTO_INCREMENT"),
    ("",   "name",          "VARCHAR(120) NOT NULL"),
    ("",   "unit",          "VARCHAR(20) NOT NULL"),
    ("",   "description",   "TEXT NULL"),
    ("",   "is_active",     "BOOLEAN NOT NULL DEFAULT TRUE"),
    ("",   "created_at",    "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"),
])

# ===========================================================================
# RELATIONSHIPS (IE Crow's Foot)
# ===========================================================================
# Admin <-> Staff Permission (holds, grants)
rel(t_admin, t_perm, "ERmandOne", "ERzeroToMany", "holds (admin_id)", color="#475569", wps=[(210, 265)])
rel(t_admin, t_perm, "ERmandOne", "ERzeroToMany", "grants (granted_by)", color="#475569", wps=[(340, 265)])

# Admin -> Doctor
rel(t_admin, t_doctor, "ERmandOne", "ERzeroToMany", "created_by", color="#475569")

# Doctor -> GP / Specialist (Identifying 1:0..1, Option 8A)
rel(t_doctor, t_gp,   "ERmandOne", "ERzeroToOne", "spec='GP'", color="#2563EB")
rel(t_doctor, t_spec, "ERmandOne", "ERzeroToOne", "spec='SPECIALIST'", color="#2563EB")

# Specialty -> Specialist
rel(t_specialty, t_spec, "ERmandOne", "ERzeroToMany", "specialty_id", color="#2563EB", wps=[(1085, 550), (1085, 420)])

# Doctor -> Shift
rel(t_doctor, t_shift, "ERmandOne", "ERzeroToMany", "doctor_id", color="#059669", wps=[(1080, 180), (1080, 320)])

# Room -> Shift (Optional / Nullable FK, Trigger BR-03/26)
rel(t_room, t_shift, "ERzeroToOne", "ERzeroToMany", "room_id (NULL for Specialist)", dashed=True, color="#059669")

# Patient -> Appointment, Shift -> Appointment
rel(t_patient, t_appt, "ERmandOne", "ERzeroToMany", "patient_id", color="#059669", wps=[(530, 560)])
rel(t_shift,   t_appt, "ERmandOne", "ERzeroToMany", "shift_id",   color="#059669", wps=[(1100, 410), (1100, 580)])

# Appointment -> Medical Record -> Prescription -> Prescription Item
rel(t_appt,  t_mr,    "ERmandOne", "ERzeroToOne", "appointment_id (UQ)", color="#7C3AED")
rel(t_mr,    t_presc, "ERmandOne", "ERzeroToOne", "record_id (UQ)",      color="#7C3AED")
rel(t_presc, t_pitem, "ERmandOne", "ERoneToMany", "contains (BR-15)",    color="#7C3AED")

# Medication -> Prescription Item
rel(t_med, t_pitem, "ERmandOne", "ERzeroToMany", "listed in (BR-16)", color="#D97706")

# Medication & Admin -> Medication Audit Log
rel(t_med,   t_med_audit, "ERmandOne", "ERzeroToMany", "medication_id", color="#D97706", wps=[(1365, 1550)])
rel(t_admin, t_med_audit, "ERmandOne", "ERzeroToMany", "admin_id", color="#475569", wps=[(35, 145), (35, 1550)])

# Medical Record & Doctor (x2) -> Consultation Request
rel(t_mr,     t_consult, "ERmandOne", "ERzeroToMany", "record_id",            color="#7C3AED", wps=[(1075, 830), (1075, 720)])
rel(t_doctor, t_consult, "ERmandOne", "ERzeroToMany", "requesting_doctor_id", color="#7C3AED", wps=[(1645, 120), (1645, 700)])
rel(t_doctor, t_consult, "ERmandOne", "ERzeroToMany", "consulting_doctor_id", color="#7C3AED", wps=[(1675, 100), (1675, 740)])

# Medical Record & Exclusive Arc Actors -> Medical Record Audit Log
rel(t_mr,      t_mr_audit, "ERmandOne",  "ERzeroToMany", "record_id",          color="#7C3AED", wps=[(1080, 960), (1080, 995)])
rel(t_patient, t_mr_audit, "ERzeroToOne","ERzeroToMany", "patient_id (arc)",   dashed=True, color="#DB2777", wps=[(530, 740), (530, 1090), (1095, 1090)])
rel(t_doctor,  t_mr_audit, "ERzeroToOne","ERzeroToMany", "doctor_id (arc)",    dashed=True, color="#DB2777", wps=[(1710, 80), (1710, 1050)])
rel(t_admin,   t_mr_audit, "ERzeroToOne","ERzeroToMany", "admin_id (arc)",     dashed=True, color="#DB2777", wps=[(1745, 60), (1745, 1080)])


# Verify no table boxes overlap
ov = 0
tlist = list(boxes.items())
for i in range(len(tlist)):
    _, (x1, y1, w1, h1, n1) = tlist[i]
    for j in range(i + 1, len(tlist)):
        _, (x2, y2, w2, h2, n2) = tlist[j]
        if (x1 < x2 + w2 and x1 + w1 > x2 and y1 < y2 + h2 and y1 + h1 > y2):
            print(f"[OVERLAP] {n1} <-> {n2}")
            ov += 1
print(f"Physical tables: {len(boxes)}, Overlaps: {ov}")

xml = (
    '<mxfile host="app.diagrams.net">'
    '<diagram name="Physical Diagram (IE Crow\'s Foot)" id="physical-crows-foot-v2">'
    '<mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" '
    'connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="1820" '
    'pageHeight="1700" background="#FFFFFF" math="0" shadow="0">'
    '<root><mxCell id="0"/><mxCell id="1" parent="0"/>'
    + "".join(cells) +
    '</root></mxGraphModel></diagram></mxfile>'
)
out = Path(__file__).with_name("physical_diagram_crows_foot.drawio")
out.write_text(xml, encoding="utf-8")
print(f"Generated cleanly: {out}")
