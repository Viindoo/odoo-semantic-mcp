# tests/test_master_data_seed.py
"""Tests for master data seeding (profiles + repos).

Uses the session-scoped pg_conn + per-test clean_pg fixture to wipe schema
tables (including yoyo state) before/after each test. run_migrations() then
re-creates schema + applies migration 0002 (which seeds profiles). seed_repos()
fills the repos table with default_clone_dir-derived local paths.
"""

import pytest

from src.db.migrate import run_migrations
from src.db.seed_master_data import (
    _PROFILE_DEFS,
    _REPO_DEFS_BY_PROFILE,
    reset_seeded_data,
    seed_all,
    seed_profiles,
    seed_repos,
)


def _count_seeded_profiles(conn) -> int:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM profiles "
            r"WHERE name LIKE 'odoo\_%' ESCAPE '\' "
            r"   OR name LIKE 'standard\_viindoo\_%' ESCAPE '\' "
            r"   OR name LIKE 'viindoo\_internal\_%' ESCAPE '\'"
        )
        return cur.fetchone()[0]


def _count_repos_for_profile(conn, profile_name: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM repos r "
            "JOIN profiles p ON p.id = r.profile_id "
            "WHERE p.name = %s",
            (profile_name,),
        )
        return cur.fetchone()[0]


def test_migrate_seeds_26_profiles(clean_pg):
    """run_migrations() applies 0002_master_data_seed.sql → 26 profiles inserted."""
    run_migrations(clean_pg)
    assert _count_seeded_profiles(clean_pg) == 26
    # Sanity: _PROFILE_DEFS matches what we expect
    assert len(_PROFILE_DEFS) == 26


def test_seed_repos_inserts_68_total(clean_pg):
    """seed_repos() inserts the expected 68 repos across all 26 profiles."""
    run_migrations(clean_pg)  # profiles already seeded via migration 0002
    inserted, skipped = seed_repos(clean_pg)
    assert inserted == 68
    assert skipped == 0
    # Sanity against the data definition
    assert sum(len(v) for v in _REPO_DEFS_BY_PROFILE.values()) == 68


def test_seed_all_idempotent(clean_pg):
    """Calling seed_all() twice does not duplicate rows."""
    run_migrations(clean_pg)
    first = seed_all(clean_pg)
    second = seed_all(clean_pg)
    # First call: profiles are already there (seeded by migration 0002).
    # seed_profiles INSERT ON CONFLICT DO NOTHING → all 26 skipped.
    assert first["profiles_inserted"] == 0
    assert first["profiles_skipped"] == 26
    assert first["repos_inserted"] == 68
    assert first["repos_skipped"] == 0
    # Second call: all rows already present → everything skipped
    assert second["profiles_inserted"] == 0
    assert second["profiles_skipped"] == 26
    assert second["repos_inserted"] == 0
    assert second["repos_skipped"] == 68
    # No duplicates: row counts unchanged
    assert _count_seeded_profiles(clean_pg) == 26
    with clean_pg.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM repos")
        assert cur.fetchone()[0] == 68


def test_seeded_profile_repo_counts_match_matrix(clean_pg):
    """Each profile tier has the right repo count per the design matrix."""
    run_migrations(clean_pg)
    seed_repos(clean_pg)
    # Odoo CE: 1 repo per version
    for v in range(8, 20):
        assert _count_repos_for_profile(clean_pg, f"odoo_{v}") == 1, f"odoo_{v}"
    # Standard Viindoo:
    #   v8-v9   → 2 (odoo + tvtmaaddons)
    #   v10-v12 → 3 (+erponline-enterprise)
    #   v13-v19 → 4 (+branding)
    for v in (8, 9):
        assert _count_repos_for_profile(clean_pg, f"standard_viindoo_{v}") == 2
    for v in (10, 11, 12):
        assert _count_repos_for_profile(clean_pg, f"standard_viindoo_{v}") == 3
    for v in (13, 14, 15, 16, 17, 18, 19):
        assert _count_repos_for_profile(clean_pg, f"standard_viindoo_{v}") == 4
    # Viindoo Internal: v17=8, v18=7 (no themes)
    assert _count_repos_for_profile(clean_pg, "viindoo_internal_17") == 8
    assert _count_repos_for_profile(clean_pg, "viindoo_internal_18") == 7


