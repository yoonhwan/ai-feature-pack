from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import TypeAlias, TypeGuard, override

JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
JsonObject: TypeAlias = dict[str, JsonValue]


class OutputFormat(StrEnum):
    HUMAN = "human"
    JSON = "json"


@dataclass(frozen=True, slots=True)
class SyncConfig:
    repo_root: Path
    home: Path
    apply: bool
    output_format: OutputFormat
    json_path: Path | None
    packages: tuple[str, ...] | None
    runtime: str
    operation_id: str


@dataclass(frozen=True, slots=True)
class PlannedAction:
    package: str
    runtime: str
    kind: str
    source: Path
    target: Path
    state: str
    backup_path: Path | None
    notes: tuple[str, ...] = ()
    rendered_content: str | None = None

    @property
    def changed(self) -> bool:
        return self.state != "up-to-date"


@dataclass(frozen=True, slots=True)
class SyncError(Exception):
    message: str

    @override
    def __str__(self) -> str:
        return self.message


def is_json_object(value: JsonValue) -> TypeGuard[JsonObject]:
    return isinstance(value, dict)


def json_objects(entries: list[JsonObject]) -> list[JsonValue]:
    values: list[JsonValue] = []
    values.extend(entries)
    return values


def string_values(values: list[str]) -> list[JsonValue]:
    strings: list[JsonValue] = []
    strings.extend(values)
    return strings
