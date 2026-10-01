"""airag CLI — init, manage doctor/verify (P-01) + add/update/delete/manage
status/list/show/restore + fetch original (P-02).

Envelope contract: schema_version, request_id, ok, command, data, error.
`error` is a structured object {code, message, retryable} — see airag/api.py,
the single shared entrypoint both this CLI and any direct Python caller go
through (p02-review1.txt item 6). JSON goes to stdout only; nothing else may
print to stdout ("JSON stdout 오염 없음"). Parser/argument errors also emit
this same JSON contract (not argparse's default usage-text-to-stderr) —
`--help`/`-h` is the one deliberate exception and stays plain text
(p02-cli-review.txt item 5).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import NoReturn

from airag import _fileio, api, keys, store
from airag.db import connect

ENVELOPE_SCHEMA_VERSION = 1


def _envelope(
    command: str,
    *,
    ok: bool,
    data: dict[str, object] | None = None,
    error: dict[str, object] | None = None,
    request_id: str | None = None,
) -> dict[str, object]:
    return api.envelope(command, ok=ok, data=data, error=error, request_id=request_id)


def _error(code: str, message: str, *, retryable: bool = False) -> dict[str, object]:
    return {"code": code, "message": message, "retryable": retryable}


def _emit(envelope: dict[str, object]) -> None:
    print(json.dumps(envelope, ensure_ascii=False))


def _resolve_key(args: argparse.Namespace) -> bytes | None:
    if args.key_fd is not None:
        return keys.read_key_from_fd(args.key_fd)
    if keys.keychain_available():
        return keys.read_key_from_keychain("airag", args.db)  # pragma: no cover (phase 1: never true)
    return None


def _no_key_error(command: str, request_id: str | None) -> dict[str, object]:
    return _envelope(
        command, ok=False, request_id=request_id,
        error=_error(
            "NO_KEY_SOURCE",
            "no key source configured (pass --key-fd; macOS Keychain provider not implemented in phase 1)",
        ),
    )


class _JsonArgumentParser(argparse.ArgumentParser):
    """Parser/unknown-argument errors emit the standard JSON envelope
    instead of argparse's default usage-text-to-stderr + exit(2)
    (p02-cli-review.txt item 5). `--help`/`-h` is unaffected: argparse's
    built-in help action exits directly, never calling `error()`."""

    def error(self, message: str) -> NoReturn:
        _emit(_envelope(self.prog, ok=False, error=_error("ARGUMENT_ERROR", message)))
        raise SystemExit(2)


# ------------------------------------------------------------------ P-01


def cmd_init(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("init", None)
    try:
        con = connect.init_db(args.db, key_bytes)
    except connect.DatabaseAlreadyExists as exc:
        return _envelope("init", ok=False, error=_error("DATABASE_ALREADY_EXISTS", str(exc)))
    try:
        version = connect.read_schema_version(con)
    finally:
        con.close()
    return _envelope("init", ok=True, data={"path": str(Path(args.db).resolve()), "schema_version": version})


def cmd_doctor(args: argparse.Namespace) -> dict[str, object]:
    if args.db is None:
        return api.doctor(request_id=args.request_id)
    return _database_diagnostic(args, "manage doctor", api.doctor)


def _database_diagnostic(args, command, fn):
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error(command, getattr(args, "request_id", None))
    try:
        con = connect.open_readonly(args.db, key_bytes)
    except Exception:
        return _envelope(command, ok=False, request_id=getattr(args, "request_id", None),
                         error=_error("KEY_OR_DB_VERIFICATION_FAILED", "database could not be opened for read-only diagnostics"))
    try:
        result = fn(con, request_id=getattr(args, "request_id", None))
        if command == "manage verify":
            result["data"]["path"] = str(Path(args.db).resolve())
            result["data"]["schema_version"] = connect.read_schema_version(con)
        return result
    finally:
        con.close()


def cmd_verify(args: argparse.Namespace) -> dict[str, object]:
    if args.db_option is not None:
        if args.db is not None:
            raise ValueError("pass the database either positionally or with --db")
        args.db = args.db_option
    if args.db is None:
        raise ValueError("database path is required")
    return _database_diagnostic(args, "manage verify", api.verify)


def cmd_backup(args: argparse.Namespace) -> dict[str, object]:
    command = _compound_command_name(args)
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error(command, args.request_id)
    destination_key = None
    if args.destination_key_fd is not None:
        if args.destination_key_fd == args.key_fd:
            raise ValueError("destination key must use a distinct file descriptor")
        destination_key = keys.read_key_from_fd(args.destination_key_fd)
    if command == "manage backup":
        return api.backup_database(args.db, args.output, key_bytes,
                                   destination_key_bytes=destination_key, request_id=args.request_id)
    return api.restore_backup(args.backup, args.db, key_bytes,
                              destination_key_bytes=destination_key, request_id=args.request_id)


# ------------------------------------------------------------------ P-02


def _resolve_single_item_content(args: argparse.Namespace) -> tuple[bytes, str, str | None]:
    """Returns (content, effective_media_type, effective_origin_uri).
    Reads --content-file exactly once via the bounded, regular-file-only
    helper — never an unbounded read, never a second read. Infers
    media_type/origin_uri from the file when not explicitly supplied,
    rather than defaulting an unknown/binary file to text/plain
    (p02-cli-review.txt item 4)."""
    content_file: str | None = args.content_file
    text: str | None = args.text
    if (content_file is None) == (text is None):
        raise store.ApiError(
            "VALIDATION_ERROR", "exactly one of --content-file or --text is required", retryable=False
        )
    if text is not None:
        media_type = args.media_type or "text/plain"
        return text.encode("utf-8"), media_type, args.origin_uri

    try:
        content = _fileio.read_bounded_regular_file(content_file, store.MAX_CONTENT_BYTES)
    except OSError as exc:
        raise store.ApiError(
            "IO_ERROR", f"could not read --content-file: {exc}", retryable=False
        ) from exc
    media_type = args.media_type or _fileio.guess_media_type(content_file)
    origin_uri = args.origin_uri or _fileio.default_origin_uri(content_file)
    return content, media_type, origin_uri


def _reject_conflicting_content_modes(args: argparse.Namespace) -> None:
    batch = getattr(args, "batch", None)
    content_file = getattr(args, "content_file", None)
    text = getattr(args, "text", None)
    if batch is not None and (content_file is not None or text is not None):
        raise store.ApiError(
            "VALIDATION_ERROR",
            "--batch cannot be combined with --content-file or --text",
            retryable=False,
        )


def cmd_add(args: argparse.Namespace) -> dict[str, object]:
    _reject_conflicting_content_modes(args)
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("add", getattr(args, "request_id", None))
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        if args.batch is not None:
            items = _read_batch_items(args.batch)
            return api.add_batch(con, items, request_id=args.request_id)
        content, media_type, origin_uri = _resolve_single_item_content(args)
        return api.add(con, args.request_id, args.collection, args.source_key, content, media_type=media_type, origin_uri=origin_uri, profile_key=args.profile_key)
    finally:
        con.close()


def cmd_update(args: argparse.Namespace) -> dict[str, object]:
    _reject_conflicting_content_modes(args)
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("update", getattr(args, "request_id", None))
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        if args.batch is not None:
            items = _read_batch_items(args.batch)
            return api.update_batch(con, items, request_id=args.request_id)
        content, media_type, origin_uri = _resolve_single_item_content(args)
        return api.update(
            con, args.request_id, args.collection, args.source_key, args.expected_revision, content,
            media_type=media_type, origin_uri=origin_uri, force_reprocess=args.force_reprocess, profile_key=args.profile_key,
        )
    finally:
        con.close()


def _read_batch_items(batch_path: str) -> object:
    """Whole-batch syntactic/schema validation is explicit and happens
    BEFORE any item is processed: a malformed --batch file (unreadable,
    invalid UTF-8, invalid/non-finite JSON, not an array) is refused
    outright rather than partially processing items then crashing
    (p02-cli-review.txt item 2)."""
    try:
        content = _fileio.read_bounded_regular_file(batch_path, store.MAX_CONTENT_BYTES)
    except OSError as exc:
        raise store.ApiError("IO_ERROR", f"could not read --batch: {exc}", retryable=False) from exc
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise store.ApiError("VALIDATION_ERROR", f"--batch is not valid UTF-8: {exc}", retryable=False) from exc
    try:
        items = store.strict_json_loads(text)
    except (json.JSONDecodeError, ValueError) as exc:
        raise store.ApiError("VALIDATION_ERROR", f"--batch is not valid JSON: {exc}", retryable=False) from exc
    if not isinstance(items, list):
        raise store.ApiError("VALIDATION_ERROR", "--batch JSON must be an array", retryable=False)
    return items


def cmd_delete(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("delete", args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        return api.delete(con, args.request_id, args.collection, args.source_key, args.expected_revision)
    finally:
        con.close()


def cmd_restore(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("manage restore", args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        return api.restore(con, args.request_id, args.collection, args.source_key, args.expected_revision)
    finally:
        con.close()


def cmd_status(args: argparse.Namespace) -> dict[str, object]:
    if args.collection is None and args.source_key is None:
        return _database_diagnostic(args, "manage status", api.operational_status)
    if args.collection is None or args.source_key is None:
        raise ValueError("--collection and --source-key must be supplied together")
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("manage status", args.request_id)
    con = connect.open_readonly(args.db, key_bytes)
    try:
        return api.status(con, args.collection, args.source_key, request_id=args.request_id)
    finally:
        con.close()


def cmd_list(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("manage list", args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        return api.list_(con, args.collection, include_deleted=args.include_deleted, request_id=args.request_id)
    finally:
        con.close()


def cmd_show(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("manage show", args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        return api.show(con, args.collection, args.source_key, revision_id=args.revision_id, request_id=args.request_id)
    finally:
        con.close()


def cmd_fetch_original(args: argparse.Namespace) -> dict[str, object]:
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error("fetch original", args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        return api.fetch_original(
            con, args.collection, args.source_key,
            revision_id=args.revision_id, include_bytes=args.include_bytes, request_id=args.request_id,
        )
    finally:
        con.close()


def cmd_processing(args: argparse.Namespace) -> dict[str, object]:
    command = _compound_command_name(args)
    key_bytes = _resolve_key(args)
    if key_bytes is None:
        return _no_key_error(command, args.request_id)
    con = connect.open_encrypted(args.db, key_bytes)
    try:
        if command == "manage profile":
            raw = _fileio.read_bounded_regular_file(args.config, store.MAX_CONTENT_BYTES)
            return api.register_profile(con, store.strict_json_loads(raw.decode("utf-8")), request_id=args.request_id)
        if command == "manage retry":
            return api.retry(con, args.request_id, args.job_id, profile_key=args.profile_key)
        if command == "manage reindex":
            return api.reindex(
                con, args.request_id, args.collection, args.source_key, args.expected_revision,
                profile_key=args.profile_key,
            )
        if command == "search":
            options=_expansion_options(args)
            if options and not args.expand:
                raise ValueError('expansion flags require --expand')
            return api.search(con, args.collection, args.query, args.profile_key, top_k=args.top_k, request_id=args.request_id,
                              source_keys=args.source_key,media_types=args.media_type,expansion_options=options if args.expand else None)
        if command == 'expand':
            return api.expand(con,args.manifest_id,options=_expansion_options(args),seed_chunk_ids=args.seed_chunk_id,request_id=args.request_id)
        if command == "fetch manifest":
            return api.fetch_manifest(con, args.manifest_id, request_id=args.request_id)
        if command == 'fetch expansion':
            return api.fetch_expansion(con,args.expansion_id,request_id=args.request_id)
        return api.fetch_artifact(
            con, args.collection, args.source_key, chunk_id=getattr(args, "chunk_id", None),
            generation_id=getattr(args, "generation_id", None), request_id=args.request_id,
        )
    finally:
        con.close()


def _expansion_options(args):
    keys=('max_depth','max_chunks','max_tokens','max_bytes','max_edges','include_semantic','semantic_neighbors','min_similarity')
    options={k:getattr(args,k) for k in keys if getattr(args,k,None) is not None}
    if getattr(args,'relation',None) is not None:options['relations']=args.relation
    return options


# --------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = _JsonArgumentParser(prog="ai-rag")
    sub = parser.add_subparsers(dest="command", required=True, parser_class=_JsonArgumentParser)

    p_init = sub.add_parser("init")
    p_init.add_argument("db")
    p_init.add_argument("--key-fd", type=int, default=None)
    p_init.set_defaults(func=cmd_init)

    p_manage = sub.add_parser("manage")
    manage_sub = p_manage.add_subparsers(dest="manage_command", required=True, parser_class=_JsonArgumentParser)

    p_doctor = manage_sub.add_parser("doctor")
    p_doctor.add_argument("--db", default=None)
    p_doctor.add_argument("--key-fd", type=int, default=None)
    p_doctor.add_argument("--request-id", default=None)
    p_doctor.set_defaults(func=cmd_doctor)

    p_verify = manage_sub.add_parser("verify")
    p_verify.add_argument("db", nargs="?", default=None)
    p_verify.add_argument("--db", dest="db_option", default=None)
    p_verify.add_argument("--key-fd", type=int, default=None)
    p_verify.add_argument("--request-id", default=None)
    p_verify.set_defaults(func=cmd_verify)

    def _add_db_key_args(p: argparse.ArgumentParser) -> None:
        p.add_argument("--db", required=True)
        p.add_argument("--key-fd", type=int, default=None)

    def _add_content_args(p: argparse.ArgumentParser) -> None:
        p.add_argument("--content-file", default=None)
        p.add_argument("--text", default=None)
        p.add_argument("--batch", default=None, help="path to a JSON array of items")
        p.add_argument("--media-type", default=None, help="default: inferred for --content-file, text/plain for --text")
        p.add_argument("--origin-uri", default=None, help="default: the file:// URI for --content-file, none for --text")

    for name, path_flag in (("backup", "--output"), ("restore-backup", "--backup")):
        p_snapshot = manage_sub.add_parser(name)
        _add_db_key_args(p_snapshot)
        p_snapshot.add_argument(path_flag, required=True)
        p_snapshot.add_argument("--destination-key-fd", type=int, default=None)
        p_snapshot.add_argument("--request-id", default=None)
        p_snapshot.set_defaults(func=cmd_backup)

    def _add_expansion_args(p):
        for name in ('depth','chunks','tokens','bytes','edges'):
            p.add_argument('--max-'+name,type=int,default=None)
        p.add_argument('--include-semantic',action='store_true',default=None)
        p.add_argument('--semantic-neighbors',type=int,default=None)
        p.add_argument('--min-similarity',type=float,default=None)
        p.add_argument('--relation',action='append',default=None)

    # request_id is REQUIRED for every mutation's single-item form — never
    # silently synthesized (p02-cli-review.txt item 5: an auto-generated id
    # would defeat consumer-supplied idempotency: a caller who omitted it
    # and genuinely retries would get a fresh id each time and never
    # dedupe). --batch items supply their own request_id per item instead,
    # so it is not required when --batch is given (enforced at the
    # argparse level via required=False + a runtime check).
    p_add = sub.add_parser("add")
    _add_db_key_args(p_add)
    p_add.add_argument("--request-id", default=None)
    p_add.add_argument("--collection", default=None)
    p_add.add_argument("--source-key", default=None)
    p_add.add_argument("--profile-key", default=None)
    _add_content_args(p_add)
    p_add.set_defaults(func=cmd_add)

    p_update = sub.add_parser("update")
    _add_db_key_args(p_update)
    p_update.add_argument("--request-id", default=None)
    p_update.add_argument("--collection", default=None)
    p_update.add_argument("--source-key", default=None)
    p_update.add_argument("--expected-revision", default=None)
    p_update.add_argument("--force-reprocess", action="store_true")
    p_update.add_argument("--profile-key", default=None)
    _add_content_args(p_update)
    p_update.set_defaults(func=cmd_update)

    p_delete = sub.add_parser("delete")
    _add_db_key_args(p_delete)
    p_delete.add_argument("--request-id", required=True)
    p_delete.add_argument("--collection", required=True)
    p_delete.add_argument("--source-key", required=True)
    p_delete.add_argument("--expected-revision", required=True)
    p_delete.set_defaults(func=cmd_delete)

    p_restore = manage_sub.add_parser("restore")
    _add_db_key_args(p_restore)
    p_restore.add_argument("--request-id", required=True)
    p_restore.add_argument("--collection", required=True)
    p_restore.add_argument("--source-key", required=True)
    p_restore.add_argument("--expected-revision", required=True)
    p_restore.set_defaults(func=cmd_restore)

    # Read endpoints: request_id is optional (correlation only, no
    # idempotency semantics) but preserved into the envelope when given.
    p_status = manage_sub.add_parser("status")
    _add_db_key_args(p_status)
    p_status.add_argument("--collection", default=None)
    p_status.add_argument("--source-key", default=None)
    p_status.add_argument("--request-id", default=None)
    p_status.set_defaults(func=cmd_status)

    p_list = manage_sub.add_parser("list")
    _add_db_key_args(p_list)
    p_list.add_argument("--collection", required=True)
    p_list.add_argument("--include-deleted", action="store_true")
    p_list.add_argument("--request-id", default=None)
    p_list.set_defaults(func=cmd_list)

    p_show = manage_sub.add_parser("show")
    _add_db_key_args(p_show)
    p_show.add_argument("--collection", required=True)
    p_show.add_argument("--source-key", required=True)
    p_show.add_argument("--revision-id", type=int, default=None)
    p_show.add_argument("--request-id", default=None)
    p_show.set_defaults(func=cmd_show)

    p_fetch = sub.add_parser("fetch")
    fetch_sub = p_fetch.add_subparsers(dest="fetch_command", required=True, parser_class=_JsonArgumentParser)
    p_fetch_original = fetch_sub.add_parser("original")
    _add_db_key_args(p_fetch_original)
    p_fetch_original.add_argument("--collection", required=True)
    p_fetch_original.add_argument("--source-key", required=True)
    p_fetch_original.add_argument("--revision-id", type=int, default=None)
    p_fetch_original.add_argument("--include-bytes", action="store_true")
    p_fetch_original.add_argument("--request-id", default=None)
    p_fetch_original.set_defaults(func=cmd_fetch_original)

    p_profile = manage_sub.add_parser("profile")
    _add_db_key_args(p_profile)
    p_profile.add_argument("--config", required=True, help="JSON object containing embedding, optional llm and normalizer configuration")
    p_profile.add_argument("--request-id", default=None)
    p_profile.set_defaults(func=cmd_processing)

    # P06-03: --job-id identifies the target job (see `manage status`'s
    # latest_job field to find one without touching SQL). --request-id is
    # REQUIRED (this command's own idempotency key, distinct from
    # whatever request_id created the job) — same rationale as add/update
    # (p02-cli-review.txt item 5): an auto-generated id would defeat
    # consumer-supplied idempotency.
    p_retry = manage_sub.add_parser("retry")
    _add_db_key_args(p_retry)
    p_retry.add_argument("--job-id", type=int, required=True)
    p_retry.add_argument("--request-id", required=True)
    p_retry.add_argument("--profile-key", default=None)
    p_retry.set_defaults(func=cmd_processing)

    # P06-04: reindex is identified by (collection, source_key,
    # expected_revision), not a job_id — it targets the source's current
    # head revision, not an existing job. --profile-key is REQUIRED (no
    # "originally captured" profile to fall back to, D-011) and may name a
    # different profile/space than what is currently ready (a migration).
    p_reindex = manage_sub.add_parser("reindex")
    _add_db_key_args(p_reindex)
    p_reindex.add_argument("--collection", required=True)
    p_reindex.add_argument("--source-key", required=True)
    p_reindex.add_argument("--expected-revision", required=True)
    p_reindex.add_argument("--profile-key", required=True)
    p_reindex.add_argument("--request-id", required=True)
    p_reindex.set_defaults(func=cmd_processing)

    p_search = sub.add_parser("search")
    _add_db_key_args(p_search)
    p_search.add_argument("--collection", required=True)
    p_search.add_argument("--query", required=True)
    p_search.add_argument("--profile-key", required=True)
    p_search.add_argument("--top-k", type=int, default=10)
    p_search.add_argument("--request-id", default=None)
    p_search.add_argument('--source-key',action='append',default=None)
    p_search.add_argument('--media-type',action='append',default=None)
    p_search.add_argument('--expand',action='store_true')
    _add_expansion_args(p_search)
    p_search.set_defaults(func=cmd_processing)

    p_expand=sub.add_parser('expand')
    _add_db_key_args(p_expand)
    p_expand.add_argument('--manifest-id',type=int,required=True)
    p_expand.add_argument('--seed-chunk-id',type=int,action='append',default=None)
    p_expand.add_argument('--request-id',default=None)
    _add_expansion_args(p_expand)
    p_expand.set_defaults(func=cmd_processing)

    for name, identifier in (("chunk", "chunk-id"), ("source", "generation-id"), ("manifest", "manifest-id"), ('expansion','expansion-id')):
        p_artifact = fetch_sub.add_parser(name)
        _add_db_key_args(p_artifact)
        p_artifact.add_argument("--" + identifier, type=int, required=True)
        p_artifact.add_argument("--request-id", default=None)
        if name not in ("manifest",'expansion'):
            p_artifact.add_argument("--collection", required=True)
            p_artifact.add_argument("--source-key", required=True)
        p_artifact.set_defaults(func=cmd_processing)

    return parser


def _compound_command_name(args: argparse.Namespace) -> str:
    parts = [getattr(args, "command", None), getattr(args, "manage_command", None), getattr(args, "fetch_command", None)]
    return " ".join(p for p in parts if p) or "unknown"


def _validate_request_id_required_for_mutation(args: argparse.Namespace) -> None:
    """add/update require --request-id unless --batch is used (each batch
    item carries its own); delete/manage restore already enforce it via
    argparse required=True."""
    if getattr(args, "batch", None) is not None and getattr(args, "profile_key", None) is not None:
        raise store.ApiError("VALIDATION_ERROR", "--batch items must carry their own profile_key", retryable=False)
    if getattr(args, "command", None) in ("add", "update") and getattr(args, "batch", None) is None:
        if not args.request_id:
            raise store.ApiError(
                "VALIDATION_ERROR",
                "--request-id is required (omit only when using --batch, where each item supplies its own)",
                retryable=False,
            )


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    command_name = _compound_command_name(args)
    request_id = getattr(args, "request_id", None)

    try:
        _validate_request_id_required_for_mutation(args)
        envelope = args.func(args)
    except Exception as exc:
        mapped = api.map_exception(exc)
        if mapped is None:
            raise
        envelope = _envelope(command_name, ok=False, error=mapped, request_id=request_id)
    _emit(envelope)
    return 0 if envelope["ok"] else 4


if __name__ == "__main__":
    sys.exit(main())
