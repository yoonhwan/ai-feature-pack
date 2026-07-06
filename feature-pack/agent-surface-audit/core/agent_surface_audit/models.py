from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import TypeAlias, override

JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
JsonObject: TypeAlias = dict[str, JsonValue]


class OutputFormat(StrEnum):
    HUMAN = "human"
    JSON = "json"


@dataclass(frozen=True, slots=True)
class AuditConfig:
    repo_root: Path
    home: Path
    dry_run: bool
    output_format: OutputFormat
    json_path: Path | None
    public_safety_only: bool = False


@dataclass(frozen=True, slots=True)
class SurfaceRoot:
    runtime: str
    path: Path
    surface_type: str


@dataclass(frozen=True, slots=True)
class AuditError(Exception):
    message: str

    @override
    def __str__(self) -> str:
        return self.message
