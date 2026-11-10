"""key_change_judge — PreToolUse(Bash) 키 변경 판정기 (R277 · 판정기 = key-change-gate.sh 의 두뇌).

진짜 키 변경 명령(gcloud api-keys·secrets versions·secrets delete·Cloud Run 키 env)만 걸러 byz-keys 장부의 «사용처 표»를 본다.
변경 = 사용처 칸이 미조사 아님 ∧ 표 파일 있음 ∧ 칸 sha12 == 표 마커 사이 sha ∧ 표 7일 이내. 삭제·비활성 = 위 + 전환 확인 줄(24시간 이내).
글자로만 든 명령(echo·git commit -m·heredoc·주석)은 ft_secret_lex 의 토큰 분석으로 거른다. 값(= 오른쪽)은 사유·로그에 쓰지 않는다.
rc: 0 판정 완료(deny 는 --hook 이 JSON 출력) · 1 CLI 모드 deny · 2 내부 오류(호출자가 글자 검사로 후퇴).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from key_change_cmd import commands, gcloud_hits
    from key_change_ledger import Unreadable, by_env, by_identity, by_secret, ledger_rows, now, verify
except ImportError as e:
    print("key_change_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
    sys.exit(2)

LOG = os.environ.get("KEY_GATE_LOG", os.path.expanduser("~/.claude/state/key-change-gate.log"))


def decide(cls: str, kind: str, idents: list[str]) -> tuple[str, str]:
    """→ (이름 표지, 사유 '' = 통과). 값 0 — 이름·ENV 만."""
    rows = ledger_rows()
    if kind == "run":
        if "*" in idents:
            return "run:*", "Cloud Run 비밀 참조 전체 제거는 사용처를 판정할 수 없음"
        cand = [r for n in idents for r in by_env(rows, n)]
        if not cand:
            return "run:-", ""  # 장부에 없는 이름만 바꾸는 update — 키가 아니다
    else:
        cand = (by_secret(rows, idents[0]) if idents else []) if kind == "secret" else by_identity(rows, idents)
        if not cand:
            return kind + ":" + (idents[0] if idents else "-"), f"장부에 없는 키(사용처 모름) — {kind} {idents[0] if idents else '이름 없음'}"
    label = ",".join(sorted({r[0].split(",")[0].strip() for r in cand}))
    for r in cand:
        why = verify(r, cls == "삭제")
        if why:
            return label, why
    return label, ""


def seat() -> str:
    if os.environ.get("KEY_GATE_SEAT"):
        return os.environ["KEY_GATE_SEAT"]
    try:
        return subprocess.run(["tmux", "display-message", "-p", "#S"], capture_output=True, text=True, timeout=2).stdout.strip() or "-"
    except (OSError, subprocess.SubprocessError):
        return "-"


def log(cls: str, kind: str, label: str, result: str) -> None:
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write("%s %s %s/%s %s %s\n" % (now().strftime("%F %T"), seat(), cls, kind, label, result))
    except OSError:
        pass


def judge(cmd: str) -> tuple[str, str]:
    if "gcloud" not in cmd:
        return "ok", ""
    for args in commands(cmd):
        if os.path.basename(args[0]) != "gcloud":
            continue
        for cls, kind, idents in gcloud_hits(args):
            try:
                label, why = decide(cls, kind, idents)
            except Unreadable:
                label, why = "-", "장부·사용처 표를 못 읽음(#0 RULE — 못 읽으면 막는다)"
            if label != "run:-":
                log(cls, kind, label, "deny" if why else "allow")
            if why:
                return "deny", why
    return "ok", ""


GUIDE = (" · `bash .claude/skills/byz-keys/scripts/keys-usage.sh <ENV> --use <kebab>` 로 사용처 표를 만든 뒤 다시"
         " (삭제·비활성은 표의 «전환 확인» 줄 뒤) · 규칙 .claude/rules/key-change.md · 오빠가 `!` 로 직접 치는 명령은 이 훅 밖")


def main(argv: list[str]) -> int:
    if argv[:1] == ["--hook"]:
        verdict, why = judge(json.load(sys.stdin)["tool_input"]["command"])
        if verdict == "deny":
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                     "permissionDecisionReason": "REJECT 키 변경 게이트 — " + why + GUIDE}}, ensure_ascii=False))
        return 0
    if len(argv) != 1:
        print("usage: key_change_judge.py '<명령>' | - | --hook", file=sys.stderr)
        return 2
    verdict, why = judge(sys.stdin.read() if argv[0] == "-" else argv[0])
    print("ok" if verdict == "ok" else "deny " + why)
    return 0 if verdict == "ok" else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # 내부 오류는 deny(rc1)와 섞이지 않게 rc2 — 호출자가 글자 검사로 후퇴
        print("key_change_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
        sys.exit(2)
