#!/usr/bin/env bash
# ft-autonomy-standing-d3.sh — r1794 «상시 승인 D3» 위험 낮은 병합(docs · ff · 시험 파일만) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   왜: D1·D2 는 DA 판정문이 있어야 한다 → DA 가 필요 없는 ff·docs·시험 파일만 PR 이 범위 승인 건수를 먹었다(S45 하루 20건 중 11건).
#   approve-standing D3 --repos byz|pack|byz,pack --classes <docs,ff,test 중 1~3개>   ← 오빠 `!` 전용(D1 과 같은 좌석 판정 = std_seat_probe) · 끝 시각 없음
#       켜짐 Slack 1글 먼저(scope_slack_post) → grants.audit(+slack_ts) → log `approve-standing D3 <epoch> repos=… classes=…`
#   standing-approve D3 <head40> --pr <N> --repo byz|pack   ← 쓰기 = 그 팀 master 좌석만(team-master-seat 통과만 · desk 포함 그 밖 = 거절 · d2_seat 재사용 0)
#       ①D3 켜짐 ②분류 CLASS docs|ff ∈ classes · 또는 CLASS code ∧ 바뀐 파일 «전부» 시험 파일 ∧ test ∈ classes ③FORBID 0 ∧ --critical = CRITICAL-OK ④--repo ⊆ repos · DA 판정문 요구 0
#       통과 = log `standing-use D3 <head> <epoch> pr=<N> repo=<r> class=<k>` → `approve-merge <head> D3 <epoch>` → 승인 파일 → 원장 D3.ledger.tsv(7칸) · scope 셈 변화 0
#       거절 = STANDING-REJECT rc2 · 쓰기 0 · 끝줄 «다시: scope-approve 또는 D2»
#   standing-stop D3 "<사유>"   누구나 · 멈춘 뒤 standing-approve D3 = 거절 · 다시 켜기 = approve-standing D3 뿐
. "$HERE/ft-autonomy-standing-d2.sh"   # D1·D2 헬퍼(std_t7·std_usage·std_wfail·std_seat_probe·std_roster_root·d2_repo·tpl_file·amt_write) 재사용 — 사본 0
D3="$STATE/autonomy-standing"
D3_GRANT_RE='^approve-standing D3 [0-9]+ repos=(byz|pack|byz,pack) classes=(docs|ff|test)(,(docs|ff|test)){0,2}$'
std_err() { echo "STANDING-REJECT $1" >&2; echo "다시: scope-approve 또는 D2 — 위험 낮은 병합(docs·ff·시험 파일만) 상시 승인 D3 를 못 지났어요" >&2; exit 2; }
d3_plain() {  # <classes> → 사람 말
  local c out="" sep=""
  for c in ${1//,/ }; do case "$c" in docs) out="$out${sep}문서 병합" ;; ff) out="$out${sep}빨리 감기 병합" ;; test) out="$out${sep}시험 파일만 바꾼 병합" ;; esac; sep=" · "; done
  printf '%s' "$out"
}
d3_on() {  # rc0 = 마지막 approve-standing D3 줄(꼴 맞음)이 마지막 standing-stop D3 줄보다 뒤 → D3_LINE D3_REPOS D3_CLASSES
  local g s; g="$(grep -n '^approve-standing D3 ' "$LOG" 2>/dev/null | tail -1)"; s="$(grep -n '^standing-stop D3 ' "$LOG" 2>/dev/null | tail -1)"
  [ -n "$g" ] || return 1; D3_LINE="${g#*:}"; [[ "$D3_LINE" =~ $D3_GRANT_RE ]] || return 1
  D3_REPOS="${D3_LINE#* repos=}"; D3_REPOS="${D3_REPOS%% *}"; D3_CLASSES="${D3_LINE#* classes=}"; D3_CLASSES="${D3_CLASSES%% *}"
  [ -z "$s" ] || [ "${g%%:*}" -gt "${s%%:*}" ]
}
cmd_approve_standing() {
  local d="${1:-}" rp="" cl="" c seen="," now body ts line u="usage: approve-standing D3 --repos byz|pack|byz,pack --classes docs,ff,test"
  [ "$d" = D3 ] || std_usage "$u"; shift
  while [ $# -gt 0 ]; do [ $# -ge 2 ] || std_usage "$1 값 없음 ($u)"
    case "$1" in --repos) rp="$2" ;; --classes) cl="$2" ;; *) std_usage "알 수 없는 인자: $1" ;; esac; shift 2; done
  case "$rp" in byz|pack|byz,pack) ;; *) std_usage "--repos 는 byz·pack·byz,pack(받은 값: ${rp:-없음})" ;; esac
  [[ "$cl" =~ ^(docs|ff|test)(,(docs|ff|test)){0,2}$ ]] || std_usage "--classes 는 docs·ff·test 중 1~3개(받은 값: ${cl:-없음})"
  for c in ${cl//,/ }; do case "$seen" in *",$c,"*) std_usage "종류 중복: $c" ;; esac; seen="$seen$c,"; done
  std_seat_probe || {   # 켜기 = 오빠 `!` 전용 — D1 과 같은 좌석 판정(planner master pane) · 쓰기 판정(팀 master)과 «다른» 함수
    echo "STANDING-REJECT approve-standing D3 — 호출 좌석 $STD_SEAT_ACTUAL ≠ planner master(오빠 \`!\`) · 쓰기 0" >&2
    echo "  ($STD_SEAT_ERR · D3 켜기는 오빠 \`!\` 한 줄 몫)" >&2; exit 2; }
  [ -z "${FT_DOC_EXEMPT_SELFTEST:-}${FT_DOC_EXEMPT_SEAT:-}" ] || { echo "STANDING-REJECT approve-standing D3 — 시험 판정(SELFTEST env)으로는 승인 0" >&2; exit 3; }
  lock; [ "$(mode)" = tamper ] && std_usage "자율 상태 위변조(tamper) — 상시 승인 기록 없음"
  if d3_on; then unlock; echo "STANDING-NOOP D3 이미 켜짐($D3_LINE)"; return 0; fi
  now="$(now_epoch)"; line="approve-standing D3 $now repos=$rp classes=$cl"
  body="$(printf '%s\n%s\n%s' "상시 승인 D3 켜짐: 위험 낮은 병합은 팀장이 바로 해요" "혼자 해도 되는 것: $(d3_plain "$cl")(DA 없이 · 범위 승인 건수를 안 써요)" \
    "언제까지: 멈춤(standing-stop D3) 전까지 · 코드 PR 은 D2 · 비밀·파괴 줄이 있으면 거절")"
  ts="$(scope_slack_post "$body")" || exit $?   # 게시 «먼저» — 실패면 쓰기 0
  mkdir -p "$D3" || std_wfail "$D3"
  printf '%s\tslack_ts=%s\n' "$line" "$ts" >> "$D3/grants.audit" || std_wfail "$D3/grants.audit"
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-GRANTED D3 repos=$rp classes=$cl slack_ts=$ts"
}
d3_seat() {  # 쓰기 좌석 = 그 팀 master 만(team-master-seat 통과) — desk·자율 ON full 갈래 0(DA R1) · 실제 좌석(TMUX_PANE) · SELFTEST env 는 env -u 로 지운다
  local dx="$HERE/ft_doc_exempt.py"; [ -f "$dx" ] || std_err "좌석 판정 모듈 없음: $dx"
  std_roster_root
  std_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3 "$dx" --mode team-master-seat --repo "$ROOT" --root "$STD_ROOT"
  [ "$RC" = 0 ] && [[ "$FIRST" =~ ^TEAM-MASTER-SEAT\ ([A-Za-z0-9#_-]+) ]] || std_err "ⓑ 팀 master 좌석만(D3 · desk 포함 그 밖 좌석 0) rc=$RC ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  D3_BY="${BASH_REMATCH[1]}"
}
d3_is_test() {  # <경로> — 시험 파일 = 경로 칸에 tests/ ∧ 이름 test_*.sh|test_*.py|*.test.ts|*.spec.ts
  [[ "/$1" == */tests/* ]] || return 1
  case "${1##*/}" in test_*.sh|test_*.py|*.test.ts|*.spec.ts) return 0 ;; esac; return 1
}
d3_all_tests() {  # <head> — merge-base..head 바뀐 파일 «전부» 시험 파일이면 rc0 · 확인 실패 = 거절
  local base p n=0
  std_t7 git -C "$D2_REPO" merge-base "refs/remotes/origin/$D2_TARGET" "$1"; [ "$RC" = 0 ] || std_err "② 시험 파일 판정 merge-base 실패 rc=$RC: $FIRST"; base="$FIRST"
  std_t7 git -C "$D2_REPO" diff --name-only --no-renames "$base" "$1"; [ "$RC" = 0 ] || std_err "② 시험 파일 판정 diff 실패 rc=$RC: $FIRST"
  while IFS= read -r p; do [ -n "$p" ] || continue; n=$((n+1)); d3_is_test "$p" || return 1; done <<<"$OUT"
  [ "$n" -gt 0 ]
}
d3_classify() {  # ② <head> → D3_CLS — 분류기(scope 와 같은 표) · FORBID·ERROR·시간 초과 = 거절 · revert = 범위 밖
  local cls="${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" a=() t k; [ -f "$cls" ] || std_err "분류기 없음: $cls"
  if [ "$D2_RK" = pack ]; then t="${FT_SCOPE_PACK_TABLE:-$(tpl_file scope-classes-pack.tsv)}" || std_err "② 팩 분류표 없음(templates/scope-classes-pack.tsv)"; a+=(--table "$t")
  elif t="${FT_SCOPE_DDL_RECORDS:-$(tpl_file scope-ddl-record.tsv)}"; then a+=(--ddl-records "$t"); fi
  std_t7 python3 "$cls" classify "$1" --repo "$D2_REPO" --remote origin --target "$D2_TARGET" --scope S0 "${a[@]}"
  [ "$RC" = 0 ] || std_err "② 분류기 거절 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [[ "$FIRST" =~ ^CLASS\ (docs|ff|code)$ ]] || std_err "② 종류가 docs·ff·code 아님: $FIRST"
  k="${BASH_REMATCH[1]}"
  if [ "$k" = code ]; then d3_all_tests "$1" || std_err "② 코드 PR 인데 바뀐 파일이 전부 시험 파일은 아님 — 코드 PR 은 D2"; k=test; fi
  case ",$D3_CLASSES," in *",$k,"*) ;; *) std_err "② 종류 $k 는 상시 승인 범위(classes=$D3_CLASSES) 밖" ;; esac
  D3_CLS="$k"
}
d3_critical() {  # ③ <head> — --critical(기본 profile full) = CRITICAL-OK 만 · 판정 못 함 = 거절(닫힌 쪽)
  std_t7 python3 "${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" classify "$1" --repo "$D2_REPO" --remote origin --target "$D2_TARGET" --critical
  [ "$RC" = 0 ] && [ "$FIRST" = CRITICAL-OK ] && return 0
  [[ "$FIRST" =~ ^CRITICAL\ kind=([a-z]+)\ (.*)$ ]] && std_err "③ 크리티컬: ${BASH_REMATCH[1]} — ${BASH_REMATCH[2]}"
  std_err "③ 크리티컬 판정 실패 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
}
d3_write() {  # <head> <pr> — log(standing-use → approve-merge) 먼저 · 승인 파일 · 원장 나중 · scope-use 0(셈 변화 0)
  local now line dir="$STATE/autonomy-merge-approved"; now="$(now_epoch)"; line="approve-merge $1 D3 $now"
  mkdir -p "$dir" "$D3" || std_wfail "$dir"
  amt_write "$1" "$D2_TARGET" || std_wfail "$STATE/autonomy-merge-target/$1"   # r1955 — 승인 쓰기 «앞»
  printf 'standing-use D3 %s %s pr=%s repo=%s class=%s\n' "$1" "$now" "$2" "$D2_RK" "$D3_CLS" >> "$LOG" || std_wfail log
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  { printf '%s\n' "$line" > "$dir/$1.tmp" && mv "$dir/$1.tmp" "$dir/$1"; } || std_wfail "$dir/$1"
  printf '%s\t%s\t%s\tclass=%s\trepo=%s\t\t\n' "$now" "$1" "$2" "$D3_CLS" "$D2_RK" >> "$D3/D3.ledger.tsv" || std_wfail "$D3/D3.ledger.tsv"
  echo "STANDING-OK $1 pr=$2 repo=$D2_RK class=$D3_CLS by=$D3_BY"
}
cmd_standing_approve() {
  local d="${1:-}" head pr="" rk="" D2_TARGET=main m u="usage: standing-approve D3 <head40> --pr <N> --repo byz|pack"
  [ "$d" = D3 ] || std_usage "$u"
  shift; head="${1:-}"; [[ "$head" =~ ^[0-9a-f]{40}$ ]] || std_usage "sha 형식 틀림(40hex 소문자): $head ($u)"
  STD_SHA="$head"; shift
  while [ $# -gt 0 ]; do [ $# -ge 2 ] || std_err "$1 값 없음"; case "$1" in --pr) [[ "$2" =~ ^[0-9]+$ ]] || std_err "--pr 값 틀림: $2"; pr="$2" ;;
    --repo) rk="$2" ;; *) std_err "알 수 없는 인자: $1" ;; esac; shift 2; done
  [ -n "$pr" ] || std_err "--pr 필수"
  d3_seat
  lock; [ "$(mode)" = tamper ] && std_err "자율 상태 위변조(tamper) — 승인 기록 없음"
  d3_on || std_err "① 상시 승인 D3 꺼짐(approve-standing D3 줄 없음 또는 standing-stop 뒤)"
  D2_REPOS="$D3_REPOS"; d2_repo "$rk"; D2_TARGET="$(autonomy_pr_target "$D2_REPO" "$pr" "$rk")" || std_err "$D2_TARGET"   # ④ --repo ⊆ repos(D2 와 같은 함수)
  if grep -q "^standing-use D3 $head " "$LOG" 2>/dev/null; then m="$(amt_same "$head" "$D2_TARGET")" || std_err "$m"; echo "STANDING-NOOP $head (이미 상시 승인함)"; return 0; fi
  d3_classify "$head"; d3_critical "$head"
  d3_write "$head" "$pr"
}
cmd_standing_stop() {
  local d="${1:-}" r="${2:-}"
  [ "$d" = D3 ] && [ -n "${r//[[:space:]]/}" ] || std_usage 'usage: standing-stop D3 "<사유>"'
  lock; grep -q '^approve-standing D3 ' "$LOG" 2>/dev/null || std_usage "그런 상시 승인 없음: D3"
  d3_on || { unlock; echo "STANDING-STOPPED D3 (이미 꺼짐)"; return 0; }; r="${r//[$'\t\n\r']/ }"
  printf 'standing-stop D3 %s %s\n' "$(now_epoch)" "$r" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-STOPPED D3: $r"
}
