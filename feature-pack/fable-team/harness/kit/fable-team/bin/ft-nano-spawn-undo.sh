#!/usr/bin/env bash
# ft-nano-spawn-undo.sh <좌석> --owned <pane_id>:<session_created> --card <대기 카드>   롤백 모드 — ft-nano-spawn.sh 만 부른다(kill)
#                       <좌석> [--card <대기 카드>]                                      단독 모드 — 이미 생긴 고아: kill 0 · 계획 <STATE>/spawn-undo/<좌석>.sh.hil 만 생성(사람 ! 실행)
#                       <좌석> --confirm --owned <pane_id>:<created> [--card <카드>]     계획 파일이 부르는 집행(단독 모드의 사람 실행 경로 · 명부 행 삭제 포함)
#   R81 · 판정 845(롤백 kill 표준승인)·846(r2)·847(③④ 실패만 kill). exit 0 = UNDONE|PLANNED · 1 = REJECT · 2 = usage
#   조건 ⓐ~ⓗ 하나라도 아니거나 «값을 못 읽으면» REJECT(아무것도 안 함) — 워크트리·브랜치·카드는 손대지 않는다(재spawn 이 워크트리를 재사용).
set -uo pipefail
usage() { echo "usage: $0 <좌석> --owned <pane_id>:<session_created> --card <대기 카드> | <좌석> [--card <대기 카드>]" >&2; exit 2; }
rej() { echo "REJECT $*"; exit 1; }
SEAT="${1:-}"; [ -n "$SEAT" ] || usage; shift
OWNED=""; CARD=""; CONFIRM=0
while [ $# -gt 0 ]; do case "$1" in
  --owned) OWNED="${2:-}"; shift 2 2>/dev/null || usage;; --card) CARD="${2:-}"; shift 2 2>/dev/null || usage;;
  --confirm) CONFIRM=1; shift;; *) echo "unknown $1" >&2; usage;; esac; done
[ "$CONFIRM" = 0 ] || [ -n "$OWNED" ] || usage
MODE=PLAN; [ -z "$OWNED" ] || MODE=ROLL; [ "$CONFIRM" = 0 ] || MODE=EXEC
[ "$MODE" != ROLL ] || [ -n "$CARD" ] || rej "롤백 모드는 --card 가 필요하다"
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename -- "${BASH_SOURCE[0]:-$0}")"
WT0="$(git rev-parse --show-toplevel 2>/dev/null)" || rej "git 저장소 밖에서 불렸다"
ROOT="$(git -C "$WT0" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
# ① 팀 env — spawn 과 같은 규약(FT_NANO_PREFIX 가 이미 있으면 명시가 이긴다)
if [ -z "${FT_NANO_PREFIX:-}" ]; then
  _team=""; [[ "$CARD" =~ design/([a-z0-9]+)/indices/ ]] && [ "${BASH_REMATCH[1]}" != v65 ] && _team="${BASH_REMATCH[1]}"
  if [ -n "$_team" ]; then _tenv="$ROOT/.fable-team/bin-$_team/$_team-env.sh"; [ -f "$_tenv" ] || rej "팀 env 없음: $_tenv"; . "$_tenv"; fi
fi
PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"; SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"; TAG="${FT_ACTIVE_TAG:-@zc_v65_active}"
STATE="${FT_UNDO_STATE:-$ROOT/.fable-team/state}"; MBOX_DIR="${FT_MBOX_DIR:-$ROOT/.fable-team/comm}"
LEDGER="${FT_NANO_LEDGER:-$ROOT/.worktrees/v6-realtime-live/design/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md}"
[ -f "$SEATS" ] || rej "seats.json 없음: $SEATS"
# ② 카드 — --card 또는 명부 행 index 의 /진행/ → /대기/
if [ -z "$CARD" ]; then
  _idx="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1],encoding="utf-8")).get(sys.argv[2]) or {}).get("index",""))' "$SEATS" "$SEAT" 2>/dev/null)"
  for c in "$WT0/${_idx/\/진행\//\/대기\/}" "$ROOT/${_idx/\/진행\//\/대기\/}"; do [ -n "$_idx" ] && [ -f "$c" ] && { CARD="$c"; break; }; done
  [ -n "$CARD" ] || rej "카드를 못 찾았다(명부 index=${_idx:-<빈 값>}) — --card 로 대기/ 카드를 준다"
fi

pane_info() { tmux list-panes -a -F '#{session_name}|#{pane_id}|#{session_created}' 2>/dev/null | awk -F'|' -v s="$SEAT" '$1==s{print $2"|"$3; exit}'; }
IFS='|' read -r PANE_ID CREATED <<<"$(pane_info)"
[ -n "${PANE_ID:-}" ] || rej "세션이 없다: $SEAT (이미 닫힌 좌석은 ft-nano-close 경로)"
WTP="$(tmux display-message -p -t "$PANE_ID" '#{pane_current_path}' 2>/dev/null)"
[ -n "$WTP" ] && [ -d "$WTP" ] || rej "ⓔ 좌석 워크트리를 못 읽었다(pane cwd 불명)"

