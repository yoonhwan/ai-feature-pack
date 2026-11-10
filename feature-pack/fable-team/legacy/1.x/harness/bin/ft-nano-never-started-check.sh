#!/usr/bin/env bash
# ft-nano-never-started-check.sh <좌석> --wt <워크트리> --branch <가지> [--base <sha>] [--card <카드>] [--comm <우편함 폴더>] [--agent claude|opencode] [--successor-auto --seats <명부>] [--landed-auto]
#   ft-nano-close.sh --never-started 의 «산출 0» 검사 (r506): 발주를 한 번도 처리하지 못한 나노는 회수할 산출·seq·증거 줄이 없다 — 그 대신 «한 일 0» 을 값 4개로 센다.
#     ⓐ 대화 기록 assistant 턴 0 (규칙 1 · 에이전트별) — claude(기본) = ~/.claude/projects/<워크트리 인코딩>/*.jsonl 중 좌석명(agentName/customTitle) 파일의 type=assistant(model <synthetic> 제외) 줄 수(jsonl 없음 = 0)
#        opencode = ${FT_OPENCODE_DB:-~/.local/share/opencode/opencode.db} 읽기 전용(7초 상한) · session.directory == 워크트리 실경로(또는 그 아래) ∧ time_created ≥ .worktree-info.json created_at(못 정하면 시각 조건 0)
#        인 세션의 role=assistant 메시지 수 · db 없음·잠김·스키마 다름 = 확인 못 함 · 그 밖 에이전트 = 확인 못 함
#     ⓑ base 위 커밋 0 — base = --base › 카드 `base_sha:` › <워크트리>/.worktree-info.json base_sha · `git rev-list --count <base>..<가지>`
#     ⓒ 워크트리 미커밋 0 — `git status --porcelain -uall` 중 노이즈(.worktree-info.json · next-env.d.ts · tsconfig.json · .serena/project.yml) 제외
#     ⓓ 좌석이 보낸 쪽지 0 — <우편함>/mailbox.log.jsonl(+ 회전본 .1) 의 "from": "<좌석>" 줄 수
#   --successor-auto(규칙 2·3): 같은 계보(이름 베이스 같고 #번호가 더 큼) 좌석이 ⓐtmux 생존 ⓑpane cwd toplevel == 워크트리 ⓒ명부 행 실재 ∧ _replaced_by 없음 — 셋 다 값으로 확인되면
#     `SUCCESSOR <이름>` 을 내고 ⓑⓒ(커밋·미커밋 = 후계 몫)를 건너뛴다 · 후계 0 = `SUCCESSOR none` · 못 셈(tmux·명부 조회 실패) = `SUCCESSOR unknown` → 4값 전부(추측 면제 0)
#   --landed-auto(규칙 2b · 개정 r3): 후계가 없거나 못 셀 때 — ft-landed-check.sh <리포> ${FT_NEVER_MAIN_REF:-origin/main} <가지> <카드 키> 가 rc0(ancestor·cherry·card)이면
#     `LANDED <근거>` 를 내고 ⓑ 커밋 수만 건너뛴다(ⓒ 미커밋·ⓐ 턴·ⓓ 발신은 그대로) · grep·no·판정 실패·7초 초과 = `LANDED no` → 4값 전부
#   exit 0 = `NEVER-STARTED ok turns=0 commits=… dirty=… sent=0` · 1 = `REJECT never-started: <항목> <값>` 또는 `… 확인 못 함 <항목>`(셀 수 없으면 통과 0) · 2 = usage
set -uo pipefail
USAGE="usage: $0 <좌석> --wt <워크트리> --branch <가지> [--base <sha>] [--card <카드>] [--comm <우편함 폴더>] [--agent claude|opencode] [--successor-auto --seats <명부>]"
SEAT="${1:-}"; shift 2>/dev/null || { echo "$USAGE" >&2; exit 2; }
WT=""; BR=""; BASE=""; CARD=""; COMM="${FT_INBOX_ROOT:-}"; AGENT=""; SUCC_AUTO=0; SEATS=""; LAND_AUTO=0
while [ $# -gt 0 ]; do
  [ "$1" != --successor-auto ] || { SUCC_AUTO=1; shift; continue; }
  [ "$1" != --landed-auto ] || { LAND_AUTO=1; shift; continue; }
  [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
  case "$1" in --wt) WT="$2";; --branch) BR="$2";; --base) BASE="$2";; --card) CARD="$2";; --comm) COMM="$2";; --agent) AGENT="$2";; --seats) SEATS="$2";;
    *) echo "$USAGE" >&2; exit 2;; esac; shift 2; done
