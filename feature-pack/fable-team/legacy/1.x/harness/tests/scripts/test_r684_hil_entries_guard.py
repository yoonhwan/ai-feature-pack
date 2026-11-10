"""r684 — 시험이 «실제» 사람 실행 번호표(${HIL_DIR:-/tmp}/h<N>)를 쓰지 않게 막고(공용 가드가 자식 env 에 HIL_DIR 주입)·잡는다(실 상태 지문에 h<N> 최대 번호·개수).

사건(arch 119 실측 2026-10-22): 나노 되돌리기 시험이 ft-hil.sh --add 를 그대로 불러 진짜 /tmp 에 h187~h238 을 썼고
( h236 본문 = «# ft-hil-entry plan=…/undo-repo/.fable-team/state/spawn-undo/…sh.hil» ) ft-tick 이 «사람이 아직 실행 안 한 명령» 오경보를 냈다.
막기 = ① _nano_rollback_env 의 undo 실행 env 에 HIL_DIR ② 공용 가드(sh·py)가 자식 env 에 HIL_DIR=<임시>/hil 주입.
잡기 = ③ 지문(fingerprint)에 h<N> 최대 번호·개수 — 시험 중 «늘면» REAL-STATE-GUARD FAIL. 줄어듦은 사람 정리라 FAIL 아님.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from _nano_rollback_env import jsonl, make_env, roster, undo, undo_env

HERE = Path(__file__).resolve().parent
RSG = HERE / "real_state_guard.py"
GUARD_SH = HERE.parent / "lib" / "real_state_guard.sh"
KIT_BIN = HERE.parent.parent / "bin"


def hil_files(d):
    """<d>/h<숫자> 목록(링크·파일 모두) — ft-hil.sh 의 max_n 과 같은 눈."""
    p = Path(d) if d else None
    if not p or not p.is_dir():
        return []
    out = []
    for f in p.iterdir():
        m = re.fullmatch(r"h(\d+)", f.name)
        if m and (f.exists() or f.is_symlink()):
            out.append(int(m.group(1)))
    return sorted(out)


def real_hil_max():
    """실제 번호표 폴더(이 시험 실행 env 기준)의 최대 번호 — 읽기만 한다."""
    nums = hil_files(os.environ.get("HIL_DIR") or "/tmp")
    return nums[-1] if nums else 0


def real_hil_count():
    return len(hil_files(os.environ.get("HIL_DIR") or "/tmp"))


def no_hil_env():
    return {k: v for k, v in os.environ.items() if k != "HIL_DIR"}


# ---- ① 격리 env (ⓐ) ----

def test_undo_env_sets_hil_dir_inside_temp(tmp_path):
    e = make_env(tmp_path)
    env = undo_env(e)
    assert "HIL_DIR" in env, "_nano_rollback_env 의 undo env 에 HIL_DIR 이 없다 — 시험이 진짜 /tmp/h<N> 에 쓴다"
    hil = Path(env["HIL_DIR"])
    assert hil.is_dir(), f"HIL_DIR 이 폴더가 아니다: {hil}"
    assert str(tmp_path) in str(hil), f"HIL_DIR 이 시험 임시 폴더 밖이다: {hil}"


# ---- ② 실 누수 0 (ⓑ) — 단독 모드 1회 뒤 임시 폴더에만 1장, 실제 /tmp 최대 번호 그대로 ----

def test_standalone_plan_writes_entry_only_into_temp_hil_dir(tmp_path):
    e = make_env(tmp_path)
    roster(e)
    jsonl(e)
    before = real_hil_max()
    r = undo(e, "--card", str(e["card"]), HIL_CLIP="0")
    assert r.returncode == 0, r.stdout + r.stderr
    hil = Path(undo_env(e)["HIL_DIR"])
    assert hil_files(hil) == [1], f"임시 HIL_DIR 에 번호표 1장이 아니다: {hil_files(hil)}"
    assert "사람 ! 실행: ! bash" in r.stdout, f"안내 줄에 짧은 실행 경로가 없다: {r.stdout}"
    assert real_hil_max() == before, f"실제 번호표가 늘었다: {before} → {real_hil_max()}"


# ---- ③ 지문이 잡는다 (ⓒ py) ----

def test_py_fingerprint_records_hil_axis(tmp_path):
    out = tmp_path / "snap.json"
    subprocess.run([sys.executable, str(RSG), "snap", "--out", str(out), "--cwd", str(tmp_path)],
                   check=True, env=no_hil_env(), capture_output=True, text=True)
    fp = json.loads(out.read_text())["fp"]
    assert fp["hil"]["dir"] == os.path.realpath("/tmp"), \
        f"HIL_DIR 미설정이면 /tmp 를 본다: {fp.get('hil')}"
    assert isinstance(fp["hil"]["max"], int) and isinstance(fp["hil"]["count"], int)


def test_py_fingerprint_fails_when_real_hil_entry_appears(tmp_path):
    root = tmp_path / "data"
    (root / ".fable-team" / "state").mkdir(parents=True)
    hil = tmp_path / "hil"
    hil.mkdir()
    env = {**no_hil_env(), "FT_ROOT": str(root), "HIL_DIR": str(hil)}
    out = tmp_path / "snap.json"
    subprocess.run([sys.executable, str(RSG), "snap", "--out", str(out), "--cwd", str(tmp_path)],
                   check=True, env=env, capture_output=True, text=True)
    assert json.loads(out.read_text())["roots"], "실 루트를 못 풀면 compare 가 PASS 로 끝나 지문이 무의미하다(FT_ROOT 픽스처)"
    (hil / "h1").write_text("#!/usr/bin/env bash\n")
    c = subprocess.run([sys.executable, str(RSG), "compare", str(out)], env=env, capture_output=True, text=True)
    assert c.returncode == 1, f"새 번호표를 못 잡았다 rc={c.returncode} {c.stderr}"
    assert f"FAIL 실 상태 바뀜: {hil / 'h1'}" in c.stderr, f"FAIL 줄이 번호표를 안 가리킨다: {c.stderr}"


def test_py_fingerprint_pass_when_hil_entry_only_shrinks(tmp_path):
    """사람이 옛 번호표를 정리(줄어듦)하는 것은 FAIL 이 아니다 — planner 의 h187~h238 정리와 겹치지 않게."""
    root = tmp_path / "data"
    (root / ".fable-team" / "state").mkdir(parents=True)
    hil = tmp_path / "hil"
    hil.mkdir()
    (hil / "h7").write_text("x")
    env = {**no_hil_env(), "FT_ROOT": str(root), "HIL_DIR": str(hil)}
    out = tmp_path / "snap.json"
    subprocess.run([sys.executable, str(RSG), "snap", "--out", str(out), "--cwd", str(tmp_path)],
                   check=True, env=env, capture_output=True, text=True)
    (hil / "h7").unlink()
    c = subprocess.run([sys.executable, str(RSG), "compare", str(out)], env=env, capture_output=True, text=True)
    assert c.returncode == 0, f"줄어듦을 FAIL 로 본다: rc={c.returncode} {c.stderr}"

def test_simulated_plan_classification(tmp_path):
    """r684 r2: 번호표 계획 경로로 «시험 사본» 과 «실 좌석» 을 가른다.
    사건(2026-10-22 03:34 master#93): /tmp/h259 = plan=<BYZ-Agents>/.fable-team/state/approve-merge-lecture-… (실 좌석 approve-merge).
    실 좌석 계획은 $HOME 아래, 시험 사본 계획은 mktemp(/tmp·/var/folders) 아래다.
    """
    sys.path.insert(0, str(HERE))
    import real_state_guard as rsg
    assert rsg._simulated(str(Path.home() / "Project/x/.fable-team/state/approve-merge-lecture-a.sh.hil")) is False
    assert rsg._simulated(str(tmp_path / "undo-repo/.fable-team/state/spawn-undo/p.sh.hil")) is True
    assert rsg._simulated("/tmp/tmp.ab12/undo-repo/x.sh.hil") is True, "macOS /tmp = /private/tmp 심볼릭"
    assert rsg._simulated(None) is True, "계획 줄이 없는 번호표는 판단 불가 = 누수로 본다"


def test_py_check_warns_when_new_entry_is_real_seat_plan(tmp_path, monkeypatch):
    """실 좌석 계획 번호표 = FAIL 이 아니라 WARN 1줄(동시 실행). pytest 임시 폴더는 그 자체가 temp 라 _simulated 를 고정한다."""
    sys.path.insert(0, str(HERE))
    import real_state_guard as rsg
    hil = tmp_path / "hil"
    hil.mkdir()
    monkeypatch.setenv("HIL_DIR", str(hil))
    before = {"roots": [], "fp": rsg.fingerprint([])}
    (hil / "h2").write_text("#!/usr/bin/env bash\n# ft-hil-entry plan=/Users/x/Project/a/.fable-team/state/approve-merge-a.sh.hil\n")
    monkeypatch.setattr(rsg, "_simulated", lambda p: False)
    fails, warns, _ = rsg.check(before)
    assert not fails, f"실 좌석 계획을 누수 FAIL 로 오판했다: {fails}"
    assert any("번호표 늘었으나 실 좌석 계획" in w for w in warns), f"WARN 1줄이 없다: {warns}"


def test_py_fingerprint_fails_when_new_entry_is_temp_copy_plan(tmp_path):
    """시험 사본 계획(tmp 아래) 번호표 = 진짜 누수 — 이건 계속 FAIL 이어야 한다(잡기 유지)."""
    root = tmp_path / "data"
    (root / ".fable-team" / "state").mkdir(parents=True)
    hil = tmp_path / "hil"
    hil.mkdir()
    copy_plan = tmp_path / "undo-repo" / ".fable-team" / "state" / "spawn-undo" / "p.sh.hil"
    copy_plan.parent.mkdir(parents=True)
    copy_plan.write_text("#!/usr/bin/env bash\n")
    env = {**no_hil_env(), "FT_ROOT": str(root), "HIL_DIR": str(hil)}
    out = tmp_path / "snap.json"
    subprocess.run([sys.executable, str(RSG), "snap", "--out", str(out), "--cwd", str(tmp_path)],
                   check=True, env=env, capture_output=True, text=True)
    (hil / "h3").write_text(f"#!/usr/bin/env bash\n# ft-hil-entry plan={copy_plan}\n")
    c = subprocess.run([sys.executable, str(RSG), "compare", str(out)], env=env, capture_output=True, text=True)
    assert c.returncode == 1, f"시험 사본 계획(tmp) 번호표를 못 잡았다 rc={c.returncode} {c.stderr}"
    assert f"FAIL 실 상태 바뀜: {hil / 'h3'}" in c.stderr, f"FAIL 줄이 번호표를 안 가리킨다: {c.stderr}"


# ---- ④ 공용 가드가 막는다 (ⓓ sh) — 자식 env HIL_DIR, 실제 /tmp 불변 ----

INNER = """#!/usr/bin/env bash
# r684 시험용 «가드가 지키는 시험» — 자식(RSG_ACTIVE)일 때만 번호표를 쓴다.
if [ -n "${RSG_ACTIVE:-}" ]; then
  printf '%s\\n' "${HIL_DIR:-}" > "$OUT/inner_hil"
  [ -n "${HIL_DIR:-}" ] || { echo NO_HIL_DIR >&2; exit 1; }
  mkdir -p "$HIL_DIR"
  bash "$KITBIN/ft-hil.sh" --add "$OUT/plan.sh" > "$OUT/inner_out" 2>&1 || exit 1
  ls -1 "$HIL_DIR" > "$OUT/inner_files"
  exit 0
fi
. "$GUARDSH"
guard_begin "$@"
"""


def test_shell_guard_injects_temp_hil_dir_into_child(tmp_path):
    (tmp_path / "plan.sh").write_text("#!/usr/bin/env bash\necho hi\n")
    inner = tmp_path / "inner.sh"
    inner.write_text(INNER)
    before = real_hil_max()
    r = subprocess.run(["bash", str(inner)], cwd=tmp_path, capture_output=True, text=True,
                       env={**no_hil_env(), "OUT": str(tmp_path), "KITBIN": str(KIT_BIN), "GUARDSH": str(GUARD_SH), "HIL_CLIP": "0"})
    assert r.returncode == 0, f"가드가 지키는 시험이 실패했다 — 자식 env 에 HIL_DIR 이 없다? {r.stdout[-500:]} {r.stderr[-500:]}"
    hil = (tmp_path / "inner_hil").read_text().strip()
    assert hil and hil != "/tmp", f"자식 HIL_DIR 이 실제 번호표 폴더다: {hil!r}"
    assert (tmp_path / "inner_files").read_text().split() == ["h1"], f"임시 HIL_DIR 에 h1 이 안 생겼다: {hil}"
    assert real_hil_max() == before, f"가드가 지키는 시험인데 실제 번호표가 늘었다: {before} → {real_hil_max()}"

# ---- ⑤ 닫기 시험이 실행마다 실 번호표를 만들지 않는다 (master 발주 135683 · r680 나노 «never_started +2장/회» 보고) ----

def test_nano_close_never_started_leaves_real_hil_count_unchanged():
    """r684 r2: 실 번호표는 동시 실행 좌석도 늘린다(전역 /tmp) — 세는 대신 «새 번호표의 계획이 시험 사본인지» 로 본다."""
    before = set(hil_files(os.environ.get("HIL_DIR") or "/tmp"))
    r = subprocess.run(["bash", str(HERE.parent / "test_nano_close_never_started.sh")], capture_output=True, text=True,
                       cwd=str(HERE.parent), env=no_hil_env())
    assert r.returncode == 0, f"{r.stdout[-800:]} {r.stderr[-400:]}"
    d = os.environ.get("HIL_DIR") or "/tmp"
    leaked = []
    for n in sorted(set(hil_files(d)) - before):
        p = os.path.join(d, f"h{n}")
        try:
            head = open(p, "rb").read(600).decode("utf-8", "replace")
        except OSError:
            continue
        m = re.search(r"ft-hil-entry plan=(\S+)", head)
        if not m:
            continue
        if os.path.realpath(m.group(1)).startswith("/var/folders") or os.path.realpath(m.group(1)).startswith("/tmp/") \
                or os.path.realpath(m.group(1)).startswith("/private/tmp/"):
            leaked.append(p)
    assert not leaked, f"never_started 시험이 시험 사본 계획으로 실 번호표를 늘렸다: {leaked}"
