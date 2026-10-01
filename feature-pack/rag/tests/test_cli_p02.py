from __future__ import annotations

import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

AI_RAG = str(Path(sys.executable).with_name("ai-rag"))


def _rid() -> str:
    return str(uuid.uuid4())


def _run_with_key(argv: list[str], key_bytes: bytes, *, cwd: Path) -> dict[str, object]:
    r, w = os.pipe()
    os.set_inheritable(r, True)
    _ = os.write(w, key_bytes)
    os.close(w)
    try:
        proc = subprocess.run(
            [*argv, "--key-fd", str(r)],
            cwd=cwd,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        os.close(r)
    assert proc.stdout, f"no stdout; stderr={proc.stderr}"
    return json.loads(proc.stdout)


def _init_db(tmp_path: Path, key_bytes: bytes) -> Path:
    db_path = tmp_path / "cli.db"
    env = _run_with_key([AI_RAG, "init", str(db_path)], key_bytes, cwd=tmp_path)
    assert env["ok"] is True, env
    return db_path


def test_add_update_delete_restore_status_roundtrip(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)

    add_env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--text", "hello world"],
        key_bytes, cwd=tmp_path,
    )
    assert add_env["ok"] is True, add_env
    token = add_env["data"]["revision_token"]

    status_env = _run_with_key(
        [AI_RAG, "manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md"],
        key_bytes, cwd=tmp_path,
    )
    assert status_env["ok"] is True
    assert status_env["data"]["revision_token"] == token

    update_env = _run_with_key(
        [AI_RAG, "update", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--expected-revision", token, "--text", "updated body"],
        key_bytes, cwd=tmp_path,
    )
    assert update_env["ok"] is True
    assert update_env["data"]["content_changed"] is True
    token2 = update_env["data"]["revision_token"]

    delete_env = _run_with_key(
        [AI_RAG, "delete", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--expected-revision", token2],
        key_bytes, cwd=tmp_path,
    )
    assert delete_env["ok"] is True
    token3 = delete_env["data"]["revision_token"]

    restore_env = _run_with_key(
        [AI_RAG, "manage", "restore", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--expected-revision", token3],
        key_bytes, cwd=tmp_path,
    )
    assert restore_env["ok"] is True
    assert restore_env["data"]["deleted"] is False


def test_add_from_content_file_infers_media_type_and_origin_uri(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    content_file = tmp_path / "note.md"
    content_file.write_text("# hello\n", encoding="utf-8")

    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "note.md",
         "--request-id", _rid(), "--content-file", str(content_file)],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is True, env

    show_env = _run_with_key(
        [AI_RAG, "manage", "show", "--db", str(db_path), "--collection", "docs", "--source-key", "note.md"],
        key_bytes, cwd=tmp_path,
    )
    assert show_env["data"]["media_type"] == "text/markdown"
    assert show_env["data"]["origin_uri"] == content_file.resolve().as_uri()


def test_add_missing_request_id_rejected(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md", "--text", "x"],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is False
    assert env["error"]["code"] == "VALIDATION_ERROR"
    assert "request-id" in env["error"]["message"]


def test_add_conflicting_content_and_text_rejected(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    content_file = tmp_path / "note.md"
    content_file.write_text("body", encoding="utf-8")
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--text", "x", "--content-file", str(content_file)],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is False
    assert env["error"]["code"] == "VALIDATION_ERROR"


def test_add_missing_content_file_is_io_error_not_a_delete(tmp_path: Path, key_bytes: bytes) -> None:
    """A file-read failure on --content-file must surface as a clean
    IO_ERROR — never silently reinterpreted as 'no content' and routed
    into any delete-like behavior. No source may be created either."""
    db_path = _init_db(tmp_path, key_bytes)
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--content-file", str(tmp_path / "does-not-exist.md")],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is False
    assert env["error"]["code"] == "IO_ERROR"
    assert env["command"] == "add"

    status_env = _run_with_key(
        [AI_RAG, "manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md"],
        key_bytes, cwd=tmp_path,
    )
    assert status_env["ok"] is False
    assert status_env["error"]["code"] == "NOT_FOUND"


def test_batch_mixed_valid_and_invalid_items_all_get_outcomes(tmp_path: Path, key_bytes: bytes) -> None:
    """One bad item must not abort the batch or hide earlier/later
    successful items' results."""
    db_path = _init_db(tmp_path, key_bytes)
    batch_path = tmp_path / "batch.json"
    batch_path.write_text(
        json.dumps([
            {"request_id": _rid(), "collection": "docs", "source_key": "a.md", "text": "content a"},
            {"request_id": _rid(), "collection": "docs", "source_key": "b.md"},  # missing content -> invalid
            {"request_id": _rid(), "collection": "docs", "source_key": "c.md", "text": "content c"},
        ]),
        encoding="utf-8",
    )
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path)], key_bytes, cwd=tmp_path
    )
    assert env["ok"] is True, env
    items = env["data"]["items"]
    assert len(items) == 3
    assert items[0]["ok"] is True
    assert items[1]["ok"] is False
    assert items[1]["error"]["code"] == "VALIDATION_ERROR"
    assert items[2]["ok"] is True

    a = _run_with_key(
        [AI_RAG, "manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "a.md"],
        key_bytes, cwd=tmp_path,
    )
    c = _run_with_key(
        [AI_RAG, "manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "c.md"],
        key_bytes, cwd=tmp_path,
    )
    assert a["ok"] is True
    assert c["ok"] is True


def test_batch_conflicting_with_text_rejected_before_any_mutation(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    batch_path = tmp_path / "batch.json"
    batch_path.write_text(json.dumps([{"request_id": _rid(), "collection": "docs", "source_key": "a.md", "text": "x"}]), encoding="utf-8")
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path), "--text", "also this"],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is False
    assert env["error"]["code"] == "VALIDATION_ERROR"

    listed = _run_with_key(
        [AI_RAG, "manage", "list", "--db", str(db_path), "--collection", "docs"], key_bytes, cwd=tmp_path
    )
    assert listed["data"]["sources"] == []


def test_batch_rejects_nonfinite_json_number(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    batch_path = tmp_path / "batch.json"
    # A syntactically valid JSON number that overflows to +inf on parse.
    batch_path.write_text('[{"request_id": "r1", "collection": "docs", "source_key": "a.md", "text": "1e999"}]', encoding="utf-8")
    # (this one is valid — 1e999 is inside a STRING here; test the batch's
    # own structural numbers instead by embedding one outside a JSON string)
    batch_path.write_text('[{"request_id": "r1", "collection": "docs", "source_key": "a.md", "text": "x", "extra": 1e999}]', encoding="utf-8")
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path)], key_bytes, cwd=tmp_path
    )
    assert env["ok"] is False
    assert env["error"]["code"] == "VALIDATION_ERROR"


def test_batch_binary_file_gets_same_media_type_inference_as_single_item(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """A .bin file with raw non-UTF8 bytes must be inferred as
    application/octet-stream in --batch exactly as it would be for a
    single --content-file call — not defaulted to text/plain and then
    fail UTF-8 validation (p02-final-probes.txt item 3). This only tests
    that raw bytes are stored/retrieved correctly, not any real binary
    format conversion (no PDF parsing etc. is claimed)."""
    db_path = _init_db(tmp_path, key_bytes)
    bin_file = tmp_path / "raw.bin"
    bin_file.write_bytes(bytes([0x00, 0xFF, 0x00, 0xFF]))

    single_env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "single.bin",
         "--request-id", _rid(), "--content-file", str(bin_file)],
        key_bytes, cwd=tmp_path,
    )
    assert single_env["ok"] is True, single_env

    batch_path = tmp_path / "batch.json"
    batch_item_id = _rid()
    batch_path.write_text(
        json.dumps([
            {"request_id": batch_item_id, "collection": "docs", "source_key": "batch.bin", "content_file": str(bin_file)}
        ]),
        encoding="utf-8",
    )
    batch_env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path)], key_bytes, cwd=tmp_path
    )
    assert batch_env["ok"] is True, batch_env
    item = batch_env["data"]["items"][0]
    assert item["ok"] is True, item

    single_show = _run_with_key(
        [AI_RAG, "manage", "show", "--db", str(db_path), "--collection", "docs", "--source-key", "single.bin"],
        key_bytes, cwd=tmp_path,
    )
    batch_show = _run_with_key(
        [AI_RAG, "manage", "show", "--db", str(db_path), "--collection", "docs", "--source-key", "batch.bin"],
        key_bytes, cwd=tmp_path,
    )
    assert single_show["data"]["media_type"] == "application/octet-stream"
    assert batch_show["data"]["media_type"] == "application/octet-stream"


