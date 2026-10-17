#!/bin/bash
# fable-team drain-before-interview — PreToolUse:AskUserQuestion (planner 좌석 전용 · 판정 423 ⑤ · 설계 §2-4)
# 왜: planner 가 인터뷰 창을 띄우면 그동안 쪽지·인박스가 쌓여도 손이 묶인다(AUDIT-r34). 인터뷰 직전에 함을 한 번 비우게 한다.
# 동작: mailbox pending>0 또는 인박스 ①~④ 미닫힘>0 이면 턴 키당 deny 1회(사유에 pending 수 · 미보고 #seq). 같은 턴 재호출 = 통과.
#   술어 재구현 0 — `ft-inbox.sh show` 의 «미닫힘» 열 · `mbox.sh peek` 의 pending= 만 읽는다. 턴 키 = 세션 id + 마지막 사용자 레코드 uuid.
# ★영구 차단 0★: 조회/저장 실패 = 통과 + state/hook-errors.log 1줄. 저장 파일 = state/inbox/deny-<세션>.json(Stop 훅 파일과 공유 0).
# 인박스 큐 파일이 없으면(팀 밖·planner 아님) 무출력 통과. 등록은 planner 좌석 settings 에만(전역 0 · master 집행).
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
if [ -z "${FT_ROOT:-}" ]; then
  COMMON="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$COMMON" ] || exit 0
  FT_ROOT="$(dirname "$COMMON")"
fi
ME="${FT_SEAT:-}"
[ -z "$ME" ] && [ -n "${TMUX_PANE:-}" ] && ME="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)"
[ -n "$ME" ] || exit 0
STATE="$FT_ROOT/.fable-team/state/inbox"
[ -f "$STATE/${ME%%#*}.jsonl" ] || exit 0
export FT_ROOT ME STATE INPUT
export FT_INBOX_SH="${FT_INBOX_SH:-${FT_BIN:-$FT_ROOT/.fable-team/bin}/ft-inbox.sh}"
export FT_MBOX_SH="${FT_MBOX_SH:-$FT_ROOT/.fable-team/comm/mbox.sh}"
python3 - <<'PYEOF'
import json, os, re, subprocess, sys, tempfile, time

STATE, ME = os.environ["STATE"], os.environ["ME"]
INBOX, MBOX = os.environ["FT_INBOX_SH"], os.environ["FT_MBOX_SH"]
LOG = os.path.join(os.path.dirname(STATE), "hook-errors.log")  # state/hook-errors.log = ft_inbox_core.HOOK_ERRORS 와 같은 파일
CAP = 40


def log(msg):
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" drain-before-interview {ME}: {msg}\n")
    except OSError:
        pass
    sys.exit(0)


def run(*cmd):
    p = subprocess.run(list(cmd), capture_output=True, text=True, timeout=30)
    if p.returncode != 0:
        raise RuntimeError(f"{os.path.basename(cmd[0])} {cmd[1]} rc={p.returncode} {p.stderr.strip()[:120]}")
    return p.stdout


def text_of(rec):
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, str):
        return c
    return "".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text") if isinstance(c, list) else ""


def last_user_uuid(path):
    uuid = None
    with open(path, encoding="utf-8") as f:
        for ln in f:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            t = text_of(r).strip()
            if r.get("type") == "user" and t and not r.get("isSidechain") and not r.get("isMeta") and not t.startswith("Stop hook feedback"):
                uuid = r.get("uuid")
    return uuid


try:
    d = json.loads(os.environ["INPUT"])
    if d.get("tool_name") != "AskUserQuestion":
        sys.exit(0)
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("session_id") or ""))
    uuid = last_user_uuid(d.get("transcript_path") or "")
    if not sid or not uuid:
        log("세션 id 또는 사용자 턴 uuid 를 못 읽음 — 통과")
    m = re.search(r"pending=(\d+)", run(MBOX, "peek", ME))
    if not m:
        raise RuntimeError("mbox peek 출력에서 pending= 을 못 읽음")
    pending = int(m.group(1))
    left = sorted({s for ln in run(INBOX, "show", ME).splitlines()
                   for mm in [re.match(r"^\[[①②③④]\] \S+ seq=\S+ 미닫힘=(\S*) ", ln)] if mm
                   for s in mm.group(1).split(",") if s}, key=int)
except Exception as e:
    log(f"{type(e).__name__} {e} — 통과")
if pending == 0 and not left:
    sys.exit(0)
key, sf = f"{sid}:{uuid}", f"{STATE}/deny-{sid}.json"
try:
    prev = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    if prev.get("turn_key") == key:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=STATE)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"turn_key": key, "denied_at": time.strftime("%Y-%m-%dT%H:%M:%S")}, f)
    os.replace(tmp, sf)
except Exception as e:
    log(f"턴 키 저장 실패 {type(e).__name__} {e} — 통과")
shown = " · ".join("#" + s for s in left[:CAP]) + (f" 외 {len(left) - CAP}건" if len(left) > CAP else "") if left else "없음"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": (
    f"[drain-before-interview] 인터뷰 전에 함을 먼저 비워라 — mailbox pending={pending} · 인박스 ①~④ 미닫힘 {len(left)}건({shown}). "
    "mbox recv 로 읽고 ft-inbox.sh mark/report(--seat <내 좌석> 또는 FT_SEAT)로 처리한 뒤 AskUserQuestion 을 다시 호출하라(이번 턴 1회뿐 — 재호출은 통과).")}}, ensure_ascii=False))
PYEOF
exit 0
