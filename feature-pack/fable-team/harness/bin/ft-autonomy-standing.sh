#!/usr/bin/env bash
# ft-autonomy-standing.sh — 외부 DA APPROVE 팩 PR «상시 승인» D1 4명령 (r947 · 오빠 D1 mbox 169402) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   approve-standing D1 --repos pack --classes code,docs   오빠 `!` 전용(autonomy-state-guard 가 좌석 실행을 막는다) · 자율 모드 무관 · 끝 시각 없음(멈춤 = standing-stop)
#       슬랙 «켜짐 알림» 1글(사람 말 3줄 · scope_slack_post 재사용) 게시 «먼저» → grants.audit(+슬랙 ts) → log `approve-standing D1 <epoch> repos=pack classes=<…> da=external`
#   standing-approve <head40> --pr <N> --repo pack --verdict <판정문.md>   planner master 좌석만(ft_doc_exempt.py --mode planner-seat = 문서 전용 예외와 같은 좌석 함수)
#       ①D1 켜짐(마지막 approve-standing 이 마지막 standing-stop 뒤) ②팩 분류표 forbid 0 ∧ 종류 ∈ classes ③판정문이 BYZ origin/main 에 있음 — 읽는 값도 origin/main 의 blob
#       ④판정문 4줄 `승인 sha: <A>` · `DA 원문: <절대경로>` · `DA 원문 sha256: <64hex>` · `격리: 세트 <A> · rc=0` (각 정확히 1줄) ∧ 로컬 DA 원문 sha256 = 판정문 값
#       ⑤DA 원문 마지막 `codex` 블록 첫 줄 ∧ 그 블록의 마지막 `판정:` 줄 = `판정: APPROVE` · <원문>.meta head=A rc=0 · model 이 claude 계열 아님 ⑥head=A 또는 ft-approval-equiv A head EQUIV
#       통과 = log `standing-use D1 <head> <epoch> pr=<N> repo=pack da=<A>` → `approve-merge <head> D1 <epoch>` → 승인 파일 → 원장 1행 · 거절 = rc2 · 쓰기 0 · 끝줄 «다시: 오빠 h(approve-merge)»
#   standing-stop D1 "<사유>"   누구나 · standing-status [--since <epoch>]   읽기(켜짐 여부 + 그 뒤 원장 행을 사람 말 1덩이로)
# 원장 $STATE/autonomy-standing/D1.ledger.tsv 7칸 = 시각·head·PR·da=<A>·DA 원문 경로·착지 sha·되돌림 명령(뒤 둘 = ft-merge-land 가 채운다 · scope 원장과 같은 칸 번호)
# 도구 호출마다 7초 상한(판정 666) · 외부 호출 = 슬랙 게시 1(approve-standing)뿐 · 한계: 같은 uid 의 직접 쓰기는 scope 와 같다(판정 2078 ⓐ — 슬랙 1글 + grants.audit 로 들킨다)
STD="$STATE/autonomy-standing"
. "$HERE/ft-autonomy-scope.sh"   # scope_slack_post · scope_class_plain 재사용(사본 0)

std_usage() { echo "STANDING-REJECT $1" >&2; exit 2; }
std_err() { echo "STANDING-REJECT $1" >&2; echo "다시: 오빠 h(approve-merge ${STD_SHA:-<sha>}) — 상시 승인 길을 못 지나면 건마다 승인" >&2; exit 2; }
std_wfail() { echo "REJECT $1 쓰기 실패" >&2; exit 1; }
std_t7() { OUT="$(perl -e 'alarm 7; exec @ARGV' -- "$@" 2>&1)"; RC=$?; FIRST="${OUT%%$'\n'*}"; }   # 도구 1회 7초 — 넘으면 rc≠0 = 거절 쪽

