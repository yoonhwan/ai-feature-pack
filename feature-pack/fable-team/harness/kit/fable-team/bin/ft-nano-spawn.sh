#!/usr/bin/env bash
# ft-nano-spawn.sh <indices/대기/X.md> [--agent claude|codex|cmd|opencode|pi] [--model ID] [--effort E] [--raise "<사유>"] [--from <발주좌석>] [--recheck <판정문>] [--base <ref>] [--cherry-override "<사유>"] [--research] [--dry-run]
#   --research = 리서치 나노(판정 2282 · R387 · 설계 §3·§7) — «진행/ 부모 카드»(DA 보류가 쌓인 카드)를 옮기지 않고 같은 카드에 읽기 전용 조사 좌석을 연다: 좌석 이름 꼬리 `-research` · 발주 본문에 고정 문단(산출 = RESEARCH 파일 1개 · 코드 0) · 카드에 `- 리서치: <좌석> base=<sha> 허용=…` · opencode 는 ft-opencode-reap.sh(r286) 없으면 REJECT
#   --raise "<사유>" = 상향 모델(claude-fable-*·*astra* · 판정 1641)을 열 때 필수 · 명부 행에 raised{reason,card,by,at,close_on} 를 남긴다(R149)
#   Seatbelt 0.3 · 나노 좌석을 «손타이핑 없이» 연다 (SEATBELT-README §3 열기).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인) · 7 = 나노 상한·프록시 진짜 장애(r669) — 좌석 0 · 순번 큐(QUEUED · r-teamset-standard/r666/r669)
# 한 번에: ①lint ②워크트리+.venv/.env·clients/web/node_modules 심링크+.worktree-info.json ③tmuxc open(--agent/--model 통과, 기본 claude/sonnet-5.5 — r286)
#          ④remain-on-exit on + @zc_v65_active=1 ⑤seats.json 등록 ⑥인덱스 대기→진행 ⑦첫 발주(인덱스 경로 한 줄, mbox) ⑧도달 확인(jsonl)
# ★팩 ft-tmux-spawn.sh 미사용★: install.json canonical·CAPABILITY_GAP 게이트가 v65 워크트리에 없다(troubleshoot 09-06 「install.json 부재 = exit 4」) · 오빠 §0-A 「tmuxc 로 생성해서 어차피 쓰니 모델까지 지정가능」 — tmuxc 직접 호출.
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec
IDX="${1:-}"; shift || { echo "usage: $0 <indices/대기/X.md> [--agent claude|codex|cmd|opencode|pi] [--model M] [--effort E] [--raise \"<사유>\"] [--from SEAT] [--base REF] [--cherry-override \"<사유>\"] [--dry-run]" >&2; exit 2; }
AGENT="claude"; AGENT_SET=0; MODEL=""; EFFORT="high"; EFFORT_SET=0; FROM="${FT_SEND_FROM:-}"; FROM_SET=0; RESEARCH=0; DRY=0; FAST=""; TIER=""; RECHECK=""; BASE_REF=""; HAVE_CO=0; CO=""; RAISE=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; AGENT_SET=1; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; EFFORT_SET=1; shift 2;; --raise) RAISE="${2:-}"; shift 2 2>/dev/null || shift;;
  --from) FROM="$2"; FROM_SET=1; shift 2;; --recheck) RECHECK="$2"; shift 2;; --dry-run) DRY=1; shift;; --research) RESEARCH=1; shift;; --tier) TIER="$2"; shift 2;; --base) BASE_REF="$2"; shift 2;;
  --cherry-override) HAVE_CO=1; CO="${2:-}"; shift 2 2>/dev/null || shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
CO_ARGS=(); [ "$HAVE_CO" -eq 0 ] || { [ -n "${CO//[[:space:]]/}" ] || { echo "usage: --cherry-override \"<사유>\" — 사유가 비었다(사유 없는 우회 거부)" >&2; exit 2; }; CO_ARGS=(--override "$CO"); }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ★spawn 정지 파일 (R320 · 판정 2166)★: 정지는 기한·해제 조건이 있는 SPAWN_HOLD 파일 하나로만 걸린다 — 문장·쪽지로 받은 정지는 효력 0. 출력 `hold=none` = 정지 아님. 없는 도구는 설치 누락(라이브 드리프트 검사가 잡는다).
if [ -f "$HERE/ft-spawn-hold.sh" ]; then
  _hold="$(bash "$HERE/ft-spawn-hold.sh" status 2>&1)"; _hrc=$?
  [ "$_hrc" = 0 ] || { printf '%s\n' "$_hold"; exit "$_hrc"; }
  printf '%s\n' "$_hold"
