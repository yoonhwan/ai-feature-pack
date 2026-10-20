#!/usr/bin/env bash
# ft-autonomy-scope.sh — 오빠 부재 중 병합 «범위 사전 승인» 4명령 (R298 1/3 · 판정 2055 · 카드 r298a-away-scope-grant) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   approve-scope --for <N>h --max <n> [--daily <n>] --classes <docs,ff,revert[,code]> [--code-max <n>] [--repos byz|byz,pack]  오빠 `!` 전용 — 기간·건수·종류를 «한 번» 정한다(code 는 --code-max 1~max 필수 · R411 판정 2326)
#   scope-approve <40hex> [--pr <N>] [--card <카드.md>] [--repo byz|pack]   좌석 허용 — 범위 대조만(분류기 = r298b autonomy_scope_classify.py) · 통과하면 기존 형식 `approve-merge` 줄을 대신 쓴다 · 종류 code 는 --card 의 시험 통과 세트만(ft-autonomy-scope-code.sh)
#   r466: 승인 줄 끝 선택 칸 `repos=byz,pack`(팩 PR 허용 · 팩 분류표) · `level=full|mid`(ft-autonomy.sh on --level 이 쓴다 — 사건 번호가 바뀌어도 지금 ON 의 레벨이 같으면 scope-approve 가 재발급 SCOPE-RENEWED)
#         FORBID kind=<키> = 거절 원장 denied.tsv 1행 · 레벨 full 이면 학습표(learned-kinds.tsv)의 종류는 분류기가 docs 로 통과(`learned=<키>`)
#   scope-stop S<n> "<사유>"            좌석 허용 — 누구나 멈춘다 · 다시 켜기 = 오빠의 새 approve-scope 뿐
#   scope-status                       읽기 — `[범위 승인 S3 · A7 · ~03:10까지 · 4/20 · 오늘 2/10 · docs,ff,revert]`
#   scope-status --audit               읽기 — log grant 줄 ↔ grants.audit(슬랙 ts 포함) 대조 + 승인 파일 수 ≥ scope-use 수 · 어긋나면 `AUDIT-MISMATCH …` rc 3
# ★한계(판정 2078 ⓐ)★ 같은 uid 의 직접 쓰기(log 에 grant 줄 덧붙이기·scope-use 줄 지우기)는 막지 못한다 — approve-scope 의 슬랙 1줄 + --audit 대조로 «들킨다».
#   r560: 같은 범위 원장에 이미 센 승인 A 가 새 sha 의 EQUIV(판정기 rc0)면 원장 줄 종류 `equiv` · used·today 증가 0 · 출력 `equiv=<A>`(재승인은 범위 한도 비차감 — 하루 한도 15 중 9 소진 사건)
# 상태 원천 = autonomy.log 한 곳(추가 전용 · 쓰기는 ft-autonomy.sh 의 lock 안 · json 카운터 0) — 건수는 `scope-use` 줄을 센다(종류 revert·equiv 는 안 센다).
# 원장 `$STATE/autonomy-scope/S<n>.ledger.tsv` 7칸 = 시각·sha·PR·종류·판정문(빈칸)·착지 sha(빈칸 — r298b 가 6번째 칸을 채운다)·되돌림 명령(빈칸)
# 외부 호출 0 — 분류기는 로컬 git 뿐 · 7초 상한(넘으면 REJECT · 판정 666).
SDIR="$STATE/autonomy-scope"
. "$HERE/ft-autonomy-scope-code.sh"

scope_err() { echo "SCOPE-REJECT $1" >&2; exit 2; }
scope_wfail() { echo "REJECT $1 쓰기 실패" >&2; exit 1; }

