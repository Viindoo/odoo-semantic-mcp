-- migrations/m10_001_drop_audit_legacy_columns.sql
-- M10 Polish: drop legacy W-UM columns from admin_audit_log.
--
-- Context (ADR-0021 §Legacy Column Deprecation):
--   Two M9 worktrees produced conflicting schemas for admin_audit_log:
--     - W-UM (9001_m9_user_mgmt.sql)           → actor_id INTEGER, target_id INTEGER, detail_text TEXT
--     - W-AC (m9_003_admin_audit_log.sql)       → actor TEXT, action TEXT, target TEXT, success BOOLEAN, detail JSONB
--   The W-AC schema is canonical. The W-UM legacy columns were retained for
--   backward compatibility while call sites were migrated to write_audit_log()
--   (src/db/audit.py). All call sites now use the canonical columns exclusively.
--   This migration removes the three legacy columns.
--
-- Idempotency: DROP COLUMN IF EXISTS is safe to run multiple times.
-- Schema-only: no data is seeded or transformed here.

ALTER TABLE admin_audit_log DROP COLUMN IF EXISTS actor_id;
ALTER TABLE admin_audit_log DROP COLUMN IF EXISTS target_id;
ALTER TABLE admin_audit_log DROP COLUMN IF EXISTS detail_text;