def test_viindoo_internal_18_excludes_themes(clean_pg):
    """themes max branch is 17.0 → viindoo_internal_18 must not include themes."""
    run_migrations(clean_pg)
    seed_repos(clean_pg)
    with clean_pg.cursor() as cur:
        cur.execute(
            "SELECT r.url FROM repos r "
            "JOIN profiles p ON p.id = r.profile_id "
            "WHERE p.name = %s",
            ("viindoo_internal_18",),
        )
        urls = [row[0] for row in cur.fetchall()]
    assert all("themes" not in url for url in urls), urls
    # v17 should include themes (positive control)
    with clean_pg.cursor() as cur:
        cur.execute(
            "SELECT r.url FROM repos r "
            "JOIN profiles p ON p.id = r.profile_id "
            "WHERE p.name = %s",
            ("viindoo_internal_17",),
        )
        urls17 = [row[0] for row in cur.fetchall()]
    assert any("themes" in url for url in urls17), urls17


def test_seeded_repos_clone_status_manual(clean_pg):
    """All seeded repos must have clone_status='manual'."""
    run_migrations(clean_pg)
    seed_repos(clean_pg)
    with clean_pg.cursor() as cur:
        cur.execute(
            "SELECT DISTINCT clone_status FROM repos r "
            "JOIN profiles p ON p.id = r.profile_id "
            r"WHERE p.name LIKE 'odoo\_%' ESCAPE '\' "
            r"   OR p.name LIKE 'standard\_viindoo\_%' ESCAPE '\' "
            r"   OR p.name LIKE 'viindoo\_internal\_%' ESCAPE '\'"
        )
        statuses = {row[0] for row in cur.fetchall()}
    assert statuses == {"manual"}


def test_admin_data_wins_on_name_conflict(clean_pg):
    """Manual profile created before seed is NOT overwritten — admin data wins."""
    run_migrations(clean_pg)
    # Drop the auto-seeded odoo_17 and replace with a manual profile of the same name
    # but different description.
    with clean_pg.cursor() as cur:
        cur.execute("DELETE FROM profiles WHERE name = %s", ("odoo_17",))
        cur.execute(
            "INSERT INTO profiles (name, odoo_version, description) VALUES (%s, %s, %s)",
            ("odoo_17", "17.0", "MANUAL — do not overwrite"),
        )
    # Re-seed
    seed_profiles(clean_pg)
    with clean_pg.cursor() as cur:
        cur.execute("SELECT description FROM profiles WHERE name = %s", ("odoo_17",))
        assert cur.fetchone()[0] == "MANUAL — do not overwrite"


def test_reset_seeded_data_deletes_only_seeded_profiles(clean_pg):
    """reset_seeded_data deletes prefix-matching profiles + cascades repos.

    Profiles not matching the seed prefixes (e.g. legacy 'viindoo17' without
    underscore from the apply-preset CLI) MUST be preserved.
    """
    run_migrations(clean_pg)
    seed_repos(clean_pg)
    # Manually create a non-seed profile to verify it survives reset
    with clean_pg.cursor() as cur:
        cur.execute(
            "INSERT INTO profiles (name, odoo_version, description) VALUES (%s, %s, %s)",
            ("viindoo17", "17.0", "Legacy preset profile"),
        )
    assert _count_seeded_profiles(clean_pg) == 26
    deleted = reset_seeded_data(clean_pg)
    assert deleted == 26
    assert _count_seeded_profiles(clean_pg) == 0
    # All seeded repos cascaded away
    with clean_pg.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM repos")
        assert cur.fetchone()[0] == 0
    # Legacy non-seed profile survives
    with clean_pg.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM profiles WHERE name = %s", ("viindoo17",)
        )
        assert cur.fetchone()[0] == 1


@pytest.mark.parametrize(
    "profile_name,expected_url_substring",
    [
        ("odoo_17",              "Viindoo/odoo.git"),
        ("standard_viindoo_13",  "Viindoo/branding.git"),
        ("viindoo_internal_17",  "Viindoo/saas-infrastructure.git"),
    ],
)
def test_seed_repos_uses_viindoo_ssh_url(clean_pg, profile_name, expected_url_substring):
    """All seeded repos must use git@github.com:Viindoo/* SSH URLs."""
    run_migrations(clean_pg)
    seed_repos(clean_pg)
    with clean_pg.cursor() as cur:
        cur.execute(
            "SELECT r.url FROM repos r JOIN profiles p ON p.id = r.profile_id "
            "WHERE p.name = %s",
            (profile_name,),
        )
        urls = [row[0] for row in cur.fetchall()]
    assert all(url.startswith("git@github.com:Viindoo/") for url in urls), urls
    assert any(expected_url_substring in url for url in urls), (
        f"{profile_name} missing {expected_url_substring} in {urls}"
    )