scope_load() {  # 마지막 approve-scope 줄 → G_S G_A G_UNTIL G_MAX G_DAILY G_CLASSES G_CODEMAX(옛 줄 = 0) G_REPOS(옛 줄 = byz) G_LEVEL(옛 줄 = 빈 값) (rc 1 = 없음·꼴 틀림)
  local line a u m d c rest t; line="$(grep '^approve-scope ' "$LOG" 2>/dev/null | tail -1)"
  [[ "$line" =~ $SCOPE_GRANT_RE ]] || return 1
  read -r a G_S G_A G_AT u m d c rest <<<"$line"
  G_UNTIL="${u#until=}"; G_MAX="${m#max=}"; G_DAILY="${d#daily=}"; G_CLASSES="${c#classes=}"; G_CODEMAX=0; G_REPOS=byz; G_LEVEL=""
  for t in $rest; do case "$t" in codemax=*) G_CODEMAX="${t#codemax=}" ;; repos=*) G_REPOS="${t#repos=}" ;; level=*) G_LEVEL="${t#level=}" ;; esac; done
}

scope_validate() {  # <max> <daily|""> <classes> <codemax|""> <repos> → SV_MX SV_DL SV_CL SV_CM(0 = 없음) SV_REPOS · 틀리면 SCOPE-REJECT rc 2(쓰기 0)
  local mx="$1" dl="$2" cl="$3" cm="$4" c seen=","
  [[ "$mx" =~ ^[0-9]+$ ]] && mx=$((10#$mx)) && [ "$mx" -ge 1 ] && [ "$mx" -le 30 ] || scope_err "--max 는 1~30(받은 값: ${mx:-없음})"
  if [ -z "$dl" ]; then dl=10; [ "$dl" -le "$mx" ] || dl="$mx"; fi
  [[ "$dl" =~ ^[0-9]+$ ]] && dl=$((10#$dl)) && [ "$dl" -ge 1 ] && [ "$dl" -le "$mx" ] || scope_err "--daily 는 1~max($mx)(받은 값: $dl)"
  [ -n "$cl" ] || scope_err "--classes 없음"
  for c in ${cl//,/ }; do
    case "$c" in
      docs|ff|revert|code) case "$seen" in *",$c,"*) scope_err "종류 중복: $c" ;; esac; seen="$seen$c," ;;
      *) scope_err "알 수 없는 종류: $c (docs·ff·revert·code 만)" ;;
    esac
  done
  [[ "$cl" != ,* && "$cl" != *, && "$cl" != *,,* ]] || scope_err "--classes 형식 틀림: $cl"
  if [[ "$seen" == *",code,"* ]]; then   # code = 시험 통과 세트만 · 건수 상한 필수(판정 2326) — 기본 닫힘
    [[ "$cm" =~ ^[0-9]+$ ]] && cm=$((10#$cm)) && [ "$cm" -ge 1 ] && [ "$cm" -le "$mx" ] || scope_err "종류 code 는 --code-max 1~max($mx) 필수(받은 값: ${cm:-없음})"
  else [ -z "$cm" ] || [ "$cm" = 0 ] || scope_err "--code-max 는 --classes 에 code 가 있을 때만"; cm=0; fi
  case "$5" in byz|byz,pack) ;; *) scope_err "--repos 는 byz 또는 byz,pack(받은 값: $5)" ;; esac
  SV_MX="$mx"; SV_DL="$dl"; SV_CL="$cl"; SV_CM="$cm"; SV_REPOS="$5"
}

scope_grant_post() {  # <A> <부여 epoch> <until> <max> <daily> <classes> <codemax> <repos> <level|""> — 잠금 안 · 슬랙 게시 «먼저»(실패 = rc 1 · 쓰기 0) → GR_N GR_LINE GR_TS
  local n tail=""; n="$(grep -c '^approve-scope ' "$LOG" 2>/dev/null)"; GR_N="S$(( ${n:-0} + 1 ))"
  [ "$7" -gt 0 ] && tail=" codemax=$7"; [ "$8" = byz ] || tail="$tail repos=$8"; [ -z "$9" ] || tail="$tail level=$9"
  GR_LINE="approve-scope $GR_N $1 $2 until=$3 max=$4 daily=$5 classes=$6$tail"
  GR_TS="$(scope_slack_post "[범위 승인] $GR_N · $1 · ~$(hhmm "$3")까지 · max $4 · 하루 $5 · $6$([ "$7" -gt 0 ] && echo " · code $7")$([ "$8" = byz ] || echo " · 저장소 $8")$([ -z "$9" ] || echo " · 레벨 $9") · 부여 $2")" || exit $?
}

scope_grant_write() {  # scope_grant_post 뒤 — grants.audit(같은 칸 + 슬랙 ts) 먼저, log 나중
  mkdir -p "$SDIR" || scope_wfail "$SDIR"
  printf '%s\tslack_ts=%s\n' "$(cut -d' ' -f2- <<<"$GR_LINE" | tr ' ' '\t')" "$GR_TS" >> "$SDIR/grants.audit" || scope_wfail "$SDIR/grants.audit"
  printf '%s\n' "$GR_LINE" >> "$LOG" || scope_wfail log
}

scope_stopped() { [ -f "$SDIR/$1.stopped" ] || grep -q "^scope-stop $1 " "$LOG" 2>/dev/null; }
scope_stop_reason() {  # <S> — log 의 마지막 stop 줄 사유(없으면 .stopped 파일)
  local r; r="$(grep "^scope-stop $1 " "$LOG" 2>/dev/null | tail -1 | cut -d' ' -f4-)"
  [ -n "$r" ] || r="$(head -1 "$SDIR/$1.stopped" 2>/dev/null)"; printf '%s' "$r"
}
scope_used() { awk -v s="$1" '$1=="scope-use" && $2==s && $4!="revert" && $4!="equiv" {n++} END{print n+0}' "$LOG" 2>/dev/null; }
scope_today() { awk -v s="$1" -v c="$(( $(now_epoch) - 86400 ))" '$1=="scope-use" && $2==s && $4!="revert" && $4!="equiv" && $5>c {n++} END{print n+0}' "$LOG" 2>/dev/null; }

scope_ledger_shas() {  # <S> → 이 범위 원장에 이미 센 승인 sha(최신순 · 중복 0) — 판정기 대조 후보
  [ -f "$SDIR/$1.ledger.tsv" ] || return 0
  awk -F'\t' '$2 ~ /^[0-9a-f]{40}$/ && !seen[$2]++ {a[NR]=$2} END {for (i=NR; i>0; i--) print a[i]}' "$SDIR/$1.ledger.tsv" 2>/dev/null
}

scope_equiv_sha() {  # <sha> → stdout = 이미 센 승인 A(EQUIV rc0) · 없으면 rc 1 · 판단 못 함 = rc 1(셈 그대로 = 증가 — #0 RULE)
  local a t0; t0="$(now_epoch)"
  for a in $(scope_ledger_shas "$G_S"); do
    [ "$a" = "$1" ] && continue
    [ $(( $(now_epoch) - t0 )) -lt 21 ] || break   # 판정기 7초 × 3 — 승인 한 건을 오래 붙잡지 않는다(판정 666)
    scope_code_tool ft-approval-equiv.sh "$a" "$1" --repo "${SCOPE_REPO:-$ROOT}"
    [ "$RC" = 0 ] && [[ "$FIRST" == EQUIV\ * ]] && { printf '%s' "$a"; return 0; }
  done
  return 1
}

scope_write_stop() {  # <S> <사유> — log 먼저, .stopped 나중. 사유의 탭·개행은 공백으로
  local r="${2//[$'\t\n\r']/ }"; [ -n "${r//[[:space:]]/}" ] || r="사유 없음"
  mkdir -p "$SDIR" || scope_wfail "$SDIR"
  printf 'scope-stop %s %s %s\n' "$1" "$(now_epoch)" "$r" >> "$LOG" || scope_wfail log
  printf '%s\n' "$r" > "$SDIR/$1.stopped" || scope_wfail "$SDIR/$1.stopped"
}

scope_block() {  # scope_load 뒤 — 막는 사유를 BLOCK 에 · 스스로 정지를 써야 하는 사유(위변조·사건 번호·기간)면 AUTOSTOP=1
  local m ev; BLOCK=""; AUTOSTOP=0; RENEW=0; m="$(mode)"; ev="$(event)"
  if scope_stopped "$G_S"; then BLOCK="$(scope_stop_reason "$G_S")"
  elif [ "$m" = tamper ]; then BLOCK="위변조 → OFF"; AUTOSTOP=1
  elif [ "$m" != on ]; then BLOCK="자율 모드 OFF"
  elif [ "$ev" != "$G_A" ]; then   # r466: 레벨 줄(full·mid) ∧ 지금 ON 의 레벨이 같으면 정지 대신 재발급(scope-approve 가 잠금 안에서)
    BLOCK="사건 번호 바뀜(${G_A}→${ev})"
    if [[ "$G_LEVEL" == full || "$G_LEVEL" == mid ]] && [ "$(jfield level)" = "$G_LEVEL" ]; then RENEW=1; BLOCK="$BLOCK · 레벨 $G_LEVEL 재발급 대상"; else AUTOSTOP=1; fi
  elif [ "$(now_epoch)" -ge "$G_UNTIL" ]; then BLOCK="기간 끝 도달 $(hhmm "$G_UNTIL")"; AUTOSTOP=1
  fi
}

scope_renew() {  # 잠금 안 · RENEW=1 일 때 — 같은 max·daily·classes·codemax·repos·level 로 S<n+1> A<지금> 1줄(until = 지금 ON 의 끝 · 끝 없음 = 24h)
  local ev now un; ev="$(event)"; now="$(now_epoch)"; un="$(jfield until)"; [[ "$un" =~ ^[0-9]+$ ]] || un=$(( now + 86400 ))
  scope_grant_post "$ev" "$now" "$un" "$G_MAX" "$G_DAILY" "$G_CLASSES" "$G_CODEMAX" "$G_REPOS" "$G_LEVEL"; scope_grant_write
  echo "SCOPE-RENEWED $GR_N $ev level=$G_LEVEL (옛 $G_S $G_A)" >&2
  scope_load; scope_block
}

scope_slack_post() {  # <본문> → stdout = 슬랙 ts · 실패 = rc 1(호출자는 grant 쓰기 0 — 알림 없는 grant 는 만들지 않는다 · #0 RULE)
  local p="${FT_SCOPE_SLACK_POST:-$HERE/autonomy_scope_post.py}" out rc runner
  [ -f "$p" ] || { echo "SCOPE-REJECT 슬랙 게시 도구 없음: $p — grant 쓰기 0" >&2; exit 1; }
  if [[ "$p" == *.py ]]; then runner=(python3 "$p"); else runner=("$BASH" "$p"); fi
  out="$(perl -e 'alarm 9; exec @ARGV' -- "${runner[@]}" --text "$1" 2>&1)"; rc=$?   # 호출 상한 7초는 mirror_lib · alarm 9 는 멈춤 방지 안전망
  [ "$rc" = 0 ] && [[ "$out" =~ ^SLACK-TS\ ([0-9]+\.[0-9]+)$ ]] || { echo "SCOPE-REJECT 슬랙 게시 실패 rc=$rc: ${out%%$'\n'*} — grant 쓰기 0" >&2; exit 1; }
  printf '%s' "${BASH_REMATCH[1]}"
}

cmd_approve_scope() {
  local f="" mx="" dl="" cl="" cm="" rp=byz h now
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || scope_err "$1 값 없음 (usage: approve-scope --for <N>h --max <n> [--daily <n>] --classes <docs,ff,revert[,code]> [--code-max <n>] [--repos byz|byz,pack])"
    case "$1" in --for) f="$2" ;; --max) mx="$2" ;; --daily) dl="$2" ;; --classes) cl="$2" ;; --code-max) cm="$2" ;; --repos) rp="$2" ;; *) scope_err "알 수 없는 인자: $1" ;; esac
    shift 2
  done
  [[ "$f" =~ ^([0-9]+)h$ ]] && h=$((10#${BASH_REMATCH[1]})) && [ "$h" -ge 1 ] && [ "$h" -le 72 ] || scope_err "--for 는 1h~72h 형식(받은 값: ${f:-없음})"
  scope_validate "$mx" "$dl" "$cl" "$cm" "$rp"
  lock; [ "$(mode)" = on ] || scope_err "자율 모드가 ON 이 아님($(mode)) — 승인 기록 없음"
  now="$(now_epoch)"
  scope_grant_post "$(event)" "$now" "$(( now + h * 3600 ))" "$SV_MX" "$SV_DL" "$SV_CL" "$SV_CM" "$SV_REPOS" ""; scope_grant_write   # 게시 «먼저» — 실패면 쓰기 0
  unlock; scope_load; echo "SCOPE-GRANTED $G_S $G_A until=$(hhmm "$G_UNTIL") max=$G_MAX daily=$G_DAILY classes=$G_CLASSES${GR_LINE#*classes="$G_CLASSES"}"
}

scope_run_cls() {  # <하위명령> <sha|""> [분류 인자…] → OUT·RC·FIRST (분류기 r298b · 로컬 git 뿐 · 7초 상한 — 넘으면 rc≠0 = REJECT 쪽)
  local cls="${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" runner a=("$1"); [ -n "$2" ] && a+=("$2"); shift 2
  [ -f "$cls" ] || scope_err "분류기 없음: $cls"
  if [[ "$cls" == *.py ]]; then runner=(python3 "$cls"); else runner=("$BASH" "$cls"); fi
  OUT="$(perl -e 'alarm 7; exec @ARGV' -- "${runner[@]}" "${a[@]}" --repo "${SCOPE_REPO:-$ROOT}" --remote origin --target main --scope "$G_S" "$@" 2>&1)"; RC=$?
  FIRST="${OUT%%$'\n'*}"
}

scope_repo_set() {  # <byz|pack> → SCOPE_REPO(리포 절대경로) SCOPE_RK · pack = 하네스 코드 루트의 git 최상위(ft_harness_root) · 승인 줄 repos 밖 = REJECT
  SCOPE_RK="$1"; SCOPE_REPO="$ROOT"
  case "$1" in
    byz) ;;
    pack) local h; h="$(. "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE")" && SCOPE_REPO="$(git -C "$h" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$SCOPE_REPO" ] \
            || scope_err "팩 리포를 못 풂(FT_HARNESS_ROOT · <bin>/../HARNESS_ROOT)" ;;
    *) scope_err "--repo 는 byz 또는 pack(받은 값: $1)" ;;
  esac
  case ",$G_REPOS," in *",$1,"*) ;; *) scope_err "저장소 $1 은 승인 범위(repos=$G_REPOS) 밖" ;; esac
}

