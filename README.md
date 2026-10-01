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

- [x] Problem statement, actor definitions
- [x] Business rules (BR-00 to BR-26)
- [x] EER diagram
- [x] Attribute data dictionary
- [x] Relationship definitions
- [x] Relational schema mapping (Elmasri Steps 1-9)
- [x] Normalization (3NF/BCNF proof)
- [ ] EER diagram redraw + Crow's Foot physical diagram (Appendix A)
- [ ] DDL + mock data
- [ ] Queries, triggers, views
- [ ] Backend integration + demo

## Timeline (12 weeks)

| Phase | Week | Deliverables |
|---|---|---|
| 1 - Conceptual Design | 3-4 | Problem statement, BR, EER diagram |
| 2 - Logical Design | 5-8 | Schema mapping, FK, normalization |
| 3 - Implementation | 9-10 | DDL, mock data, queries, triggers/views |
| 4 - Integration & Defense | 11-12 | UI/backend, demo, defense |

## Docs

Full report lives in `/docs`, following the course template, based on ISO/IEC/IEEE 29148 (requirements) and ISO/IEC 11179 (data dictionary).
