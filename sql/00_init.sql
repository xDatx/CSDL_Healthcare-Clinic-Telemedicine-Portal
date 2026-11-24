-- Author: Lý Thành Đạt
-- Module: Schema bootstrap
-- DBMS: MySQL 8.0.18+ (CHECK constraints enforced from 8.0.16, EXPLAIN ANALYZE from 8.0.18)
-- WARNING: drops and recreates the database `healthcare`.
-- Run in DBeaver: Execute SQL Script (Alt+X)

DROP DATABASE IF EXISTS healthcare;
CREATE DATABASE healthcare
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE healthcare;

-- Audit context. The application sets these session variables before a write:
--   SET @app_actor_type = 'DOCTOR';   -- PATIENT | DOCTOR | ADMIN  (medical-record audit)
--   SET @app_actor_id   = 1;          -- id of that actor / of the admin changing the medication catalog
-- Triggers read them; the audit triggers reject a change when no valid actor is available.
