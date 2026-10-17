#!/usr/bin/env bash
# ft-autonomy-scope.sh — 오빠 부재 중 병합 «범위 사전 승인» 4명령 (R298 1/3 · 판정 2055 · 카드 r298a-away-scope-grant) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   approve-scope --for <N>h --max <n> [--daily <n>] --classes <docs,ff,revert>  오빠 `!` 전용 — 기간·건수·종류를 «한 번» 정한다(code 는 열 수 없음 · r298c 전)
#   scope-approve <40hex> [--pr <N>]   좌석 허용 — 범위 대조만(분류기 = r298b autonomy_scope_classify.py) · 통과하면 기존 형식 `approve-merge` 줄을 대신 쓴다
#   scope-stop S<n> "<사유>"            좌석 허용 — 누구나 멈춘다 · 다시 켜기 = 오빠의 새 approve-scope 뿐
#   scope-status                       읽기 — `[범위 승인 S3 · A7 · ~03:10까지 · 4/20 · 오늘 2/10 · docs,ff,revert]`
#   scope-status --audit               읽기 — log grant 줄 ↔ grants.audit(슬랙 ts 포함) 대조 + 승인 파일 수 ≥ scope-use 수 · 어긋나면 `AUDIT-MISMATCH …` rc 3
# ★한계(판정 2078 ⓐ)★ 같은 uid 의 직접 쓰기(log 에 grant 줄 덧붙이기·scope-use 줄 지우기)는 막지 못한다 — approve-scope 의 슬랙 1줄 + --audit 대조로 «들킨다».
# 상태 원천 = autonomy.log 한 곳(추가 전용 · 쓰기는 ft-autonomy.sh 의 lock 안 · json 카운터 0) — 건수는 `scope-use` 줄을 센다.
# 원장 `$STATE/autonomy-scope/S<n>.ledger.tsv` 7칸 = 시각·sha·PR·종류·판정문(빈칸)·착지 sha(빈칸 — r298b 가 6번째 칸을 채운다)·되돌림 명령(빈칸)
# 외부 호출 0 — 분류기는 로컬 git 뿐 · 7초 상한(넘으면 REJECT · 판정 666).
SDIR="$STATE/autonomy-scope"

scope_err() { echo "SCOPE-REJECT $1" >&2; exit 2; }
scope_wfail() { echo "REJECT $1 쓰기 실패" >&2; exit 1; }

scope_load() {  # 마지막 approve-scope 줄 → G_S G_A G_UNTIL G_MAX G_DAILY G_CLASSES (rc 1 = 없음·꼴 틀림)
  local line a u m d c; line="$(grep '^approve-scope ' "$LOG" 2>/dev/null | tail -1)"
  [[ "$line" =~ $SCOPE_GRANT_RE ]] || return 1
  read -r a G_S G_A G_AT u m d c <<<"$line"
  G_UNTIL="${u#until=}"; G_MAX="${m#max=}"; G_DAILY="${d#daily=}"; G_CLASSES="${c#classes=}"
}

scope_stopped() { [ -f "$SDIR/$1.stopped" ] || grep -q "^scope-stop $1 " "$LOG" 2>/dev/null; }
scope_stop_reason() {  # <S> — log 의 마지막 stop 줄 사유(없으면 .stopped 파일)
  local r; r="$(grep "^scope-stop $1 " "$LOG" 2>/dev/null | tail -1 | cut -d' ' -f4-)"
  [ -n "$r" ] || r="$(head -1 "$SDIR/$1.stopped" 2>/dev/null)"; printf '%s' "$r"
}
scope_used() { awk -v s="$1" '$1=="scope-use" && $2==s && $4!="revert" {n++} END{print n+0}' "$LOG" 2>/dev/null; }
scope_today() { awk -v s="$1" -v c="$(( $(now_epoch) - 86400 ))" '$1=="scope-use" && $2==s && $4!="revert" && $5>c {n++} END{print n+0}' "$LOG" 2>/dev/null; }

scope_write_stop() {  # <S> <사유> — log 먼저, .stopped 나중. 사유의 탭·개행은 공백으로
  local r="${2//[$'\t\n\r']/ }"; [ -n "${r//[[:space:]]/}" ] || r="사유 없음"
  mkdir -p "$SDIR" || scope_wfail "$SDIR"
  printf 'scope-stop %s %s %s\n' "$1" "$(now_epoch)" "$r" >> "$LOG" || scope_wfail log
  printf '%s\n' "$r" > "$SDIR/$1.stopped" || scope_wfail "$SDIR/$1.stopped"
}

