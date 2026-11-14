"""r1996 — pi 좌석 cliPath 가 «부를 때마다» 설치본 CURRENT 판 cli 를 고른다.

임시 home 에 versions/2.0.49·2.0.50 (core/cli.py 스텁 + 어댑터 사본)과 CURRENT 파일을 둔다.
node 로 2.0.49 어댑터 사본을 불러 cliPath 를 부르고 고른 경로를 본다(실 cli·실 좌석 0 · sleep 0).
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
ADAPTER = FT2 / "adapters" / "pi" / "ft2-seat.ts"
NODE = shutil.which("node")
DRIVER = """
import fs from "node:fs";
const mod = await import(process.env.FT2_ADAPTER), steps = JSON.parse(fs.readFileSync(0, "utf8")), out = [];
for (const s of steps) { if (s.current !== undefined) fs.writeFileSync(process.env.FT2_HOME_CURRENT, s.current);
  out.push(mod.cliPath("/nowhere")); }
process.stdout.write(JSON.stringify(out));
"""
pytestmark = pytest.mark.skipif(NODE is None, reason="node 없음")


def home(tmp_path, current=None, versions=("2.0.49", "2.0.50")):
    """임시 home — 판마다 core/cli.py 스텁 · 2.0.49 에 어댑터 사본 · CURRENT(있으면)."""
    root = tmp_path / "ft2"
    for v in versions:
        (root / "versions" / v / "core").mkdir(parents=True)
        (root / "versions" / v / "core" / "cli.py").write_text("# stub\n", encoding="utf-8")
    (root / "versions" / "2.0.49" / "adapters" / "pi").mkdir(parents=True)
    shutil.copy(ADAPTER, root / "versions" / "2.0.49" / "adapters" / "pi" / "ft2-seat.ts")
    if current is not None:
        (root / "CURRENT").write_text(current, encoding="utf-8")
    return root


def pick(root, adapter, steps, env_cli=None):
    env = {k: v for k, v in os.environ.items() if k != "FT2_CLI"}
    env.update(FT2_ADAPTER=str(adapter), FT2_HOME_CURRENT=str(root / "CURRENT"))
    if env_cli:
        env["FT2_CLI"] = env_cli
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], input=json.dumps(steps),
                          capture_output=True, text=True, timeout=60, env=env)
    assert proc.returncode == 0, proc.stderr
    return [str(Path(p).resolve()) for p in json.loads(proc.stdout)]


def cli_of(root, v):
    return str((root / "versions" / v / "core" / "cli.py").resolve())


def adapter_of(root):
    return root / "versions" / "2.0.49" / "adapters" / "pi" / "ft2-seat.ts"


@pytest.mark.parametrize("current,want", [
    ("2.0.50", "2.0.50"),        # ① 옛 판 어댑터 · CURRENT 새 판 → 새 판 cli
    (None, "2.0.49"),            # ③ CURRENT 없음 → 어댑터 옆
    ("2.0.99", "2.0.49"),        # ④ 판 폴더 없음 → 어댑터 옆
    ("2.0.50 \n\n", "2.0.50"),   # ⑦ 줄 끝 공백·개행 다듬음
    ("", "2.0.49"),              # 빈 값 → 어댑터 옆
])
def test_current_resolution(tmp_path, current, want):
    root = home(tmp_path, current)
    assert pick(root, adapter_of(root), [{}]) == [cli_of(root, want)]


def test_reads_every_call_no_cache(tmp_path):
    """② 호출 사이에 CURRENT 를 2.0.49→2.0.50 으로 바꾸면 두 번째 호출부터 2.0.50."""
    root = home(tmp_path, "2.0.49")
    got = pick(root, adapter_of(root), [{}, {"current": "2.0.50"}])
    assert got == [cli_of(root, "2.0.49"), cli_of(root, "2.0.50")]


def test_env_cli_wins(tmp_path):
    """⑤ FT2_CLI 가 있으면 CURRENT 보다 앞."""
    root = home(tmp_path, "2.0.50")
    stub = tmp_path / "x.py"
    stub.write_text("", encoding="utf-8")
    assert pick(root, adapter_of(root), [{}], env_cli=str(stub)) == [str(stub.resolve())]


def test_pack_checkout_unchanged(tmp_path):
    """⑥ versions/ 꼴 밖(팩 원본 체크아웃) → 어댑터 옆 ../../core/cli.py 그대로."""
    root = home(tmp_path, "2.0.50")
    assert pick(root, ADAPTER, [{}]) == [str((FT2 / "core" / "cli.py").resolve())]
