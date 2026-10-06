#!/bin/bash
# boot-read-gate.sh — PreToolUse(Read|Bash|mcp__serena__read_file): COMM-GUIDE.md «전문» 로드 차단.
# 하네스 0.4 단위 5 (GOAL-harness-v2 축 A 「작은 시작 로드」). 설계: design/journey/DESIGN-harness-0.4-fable.md 항목 5.
# 소스: ai-feature-pack/feature-pack/fable-team/skill/templates/hooks/boot-read-gate.sh (이 파일이 정본. ~/.claude/hooks/ 는 사본).
# settings.json 등록: PreToolUse matcher "Read|Bash|mcp__serena__read_file" → "$HOME/.claude/hooks/boot-read-gate.sh" (timeout 5000).
# 실측(2026-09-23): 전문 40,749 B ≈ 20.5k 토큰이 좌석마다 첫 mbox 보고 «전»에 들어갔다(usage delta +20,553).
# 허용: COMM-GUIDE-BOOT.md · 전문은 Read(offset, limit≤200) 또는 Bash sed -n N,Mp(폭≤200) / grep.
# 차단(exit 2, stderr 가 모델에 피드백):
#   Read   file_path=…COMM-GUIDE.md 이고 (limit 없음 또는 limit>200)
#   Bash   조각(; & | 개행 분리)의 첫 단어가 cat|head|tail|less|more|bat|view|nl 이고 그 조각에 COMM-GUIDE.md
#          — 단 head/tail -n N (N≤200) 통과 · 리다이렉트(>, >>) 가 있는 «쓰기» 조각 통과
#          sed -n A,Bp 로 폭이 200줄을 넘으면 차단
#   serena read_file 같은 파일에 start_line/max_answer_chars 없음
# 판정 자체가 실패하면 exit 1(경고가 보인다) — 훅은 fail-open 이지만 «보이지 않는 ALLOW» 는 두지 않는다(#0 RULE).
# deny·error 는 ~/.claude/logs/boot-read-gate.log 에 한 줄씩(닫는 증거 보조).
# 면제 없음 — 서브에이전트(agent_id)도 막는다(읽기 차단은 워커에도 이득).
set +e
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0
LOG="$HOME/.claude/logs/boot-read-gate.log"; mkdir -p "$(dirname "$LOG")" 2>/dev/null

python3 - "$INPUT" "$LOG" <<'PYEOF'
import json, re, sys, datetime
LOG = sys.argv[2]
def log(kind, what):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s %s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), kind, what.replace("\n", " ")[:200]))
    except Exception:
        pass
try:
    d = json.loads(sys.argv[1])
    tool = d.get("tool_name") or ""
    ti = d.get("tool_input") or {}
    if not isinstance(ti, dict): raise ValueError("tool_input is not a dict: %r" % type(ti).__name__)
except Exception as e:
    print("boot-read-gate: input parse failed (ALLOW, fail-open): %s" % e, file=sys.stderr); log("error", str(e)); sys.exit(1)

FULL = re.compile(r"COMM-GUIDE\.md")          # BOOT 는 «COMM-GUIDE-BOOT.md» 라 안 걸린다
MAXL = 200
MSG = ("🚫 [boot-read-gate] COMM-GUIDE.md «전문»(40KB≈20k 토큰) 로드 차단 — GOAL-harness-v2 축 A.\n"
       "→ ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄) 를 읽고, 필요한 절만 BOOT 매핑표의 줄 범위로 Read(offset, limit≤200) 하라.\n"
       "   Bash 는 sed -n N,Mp(폭≤200) 또는 grep 만. 감지: %s")
def deny(what):
    print(MSG % what, file=sys.stderr); log("deny", "%s %s" % (tool, what)); sys.exit(2)
def toint(v):
    try: return int(v)
    except Exception: return None

if tool == "Read":
    fp = str(ti.get("file_path") or "")
    if FULL.search(fp):
        lim = toint(ti.get("limit"))
        if lim is None or lim > MAXL:
            deny("Read %s (limit=%s — 없거나 %d 초과)" % (fp, ti.get("limit"), MAXL))
elif tool == "mcp__serena__read_file":
    fp = str(ti.get("relative_path") or ti.get("file_path") or "")
    if FULL.search(fp) and not ti.get("start_line") and not ti.get("max_answer_chars"):
        deny("serena read_file %s" % fp)
elif tool == "Bash":
    cmd = str(ti.get("command") or "")
    if FULL.search(cmd):
        DUMP = ("cat", "head", "tail", "less", "more", "bat", "view", "nl")
        for seg in re.split(r"[;&|\n]+", cmd):
            s = seg.strip()
            if not FULL.search(s): continue
            if re.search(r"(^|[^<])>(>)?", s): continue          # 리다이렉트 = 쓰기 조각, 통과
            words = s.split()
            head = words[0].rsplit("/", 1)[-1] if words else ""
            if head in ("head", "tail"):
                m = re.search(r"-n\s*(\d+)|-(\d+)\b", s)
                n = toint(m.group(1) or m.group(2)) if m else None
                if n is not None and n <= MAXL: continue
                deny("Bash: %s" % s[:120])
            elif head in DUMP:
                deny("Bash: %s" % s[:120])
            elif head == "sed":
                m = re.search(r"-n\s*'?(\d+),(\d+)p", s)
                if m and toint(m.group(2)) - toint(m.group(1)) > MAXL:
                    deny("Bash sed 범위 %s–%s (%d 초과)" % (m.group(1), m.group(2), MAXL))
                if re.search(r"sed\s+(-n\s+)?''?\s", s) or (not m and not re.search(r"\d+p", s)):
                    deny("Bash: %s (sed 전문 덤프)" % s[:120])
sys.exit(0)
PYEOF
RC=$?
[ "$RC" = "2" ] && exit 2
[ "$RC" = "1" ] && exit 1
exit 0
