# Telemedicine Portal & Clinical Management DB

Database course project — INT1313, Semester 1 2026-2027.

We're building a database for a small clinic that does both in-person and remote visits. Right now these clinics run on paper and phone calls, which means doctors get double-booked, patient records are scattered everywhere, and nobody can track prescriptions properly. This project puts it all in one schema: patient profiles, doctor shifts, appointment booking, medical records, prescriptions.

## Team — Phải Tin tui

- Nguyễn Hoàng Dũng — n24dccn110@student.ptithcm.edu.vn
- Lý Thành Đạt — n24dccn103@student.ptithcm.edu.vn
- Phạm Trần Quốc Việt — n24dccn182@student.ptithcm.edu.vn

## Scope

Outpatients only (seen same-day, no admission), so no wards or beds anywhere in the schema.

Doctors are classified along 3 independent axes:
- GP or Specialist (clinical role)
- Full-time or Part-time (employment type, only affects pay)
- Treating or Consulting (per case — a consulting doctor is invited to review one specific record, nothing more)

The biggest piece is case-based access control on medical records — a doctor can only see records of appointments in their own shifts. Cross-specialty (second-opinion) access needs a consultation request accepted by the invited doctor first.

## Current status

### Phase 1 — Conceptual Design ✅
- [x] Problem statement, actor definitions
- [x] Business rules (BR-00 to BR-26)
- [x] EER diagram

### Phase 2 — Logical Design ✅
- [x] Attribute data dictionary
- [x] Relationship definitions
- [x] Relational schema mapping (Elmasri Steps 1–9)
- [x] Normalization (3NF/BCNF proof)

### Phase 3 — Implementation & Queries ✅
- [x] DDL (10 tables, 6 indexes, composite FK, CHECK constraints)
- [x] Triggers (12+ triggers covering BR-01, 03, 05, 08, 09, 11, 12, 19, 20, 23, 24, 25, 26 + NFR-04)
- [x] Stored procedure `sp_read_medical_record` with audit
- [x] 3 views (patient history, doctor availability, active consultations)
- [x] 10 complex queries (joins, subqueries, aggregations)
- [x] Seed data (small + bulk: 10,002 patients, 302 appointments, 5,002 items)
- [x] RBAC (app_patient / app_doctor / app_admin)
- [x] 10 test cases (TC-01..TC-10) — all PASS
- [x] Performance evidence (Q01: 0.03ms, Q03: 0.6ms, Q05: 8.65ms)

### Phase 4 — Integration & Defense ⬜
- [ ] Backend integration (Flask/Node)
- [ ] Live demo scenarios
- [ ] Defense preparation

## Timeline (12 weeks)

| Phase | Week | Deliverables |
|---|---|---|
| 1 — Conceptual Design | 3–4 | Problem statement, BR, EER diagram |
| 2 — Logical Design | 5–8 | Schema mapping, FK, normalization |
| 3 — Implementation | 9–10 | DDL, mock data, queries, triggers/views |
| 4 — Integration & Defense | 11–12 | UI/backend, demo, defense |

## Docs

- Full report: `/docs`, following course template, based on ISO/IEC/IEEE 29148 (requirements) and ISO/IEC 11179 (data dictionary).
- SQL execution guide: [`README_SQL.md`](README_SQL.md)
- Traceability matrix: [`docs/traceability_matrix.md`](docs/traceability_matrix.md)
- Performance evidence: [`docs/performance.md`](docs/performance.md)

## Quick start

```bash
# 1. Tạo database
mysql -u root -p < sql/00_init.sql

# 2. Chạy DDL theo thứ tự (xem README_SQL.md)
# 3. Chạy seed + RBAC + tests
