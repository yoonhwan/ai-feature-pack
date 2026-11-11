"""ft2 효과 동사의 시험용 `run` 인자를 표면에서 뺀다 (r1633). ⓐ `--run 1` = 사용법 rc64 JSON 1줄 · 쓰기 0(예전
TypeError traceback rc1) · ⓑ --run 없이 부른 effect = 라이브러리 직접 호출과 같은 값 · ⓒ pi 도구 ft2_effect 에
run 칸 0(다른 동사 불변) · ⓓ 코어 `effect(run=callable)` 시험 경로 보존 · 변이 M1(VERBS·INTS 되돌림)=ⓐ 빨강 ·
M2(도구 run 칸 되돌림)=ⓒ 빨강 — 사본은 시험 폴더(코어 옆 1개) 안에서만 만든다."""
import importlib.util, json, os, shutil, subprocess, sys                              # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
CLI, CORE, ADAPTER = FT2 / "core" / "cli.py", FT2 / "core", FT2 / "adapters" / "pi" / "ft2-seat.ts"
TEAM, NOW, USAGE, OK, GEN = "harness", "2026-11-11T03:00:00", 64, 0, 2                # claim 이 gen 1→2
BASE = (("submit", "--command", "c1", "--body", "본문-1", "--work", "W1"),
        ("assign", "--work", "W1", "--holder", "h1", "--evidence", "v1,v2"), ("deliver", "--work", "W1"),
        ("claim", "--work", "W1", "--holder", "h1"), ("start", "--work", "W1", "--holder", "h1", "--gen", str(GEN)))
EFFECT = ("effect", "--work", "W1", "--holder", "h1", "--gen", str(GEN), "--effect", "e1")
WANT = {name: {"root", "team"} | set(keys.split()) for name, keys in (("ft2_claim", "work holder rotation confirm_by"),
        ("ft2_start", "work holder gen"), ("ft2_effect", "work holder gen effect"), ("ft2_result", "work holder gen word"))}
DRIVER = '''import fs from "node:fs"; const mod = await import(process.env.FT2_ADAPTER); const tools = new Map();
mod.default({ registerTool: (t) => tools.set(t.name, t), on: () => 0 });
process.stdout.write(JSON.stringify({ verbs: mod.VERBS, tools: [...tools.values()].map((t) => ({ name: t.name, parameters: t.parameters })) }));'''
NODE = shutil.which("node")
needs_node = pytest.mark.skipif(not NODE, reason="node 없음 — 도구 표면 대조 불가")

def core(name):
    spec = importlib.util.spec_from_file_location("ft2_test_effect_run_" + name, CORE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def cli(root, *args, script=CLI):                    # cli 1회 — stdout 은 JSON 1줄 계약
    return subprocess.run([sys.executable, str(script), *args, "--root", str(root), "--team", TEAM], cwd=FT2,
                          env=dict(os.environ, FT_NOW=NOW), capture_output=True, text=True, timeout=25)

def prepared(root):
    for args in BASE:
        assert cli(root, *args).returncode == OK, args
    return root

def files(root):                                     # 루트 파일 지문 — 쓰기 0 판정
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(Path(root).rglob("*")) if p.is_file()}

def schema(box, adapter=ADAPTER):                    # 도구 표면(등록 스키마·VERBS) 1벌
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], input="{}", capture_output=True, env={
        "PATH": os.environ["PATH"], "HOME": str(box), "FT2_ADAPTER": adapter.as_uri()}, text=True, timeout=60)
    assert proc.returncode == 0, proc.stderr[-800:]
    return json.loads(proc.stdout)

def test_a_run_arg_is_usage_64_json_line_without_write(tmp_path):
    root = prepared(tmp_path / "a")
    before, done = files(root), cli(root, *EFFECT, "--run", "1")
    out = json.loads(done.stdout)
    assert (done.returncode, done.stdout.count("\n"), "Traceback" in done.stderr) == (USAGE, 1, False), done.stderr[-300:]
    assert out["result"] == "사용법" and "run" in out["reason"] and files(root) == before, "쓰기 0"

def test_b_effect_without_run_matches_library(tmp_path):
    root, mirror = prepared(tmp_path / "b"), tmp_path / "b-lib"
    shutil.copytree(root, mirror)
    done = cli(root, *EFFECT)
    own = core("execution").Execution(str(mirror), TEAM, clock=lambda: NOW).effect("W1", "h1", GEN, "e1")
    assert done.returncode == OK and own.result == "접수 성공" and json.loads(done.stdout) == own._asdict()

@needs_node
def test_c_tool_surface_has_no_run_field(tmp_path):
    got = schema(tmp_path)
    assert got["verbs"]["ft2_effect"]["optional"] == [], got["verbs"]["ft2_effect"]
    assert {row["name"]: set(row["parameters"]["properties"]) for row in got["tools"]} == WANT

def test_d_core_effect_keeps_run_callable(tmp_path):
    seen, calls = [], []
    ex = core("execution").Execution(str(prepared(tmp_path / "d")), TEAM, clock=lambda: NOW, on_step=seen.append)
    grant = ex.effect("W1", "h1", GEN, "e1", run=lambda: calls.append("run"))
    assert (grant.result, calls, seen[-1]) == ("접수 성공", ["run"], "after_effect"), (grant, seen)

def test_e_mutants_break_a_and_c(tmp_path):
    """M1 = VERBS·INTS 되돌리기(ⓐ 빨강 · TypeError traceback rc1) · M2 = 도구 run 칸 되돌리기(ⓒ 빨강)."""
    source = CLI.read_text(encoding="utf-8")
    mutant = source.replace('"effect"), ()', '"effect"), ("run",)').replace('INTS = ("gen",)', 'INTS = ("gen", "run")')
    path = CORE / ("_cli_m1_mutant_%d.py" % os.getpid())     # 옆 코어 모듈을 그대로 쓰도록 코어 옆에 둔다
    path.write_text(mutant, encoding="utf-8")
    try:
        done = cli(prepared(tmp_path / "m1"), *EFFECT, "--run", "1", script=path)
    finally:
        path.unlink()
    assert '("run",)),' in mutant and done.returncode != USAGE and "not callable" in done.stderr, done.stderr[-300:]
    if not NODE:
        return
    seat = ADAPTER.read_text(encoding="utf-8")
    adir = tmp_path / "ft2-seat-m2.ts"
    adir.write_text(seat.replace('"effect"], optional: [] }', '"effect"], optional: ["run"] }').replace(
        "effect: STR } },", 'effect: STR, run: { type: "integer" } } },'), encoding="utf-8")
    got = schema(tmp_path, adir)
    props = {row["name"]: set(row["parameters"]["properties"]) for row in got["tools"]}
    assert seat != adir.read_text(encoding="utf-8") and props["ft2_effect"] != WANT["ft2_effect"], "M2 미검출"
    assert got["verbs"]["ft2_effect"]["optional"] == ["run"], got["verbs"]["ft2_effect"]
