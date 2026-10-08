#!/bin/bash
# fable-team no-attach-to-user — 오빠께 attach 실행을 떠넘기는 문장 차단 (Stop · R30)
# 마지막 assistant 텍스트에서 인용 문맥을 «먼저» 떼어낸 뒤 남은 줄이 «오빠 실행 요청 형태» 일 때만 block.
#   1단 제외(기록만): 코드 펜스 안 · `>` 줄 · 따옴표/「」/백틱 안의 패턴 · 첫 줄이 [HIL]/감사/AUDIT/DESIGN 인 메시지 전체
#   2단 block: 남은 줄에 attach 패턴 + (`! ` 접두 또는 요청어)
#   stop_hook_active == true 면 block 0(기록만) · 기록 = $FT_ROOT/.fable-team/state/hil-falsepos.log 1줄
# FAIL-OPEN: 읽기·파싱 오류는 stderr 1줄 + exit 0.
set +e
INPUT="$(cat 2>/dev/null)"
FT_ROOT="${FT_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
LOG="$FT_ROOT/.fable-team/state/hil-falsepos.log"
read -r -d '' PY <<'PYEOF'
import json, os, re, sys
d = json.loads(os.environ.get("HOOK_INPUT") or "{}")
tp = d.get("transcript_path") or ""
active = bool(d.get("stop_hook_active"))
text = ""
try:
    with open(tp, "rb") as f:
        f.seek(0, 2); n = f.tell(); f.seek(max(0, n - 2_000_000))
        for ln in f.read().decode("utf-8", "replace").splitlines():
            try: o = json.loads(ln)
            except Exception: continue
            if o.get("type") != "assistant": continue
            t = "\n".join(c.get("text", "") for c in (o.get("message", {}).get("content") or []) if isinstance(c, dict) and c.get("type") == "text")
            if t.strip(): text = t
except Exception as e:
    print("ERR transcript 읽기 실패: %s" % e); sys.exit(0)
ATTACH = re.compile(r"tmux\s+attach|tmux\s+a\s+-t|attach-session|tmuxc\s+attach")
ASK = ("해 주세요", "하세요", "붙어 주", "접속해", "들어가 주", "실행해")
QUOTE = re.compile(r'"[^"]*"|「[^」]*」|\'[^\']*\'|`[^`]*`')
first = next((l for l in text.splitlines() if l.strip()), "")
whole_excluded = first.lstrip().startswith(("[HIL]", "감사", "AUDIT", "DESIGN"))
fence, blocked, recorded = False, [], []
for line in text.splitlines():
    if line.strip().startswith("```"): fence = not fence; continue
    if not ATTACH.search(line): continue
    if whole_excluded: recorded.append(("header", line)); continue
    if fence: recorded.append(("fence", line)); continue
    if line.lstrip().startswith(">"): recorded.append(("blockquote", line)); continue
    rest = QUOTE.sub("", line)
    if not ATTACH.search(rest): recorded.append(("quoted", line)); continue
    if rest.lstrip().startswith("! ") or any(w in rest for w in ASK): blocked.append(line)
    else: recorded.append(("mention", line))
if blocked and active:
    recorded += [("stop_hook_active", l) for l in blocked]; blocked = []
for why, l in recorded[:1]:
    print("REC %s n=%d %s" % (why, len(recorded), l.strip()[:120]))
if blocked:
    print("BLOCK 승계 창 이관은 ft-seat-handover.sh apply 로 직접 — 오빠께 attach 실행을 맡기지 않는다(R30)")
PYEOF
RESULT="$(HOOK_INPUT="$INPUT" python3 -c "$PY" 2>&1)"
while IFS= read -r l; do
  case "$l" in
    REC\ *) mkdir -p "$(dirname "$LOG")" && printf '%s no-attach-to-user %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${l#REC }" >> "$LOG";;
    BLOCK\ *) jq -cn --arg r "${l#BLOCK }" '{decision:"block",reason:$r}';;
    ERR\ *) echo "no-attach-to-user: ${l#ERR }" >&2;;
  esac
done <<<"$RESULT"
exit 0
