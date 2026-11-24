-- Author: Nguyễn Hoàng Dũng
-- Module: Teardown - removes everything this project created.
-- Dropping the database removes tables, triggers, views, procedures and functions in one step
-- (in the right order, which a table-by-table DROP cannot do because of the append-only triggers).
-- Run as root.

DROP DATABASE IF EXISTS healthcare;

DROP USER IF EXISTS 'app_patient'@'%';
DROP USER IF EXISTS 'app_doctor'@'%';
DROP USER IF EXISTS 'app_admin'@'%';
DROP ROLE IF EXISTS 'r_patient', 'r_doctor', 'r_admin';
