# Telemedicine Portal & Clinical Management DB

Database course project - INT1313, Semester 1 2026-2027.

We're building a database for a small clinic that does both in-person and remote visits. Right now these clinics run on paper and phone calls, which means doctors get double-booked, patient records are scattered everywhere, and nobody can track prescriptions properly. This project puts it all in one schema: patient profiles, doctor shifts, appointment booking, medical records, prescriptions.

## Team - Phải Tin tui

- Nguyễn Hoàng Dũng
- Lý Thành Đạt
- Phạm Trần Quốc Việt

## Scope

Outpatients only (seen same-day, no admission), so no wards or beds anywhere in the schema.

Doctors are classified along 3 independent axes:
- GP or Specialist (clinical role)
- Full-time or Part-time (employment type, only affects pay)
- Treating or Consulting (per case - a consulting doctor is invited to review one specific record, nothing more)

The biggest piece is case-based access control on medical records - a doctor can only see records of appointments in their own shifts. Cross-specialty (second-opinion) access needs a consultation request accepted by the invited doctor first.

## Current status

### Phase 1 - Conceptual Design
- [x] Problem statement, actor definitions
- [x] Business rules (BR-00 to BR-26)
- [x] EER diagram

### Phase 2 - Logical Design
- [x] Attribute data dictionary
- [x] Relationship definitions
- [x] Relational schema mapping (Elmasri Steps 1-9)
- [x] Normalization (3NF/BCNF proof)

### Phase 3 - Implementation & Queries
- [x] DDL: 17 tables, composite PK / FK, CHECK constraints, 7 indexes
- [x] 25 triggers + shared validation procedures (BR-01, 03, 05, 08, 09, 11, 12, 19, 20, 22-26, NFR-04)
- [x] `sp_read_medical_record` / `sp_patient_history`: authorised and audited access to clinical data (NFR-02, NFR-04)
- [x] 6 views (availability, appointment detail, active consultations, part-time pay, medication catalog, internal history)
- [x] 16 queries (joins, subqueries, aggregates, CTE, recursive CTE, window functions, ROLLUP)
- [x] Seed data: small hand-written set + bulk set (50 active doctors, 10,021 patients, 19,726 appointments)
- [x] RBAC: 3 roles, least privilege, no direct access to clinical tables
- [x] 60 automated test cases, all PASS ([traceability matrix](docs/traceability_matrix.md))
- [x] Performance evidence with before/after plans ([docs/performance.md](docs/performance.md))
- [ ] Update the report (`database_project_report.docx`) so that column names and the audit design match the DDL
- [ ] Encryption of clinical data at rest (NFR-04, AES-256)

### Phase 4 - Integration & Defense
- [ ] Backend integration (authenticated user id passed to the access procedures)
- [ ] Live demo scenarios
- [ ] Defense preparation

## Timeline (12 weeks)

| Phase | Week | Deliverables |
|---|---|---|
| 1 - Conceptual Design | 3-4 | Problem statement, BR, EER diagram |
| 2 - Logical Design | 5-8 | Schema mapping, FK, normalization |
| 3 - Implementation | 9-10 | DDL, mock data, queries, triggers/views |
| 4 - Integration & Defense | 11-12 | UI/backend, demo, defense |

## Docs

Full report lives in `/docs`, following the course template, based on ISO/IEC/IEEE 29148 (requirements) and ISO/IEC 11179 (data dictionary).

- SQL guide (Vietnamese): [`README_SQL.md`](README_SQL.md)
- Traceability matrix: [`docs/traceability_matrix.md`](docs/traceability_matrix.md)
- Performance evidence: [`docs/performance.md`](docs/performance.md)

## Quick start

Needs MySQL 8.0.18+.

```bash
cd sql
mysql -u root -p --default-character-set=utf8mb4 -e "source run_all.sql"     # build schema, triggers, views, seed, RBAC
cd ..
mysql -u root -p --default-character-set=utf8mb4 healthcare < tests/run_all_tests.sql   # expect 60 / 60 PASS
```

See [`README_SQL.md`](README_SQL.md) for DBeaver, the bulk data set and the performance scripts.