[ -n "$SEAT" ] && [ -n "$WT" ] && [ -n "$BR" ] || { echo "$USAGE" >&2; exit 2; }
[ "$SUCC_AUTO" = 0 ] || [ -n "$SEATS" ] || { echo "$USAGE (--successor-auto 는 --seats 필수)" >&2; exit 2; }
WTR="$(cd "$WT" 2>/dev/null && pwd -P)" || WTR=""
bad=()
# 규칙 2·3 공유 워크트리 후계
SUCC=none
if [ "$SUCC_AUTO" = 1 ]; then
  _base="${SEAT%#*}"; _n="${SEAT##*#}"
  if [ "$_base" = "$SEAT" ] || ! [[ "$_n" =~ ^[0-9]+$ ]] || [ -z "$WTR" ] || [ ! -r "$SEATS" ]; then SUCC=unknown
  elif ! _pp="$(tmux list-panes -a -F '#{session_name}|#{pane_current_path}' 2>&1)"; then
    case "$_pp" in *"no server running"*) SUCC=none;; *) SUCC=unknown;; esac
  else
    _best=-1
    while IFS='|' read -r _s _c; do
      [[ "$_s" == "$_base#"* ]] || continue; _m="${_s##*#}"; [[ "$_m" =~ ^[0-9]+$ ]] && [ "$_m" -gt "$_n" ] && [ "$_m" -gt "$_best" ] || continue
      _top="$(git -C "$_c" rev-parse --show-toplevel 2>/dev/null)" && [ "$(cd "$_top" && pwd -P)" = "$WTR" ] || continue
      _row="$(jq -r --arg s "$_s" 'if has($s) then (if (.[$s]|type)=="object" and (.[$s]|has("_replaced_by")|not) then "ok" else "replaced" end) else "absent" end' "$SEATS" 2>/dev/null)" || { SUCC=unknown; break; }
      [ "$_row" = ok ] || continue
      _best="$_m"; SUCC="$_s"
    done <<< "$_pp"
  fi
  echo "SUCCESSOR $SUCC"
fi
# ⓐ 대화 기록
case "${AGENT:-claude}" in
  claude)
    turns="$(python3 - "$HOME/.claude/projects/$(printf '%s' "$WT" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')" "$SEAT" <<'PY'
import glob, json, os, sys
d, seat = sys.argv[1:3]; needles = ('"agentName":"%s"' % seat, '"customTitle":"%s"' % seat); n = 0
for p in glob.glob(os.path.join(d, "*.jsonl")):  # 좌석명 레코드는 파일 앞 1MB 안(ft-seat-status.sh newest_jsonl_of 와 같은 규칙)
    with open(p, encoding="utf-8", errors="replace") as fh: head = fh.read(1048576)
    if not any(x in head for x in needles): continue
    for l in open(p, encoding="utf-8", errors="replace"):
        try: r = json.loads(l)
        except ValueError: continue
        if r.get("type") == "assistant" and (r.get("message") or {}).get("model") != "<synthetic>": n += 1
print(n)
PY
)" || turns=""
    if [ -z "$turns" ]; then bad+=("확인 못 함 대화 기록(claude jsonl)"); elif [ "$turns" != 0 ]; then bad+=("대화 기록에 턴 $turns"); fi;;
  opencode)
    db="${FT_OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"; turns=""
    [ -f "$db" ] && [ -n "$WTR" ] && turns="$(python3 - "$db" "$WTR" "$WT/.worktree-info.json" "${FT_OPENCODE_DB_TIMEOUT:-7}" <<'PY'
import json, sqlite3, sys, time
db, wt, info, to = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
since = 0
try: since = int(time.mktime(time.strptime(json.load(open(info))["created_at"], "%Y-%m-%d %H:%M:%S")) * 1000)
except Exception: since = 0  # 좌석 생성 시각을 못 정하면 시각 조건 없이 전부(더 엄격)
c = sqlite3.connect("file:%s?mode=ro" % db, uri=True, timeout=to)
end = time.monotonic() + to  # 질의 시간도 같은 상한(7초 룰) — 넘으면 중단 = 확인 못 함
c.set_progress_handler(lambda: 1 if time.monotonic() > end else 0, 10000)
# 세션 먼저(작은 표) → 세션별 메시지(session_id 색인) — message 통째 join 은 실 db(5GB)에서 7.3초(r506 실측)
ids = [r[0] for r in c.execute("select id from session where (directory=? or directory like ?) and time_created >= ?", (wt, wt.rstrip("/") + "/%", since))]
print(sum(c.execute("select count(*) from message where session_id=? and json_extract(data,'$.role')='assistant'", (i,)).fetchone()[0] for i in ids))
PY
)" || turns=""
    if [ -z "$turns" ]; then bad+=("확인 못 함 opencode.db($db · 없음·잠김·스키마 다름)"); elif [ "$turns" != 0 ]; then bad+=("opencode 턴 $turns"); fi;;
  *) bad+=("확인 못 함 대화 기록(agent=$AGENT)");;
