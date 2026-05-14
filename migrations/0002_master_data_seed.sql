-- migrations/0002_master_data_seed.sql
-- Master data: seed 26 standard profiles for Odoo CE v8-v19,
-- Standard Viindoo v8-v19, and Viindoo Internal v17/v18.
--
-- Profiles are inserted with INSERT ... ON CONFLICT (name) DO NOTHING,
-- so re-running this migration (or running it against a database that
-- already has these profiles via prior `seed-master-data` CLI runs) is a no-op.
-- Existing manually-created profiles with the same name are NOT overwritten.
--
-- The matching repos rows are seeded by src/db/seed_master_data.py::seed_repos()
-- because repos.local_path depends on Path.home() at runtime (per
-- src/git_utils.py::default_clone_dir) and cannot be hardcoded in pure SQL.
-- src/db/migrate.py invokes seed_repos() after yoyo applies this migration.

INSERT INTO profiles (name, odoo_version, description) VALUES
    ('odoo_8',  '8.0',  'Odoo CE 8.0 (Viindoo fork as canonical CE)'),
    ('odoo_9',  '9.0',  'Odoo CE 9.0 (Viindoo fork as canonical CE)'),
    ('odoo_10', '10.0', 'Odoo CE 10.0 (Viindoo fork as canonical CE)'),
    ('odoo_11', '11.0', 'Odoo CE 11.0 (Viindoo fork as canonical CE)'),
    ('odoo_12', '12.0', 'Odoo CE 12.0 (Viindoo fork as canonical CE)'),
    ('odoo_13', '13.0', 'Odoo CE 13.0 (Viindoo fork as canonical CE)'),
    ('odoo_14', '14.0', 'Odoo CE 14.0 (Viindoo fork as canonical CE)'),
    ('odoo_15', '15.0', 'Odoo CE 15.0 (Viindoo fork as canonical CE)'),
    ('odoo_16', '16.0', 'Odoo CE 16.0 (Viindoo fork as canonical CE)'),
    ('odoo_17', '17.0', 'Odoo CE 17.0 (Viindoo fork as canonical CE)'),
    ('odoo_18', '18.0', 'Odoo CE 18.0 (Viindoo fork as canonical CE)'),
    ('odoo_19', '19.0', 'Odoo CE 19.0 (Viindoo fork as canonical CE)'),
    ('standard_viindoo_8',  '8.0',  'Standard Viindoo 8.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_9',  '9.0',  'Standard Viindoo 9.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_10', '10.0', 'Standard Viindoo 10.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_11', '11.0', 'Standard Viindoo 11.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_12', '12.0', 'Standard Viindoo 12.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_13', '13.0', 'Standard Viindoo 13.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_14', '14.0', 'Standard Viindoo 14.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_15', '15.0', 'Standard Viindoo 15.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_16', '16.0', 'Standard Viindoo 16.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_17', '17.0', 'Standard Viindoo 17.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_18', '18.0', 'Standard Viindoo 18.0 (Odoo CE + Viindoo addons)'),
    ('standard_viindoo_19', '19.0', 'Standard Viindoo 19.0 (Odoo CE + Viindoo addons)'),
    ('viindoo_internal_17', '17.0', 'Viindoo Internal 17.0 (Standard Viindoo + internal repos)'),
    ('viindoo_internal_18', '18.0', 'Viindoo Internal 18.0 (Standard Viindoo + internal repos)')
ON CONFLICT (name) DO NOTHING;