c_roster() {  # ⓐ 롤백 = 명부에 행 없음(등록 전) · 단독/집행 = 행 있고 role=nano
  python3 - "$SEATS" "$SEAT" "$MODE" <<'PY' || { echo "ⓐ 명부 조건 불충족($MODE) — 행 유무·role 불명 포함"; return 1; }
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2])
sys.exit(0 if (r is None if sys.argv[3] == "ROLL" else isinstance(r, dict) and r.get("role") == "nano") else 1)
PY
}
c_card() {  # ⓒ 카드가 대기/ 에 실재 · 진행/ 같은 이름 없음(이동 0 = 착수 0)
  case "$CARD" in */대기/*) ;; *) echo "ⓒ 카드가 대기/ 에 없다: $CARD"; return 1;; esac
  [ -f "$CARD" ] || { echo "ⓒ 카드 없음: $CARD"; return 1; }
  [ ! -e "${CARD/\/대기\//\/진행\/}" ] || { echo "ⓒ 진행/ 에 같은 카드가 있다(이미 이동됨)"; return 1; }
}
c_mail() {  # ⓓ 쪽지 이력 0건 — 소비되면 지워지는 mailbox.jsonl 이 아니라 append 기록(log + 회전본 .1) 포함. 기록 파일 없음 = 불명
  [ -f "$MBOX_DIR/mailbox.log.jsonl" ] || { echo "ⓓ 쪽지 기록 파일 없음(불명): $MBOX_DIR/mailbox.log.jsonl"; return 1; }
  local n; n="$(python3 - "$SEAT" "$MBOX_DIR" <<'PY'
import json, os, sys
seat, d = sys.argv[1:3]; n = 0
for f in ("mailbox.jsonl", "mailbox.log.jsonl", "mailbox.log.jsonl.1"):
    p = os.path.join(d, f)
    if not os.path.exists(p): continue
    for ln in open(p, encoding="utf-8", errors="replace"):
        try: r = json.loads(ln)
        except ValueError: continue
        if r.get("to") == seat or r.get("from") == seat: n += 1
print(n)
PY
)" || { echo "ⓓ 쪽지 기록 읽기 실패(불명)"; return 1; }
  [ "$n" = 0 ] || { echo "ⓓ 쪽지 이력 ${n}건"; return 1; }
}
c_branch() {  # ⓔ 좌석 브랜치가 base 이후 커밋 0
  local br bs
  br="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("branch",""))' "$WTP/.worktree-info.json" 2>/dev/null)"
  bs="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("base_sha",""))' "$WTP/.worktree-info.json" 2>/dev/null)"
  [ -n "$br" ] && [ -n "$bs" ] || { echo "ⓔ .worktree-info.json 의 branch·base_sha 불명"; return 1; }
  local n; n="$(git -C "$WTP" rev-list --count "$bs..$br" 2>/dev/null)" || { echo "ⓔ rev-list 실패(불명)"; return 1; }
  [ "$n" = 0 ] || { echo "ⓔ 브랜치 $br 커밋 ${n}개(착수 흔적)"; return 1; }
}
c_dirty() {  # ⓕ 미커밋 실작업 0 — .serena/project.yml·.worktree-info.json 만 허용
  local out n; out="$(git -C "$WTP" status --porcelain 2>/dev/null)" || { echo "ⓕ git status 실패(불명)"; return 1; }
  n="$(printf '%s\n' "$out" | sed -E 's/^.{3}//' | grep -vE '^(\.serena/project\.yml|\.worktree-info\.json)?$' | wc -l | tr -d ' ')"
  [ "$n" = 0 ] || { echo "ⓕ 미커밋 실작업 ${n}줄"; return 1; }
}
user_turns() {  # 세션 jsonl(~/.claude/projects/<cwd 인코딩>) 중 좌석명이 박힌 최신 파일의 «사용자 입력» 레코드 수 · 파일 없음 = NONE
  SEAT="$SEAT" CWD="$WTP" python3 - <<'PY'
import glob, json, os, re
seat = os.environ["SEAT"].encode(); d = os.path.expanduser("~/.claude/projects/" + re.sub(r"[^A-Za-z0-9]", "-", os.environ["CWD"]))
needles = (b'"agentName":"' + seat + b'"', b'"customTitle":"' + seat + b'"'); best = (0, "")
for p in glob.glob(os.path.join(d, "*.jsonl")):
    try: head = open(p, "rb").read(1 << 20)
    except OSError: continue
    if any(n in head for n in needles) and os.stat(p).st_mtime >= best[0]: best = (os.stat(p).st_mtime, p)
if not best[1]: print("NONE"); raise SystemExit
n = 0
for ln in open(best[1], encoding="utf-8", errors="replace"):
    try: r = json.loads(ln)
    except ValueError: continue
    if r.get("type") != "user" or r.get("isMeta"): continue
    c = (r.get("message") or {}).get("content")
    if isinstance(c, str) or (isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "text" for b in c)): n += 1
print(n)
PY
}
c_turns() {  # ⓖ 사용자 턴 0 — jsonl 없음 = 불명(REJECT) · 단 롤백 모드가 ⓗ 를 통과하고 생성 120초 이내면 «턴 0»
  local n; n="$(user_turns)" || { echo "ⓖ jsonl 읽기 실패(불명)"; return 1; }
  if [ "$n" = NONE ]; then
    [ "$MODE" = ROLL ] && [ $(( $(date +%s) - CREATED )) -le 120 ] && return 0
    echo "ⓖ jsonl 없음 — 사용자 턴 불명"; return 1
  fi
  [ "$n" = 0 ] || { echo "ⓖ 사용자 턴 ${n}회"; return 1; }
}
c_owned() {  # ⓗ 지금 그 이름 세션의 pane_id·session_created 가 인자 값과 둘 다 같다(호출자 주장만으로 면제 0)
  [ "$PANE_ID:$CREATED" = "$OWNED" ] || { echo "ⓗ 소유권 불일치: 지금 $PANE_ID:$CREATED ≠ 인자 $OWNED"; return 1; }
}
gate() {  # $1=full|dyn — 첫 실패 사유를 REJECT 로 낸다
  local r
  if [ -n "$OWNED" ]; then r="$(c_owned)" || rej "$r"; fi
  r="$(c_roster)" || rej "$r"; r="$(c_mail)" || rej "$r"; r="$(c_turns)" || rej "$r"
  [ "$1" = dyn ] && return 0
  [[ "$SEAT" == "$PREFIX"* ]] || rej "ⓑ 좌석명이 접두 $PREFIX 로 시작하지 않는다"
  r="$(c_card)" || rej "$r"; r="$(c_branch)" || rej "$r"; r="$(c_dirty)" || rej "$r"
}

LOCK="$STATE/spawn-undo/$SEAT.lock"; mkdir -p "$STATE/spawn-undo" || rej "상태 폴더를 못 만들었다: $STATE/spawn-undo"
mkdir "$LOCK" 2>/dev/null || rej "락 선점 중: $LOCK (같은 좌석을 다른 실행이 정리 중)"
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
gate full
if [ "$MODE" = PLAN ]; then   # 단독 모드 — kill 0 · 계획만. 실행 시점에 ⓓ·ⓖ·pane_id/session_created 를 다시 검사한다(--confirm)
  PLAN="$STATE/spawn-undo/$SEAT.sh.hil"
  printf '#!/usr/bin/env bash\n# R81 단독 모드 계획 — 사람 ! 실행. 실행 시점에 소유권(%s)·쪽지·사용자 턴을 다시 검사한다.\nFT_NANO_PREFIX=%q FT_SEATS_JSON=%q FT_ACTIVE_TAG=%q FT_NANO_LEDGER=%q FT_UNDO_STATE=%q FT_MBOX_DIR=%q bash %q %q --confirm --owned %q --card %q\n' \
    "$PANE_ID:$CREATED" "$PREFIX" "$SEATS" "$TAG" "$LEDGER" "$STATE" "$MBOX_DIR" "$SELF" "$SEAT" "$PANE_ID:$CREATED" "$CARD" > "$PLAN" || rej "계획 파일을 못 썼다: $PLAN"
  echo "PLANNED $SEAT $PLAN"; exit 0
fi
# 롤백·집행: 태그 해제 → «kill 직전» 재검사(ⓗⓐⓓⓖ) → kill → (집행이면 명부 행 삭제) → 원장 1행
tmux set-option -t "$PANE_ID" -u "$TAG" 2>/dev/null || rej "태그 해제 실패 — kill 0"
restore() { tmux set-option -t "$PANE_ID" "$TAG" 1 2>/dev/null; }
r="$( gate dyn )" || { restore; echo "$r"; exit 1; }
tmux kill-session -t "$PANE_ID" 2>/dev/null || { restore; rej "kill-session 실패"; }
if [ "$MODE" = EXEC ]; then
  python3 - "$SEATS" "$SEAT" <<'PY' || echo "WARN 명부 행 삭제 실패 — 손으로 지울 것: $SEAT"
import collections, json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d.pop(sys.argv[2], None); json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
fi
printf -- '- **[%s KST, `date` 실측] `%s` 롤백(spawn-undo %s)**: 세션 kill · 명부·카드·워크트리·브랜치 보존 · 카드 %s\n' "$(date '+%Y-%m-%d %H:%M')" "$SEAT" "$MODE" "$CARD" >> "$LEDGER" 2>/dev/null \
  || echo "WARN 원장에 못 썼다: $LEDGER"
echo "UNDONE $SEAT"