fi
# ★자원 게이트 (Res-1014 · r921 개정)★: 넘으면 «회수 먼저 → 다시 재고 → 그래도 넘으면 WARN 1줄 + 진행» — 멈추는 것은 문지기의 REJECT(디스크 하드 하한·디스크 측정 실패)뿐이다(오빠 2026-10-25 «컴퓨터가 죽어도 개발은 해야지»). 우회 플래그 없음 — 조정은 env 문턱만.
[ -f "$HERE/ft-resource-gate.sh" ] || { echo "REJECT ft-resource-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
# ★W3(DA⑥ r1)★ 회수 호출은 «7초 상한» 안에서만 — 넘으면 `WARN 회수 시간 초과 — 진행` 1줄 남기고 그대로 간다(spawn 이 회수에 묶여 멈추지 않는다).
[ -f "$HERE/ft-reclaim-capped.sh" ] || { echo "REJECT ft-reclaim-capped.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
. "$HERE/ft-reclaim-capped.sh"
RG_ARGS=(check); [ "$RESEARCH" = 1 ] && RG_ARGS+=(--research)
_rgout="$(bash "$HERE/ft-resource-gate.sh" "${RG_ARGS[@]}" 2>&1)"; _rgrc=$?
# R198(판정 1767) + r921: 넘었으면(WARN) — 기존 표준승인 범위 안의 유휴·완료 좌석을 자동 정리한 뒤 문지기 재검(FT_RECLAIM=0 으로 끔). 좌석을 닫아 풀릴 수 있는 축(agents·swap·memfree·level·rate)일 때만 부른다.
#   W3: WARN 줄의 «모든» 항목을 본다(«;» 로 이어 붙인 여러 축) — 하나라도 좌석을 닫아 풀리는 축이면 회수 1회(7초 상한 · 넘으면 WARN 1줄 + 진행)
_WARN_AXES="$(printf '%s\n' "$_rgout" | sed -n 's/^WARN resource //p' | tr ';' '\n')"
if [ "$_rgrc" = 0 ] && [ -n "$_WARN_AXES" ] && printf '%s\n' "$_WARN_AXES" | grep -Eq '(agents|swap|memfree|level)=[0-9]|rate=-?[0-9]'; then
  if [ "${FT_RECLAIM:-1}" != 0 ] && [ -f "$HERE/ft-resource-reclaim.sh" ]; then
    _rl_out="$(mktemp "${TMPDIR:-/tmp}/ft-r921-reclaim.XXXXXX")"
    ft_reclaim_capped "$_rl_out" bash "$HERE/ft-resource-reclaim.sh" --on-reject "$_rgout" --gate "$HERE/ft-resource-gate.sh"; _rlrc=$?
    sed -n '1,40p' "$_rl_out" >&2; rm -f "$_rl_out"
    [ "$_rlrc" != 124 ] || echo "WARN 회수 시간 초과(${FT_RECLAIM_TIMEOUT_SEC:-7}초) — 진행" >&2
    _rgout="$(bash "$HERE/ft-resource-gate.sh" "${RG_ARGS[@]}" 2>&1)"; _rgrc=$?
  fi
fi
[ "$_rgrc" = 0 ] || { printf '%s\n' "$_rgout"; exit "$_rgrc"; }
printf '%s\n' "$_rgout" | grep '^WARN ' >&2 || true   # r672: 넘은 채 진행한다는 사실(WARN)을 숨기지 않는다 · r921: 진행은 한다
# ★r921 리서치 좌석 상한 삭제★: 리서치는 일반 나노와 같은 규칙으로 열린다(옛 r672 «1석 고정» 은 오빠 «멈추지 마라» 로 폐기). 잠금만 아래 ③ 열기 직전에 잡는다.
[ -f "$HERE/ft-research-seat-lib.sh" ] || { echo "REJECT ft-research-seat-lib.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
. "$HERE/ft-research-seat-lib.sh"
RESEARCH_LOCK=""
WT="$(git rev-parse --show-toplevel)"                       # 호출 워크트리(기준 브랜치의 자리)
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
# ★r975 회신 대상 = --from > env FT_SEND_FROM(명부 현역으로 해석) > 그 팀 명부의 현역 `_master`★ — 아래 세 줄이 그 순서다(1번째는 r730 가드, 2·3번째가 r975 ).
# (r975 r4: 보고 대상은 «살아 있는 좌석 목록»(tmm ls) 에서 고른다 — 명부 파일 해석 0 · 아래 _nano_reply_target 한 칸)
# ★페널티 게이트 (R320b · 오빠 판정 2170)★: 전 세션 정지(PENALTY_STOP 파일) 중이면 재개 전 팀은 열지 않는다(부작용 전 · successor 는 대상 아님). 우회 플래그 없음 — 풀기는 ft-penalty.sh resume <팀>. 파일이 있는데 판정기가 없으면 REJECT(조용한 통과 0).
if [ -f "$ROOT/.fable-team/state/PENALTY_STOP" ]; then
  [ -f "$HERE/ft-penalty.sh" ] || { echo "REJECT 전 세션 정지 중인데 ft-penalty.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _ptm=""; [[ "$IDX" =~ design/(teams/)?([a-z0-9]+)/indices/ ]] && _ptm="${BASH_REMATCH[2]}"   # R382: design/teams/<팀>/ 꼴도 팀 이름으로 읽는다
  _pout="$(FT_ROOT="$ROOT" bash "$HERE/ft-penalty.sh" check "$_ptm" 2>&1)"; _prc=$?
  [ "$_prc" != 0 ] && { printf '%s\n' "$_pout"; exit "$_prc"; }
fi
# ★전팀 정지 게이트 (r626)★: 늘 check — 판정(상태 파일·원장 all-stop.log·상태 폴더)은 ft_all_stop.py 하나 · «파일 없음 = 꺼짐» 가정 0(DA⑥ r2) · 정지면 끄기 전 spawn 0(팀 구분·우회 플래그 없음 · 부작용 전) · 판정기가 없으면 그 오류로 REJECT(조용한 통과 0).
[ -e "$ROOT/.fable-team" ] && { _aout="$(FT_ROOT="$ROOT" bash "$HERE/ft-all-stop.sh" check 2>&1)" || { printf '%s\n' "$_aout"; exit 1; }; }
# ★팀 env 자동 로드 (카드 nano-spawn-close-team-env §1)★: FT_NANO_PREFIX 가 이미 있으면 «명시가 이긴다» — 아무것도 안 한다.
#   없으면 카드 경로 design/<팀>/indices/ 의 팀(v65 포함)으로 $ROOT/.fable-team/bin-<팀>/<팀>-env.sh 를 source. ★v65 도 예외 없이 읽다(r655)★ — 파일이 없는 다른 팀은 지금처럼 REJECT, v65 는 파일이 없으면 기본값(아래 공용 규칙 = byz-v65-nano-)으로 간다.
# ★r975 r2(DA② ③)★ 팀 추출은 «정귀식» 이 아니라 마지막 조각 잘라내기 — 폴더 이름에 공백·한글이 들어가도 팀 env 를 읽는다(옛 `[a-z0-9]+` 정규식은 그 꼴을 v65 로 밀어 버렸다).
_nano_team() { local t="${FT_TEAM:-}" seg; [ -n "$t" ] || { case "$IDX" in */indices/*) seg="${IDX%/indices/*}"; t="${seg##*/}" ;; esac; }; printf '%s\n' "${t:-v65}"; }
[ -f "$HERE/ft_teamset.py" ] || { echo "REJECT ft_teamset.py·ft_spawn_queue.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }   # r689: 이름 규칙 읽기 «전» 존재·안내 검사(:102 와 같은 글자) — 있는데 못 읽으면 아래 문구
DEF_NANO_PREFIX="$(python3 "$HERE/ft_teamset.py" prefix --team v65 2>/dev/null)"
[ -n "$DEF_NANO_PREFIX" ] || { echo "REJECT 나노 이름 규칙(ft_teamset.py prefix --team v65) 못 읽음: $HERE"; exit 1; }
if [ -z "${FT_NANO_PREFIX:-}" ]; then
  _team="$(_nano_team)"
  if [ -n "$_team" ] && [ "$_team" != v65 ]; then
    _tenv="$ROOT/.fable-team/bin-$_team/$_team-env.sh"
    [ -f "$_tenv" ] || { echo "REJECT 팀 env 없음: $_tenv"; exit 1; }
    . "$_tenv"
  else
    _tenv="$ROOT/.fable-team/bin-v65/v65-env.sh"   # 있으면 읽는다(팀별 설정) — 없으면 기본값
    [ -f "$_tenv" ] && . "$_tenv"
  fi
  echo "ENV team=${_team:-v65} prefix=${FT_NANO_PREFIX:-$DEF_NANO_PREFIX} seats=${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
fi
# ★r975 r4 (오빠 결정 3 · 10-27 09:3x «tmuxc tmm 에서 현팀 리스트 보고 판단»)· 보고 대상은 «지금 살아 있는 좌석 목록» 에서 고른다★
#   명부 파일(seats.json · 팀 env · FT_SEATS_JSON) 해석은 «하지 않는다» — 그 입력이 답을 바꿀 수 있으면 그 자체가 결함이다(r1~r3 반례 전부).
#   순서(r8): tmm ls byz-<팀> 1회 + 후보마다 ft-name-lint 1회(«같은 7초 상한 하나» · rc≠0/초과 = REJECT 1줄) → PASS 만 «이 팀 좌석» → --from > FT_SEND_FROM > 기본 = master 현역 1명(0·2명+ = REJECT).
#   «이 팀 좌석인가» 판정 사본 0 — 역할 목록·정규식은 검사기(ft-name-lint) 한 곳(오빠 결정 6 = 4번).
#   목록 0 · 2명 이상 · rc≠0 · 빈 출력 · 7초 초과 = REJECT 1줄 rc≠0 · 개설 0 (조용한 루트 팀장·옛 이름 대체 0).
_nano_team() { local t="${FT_TEAM:-}" seg; [ -n "$t" ] || { case "$IDX" in */indices/*) seg="${IDX%/indices/*}"; t="${seg##*/}" ;; esac; }; printf '%s\n' "${t:-v65}"; }
_nano_reply_target() {  # rc0 = stdout 보고 대상 1줄 · rc1 = stdout REJECT 1줄(부작용 0 — 워크트리·tmux·명부 등록 전부 앞)
  local team tmp rc
  team="$(_nano_team)"
  command -v tmm >/dev/null 2>&1 || { echo "REJECT 보고 대상을 못 풀었다 — tmm 이 PATH 에 없다(tmuxc tmm ls)"; return 1; }
  [ -f "$HERE/ft-name-lint.sh" ] || { echo "REJECT 보고 대상을 못 풀었다 — ft-name-lint.sh 없음: $HERE"; return 1; }
  tmp="$(mktemp "${TMPDIR:-/tmp}/ft-r975-tmm.XXXXXX")" || { echo "REJECT 보고 대상을 못 풀었다 — 임시 파일 실패"; return 1; }
  # ★외부 호출 = «한 함수 한 상한»(r8 ② · 하드 룰 12/20)★ — `tmm ls` 1회 + 후보 이름마다 `ft-name-lint` 1회를
  #   «같은 7초 상한» 안에서 돈다. rc≠0 또는 초과 = REJECT 1줄 · 개설 0(호출마다 7초가 아니다).
  #   «이 팀 좌석인가» 판정은 검사기에 통째로 맡긴다 — spawn 안에 역할 목록·정규식 사본을 두지 않는다(결정 6 = 4번).
  COLUMNS=400 ft_reclaim_capped "$tmp" bash -c '
    T="$1"; L="$2"
    list="$(tmm ls "$T" 2>/dev/null)" || exit 3
    printf "%s\n" "$list" | tr -s " " "\n" | grep -E "^${T}-" | grep -v "…" | sort -u | while IFS= read -r n; do
      case "$n" in *"#"*) ;; *) continue;; esac
      bash "$L" "$n" >/dev/null 2>&1 && printf "%s\n" "$n"
    done
    exit 0
  ' _ "byz-$team" "$HERE/ft-name-lint.sh"; rc=$?
  if [ "$rc" = 124 ]; then rm -f "$tmp"
    echo "REJECT 보고 대상을 못 풀었다 — 좌석 목록·이름 검사 7초 초과(tmm ls + ft-name-lint) · 개설 0"; return 1; fi
  if [ "$rc" != 0 ]; then rm -f "$tmp"
    echo "REJECT 보고 대상을 못 풀었다 — ft-name-lint/tmm 호출 rc=$rc (좌석 목록·이름 검사) · 개설 0"; return 1; fi
  [ -s "$tmp" ] || { rm -f "$tmp"; echo "REJECT 보고 대상을 못 풀었다 — 이름 검사를 지난 좌석이 0명(tmm ls byz-$team · ft-name-lint PASS 0) · 개설 0"; return 1; }
  python3 - "$team" "$FROM_SET" "$FROM" "${FT_SEND_FROM:-}" "$tmp" <<'PY'
import re, sys
team, from_set, arg, env_from, path = sys.argv[1:6]
names = [ln.strip() for ln in open(path, encoding="utf-8", errors="replace") if ln.strip()]
mpat = re.compile(r"^byz-" + re.escape(team) + r"-master-[^#\s]+#([0-9]+)$")   # 기본 선택 = «그 팀 master» (이름 규칙은 검사기가 이미 통과시킨 것)
masters = sorted((int(m.group(1)), n) for n in names for m in [mpat.match(n)] if m)
def reject(msg):
    print("REJECT 보고 대상을 못 풀었다 — " + msg); sys.exit(1)
def note(s):
    sys.stderr.write("INFO " + s + "\n")
state = ("1명(%s)" % masters[0][1]) if len(masters) == 1 else ("0명" if not masters else "%d명" % len(masters))
want, src = ("", "")
if from_set == "1":
    want, src = arg.strip(), "--from"
    if not want:
        reject("--from 값이 비었다")
elif env_from.strip():
    want, src = env_from.strip(), "FT_SEND_FROM"
if want:
    if want not in names:
        reject("%s 가 이 팀(byz-%s) 좌석 집합에 없다(ft-name-lint PASS 0): %s (집합: %s)"
               % (src, team, want, " ".join(names) or "0명"))
    if len(masters) != 1:
        note("%s 로 확정 = %s (팀장 %s — 명시가 기본 선택을 대신한다 · 계약 ③)" % (src, want, state))
    print(want); sys.exit(0)
if not masters:
    reject("이 팀(byz-%s) master 좌석이 집합에 없다 (집합: %s)" % (team, " ".join(names) or "0명"))
if len(masters) > 1:
    reject("현역 master 가 %d명이다(하나여야 한다): %s" % (len(masters), " ".join(n for _, n in masters)))
print(masters[0][1])
PY
  local prc=$?; rm -f "$tmp"; return "$prc"
}
# ①-0 보고 대상 = lint 첫 칸 (dry-run·실행 같은 칸 · 워크트리·tmux·명부 등록 전부 앞)
_nano_rt="$(_nano_reply_target)"; _nano_rtrc=$?
[ "$_nano_rtrc" = 0 ] || { printf '%s\n' "$_nano_rt"; exit 1; }
FROM="$_nano_rt"
echo "INFO 회신 대상 = $FROM (발주문 머리 [$FROM-><나노>] · 출처: 살아 있는 좌석 목록 tmm ls byz-$(_nano_team))" >&2
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"   # ⑤명부 «등록» 대상 전용 — 보고 대상 해석에는 쓰지 않는다(tmm 목록이 정한다)
# ★v65 기본 접두 = 공용 규칙(ft_teamset.py)★ — 이름 규칙을 스크립트마다 복사하지 않는다(두 벌 규칙 0). 규칙을 못 읽으면 추측 없이 REJECT.
[ -n "${FT_NANO_PREFIX:-}" ] || FT_NANO_PREFIX="$DEF_NANO_PREFIX"
# ★EXIT 정리 목록 (r921 r3 · DA⑥ r2 W4)★: trap 을 «덮어쓰지» 않는다 — 정리 함수를 _ON_EXIT 에 이어 붙이고 trap 은 _on_exit 하나만 건다(잠금 해제·사건 원장 abort 가 둘 다 돈다).
_ON_EXIT=()
_on_exit() { local f; for f in ${_ON_EXIT[@]+"${_ON_EXIT[@]}"}; do "$f" || true; done; }
trap _on_exit EXIT
# ★좌석 상한 (R252 · 판정 1949 · ★r921 r3 = DA⑥ r2 W1★)★: 팀 env 에 FT_TEAM_SEAT_CAP·FT_GROUP_SEAT_CAP 가 있는 팀(위성)만 — 부작용 0 지점(워크트리·세션·명부 «전»)에서 센다. env 가 없는 팀은 검사 0.
#   팀셋 상한과 같은 W4 규칙: 판정기 REJECT(live >= cap) = 회수 1회(ft_reclaim_capped · 7초 상한) → 다시 셈 → live < cap+1 이면 WARN 1줄 + 개설 · 그래도 live >= cap+1 이면 순번 큐(exit 7).
#   W1: 상한 측정 실패(ERROR · `N/M` 꼴 못 읽음)는 정지가 아니다 — `WARN 좌석 상한 측정 실패 — 진행` 1줄. --dry-run 은 회수·큐 0(REJECT 면 옛 rc1 그대로).
_cap_fields() { # <판정기 출력> → "live cap" (`REJECT … N/M` 꼴 · 못 읽으면 빈 값)
  printf '%s\n' "$1" | sed -n 's/^REJECT .* \([0-9][0-9]*\)\/\([0-9][0-9]*\)$/\1 \2/p' | head -1
}
if [ -n "${FT_TEAM_SEAT_CAP:-}${FT_GROUP_SEAT_CAP:-}" ]; then
  [ -f "$HERE/ft_seat_cap.py" ] || { echo "REJECT ft_seat_cap.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _capt="$(printf '%s' "${FT_NANO_PREFIX:-}" | sed -n 's/^byz-\([a-z0-9]*\)-nano-$/\1/p')"
  _cap="$(python3 "$HERE/ft_seat_cap.py" --root "$ROOT" 2>&1)"; _caprc=$?
  if [ "$_caprc" != 0 ]; then
    case "$_cap" in
      REJECT*)
        [ "$DRY" != 1 ] || { printf '%s\n' "$_cap"; exit 1; }   # --dry-run: 회수·큐 0 · 옛 rc1 그대로(판정만)
        if [ -n "$_capt" ]; then
          _cr_out="$(mktemp "${TMPDIR:-/tmp}/ft-r921-capreclaim.XXXXXX")"
          ft_reclaim_capped "$_cr_out" bash "${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}" --caller "$FROM" --need 1 --team "$_capt"; _crrc=$?
          sed -n '1,40p' "$_cr_out" >&2; rm -f "$_cr_out"
          [ "$_crrc" != 124 ] || echo "WARN 회수 시간 초과(${FT_RECLAIM_TIMEOUT_SEC:-7}초) — 진행" >&2
          _cap="$(python3 "$HERE/ft_seat_cap.py" --root "$ROOT" 2>&1)"; _caprc=$?
        else echo "WARN 좌석 상한 — FT_NANO_PREFIX 에서 팀 이름을 못 읽어 회수 0 — 진행" >&2; fi
        if [ "$_caprc" != 0 ]; then
          read -r _cl _cc <<<"$(_cap_fields "$_cap")"
          if [ -z "${_cl:-}" ] || [ -z "${_cc:-}" ]; then
            printf '%s\n' "$_cap"
            echo "WARN 좌석 상한 측정 실패(재검 ${_cap%%$'\n'*}) — 진행(r921: 정지는 디스크 하한·디스크 측정 실패 둘뿐)" >&2
          elif [ "$_cl" -ge "$((_cc + 1))" ]; then
            printf '%s\n' "$_cap"
            [ -f "$HERE/ft_spawn_queue.py" ] || { echo "REJECT ft_spawn_queue.py 없음: $HERE (순번 큐를 쓸 수 없다)"; exit 1; }
            python3 "$HERE/ft_spawn_queue.py" add --root "$ROOT" --prefix "$FT_NANO_PREFIX" --card "$IDX" --from "$FROM"
            exit 7
          else
            echo "WARN resource seat-cap ${_cap%%$'\n'*} — 회수 1회 뒤 cap+1 까지 열어 준다(r921 · 순번 큐 적재 0)" >&2
          fi
        fi;;
      *) printf '%s\n' "$_cap"; echo "WARN 좌석 상한 측정 실패(rc=$_caprc) — 진행(r921: 정지는 디스크 하한·디스크 측정 실패 둘뿐)" >&2;;
    esac
  fi
fi
# ★팀셋 나노 상한 (r-teamset-standard · 판정 2170 · ★r921 r2 개정 = DA⑥ r1 W1·W4★)★
#   W4: 좌석 셈과 개설을 «같은 잠금»(state/nano-cap.lock.d · 7초) 안에서 한다 — 동시 두 spawn 이 둘 다 «cap-1» 을 읽고 둘 다 여는 길 0.
#   상한은 «cap+1» 까지: live < cap+1 → WARN 1줄 + 개설(넘긴 채 연다) · live >= cap+1 → 그 팀 유휴·끝난 나노 회수 1회(7초 상한) → 재검
#     → 그래도 live >= cap+1 이면 순번 큐 + master 알림(«정지» 아니라 «순서 바꿈» · 오빠 «idle 좌석 닫고 순서 바꿈»).
#     잠금을 7초 안에 못 잡으면 WARN + 순번 큐(이중 개설 0).
#   W1: 팀셋 측정 실패(표 못 읽음·cap rc1 등)는 «정지» 가 아니다 — `WARN 팀셋 측정 실패 — 진행` 1줄 남기고 연다(정지는 디스크 하한·디스크 측정 실패 둘뿐).
#   FT_TEAMSET=0 으로 끔 · --dry-run 은 잠금·회수·큐 없이 지금처럼 판정만 한다.
TS_LOCK=""
_ts_lock_free() { [ -z "${TS_LOCK:-}" ] || { rm -rf "$TS_LOCK" 2>/dev/null; TS_LOCK=""; }; return 0; }
_ts_lock_take() { # <잠금 경로> — 7초 안에 못 잡으면 rc1(부르는 쪽이 WARN + 큐)
  local d="$1" i=0 p
  while [ "$i" -lt 70 ]; do
    if mkdir "$d" 2>/dev/null; then printf '%s\n' "$$" > "$d/pid" 2>/dev/null; TS_LOCK="$d"; return 0; fi
    p="$(cat "$d/pid" 2>/dev/null)"
    if [ -z "$p" ]; then [ "$i" -gt 30 ] && rm -rf "$d" 2>/dev/null
    else case "$p" in *[!0-9]*) rm -rf "$d" 2>/dev/null;; *) kill -0 "$p" 2>/dev/null || rm -rf "$d" 2>/dev/null;; esac; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
_ts_fields() { # <cap 출력> → "live cap" (못 읽으면 빈 값)
  local l c
  l="$(printf '%s' "$1" | sed -n 's/.*live=\([0-9][0-9]*\).*/\1/p' | head -1)"
  c="$(printf '%s' "$1" | sed -n 's/.*cap=\([0-9][0-9]*\).*/\1/p' | head -1)"
  printf '%s %s' "${l:-}" "${c:-}"
}
_ts_queue() { # <사유> — 순번 큐에 넣고 master 알림(있으면) · rc7
  echo "QUEUED $2 — $1" >&2
  [ "$DRY" = 1 ] || python3 "$HERE/ft_spawn_queue.py" add --root "$ROOT" --prefix "$_tsp" --card "$IDX" --from "$FROM" || true
  exit 7
}
if [ "${FT_TEAMSET:-1}" != 0 ]; then
  [ -f "$HERE/ft_teamset.py" ] && [ -f "$HERE/ft_spawn_queue.py" ] || { echo "REJECT ft_teamset.py·ft_spawn_queue.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _tsp="$FT_NANO_PREFIX"; _tsmd="${FT_TEAMSET_MD:-gitref:origin/main:design/TEAMSET.md}"   # R351: 표 정본 = $ROOT 의 origin/main
  _tst=""; _tslive=""; _tscap=""
  if [ "$DRY" != 1 ]; then
    mkdir -p "$ROOT/.fable-team/state" 2>/dev/null || true
    _ts_lock_take "$ROOT/.fable-team/state/nano-cap.lock.d" || _ts_lock_fail=1
    if [ "${_ts_lock_fail:-0}" = 1 ]; then
      echo "WARN resource teamset 잠금 대기 초과(7초) — 순번 큐로 보낸다(이중 개설 0)" >&2
      _ts_queue "잠금 대기 초과" "$_tsp"
    fi
    _ON_EXIT+=(_ts_lock_free)   # W4: 덮어쓰기 0 — 정리 목록에 이어 붙인다
  fi
  _tso="$(python3 "$HERE/ft_teamset.py" cap --root "$ROOT" --md "$_tsmd" --prefix "$_tsp" 2>&1)"; _tsrc=$?
  _tst="$(printf '%s' "$_tso" | awk '{print $2}')"
  printf '%s\n' "$_tso"
  read -r _tslive _tscap <<<"$(_ts_fields "$_tso")"
  case "$_tsrc" in
    0) ;;   # live < cap
    4)       # AT-CAP — cap+1 까지는 연다 · 그 위는 회수 1회 → 큐
      if [ -z "$_tslive" ] || [ -z "$_tscap" ]; then
        echo "WARN resource teamset live/cap 못 읽음(${_tso%%$'\n'*}) — 진행" >&2
      elif [ "$_tslive" -lt "$((_tscap + 1))" ]; then
        echo "WARN resource teamset AT-CAP $_tst live=$_tslive cap=$_tscap — cap+1 까지 열어 준다(r921 · 순번 큐 적재 0)" >&2
      elif [ "$DRY" = 1 ]; then
        echo "DRY AT-CAP $_tst live=$_tslive cap=$_tscap — 회수·큐는 실제 실행에서만" >&2
      else
        _tr_out="$(mktemp "${TMPDIR:-/tmp}/ft-r921-tsreclaim.XXXXXX")"
        ft_reclaim_capped "$_tr_out" bash "${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}" --caller "$FROM" --need 1 --team "$_tst"; _trrc=$?
        sed -n '1,40p' "$_tr_out" >&2; rm -f "$_tr_out"
        [ "$_trrc" != 124 ] || echo "WARN 회수 시간 초과(${FT_RECLAIM_TIMEOUT_SEC:-7}초) — 진행" >&2
        _tso="$(python3 "$HERE/ft_teamset.py" cap --root "$ROOT" --md "$_tsmd" --prefix "$_tsp" 2>&1)"; _tsrc=$?
        printf '%s\n' "$_tso"
        read -r _tslive _tscap <<<"$(_ts_fields "$_tso")"
        if [ "$_tsrc" = 4 ] && [ -n "$_tslive" ] && [ "$_tslive" -ge "$((_tscap + 1))" ]; then
          _ts_queue "cap+1 포화(${_tst:-?} live=${_tslive} cap=${_tscap})" "$_tsp"
        fi
        echo "WARN resource teamset AT-CAP 뒤 회수 1회 — live=${_tslive:-?} cap=${_tscap:-?} · 순서 바꿈(정지 아님)" >&2
      fi ;;
    *)       # W1: 측정 실패 = 정지 아님
      echo "WARN 팀셋 측정 실패(rc=$_tsrc) — 진행(r921: 정지는 디스크 하한·디스크 측정 실패 둘뿐)" >&2;;
  esac
fi
# ★카드 흐름 경보 (r954 · 오빠 10-26 «쌓이니까 하루를 다써도 완성이 안되지»)★: 진행 카드 > 일하는 좌석 + 2 또는 착지됐는데 진행인 카드가 있으면 `WARN 카드 흐름 … 이동 먼저: <카드>` 1줄을 내고 «계속» 연다 — rc·개설 불변(개발은 멈추지 않는다 · 읽기 전용 계산).
_cft="$(printf '%s' "${FT_NANO_PREFIX:-}" | sed -n 's/^byz-\([a-z0-9]*\)-nano-$/\1/p')"
[ -n "$_cft" ] || _cft="$(printf '%s' "$IDX" | sed -n 's|.*design/\(teams/\)\{0,1\}\([a-z0-9_-]*\)/indices/.*|\2|p')"
if [ "${FT_CARD_FLOW:-1}" != 0 ] && [ -n "$_cft" ]; then
  if [ -f "$HERE/ft-card-flow.sh" ]; then bash "$HERE/ft-card-flow.sh" --team "$_cft" --root "$ROOT" --warn >&2 || true
  else echo "WARN 카드 흐름 경보 못 냄 — ft-card-flow.sh 없음: $HERE" >&2; fi
fi
# ★라이브 bin 드리프트 입구 검사 (카드 live-bin-drift-check · Issue 816 ③)★: 설치 꼴(*/.fable-team/bin)에서 돌 때만 — 라이브 도구가 origin/main 키트와 다르면 열지 않는다(--dry-run 도 같다).
#   검사 스크립트가 없는 것도 드리프트(설치 누락) · 우회 스위치 없음 — 해결은 master 라이브 cp.
case "$HERE" in
  */.fable-team/bin|*/.fable-team/*/bin|*/fable-team/live/*/bin)   # r385: 버전 폴더 설치 꼴 포함 · 키트 리포 = 하네스 코드 루트(--repo 생략)
    if [ ! -f "$HERE/ft-live-bin-drift-check.sh" ]; then echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시 (ft-live-bin-drift-check.sh 설치 누락)"; exit 1; fi
    _dout="$(bash "$HERE/ft-live-bin-drift-check.sh" --bin "$HERE")" || { printf '%s\n' "$_dout"; echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시"; exit 1; }
    printf '%s\n' "$_dout";;
  *) echo "INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $HERE";;
esac
# ★--tier checker|tester[:N] = 싼 모델 순위 (오빠 2026-09-14 확정 「zcode > cmd > luna > sonnet」 · README §5-1)★
#   N 생략 = 1순위. 한도·거부(usage_limit_reached·429·exit 10 크레딧)면 발주자가 :2 :3 :4 로 다음 순위. sonnet(4) 은 마지막.
#   zcode 슬러그는 설치마다 다르다 — FT_ZCODE_MODEL 로 준다(없으면 REJECT — 없는 모델을 지어내지 않는다).
# 2026-09-14 오빠 실측 정정 2회: 「zcode 구독 없네 제외」 → 「cmd 월제한이 18일날 풀린다.. cmd도 넘기자」 ⇒ 지금 순위 = luna > sonnet. cmd 는 FT_CMD_ENABLED=1 일 때만 1순위 복귀(월제한 해제 후 오빠가 켠다).
_cmd_on="${FT_CMD_ENABLED:-0}"
# ★일반화(2026-10-20 오빠 «ft-nano-spawn.sh 일반화 업그레이드»)★ — 티어는 «기본값 공급자»다: --agent 를 명시하면 티어가 에이전트·모델·effort·fast 를 덮어쓰지 않는다
#   (chatbot #120064: `--agent pi --tier search` 가 pi 가 아니라 opencode 로 열렸다). 티어 이름 검사와 ROLE 은 그대로 한다.
_A0="$AGENT"; _M0="$MODEL"; _E0="$EFFORT"; _F0="$FAST"
case "$TIER" in
  checker|tester|checker:1|tester:1)
    if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
    else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  checker:2|tester:2)
    if [ "$_cmd_on" = 1 ]; then AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";
    else AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5-5[1m]}"; EFFORT="high"; fi;;
  checker:3|tester:3)                AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5-5[1m]}"; EFFORT="high";;
  # impl = 구현 나노. 1순위 sonnet-5.5(기본값 — r286 오빠 하네스 뉴스 «Sonnet 5.5 가 Opus·sol 보다 처리 능력 우위» · 옛 09-28 opus5.5 · fable 은 --model 명시로만), :2 luna (cmd 는 FT_CMD_ENABLED=1 일 때 :2 로 끼어듦)
  impl|impl:1) ;;
  # search = 검색 나노 — 대용량 로그·코드 분석·정본화 서치 «읽고 모으기» 전용(코드 수정 0) · 기본 에이전트 = FT_SEARCH_AGENT(기본 pi: deepseek flash — opencode 무료 경로는 이 IP 에서 «abusive traffic» 으로 차단 · 2026-10-20) ·
  #   FT_SEARCH_AGENT=opencode 로 r286 옛 경로(opencode/deepseek-v4.1-flash-free)로 되돌린다 · 모델은 아래 «에이전트별 기본»(FT_PI_MODEL · FT_OC_MODEL) · 닫기 = ft-nano-close(그 에이전트 프로세스 left=0 확인)
  search) AGENT="${FT_SEARCH_AGENT:-pi}"; MODEL="";;
  impl:2) if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
          else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  impl:3) AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";;
  '') ;; *) echo "unknown --tier $TIER (checker|tester[:1-3] · impl[:1-3] · search)" >&2; exit 2;;
esac
if [ "$AGENT_SET" = 1 ]; then AGENT="$_A0"; MODEL="$_M0"; EFFORT="$_E0"; FAST="$_F0"; fi   # 명시 --agent 우선(위 주석)
# ★r631(planner «짧은 나노 low · 구현 high» · r556 개정)★ pi 나노 종류 판별 1곳 — short = 티어 search·checker·tester 또는 --research · impl = 그 밖(티어 impl · 티어 없는 코드 나노).
pi_kind() { if [ "$RESEARCH" = 1 ]; then echo "short:research"; else case "${TIER%%:*}" in search|checker|tester) echo "short:tier=${TIER%%:*}";; impl) echo "impl:tier=impl";; *) echo "impl:code-nano";; esac; fi; }
# pi 기본 effort = short FT_PI_EFFORT_SHORT(low) · impl FT_PI_EFFORT_IMPL(high) — 13행 high·티어 기본값은 pi 에서 덮는다 · 직접 적은 --effort 가 이긴다(explicit)
#   옛 이름 FT_PI_EFFORT(r556)는 두 갈래 모두에 적용 + stderr WARN(새 이름이 있으면 새 이름이 이긴다) · 되돌림 = FT_PI_EFFORT_IMPL=low
EFFORT_WHY=""
if [ "$AGENT" = pi ]; then
  if [ "$EFFORT_SET" = 1 ]; then EFFORT_WHY="explicit"
  else
    EFFORT_WHY="$(pi_kind)"
    [ -z "${FT_PI_EFFORT:-}" ] || echo "WARN FT_PI_EFFORT 는 옛 이름(r556) — FT_PI_EFFORT_SHORT·FT_PI_EFFORT_IMPL 로 나눠 적어라(지금은 두 갈래 모두 $FT_PI_EFFORT)" >&2
    case "$EFFORT_WHY" in short:*) EFFORT="${FT_PI_EFFORT_SHORT:-${FT_PI_EFFORT:-low}}";; *) EFFORT="${FT_PI_EFFORT_IMPL:-${FT_PI_EFFORT:-high}}";; esac
  fi
fi
# 역할을 seats.json 에 남긴다 — 세션 상태 절·stall 대상 판정이 «checker/tester/impl» 을 가른다
ROLE="${TIER%%:*}"; ROLE="${ROLE:-nano}"
# --model 미지정(티어도 안 정함)이면 에이전트별 기본 — claude 는 FT_IMPL_MODEL, 그 밖은 모델을 지어내지 않고 정해진 것만(표에 없는 에이전트는 REJECT)
if [ -z "$MODEL" ]; then case "$AGENT" in
  claude) MODEL="${FT_IMPL_MODEL:-claude-sonnet-5-5[1m]}";;
  codex)  MODEL="${FT_LUNA_MODEL:-gpt-6-luna}";;
  cmd)    MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}";;
  opencode) MODEL="${FT_OC_MODEL:-opencode/deepseek-v4.1-flash-free}";;   # r286
  pi)     MODEL="${FT_PI_MODEL:-opengateway/deepseek/deepseek-v4.1-flash-ultrafast}";;   # Pi 1.3.0 · OpenGateway fast lane
  *) echo "REJECT --model 필수 (--agent $AGENT 는 기본 모델이 없다)"; exit 1;; esac
fi
# (r975: SEATS·회신 대상 해석은 :54 로 옮겼다 — 상한·회수 게이트의 --caller/--from 도 같은 값을 쓴다)
if [ ! -f "$IDX" ] && [ -f "$HERE/ft-team-lib.sh" ]; then . "$HERE/ft-team-lib.sh"; _tw="$(ft_index_twin "$IDX")" && [ -f "$_tw" ] && { echo "INFO 인덱스 쌍둥이 경로로 해석: $IDX → $_tw (R382 전환 기간 역호환)"; IDX="$_tw"; }; fi
[ -f "$IDX" ] || { echo "REJECT 인덱스 없음: $IDX"; exit 1; }
[ ! -f "$HERE/ft-team-lib.sh" ] || ( . "$HERE/ft-team-lib.sh" && ft_card_location_ok "$IDX" ) || exit 1   # r447: 명단 새 꼴 팀 카드가 옛 꼴 폴더(쌍둥이 해석 포함)면 REJECT
if [ "$RESEARCH" = 1 ]; then case "$IDX" in */진행/*) ;; *) echo "REJECT --research 는 진행/ 에 있는 부모 카드(DA 보류가 쌓인 카드)만 — 카드는 옮기지 않는다: $IDX"; exit 1;; esac
else case "$IDX" in */대기/*) ;; *) echo "REJECT 대기/ 에 있는 인덱스만 연다: $IDX"; exit 1;; esac; fi
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }
# 형제 도구는 설치 폴더에만 있다 — 원본 폴더에서 돌리면 lint 의 «파일 없음» 이 «lint 실패» 로, 첫 발주는 좌석을 연 «뒤» 에 죽는다. 열기 «전»에 거절한다(R134). --dry-run 은 송신 전(179행)에 끝나므로 send-verified 는 실전만.
for _sib in ft-index-lint.sh $([ "$DRY" = 1 ] || echo ft-send-verified.sh ft-agent-ready.sh); do
  [ -f "$HERE/$_sib" ] || { echo "REJECT $_sib 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
done
# R149(판정 1641): 상향 모델은 사유 필수 — 해석이 끝난 실제 MODEL 로 판정하고 부작용(카드·원장·워크트리·tmux·명부) «전»에 거절한다. rc 0=상향 1=기본 그 밖=도구 고장(조용히 기본 취급 0)
python3 "$HERE/ft_raised.py" is-raised "$MODEL"; _rrc=$?
case "$_rrc" in
  0) [ -n "${RAISE//[[:space:]]/}" ] || { echo "REJECT 상향 모델($MODEL)은 --raise \"<사유>\" 필수 — 닫히면 원래 모델로(판정 1641)"; exit 1; };;
  1) ;;
  *) echo "REJECT ft_raised.py 판정 실패 rc=$_rrc ($HERE/ft_raised.py) — 부작용 0"; exit 1;;
esac

# R387 --research: opencode 리서치 좌석은 «쓰고 바로 닫기»(메모리 버그 · r286 reap)가 전제 — 회수 도구가 없으면 부작용 «전» REJECT. Fable 등 다른 에이전트는 통과.
[ "$RESEARCH" != 1 ] || [ "$AGENT" != opencode ] || [ -f "$HERE/ft-opencode-reap.sh" ] || { echo "REJECT --research --agent opencode 는 ft-opencode-reap.sh(r286) 미설치 — 닫을 때 프로세스를 못 회수한다: $HERE · Fable(--agent claude --model claude-fable-5-1[1m])로 열거나 r286 설치 뒤"; exit 1; }

# ★r1217 계정 주간 한도 배정(#5345 ⑦)★ — 모델 확정 뒤 · 카드·워크트리 쓰기 «전» 1회. 대체 = 그 모델로 열기 · 정지 중·가용 0 = rc3 중단(부작용 0)
#   불명 = 원래 모델로 열되 WARN + 발주문 «[배정 불명]» · 기록(발주문·카드 «상태» 절)은 이동 «뒤» · --dry-run 은 판정 줄만 · FT_ACCT_ASSIGN=0 = 호출 0
card_note() {  # <진행/ 카드 경로> "<줄>" — «## 상태» 절 끝에 1줄 · 진행/ 밖·절 없음 = «판정 불가 카드 경로» rc3
  case "$1" in */진행/*) ;; *) echo "판정 불가 카드 경로 $1 (진행/ 아님)"; return 3;; esac
  python3 - "$1" "$2" <<'PY' || return 3
import sys
p, note = sys.argv[1:3]
ls = open(p, encoding="utf-8").read().splitlines()
i = next((k for k, s in enumerate(ls) if s.strip() == "## 상태"), None)
if i is None:
    print(f"판정 불가 카드 경로 {p} (## 상태 절 없음)"); sys.exit(3)
j = next((k for k in range(i + 1, len(ls)) if ls[k].startswith("## ")), len(ls))
while j > i + 1 and not ls[j - 1].strip():
    j -= 1
ls.insert(j, f"- {note}")
open(p, "w", encoding="utf-8").write("\n".join(ls) + "\n")
PY
}
_ASG_LINE=""
if [ "${FT_ACCT_ASSIGN:-1}" != 0 ] && [ -f "$HERE/ft-acct-assign.sh" ]; then
  _asg="$(FT_ROOT="$ROOT" bash "$HERE/ft-acct-assign.sh" "$MODEL" --seat-kind nano | tail -1)"   # INFO·오류는 stderr 그대로 보인다
  echo "ASSIGN $MODEL → $_asg"
  _am=""; case "$_asg" in "대체 없음"*) ;; "대체 "*) _am="${_asg#대체 }"; _am="${_am%% · *}";; esac   # «대체 없음 · 선택 불명» 은 대체가 아니다
  case "$_asg" in
    "허용 "*) ;;
    "정지 중"*|"가용 0"*) echo "REJECT 계정 배정 $_asg — 부작용 0"; exit 3;;
    *) if [ -n "$_am" ]; then _ASG_LINE="[배정] $MODEL → $_am · ${_asg#* · }"; MODEL="$_am"
       else echo "WARN 계정 배정 ${_asg:-출력 없음} — 원래 모델($MODEL)로 연다" >&2; _ASG_LINE="[배정 불명] ${_asg:-출력 없음}"; fi;;
  esac
fi

# ① lint — 누가 읽어도 착수 가능한가 (P2: planner 카드 머리 「- 템플릿: 빈 카드(나노가 채움)」 = lint ⑤⑥ 만 건너뜀 · 그 밖 팀·검사는 그대로)
[ -f "$HERE/ft-team-lib.sh" ] || { echo "REJECT ft-team-lib.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
. "$HERE/ft-team-lib.sh"   # R383: planner 카드 판정·SEATBELT 경로를 팀 폴더 명단으로 푼다(팀 이름 글자 0)
_EBN=""; if ft_team_has_ref "$WT" planner "$IDX" indices/ && awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -q '^- 템플릿: 빈 카드(나노가 채움)'; then export FT_INDEX_ALLOW_EMPTY_BODY=1; _EBN=" ★빈 카드 템플릿: 카드 구현 범위·완료 조건 절을 네가 먼저 채우고 arch 1줄 확인 뒤 착수★"; else unset FT_INDEX_ALLOW_EMPTY_BODY; fi
# ①-0 보고 대상 검사는 위 _nano_reply_target 한 곳에서 끝났다(tmm 목록 1회 · 같은 칸 · REJECT 1줄).

bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }
# r1118: 명부 index = 리포 상대경로 — 카드가 호출 체크아웃(WT) 밖(스크래치·다른 워크트리)이면 접두가 안 떼져 절대경로가 명부에 들어가 닫기 ⑥ ls-tree 가 rc128 이던 자리.
#   ft_index_rel 로 `design/…/indices/<단계>/<파일>` 꼬리 · 꼴 밖 절대경로 = REJECT(카드 base_sha 쓰기·워크트리·명부 «전») · IDX_WT = 카드가 있는 체크아웃(발주문·기준선의 카드 절대경로)
IDX_ABS="$(cd "$(dirname "$IDX")" && pwd)/$(basename "$IDX")"
IDX_REL="${IDX_ABS#"$WT"/}"
IDX_REL="$(ft_index_rel "$IDX_REL")" || { echo "REJECT 카드는 design/…/indices/<단계>/ 아래에 — 리포 상대경로로 못 바꾼다: $IDX_ABS"; exit 1; }   # r1118-mut:spawn
IDX_WT="${IDX_ABS%/"$IDX_REL"}"
# ①-0 제안서 «오빠가 본 승인» 게이트 (R77 · 판정 816 — 로직은 ft-proposal-gate.sh --card)
_pg="$(bash "$HERE/ft-proposal-gate.sh" --card "$IDX")" || { echo "REJECT 제안서 승인 증거 부족 — $_pg"; exit 1; }; echo "$_pg"
# ①-0b 착수 = 열린 깃 이슈 (r823 · 오빠 «시작시 깃 이슈 기반으로 작업 시작») — 대기/ 카드 착수만(--research·--dry-run 대상 아님) · 새·옛 판별·면제 0 · ①b 카드 쓰기·워크트리 «전»
if [ "$RESEARCH" != 1 ] && [ "$DRY" != 1 ]; then
  [ -f "$HERE/ft-spawn-issue-gate.sh" ] || { echo "REJECT ft-spawn-issue-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _ig="$(bash "$HERE/ft-spawn-issue-gate.sh" "$IDX")" || { printf '%s\n' "$_ig"; exit 1; }; echo "$_ig"
fi
# ①a 머리줄 4줄(C6 · SPEC-roles P3-1) — 없으면 REJECT 가 아니라 «spawn 후보 제외» 경고(ft-nano-slots.sh 와 같은 검사 · 현행 동작 보존)
_hmiss="$(awk '/^##[[:space:]]/{exit} {print}' "$IDX" | python3 -c "
import re, sys
h = sys.stdin.read()
print(' '.join(k.replace(' ', '_') for k in ('Issue', '상태', '선행', '시험 입력') if not re.search(r'^\s*[-*]?\s*' + k + r':[ \t]*\S', h, re.M)))")"
[ -z "$_hmiss" ] || echo "WARN 후보 제외 — 카드 머리줄 없음: $_hmiss (REJECT 아님 · ft-nano-slots.sh 후보에서 빠진다): $IDX"
# ①a-2 기준값 머리줄(C20 · SPEC-github-issue-driven §12-1) — 없거나 빈칸이면 REJECT 가 아니라 «후보 제외» 경고(위 4줄 검사와 같은 방식 · 현행 동작 보존).
#   지표가 없으면 「없음 → 대체 축」 을 적어야 하며 빈칸은 안 된다(design/harness/BASELINE-TEMPLATE.md).
awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -Eq '^[[:space:]]*[-*]?[[:space:]]*기준값:[[:space:]]*[^[:space:]]' \
  || echo "WARN 후보 제외 — 카드 머리줄 기준값 없음 또는 빈칸 (REJECT 아님 · 지표 없으면 「기준값: 없음 → 대체 축 <무엇>」 · 하네스 팀 폴더의 BASELINE-TEMPLATE.md): $IDX"

# r1162: --base 없음 ∧ 호출 워크트리 detached(임시 사본 · r1120 길) → 그 커밋이 origin/main 의 조상인지 «열기 전» 확인.
#   미착지·squash 착지 커밋을 base 로 굽으면 닫기 R42 조상 판정이 막힌다(lecture L89 2석) · 카드·워크트리·명부·tmux 쓰기 «전» · --dry-run 도 같은 판정.
#   origin main 1 ref fetch(7초 · 재시도 1 = ft_git_capped) · git 실패 = «판정 불가» REJECT 1줄(하드 룰 20 · 열지 않음).
if [ -z "${BASE_REF:-}" ] && [ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = HEAD ]; then
  _dh="$(git -C "$WT" rev-parse --verify HEAD)" && ft_git_capped 7 "$WT" fetch -q origin +refs/heads/main:refs/remotes/origin/main >/dev/null \
    || { echo "REJECT detached HEAD 기준 커밋 판정 불가 — origin main fetch 실패($WT)"; exit 1; }
  _arc=0; ft_git_capped 7 "$WT" merge-base --is-ancestor "$_dh" refs/remotes/origin/main || _arc=$?
  case "$_arc" in
    0) ;;
    1) echo "REJECT 기준 커밋 ${_dh:0:10} 가 origin/main 에 없다(미착지·squash) — --base origin/main 으로 다시"; exit 1;;
    *) echo "REJECT detached HEAD 기준 커밋 ${_dh:0:10} 조상 판정 불가(rc=$_arc)"; exit 1;;
  esac
fi

# ①b 카드 base_sha 대조 (M7 · single_set_testing §1 규칙 2 · 오빠 ORDERS 102): 09-25 카드를 10-02 코드에 재대조 없이 집행한 사고 차단.
#   카드 «## 상태» 에 `base_sha: <40-hex>` 가 없으면 첫 개설 = 현재 기준 브랜치 HEAD 를 써넣고 진행(REJECT 0).
#   있으면 재개·재spawn = base_sha..HEAD 사이에 카드 «## 구현 범위» 가 인용한 파일(경로 토큰 · `관련 파일:` 줄 포함 · 인용 0 이면 세트 경로 전체 worker/ gateway/ shared/ clients/web/src/ tests/e2e/ scripts/server/)이 바뀌었으면 REJECT.
#   통과 = `--recheck <판정문>` 이 실재하고 그 판정문이 «현재 HEAD sha»(7자 이상 접두)를 적고 있을 때만.
#   r580: 인용 = «확장자 있는 파일 토큰» 만(폴더·ref 토큰은 버린다 · `관련 파일:` 줄의 폴더만 접두) · 확장자 교대는 긴 것 먼저(`tsx|ts` · `json|js` 잘림 방지) · 맨 이름은 basename 대조.
#         겹침 0 통과면 카드 `base_sha:` 를 지금 HEAD 로 갱신한다(다음 재spawn 은 거기서부터 · 출력 `BASE-RENEW …`).
CUR_HEAD="$(git -C "$WT" rev-parse "${BASE_REF:-HEAD}^{commit}")" || { echo "REJECT 기준 ${BASE_REF:+ref(--base) }HEAD 조회 실패: ${BASE_REF:-HEAD}"; exit 1; }
CARD_BASE="$(grep -E '^[[:space:]-]*base_sha:[[:space:]]*[0-9a-f]{40}' "$IDX" | head -1 | grep -oE '[0-9a-f]{40}' | head -1)"
if [ "$RESEARCH" = 1 ]; then
  STAMP_BASE=0   # 리서치 좌석은 코드를 안 만든다 — 부모 카드 base_sha 대조·기록 0(허용 밖 변경은 닫을 때 «리서치 위반» 으로 기록)
elif [ -z "$CARD_BASE" ]; then
  STAMP_BASE=1
else
  STAMP_BASE=0
  _chg="$(python3 - "$IDX" "$WT" "$CARD_BASE" "$CUR_HEAD" <<'PY'
import os, re, subprocess, sys
card, repo, base, head = sys.argv[1:5]
txt = open(card, encoding="utf-8").read()
m = re.search(r"^##\s*구현 범위.*?(?=^##\s|\Z)", txt, re.S | re.M)
scope = m.group(0) if m else ""
# r580: 인용 파일 뽑기 — «확장자 있는 파일 토큰» 만. 확장자 교대는 긴 것 먼저(짧은 것이 먼저 맞으면 `.tsx`→`.ts` 로 잘려 진짜 인용 파일 변경을 놓친다).
#   구현 범위 본문의 폴더 토큰(`clients/web`·`clients/web/src/`)·ref(`origin/main`)는 «인용»이 아니다(그 폴더 아무 변경이나 겹침으로 잡히던 원인) — `관련 파일:` 줄에 명시된 폴더만 접두로 본다.
FILE_RE = re.compile(r"[A-Za-z0-9_.\-]*(?:/[A-Za-z0-9_.\-]+)*\.(?:tsx|ts|json|js|yaml|yml|sh|py|md)(?![A-Za-z0-9_])")
cited = set(FILE_RE.findall(scope))
for ln in txt.splitlines():
    if ln.strip().startswith("관련 파일:"):
        cited |= {t.strip() for t in re.split(r"[,\s]+", ln.split(":", 1)[1]) if t.strip()}
if not cited:
    cited = {"worker/", "gateway/", "shared/", "clients/web/src/", "tests/e2e/", "scripts/server/"}
def hit(p, c):
    if c.endswith("/"):
        return p == c[:-1] or p.startswith(c) or p.endswith("/" + c[:-1])
    if "/" in c:
        return p == c or p.endswith("/" + c)
    return os.path.basename(p) == c
out = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", "diff", "--name-only", base, head], capture_output=True, text=True)
if out.returncode != 0:
    print("DIFFFAIL " + out.stderr.strip()[:120]); sys.exit(3)
hits = [p for p in out.stdout.splitlines() if any(hit(p, c) for c in cited)]
if hits:
    n = subprocess.run(["git", "-C", repo, "rev-list", "--count", f"{base}..{head}"], capture_output=True, text=True).stdout.strip()
    print(f"CHANGED {n} " + " ".join(hits[:20]) + (f" … 외 {len(hits) - 20}개" if len(hits) > 20 else ""))
else:
    print(f"CLEAN {len(cited)}")
PY
)"; _crc=$?
  [ "$_crc" -eq 0 ] || { echo "REJECT 카드 base_sha 대조 실패(rc=$_crc): ${_chg:0:160}"; exit 1; }
  case "$_chg" in
    CLEAN*)
      # 겹침 0 통과 = 카드 기준 시점을 지금으로 옮긴다(다음 재spawn 은 여기서부터 · RECHECK 없이 통과).
      python3 - "$IDX" "$CUR_HEAD" <<'PY' || { echo "REJECT 카드 base_sha 갱신 실패($IDX)"; exit 1; }
import re, sys, datetime
p, head = sys.argv[1:3]
txt = open(p, encoding="utf-8").read()
m = re.search(r"^([ \t]*-[ \t]*base_sha:[ \t]*)[0-9a-f]{40}[^\n]*$", txt, re.M)
if not m:
    sys.exit(3)
txt = txt[:m.start()] + m.group(1) + head + f" (recheck-auto {datetime.date.today()} · 겹침 0)" + txt[m.end():]
open(p, "w", encoding="utf-8").write(txt)
PY
      echo "BASE-RENEW ${CARD_BASE:0:9} → ${CUR_HEAD:0:9} · 인용 ${_chg#CLEAN }개 겹침 0"
      ;;
    ?*)
      _ok=0
      if [ -n "$RECHECK" ] && [ -f "$RECHECK" ]; then
        while read -r _t; do case "$CUR_HEAD" in "$_t"*) _ok=1; break;; esac; done < <(grep -oE '[0-9a-f]{7,40}' "$RECHECK" | sort -u)
      fi
      [ "$_ok" = 1 ] || { echo "REJECT 카드 base_sha ${CARD_BASE:0:9} 이후 feat HEAD ${CUR_HEAD:0:9} 사이에 카드가 인용한 파일이 바뀜 — 재대조 필요(arch 판정 뒤 --recheck <판정문>; 판정문에 현재 HEAD sha 를 적는다). 커밋 $(printf '%s' "$_chg" | cut -d' ' -f2)개 · 바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-)"; exit 1; }
      echo "RECHECK 통과 — 판정문 $RECHECK 가 현재 HEAD ${CUR_HEAD:0:9} 를 적음(바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-))"
      ;;
  esac
fi
SLUG="$(basename "$IDX" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"
[ "$RESEARCH" != 1 ] || SLUG="$(printf '%s' "$SLUG" | cut -c1-30)-research"   # R387: 좌석 이름·브랜치·워크트리 꼬리 -research
BASE_NAME="${FT_NANO_PREFIX:-$DEF_NANO_PREFIX}$SLUG"
N=0; while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"
BRANCH="nano/$SLUG"; WTDIR="$ROOT/.worktrees/${FT_NANO_WT_PREFIX:-v65-}$SLUG"
BASE_BRANCH="${BASE_REF:-$(git -C "$WT" rev-parse --abbrev-ref HEAD)}"
# R42: --base 가 ref 가 아니고 commit(sha)이면 info 에는 «랜딩 브랜치» 를 쓴다(닫기 게이트의 비교 기준) — sha 는 base_sha 칸.
INFO_BASE="$BASE_BRANCH"
if [ -n "${BASE_REF:-}" ] && ! git -C "$ROOT" rev-parse --verify -q "refs/heads/$BASE_REF" >/dev/null \
   && ! git -C "$ROOT" rev-parse --verify -q "refs/remotes/$BASE_REF" >/dev/null \
   && git -C "$ROOT" rev-parse --verify -q "$BASE_REF^{commit}" >/dev/null; then
  INFO_BASE="${FT_NANO_FEAT:-$(git -C "$WT" rev-parse --abbrev-ref HEAD)}"
fi
# r1120: detached HEAD(임시 사본 ft-scratch)면 --abbrev-ref 가 글자 «HEAD» — info base 에는 그 커밋 40hex(닫기 = R42 sha 길).
#   worktree add 기준(BASE_BRANCH)도 같은 40hex — 사본은 --detach linked worktree 라 «HEAD» 를 $ROOT 에서 풀면 메인 체크아웃 HEAD 가 된다.
_BASE_SHOW="$BASE_BRANCH"
if [ -z "${BASE_REF:-}" ] && [ "$BASE_BRANCH" = HEAD ]; then
  INFO_BASE="$(git -C "$WT" rev-parse --verify HEAD)" || { echo "REJECT detached HEAD 커밋 판정 불가($WT)"; exit 1; }
  BASE_BRANCH="$INFO_BASE"; _BASE_SHOW="$INFO_BASE(detached)"
fi
# R387 --research 고정 문단 — 산출 1개·코드 0·arch relay·즉시 [완료·휴식]. 허용 경로 = 부모 카드가 있는 팀 폴더의 RESEARCH-*.md
_RS_DIR="$(dirname "$(dirname "$(dirname "$IDX_REL")")")"; _RS_ALLOW="$_RS_DIR/RESEARCH-*.md"; _RS_OUT="$_RS_DIR/RESEARCH-$(basename "$IDX" .md)-$(date +%F).md"
_RSP=" ★리서치 워커(판정 2282 · R387)★ 네 일 = 부모 카드가 막힌 문제의 자료 조사·가설 조정·BTS 결과 수집뿐이다 — 산출 1개 = $WT/$_RS_OUT (출처·가설·BTS 결과 표기) · 이 경로($_RS_ALLOW) 밖 파일·코드 수정 0(닫을 때 도구가 허용 밖 변경을 카드에 «- 리서치 위반:» 으로 기록한다) · 끝나면 mbox relay 로 arch 에 산출 경로 + 3줄 요약을 보내고 카드 «상태» 에 «- 리서치 산출: <경로> · relay #<seq>» 줄을 쓴다 · 증거 줄 시험 칸 = «RESEARCH 파일 작성 rc=0» · 그 뒤 즉시 [완료·휴식] — 후속 일·재질문 대기 외 작업 0(opencode 좌석은 relay 직후 닫힌다)."

# ②-0 옛 nano 브랜치 충돌 (M7 · 10-02 슬러그 충돌 5회) — 나노 닫기는 워크트리만 지우고 브랜치는 보존한다(09-25 승인).
#   워크트리 없음 ∧ 브랜치 실재 → 그 브랜치를 cherry 게이트로 판정. 반입이면 -r2, -r3 … 후보마다 브랜치가 있으면 «워크트리 유무와
#   무관하게» 같은 판정(DA⑥ 53519 H1 — 살아 있는 -rN 워크트리도 미반입이면 재사용 0). 반입 + 워크트리 있음 = 재사용 · 브랜치 없음 = 새로.
#   미반입이면 REJECT — 옛 브랜치·워크트리 삭제·덮기·재사용 0(판정은 arch). base 워크트리 재발주 재사용(아래 ②)은 그대로.
#   ①b 카드 base_sha 기록보다 «앞» 이라 REJECT 면 카드 파일도 안 건드린다.
if [ ! -d "$WTDIR" ] && git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
  WT_BASE="$WTDIR"; R=1
  while git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; do
    # R71: --base 가 sha 면 게이트는 랜딩 브랜치(INFO_BASE · R42)와 비교 — sha 를 넘기면 게이트가 «브랜치 없음» 으로 막는다
    gate="$( [ "$HAVE_CO" -eq 0 ] || export FT_SEAT="$FROM"   # R70: 원장 seat 칸 = 발주자(서브셸 안만)
             bash "$HERE/ft-nano-cherry-gate.sh" "$INFO_BASE" "$BRANCH" --repo "$ROOT" ${CO_ARGS[@]+"${CO_ARGS[@]}"} )" \
      || { echo "REJECT 옛 브랜치 미반입 — $BRANCH (삭제·덮기·재사용 0 · 판정 arch):"; printf '%s\n' "$gate"; exit 1; }
    echo "old_branch=$BRANCH landed=yes gate=${gate%% *}"
    [ -d "$WTDIR" ] && break
    R=$((R+1)); BRANCH="nano/$SLUG-r$R"; WTDIR="$WT_BASE-r$R"
  done
fi

# tmuxc 옵션은 에이전트별로 다르다 — `--ctx` 는 claude 만, `--effort` 는 claude·cmd·codex, `--fast` 는 codex 만 (ft-role-spawn 과 같은 분기)
OPEN=(tmuxc open "$WTDIR" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex|pi) OPEN+=(--effort "$EFFORT");; esac
[ "$AGENT" = codex ] && [ -n "$FAST" ] && OPEN+=(--fast "$FAST")
# ★r1107(오빠 «꺼야하고 누가 살렸냐. 안뜨게해라» · r556 뒤집음)★ Serena 는 10-22 은퇴 — 어떤 나노에도 tmuxc --serena 를 붙이지 않는다.
#   FT_PI_SERENA 는 읽지 않는다(1 이어도 off) · 코드 탐색은 ci · PLAN 표시만 남긴다(사람이 보는 확인).
SERENA="off(은퇴 10-22)"
_PLANX=""; [ "$AGENT" != pi ] || _PLANX=" effort=$EFFORT($EFFORT_WHY) serena=$SERENA"
# r476: opencode 2.0.32 TUI 는 --model 플래그가 없다 — tmuxc 가 모델을 세션 env OPENCODE_CONFIG_CONTENT 로 심는다(PLAN 에 경로 표기)
_VIA=""; [ "$AGENT" = opencode ] && _VIA=" via=OPENCODE_CONFIG_CONTENT"
echo "PLAN seat=$NAME agent=$AGENT model=$MODEL$_VIA${TIER:+ tier=$TIER}${FAST:+ fast=$FAST} wt=$WTDIR branch=$BRANCH base=${_BASE_SHOW:-$BASE_BRANCH} index=$IDX_REL$_PLANX"
# r486: 나노 워크트리 = sparse(r444 ⑤ · 남의 팀 design 없음) → 광역·다른 팀 자료 시험은 «평범한 실패» 로 보인다 — 발주문 1줄(BODY) · dry-run 에도 같은 글자
_SPX=" ★광역 pytest 금지 — 이 워크트리는 sparse(다른 팀 design 없음 · r444) · 자기 카드 시험만 · 광역·다른 팀 자료 시험은 ft-scratch-repo.sh <base> 사본에서 · 도구는 SPARSE-HIDDEN <경로> 로 말한다(r486)★"
echo "BODY+${_SPX}"
# r570: 나노가 리포 전체를 grep -r 로 훑어 부하를 올리고(v65 press 첫 원문 오염) 공용 명부에 자기 행을 손으로 넣던 사고(쪽지 반송) — 첫 발주문 고정 줄 1개. 에이전트 분기 0(claude·pi·opencode·codex 같은 줄).
_SRX=" ★저장소 전체 검색 금지 — grep -r · git log --all -S · find / 를 리포 루트·홈에서 돌리지 않는다(부하 40 → 다른 팀 press 오염 · r570) · 카드 §구현 범위 경로나 자기 워크트리 폴더를 지정해 찾는다 · 코드 찾기·바꾸기는 \`ci sym/refs/outline/search\`(스코프 = 카드 §구현 범위 폴더 · 리포 루트 scope 금지) · grep 은 로그·결과·명부만 · ci 가 없으면 rg+Read 로 진행하고 1줄 보고(하드 룰 16 · r1025) · 명부(seats.json · seats-<팀>.json)는 손대지 않는다(spawn 이 이미 등록 · 손 행 = 쪽지 반송)★"
echo "BODY+${_SRX}"
# r1035: 나노가 산출 보고를 «턴 종료» 로 읽고 멈추던 사고(10-28 ops 나노 REWORK 보고 뒤 약 20분 유휴 · 카드에 닫을 수 있는 행 3개가 남아 있었고 지적 뒤 5분 만에 끝남) — 첫 발주문 고정 줄 1개. 에이전트 분기 0(claude·pi·opencode·codex 같은 줄).
_AFX=" ★산출 보고 뒤 = 멈춤 아님 — ①보고 직후 카드 «완료 조건» 표를 행마다 다시 훑어 네가 닫을 수 있는 행은 그 턴에 닫고 증거 줄을 카드 «상태» 절에 더한다(master 회신 대기는 일이 아니다) ②보고의 «남은 것» 항목마다 «네가 못 닫는 이유» 를 한 줄 붙이고 못 쓰면 네가 닫는다 ③남은 것이 0 이면 «남은 것 0 + 근거» 와 좌석 종료 요청을 같은 쪽지에 넣는다(r1035)★"
echo "BODY+${_AFX}"
# r1041: 나노 시험이 자기 파일을 가드 없이 다시 불러 fork 폭주 → 사용자 프로세스 상한(kern.maxprocperuid 6000) 도달 · 전 좌석 셸 fork 실패(10-28 r1038) — 첫 발주문 고정 줄 1개. 에이전트 분기 0.
_RLX=" ★시험 안전선(r1041) — 시험은 «ulimit -u»(지금 사용자 프로세스 수 + 여유) 와 «timeout 70» 안에서만 돌린다 · 자기 파일을 다시 부르는 시험은 재진입 표지(환경변수 검사 + exit)가 필수다 · 완료 보고에 ft-test-reentry-lint.sh «시험파일» rc0 을 싣는다 — 가드 없는 자기 호출은 lint rc3 으로 막힌다★"
echo "BODY+${_RLX}"
# r519: 하네스 카드(머리 `- 설치: 있음`) 나노는 팩 리포에 따로 작업 폴더를 만든다 — 자리를 발주문 1줄로 정한다.
#   세션 스크래치에 만들면 nano-close --wt 팩 모드(r508 · 팩 .worktrees/ 아래만)가 거절한다(r517 실사건) · 그 밖 카드 = 출력 0
pack_wt_line() {
  grep -qE '^- 설치: 있음' "$1" || return 0
  local pk="${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}"
  printf ' ★팩 작업 폴더 = %s/.worktrees/%s (git -C %s worktree add %s/.worktrees/%s -b %s origin/main · 세션 스크래치 0 — 닫기 = nano-close --wt %s/.worktrees/%s --branch %s)★' \
    "$pk" "$2" "$pk" "$pk" "$2" "$3" "$pk" "$2" "$3"
}
_PKX="$(pack_wt_line "$IDX" "$SLUG" "$BRANCH")"
[ -z "$_PKX" ] || echo "BODY+${_PKX}"
# R81 ⓐ 슬랙 장부 사전 확인 — 카드에 「- 슬랙:」 줄이 있으면 부작용 «전»에 check(dry-run 도 같다): rc 0·1 통과 · 3 = 장부 불명 · 그 밖·도구 없음 = REJECT
if grep -q '^- 슬랙:' "$IDX"; then _TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
  if [ -f "$_TP" ]; then if [ -x "$_TP" ]; then "$_TP" check --card "$IDX"; else python3 "$_TP" check --card "$IDX"; fi >/dev/null 2>&1; _src=$?; else _src=127; fi
  case "$_src" in 0|1) ;; 3) echo "REJECT 슬랙 장부 불명 — byz_thread_post.py repair --card $IDX (부작용 0)"; exit 1;; *) echo "REJECT 슬랙 장부 확인 실패 rc=$_src(127=도구 없음) — 부작용 0"; exit 1;; esac; fi
# r1078: r444 ⑤ 디스크 여유 검사 — 새 워크트리를 만들 때만 · 여유 < FT_NANO_MIN_FREE_GI(40)Gi 면 WARN 1줄 + 진행(r921 «멈추는 것은 디스크 하한 1GiB·측정 실패 둘뿐» · 회수 권장은 WARN 줄에). 측정 실패는 REJECT(여유 미상 ≠ 충분).
if [ ! -d "$WTDIR" ]; then
  _free="${FT_DISK_FREE_GIB:-$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 && $4+0>0{print int($4/1048576)}')}"
  case "$_free" in ''|*[!0-9]*) echo "REJECT [HIL] 디스크 여유 측정 실패(df $ROOT · 값 '${_free}') — spawn 0 · 여유 미상은 충분하다는 뜻 아님"; exit 1;; esac
  [ "$_free" -ge "${FT_NANO_MIN_FREE_GI:-40}" ] || echo "WARN 디스크 여유 ${_free}Gi < ${FT_NANO_MIN_FREE_GI:-40}Gi — 진행(r1078 · 정지는 디스크 하한 1GiB·측정 실패 둘뿐) · 회수 권장 ft-resource-reclaim.sh · ft-wt-sweep.sh" >&2
fi
if [ "$DRY" = 1 ]; then [ "$RESEARCH" != 1 ] || echo "RESEARCH seat=$NAME allow=$_RS_ALLOW card=$IDX_REL body=$_RSP"; [ -d "$WTDIR" ] || echo "PLAN shim-init $WTDIR (워크트리 생성 직후 ft-root-bin-shim.sh --init)"; "${OPEN[@]}" --dry-run; exit 0; fi
# R251 ⓐ 추론 프록시 사전 확인(7초 룰 · 부작용 0 지점) — 순간 장애는 넘기고 진짜 장애면 직결로 바꾸지 않는다
#   r669: 옛 판은 진짜 장애도 그냥 exit 1 이라 카드가 큐에도 안 남고 사라졌다(같은 파일 위 좌석 상한·팀셋 경로는 이미 «큐 → exit 7») — 같은 꼴로 맞춘다.
_pxout="$(bash "$HERE/ft-agent-ready.sh" --proxy "$WT" --agent "$AGENT" 2>&1)"; _pxrc=$?
[ -z "$_pxout" ] || printf '%s\n' "$_pxout"
if [ "$_pxrc" != 0 ]; then
  [ -f "$HERE/ft_spawn_queue.py" ] || { echo "REJECT 프록시 확인 실패(rc=$_pxrc) + ft_spawn_queue.py 없음: $HERE — 순번 큐를 쓸 수 없다(부작용 0)"; exit 1; }
  python3 "$HERE/ft_spawn_queue.py" add --root "$ROOT" --prefix "$FT_NANO_PREFIX" --card "$IDX" --from "$FROM" || { echo "REJECT 프록시 확인 실패(rc=$_pxrc) + 순번 큐 실패 — 부작용 0"; exit 1; }
  echo "INFO 프록시 확인 실패 = 진짜 장애 — 좌석 0 · 순번 큐에 남깁니다(사유 proxy · 다음 틱 재시도)"
  exit 7
fi
# 사건 원장 훅(PLAN-status-sheet §3-1 · 근원 ⑥): prepared 를 «먼저» — 못 쓰면 착수 거절 · 성공(⑥ 끝)에 committed · 그 밖의 종료는 abort(trap)
_SK="$(bash "$HERE/ft-sheet-events.sh" key spawn "$SLUG" "$NAME")"; _ST="$(printf '%s' "$IDX_REL" | sed -n 's#^design/\(teams/\)\{0,1\}\([a-z0-9]*\)/indices/.*#\2#p')"
bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' spawn "${_ST:-v65}" "$SLUG" "$NAME" "$IDX_REL" "$FROM")" >/dev/null || { echo "REJECT 사건 원장 prepared 실패 — 착수 거절(부작용 0)"; exit 1; }
_sheet_abort() { bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null; }
_ON_EXIT+=(_sheet_abort)   # W4: trap 덮어쓰기 0 — 잠금 해제(_ts_lock_free)와 abort 가 둘 다 돈다
if [ "$STAMP_BASE" = 1 ]; then
  python3 - "$IDX" "$CUR_HEAD" <<'PY' || { echo "REJECT 카드 base_sha 기록 실패($IDX)"; exit 1; }
import re, sys, datetime
p, head = sys.argv[1:3]
txt = open(p, encoding="utf-8").read()
line = f"- base_sha: {head} (spawn {datetime.date.today()})\n"
m = re.search(r"^##\s*상태[^\n]*\n", txt, re.M)
txt = txt[:m.end()] + line + txt[m.end():] if m else txt.rstrip("\n") + "\n\n## 상태\n" + line
open(p, "w", encoding="utf-8").write(txt)
PY
fi

# ★R181★ 웹 시험(jest)은 clients/web/node_modules 가 있어야 돈다 — 루트 것을 상대 심링크로 건다(없으면 건너뛰고 한 줄 출력).
#   lock 이 달라도 걸되 «판이 다르다» 를 출력해 환경 RED 를 결함으로 오판하지 않게 한다. 무시 규칙은 .gitignore `clients/web/node_modules`(슬래시 없음).
link_web_node_modules() {
  local root="$1" wt="$2" rel="../../../../clients/web/node_modules"
  if [ ! -d "$root/clients/web/node_modules" ]; then
    echo "node_modules=none (루트 clients/web/node_modules 없음 — 웹 시험 불가)"; return 0
  fi
  [ -d "$wt/clients/web" ] || { echo "node_modules=none (워크트리에 clients/web 없음 — 웹 시험 불가)"; return 0; }
  [ -e "$wt/clients/web/node_modules" ] || [ -L "$wt/clients/web/node_modules" ] || ln -s "$rel" "$wt/clients/web/node_modules"
  if cmp -s "$root/clients/web/package-lock.json" "$wt/clients/web/package-lock.json"; then
    echo "node_modules=link lock=same"
  else
    echo "node_modules=link lock=differ (루트 node_modules 판이 이 base 와 다름 — 웹 시험 RED 는 환경 원인 후보)"
  fi
}

# ★r1072 SEATBELT-README 경로 = 좌석·명부·카드 «손대기 전»(워크트리·tmux·seats·git mv 앞)에 푼다★
#   자리 = --dry-run 종료 줄 «뒤»(dry-run 은 좌석을 열지 않아 README 가 필요 없다 — 기존 동작 보존) · ② 워크트리 «앞».
#   옛 자리(⑦⑧)는 좌석을 열고 명부를 쓰고 카드를 옮긴 «뒤» 였다 — ccu 처럼 sparse 워크트리(v65 폴더 없음)에서
#   경로를 못 풀면 REJECT 가 그 뒤에 떠서 «좌석만 열리고 첫 발주 0» 이 남았다(실측 2026-10-28 ccu#18).
#   해석 순서: ① FT_SEATBELT_README(명시 = 그대로) ② 디스크(ft_team_file_ref · 실재 1개)
#   ③ ref 판 사본 — <루트>/.fable-team/state/seatbelt-readme/<ref sha 12>-SEATBELT-README.md (같은 sha = 재사용 · tmp+mv)
#   셋 다 실패 = rc1(부르는 쪽이 REJECT — 좌석·명부·카드 손 0). 결과 = 전역 _SBR(경로) · _SBR_REF(사본일 때만 ref 이름)
#   ★$( ) 로 부르지 않는다★ — 서브셸이면 _SBR_REF 가 부르는 쪽으로 안 온다.
seatbelt_readme_path() {
  local ref sha doc dest tmp
  _SBR=""; _SBR_REF=""
  if [ -n "${FT_SEATBELT_README:-}" ]; then _SBR="$WT/$FT_SEATBELT_README"; return 0; fi   # R406: 명시 지정은 그대로
  if doc="$(ft_team_file_ref "$WT" v65 SEATBELT-README.md)"; then _SBR="$doc"; return 0; fi   # R406: 기본값 = 명단 ref 의 v65 폴더 꼴·쌍둥이 중 WT 에 실재하는 1개
  ref="${FT_TEAMS_REF:-origin/main}"
  sha="$(git -C "$WT" rev-parse --verify -q "$ref^{commit}" 2>/dev/null)" || return 1
  doc="$(ft_team_doc_ref "$WT" v65 SEATBELT-README.md "$ref")" || return 1
  dest="$ROOT/.fable-team/state/seatbelt-readme/${sha:0:12}-SEATBELT-README.md"
  if [ ! -f "$dest" ]; then   # 같은 ref sha = 이미 꺼낸 사본 재사용(두 번 spawn 해도 1개)
    { mkdir -p "${dest%/*}" && tmp="$dest.tmp.$$" && cp "$doc" "$tmp" && mv -f "$tmp" "$dest"; } 2>/dev/null || { rm -f "${tmp:-}" "$doc" 2>/dev/null; return 1; }
  fi
  ft_team_doc_tmp "$doc" && rm -f "$doc"
  _SBR="$dest"; _SBR_REF="$ref"
  return 0
}
seatbelt_readme_path || { echo "REJECT SEATBELT-README 경로를 못 풀었다(디스크 0 · ${FT_TEAMS_REF:-origin/main} 판 0) — 좌석·명부·카드 손대기 전"; exit 1; }

# ② 워크트리 — 이미 있으면 재사용(재발주), 없으면 기준 브랜치에서 분기
# r444 ⑤ sparse — 남의 팀 폴더(design/teams/<남>/)는 체크아웃하지 않는다(나노 1개 1.5Gi 중 design 1.34Gi).
#   팀을 못 정하면(카드 경로가 design/(teams/)<팀>/indices 꼴 아님) 전체 체크아웃 · FT_NANO_SPARSE=0 이면 끔 · 되돌림: git -C <워크트리> sparse-checkout disable
# r879 r3 자기 팀 폴더 안에서는 «미디어 확장자»만 뺀다(v65 822M 중 656M) — 글자 파일(md·txt·json)은 작아 남긴다 · fixtures/ 는 통째 · 자기 카드 증거 evidence/<slug>/ 는 맨 뒤에서 통째(나중 줄이 이김).
#   카드 본문 글자에서 허용 경로를 뽑지 않는다(DA⑥ r1·r2 반례 = 자유 글자 파싱이 공백·괄호·«...» 에서 샜다). $2 는 옛 호출 꼴 호환용으로만 받는다.
# r879 r3b(REWORK-r879-r3b): 큰 글자 몫도 뺀다 — `result.json`(press 결과 13~30M)·`*.jsonl`(대소문자 두 벌). 자기 카드 stem 허용 줄은 그대로 맨 뒤.
# r879 r4(DA⑥ r3 HOLD 2 · REWORK-r879-r4): 패턴 «글자 꼴» 을 손으로 쓰지 않는다 — 함수 하나가 만든다. (r5 에서 이 글자 조립 자체를 버렸다 — 아래 r5 주석)
#   r4 의 ①확장자 대소문자 묶음 · ②«폴더 전용» 되살림 줄은 r5 가 지웠다(실재 파일만 제외하므로 폴더 오인이 없다).
# r879 r5(REWORK-r879-r5 · 하드 룰 14 보류 3회 재설계): 제외 규칙을 «손글자 glob» 으로 조립하지 않는다 —
#   git 이 아는 «실재 파일 이름 그대로»(literal) 1줄씩 적는다. 글자 규칙은 git 의 매칭 규칙(폴더/파일 · 대소문자 ·
#   되살림 순서)에 기대므로 입력 꼴마다 새 반례가 났다(r3 두 꼴 · r4 두 꼴). 실재 이름이면 기댈 규칙이 없다.
#   경로 출처 = `git ls-tree -r <BASE_BRANCH>` = 그 워크트리에 «실제로 체크아웃될 파일» 그대로.
#   ★`ls-files` 를 쓰지 않는 이유(실측 2026-10-27)★ ①`worktree add --no-checkout` 직후 그 워크트리 index 는 비어 있다
#     (ls-files 0줄) ②`$ROOT` 의 index 는 ROOT 가 «체크아웃한 가지»의 것이라 BASE_BRANCH 와 다르다(실측: base 에만
#     있는 파일이 빠졌다). 트리(commit)에서 뜨면 두 경우가 다 없다.
#   판정 = python 이 실재 «이름» 의 확장자를 소문자로 비교(폴더는 대상 아님 — 이름이 .wav 로 끝나는 폴더도 그 안 글자는 IN)
#     · `result.json` · 끝 `.jsonl` 도 같은 자리에서 본다.
#   이스케이프 1규칙(gitignore): `\` `!` `*` `?` `[` `]` `#` 앞에 `\` · 공백은 `\ `.
# r879 r6(DA⑥ r4 반례 · REWORK-r879-r6): 이름 안 «제어 문자»(개행·탭·CR 등)는 그 글자 하나를 `?` 한 글자로 적는다.
#   규칙 파일이 «줄 단위»라 개행을 literal 로 적을 수 없다 — 그대로 내보내면 `…/other/line` + `break.wav` 두 줄이 되어
#   첫 줄이 `line/` 폴더를 통째 제외한다(DA 원문 반례). `?` 는 그 자리 한 글자만 대신하므로 폴더를 건드리지 않는다.
#   (계약 아님 · 실측) 같은 폴더에 그 자리만 다른 이름의 «다른 미디어 파일» 이 있으면 함께 제외될 수 있다.
#   새 파일(트리에 없는 것)은 제외 줄에 없다 — 나노 자기 산출은 그대로 add rc0(계약 ③).
SPARSE_EXTS="wav mp3 m4a flac ogg mp4 webm mov png jpg jpeg gif zip tar gz tgz"
sparse_exclude_lines() {  # $1=팀 $2=base ref → 제외 줄('!/<실재 경로>') 1줄씩 · NUL 로 받아 NUL 로 내보낸다
  git -C "$ROOT" --literal-pathspecs ls-tree -r -z --name-only "$2" -- "design/teams/$1" \
    | python3 -c 'import sys
exts = set(sys.argv[1].split())
raw = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
for p in raw.split("\0"):
    if not p:
        continue
    name = p.rsplit("/", 1)[-1].lower()
    if not (name == "result.json" or name.endswith(".jsonl") or any(name.endswith("." + e) for e in exts)):
        continue
    out = []
    for ch in p:
        if ord(ch) < 0x20 or ord(ch) == 0x7f:
            out.append("?")
            continue
        if ch in "\\!*?[]#" or ch == " ":
            out.append("\\" + ch)
        else:
            out.append(ch)
    sys.stdout.write("!/" + "".join(out) + "\0")' "$SPARSE_EXTS"
}
sparse_patterns() {  # $1=팀 $2=base ref $3=카드 슬러그 — 머리 3줄 → 제외 N줄(실재 파일) → 되살림 2줄(뒤 줄이 이김)
  printf '/*\n!/design/teams/*/\n/design/teams/%s/\n' "$1"
  sparse_exclude_lines "$1" "$2" | tr '\0' '\n'
  printf '/design/teams/%s/**/fixtures/**\n' "$1"
  [ -z "${3:-}" ] || printf '/design/teams/%s/evidence/%s/**\n' "$1" "$3"
}
if [ ! -d "$WTDIR" ]; then
  _SPT="$(printf '%s' "$IDX_ABS" | sed -nE 's#.*/design/(teams/)?([a-z0-9][a-z0-9_-]*)/indices/.*#\2#p')"   # 카드가 다른 워크트리(절대경로)에 있어도 팀을 푼다
  if [ "${FT_NANO_SPARSE:-1}" = 1 ] && [ -n "$_SPT" ]; then
    git -C "$ROOT" worktree add --no-checkout "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
    sparse_patterns "$_SPT" "$BASE_BRANCH" "$SLUG" | git -C "$WTDIR" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 && git -C "$WTDIR" checkout -q 2>/dev/null \
      || { echo "REJECT sparse 체크아웃 실패($WTDIR · 브랜치 $BRANCH · 워크트리는 남김 — 사람 판정)"; exit 1; }
    echo "SPARSE team=$_SPT 남의 팀 design·자기 팀 안 미디어(wav·mp4·png·zip 등)·큰 글자(result.json·jsonl) 제외 · 글자 파일은 남김 · 새 증거 = design/teams/$_SPT/evidence/$SLUG/ (다른 미디어가 필요하면 git sparse-checkout add <경로> · 되돌림: git -C $WTDIR sparse-checkout disable)"
  else
    FT_WT_FULL="nano full(FT_NANO_SPARSE=${FT_NANO_SPARSE:-1} · team=${_SPT:-?}) $IDX_REL" git -C "$ROOT" worktree add "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }   # r835: 풀 선택을 post-checkout 에 알림(표식 full)
  fi
  # r494: 새 워크트리에 하네스 입구(.fable-team/bin 연결 파일 + LIVE_BIN·LIVE_ROOT) — 실패해도 spawn 은 계속 · 조용한 통과 0(NOTE 줄)
  _shim_out="$(bash "$HERE/ft-root-bin-shim.sh" --root "$WTDIR" --live "$(sed -n 1p "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null)" --init 2>&1)" \
    && echo "$(tail -1 <<< "$_shim_out") (shim-init $WTDIR)" || echo "NOTE shim-init 실패: $(tail -1 <<< "$_shim_out")"
  for l in .venv .env; do [ -e "$ROOT/$l" ] && ln -sfn "../../$l" "$WTDIR/$l"; done
  link_web_node_modules "$ROOT" "$WTDIR"
  # base_sha(오빠 ORDERS 103 · single_set_testing §3 ①): 갈라진 시점을 남겨 ft-nano-freshness 가 «루트부터» 판정한다.
  printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"nano · %s"}\n' "$BRANCH" "$INFO_BASE" "$(git -C "$ROOT" rev-parse --short "$BASE_BRANCH")" "$(date '+%F %T')" "$IDX_REL" > "$WTDIR/.worktree-info.json"
  # ★Serena project_name 충돌 차단 (2026-09-16 사고 1 · arch#49 #17015)★
  #   워크트리 41개가 전부 project_name "BYZ-Agents" 라 «나중 활성이 이긴다» — 형제 좌석의
  #   Serena 편집 8파일이 남의 워크트리에 떨어졌다(손실 0으로 복구). 절대경로 활성도 이름
  #   충돌엔 무력하고 `get_current_config` 는 이름만 보여줘 판별이 안 된다.
  #   ⇒ 워크트리를 만드는 그 자리에서 이름을 워크트리 이름으로 박는다.
  if [ -f "$WTDIR/.serena/project.yml" ]; then
    _wtname="$(basename "$WTDIR")"
    /usr/bin/sed -i '' -E "s|^([[:space:]]*project_name:[[:space:]]*).*$|\1\"$_wtname\"|" "$WTDIR/.serena/project.yml" \
      && echo "SERENA project_name=$_wtname ($WTDIR/.serena/project.yml)" \
      || echo "WARN serena project_name 치환 실패 — 좌석에 «편집 직전 find_file 1회» 규율을 알려라"
  fi
