# tests/test_web_ui_delete_profile_browser.py
"""Browser E2E tests for the delete-profile feature (M8 W1).

Uses Playwright headless Chromium via web_ui_server + clean_browser fixtures.
Auth is bypassed via WEBUI_AUTH_DISABLED=1 (set by _bypass_webui_auth_for_legacy_tests).

Skipped automatically when chromium is not installed (conftest.py hook).
"""
import pytest

pytestmark = [pytest.mark.browser, pytest.mark.postgres]


class TestDeleteProfileBrowser:
    def test_delete_button_present_after_profile_created(
        self, web_ui_server, clean_browser, page
    ):
        """After adding a profile, the 🗑 delete button must be visible."""
        page.goto(f"{web_ui_server}/repos")
        page.fill("input[name='name']", "to_delete_profile")
        page.fill("input[name='version']", "99.0")
        page.click("button:has-text('Add Profile')")
        page.wait_for_load_state("load")

        # The delete button (🗑) should be visible in the profile card
        assert page.locator("button[title='Delete profile']").is_visible()

    def test_delete_profile_removes_from_page(
        self, web_ui_server, clean_browser, page
    ):
        """Click 🗑 → accept confirm dialog → profile card disappears + flash shown."""
        page.goto(f"{web_ui_server}/repos")
        page.fill("input[name='name']", "victim_browser_99")
        page.fill("input[name='version']", "99.0")
        page.click("button:has-text('Add Profile')")
        page.wait_for_load_state("load")

        # Accept the JS confirm() dialog before the form submits
        page.on("dialog", lambda d: d.accept())
        page.click("button[title='Delete profile']")
        page.wait_for_load_state("load")

        # Profile card should be gone
        assert "victim_browser_99" not in page.content()

        # Flash message mentioning 'deleted' should be present
        assert "deleted" in page.content().lower()

    def test_delete_profile_with_repo_shows_flash(
        self, web_ui_server, clean_browser, page
    ):
        """Delete profile that has a repo → flash includes repo count."""
        page.goto(f"{web_ui_server}/repos")
        page.fill("input[name='name']", "prof_with_repo_99")
        page.fill("input[name='version']", "99.0")
        page.click("button:has-text('Add Profile')")
        page.wait_for_load_state("load")

        # Add a repo to the profile
        page.fill("input[name='branch']", "99.0")
        page.fill("input[name='local_path']", "/tmp/test_del_browser_repo")
        page.click("button:has-text('Add Repo')")
        page.wait_for_load_state("load")

        # Delete the profile
        page.on("dialog", lambda d: d.accept())
        page.click("button[title='Delete profile']")
        page.wait_for_load_state("load")

        # Profile should be gone, flash present
        assert "prof_with_repo_99" not in page.content()
        assert "deleted" in page.content().lower()
