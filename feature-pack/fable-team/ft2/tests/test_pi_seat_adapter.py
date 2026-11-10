"""ft2 pi 좌석 어댑터 시험 (r1610 · 조건 14 «Pi 실행» 첫 칸).

사례 ⓐ~ⓕ = 카드 수용 기준 그대로다. node 로 확장 모듈을 불러 «가짜 pi API»(registerTool·on 기록)에 걸고,
도구 실행은 FT2_CLI 래퍼(python)가 argv 1줄을 적은 뒤 실제 `core/cli.py` 를 돌린다 — 그래서 «cli 를 몇 번
불렀나» 가 관측된다. 실 좌석·실 pi 세션·press 0 · 시험 입력 = tmp_path 격리 루트뿐(격리 Redis 픽스처도 안 쓴다).
ⓑ 의 «그대로» 는 같은 준비를 한 두 루트(도구 쪽 / 직접 cli 쪽)에 FT_NOW 고정으로 돌려 JSON 줄을 1:1 대조한다.
ⓓ 의 «결과 있음 1행» = 투영에 그 작업 1행 + journal 의 result 기록 1건이다(코어 result 는 owner 를 반환한다).
"""
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
ADAPTER = FT2 / "adapters" / "pi" / "ft2-seat.ts"
CLI = FT2 / "core" / "cli.py"
GUARD = FT2 / "tools" / "legacy_guard.py"
NODE = shutil.which("node")
TEAM, HOLDER, WORK, NOW = "harness", "pi-seat#0", "W1", "2026-11-11T02:00:00"
TOOLS = ("ft2_claim", "ft2_start", "ft2_effect", "ft2_result")
GEN = 2          # assign 이 gen 1 을 잡고 claim 이 gen 2 로 올린다
RESULT_WORD = "회수 결과"
DRIVER = """
import fs from "node:fs";
const mod = await import(process.env.FT2_ADAPTER), req = JSON.parse(fs.readFileSync(0, "utf8"));
const tools = new Map(), hooks = [];
mod.default({ registerTool: (t) => tools.set(t.name, t), on: (name) => hooks.push(name) });
if (req.op === "register") process.stdout.write(JSON.stringify({ hooks, timeout: mod.TIMEOUT_MS,
  tools: [...tools.values()].map((t) => ({ name: t.name, label: t.label, description: t.description, parameters: t.parameters, hasExecute: typeof t.execute === "function" })) }));
else { const out = [];
  for (const c of req.cases) { const r = await tools.get(c.tool).execute("call", c.params, undefined, undefined, { cwd: req.cwd });
    out.push({ tool: c.tool, text: r.content[0].text, isError: r.isError === true, details: r.details }); }
  process.stdout.write(JSON.stringify(out)); }
"""
WRAPPER = '''
import json, os, runpy, sys
with open(os.environ["FT2_CALL_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(sys.argv[1:], ensure_ascii=False) + "\\n")
sys.argv = ["cli.py"] + sys.argv[1:]
runpy.run_path(os.environ["FT2_REAL_CLI"], run_name="__main__")
'''