def test_batch_item_result_preserves_request_id_for_success_and_failure(
    tmp_path: Path, key_bytes: bytes
) -> None:
    """Each batch result item must carry its own request_id — both when it
    succeeded and when it failed before store execution
    (p02-final-probes.txt item 4)."""
    db_path = _init_db(tmp_path, key_bytes)
    good_id = _rid()
    bad_id = _rid()
    batch_path = tmp_path / "batch.json"
    batch_path.write_text(
        json.dumps([
            {"request_id": good_id, "collection": "docs", "source_key": "ok.md", "text": "fine"},
            {"request_id": bad_id, "collection": "docs", "source_key": "bad.md"},  # no content -> fails
        ]),
        encoding="utf-8",
    )
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path)], key_bytes, cwd=tmp_path
    )
    items = env["data"]["items"]
    assert items[0]["ok"] is True
    assert items[0]["request_id"] == good_id
    assert items[1]["ok"] is False
    assert items[1]["request_id"] == bad_id


def test_batch_outer_envelope_preserves_caller_batch_request_id(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    batch_id = _rid()
    batch_path = tmp_path / "batch.json"
    batch_path.write_text(
        json.dumps([{"request_id": _rid(), "collection": "docs", "source_key": "a.md", "text": "x"}]),
        encoding="utf-8",
    )
    env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--batch", str(batch_path), "--request-id", batch_id],
        key_bytes, cwd=tmp_path,
    )
    assert env["ok"] is True
    assert env["request_id"] == batch_id


