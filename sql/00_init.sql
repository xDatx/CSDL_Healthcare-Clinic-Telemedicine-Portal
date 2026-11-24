-- Author: Lý Thành Đạt
-- Module: Schema bootstrap
-- DBMS: MySQL 8.0.16+ (CHECK enforced)
-- Run in DBeaver: Execute SQL Script (Alt+X)

DROP DATABASE IF EXISTS healthcare;
CREATE DATABASE healthcare
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE healthcare;

-- @app_actor_id: set trước mỗi thao tác ghi, ví dụ:
--   SET @app_actor_id = 1;
-- Trigger audit sẽ đọc biến session này.