else
  # R196: 재사용인데 .worktree-info.json 이 없으면(정리·복원으로 소실) 새로 만들 때와 같은 꼴로 다시 쓴다 — 없는 채로 두면 ft-nano-close 가 branch=? 로 멈춘다. 있으면 손대지 않는다(created_at 보존).
  if [ ! -f "$WTDIR/.worktree-info.json" ]; then
    _reuse_head="$(git -C "$WTDIR" symbolic-ref --short HEAD 2>/dev/null)"
    [ "$_reuse_head" = "$BRANCH" ] || { echo "REJECT 재사용 워크트리 브랜치 불일치 — HEAD=${_reuse_head:-detached} 기대=$BRANCH"; exit 1; }
    _reuse_mb="$(git -C "$WTDIR" merge-base "$BRANCH" "$BASE_BRANCH" 2>/dev/null)" || { echo "REJECT 재사용 워크트리 merge-base 실패 — $BRANCH ↔ $BASE_BRANCH"; exit 1; }
    # 같은 폴더 임시 파일에 쓰고 mv — 완성본만 게시한다. 쓰기·mv 실패는 REJECT(info 없이 열기 0).
    _reuse_tmp="$WTDIR/.worktree-info.json.tmp.$$"
    { printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"nano · reuse · %s"}\n' "$BRANCH" "$INFO_BASE" "$(git -C "$WTDIR" rev-parse --short "$_reuse_mb")" "$(date '+%F %T')" "$IDX_REL" > "$_reuse_tmp" && mv -f "$_reuse_tmp" "$WTDIR/.worktree-info.json"; } 2>/dev/null \
      || { rm -f "$_reuse_tmp" 2>/dev/null; echo "REJECT 재사용 워크트리 info 쓰기 실패 — $WTDIR/.worktree-info.json"; exit 1; }
    echo "INFO 재작성 $WTDIR"
  fi