std_on() {  # rc0 = 마지막 approve-standing 줄(꼴 맞음)이 마지막 standing-stop 줄보다 뒤 → STD_LINE · STD_CLASSES
  local g s; g="$(grep -n '^approve-standing D1 ' "$LOG" 2>/dev/null | tail -1)"; s="$(grep -n '^standing-stop D1 ' "$LOG" 2>/dev/null | tail -1)"
  [ -n "$g" ] || return 1
  STD_LINE="${g#*:}"; [[ "$STD_LINE" =~ $STANDING_GRANT_RE ]] || return 1
  STD_CLASSES="${STD_LINE#*classes=}"; STD_CLASSES="${STD_CLASSES%% *}"
  [ -z "$s" ] || [ "${g%%:*}" -gt "${s%%:*}" ]
}

std_plain() {  # <classes> → «코드 병합 · 문서 병합»
  local c w out="" sep=""
  for c in ${1//,/ }; do w="$(scope_class_plain "$c")" || return 1; out="$out$sep$w"; sep=" · "; done
  printf '%s' "$out"
}

cmd_approve_standing() {
  local d="${1:-}" rp="" cl="" c seen="," now body ts line; [ $# -gt 0 ] && shift
  [ "$d" = D1 ] || std_usage "usage: approve-standing D1 --repos pack --classes code,docs"
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || std_usage "$1 값 없음"
    case "$1" in --repos) rp="$2" ;; --classes) cl="$2" ;; *) std_usage "알 수 없는 인자: $1" ;; esac; shift 2
  done
  [ "$rp" = pack ] || std_usage "--repos 는 pack 만(D1 = 팩 PR · 받은 값: ${rp:-없음})"
  [[ "$cl" =~ ^(code|docs)(,(code|docs))?$ ]] || std_usage "--classes 는 code·docs 중 1~2개(받은 값: ${cl:-없음})"
  for c in ${cl//,/ }; do case "$seen" in *",$c,"*) std_usage "종류 중복: $c" ;; esac; seen="$seen$c,"; done
  lock; [ "$(mode)" = tamper ] && std_usage "자율 상태 위변조(tamper) — 상시 승인 기록 없음"
  if std_on; then unlock; echo "STANDING-NOOP D1 이미 켜짐($STD_LINE)"; return 0; fi
  now="$(now_epoch)"; line="approve-standing D1 $now repos=pack classes=$cl da=external"
  body="$(printf '%s\n%s\n%s' "상시 승인 켜짐: 외부 DA 가 승인한 팩 PR 은 planner 가 바로 착지해요" \
    "혼자 해도 되는 것: 팩 $(std_plain "$cl")(외부 DA 승인 + 격리 시험 통과만 · 착지는 뒤에 묶어서 알려요)" "언제까지: 멈춤(standing-stop) 전까지")"
  ts="$(scope_slack_post "$body")" || exit $?   # 게시 «먼저» — 실패면 쓰기 0
  mkdir -p "$STD" || std_wfail "$STD"
  printf '%s\tslack_ts=%s\n' "$line" "$ts" >> "$STD/grants.audit" || std_wfail "$STD/grants.audit"
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-GRANTED D1 repos=pack classes=$cl slack_ts=$ts"
}