esac
# 규칙 2b 착지 가지(개정 r3) — 후계가 없고 센 커밋이 0 이 아닐 때만 · 판정 7초 상한(perl alarm) · rc0 강한 근거(ancestor·cherry·card)만
LANDED=no
landed_check() {
  local root key lc lw
  root="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  key="$(printf '%s' "$BR" | sed 's|^nano/||; s|-r[0-9][0-9]*$||')"; lc="$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-landed-check.sh"
  if [ -n "$root" ] && [ -f "$lc" ] && lw="$(perl -e 'alarm shift; exec @ARGV' 7 bash "$lc" "$root" "${FT_NEVER_MAIN_REF:-origin/main}" "refs/heads/$BR" "$key" 2>/dev/null)"; then
    case "$lw" in ancestor|cherry|card) LANDED="$lw";; esac
  fi
  echo "LANDED $LANDED"
}
commits=skip; dirty=skip
case "$SUCC" in none|unknown)
# ⓑ base 위 커밋
[ -n "$BASE" ] || [ -z "$CARD" ] || [ ! -f "$CARD" ] || BASE="$(sed -nE 's/^[-[:space:]]*base_sha:[[:space:]]*([0-9a-f]{7,40}).*/\1/p' "$CARD" | head -1)"
[ -n "$BASE" ] || BASE="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("base_sha",""))' "$WT/.worktree-info.json" 2>/dev/null)"
if [ -z "$BASE" ]; then bad+=("확인 못 함 base(--base · 카드 base_sha · .worktree-info.json base_sha 모두 없음)")
elif ! git -C "$WT" rev-parse -q --verify "$BASE^{commit}" >/dev/null || ! git -C "$WT" rev-parse -q --verify "refs/heads/$BR" >/dev/null; then bad+=("확인 못 함 커밋(base $BASE · 가지 $BR)")
else commits="$(git -C "$WT" rev-list --count "$BASE..refs/heads/$BR")" || commits=""
  [ -z "$commits" ] || [ "$commits" = 0 ] || [ "$LAND_AUTO" = 0 ] || landed_check   # 2b 는 «센 커밋이 0 이 아닐 때» 만(0 커밋 가지는 늘 ancestor — 기본 닫기 그대로)
  if [ -z "$commits" ]; then bad+=("확인 못 함 커밋(rev-list 실패)"); elif [ "$LANDED" != no ]; then commits="skip(landed $LANDED)"; elif [ "$commits" != 0 ]; then bad+=("커밋 $commits"); fi; fi
# ⓒ 미커밋 (노이즈 제외)
if st="$(git -C "$WT" status --porcelain -uall 2>/dev/null)"; then   # -uall: 새 폴더를 «dir/» 한 줄로 접지 않는다(노이즈 파일 이름 대조)
  dirty="$(printf '%s\n' "$st" | grep -vE '([ /])(\.worktree-info\.json|next-env\.d\.ts|tsconfig\.json|\.serena/project\.yml)"?$' | grep -c .)"
  [ "$dirty" = 0 ] || bad+=("미커밋 ${dirty}파일")
else bad+=("확인 못 함 미커밋(git status 실패: $WT)"); fi;;
esac
# ⓓ 보낸 쪽지
if [ -n "$COMM" ] && [ -f "$COMM/mailbox.log.jsonl" ]; then
  logs=("$COMM/mailbox.log.jsonl"); [ ! -f "$COMM/mailbox.log.jsonl.1" ] || logs+=("$COMM/mailbox.log.jsonl.1")
  sent="$(cat "${logs[@]}" | grep -cF "\"from\": \"$SEAT\"")"
  [ "$sent" = 0 ] || bad+=("보낸 쪽지 $sent")
else bad+=("확인 못 함 보낸 쪽지(우편함 기록 없음: ${COMM:-<미지정>}/mailbox.log.jsonl)"); fi
if [ "${#bad[@]}" -gt 0 ]; then printf 'REJECT never-started: %s\n' "${bad[@]}"; exit 1; fi
echo "NEVER-STARTED ok turns=0 commits=$commits dirty=$dirty sent=0"
exit 0
