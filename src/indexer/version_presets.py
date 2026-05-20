# SPDX-License-Identifier: AGPL-3.0-or-later
"""Version presets — bundled profile + repo definitions for one-shot setup.

No presets bundled by default; admins configure profiles and repos via the
web UI (/admin) or the JSON API. Populate PRESETS here if you want to ship
pre-built presets with your deployment.
"""

PRESETS: dict[str, dict] = {}


def list_presets() -> list[str]:
    """Return preset names sorted alphabetically."""
    return sorted(PRESETS.keys())


def load_preset(name: str) -> dict:
    """Return preset dict (deep-copy to prevent mutation)."""
    import copy
    if name not in PRESETS:
        raise KeyError(f"unknown preset: {name!r}; available: {list_presets()}")
    return copy.deepcopy(PRESETS[name])
