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
class ListConfig:
    home: Path
    output_format: OutputFormat
    runtime: str


@dataclass(frozen=True, slots=True)
class MutateConfig:
    home: Path
    output_format: OutputFormat
    runtime: str
    server: str
    apply: bool


@dataclass(frozen=True, slots=True)
class PruneConfig:
    home: Path
    output_format: OutputFormat
    runtime: str
    keep: tuple[str, ...]
    apply: bool


@dataclass(frozen=True, slots=True)
class ManagerError(Exception):
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
