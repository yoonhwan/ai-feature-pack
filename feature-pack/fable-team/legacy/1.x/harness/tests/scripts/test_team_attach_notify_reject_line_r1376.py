"""R1376 — 팀 명부 알림 실패 줄이 진짜 거절 원인을 보이고, 판정 불가와 알림 실패를 다른 칸으로 가른다.

W1 대역 stderr = WARN 1줄 + REJECT 1줄 · rc3 → «NOTIFY-FAIL rc=3 REJECT …» 전체 1줄 · WARN 만 실린 줄 0 · 표식 0
W2 대역 stderr = WARN 1줄 · rc0 → 성공 · 표식 1
W3 같은 날 두 번째 회차(표식 있음) → 전송 0 · «already sent»
W4 회차 중 명부 _master 가 바뀜(옛 이름으로 부름) → 지금 _master 로 전송
W5 판정 불가(u≥1) + 알림 성공 → 잡 rc1 · 요약 notify_fail=0 / 알림 실패 → NOTIFY-FAIL 줄 · notify_fail=1 · rc 그대로
임시 루트 · FT_MBOX_SH 대역 · 실 쪽지 0 · 자기 재호출 0. 기준판·변이는 R1376_BIN 으로 다른 bin 을 가리킨다.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get("R1376_BIN") or HARNESS / "bin")
WARN = "WARN planner 머리 규칙 위반(warn 모드 · 전송) — planner 앞 쪽지는 [결정]·[HIL]·[긴급]·[합치기]·[정지 레디]·[완료]·[부팅 보고] 만 — 진행·참고·마일스톤은 상태판으로 보낸다 " + "가" * 40
REJECT = "REJECT 은퇴한 좌석 byz-planner-master-claude#1 → 현역 byz-planner-master-pi#2 — 후계 이름으로 다시 보내라"
STUB = f"""#!/bin/bash
printf '%s\\n' "$*" >> "$R1376_SENT"
echo '{WARN}' >&2
[ "$R1376_MODE" = reject ] || exit 0
echo '{REJECT}' >&2
exit 3
"""


def _root(tmp: Path, mode: str) -> tuple[Path, dict[str, str]]:
    root = tmp / "root"
    (root / "design/teams/planner/indices").mkdir(parents=True)
    (root / ".fable-team/bin").mkdir(parents=True)
    (root / "design/TEAMS.md").write_text("| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | design/teams/planner/ | x | 현역 |\n", encoding="utf-8")
    (root / "design/TEAMSET.md").write_text("## 표 2\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    (root / ".fable-team/bin/team-tick-env.tsv").write_text("# header\n", encoding="utf-8")
    roster(root, "byz-planner-master-pi#2")
    mbox = tmp / "mbox.sh"
    mbox.write_text(STUB, encoding="utf-8")
    mbox.chmod(0o755)
    env = {**os.environ, "FT_ROOT": str(root), "FT_TEAMS_MD": str(root / "design/TEAMS.md"), "FT_TEAMSET_MD": str(root / "design/TEAMSET.md"),
           "FT_TEAM_ATTACH_SANDBOX": "1", "FT_MBOX_SH": str(mbox), "R1376_SENT": str(tmp / "sent.log"), "R1376_MODE": mode,
           "FT_TICK_TEAM_TSV": str(root / ".fable-team/bin/team-tick-env.tsv")}
    return root, env


def roster(root: Path, master: str) -> None:
    doc = {"_master": master, "_cards": "design/teams/planner/indices", "byz-planner-master-claude#1": "byz-planner-master-pi#2", master: None}
    (root / ".fable-team/seats-planner.json").write_text(json.dumps(doc), encoding="utf-8")


def attach(env: dict[str, str], to: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-team-attach.sh"), "--all", "--check", "--notify", to],
                          capture_output=True, text=True, timeout=30, env=env, cwd=env["FT_ROOT"])


def sent(tmp: Path) -> list[str]:
    p = tmp / "sent.log"
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def markers(root: Path) -> list[Path]:
    return sorted((root / ".fable-team/state/team-attach-lint").glob("*.sent"))


def test_w1_reject_line_is_kept_whole(tmp_path):
    root, env = _root(tmp_path, "reject")
    r = attach(env, "byz-planner-master-pi#2")
    lines = [x for x in r.stdout.splitlines() if x.startswith("NOTIFY-FAIL")]
    assert lines == [f"NOTIFY-FAIL rc=3 {REJECT}"], r.stdout
    assert not any("WARN planner" in x for x in r.stdout.splitlines() if "실패" in x or "FAIL" in x), r.stdout
    assert markers(root) == [], "실패한 날은 표식 0(다음 회차 재시도)"


def test_w2_warn_only_send_counts_as_success(tmp_path):
    root, env = _root(tmp_path, "warn")
    r = attach(env, "byz-planner-master-pi#2")
    assert "NOTIFY-FAIL" not in r.stdout and r.returncode == 1, r.stdout   # rc1 = 명부 어긋남(알림 실패 아님)
    assert len(sent(tmp_path)) == 1 and len(markers(root)) == 1


def test_w3_same_day_second_run_does_not_resend(tmp_path):
    root, env = _root(tmp_path, "warn")
    attach(env, "byz-planner-master-pi#2")
    r = attach(env, "byz-planner-master-pi#2")
    assert len(sent(tmp_path)) == 1, sent(tmp_path)
    assert "already sent" in r.stdout, r.stdout
    assert markers(root) == [root.resolve() / ".fable-team/state/team-attach-lint" / markers(root)[0].name]


def test_w4_recipient_is_reread_from_roster_before_send(tmp_path):
    root, env = _root(tmp_path, "warn")
    roster(root, "byz-planner-master-pi#3")   # 회차 시작 뒤 승계 — 잡은 옛 이름(#1)을 들고 있다
    attach(env, "byz-planner-master-claude#1")
    got = sent(tmp_path)
    assert len(got) == 1 and got[0].startswith("send byz-planner-master-pi#3 "), got


def _sweep(tmp: Path, attach_body: str) -> tuple[int, str, str]:
    """FT_ROOT = git 아닌 폴더 → 본체 «판정 불가 :init» u=1(주입 0). attach 는 정해진 출력만 내는 대역."""
    b = tmp / "bin"
    b.mkdir()
    for f in BIN.glob("ft_team*.py"):
        shutil.copy2(f, b / f.name)
    shutil.copy2(BIN / "ft-wt-sweep.sh", b / "ft-wt-sweep.sh")
    (b / "ft-team-attach.sh").write_text("#!/bin/bash\n" + attach_body, encoding="utf-8")
    (b / "ft-team-attach.sh").chmod(0o755)
    root, env = _root(tmp, "warn")
    env.update({"FT_WT_ARCHIVE": "0", "FT_WT_LAND_PLAN": "0", "FT_WT_SHELL_SCAN_SEC": "0", "FT_MBOX_SH": "/usr/bin/true",
                "HIL_DIR": str(tmp / "hil"), "HIL_CLIP": "0", "GIT_CEILING_DIRECTORIES": str(tmp)})
    r = subprocess.run(["bash", str(b / "ft-wt-sweep.sh"), "--launchd"], capture_output=True, text=True, timeout=60, env=env, cwd=str(tmp))
    log = (root / ".fable-team/state/wt-sweep.log").read_text(encoding="utf-8").splitlines()
    return r.returncode, r.stdout + r.stderr, log[-1] if log else ""


def test_w5_unknown_and_notify_are_separate(tmp_path):
    rc, out, last = _sweep(tmp_path, 'echo "SUMMARY mismatch=1 unknown=0"; exit 1\n')
    assert "판정 불가" in out and rc == 1, out
    assert " rc=1 " in last and last.endswith(" notify_fail=0"), last


def test_w5b_notify_fail_line_and_column(tmp_path):
    rc, out, last = _sweep(tmp_path, f'echo "SUMMARY mismatch=1 unknown=0"; echo "NOTIFY-FAIL rc=3 {REJECT}"; exit 1\n')
    assert f"NOTIFY-FAIL rc=3 {REJECT}" in out.splitlines(), out
    assert rc == 1 and " rc=1 " in last and last.endswith(" notify_fail=1"), last
