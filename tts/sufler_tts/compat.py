"""Compatibility shims for transitive dependencies.

resemble-perth 1.0.1 (newest; Chatterbox's watermarker) does
`from pkg_resources import resource_filename`, and setuptools >= 81 no longer
ships `pkg_resources`. Without it `perth.PerthImplicitWatermarker` is None and
Chatterbox fails to construct. Rather than pin an old setuptools (breaks the
newest-stable rule) or drop the watermark, provide the one function perth uses.
"""

from __future__ import annotations

import importlib.util
import sys
import types
from importlib.resources import files


def resource_filename(package: str, resource: str) -> str:
    """`pkg_resources.resource_filename` for regular (on-disk) packages."""
    return str(files(package).joinpath(resource))


def install_pkg_resources_shim() -> bool:
    """Register a minimal `pkg_resources` if the real one is missing."""
    if "pkg_resources" in sys.modules or importlib.util.find_spec("pkg_resources"):
        return False
    shim = types.ModuleType("pkg_resources")
    shim.resource_filename = resource_filename  # type: ignore[attr-defined]
    sys.modules["pkg_resources"] = shim
    return True
