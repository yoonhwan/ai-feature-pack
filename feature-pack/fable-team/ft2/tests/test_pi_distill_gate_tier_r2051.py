"""ft2 pi distill-gate r2051 시험 — 증류 문턱 모델 창 티어별 세트(①~⑥ pi 몫 · ft-thresholds.sh·claude 훅 몫 = 1.x 하네스 tests/test_thresholds_tier_r2051.sh).
node 로 thresholds()·judge() 만 부른다 · 픽스처 = tmp_path 뿐(임시 HOME · 실 명부·우편함·tmux 0 · FT_SEAT 로 좌석)."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GATE = Path(os.environ.get("PI_GATE") or FT2 / "adapters" / "pi" / "distill-gate.ts")
NODE = shutil.which("node")
SEAT = "byz-x-nano#0"
BASE = "FT_DISTILL_WARN=330000\nFT_DISTILL_BLOCK=350000\nFT_DISTILL_RECV=280000\n"
T200 = "FT_DISTILL_TIER_200K_MATCH=haiku\nFT_DISTILL_RECV_200K=120000\nFT_DISTILL_WARN_200K=140000\nFT_DISTILL_BLOCK_200K=150000\n"
T400 = "FT_DISTILL_TIER_400K_MATCH=haiku-4\nFT_DISTILL_RECV_400K=200000\nFT_DISTILL_WARN_400K=210000\nFT_DISTILL_BLOCK_400K=220000\n"
DRIVER = """
import fs from "node:fs"; const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8"));
const err = [], orig = console.error; console.error = (...a) => err.push(a.map(String).join(" "));
const out = req.cases.map((c) => c.op === "thr" ? mod.thresholds(req.env, req.cwd, c.model) : mod.judge({ ...c, cwd: req.cwd, env: req.env, seat: undefined }));
console.error = orig; process.stdout.write(JSON.stringify({ out, err }));"""

pytestmark = pytest.mark.skipif(NODE is None, reason="node 없음")


def run(tmp, text, cases, env=None):
    root = tmp / "repo"
    (root / ".git").mkdir(parents=True, exist_ok=True)
    (root / ".fable-team").mkdir(exist_ok=True)
    (root / ".fable-team" / "thresholds.env").write_text(text, encoding="utf-8")
    e = {"FT_SEAT": SEAT, "FT_DISTILL_SAMPLE": str(tmp / "no-sample")}
    e.update(env or {})
    proc = subprocess.run([NODE, "--no-warnings", "--input-type=module", "-e", DRIVER], capture_output=True, text=True, timeout=60,
                          env={"PATH": os.environ["PATH"], "HOME": str(tmp), "FT_GATE": GATE.resolve().as_uri()},
                          input=json.dumps({"cwd": str(root), "env": e, "cases": cases}))
    if proc.returncode != 0:
        pytest.fail(proc.stderr[-800:])
    return json.loads(proc.stdout)


def trio(t):
    return None if t is None else (t["recv"], t["warn"], t["block"])


def test_1_haiku_tier_and_gate(tmp_path):
    r = run(tmp_path, BASE + T200, [{"op": "thr", "model": "claude-haiku-4-5"},
                                    {"tool": "bash", "command": "ls", "tokens": 145000, "model": "claude-haiku-4-5"},
                                    {"tool": "bash", "command": "ls", "tokens": 155000, "model": "claude-haiku-4-5"}])["out"]
    assert trio(r[0]) == (120000, 140000, 150000)
    assert r[1]["rule"] == "warn-line" and "140000" in r[1]["reason"]
    assert r[2]["action"] == "block" and r[2]["rule"] == "block-gate"


def test_2_opus_gpt_base(tmp_path):
    r = run(tmp_path, BASE + T200, [{"op": "thr", "model": "claude-opus-5-5"}, {"op": "thr", "model": "gpt-6-sol"}, {"op": "thr"},
                                    {"tool": "bash", "command": "ls", "tokens": 145000, "model": "claude-opus-5-5"}])["out"]
    assert trio(r[0]) == trio(r[1]) == trio(r[2]) == (280000, 330000, 350000)
    assert r[3]["rule"] == "below-warn"


def test_3_first_tier_in_file_order(tmp_path):
    assert trio(run(tmp_path, BASE + T200 + T400, [{"op": "thr", "model": "claude-haiku-4-5"}])["out"][0]) == (120000, 140000, 150000)
    assert trio(run(tmp_path, BASE + T400 + T200, [{"op": "thr", "model": "claude-haiku-4-5"}])["out"][0]) == (200000, 210000, 220000)


def test_4_incomplete_tier_falls_back(tmp_path):
    text = BASE + "FT_DISTILL_TIER_200K_MATCH=haiku\nFT_DISTILL_RECV_200K=120000\n"
    res = run(tmp_path, text, [{"op": "thr", "model": "claude-haiku-4-5"}, {"tool": "bash", "command": "ls", "tokens": 145000, "model": "claude-haiku-4-5"}])
    t, v = res["out"]
    assert trio(t) == (280000, 330000, 350000) and t.get("note") == "티어 200K 불완전 — 기본 세트"
    assert v["rule"] == "below-warn"
    assert sum("티어 200K 불완전" in line for line in res["err"]) == 1
    bad = BASE + T200.replace("FT_DISTILL_BLOCK_200K=150000", "FT_DISTILL_BLOCK_200K=100000")
    assert trio(run(tmp_path, bad, [{"op": "thr", "model": "claude-haiku-4-5"}])["out"][0]) == (280000, 330000, 350000)


def test_5_env_base_key_wins(tmp_path):
    r = run(tmp_path, BASE + T200, [{"op": "thr", "model": "claude-haiku-4-5"}], env={"FT_DISTILL_RECV": "50000"})["out"]
    assert trio(r[0]) == (50000, 140000, 150000)


def test_6_empty_model_same_as_before(tmp_path):
    case = [{"op": "thr", "model": ""}, {"tool": "bash", "command": "ls", "tokens": 145000, "model": ""}]
    a = run(tmp_path, BASE + T200, case)
    b = run(tmp_path, BASE, case)
    assert a["out"] == b["out"] and a["out"][1]["rule"].startswith("undecidable")
