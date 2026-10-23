"""The pkg_resources shim that lets resemble-perth import on setuptools >= 81."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path

import pytest

from sufler_tts import compat


def test_resource_filename_points_inside_the_package() -> None:
    path = Path(compat.resource_filename("sufler_tts", "voices.py"))
    assert path.is_file()


def test_shim_installs_only_when_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delitem(sys.modules, "pkg_resources", raising=False)
    monkeypatch.setattr(importlib.util, "find_spec", lambda _name: None)
    assert compat.install_pkg_resources_shim()
    shim = importlib.import_module("pkg_resources")
    assert shim.resource_filename is compat.resource_filename
    assert not compat.install_pkg_resources_shim()  # already there
    del sys.modules["pkg_resources"]  # leave no shim behind for other tests
