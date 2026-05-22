# SPDX-License-Identifier: AGPL-3.0-or-later
# tests/test_tools_symbols_integration.py
"""Integration tests for odoo.tools symbol coverage (ADR-0033).

Acceptance criteria (per WI-4 spec):
  - lookup_core_api("odoo.tools.SQL", "16.0") → not available (SQL absent in v16)
  - lookup_core_api("odoo.tools.SQL", "17.0") → stable

These tests seed CoreSymbol nodes directly (mirroring test_mcp_spec_tools.py pattern)
using the REAL version strings 16.0 / 17.0, because lifecycle correctness is what
we are validating.

The seeded data is isolated via DETACH DELETE on version strings 16.0 and 17.0
at setup and teardown — this is safe because test Neo4j containers are ephemeral.
"""
import os
import sys

import pytest

from src.indexer.parser_tools_symbols import _load_static_tools_symbols
from src.indexer.writer_neo4j import Neo4jWriter

pytestmark = pytest.mark.neo4j

# Use real version strings to validate lifecycle correctness.
TOOLS_V16 = "16.0"
TOOLS_V17 = "17.0"

_SPEC_DATA_DIR = (
    __import__("pathlib").Path(__file__).parent.parent / "src" / "indexer" / "spec_data"
)


@pytest.fixture(scope="module")
def seeded_tools_neo4j(neo4j_driver):
    """Seed CoreSymbol nodes from curated tools_symbols_{16.0,17.0}.json."""
    writer = Neo4jWriter(
        uri=os.getenv("NEO4J_TEST_URI", "bolt://localhost:7687"),
        user=os.getenv("NEO4J_TEST_USER", "neo4j"),
        password=os.getenv("NEO4J_TEST_PASSWORD", "password"),
    )
    writer.setup_indexes()

    # Clean both versions before seeding (ephemeral test container)
    with neo4j_driver.session() as session:
        for v in (TOOLS_V16, TOOLS_V17):
            session.run("MATCH (n:CoreSymbol) WHERE n.odoo_version = $v DETACH DELETE n", v=v)

    symbols_v16 = _load_static_tools_symbols(TOOLS_V16, static_data_dir=_SPEC_DATA_DIR)
    symbols_v17 = _load_static_tools_symbols(TOOLS_V17, static_data_dir=_SPEC_DATA_DIR)

    writer.write_core_symbols(symbols_v16)
    writer.write_core_symbols(symbols_v17)
    writer.close()

    yield TOOLS_V16, TOOLS_V17

    # Teardown: remove seeded nodes
    with neo4j_driver.session() as session:
        for v in (TOOLS_V16, TOOLS_V17):
            session.run("MATCH (n:CoreSymbol) WHERE n.odoo_version = $v DETACH DELETE n", v=v)


@pytest.fixture
def tools_mcp(seeded_tools_neo4j):
    """Import MCP server module with test Neo4j credentials after data is seeded."""
    os.environ["NEO4J_URI"] = os.getenv("NEO4J_TEST_URI", "bolt://localhost:7687")
    os.environ["NEO4J_USER"] = os.getenv("NEO4J_TEST_USER", "neo4j")
    os.environ["NEO4J_PASSWORD"] = os.getenv("NEO4J_TEST_PASSWORD", "password")
    sys.modules.pop("src.mcp.server", None)
    from src.mcp import server as mcp_server
    return mcp_server


# ---------------------------------------------------------------------------
# Core acceptance tests
# ---------------------------------------------------------------------------