scope_learned_keys() {  # 레벨 full 승인 줄일 때만 학습표의 종류 키(쉼표) — 아니면 빈 값(mid·each·옛 줄 = 학습 0)
  [ "$G_LEVEL" = full ] || return 0
  awk -F'\t' 'NF>=1 && $1 ~ /^[a-z][a-z0-9-]*$/ {printf "%s%s", (n++ ? "," : ""), $1}' "$SDIR/learned-kinds.tsv" 2>/dev/null
}

scope_check_revert() {  # 분류 «전» 첫 단계 — rc 4(REVERTED …) = 정지 + REJECT · rc≠0 그 밖 = REJECT(닫힌 쪽) · rc 0 계속
  scope_run_cls check-revert ""
  [ "$RC" = 0 ] && return 0
  if [ "$RC" = 4 ]; then scope_write_stop "$G_S" "${FIRST:-REVERTED}"; scope_err "$G_S 정지: ${FIRST:-REVERTED}"; fi
  scope_err "되돌림 감지 실패 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
}

scope_classify() {  # <sha> → CLS(종류) CLS_LEARNED(학습 키 · 없으면 빈 값) · 실패 = REJECT(사유 그대로) · FORBID kind=<키> = 거절 원장 denied.tsv 1행 뒤 REJECT
  local a=() t lk; lk="$(scope_learned_keys)"
  if [ "$SCOPE_RK" = pack ]; then t="${FT_SCOPE_PACK_TABLE:-$(tpl_file scope-classes-pack.tsv)}" || scope_err "팩 분류표 없음(templates/scope-classes-pack.tsv)"; a+=(--table "$t")
  elif t="${FT_SCOPE_DDL_RECORDS:-$(tpl_file scope-ddl-record.tsv)}"; then a+=(--ddl-records "$t"); fi
  [ -z "$lk" ] || a+=(--learned "$lk")
  scope_run_cls classify "$1" "${a[@]}"
  if [ "$RC" = 3 ] && [[ "$FIRST" =~ ^FORBID\ kind=([a-z][a-z0-9-]*)\  ]]; then
    mkdir -p "$SDIR" && printf '%s\t%s\t%s\n' "$1" "${BASH_REMATCH[1]}" "$(now_epoch)" >> "$SDIR/denied.tsv" || scope_wfail "$SDIR/denied.tsv"
  fi
  [ "$RC" = 0 ] || scope_err "분류기 거절 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [[ "$FIRST" =~ ^CLASS\ (docs|ff|revert|code)(\ kind=([a-z0-9,-]+)\ learned)?$ ]] || scope_err "분류기 출력 꼴 틀림: $FIRST"
  CLS="${BASH_REMATCH[1]}"; CLS_LEARNED="${BASH_REMATCH[3]}"
}