fi

# ③ 열기 — 모델 인자에 대괄호가 있어 zsh 글롭 즉사 함정(글로벌 규칙) → 이 스크립트는 bash 라 그대로 통과
# R81 판정 847 — ③④(세션 열기·태그) 실패 = 이 실행이 연 세션만 undo 가 kill(소유권·착수 0 검사) · ⑤⑥ 실패 = kill 0 + 사람 판정
fail_rb() { echo "$1"; [ -n "${OWNED:-}" ] || { echo "롤백 불가 — 고아: $NAME (소유권 값 못 읽음)"; exit 1; }
  _o="$(FT_NANO_PREFIX="${FT_NANO_PREFIX:-$DEF_NANO_PREFIX}" FT_SEATS_JSON="$SEATS" FT_ACTIVE_TAG="${FT_ACTIVE_TAG:-@zc_v65_active}" bash "$HERE/ft-nano-spawn-undo.sh" "$NAME" --owned "$OWNED" --card "$IDX")" && { printf '%s\n' "$_o"; exit 1; }; echo "롤백 실패 — 고아: $NAME ($_o)"; exit 1; }
human() { echo "REJECT $1 실패 — 세션 $NAME 떠 있음·명부 등록됨 — 사람 판정(ft-nano-spawn-undo.sh $NAME 단독 모드로 계획 생성 가능)"; exit 1; }
_OC_SINCE="$(date +%s)"   # r286: opencode 좌석이 띄운 serve(부모 잃음) 귀속 기준 시각
# ★r672 H1: 리서치 좌석은 «잠금 안에서 다시 세고» 개설한다 — 두 spawn 이 동시에 0석을 읽고 둘 다 열던 길 0.
if [ "$RESEARCH" = 1 ]; then
  _rlk="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"   # 잠금은 리포 state 안(설치 폴더 오염 0 · 모든 spawn 이 같은 자리)
  RESEARCH_LOCK="${_rlk:-${TMPDIR:-/tmp}}/.fable-team/state/research-spawn.lock.d"; mkdir -p "$(dirname "$RESEARCH_LOCK")" 2>/dev/null || true
  _rcap="$(ft_research_cap_check "$RESEARCH_LOCK")"; _rcarc=$?   # r921: 상한 판정 0 · 잠금만 잡는다
  [ "$_rcarc" = 0 ] || { echo "$_rcap"; rm -rf "$RESEARCH_LOCK" 2>/dev/null; exit 3; }
