"""r1689 — 좌석 상태 판정: 끝난 줄은 IDLE · 진행 줄은 BUSY · 다른 명부의 pi 좌석은 pi 어댑터.

입력은 전부 가짜다: pane 캡처 사본(2026-11-11 실 화면을 읽어 옮긴 글자) · tmp 명부 3개 · 가짜 tmux(PATH 앞) · 합성 pi 세션.
실 pane·실 명부·실 우편함 0 · sleep 0. 변이 M1~M3 는 tmp 사본에서만.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
KIT = Path(__file__).resolve().parents[2] / "kit" / "fable-team" / "bin"
CODEX_TAIL = "› Ask Codex to do anything\n  GPT-6.1-Sol high · Context 83% left · 6.61M in · 20.5K out\n  ← for agents · ? for shortcuts\n"
CLAUDE_TAIL = "────────────\n❯ \n────────────\n  ctx:11% | Fable 5.2 high\n  ⏵⏵ bypass permissions on (shift+tab to cycle)\n"
PI_TAIL = "~/Project/x (main) • seat\n↑272 ↓63k R13M W189k CH99.1% 19.2%/1.0M   claude-opus-5-5 • medium\n"
PANES = {  # 좌석 → (명부 agent 또는 None=어느 명부에도 없음, pane 글자, 기대 PANE 값)
    "t-feature-da-codex#6": ("codex", "  근거: 추적 판정문, commit 19e24c81f2.\n  Worked for 5m 37s • 6:30 PM\n" + CODEX_TAIL, "IDLE"),
    "t-harness-da-codex#10": ("codex", "  실제 닫기 성공 기록을 확인해 팀장에게 회신했습니다.\n  Worked for 1m 45s • 6:42 PM\n" + CODEX_TAIL, "IDLE"),
    "t-harness-da-astra#0": (None, "  구현·설치 승인은 아직 아닙니다.\n  Worked for 3m 45s • 6:52 PM\n" + CODEX_TAIL, "IDLE"),
    "t-aifp-da-codex#0": ("codex", "• Working (2m 07s • esc to interrupt)\n" + CODEX_TAIL, "BUSY"),
    "t-claude-spin#0": ("claude", "✻ Cogitating… (esc to interrupt)\n" + CLAUDE_TAIL, "BUSY"),
    "t-claude-newword#0": ("claude", "✽ Onioning… (1m 16s · ↓ 5.4k tokens)\n" + CLAUDE_TAIL, "BUSY"),
    "t-claude-brewed#0": ("claude", "⏺ 끝났습니다.\n✻ Brewed for 1m 2s\n" + CLAUDE_TAIL, "IDLE"),
    "t-claude-worked#0": ("claude", "⏺ 끝났습니다.\n✻ Worked for 3m\n" + CLAUDE_TAIL, "IDLE"),
    "t-claude-crunched#0": (None, "⏺ 끝났습니다.\n✻ Crunched for 2m 3s\n" + CLAUDE_TAIL, "IDLE"),
    "t-nolist-pi-work#0": (None, " $ bash mbox.sh send\n── ⠦ Working ──────────\n────────────\n" + PI_TAIL, "BUSY"),
    "t-nolist-pi-idle#0": (None, " 근거: 착지 쪽지 3929\n────────────\n\n────────────\n" + PI_TAIL, "IDLE"),
    "t-blank#0": (None, "\n\n", "UNKNOWN"),  # DA R2 — 빈 화면 = 근거 0(끝난 줄·프롬프트가 있는 화면과 다르다)
    # DA R1 — 보고 문장 속 낱말·인용된 진행 줄은 진행이 아니다. 진행 줄 «뒤» 에 끝난 줄이 있으면 끝난 것이다
    "t-codex-report-word#0": ("codex", "Cogitating 진행 표시를 확인했고 수정 내용을 반영했습니다.\nWorked for 5m 37s • 6:30 PM\n› Ask Codex to do anything\n", "IDLE"),
    "t-codex-quoted-spin#0": (None, "• 화면에 아래 두 줄이 보였습니다.\n  ✻ Cogitating… (esc to interrupt)\n• Working (2m 07s • esc to interrupt)\n  Worked for 2m 1s • 7:01 PM\n" + CODEX_TAIL, "IDLE"),
    "t-claude-report-word#0": ("claude", "⏺ Baking 단계와 thinking 토큰, Musing 낱말을 설명했습니다.\n✻ Brewed for 9s\n" + CLAUDE_TAIL, "IDLE"),
    "t-claude-next-turn#0": ("claude", "✻ Brewed for 1m 2s\n❯ 다음 일\n✽ Onioning… (3s · ↓ 12 tokens)\n" + CLAUDE_TAIL, "BUSY"),  # 끝난 줄 뒤 새 진행 줄 = 작업 중
    "t-nocapture#0": (None, None, "UNKNOWN"),  # 캡처 실패 = 판정 불가
    # pi 어댑터 경로 — pane 글자는 일부러 반대로 둔다(판정이 pane 이 아니라 pi 기록에서 나와야 통과)
    "t-feature-arch-pi#1": ("pi", " 끝난 것처럼 보이는 화면\n" + PI_TAIL, "BUSY"),
    "t-aifp-master-pi#4": ("pi", "── ⠹ Working ──────────\n" + PI_TAIL, "IDLE"),
    "t-planner-lost-pi#9": ("pi", "── ⠹ Working ──────────\n" + PI_TAIL, "UNKNOWN"),  # pi 기록 없음 = 결속 불가
}
ROSTER = {  # 명부 파일 → 좌석들 — 첫 명부(seats.json)에는 pi 가 없다
    "a/seats.json": ["t-claude-spin#0", "t-claude-newword#0", "t-claude-brewed#0", "t-claude-worked#0", "t-harness-da-codex#10",
                     "t-codex-report-word#0", "t-claude-report-word#0", "t-claude-next-turn#0"],
    "a/seats-feature.json": ["t-feature-da-codex#6", "t-feature-arch-pi#1"],
    "a/seats-planner.json": ["t-planner-lost-pi#9"],
    "b/seats-aifp.json": ["t-aifp-da-codex#0", "t-aifp-master-pi#4"],
}
PI_STOP = {"t-feature-arch-pi#1": "toolUse", "t-aifp-master-pi#4": "stop"}  # toolUse = 일하는 중 · stop = 끝남
TMUX = r"""#!/bin/sh
W="$R1689_W"
case "$1" in
  list-sessions) cat "$W/sessions";;
  list-panes) case "$*" in
      *pane_pid*) while read -r s; do printf '%s\t%s\t%s\t0\n' "$s" "$R1689_PID" "$W/cwd"; done < "$W/sessions";;
      *) while read -r s; do printf '%s|%s\n' "$s" "$s"; done < "$W/sessions";;
    esac;;
  capture-pane) for a in "$@"; do t="$a"; done; cat "$W/panes/$t" 2>/dev/null || exit 1;;
  show-environment) for a in "$@"; do case "$a" in =*) s="${a#=}";; esac; done; echo "TMUXC_PI_SESSION_ID=sid-$s";;
  display-message) echo "$W/cwd";;
  *) exit 1;;
