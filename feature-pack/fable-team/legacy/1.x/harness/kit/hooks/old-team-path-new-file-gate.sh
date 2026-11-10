#!/bin/bash
# old-team-path-new-file-gate — PreToolUse(Write|Edit|Bash) 게이트: 팀 폴더가 design/teams/<팀>/(꼴2)로 옮겨진 팀의
#   옛 꼴1 경로 design/<팀>/… 아래 «새 파일» 을 막는다 (r402 · 판정 2294 ⓑ · 쌍둥이 후보는 «읽기 역호환» 이지 «쓰기 허가» 가 아니다).
# 판정: 출력 0 = 허용 / stdout hookSpecificOutput deny JSON(바른 경로 1줄) = 차단.
#   대상 경로: Write·Edit `file_path` · Bash `command` 의 `>`·`>>` 대상 + `cp|mv|install|tee|touch` 마지막 인자(따옴표 밖).
#   검사: 대상이 «없는 파일» 이고 · 그 경로가 속한 git 리포 루트 아래 `design/<팀>/…` 이고 · 그 루트 `design/TEAMS.md` 의 그 팀 칸이 꼴2 일 때만 deny.
#   통과: 기존 파일 편집·읽기 · 리포 밖 · 꼴1 팀 · 꼴3($FT_HARNESS_ROOT) 팀 · 명단에 없는 폴더.
#   fail-open(stderr WARN 1줄): 입력 JSON 파싱 실패 · Bash 명령 토큰화 실패 · design/<x>/ 대상인데 TEAMS.md 없음 · ft-team-lib.sh 못 찾음.
#   팀 이름 글자 0 — 칸 해석은 ft-team-lib.sh `ft_team_rel` ($FT_BIN → ~/.claude/fable-team/live/*/bin 최신 1개).
set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# 대상 절대경로 줄마다(정규화 · 상대경로는 JSON cwd 기준). 파싱 실패 = 첫 줄 «!WARN <사유>».
TARGETS=$(python3 -c 'import json,os,shlex,sys
try: d=json.loads(sys.argv[1])
except Exception: print("!WARN 입력 JSON 파싱 실패"); sys.exit(0)
tool=d.get("tool_name"); ti=d.get("tool_input") or {}; cwd=d.get("cwd") or os.getcwd()
def out(p):
    if p: print(os.path.normpath(os.path.join(cwd, os.path.expanduser(p))))
if tool in ("Write","Edit"): out(ti.get("file_path")); sys.exit(0)
if tool!="Bash": sys.exit(0)
cmd=ti.get("command") or ""
try:
    lx=shlex.shlex(cmd,posix=True,punctuation_chars=True); lx.whitespace_split=True; toks=list(lx)
except ValueError:
    print("!WARN Bash 명령 토큰화 실패"); sys.exit(0)
OPS={"&&","||",";","|","&",";;","(",")","|&"}
REDIR={">",">>","&>","&>>",">|"}
WRITERS={"cp","mv","install","tee","touch"}
seg=[]
def flush(seg):
    if seg and os.path.basename(seg[0]) in WRITERS:
        args=[a for a in seg[1:] if not a.startswith("-")]
        if args: out(args[-1])
i=0
while i<len(toks):
    t=toks[i]
    if t in OPS: flush(seg); seg=[]; i+=1; continue
    if t in REDIR:
        if i+1<len(toks) and toks[i+1] not in OPS: out(toks[i+1])
        i+=2; continue
    if t in (">&","<","<<","<<<","<&"): i+=2; continue
    if t.isdigit() and i+1<len(toks) and toks[i+1] in REDIR|{">&"}: i+=1; continue
    seg.append(t); i+=1
flush(seg)
' "$INPUT" 2>/dev/null)
[ -z "$TARGETS" ] && exit 0

warn() { echo "⚠️ [old-team-path-new-file-gate] WARN $* — 검사 생략(허용)" >&2; }
LIB=""
load_lib() {
  [ -n "$LIB" ] && return 0
  local b
  for b in "${FT_BIN:-}" $(ls -d "$HOME"/.claude/fable-team/live/*/bin 2>/dev/null | sort -V | tail -1); do
    [ -n "$b" ] && [ -f "$b/ft-team-lib.sh" ] && { LIB="$b/ft-team-lib.sh"; . "$LIB"; return 0; }
  done
  return 1
}

DENY=""
while IFS= read -r P; do
  case "$P" in '!WARN '*) warn "${P#!WARN }"; continue;; esac
  [ -e "$P" ] && continue
  ANC="$(dirname "$P")"; while [ ! -d "$ANC" ]; do ANC="$(dirname "$ANC")"; done
  ANC_REAL="$(cd "$ANC" 2>/dev/null && pwd -P)" || continue
  ROOT="$(git -C "$ANC_REAL" rev-parse --show-toplevel 2>/dev/null)" || continue
  [ -n "$ROOT" ] || continue
  P="$ANC_REAL${P#"$ANC"}"
  REL="${P#"$ROOT"/}"; [ "$REL" = "$P" ] && continue
  case "$REL" in design/*/*) ;; *) continue;; esac
  T="${REL#design/}"; T="${T%%/*}"
  [ "$T" = teams ] && continue
  [ -f "$ROOT/design/TEAMS.md" ] || { warn "팀 명단 없음: $ROOT/design/TEAMS.md ($REL)"; continue; }
  load_lib || { warn "ft-team-lib.sh 없음(\$FT_BIN · ~/.claude/fable-team/live/*/bin)"; continue; }
  CELL="$(unset FT_TEAMS_MD; FT_REPO_ROOT="$ROOT" ft_team_rel "$T" 2>/dev/null)" || continue
  [ "$CELL" = "design/teams/$T/" ] || continue
  DENY="$DENY
옛 경로 새 파일 — 바른 경로: design/teams/$T/${REL#design/"$T"/} (막은 경로 $REL · 팀 $T 폴더 칸 = $CELL · 판정 2294 ⓑ)"
done <<< "$TARGETS"

[ -z "$DENY" ] && exit 0
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"🚫 [old-team-path-new-file-gate] "+sys.argv[1]}},ensure_ascii=False))' "${DENY#?}"
exit 0
