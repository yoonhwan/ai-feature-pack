"""JSON console interface for the explicit AIRAG consumer runtime."""

from __future__ import annotations

import argparse
from dataclasses import replace
from datetime import datetime, timezone
import json
import os
import re
import sys
import time
from typing import TYPE_CHECKING, Callable, Mapping, NoReturn, Sequence, TextIO

if TYPE_CHECKING:
    from .runtime import RuntimeHooks


class _ArgumentError(ValueError):
    pass


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise _ArgumentError("INVALID_ARGUMENTS")


def _parser() -> argparse.ArgumentParser:
    parser = _Parser(prog="airag-consumer")
    parser.add_argument("--config", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")

    run = commands.add_parser("run")
    run.add_argument("--once", action="store_true")
    run.add_argument("--task-completed", action="store_true")
    run.add_argument("--save", action="store_true")
    run.add_argument("--allow-gaps", action="store_true")

    commands.add_parser("status")
    search = commands.add_parser("search")
    search.add_argument("query")
    search.add_argument("--limit", type=int, default=5)

    archive = commands.add_parser("archive-search")
    archive.add_argument("query")
    archive.add_argument("--limit", type=int, default=20)

    confirm = commands.add_parser("memory-confirm")
    confirm.add_argument("candidate_id")

    candidates = commands.add_parser("memory-candidates")
    candidates.add_argument("--state", required=True)
    candidates.add_argument("--limit", type=int, default=10)
    candidates.add_argument("--skip", type=int, default=0)
    reject = commands.add_parser("memory-reject")
    reject.add_argument("candidate_id")
    solution = commands.add_parser("memory-verify")
    solution.add_argument("candidate_id")

    commands.add_parser("backup")
    verify = commands.add_parser("verify")
    verify.add_argument("backup_id")
    return parser


def _emit(value: object, stream: TextIO) -> None:
    stream.write(json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False,
    ) + "\n")


def main(
    argv: Sequence[str] | None = None, *, environ: Mapping[str, str] | None = None,
    clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    tokenizer: Callable[[str], int] | None = None,
    hooks: RuntimeHooks | None = None,
    stdout: TextIO | None = None, stderr: TextIO | None = None,
) -> int:
    """Run one command and return a process exit code; secrets are env-only."""
    output: TextIO = sys.stdout if stdout is None else stdout
    error_output: TextIO = sys.stderr if stderr is None else stderr
    try:
        args = _parser().parse_args(list(argv) if argv is not None else None)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 1
    except _ArgumentError as exc:
        _emit({
            "ok": False,
            "error": {"code": str(exc), "type": type(exc).__name__},
        }, error_output)
        return 2
    try:
        from .runtime import AIRAGRuntime, RuntimeConfig

        config = RuntimeConfig.load(args.config)
        if getattr(args, "allow_gaps", False):
            config = replace(config, allow_gaps=True)
        runtime = AIRAGRuntime(
            config, environ=os.environ if environ is None else environ,
            clock=clock, tokenizer=tokenizer, hooks=hooks,
        )
        if args.command == "init":
            data = runtime.init()
        elif args.command == "run":
            if args.once:
                data = runtime.run_once(
                    task_completed=args.task_completed, explicit_save=args.save,
                )
            else:
                iterations = 0
                try:
                    while True:
                        runtime.run_once(
                            task_completed=args.task_completed, explicit_save=args.save,
                        )
                        iterations += 1
                        time.sleep(config.poll_seconds)
                except KeyboardInterrupt:
                    data = {"stopped": True, "iterations": iterations}
        elif args.command == "status":
            data = runtime.status()
        elif args.command == "search":
            data = runtime.search(args.query, limit=args.limit)
        elif args.command == "archive-search":
            data = runtime.archive_search(args.query, limit=args.limit)
        elif args.command == "memory-confirm":
            data = runtime.memory_confirm(args.candidate_id)
        elif args.command == "memory-candidates":
            data = runtime.memory_candidates(args.state, limit=args.limit, skip=args.skip)
        elif args.command == "memory-reject":
            data = runtime.memory_reject(args.candidate_id)
        elif args.command == "memory-verify":
            data = runtime.memory_verify(args.candidate_id)
        elif args.command == "backup":
            data = runtime.backup(force=True)
        elif args.command == "verify":
            data = runtime.verify_backup(args.backup_id)
        else:
            raise _ArgumentError("INVALID_ARGUMENTS")
        _emit({"ok": True, "action": args.command, "data": data}, output)
        return 0
    except KeyboardInterrupt:
        _emit({"ok": False, "error": {"code": "INTERRUPTED"}}, error_output)
        return 130
    except Exception as exc:
        code = str(exc)
        if re.fullmatch(r"[A-Z0-9_:.~-]{1,160}", code or "") is None:
            code = "INTERNAL_ERROR"
        _emit({
            "ok": False,
            "error": {"code": code, "type": type(exc).__name__},
        }, error_output)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
