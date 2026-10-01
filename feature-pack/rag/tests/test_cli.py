from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

AI_RAG = str(Path(sys.executable).with_name("ai-rag"))
KRB_RAG = str(Path(sys.executable).with_name("krb-rag"))


def _run_with_key(
    argv: list[str], key_bytes: bytes, *, cwd: Path
) -> tuple[dict[str, object], subprocess.CompletedProcess[str]]:
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
    envelope = json.loads(proc.stdout)
    return envelope, proc


def test_ai_rag_init_and_verify_roundtrip(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "cli.db"

    envelope, proc = _run_with_key([AI_RAG, "init", str(db_path)], key_bytes, cwd=tmp_path)
    assert proc.returncode == 0, proc.stderr
    assert envelope["ok"] is True
    assert envelope["command"] == "init"

    envelope2, proc2 = _run_with_key(
        [AI_RAG, "manage", "verify", str(db_path)], key_bytes, cwd=tmp_path
    )
    assert proc2.returncode == 0, proc2.stderr
    assert envelope2["ok"] is True
    assert envelope2["command"] == "manage verify"


def test_krb_rag_entrypoint_also_works(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "cli.db"
    envelope, proc = _run_with_key([KRB_RAG, "init", str(db_path)], key_bytes, cwd=tmp_path)
    assert proc.returncode == 0, proc.stderr
    assert envelope["ok"] is True


def test_cli_runs_from_outside_repo_with_no_pythonpath(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "cli.db"
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    r, w = os.pipe()
    os.set_inheritable(r, True)
    _ = os.write(w, key_bytes)
    os.close(w)
    try:
        proc = subprocess.run(
            [AI_RAG, "init", str(db_path), "--key-fd", str(r)],
            cwd="/tmp",
            env=env,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        os.close(r)
    assert proc.returncode == 0, proc.stderr
    envelope = json.loads(proc.stdout)
    assert envelope["ok"] is True


def test_cli_wrong_key_rejected_on_verify(tmp_path: Path, key_bytes: bytes) -> None:
    db_path = tmp_path / "cli.db"
    _, proc = _run_with_key([AI_RAG, "init", str(db_path)], key_bytes, cwd=tmp_path)
    assert proc.returncode == 0, proc.stderr

    wrong_key = bytes((b + 1) % 256 for b in key_bytes)
    envelope2, proc2 = _run_with_key(
        [AI_RAG, "manage", "verify", str(db_path)], wrong_key, cwd=tmp_path
    )
    assert proc2.returncode == 4
    assert envelope2["ok"] is False
    assert envelope2["error"] is not None


def test_cli_no_key_source_errors_without_key_leakage(tmp_path: Path) -> None:
    db_path = tmp_path / "cli.db"
    proc = subprocess.run(
        [AI_RAG, "init", str(db_path)],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 4
    envelope = json.loads(proc.stdout)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "NO_KEY_SOURCE"
    assert "key-fd" in envelope["error"]["message"]


def test_cli_doctor_no_key_needed(tmp_path: Path) -> None:
    proc = subprocess.run(
        [AI_RAG, "manage", "doctor"],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, proc.stderr
    envelope = json.loads(proc.stdout)
    assert envelope["ok"] is True
    assert envelope["data"]["sqlcipher"]["available"] is True
    assert envelope["data"]["fts5"]["available"] is True
    assert envelope["data"]["vec0"]["available"] is True


def test_cli_never_puts_key_material_in_argv_or_output(
    tmp_path: Path, key_bytes: bytes
) -> None:
    db_path = tmp_path / "cli.db"
    r, w = os.pipe()
    os.set_inheritable(r, True)
    _ = os.write(w, key_bytes)
    os.close(w)
    argv = [AI_RAG, "init", str(db_path), "--key-fd", str(r)]
    try:
        proc = subprocess.run(
            argv,
            cwd=tmp_path,
            pass_fds=(r,),
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        os.close(r)
    key_hex = key_bytes.hex()
    assert key_hex not in " ".join(argv)
    assert key_hex not in proc.stdout
    assert key_hex not in proc.stderr
    assert key_bytes not in proc.stdout.encode()
    assert key_bytes not in proc.stderr.encode()
