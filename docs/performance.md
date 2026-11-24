# Performance evidence (NFR-01 / NFR-03)

Measured with `EXPLAIN ANALYZE` on MySQL 8.0.46 (local, default configuration), after loading the bulk seeds.
Scripts: [`tests/performance_explain.sql`](../tests/performance_explain.sql) (plans of the real access paths) and
[`tests/performance_before_after.sql`](../tests/performance_before_after.sql) (same query with and without its index, using `IGNORE INDEX`).
Times are the `actual time` of the top plan node in milliseconds; they vary a little between runs, the ratios do not.

## Data volume (NFR-03)

| Table | Rows |
|---|---|
| doctor (active) | 50 (9 original + 41 bulk) |
| patient | 10,021 |
| shift | 2,484 |
| appointment | 19,726 |
| medical_record | 5,933 |
| prescription_item | 5,946 |
| medication | 520 |
| medical_record_audit_log | 5,938 |

Built by `seed/seed_bulk_patients.sql`, `seed/seed_bulk_medications.sql`, `seed/seed_bulk_activity.sql`.
Every row went through the real triggers (BR-01/03/05/08/09/11/12, audit), the whole bulk load takes about 5 seconds.
The first bulk patient is a deliberate "heavy user" with 308 appointments.

## Before / after an index

| Query | Index | Without index | With index | Speed-up |
|---|---|---|---|---|
| Q03 history of the heavy patient, newest first | `idx_appt_patient_date` | table scan of 19,726 rows + sort, 4.66 ms | index range, 308 rows, no sort, 0.30 ms | ~15x |
| Q01 shifts of one doctor on one day | `idx_shift_doctor_date` | table scan of 2,484 rows, 0.78 ms | index lookup, 1 row, 0.020 ms | ~39x |
| BR-09 overlap probe (runs in the trigger on every booking) | `idx_appt_shift_time` | table scan of 19,726 rows, 5.51 ms | index range on one shift, 0.013 ms | ~430x |
| NFR-04 audit trail of one record | `idx_mr_audit_record` | table scan of 5,938 rows + sort, 1.81 ms | index lookup, 2 rows, 0.021 ms | ~85x |

The BR-09 probe matters most: it executes inside the booking trigger, so without the index every INSERT into
`appointment` would cost a full scan and get slower as the clinic grows.

## Plans of the other access paths

| Query | Plan | Time |
|---|---|---|
| P1 doctor directory (50 rows) | full scan, correct for a table this small | 0.05 ms |
| P7 medication catalog (520 rows) | full scan, correct (no index on `is_active`: low selectivity) | 0.17 ms |
| P3 patient history with joins (Q03, 308 rows) | `idx_appt_patient_date` + primary-key lookups for shift / doctor / record | 1.4 ms |
| P8 most prescribed drugs (Q05) | one pass over 5,946 items grouped through a temporary table | 10 ms |
| P5 consultation access probe (BR-22) | single-row lookup (table has 5 rows, optimizer picks an FK index) | 0.02 ms |

## Indexing decisions

* Seven explicit indexes (`sql/02_indexes.sql`); none duplicates a PRIMARY KEY, UNIQUE or FK index.
* `idx_appt_patient_date` and `idx_appt_shift_time` also serve the FKs `fk_appt_patient` / `fk_appt_shift`
  (MySQL drops the implicit FK index when a usable one exists), so `appointment` has only 3 indexes in total.
* No index on `doctor.is_active` / `medication.is_active`: the tables are tiny and the predicate is not selective,
  the full scans above are the right plan.