def core(name):
    """코어 모듈 1개(투영·journal 판독용) — ft2 다른 시험과 같은 방식(경로 적재)."""
    spec = importlib.util.spec_from_file_location("ft2_test_seat_" + name, FT2 / "core" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def cli(root, *args, timeout=20):
    """실제 코어 cli 1회 — FT_NOW 고정이라 같은 입력이면 같은 JSON 이 나온다."""
    return subprocess.run([sys.executable, str(CLI), *args, "--root", str(root), "--team", TEAM],
                          capture_output=True, text=True, timeout=timeout, env=dict(os.environ, FT_NOW=NOW))


def prepare(root, steps):
    for args in steps:
        proc = cli(root, *args)
        assert proc.returncode == 0, (args, proc.stdout, proc.stderr[-400:])


BASE = (["submit", "--command", "do it", "--body", "본문", "--work", WORK],
        ["assign", "--work", WORK, "--holder", HOLDER, "--evidence", "v1,v2"],
        ["deliver", "--work", WORK])
CLAIMED = BASE + (["claim", "--work", WORK, "--holder", HOLDER],)
STARTED = CLAIMED + (["start", "--work", WORK, "--holder", HOLDER, "--gen", str(GEN)],)
EFFECTED = STARTED + (["effect", "--work", WORK, "--holder", HOLDER, "--gen", str(GEN), "--effect", "e1"],)
STEPS = {"ft2_claim": BASE, "ft2_start": CLAIMED, "ft2_effect": STARTED, "ft2_result": EFFECTED}
ARGV = {"ft2_claim": ("claim", "--work", WORK, "--holder", HOLDER),
        "ft2_start": ("start", "--work", WORK, "--holder", HOLDER, "--gen", str(GEN)),
        "ft2_effect": ("effect", "--work", WORK, "--holder", HOLDER, "--gen", str(GEN), "--effect", "e1"),
        "ft2_result": ("result", "--work", WORK, "--holder", HOLDER, "--gen", str(GEN), "--word", RESULT_WORD)}


def params(tool, root):
    """도구 인자 — 루트·팀은 시험 루트로 고정한다."""
    return {"ft2_claim": {"work": WORK, "holder": HOLDER},
            "ft2_start": {"work": WORK, "holder": HOLDER, "gen": GEN},
            "ft2_effect": {"work": WORK, "holder": HOLDER, "gen": GEN, "effect": "e1"},
            "ft2_result": {"work": WORK, "holder": HOLDER, "gen": GEN, "word": RESULT_WORD}}[tool] | {"root": str(root), "team": TEAM}


def seat(tmp_path, adapter=None):
    """래퍼(호출 기록) + node 실행 환경 1벌."""
    wrapper, log = tmp_path / "cli-wrapper.py", tmp_path / "calls.log"
    wrapper.write_text(WRAPPER, encoding="utf-8")
    return {"call_log": log, "wrapper": wrapper,
            "env": {"FT2_ADAPTER": (adapter or ADAPTER).resolve().as_uri(), "FT2_CLI": str(wrapper),
                    "FT2_REAL_CLI": str(CLI), "FT2_CALL_LOG": str(log)}}


def calls(env):
    path = Path(env["FT2_CALL_LOG"])
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def node_run(tmp_path, env, payload, timeout=60):
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], input=json.dumps(payload), capture_output=True,
                          text=True, timeout=timeout, env={"PATH": os.environ["PATH"], "HOME": str(tmp_path), **env})
    assert proc.returncode == 0, proc.stderr[-800:]
    return json.loads(proc.stdout)


def run_tools(tmp_path, env, root, tools, extra=None):
    cases = [{"tool": name, "params": (extra or {}).get(name, params(name, root))} for name in tools]
    return node_run(tmp_path, env, {"op": "run", "cwd": str(root), "cases": cases})


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(Path(root).rglob("*")) if p.is_file()}


@pytest.fixture(autouse=True)
def budget():
    started = time.monotonic()
    yield
    assert time.monotonic() - started < 70, "시험 1개 = 70초 안(하드 룰 22)"


def test_a_registers_four_tools_and_nothing_else(tmp_path):
    env = seat(tmp_path)
    got = node_run(tmp_path, env["env"], {"op": "register"})
    assert [t["name"] for t in got["tools"]] == list(TOOLS) and all(t["hasExecute"] for t in got["tools"]), got
    assert got["hooks"] == [] and got["timeout"] == 7000, "pi.on 훅 0 · 외부 호출 상한 7초(하드 룰 12)"
    source = ADAPTER.read_text(encoding="utf-8")
    assert not [p for p in ("setInterval", "setTimeout", "pi.on(", "spawn(", "fork(", "execSync") if p in source], "상주·폴링·이벤트 훅 0"
    assert not calls(env["env"]), "등록만으로는 cli 를 부르지 않는다"
    assert all(t["parameters"]["required"] for t in got["tools"]), "도구마다 필수 인자가 스키마에 있다"


def test_b_same_verb_result_is_cli_stdout_and_one_call(tmp_path):
    tool_root, cli_root = tmp_path / "by-tool", tmp_path / "by-cli"
    prepare(tool_root, BASE)
    prepare(cli_root, BASE)
    env = seat(tmp_path)
    for name in TOOLS:                       # 같은 준비를 한 두 루트에서 한 걸음씩 나란히 — JSON 이 1:1 같아야 한다
        row = run_tools(tmp_path, env["env"], tool_root, (name,))[0]
        direct = cli(cli_root, *ARGV[name])
        assert direct.returncode == 0 and row["text"] == direct.stdout.strip(), (name, row, direct.stdout)
        assert row["isError"] is False and row["details"]["verb"] == ARGV[name][0], row
    argv_seen = calls(env["env"])
    assert [a[0] for a in argv_seen] == [ARGV[n][0] for n in TOOLS], "도구 1개 = 같은 이름 동사 1번"
    assert len(argv_seen) == 4, "도구 4개 = cli 4회(그 밖의 호출 0)"
    bad = {"ft2_start": {"work": WORK, "holder": HOLDER, "gen": 99, "root": str(tool_root), "team": TEAM}}
    refused = run_tools(tmp_path, env["env"], tool_root, ("ft2_start",), bad)[0]
    direct = cli(cli_root, "start", "--work", WORK, "--holder", HOLDER, "--gen", "99")
    assert refused["isError"] is True and direct.returncode == 1 and refused["text"] == direct.stdout.strip(), refused
    assert "낡은 실행권" in refused["text"], "rc≠0 은 오류로 나간다(성공으로 감싸지 않는다)"