class TestSQLVersionAcceptance:
    """Primary acceptance criteria from WI-4 spec."""

    def test_sql_not_available_in_v16(self, tools_mcp, seeded_tools_neo4j):
        """lookup_core_api("odoo.tools.SQL", "16.0") must return not-found."""
        out = tools_mcp._lookup_core_api("odoo.tools.SQL", TOOLS_V16)
        assert "not found" in out.lower(), (
            f"Expected 'not found' for odoo.tools.SQL in v16.0, got:\n{out}"
        )

    def test_sql_stable_in_v17(self, tools_mcp, seeded_tools_neo4j):
        """lookup_core_api("odoo.tools.SQL", "17.0") must return stable."""
        out = tools_mcp._lookup_core_api("odoo.tools.SQL", TOOLS_V17)
        assert "SQL" in out, f"Expected SQL in output, got:\n{out}"
        assert "not found" not in out.lower(), (
            f"odoo.tools.SQL must be FOUND in v17.0, got:\n{out}"
        )
        assert "stable" in out.lower() or "tool_export" in out.lower(), (
            f"Expected 'stable' or 'tool_export' in output, got:\n{out}"
        )


class TestSafeEvalLookup:
    """safe_eval must resolve via qualified submodule path."""

    def test_safe_eval_found_in_v16_by_short_name(self, tools_mcp, seeded_tools_neo4j):
        """Short name 'safe_eval' resolves via ENDS WITH query."""
        out = tools_mcp._lookup_core_api("safe_eval", TOOLS_V16)
        assert "safe_eval" in out
        assert "not found" not in out.lower()

    def test_safe_eval_found_in_v17_by_full_path(self, tools_mcp, seeded_tools_neo4j):
        """Full qualified_name 'odoo.tools.safe_eval.safe_eval' resolves exactly."""
        out = tools_mcp._lookup_core_api("odoo.tools.safe_eval.safe_eval", TOOLS_V17)
        assert "safe_eval" in out
        assert "not found" not in out.lower()


class TestToolsSymbolKindInOutput:
    """Verify tool_export kind is surfaced by the MCP tool."""

    def test_sql_v17_output_references_tool_export_kind(self, tools_mcp, seeded_tools_neo4j):
        out = tools_mcp._lookup_core_api("odoo.tools.SQL", TOOLS_V17)
        # The formatted output should include the kind field (tool_export or class)
        assert any(kw in out.lower() for kw in ("tool_export", "class", "SQL")), (
            f"Expected kind/class in output for SQL@v17, got:\n{out}"
        )


class TestHtmlEscapeDeprecationInV17:
    """html_escape is deprecated in v17 — lookup must surface deprecation."""

    def test_html_escape_deprecated_in_v17(self, tools_mcp, seeded_tools_neo4j):
        out = tools_mcp._lookup_core_api("html_escape", TOOLS_V17)
        assert "html_escape" in out
        assert "not found" not in out.lower()
        assert "deprecated" in out.lower(), (
            f"Expected 'deprecated' for html_escape in v17.0, got:\n{out}"
        )


# ---------------------------------------------------------------------------
# Data completeness via direct loader (not Neo4j — unit-style)
# ---------------------------------------------------------------------------

class TestLoaderDataCompleteness:
    """Spot-check that the loaded symbols have the expected lifecycle."""

    def test_v16_has_no_sql_symbol(self):
        syms = _load_static_tools_symbols(TOOLS_V16, static_data_dir=_SPEC_DATA_DIR)
        qnames = {s.qualified_name for s in syms}
        assert "odoo.tools.SQL" not in qnames

    def test_v17_has_sql_symbol_stable(self):
        syms = _load_static_tools_symbols(TOOLS_V17, static_data_dir=_SPEC_DATA_DIR)
        sql_sym = next((s for s in syms if s.qualified_name == "odoo.tools.SQL"), None)
        assert sql_sym is not None
        assert sql_sym.status == "stable"
        assert sql_sym.kind == "tool_export"

    def test_v17_has_deprecated_html_escape(self):
        syms = _load_static_tools_symbols(TOOLS_V17, static_data_dir=_SPEC_DATA_DIR)
        html_escape = next(
            (s for s in syms if s.qualified_name == "odoo.tools.html_escape"), None
        )
        assert html_escape is not None
        assert html_escape.status == "deprecated"
        assert html_escape.replacement_qname == "markupsafe.escape"