cmd_scope_approve() {
  local sha="${1:-}" pr="" card="" rk=byz cls used today now line ev="" cu="" tail="" eq="" CODE_EQUIV="" dir="$STATE/autonomy-merge-approved"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || scope_err "sha 형식 틀림(40hex 소문자): $sha (usage: scope-approve <40hex> [--pr <N>] [--card <카드.md>] [--repo byz|pack])"
  shift
  while [ $# -gt 0 ]; do case "$1" in
    --pr) [[ "${2:-}" =~ ^[0-9]+$ ]] || scope_err "--pr 값 틀림"; pr="$2"; shift 2 ;;
    --card) [ -n "${2:-}" ] || scope_err "--card 값 없음"; card="$2"; shift 2 ;;
    --repo) [ -n "${2:-}" ] || scope_err "--repo 값 없음"; rk="$2"; shift 2 ;;
    *) scope_err "알 수 없는 인자: $1" ;; esac; done
  lock; scope_load || scope_err "활성 범위 승인 없음"
  scope_block; [ "$RENEW" = 1 ] && scope_renew
  if [ -n "$BLOCK" ]; then [ "$AUTOSTOP" = 1 ] && scope_write_stop "$G_S" "$BLOCK"; scope_err "$G_S 정지: $BLOCK"; fi
  scope_repo_set "$rk"
  scope_check_revert
  used="$(scope_used "$G_S")"; today="$(scope_today "$G_S")"
  if grep -q "^scope-use S[0-9]* $sha " "$LOG" 2>/dev/null; then echo "SCOPE-NOOP $sha used=$used/$G_MAX today=$today/$G_DAILY"; return 0; fi
  scope_classify "$sha"; cls="$CLS"
  case ",$G_CLASSES," in *",$cls,"*) ;; *) scope_err "종류 $cls 는 승인 범위($G_CLASSES) 밖" ;; esac
  [ "$rk" = byz ] || tail=" repo=$rk"; [ -z "$CLS_LEARNED" ] || tail="$tail learned=$CLS_LEARNED"
  if [ "$cls" = code ]; then   # R411: code 건수(docs 와 별개) → 시험 통과 세트 검사 — 통과 전 쓰기 0
    cu="$(scope_code_used "$G_S")"
    [ "$cu" -lt "$G_CODEMAX" ] || { scope_write_stop "$G_S" "code 건수 도달($cu/$G_CODEMAX)"; scope_err "$G_S 정지: code 건수 도달($cu/$G_CODEMAX)"; }
    scope_code_check "$sha" "$card"; cu=$((cu + 1)); ev="evidence=$card@$CODE_A"
  elif eq="$(scope_equiv_sha "$sha")"; then   # r560: 이미 센 승인 A 의 EQUIV = 재승인이 아니다 — 셈 0 · 원장 종류 equiv
    cls="equiv"; ev="equiv=$eq"
  fi
  if [ "$cls" != revert ] && [ "$cls" != equiv ]; then   # r560: 종류 equiv(이미 센 승인의 EQUIV)만 셈 0 — code 의 CODE_EQUIV 는 종전대로 셈(code 건수 = 별도 칸)
    [ "$used" -lt "$G_MAX" ] || { scope_write_stop "$G_S" "건수 도달($used/$G_MAX)"; scope_err "$G_S 정지: 건수 도달($used/$G_MAX)"; }
    [ "$today" -lt "$G_DAILY" ] || scope_err "하루 건수 도달(오늘 $today/$G_DAILY)"
    used=$((used + 1)); today=$((today + 1))
  fi
  now="$(now_epoch)"; line="approve-merge $sha $G_A $now"
  mkdir -p "$dir" "$SDIR" || scope_wfail "$dir"
  printf 'scope-use %s %s %s %s%s\n' "$G_S" "$sha" "$cls" "$now" "$tail" >> "$LOG" || scope_wfail log
  printf '%s\n' "$line" >> "$LOG" || scope_wfail log
  { printf '%s\n' "$line" > "$dir/$sha.tmp" && mv "$dir/$sha.tmp" "$dir/$sha"; } || scope_wfail "$dir/$sha"
  ev="$ev$tail"; ev="${ev# }"
  printf '%s\t%s\t%s\t%s\t%s\t\t\n' "$now" "$sha" "$pr" "$cls" "$ev" >> "$SDIR/$G_S.ledger.tsv" || scope_wfail "$SDIR/$G_S.ledger.tsv"
  echo "SCOPE-OK $sha class=$cls${cu:+ code=$cu/$G_CODEMAX} used=$used/$G_MAX today=$today/$G_DAILY${CODE_EQUIV:+ equiv=$CODE_EQUIV}${eq:+ equiv=$eq}$tail"
}