def test_c_missing_argument_calls_nothing_and_writes_nothing(tmp_path):
    root, env = tmp_path / "root", seat(tmp_path)
    root.mkdir()
    prepare(root, BASE)
    before = snapshot(root)
    cases = {"ft2_claim": {"holder": HOLDER}, "ft2_start": {"work": WORK, "holder": HOLDER},
             "ft2_effect": {"work": WORK, "holder": HOLDER, "gen": GEN},
             "ft2_result": {"work": WORK, "holder": HOLDER}}
    got = run_tools(tmp_path, env["env"], root, TOOLS, {k: {**v, "root": str(root), "team": TEAM} for k, v in cases.items()})
    assert [row["isError"] for row in got] == [True] * 4 and all("인자 빠짐" in row["text"] for row in got), got
    assert calls(env["env"]) == [], "인자 빠짐이면 cli 호출 0"
    assert snapshot(root) == before, "루트 파일 변화 0"
    empty = run_tools(tmp_path, env["env"], root, ("ft2_claim",), {"ft2_claim": {"root": str(root), "team": TEAM}})
    assert empty[0]["isError"] is True and calls(env["env"]) == [], "전부 빠져도 같다"


def test_d_pi_seat_finishes_one_work(tmp_path):
    root, env = tmp_path / "root", seat(tmp_path)
    root.mkdir()
    prepare(root, BASE)
    claim = run_tools(tmp_path, env["env"], root, ("ft2_claim",))
    assert claim[0]["isError"] is False and json.loads(claim[0]["text"])["gen"] == GEN, claim
    rest = run_tools(tmp_path, env["env"], root, ("ft2_start", "ft2_effect", "ft2_result"))
    assert [row["isError"] for row in rest] == [False] * 3, rest
    assert [c[0] for c in calls(env["env"])] == ["claim", "start", "effect", "result"], "claim→result 를 도구로 끝낸다"
    seen = core("projection")
    works = seen.project(root, TEAM)["works"]
    assert list(works) == [WORK], works
    records = core("journal").Journal(seen.runtime_path(root, TEAM), rec=core("record")).records()
    assert [r["kind"] for r in records if r["work"] == WORK and r["kind"] == "result"] == ["result"], "journal 에 결과 1건"
    assert works[WORK]["owner"] is None and works[WORK]["done"] is False, works[WORK]


LEGACY = ("harness/" + "bin", "harness/" + "kit", "LIVE" + "_BIN", "." + "fable-team" + "/bin", "1" + ".x")


def test_e_no_legacy_dependency(tmp_path):
    guard = subprocess.run([sys.executable, str(GUARD), str(FT2)], capture_output=True, text=True, timeout=60)
    assert guard.returncode == 0, guard.stdout + guard.stderr
    source = ADAPTER.read_text(encoding="utf-8")
    assert "core/cli.py" in source and "python3" in source, "코어 cli 동사만 부른다"
    assert [bad for bad in LEGACY if bad in source] == [], "1.x 경로·도구 문자열 0"


MUTANTS = {"M1: rc≠0 을 성공으로": ("isError: true };\n      return { content", "};\n      return { content"),
           "M2: 인자 검사 빼기": ("if (bad) return fail(", "if (false) return fail(")}


def mutant(tmp_path, replacement_new):
    old, new = replacement_new
    source = ADAPTER.read_text(encoding="utf-8")
    assert old in source, old
    path = tmp_path / "mutant-ft2-seat.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path


def test_f_mutants_break_their_cases(tmp_path):
    for name, pair in MUTANTS.items():
        box = tmp_path / name.split(":")[0]
        box.mkdir()
        env = seat(box, adapter=mutant(box, pair))
        root = box / "root"
        root.mkdir()
        prepare(root, BASE)
        if name.startswith("M1"):  # ⓑ 가 빨강: rc≠0 인데 isError 가 아니다
            got = run_tools(box, env["env"], root, ("ft2_start",), {"ft2_start": {"work": WORK, "holder": HOLDER, "gen": 99, "root": str(root), "team": TEAM}})
            assert got[0]["isError"] is False and len(calls(env["env"])) == 1, (name, got)
        else:                      # ⓒ 가 빨강: 인자 빠짐인데 cli 를 부른다(쓰기 시도)
            got = run_tools(box, env["env"], root, ("ft2_start",), {"ft2_start": {"work": WORK, "holder": HOLDER, "root": str(root), "team": TEAM}})
            assert got[0]["isError"] is True and len(calls(env["env"])) == 1, (name, got)