fi
"${OPEN[@]}" >/dev/null 2>&1; _orc=$?
tmux has-session -t "=$NAME" 2>/dev/null || { [ "$_orc" -eq 0 ] && echo "REJECT 세션이 안 떴다: $NAME" || echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
ft_research_unlock "$RESEARCH_LOCK"   # r672 H1: 개설 확인 직후 잠금 해제 — 조회~개설 구간만 잡는다
_ts_lock_free   # r921 W4: 좌석 셈~개설 구간 잠금 해제(이 시점부터 다른 spawn 이 새 live 수를 본다 · 실패 경로는 trap 이 푼다)
IFS='|' read -r PANE _cr < <(tmux list-panes -a -F '#{session_name}|#{pane_id}|#{session_created}' | awk -F'|' -v s="$NAME" '$1==s{print $2"|"$3; exit}'); OWNED=""; [ -n "$PANE" ] && [ -n "$_cr" ] && OWNED="$PANE:$_cr"
[ "$_orc" -eq 0 ] || fail_rb "REJECT tmuxc open 실패 ($NAME)"
# R251 ⓑ 에이전트 본체 확인 — 명부·카드 이동 «전». 없으면 이 실행이 연 pane 에 기동 명령 1회 재입력, 그래도 없으면 롤백(카드는 대기 그대로)
bash "$HERE/ft-agent-ready.sh" --pane "$PANE" --agent "$AGENT" --restart "$("${OPEN[@]}" --dry-run 2>/dev/null | sed -n 's/^command=//p')" || fail_rb "REJECT 에이전트 미기동 ($NAME) — 재기동 1회 실패"
# r286: opencode 좌석 = 지금 프로세스 나무 + 열린 뒤 뜬 serve 를 pid 파일에(닫기가 세션 kill 뒤 부모 잃은 것까지 회수) — 기록 실패는 경고(닫기 앞 기록이 다시 모은다)
[ "$AGENT" != opencode ] || bash "$HERE/ft-opencode-reap.sh" "$NAME" --wt "$WTDIR" --record --since "$_OC_SINCE" >&2 || echo "WARN opencode pid 기록 실패($NAME) — 닫기 앞 기록이 다시 모은다" >&2

# ④ 소실 방지 두 줄 — E-190(remain-on-exit 없어 pane 통째 소실) · E-212(태그 없어 zombie-clean 이 kill)
# ★`-t "=$NAME"` 은 has-session 에만 통한다★ (실측 2026-09-14): `#` 든 이름에 set-option/display-message 는
#   `no such session`. pane_id 로 해석해 넘긴다(mbox.sh pane_of 와 같은 이유). 세션 옵션은 pane 타겟으로도 세션에 박힌다.
[ -n "$PANE" ] || fail_rb "REJECT pane 못 찾음: $NAME"   # PANE·OWNED 는 ③ 직후 읽었다(위)
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1
[ "$(tmux show-option -qv -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}")" = 1 ] || fail_rb "REJECT 태그 확인 실패: $NAME"

# ⑤ seats.json 등록 (tick=null → 알림 울림)
python3 - "$SEATS" "$NAME" "$AGENT" "$MODEL" "$IDX_REL" "$ROLE" "$RAISE" "$FROM" <<'PY' || human "⑤ 명부 등록"
import json, sys, collections, datetime
p, name, agent, model, idx, role, raise_reason, by = sys.argv[1:9]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d[name] = collections.OrderedDict([("role",role),("agent",agent),("tick",None),("model",model),("index",idx.replace("/대기/","/진행/"))])
if raise_reason.strip():   # R149: 상향 좌석 «왜 올렸나·언제 내리나» — 카드(진행/)가 완성/ 으로 가거나 없어지면 ft-tick raised_watch 가 ▶내릴 것
    d[name]["raised"] = collections.OrderedDict([("reason",raise_reason.strip()),("card",d[name]["index"]),("by",by),("at",datetime.datetime.now().isoformat(timespec="seconds")),("close_on","card 가 완성/ 으로 가거나 없어짐 · 또는 좌석 닫기")])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY

# ⑥ 대기→진행 (호출 워크트리에서 git mv — 인덱스 폴더의 정본은 기준 브랜치)
if [ "$RESEARCH" = 1 ]; then   # R387: 부모 카드는 이미 진행/ — 옮기지 않고 «리서치: 좌석 · base · 허용» 줄만 상태 절에 덧붙인다(닫을 때 위반 검사·완성 게이트가 읽는다)
  NEW_IDX="$IDX_REL"; printf -- '- 리서치: %s base=%s 허용=%s\n' "$NAME" "$CUR_HEAD" "$_RS_ALLOW" >> "$IDX" || human "⑥ 리서치 카드 줄"
else
  bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME" || human "⑥ 인덱스 이동"
  NEW_IDX="${IDX_REL/\/대기\//\/진행\/}"
fi
[ -z "$_ASG_LINE" ] || { _cn="$(card_note "$IDX_WT/$NEW_IDX" "$_ASG_LINE")" || echo "WARN 카드 배정 줄 기록 실패 — ${_cn:-rc≠0}" >&2; }   # r1217: 이동 «뒤» 경로
# ★R163 spawn 카드 기준선★ — 이 시각의 카드 내용 지문·브랜치·워크트리를 남겨 두면 자율 중 «nano-reopen» 대리 판정(r162)이 «승인 범위 그대로» 인지 비교한다.
#   spawn 출력·exit 는 불변 — 쓰기 실패는 stderr 1줄뿐(tmp→mv 원자 쓰기).
_CB_DIR="${FT_NANO_CARD_BASE_DIR:-$ROOT/.fable-team/state/nano-card-base}"
{ mkdir -p "$_CB_DIR" && _cb_blob="$(git -C "$WT" hash-object "$IDX_WT/$NEW_IDX")" && python3 - "$_CB_DIR/$NAME.json" "$NAME" "$NEW_IDX" "$_cb_blob" "$BRANCH" "$WTDIR" <<'PY'
import json, os, sys, datetime
p, name, card, blob, branch, wt = sys.argv[1:7]
tmp = f"{p}.tmp-{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"name": name, "card_path": card, "card_blob": blob, "branch": branch, "worktree": wt, "at": datetime.datetime.now().isoformat(timespec="seconds")}, f, ensure_ascii=False, indent=2); f.write("\n")
os.replace(tmp, p)
PY
} || echo "WARN spawn 카드 기준선 쓰기 실패($_CB_DIR/$NAME.json) — spawn 은 그대로 진행" >&2
bash "$HERE/ft-sheet-events.sh" commit "$_SK" >/dev/null || true   # 좌석 열림+명부+카드 이동까지 끝 = 착수 사건 성공 (append 실패는 stderr SHEET-EVENT-PENDING · rc 그대로)

# ⑦⑧ 첫 발주 = 인덱스 경로 한 줄 + README. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
#   r1072: $_SBR 은 좌석 열기 «전»(seatbelt_readme_path)에 이미 풀렸다 — 여기서 다시 풀지 않는다(경로가 두 벌이 되면 갈린다).
BODY="[Seatbelt 발주] 네 인덱스: $IDX_WT/$NEW_IDX — 먼저 $_SBR${_SBR_REF:+ (ref $_SBR_REF 판 사본)} §2 부팅 5단계(첫 보고까지), 그 다음 인덱스 §구현 범위만. 커밋은 브랜치 $BRANCH, push 금지. 산출 경로를 mbox 로 $FROM 에. ★press(라이브 오디오 시험) 금지 — 나노는 쏘지 않는다(ft-press-gate ⑦ 이 tester·checker 좌석만 허가 · 오빠 10-07) · 시험은 단위·캡처·기존 로그만, press 가 필요하면 산출에 「press 필요: <무엇을 볼지>」 1줄로 적어 $FROM 에 넘긴다★ ★측정 조작 금지(오빠 절대지침) — 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)·말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거 아님 · 측정은 trusted 클릭 + 기존 e2e 러너의 실제 음성 경로만 · 격리 Redis 픽스처 시험은 별개 · 이미 썼으면 [HIL] 로 올림 (BOOT 20)★ ★편집은 Edit 절대경로($WTDIR/…)만★ ★읽기는 Read · 코드 찾기는 ci, Bash 는 실행(git·pytest·ruff·mbox)만★ — cat/sed -n/grep 으로 파일을 읽으면 전문이 컨텍스트에 쌓인다(2026-09-14 나노 16좌석 실측: Bash 100~156회 중 절반이 파일 읽기). ★증거 줄(세트: … · 시험: … rc=… · 이슈: …)은 완료 턴에 네가 인덱스 «상태» 절에 직접 쓴다($IDX_WT/$NEW_IDX 절대경로 Edit) — master 는 커밋만(판정 1125)★ 증거 줄 템플릿(그대로 복사해 <> 만 채움): 세트: <나노 HEAD 40자> · 시험: <명령 — «(N passed)» 같은 꼬리는 여기> rc=<n> · 이슈: 0 — rc= 바로 뒤는 « · 이슈:» — 괄호·설명은 rc= 앞에. ★팀 구조: 각 팀 = master(집행) + arch(설계·발주·DA 소환) + DA(반박 게이트) 상시 · 실제 작업은 전부 나노(카드 1장 = 나노 1석) · master·arch·DA 는 코드·시안·카드 증거 줄을 쓰지 않는다★${_SPX}${_SRX}${_AFX}${_RLX}$_PKX${_EBN}"
[ -z "$_ASG_LINE" ] || BODY="[Seatbelt 발주] $_ASG_LINE — ${BODY#\[Seatbelt 발주\] }"   # r1217: 머리 뒤 배정 1줄
[ "$RESEARCH" != 1 ] || BODY="$BODY$_RSP"
[ "$TIER" != search ] || BODY="$BODY ★검색 나노($AGENT · r286)★ 읽고 모으기만 — 코드 수정·커밋 0 · 산출 = 파일 1개 + mbox relay · 끝나면 [완료·휴식] (닫기 = master ft-nano-close · $AGENT 프로세스 left=0 확인)."
# ★r1025: 송신 «직전» 최종 본문 검사★ 전역 하드 룰 16 은 «사람·나노·스크립트 모두 ci» 인데 이 스크립트의 고정 문구가
#   «serena 먼저»(r556)라 규칙과 도구가 서로 반대였다(planner 설계 §② 실측 · r1024 나노 부팅 보고 «Serena O»).
#   문구를 ci 로 바꾼 뒤 다시 섞이지 않게 «보내기 전» 검사 1개 — 걸리면 REJECT 1줄 · 송신 0 · 좌석·워크트리는 기존 REJECT 길로 롤백.
#   ★r1025 r1(arch 163 반송)★ 검사 대상 = «지시 문장» 뿐이다 — 카드 경로·가지 이름·좌석 이름에는 «serena» 가 들어갈 수 있다
#   (이 카드 r1025 자신: nano/r1025-nano-spawn-body-serena-to-ci · r1025-nano-spawn-body-serena-to-ci.md).
#   BODY 는 그대로 두고 이름 「값»만 지운 사본을 검사한다(값 지우기는 retired_probe 한 곳).
retired_probe() {   # $1=발주문 전문 · $2..=지울 «이름 값» → 이름 값을 지운 검사용 사본
  local _p="$1" _v; shift
  for _v in "$@"; do [ -n "$_v" ] && _p="${_p//"$_v"/}"; done
  printf '%s\n' "$_p"
}
retired_line() {   # $1=검사용 사본 → 은퇴 도구 낱말 1개(없으면 빈 출력)
  local _w
  for _w in serena Serena find_symbol; do
    case "$1" in *"$_w"*) printf '%s\n' "$_w"; return 0;; esac
  done
}
_probe="$(retired_probe "$BODY" "$IDX_WT/$NEW_IDX" "$WTDIR" "$BRANCH" "$IDX_REL" "$NEW_IDX" "$_SBR" "$NAME" "$FROM" "$SLUG")"
_retired="$(retired_line "$_probe")"
[ -z "$_retired" ] || fail_rb "REJECT 발주문에 은퇴 도구 지시(serena) — $_retired"
# (에이전트 본체는 ③ 직후 ft-agent-ready.sh 가 확인했다 — 옛 sleep 8 대체 · R251)
FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; _src=$?
[ "$_src" -eq 0 ] && { echo "SPAWNED $NAME index=$NEW_IDX wt=$WTDIR"; exit 0; }
echo "SPAWNED-UNVERIFIED $NAME rc=$_src — 좌석은 떴다. 도달을 사람이 확인"; exit 5