std_seat() {  # ⓓ planner master 좌석만 — 실제 좌석(TMUX_PANE) · 명부 루트 출처 · 이름 lint (SELFTEST env 는 env -u 로 지운다)
  local dx="$HERE/ft_doc_exempt.py"; [ -f "$dx" ] || std_err "좌석 판정 모듈 없음: $dx"
  std_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3 "$dx" --mode planner-seat --repo "$ROOT" --root "$ROOT"
  [ "$RC" = 0 ] && [[ "$FIRST" =~ ^PLANNER-SEAT\ ([A-Za-z0-9#_-]+)$ ]] || std_err "ⓓ planner master 좌석만 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  STD_BY="${BASH_REMATCH[1]}"
}

std_classify() {  # ② <head> — 팩 분류표(scope 와 같은 분류기·표) · FORBID·실패 = 거절 · 종류 ∈ 승인 줄 classes
  local cls="${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" t k runner h
  h="$(. "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE")" && PREPO="$(git -C "$h" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$PREPO" ] \
    || std_err "팩 리포를 못 풂(FT_HARNESS_ROOT · <bin>/../HARNESS_ROOT)"
  t="${FT_SCOPE_PACK_TABLE:-$(tpl_file scope-classes-pack.tsv)}" || std_err "팩 분류표 없음(templates/scope-classes-pack.tsv)"
  [ -f "$cls" ] || std_err "분류기 없음: $cls"
  if [[ "$cls" == *.py ]]; then runner=(python3 "$cls"); else runner=("$BASH" "$cls"); fi
  std_t7 "${runner[@]}" classify "$1" --repo "$PREPO" --remote origin --target main --scope S0 --table "$t"
  [ "$RC" = 0 ] || std_err "② 분류기 거절 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [[ "$FIRST" =~ ^CLASS\ (docs|ff|code)$ ]] || std_err "② 종류가 code·docs 아님: $FIRST"
  k="${BASH_REMATCH[1]}"; [ "$k" != ff ] || k=docs   # ff = 문서만 바뀌고 main 이 head 의 조상(분류기 docs 의 한 꼴)
  case ",$STD_CLASSES," in *",$k,"*) ;; *) std_err "② 종류 $k 는 상시 승인 범위(classes=$STD_CLASSES) 밖" ;; esac
}

std_field() {  # <변수> <본문> <키> <값 정규식(괄호 1개)> — 정확히 1줄만(0·2+ = 거절) · 목록 기호(- *) 허용
  local n re="^[-*]?[[:space:]]*$3[[:space:]]*$4[[:space:]]*$"
  n="$(grep -cE "$re" <<<"$2")"; [ "$n" = 1 ] || std_err "④ 판정문 «$3» 줄이 ${n:-0}개(정확히 1줄)"
  printf -v "$1" '%s' "$(sed -nE "s#$re#\\1#p" <<<"$2")"
}

std_common() { local c; c="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && (cd "$c" && pwd -P); }   # 같은 리포(워크트리 포함) 판정

std_verdict() {  # ③④ <판정문> → V_A V_OUT
  local f="$1" d rel body sum got iso
  [ -f "$f" ] || std_err "③ 판정문 없음: $f"
  d="$(cd "$(dirname "$f")" && pwd -P)" || std_err "③ 판정문 폴더를 못 엶: $f"
  [ "$(std_common "$d")" = "$(std_common "$ROOT")" ] && [ -n "$(std_common "$ROOT")" ] \
    || std_err "③ 판정문이 BYZ 리포($ROOT) 파일이 아님: $f"
  rel="$(git -C "$d" rev-parse --show-prefix)$(basename "$f")"
  git -C "$ROOT" cat-file -e "refs/remotes/origin/main:$rel" 2>/dev/null || std_err "③ 판정문이 BYZ origin/main 에 없음(로컬만): $rel — 착지·git fetch 뒤 다시"
  body="$(git -C "$ROOT" show "refs/remotes/origin/main:$rel")"   # 읽는 값 = origin/main 의 blob(로컬 사본을 바꿔도 못 바꾼다)
  std_field V_A "$body" '승인 sha:' '([0-9a-f]{40})'
  std_field V_OUT "$body" 'DA 원문:' '(/[^[:space:]]+)'
  std_field sum "$body" 'DA 원문 sha256:' '([0-9a-f]{64})'
  std_field iso "$body" '격리:' '(세트 [0-9a-f]{40} · rc=0)'
  [ "$iso" = "세트 $V_A · rc=0" ] || std_err "④ 격리 줄(${iso}) 의 세트 ≠ 승인 sha(${V_A:0:10})"
  [ -f "$V_OUT" ] || std_err "④ DA 원문 파일 없음: $V_OUT"
  got="$({ shasum -a 256 "$V_OUT" 2>/dev/null || sha256sum "$V_OUT"; } | awk '{print $1}')"
  [ "$got" = "$sum" ] || std_err "④ DA 원문 sha256(${got:0:12}) ≠ 판정문 값(${sum:0:12}) — 판정 뒤 원문이 바뀜"
}

std_da_out() {  # ⑤ <원문> <A> — 마지막 codex 블록만 본다(앞 블록·입력 파일 메아리의 APPROVE 는 안 센다)
  local f="$1" r m line lm
  r="$(awk '/^codex[[:space:]]*$/ {c=NR; first=""; last=""; next} c && first=="" && NF {first=$0} c && /^판정:/ {last=$0}
    END {if (!c) exit 3; sub(/[ \t\r]+$/, "", first); sub(/[ \t\r]+$/, "", last); print first "\t" last}' "$f")" || std_err "⑤ DA 원문에 codex 블록 없음: $f"
  [ "$r" = $'판정: APPROVE\t판정: APPROVE' ] || std_err "⑤ DA 마지막 codex 블록이 APPROVE 아님(첫 줄·끝 판정 줄: ${r//$'\t'/ | })"
  m="$f.meta"; line="$(head -n1 "$m" 2>/dev/null)"
  [[ "$line" =~ ^head=([0-9a-f]{40}|none)\ model=([^[:space:]]+)\ effort=[^[:space:]]+\ rc=([0-9]+)\ start=[0-9]+\ end=[0-9]+$ ]] || std_err "⑤ DA 원문 .meta 없음·꼴 틀림: $m"
  [ "${BASH_REMATCH[1]}" = "$2" ] || std_err "⑤ .meta head(${BASH_REMATCH[1]:0:10}) ≠ 승인 sha(${2:0:10}) — DA 가 본 sha 가 다르다"
  [ "${BASH_REMATCH[3]}" = 0 ] || std_err "⑤ DA rc=${BASH_REMATCH[3]}(0 아님)"
  lm="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
  case "$lm" in *claude*|*anthropic*|*opus*|*sonnet*|*haiku*|*fable*) std_err "⑤ DA 모델 ${BASH_REMATCH[2]} = claude 계열(외부 DA 아님)" ;; esac
}

std_equiv() {  # ⑥ <A> <head> — 같으면 통과 · 다르면 A 위 main 병합만(EQUIV rc0)일 때만
  STD_EQ=""; [ "$1" = "$2" ] && return 0
  [ -f "$HERE/ft-approval-equiv.sh" ] || std_err "동일 승인 판정기 없음: $HERE/ft-approval-equiv.sh"
  std_t7 "$BASH" "$HERE/ft-approval-equiv.sh" "$1" "$2" --repo "$PREPO"
  [ "$RC" = 0 ] && [[ "$FIRST" == EQUIV\ * ]] || std_err "⑥ head ≠ 승인 sha(${1:0:10}) — 동일 승인 아님 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  STD_EQ="$1"
}

std_write() {  # <head> <pr> <A> <원문> — log(standing-use → approve-merge) 먼저 · 승인 파일 · 원장 나중
  local now line dir="$STATE/autonomy-merge-approved"; now="$(now_epoch)"; line="approve-merge $1 D1 $now"
  mkdir -p "$dir" "$STD" || std_wfail "$dir"
  printf 'standing-use D1 %s %s pr=%s repo=pack da=%s\n' "$1" "$now" "$2" "$3" >> "$LOG" || std_wfail log
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  { printf '%s\n' "$line" > "$dir/$1.tmp" && mv "$dir/$1.tmp" "$dir/$1"; } || std_wfail "$dir/$1"
  printf '%s\t%s\t%s\tda=%s\t%s\t\t\n' "$now" "$1" "$2" "$3" "$4" >> "$STD/D1.ledger.tsv" || std_wfail "$STD/D1.ledger.tsv"
  echo "STANDING-OK $1 pr=$2 repo=pack da=$3${STD_EQ:+ equiv=$STD_EQ} by=$STD_BY"
}

cmd_standing_approve() {
  local head="${1:-}" pr="" rk="" vf=""
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || std_usage "sha 형식 틀림(40hex 소문자): $head (usage: standing-approve <head40> --pr <N> --repo pack --verdict <판정문.md>)"
  STD_SHA="$head"; shift
  while [ $# -gt 0 ]; do [ $# -ge 2 ] || std_err "$1 값 없음"; case "$1" in
    --pr) [[ "$2" =~ ^[0-9]+$ ]] || std_err "--pr 값 틀림: $2"; pr="$2" ;;
    --repo) rk="$2" ;; --verdict) vf="$2" ;; *) std_err "알 수 없는 인자: $1" ;; esac; shift 2; done
  [ -n "$pr" ] && [ -n "$vf" ] || std_err "--pr 와 --verdict 필수"
  [ "$rk" = pack ] || std_err "--repo 는 pack 만(D1 = 팩 PR · 받은 값: ${rk:-없음})"
  std_seat
  lock; [ "$(mode)" = tamper ] && std_err "자율 상태 위변조(tamper) — 승인 기록 없음"
  std_on || std_err "① 상시 승인 D1 꺼짐(approve-standing 줄 없음 또는 standing-stop 뒤)"
  if grep -q "^standing-use D1 $head " "$LOG" 2>/dev/null; then echo "STANDING-NOOP $head (이미 상시 승인함)"; return 0; fi
  std_classify "$head"; std_verdict "$vf"; std_da_out "$V_OUT" "$V_A"; std_equiv "$V_A" "$head"
  std_write "$head" "$pr" "$V_A" "$V_OUT"
}

