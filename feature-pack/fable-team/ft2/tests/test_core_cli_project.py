"""ft2 읽기 동사 `project` · holder «가용» 칸 시험 (r1617).

투영을 읽는 입구가 라이브러리 직접 호출(`projection.project` subprocess)뿐이던 것을 CLI 동사 1개로
내리고(r1607 은 subprocess 로 우회했다), 투영에 holder 별 «가용» 칸을 세운다. 쓰기 동사 없이 사슬을
세우고 투영만 읽는다 — 상태를 바꾸는 호출은 전부 동사이고, 읽기는 `project` 1줄이다.

ⓐ `project` = stdout JSON 1줄(works·holders) · rc0 · 루트 파일 sha256 전부 불변(쓰기 0 · lock 0)
ⓑ 가용 칸 = 진행 중(owner 이고 완료 아님) 0 이면 참 · 1 이상이면 거짓 + 그 work 이름
ⓒ 완료 뒤 가용 = r1607 ⓐ 사슬(8줄) 뒤 h1 참 · 다음 일을 claim 한 직후 거짓
ⓓ 빈 루트 = 빈 works·holders · rc0 · runtime 폴더 생성 0
M1 완료로 반환된 holder 이름 유지 줄을 빼면 ⓒ 가 빨강
press 0 · 실 runtime 0 · 재진입 표지 = 없음(자기 파일을 부르지 않는다).
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(FT2, "core")
CLI = os.path.join(CORE, "cli.py")
TEAM, NOW = "harness", "2026-11-11T01:00:00"
OK, RECLAIMED = "접수 성공", "회수 결과"
EV = "v1,v2"
ENV = dict(os.environ, FT_NOW=NOW)


def _cli(root, *args):
    """CLI 1회 = 동사 1개. stdout 은 정확히 JSON 1줄, rc 는 계약값 그대로."""
    done = subprocess.run([sys.executable, CLI] + list(args) + ["--root", str(root), "--team", TEAM],
                          cwd=FT2, env=ENV, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    assert done.stdout.count("\n") == 1, done.stdout
    return json.loads(done.stdout), done.returncode


def _ok(root, *args):
    """rc0 만 쓰는 동사 호출 — 결과 dict 를 돌려준다(사슬이 계약값으로만 지나가게)."""
    out, rc = _cli(root, *args)
    assert (out["result"], rc) == (OK, 0), (args, out, rc)
    return out


def _project(root):
    """읽기 동사 1회 — 이 시험의 유일한 관측 입구다."""
    out, rc = _cli(root, "project")
    assert (out["result"], rc) == (OK, 0), (out, rc)
    return out


def _snapshot(root):
    """루트 아래 모든 파일의 sha256 — 쓰기 0 판정(ⓐ · runtime 폴더까지 본다)."""
    base = os.path.abspath(str(root))
    paths = [(os.path.relpath(os.path.join(where, name), base), os.path.join(where, name))
             for where, _dirs, names in os.walk(base) for name in names]
    return {rel: hashlib.sha256(open(path, "rb").read()).hexdigest() for rel, path in paths}


def _chain(root, work, holder="h1"):
    """r1607 ⓐ 사슬 — submit → assign → deliver → claim → start → effect → result → complete, 전부 동사."""
    _ok(root, "submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work)
    _ok(root, "assign", "--work", work, "--holder", holder, "--evidence", EV)
    _ok(root, "deliver", "--work", work)
    gen = str(_ok(root, "claim", "--work", work, "--holder", holder)["gen"])
    for step, extra in (("start", ()), ("effect", ("--effect", "e-" + work)), ("result", ())):
        _ok(root, step, "--work", work, "--holder", holder, "--gen", gen, *extra)
    _ok(root, "complete", "--work", work)


def test_a_project_verb_reads_and_writes_nothing(tmp_path):
    """ⓐ — 사슬을 세운 루트를 읽어도 파일 sha256 이 전부 같고, JSON 1줄에 works·holders 가 있다."""
    root = tmp_path / "a"
    _chain(root, "W1")
    before = _snapshot(root)
    out = _project(root)
    assert set(out) >= {"works", "holders"} and before
    assert _snapshot(root) == before                    # 바이트 불변 = 쓰기 0 · lock 파일도 안 건드린다
    assert _project(root) == out                        # 읽기는 몇 번 해도 같은 값(멱등)
    assert out["works"]["W1"]["done"] is True
    assert out["holders"] == {"h1": {"free": True, "works": []}}


def test_b_free_counts_in_progress_works(tmp_path):
    """ⓑ — owner 가 있고 완료가 아닌 일만 «진행 중» 이다. 1개면 거짓 + 이름, 완료되면 다시 참."""
    root = tmp_path / "b"
    _chain(root, "W1")
    assert _project(root)["holders"]["h1"] == {"free": True, "works": []}
    for work in ("W2", "W3"):
        _ok(root, "submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work)
        _ok(root, "assign", "--work", work, "--holder", "h2", "--evidence", EV)
    held = _project(root)["holders"]
    assert held["h2"] == {"free": False, "works": ["W2", "W3"]} and held["h1"]["free"] is True
    _ok(root, "deliver", "--work", "W2")
    gen = str(_ok(root, "claim", "--work", "W2", "--holder", "h2")["gen"])
    for step, extra in (("start", ()), ("effect", ("--effect", "e-W2")), ("result", ())):
        _ok(root, step, "--work", "W2", "--holder", "h2", "--gen", gen, *extra)
    _ok(root, "complete", "--work", "W2")
    assert _project(root)["holders"]["h2"] == {"free": False, "works": ["W3"]}


def test_c_free_after_chain_and_busy_after_claim(tmp_path):
    """ⓒ — r1607 ⓐ 사슬 뒤 h1 은 가용(참) · 다음 일 claim 직후 거짓 + 그 work 이름."""
    root = tmp_path / "c"
    _chain(root, "W1")
    assert _project(root)["holders"]["h1"] == {"free": True, "works": []}
    _ok(root, "submit", "--command", "c-W2", "--body", "본문-W2", "--work", "W2")
    _ok(root, "assign", "--work", "W2", "--holder", "h1", "--evidence", EV)
    _ok(root, "deliver", "--work", "W2")
    gen = _ok(root, "claim", "--work", "W2", "--holder", "h1")["gen"]
    assert _project(root)["holders"]["h1"] == {"free": False, "works": ["W2"]}
    assert _ok(root, "start", "--work", "W2", "--holder", "h1", "--gen", str(gen))["result"] == OK
    assert _project(root)["holders"]["h1"] == {"free": False, "works": ["W2"]}       # 착수 뒤에도 같다


def test_d_empty_root_keeps_projection_empty(tmp_path):
    """ⓓ — 없는 루트 = 빈 works·holders · rc0 · runtime 폴더를 만들지 않는다."""
    root = tmp_path / "absent"
    out = _project(root)
    assert (out["works"], out["holders"], out["pending"]) == ({}, {}, 0)
    assert not os.path.exists(os.path.join(str(root), ".fable-team"))                 # 폴더 생성 0


def test_m1_dropping_returned_holder_names_breaks_c(tmp_path):
    """M1(제품 1곳: records 의 holder 이름 유지 줄 → pass) — 완료 뒤 h1 이 «가용» 칸에서 사라져 ⓒ 빨강."""
    source = Path(CORE, "projection.py").read_text(encoding="utf-8")
    mutant = source.replace('        names.add(rec.get("holder"))', "        pass")
    assert mutant != source
    path = Path(CORE, "_projection_m1_mutant.py")
    try:
        path.write_text(mutant, encoding="utf-8")
        spec = importlib.util.spec_from_file_location("ft2_test_projection_m1", str(path))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        root = tmp_path / "m1"
        _chain(root, "W1")
        assert _project(root)["holders"]["h1"]["free"] is True                        # 정본 = ⓒ 통과
        assert (module.project(str(root), TEAM).get("holders") or {}).get("h1") is None   # 변이 = ⓒ 위반
    finally:
        path.unlink()


def test_legacy_guard_rc0():
    """새 파일도 1.x 경로·도구를 하나도 부르지 않는다(회귀 0 · 기존 검사기 그대로)."""
    done = subprocess.run([sys.executable, "-I", os.path.join(FT2, "tools", "legacy_guard.py")],
                          capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")