cmd_scope_stop() {
  local s="${1:-}" r="${2:-}"
  [[ "$s" =~ ^S[0-9]+$ ]] && [ -n "${r//[[:space:]]/}" ] || scope_err "usage: scope-stop S<n> \"<사유>\""
  lock; grep -q "^approve-scope $s " "$LOG" 2>/dev/null || scope_err "그런 범위 승인 없음: $s"
  if scope_stopped "$s"; then echo "SCOPE-STOPPED $s (이미 정지: $(scope_stop_reason "$s"))"; return 0; fi
  scope_write_stop "$s" "$r"; echo "SCOPE-STOPPED $s: $(scope_stop_reason "$s")"
}

scope_audit() {  # grants.audit ↔ log grant 줄 · 승인 파일 수 ≥ scope-use 수 — 어긋나면 AUDIT-MISMATCH rc 3
  local audit="$SDIR/grants.audit" line key bad=0 ng na files=0 uses=0 rows f
  ng="$(grep -c '^approve-scope ' "$LOG" 2>/dev/null)"; na="$(wc -l < "$audit" 2>/dev/null | tr -d ' ')"
  while IFS= read -r line; do
    key="$(cut -d' ' -f2- <<<"$line" | tr ' ' '\t')"   # 7칸(옛 줄) 또는 8칸(+codemax · R411) — 마지막 칸 = 슬랙 ts
    awk -F'\t' -v k="$key" '{r=$1; for (i = 2; i < NF; i++) r = r "\t" $i} r==k && $NF ~ /^slack_ts=[0-9]+\.[0-9]+$/ {f=1} END{exit !f}' "$audit" 2>/dev/null \
      || { echo "AUDIT-MISMATCH $(cut -d' ' -f2 <<<"$line") grant: grants.audit 에 일치하는 줄(슬랙 ts 포함) 없음"; bad=1; }
  done < <(grep '^approve-scope ' "$LOG" 2>/dev/null)
  [ "${na:-0}" = "${ng:-0}" ] || { echo "AUDIT-MISMATCH - grant 줄 수: log ${ng:-0} ≠ grants.audit ${na:-0}"; bad=1; }
  if scope_load; then
    uses="$(grep -c "^scope-use $G_S " "$LOG" 2>/dev/null)"
    for f in "$STATE/autonomy-merge-approved"/*; do [ -f "$f" ] || continue
      awk -v a="$G_A" -v t="$G_AT" '$1=="approve-merge" && $3==a && $4>=t {n++} END{exit !n}' "$f" && files=$((files + 1))
    done
    [ "$files" -ge "${uses:-0}" ] || { echo "AUDIT-MISMATCH $G_S used: scope-use ${uses} > 승인 파일 ${files}"; bad=1; }   # 승인 파일을 지웠거나 scope-use 를 덧붙임
    rows="$(wc -l < "$SDIR/$G_S.ledger.tsv" 2>/dev/null | tr -d ' ')"
    [ "${rows:-0}" = "$uses" ] || { echo "AUDIT-MISMATCH $G_S used: scope-use ${uses} ≠ 원장 ${rows:-0}행"; bad=1; }   # scope-use 줄을 지워 건수를 되돌림(승인 파일 수만으론 안 잡힘 — 원장 행과 대조)
  fi
  while IFS=$'\t' read -r k s t _; do   # r466 학습표 행 = 거절 원장(denied.tsv)의 같은 sha·종류 + log 의 오빠 approve-merge 줄(같은 epoch) — 손 추가 행은 여기서 들킨다
    [ -n "$k" ] || continue
    awk -F'\t' -v s="$s" -v k="$k" '$1==s && $2==k {f=1} END{exit !f}' "$SDIR/denied.tsv" 2>/dev/null && grep -qE "^approve-merge $s (A[0-9]+|OFF) $t\$" "$LOG" 2>/dev/null \
      || { echo "AUDIT-MISMATCH learned $k: 거절 원장·approve-merge 줄과 안 맞음(sha=${s:0:12})"; bad=1; }
  done < <(grep -v '^#' "$SDIR/learned-kinds.tsv" 2>/dev/null)
  [ "$bad" = 0 ] || return 3
  echo "AUDIT-OK grants=${ng:-0} used=${uses:-0}"
}

cmd_scope_status() {
  if [ "${1:-}" = --audit ]; then scope_audit; return $?; fi
  [ $# -eq 0 ] || scope_err "usage: scope-status [--audit]"
  local each=""; [ "$(mode)" = on ] && [ "$(jfield level)" = each ] && each=" · 건마다 확인"   # r466 레벨 each = on 이 범위 승인을 안 건다(오빠 손 approve-scope 는 그대로 보인다)
  scope_load || { echo "[범위 승인 없음$each]"; return 0; }
  scope_block
  if [ -n "$BLOCK" ]; then echo "[범위 승인 $G_S 정지: $BLOCK]"; return 0; fi
  local c=""; [ "$G_CODEMAX" -gt 0 ] && c=" · code $(scope_code_used "$G_S")/$G_CODEMAX"
  echo "[범위 승인 $G_S · $G_A · ~$(hhmm "$G_UNTIL")까지 · $(scope_used "$G_S")/$G_MAX · 오늘 $(scope_today "$G_S")/$G_DAILY · $G_CLASSES$c]"
}