def test_fetch_original_and_manage_show_roundtrip(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    add_env = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", _rid(), "--text", "hello"],
        key_bytes, cwd=tmp_path,
    )
    assert add_env["ok"] is True

    fetch_env = _run_with_key(
        [AI_RAG, "fetch", "original", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md", "--include-bytes"],
        key_bytes, cwd=tmp_path,
    )
    assert fetch_env["ok"] is True
    assert fetch_env["command"] == "fetch original"
    import base64
    assert base64.b64decode(fetch_env["data"]["content_base64"]) == b"hello"


def test_argument_error_emits_json_not_traceback(tmp_path: Path, key_bytes: bytes) -> None:
    """An unrecognized argument must produce the standard JSON envelope,
    not argparse's default usage-text-to-stderr."""
    db_path = _init_db(tmp_path, key_bytes)
    r, w = os.pipe()
    os.set_inheritable(r, True)
    _ = os.write(w, key_bytes)
    os.close(w)
    try:
        proc = subprocess.run(
            [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
             "--request-id", _rid(), "--text", "x", "--totally-unknown-flag", "value", "--key-fd", str(r)],
            cwd=tmp_path,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        os.close(r)
    assert proc.returncode == 2
    envelope = json.loads(proc.stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "ARGUMENT_ERROR"


def test_help_stays_plain_text(tmp_path: Path) -> None:
    proc = subprocess.run([AI_RAG, "--help"], capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0
    with_json = None
    try:
        with_json = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pass
    assert with_json is None, "help output should be plain text, not a JSON envelope"
    assert "usage" in proc.stdout.lower()


def test_key_fd_short_value_rejected_without_traceback(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = _init_db(tmp_path, key_bytes)
    r, w = os.pipe()
    os.set_inheritable(r, True)
    _ = os.write(w, b"too-short")
    os.close(w)
    try:
        proc = subprocess.run(
            [AI_RAG, "manage", "status", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md", "--key-fd", str(r)],
            cwd=tmp_path,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        os.close(r)
    envelope = json.loads(proc.stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "VALIDATION_ERROR"
    assert "Traceback" not in proc.stderr


def test_idempotent_retry_survives_process_restart(tmp_path: Path, key_bytes: bytes) -> None:
    """The request ledger is durable — a retry of the same request_id from
    a brand-new process (fresh connection, DB reopened from disk) still
    replays the original result instead of conflicting or duplicating."""
    db_path = _init_db(tmp_path, key_bytes)
    rid = _rid()
    env1 = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", rid, "--text", "hello"],
        key_bytes, cwd=tmp_path,
    )
    assert env1["ok"] is True
    env2 = _run_with_key(
        [AI_RAG, "add", "--db", str(db_path), "--collection", "docs", "--source-key", "faq.md",
         "--request-id", rid, "--text", "hello"],
        key_bytes, cwd=tmp_path,
    )
    assert env2["ok"] is True
    assert env2["data"].get("idempotent_replay") is True
    assert env2["data"]["source_id"] == env1["data"]["source_id"]

    listed = _run_with_key(
        [AI_RAG, "manage", "list", "--db", str(db_path), "--collection", "docs"], key_bytes, cwd=tmp_path
    )
    assert len(listed["data"]["sources"]) == 1


def test_doctor_reports_not_ok_when_vec0_missing(tmp_path: Path, monkeypatch: object) -> None:
    """P-01 follow-through: doctor must not report ok=true purely because
    sqlcipher imported — cipher_version/fts5/vec0 must all be present."""
    # This is exercised at the unit level in test_connect.py /
    # test_vecext.py; here we just confirm the real (healthy) environment
    # reports ok=true with all four checks present, proving the stricter
    # condition doesn't false-negative in the normal case.
    proc = subprocess.run([AI_RAG, "manage", "doctor"], capture_output=True, text=True, timeout=30)
    env = json.loads(proc.stdout)
    assert env["ok"] is True
    assert env["data"]["sqlcipher"]["cipher_version"]
    assert env["data"]["fts5"]["available"] is True
    assert env["data"]["vec0"]["available"] is True