scope_block() {  # scope_load 뒤 — 막는 사유를 BLOCK 에 · 스스로 정지를 써야 하는 사유(위변조·사건 번호·기간)면 AUTOSTOP=1
  local m ev; BLOCK=""; AUTOSTOP=0; m="$(mode)"; ev="$(event)"
  if scope_stopped "$G_S"; then BLOCK="$(scope_stop_reason "$G_S")"
  elif [ "$m" = tamper ]; then BLOCK="위변조 → OFF"; AUTOSTOP=1
  elif [ "$m" != on ]; then BLOCK="자율 모드 OFF"
  elif [ "$ev" != "$G_A" ]; then BLOCK="사건 번호 바뀜(${G_A}→${ev})"; AUTOSTOP=1
  elif [ "$(now_epoch)" -ge "$G_UNTIL" ]; then BLOCK="기간 끝 도달 $(hhmm "$G_UNTIL")"; AUTOSTOP=1
  fi
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
  local f="" mx="" dl="" cl="" h c n ev now un ts seen=","
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || scope_err "$1 값 없음 (usage: approve-scope --for <N>h --max <n> [--daily <n>] --classes <docs,ff,revert>)"
    case "$1" in --for) f="$2" ;; --max) mx="$2" ;; --daily) dl="$2" ;; --classes) cl="$2" ;; *) scope_err "알 수 없는 인자: $1" ;; esac
    shift 2
  done
  [[ "$f" =~ ^([0-9]+)h$ ]] && h=$((10#${BASH_REMATCH[1]})) && [ "$h" -ge 1 ] && [ "$h" -le 72 ] || scope_err "--for 는 1h~72h 형식(받은 값: ${f:-없음})"
  [[ "$mx" =~ ^[0-9]+$ ]] && mx=$((10#$mx)) && [ "$mx" -ge 1 ] && [ "$mx" -le 30 ] || scope_err "--max 는 1~30(받은 값: ${mx:-없음})"
  if [ -z "$dl" ]; then dl=10; [ "$dl" -le "$mx" ] || dl="$mx"; fi
  [[ "$dl" =~ ^[0-9]+$ ]] && dl=$((10#$dl)) && [ "$dl" -ge 1 ] && [ "$dl" -le "$mx" ] || scope_err "--daily 는 1~max($mx)(받은 값: $dl)"
  [ -n "$cl" ] || scope_err "--classes 없음"
  for c in ${cl//,/ }; do
    case "$c" in
      docs|ff|revert) case "$seen" in *",$c,"*) scope_err "종류 중복: $c" ;; esac; seen="$seen$c," ;;
      code) scope_err "종류 code 는 r298c 착지·오빠 별도 승인 전 열 수 없음" ;;
      *) scope_err "알 수 없는 종류: $c (docs·ff·revert 만)" ;;
    esac
  done
  [[ "$cl" != ,* && "$cl" != *, && "$cl" != *,,* ]] || scope_err "--classes 형식 틀림: $cl"
  lock; [ "$(mode)" = on ] || scope_err "자율 모드가 ON 이 아님($(mode)) — 승인 기록 없음"
  n="$(grep -c '^approve-scope ' "$LOG" 2>/dev/null)"; n="S$(( ${n:-0} + 1 ))"; ev="$(event)"; now="$(now_epoch)"; un=$(( now + h * 3600 ))
  ts="$(scope_slack_post "[범위 승인] $n · $ev · ~$(hhmm "$un")까지 · max $mx · 하루 $dl · $cl · 부여 $now")" || exit $?   # 게시 «먼저» — 실패면 아래 쓰기 0
  mkdir -p "$SDIR" || scope_wfail "$SDIR"
  printf '%s\t%s\t%s\tuntil=%s\tmax=%s\tdaily=%s\tclasses=%s\tslack_ts=%s\n' "$n" "$ev" "$now" "$un" "$mx" "$dl" "$cl" "$ts" >> "$SDIR/grants.audit" || scope_wfail "$SDIR/grants.audit"
  printf 'approve-scope %s %s %s until=%s max=%s daily=%s classes=%s\n' "$n" "$ev" "$now" "$un" "$mx" "$dl" "$cl" >> "$LOG" || scope_wfail log
  unlock; scope_load; echo "SCOPE-GRANTED $G_S $G_A until=$(hhmm "$G_UNTIL") max=$G_MAX daily=$G_DAILY classes=$G_CLASSES"
}

scope_run_cls() {  # <하위명령> <sha|""> → OUT·RC·FIRST (분류기 r298b · 로컬 git 뿐 · 7초 상한 — 넘으면 rc≠0 = REJECT 쪽)
  local cls="${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" runner a=("$1"); [ -n "$2" ] && a+=("$2")
  [ -f "$cls" ] || scope_err "분류기 없음: $cls"
  if [[ "$cls" == *.py ]]; then runner=(python3 "$cls"); else runner=("$BASH" "$cls"); fi
  OUT="$(perl -e 'alarm 7; exec @ARGV' -- "${runner[@]}" "${a[@]}" --repo "$ROOT" --remote origin --target main --scope "$G_S" 2>&1)"; RC=$?
  FIRST="${OUT%%$'\n'*}"
}

scope_check_revert() {  # 분류 «전» 첫 단계 — rc 4(REVERTED …) = 정지 + REJECT · rc≠0 그 밖 = REJECT(닫힌 쪽) · rc 0 계속
  scope_run_cls check-revert ""
  [ "$RC" = 0 ] && return 0
  if [ "$RC" = 4 ]; then scope_write_stop "$G_S" "${FIRST:-REVERTED}"; scope_err "$G_S 정지: ${FIRST:-REVERTED}"; fi
  scope_err "되돌림 감지 실패 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
}

scope_classify() {  # <sha> → stdout = 종류 · 실패 = REJECT(사유 그대로)
  scope_run_cls classify "$1"
  [ "$RC" = 0 ] || scope_err "분류기 거절 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [[ "$FIRST" =~ ^CLASS\ (docs|ff|revert|code)$ ]] || scope_err "분류기 출력 꼴 틀림: $FIRST"
  printf '%s' "${BASH_REMATCH[1]}"
}

cmd_scope_approve() {
  local sha="${1:-}" pr="" cls used today now line dir="$STATE/autonomy-merge-approved"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || scope_err "sha 형식 틀림(40hex 소문자): $sha (usage: scope-approve <40hex> [--pr <N>])"
  shift; if [ "${1:-}" = --pr ]; then [[ "${2:-}" =~ ^[0-9]+$ ]] || scope_err "--pr 값 틀림"; pr="$2"; shift 2; fi
  [ $# -eq 0 ] || scope_err "알 수 없는 인자: $1"
  lock; scope_load || scope_err "활성 범위 승인 없음"
  scope_block
  if [ -n "$BLOCK" ]; then [ "$AUTOSTOP" = 1 ] && scope_write_stop "$G_S" "$BLOCK"; scope_err "$G_S 정지: $BLOCK"; fi
  scope_check_revert
  used="$(scope_used "$G_S")"; today="$(scope_today "$G_S")"
  if grep -q "^scope-use S[0-9]* $sha " "$LOG" 2>/dev/null; then echo "SCOPE-NOOP $sha used=$used/$G_MAX today=$today/$G_DAILY"; return 0; fi
  cls="$(scope_classify "$sha")" || exit $?
  case ",$G_CLASSES," in *",$cls,"*) ;; *) scope_err "종류 $cls 는 승인 범위($G_CLASSES) 밖" ;; esac
  if [ "$cls" != revert ]; then
    [ "$used" -lt "$G_MAX" ] || { scope_write_stop "$G_S" "건수 도달($used/$G_MAX)"; scope_err "$G_S 정지: 건수 도달($used/$G_MAX)"; }
    [ "$today" -lt "$G_DAILY" ] || scope_err "하루 건수 도달(오늘 $today/$G_DAILY)"
    used=$((used + 1)); today=$((today + 1))
  fi
  now="$(now_epoch)"; line="approve-merge $sha $G_A $now"
  mkdir -p "$dir" "$SDIR" || scope_wfail "$dir"
  printf 'scope-use %s %s %s %s\n' "$G_S" "$sha" "$cls" "$now" >> "$LOG" || scope_wfail log
  printf '%s\n' "$line" >> "$LOG" || scope_wfail log
  { printf '%s\n' "$line" > "$dir/$sha.tmp" && mv "$dir/$sha.tmp" "$dir/$sha"; } || scope_wfail "$dir/$sha"
  printf '%s\t%s\t%s\t%s\t\t\t\n' "$now" "$sha" "$pr" "$cls" >> "$SDIR/$G_S.ledger.tsv" || scope_wfail "$SDIR/$G_S.ledger.tsv"
  echo "SCOPE-OK $sha class=$cls used=$used/$G_MAX today=$today/$G_DAILY"
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
    key="$(cut -d' ' -f2-8 <<<"$line" | tr ' ' '\t')"
    awk -F'\t' -v k="$key" 'BEGIN{OFS="\t"} ($1 OFS $2 OFS $3 OFS $4 OFS $5 OFS $6 OFS $7)==k && $8 ~ /^slack_ts=[0-9]+\.[0-9]+$/ {f=1} END{exit !f}' "$audit" 2>/dev/null \
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
  [ "$bad" = 0 ] || return 3
  echo "AUDIT-OK grants=${ng:-0} used=${uses:-0}"
}

cmd_scope_status() {
  if [ "${1:-}" = --audit ]; then scope_audit; return $?; fi
  [ $# -eq 0 ] || scope_err "usage: scope-status [--audit]"
  scope_load || { echo "[범위 승인 없음]"; return 0; }
  scope_block
  if [ -n "$BLOCK" ]; then echo "[범위 승인 $G_S 정지: $BLOCK]"; return 0; fi
  echo "[범위 승인 $G_S · $G_A · ~$(hhmm "$G_UNTIL")까지 · $(scope_used "$G_S")/$G_MAX · 오늘 $(scope_today "$G_S")/$G_DAILY · $G_CLASSES]"
}