cmd_standing_stop() {
  local d="${1:-}" r="${2:-}"
  [ "$d" = D1 ] && [ -n "${r//[[:space:]]/}" ] || std_usage 'usage: standing-stop D1 "<사유>"'
  lock; grep -q '^approve-standing D1 ' "$LOG" 2>/dev/null || std_usage "그런 상시 승인 없음: D1"
  std_on || { unlock; echo "STANDING-STOPPED D1 (이미 꺼짐)"; return 0; }
  r="${r//[$'\t\n\r']/ }"; printf 'standing-stop D1 %s %s\n' "$(now_epoch)" "$r" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-STOPPED D1: $r"
}

std_digest() {  # <since> — 원장 행(시각 ≥ since) → 사람 말 1덩이
  [ -f "$STD/D1.ledger.tsv" ] || { echo "그 뒤 외부 DA 승인으로 바로 착지한 팩 PR 은 없어요."; return 0; }
  awk -F'\t' -v s="$1" '$1 >= s+0 {n++; l = l sprintf("- 팩 PR #%s · %s · 되돌림: %s\n", $3, ($6 == "" ? "아직 착지 전" : "착지 " substr($6, 1, 10)), ($7 == "" ? "착지 뒤에 생겨요" : $7))}
    END {if (!n) {print "그 뒤 외부 DA 승인으로 바로 착지한 팩 PR 은 없어요."; exit} printf "외부 DA 승인으로 바로 착지한 팩 PR %d건이에요.\n%s", n, l}' "$STD/D1.ledger.tsv"
}

cmd_standing_status() {
  local since=""
  case "${1:-}" in
    "") ;; --since) [[ "${2:-}" =~ ^[0-9]+$ ]] || std_usage "--since <epoch>"; since="$2" ;;
    *) std_usage "usage: standing-status [--since <epoch>]" ;;
  esac
  if std_on; then echo "[상시 승인 D1 켜짐 · 팩 $(std_plain "$STD_CLASSES") · 외부 DA 승인 + 격리 시험 통과만]"; else echo "[상시 승인 D1 꺼짐]"; fi
  [ -z "$since" ] || std_digest "$since"
}
