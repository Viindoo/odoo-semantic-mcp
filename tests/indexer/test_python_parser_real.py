"""Acceptance tests: parse real Odoo CE product models."""

from __future__ import annotations

import pathlib

import pytest

from osm.indexer.python_parser import parse_file


def _require_file(path: pathlib.Path) -> None:
    if not path.exists():
        pytest.skip(f"Odoo source not found: {path}")


def _product_product(root: pathlib.Path | None) -> pathlib.Path:
    if root is None:
        pytest.skip("ODOO_SOURCE_PATH not set")
    path = root / "addons/product/models/product_product.py"
    _require_file(path)
    return path


def _product_template(root: pathlib.Path | None) -> pathlib.Path:
    if root is None:
        pytest.skip("ODOO_SOURCE_PATH not set")
    path = root / "addons/product/models/product_template.py"
    _require_file(path)
    return path


class TestProductProduct:
    def test_at_least_one_model(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_product(odoo_source_path))
        assert len(result.models) >= 1

    def test_inherits_delegation(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_product(odoo_source_path))
        pp = next(
            (m for m in result.models if m.class_name == "ProductProduct"),
            None,
        )
        assert pp is not None, "ProductProduct class not found"
        assert pp.inherits.get("product.template") == "product_tmpl_id"

    def test_inherit_contains_mail_mixins(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_product(odoo_source_path))
        pp = next(m for m in result.models if m.class_name == "ProductProduct")
        assert "mail.thread" in pp.inherit
        assert "mail.activity.mixin" in pp.inherit

    def test_field_count_positive(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_product(odoo_source_path))
        pp_fields = [
            f for f in result.fields if f.model_class_name == "ProductProduct"
        ]
        assert len(pp_fields) > 0

    def test_no_crash(self, odoo_source_path: pathlib.Path | None) -> None:
        result = parse_file(_product_product(odoo_source_path))
        assert "error" not in result.notes


class TestProductTemplate:
    def test_at_least_one_model(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_template(odoo_source_path))
        assert len(result.models) >= 1

    def test_model_name(self, odoo_source_path: pathlib.Path | None) -> None:
        result = parse_file(_product_template(odoo_source_path))
        tmpl = next(
            (m for m in result.models if m.name == "product.template"),
            None,
        )
        assert tmpl is not None

    def test_field_count_positive(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        result = parse_file(_product_template(odoo_source_path))
        tmpl_fields = [
            f
            for f in result.fields
            if f.model_class_name == "ProductTemplate"
        ]
        assert len(tmpl_fields) > 0

    def test_no_crash(self, odoo_source_path: pathlib.Path | None) -> None:
        result = parse_file(_product_template(odoo_source_path))
        assert "error" not in result.notes


class TestBothModels:
    def test_two_models_combined(
        self, odoo_source_path: pathlib.Path | None
    ) -> None:
        r1 = parse_file(_product_product(odoo_source_path))
        r2 = parse_file(_product_template(odoo_source_path))
        total_models = r1.models + r2.models
        assert len(total_models) >= 2
