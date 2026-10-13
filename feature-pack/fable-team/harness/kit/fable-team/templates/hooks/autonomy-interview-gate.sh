#!/bin/bash
# fable-team autonomy-interview-gate — PreToolUse:AskUserQuestion (r-autonomy-hooks 훅① · 판정 1322 · DESIGN-autonomy-proxy-decision r3 §1·§2)
# 왜: 자율 대리 결정 모드는 «지침 문장»만으론 안 지켜진다(R106) — 인터뷰 도구 앞에서 모드를 읽어 강제한다.
#   ON  → deny. 사유 첫머리에 status 1줄 + 「인터뷰 대신 ft-proxy-decide.sh — 대리 가능이면 추천안 진행, 불가면 오빠 큐」.
#   OFF(상태 파일 없음·위변조 포함) → 첫 질문 머리(header 또는 question 첫머리)에 `[자율 OFF]` 가 있어야 통과. 없으면 deny — 오빠가 인터뷰 화면에서 상태를 늘 본다(판정 1314 ③).
#   BYZ 리포 밖(루트에 .fable-team 없음) = 그대로 allow.
# ★FAIL-OPEN(sibling 훅 관례)★: stdin 파싱 불가·ft-autonomy.sh 못 찾음/실패 = 허용 + 로그 1줄(FT_AUTONOMY_HOOK_LOG · 기본 ~/.claude/logs/autonomy-hooks.log).
# 환경: FT_ROOT(루트 고정) · FT_AUTONOMY_SH(ft-autonomy.sh 경로) · FT_AUTONOMY_STATE_DIR(ft-autonomy.sh 가 읽음). 외부 호출 0 — 로컬 git rev-parse·파일 읽기뿐.
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse AskUserQuestion 기존 인터뷰 훅 2개 뒤 등록)는 이 파일 범위 밖 — 설치 카드★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, subprocess, sys, time

LOG = os.environ.get("FT_AUTONOMY_HOOK_LOG") or os.path.expanduser("~/.claude/logs/autonomy-hooks.log")
MARKERS = ("[자율 OFF]", "[자율 ?? 위변조 → OFF]")  # ft-autonomy.sh status 가 OFF·위변조에서 내는 머리 그대로


def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" autonomy-interview-gate: {msg}\n")
    except OSError:
        pass


def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        base = cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        p = subprocess.run(["git", "-C", base, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root if root and os.path.isdir(os.path.join(root, ".fable-team")) else ""


def autonomy(root, *args):
    """ft-autonomy.sh <args> → stdout 한 줄. 못 찾거나 실패하면 None (fail-open)."""
    cands = [os.environ.get("FT_AUTONOMY_SH") or "", os.path.join(root, ".fable-team/bin/ft-autonomy.sh"), os.path.join(root, "scripts/fable-team-bin/ft-autonomy.sh")]
    sh = next((c for c in cands if c and os.path.isfile(c)), None)
    if not sh:
        note("ft-autonomy.sh 를 못 찾음 — 허용(fail-open)")
        return None
    p = subprocess.run(["bash", sh, *args], capture_output=True, text=True, timeout=5, env=dict(os.environ, FT_ROOT=root))
    if p.returncode != 0:
        note(f"ft-autonomy.sh {' '.join(args)} rc={p.returncode} — 허용(fail-open)")
        return None
    return p.stdout.strip()


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}, ensure_ascii=False))
    sys.exit(0)


try:
    data = json.loads(os.environ["INPUT"])
    if not isinstance(data, dict):
        raise ValueError("객체 아님")
    if data.get("tool_name") not in (None, "AskUserQuestion"):
        sys.exit(0)
    questions = [q for q in (data.get("tool_input") or {}).get("questions") or [] if isinstance(q, dict)]
    root = byz_root(data.get("cwd"))
    if not root or not questions:
        sys.exit(0)
    mode = autonomy(root, "mode")
    status = autonomy(root, "status") if mode else None
except (ValueError, OSError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 허용(fail-open)")
    sys.exit(0)
if mode not in ("on", "off", "tamper") or not status:
    note(f"모드를 못 읽음({mode!r}) — 허용(fail-open)")
    sys.exit(0)
if mode == "on":
    deny(f"{status} 자율 대리 결정 모드 ON — 인터뷰 대신 ft-proxy-decide.sh: 대리 가능이면 추천안으로 진행하고, 불가면 오빠 큐(AUTONOMY-QUEUE.md)에 올린다(판정 1322).")
first = questions[0]
if any(str(first.get(k) or "").lstrip().startswith(MARKERS) for k in ("header", "question")):
    sys.exit(0)
deny(f"현재 {status} — 자율 OFF/위변조 상태의 인터뷰는 질문 머리(header 또는 question 첫머리)에 ft-autonomy.sh status 출력을 붙여 다시 묻는다: `{status}` (판정 1314 ③ · 오빠가 인터뷰 화면에서 상태를 늘 본다).")
PYEOF
exit 0