esac
"""


def build(w: Path) -> dict:
    for d in ("panes", "cwd", "home", "fake", "sessions.d/enc", "a/.fable-team", "b/.fable-team"):
        (w / d).mkdir(parents=True)
    (w / "sessions").write_text("".join(s + "\n" for s in PANES), encoding="utf-8")
    for seat, (_, text, _) in PANES.items():
        if text is not None:
            (w / "panes" / seat).write_text(text, encoding="utf-8")
    for rel, seats in ROSTER.items():
        root, name = rel.split("/")
        rows = {s: {"agent": PANES[s][0], "role": "nano"} for s in seats}
        (w / root / ".fable-team" / name).write_text(json.dumps(rows), encoding="utf-8")
    (w / "roots.tsv").write_text("# 이름\t경로\na\t%s\tx\nb\t%s\tx\n" % (w / "a", w / "b"), encoding="utf-8")
    for n, (seat, stop) in enumerate(PI_STOP.items()):
        rows = [{"type": "session", "id": "sid-" + seat, "cwd": str(w / "cwd")},
                {"type": "message", "timestamp": "2026-11-11T09:00:00Z", "message": {"role": "assistant", "stopReason": stop}},
                {"type": "session_info", "name": seat}]
        (w / "sessions.d" / "enc" / f"{n}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    tmux = w / "fake" / "tmux"
    tmux.write_text(TMUX, encoding="utf-8")
    tmux.chmod(0o755)
    return {**os.environ, "PATH": f"{w / 'fake'}{os.pathsep}{os.environ['PATH']}", "HOME": str(w / "home"),
            "R1689_W": str(w), "R1689_PID": str(os.getpid()), "FT_TMUX": str(tmux), "FT_PI_SESSIONS": str(w / "sessions.d"),
            "FT_SEATS_JSON": str(w / "a" / ".fable-team" / "seats.json"), "FT_ROOTS_TSV": str(w / "roots.tsv")}


def listing(script: Path, env: dict) -> dict:
    out = subprocess.run(["bash", str(script), "list", "^t-", "--json"], env=env, text=True, capture_output=True, timeout=60)
    assert out.returncode == 0, out.stderr
    return {r["seat"]: r for r in json.loads(out.stdout)}


@pytest.fixture(scope="module")
def world(tmp_path_factory):
    w = tmp_path_factory.mktemp("r1689")
    env = build(w)
    return w, env, listing(BIN / "ft-seat-status.sh", env)


@pytest.mark.parametrize("seat", list(PANES))
def test_pane_state(world, seat):  # ⓐ 끝난 codex · ⓑ 일하는 codex · ⓒ 다른 명부 pi · ⓒ+ 판정 불가·명부 밖 pi · ⓓ claude
    assert world[2][seat]["pane"] == PANES[seat][2]


def test_pi_seat_of_other_roster_and_other_root_has_agent_pi(world):  # ⓒ AGENT 열
    rows = world[2]
    assert [rows[s]["agent"] for s in ("t-feature-arch-pi#1", "t-aifp-master-pi#4", "t-planner-lost-pi#9")] == ["pi"] * 3
    assert rows["t-aifp-da-codex#0"]["agent"] == "codex" and rows["t-nolist-pi-work#0"]["agent"] == "-"
    assert isinstance(rows["t-aifp-master-pi#4"]["jsonl_age"], int) and rows["t-feature-arch-pi#1"]["jsonl_age"] is None


def test_output_shape_is_unchanged(world):  # 소비자(ft-tick·stall-scan) 보호 — 4열 · JSON 키 그대로
    w, env, rows = world
    assert set(rows["t-blank#0"]) == {"seat", "pane", "jsonl_age", "agent", "replaced"}
    out = subprocess.run(["bash", str(BIN / "ft-seat-status.sh"), "one", "t-blank#0"], env=env, text=True, capture_output=True, timeout=60)
    assert out.stdout.split() == ["t-blank#0", "UNKNOWN", "-", "-"]


def test_source_equals_kit():
    assert (BIN / "ft-seat-status.sh").read_bytes() == (KIT / "ft-seat-status.sh").read_bytes()


MUTANTS = {  # 이름 → (지울 글자, 바꿀 글자, 그 변이가 뒤집어야 하는 좌석, 뒤집힌 값 «pane» 또는 «agent»)
    "M1 끝난 줄을 SPIN 에 되돌림": ('SPIN="$SPIN_CLAUDE|$SPIN_CODEX|$SPIN_PI"', 'SPIN="Worked for|$SPIN_CLAUDE|$SPIN_CODEX|$SPIN_PI"', "t-feature-da-codex#6", ("pane", "BUSY")),
    "M6 끝난 줄 뒤 순서를 안 봄": ('[ "$spin" -ge "${fin:-0}" ]', '[ "$spin" -ge 0 ]', "t-codex-quoted-spin#0", ("pane", "BUSY")),
    "M7 빈 화면을 IDLE 로": ('[ -n "${cap//[[:space:]]/}" ] ||', "true ||", "t-blank#0", ("pane", "IDLE")),
    "M2 codex 진행 토큰 뺌": ('SPIN="$SPIN_CLAUDE|$SPIN_CODEX|$SPIN_PI"', 'SPIN="$SPIN_CLAUDE|$SPIN_PI"', "t-aifp-da-codex#0", ("pane", "IDLE")),
    "M3 pi 관문을 명부 1개로": ("    files += sorted(glob.glob(os.path.join(d, \"seats*.json\")))", "    pass", "t-feature-arch-pi#1", ("agent", "-")),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant_is_caught(world, tmp_path, name):
    w, env, good = world
    old, new, seat, (key, flipped) = MUTANTS[name]
    for f in BIN.glob("ft_seat*.py"):
        shutil.copy(f, tmp_path)
    text = (BIN / "ft-seat-status.sh").read_text(encoding="utf-8")
    assert text.count(old) == 1, "변이 자리가 원본에 1곳이어야 한다"
    (tmp_path / "ft-seat-status.sh").write_text(text.replace(old, new), encoding="utf-8")
    bad = listing(tmp_path / "ft-seat-status.sh", env)
    assert good[seat][key] != flipped and bad[seat][key] == flipped
