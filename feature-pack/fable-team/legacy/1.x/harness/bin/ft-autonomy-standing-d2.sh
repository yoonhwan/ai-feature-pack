#!/usr/bin/env bash
# ft-autonomy-standing-d2.sh — r1577 «상시 승인 D2» (카드 r1577-approval-split-critical-slack-only · DA 설계 APPROVE f932111739) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   왜: 승인 길이 «병합 종류(docs/code)» 로만 나뉘어, DA APPROVE + 카드 시험 PASS 코드 PR 도 건마다 오빠 Slack 답글을 기다렸다(범위 S43 하루 14/15).
#       되돌릴 수 있는 병합은 revert 로 되돌아간다 → 그 팀 master 가 결정하고 병합 «뒤» Slack 1줄로 알린다. 되돌릴 수 «없는» 종류만 오빠 답글 길(판정 2904)로 남긴다.
#   approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision <Slack ts>   ← 켜기 = planner master 좌석(오빠 `!` 0) · ①오빠 답글 확인(새 질문 0) ②켜짐 Slack 1글 먼저 → grants.audit(slack_ts·oppa_decision) → log
#   standing-approve D2 <head40> --pr <N> --repo byz|pack --verdict <판정문> --card <카드>   ← 쓰기 = 그 팀 master 좌석(ft_doc_exempt team-master-seat)
#       ①D2 켜짐 ②분류(--repo ⊆ repos · byz=내장표/pack=팩표 · FORBID·ERROR·시간초과=거절 · 종류(ff→docs) ∈ classes) ③D1 ③~⑥ 그대로 ④카드 시험 세트(code) ⑤크리티컬 0
#       하나라도 못 지나면 STANDING-REJECT rc2 · 쓰기 0 · 끝줄 «다시: 오빠 h(approve-merge --oppa-slack)» (oppa_gate·ft_oppa_slack_check 변경 0 — D2 는 승인 기록을 직접 발급)
#   standing-stop D2 "<사유>"   누구나 · 멈춘 뒤 standing-approve D2 = 거절 · 다시 켜기 = approve-standing D2
# 원장 $STATE/autonomy-standing/D2.ledger.tsv 7칸 = 시각·head·PR·da=<A>·DA 원문 경로·착지 sha·되돌림 명령(D1 과 같은 칸 · ft-merge-land 가 채운다)
D2="$STATE/autonomy-standing"; . "$HERE/ft-autonomy-standing.sh"   # D1 헬퍼(std_t7·std_field·std_verdict·std_da_out·std_equiv·std_seat_probe·std_plain) 재사용 — 사본 0
D2_GRANT_RE='^approve-standing D2 [0-9]+ repos=(byz|pack|byz,pack) classes=(code|docs)(,(code|docs))? oppa_decision=[0-9]+\.[0-9]{6}$'
std_err() { echo "STANDING-REJECT $1" >&2; echo "다시: 오빠 h(approve-merge --oppa-slack) — 크리티컬·판정문·시험 중 하나라도 못 지나면 건마다 오빠 답글" >&2; exit 2; }
scope_err() { std_err "④ $1"; }   # scope 시험 도구의 거절도 D2 끝줄 하나로(사본 0)
d2_on() {  # rc0 = 마지막 approve-standing D2 줄(꼴 맞음)이 마지막 standing-stop D2 줄보다 뒤 → D2_LINE D2_REPOS D2_CLASSES
  local g s; g="$(grep -n '^approve-standing D2 ' "$LOG" 2>/dev/null | tail -1)"; s="$(grep -n '^standing-stop D2 ' "$LOG" 2>/dev/null | tail -1)"
  [ -n "$g" ] || return 1; D2_LINE="${g#*:}"; [[ "$D2_LINE" =~ $D2_GRANT_RE ]] || return 1
  D2_REPOS="${D2_LINE#* repos=}"; D2_REPOS="${D2_REPOS%% *}"; D2_CLASSES="${D2_LINE#* classes=}"; D2_CLASSES="${D2_CLASSES%% *}"
  [ -z "$s" ] || [ "${g%%:*}" -gt "${s%%:*}" ]
}
d2_oppa_decision() {  # <ts> — 그 ts 가 «오빠가 쓴» 글인가(기존 읽기·사용자 식별 재사용 · 새 질문 0 · 판정 못 함 = 거절)
  local dx="$HERE/ft_oppa_slack_check.py" out rc; [ -f "$dx" ] || std_err "오빠 답글 확인 도구 없음: $dx"
  out="$(python3 -c 'import sys;sys.path.insert(0,sys.argv[1].rsplit("/",1)[0]);import ft_oppa_slack_check as c
ts=sys.argv[2]
try:
  assert any(m.get("ts")==ts and c.OPPA_SLACK_UID in (m.get("user"),m.get("bot_id")) for m in c.locate(ts)), "그 ts 가 오빠 글 아님(또는 스레드에서 못 찾음)"
except Exception as e: print("판정 불가: %s"%(str(e)[:120] or type(e).__name__));sys.exit(1)
print("OPPA-DECISION %s"%ts)' "$dx" "$1" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "OPPA-DECISION $1" ] || std_err "ⓐ --oppa-decision 확인 실패 rc=$rc: ${out%%$'\n'*}"
}
cmd_approve_standing() {
  local d="${1:-}" rp="" cl="" od="" c seen="," now body ts line
  [ "$d" = D2 ] || std_usage "usage: approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision <Slack ts>"; shift
  while [ $# -gt 0 ]; do [ $# -ge 2 ] || std_usage "$1 값 없음 (usage: approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision <Slack ts>)"
    case "$1" in --repos) rp="$2" ;; --classes) cl="$2" ;; --oppa-decision) od="$2" ;; *) std_usage "알 수 없는 인자: $1" ;; esac; shift 2; done
  case "$rp" in byz|pack|byz,pack) ;; *) std_usage "--repos 는 byz·pack·byz,pack(받은 값: ${rp:-없음})" ;; esac
  [[ "$cl" =~ ^(code|docs)(,(code|docs))?$ ]] || std_usage "--classes 는 code·docs 중 1~2개(받은 값: ${cl:-없음})"
  for c in ${cl//,/ }; do case "$seen" in *",$c,"*) std_usage "종류 중복: $c" ;; esac; seen="$seen$c,"; done
  [[ "$od" =~ ^[0-9]+\.[0-9]{6}$ ]] || std_usage "--oppa-decision 은 Slack ts(숫자.숫자6자리): ${od:-없음}"
  std_seat_probe || {   # ⓐ 켜기 판정 = planner master 좌석(D1 과 같은 함수) — 쓰기 판정(ⓑ 팀 master)과 «다른» 함수
    echo "STANDING-REJECT approve-standing D2 — 호출 좌석 $STD_SEAT_ACTUAL ≠ planner master · 쓰기 0" >&2
    echo "  ($STD_SEAT_ERR · D2 켜기는 planner master 좌석 몫)" >&2; exit 2; }
  [ -z "${FT_DOC_EXEMPT_SELFTEST:-}${FT_DOC_EXEMPT_SEAT:-}" ] || { echo "STANDING-REJECT approve-standing D2 — 시험 판정(SELFTEST env)으로는 승인 0" >&2; exit 3; }
  lock; [ "$(mode)" = tamper ] && std_usage "자율 상태 위변조(tamper) — 상시 승인 기록 없음"
  if d2_on; then unlock; echo "STANDING-NOOP D2 이미 켜짐($D2_LINE)"; return 0; fi
  d2_oppa_decision "$od"   # ① 확인 못 하면 아래 쓰기 0(게시 «전»)
  now="$(now_epoch)"; line="approve-standing D2 $now repos=$rp classes=$cl oppa_decision=$od"
  body="$(printf '%s\n%s\n%s' "상시 승인 D2 켜짐: 되돌릴 수 있는 병합은 팀장이 바로 해요" "혼자 해도 되는 것: DA 승인 + 카드 시험 통과 PR($(std_plain "$cl")) · 병합 뒤 1줄로 알려요" \
    "언제까지: 멈춤(standing-stop) 전까지 · 크리티컬(kill·삭제·force push·launchd·외부 설정)은 그대로 답글 필요")"
  ts="$(scope_slack_post "$body")" || exit $?   # ② 게시 «먼저» — 실패면 쓰기 0
  mkdir -p "$D2" || std_wfail "$D2"
  printf '%s\tslack_ts=%s\n' "$line" "$ts" >> "$D2/grants.audit" || std_wfail "$D2/grants.audit"
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-GRANTED D2 repos=$rp classes=$cl oppa_decision=$od slack_ts=$ts"
}
d2_repo() {  # <byz|pack> → D2_REPO(대상 리포 최상위) D2_RK · 범위 밖 = 거절
  local h; case "$1" in
    byz) D2_REPO="$ROOT" ;;
    pack) h="$(. "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE")" && D2_REPO="$(git -C "$h" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$D2_REPO" ] || std_err "팩 리포를 못 풂(FT_HARNESS_ROOT · <bin>/../HARNESS_ROOT)" ;;
    *) std_err "--repo 는 byz|pack(받은 값: $1)" ;;
  esac
  case ",$D2_REPOS," in *",$1,"*) ;; *) std_err "② 저장소 $1 은 승인 범위(repos=$D2_REPOS) 밖" ;; esac
  D2_RK="$1"; PREPO="$D2_REPO"; SCOPE_REPO="$D2_REPO"   # ③ std_equiv·④ scope_code_check 가 같은 리포를 본다
}
d2_seat() {  # ⓑ 쓰기 좌석 = 그 팀 master — 실제 좌석(TMUX_PANE) · SELFTEST env 는 env -u 로 지운다
  local dx="$HERE/ft_doc_exempt.py"; [ -f "$dx" ] || std_err "좌석 판정 모듈 없음: $dx"
  std_roster_root   # ⓙ 켜기(std_seat_probe)와 «같은» 명부 루트 함수 1개(ⓘ) — ft_comm_dir·env 안 쓴다
  std_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3 "$dx" --mode team-master-seat --repo "$ROOT" --root "$STD_ROOT"
  if [ "$RC" = 0 ] && [[ "$FIRST" =~ ^TEAM-MASTER-SEAT\ ([A-Za-z0-9#_-]+) ]]; then D2_BY="${BASH_REMATCH[1]}"; return 0; fi
  std_err "ⓑ 팀 master 좌석만 rc=$RC ${FIRST:-출력 없음(시간 초과 7초 포함)}"
}
d2_classify() {  # ② <head> → D2_CLS — byz = 내장 BYZ 표 · pack = 팩 표 · FORBID·ERROR·시간 초과 = 거절
  local cls="${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" a=() t k; [ -f "$cls" ] || std_err "분류기 없음: $cls"
  if [ "$D2_RK" = pack ]; then t="${FT_SCOPE_PACK_TABLE:-$(tpl_file scope-classes-pack.tsv)}" || std_err "② 팩 분류표 없음(templates/scope-classes-pack.tsv)"; a+=(--table "$t")
  elif t="${FT_SCOPE_DDL_RECORDS:-$(tpl_file scope-ddl-record.tsv)}"; then a+=(--ddl-records "$t"); fi
  std_t7 python3 "$cls" classify "$1" --repo "$D2_REPO" --remote origin --target main --scope S0 "${a[@]}"
  [ "$RC" = 0 ] || std_err "② 분류기 거절 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [[ "$FIRST" =~ ^CLASS\ (docs|ff|code)$ ]] || std_err "② 종류가 code·docs 아님: $FIRST"
  k="${BASH_REMATCH[1]}"; [ "$k" != ff ] || k=docs   # ff = 문서만 바뀌고 main 이 head 의 조상(D1 과 같은 꼴)
  case ",$D2_CLASSES," in *",$k,"*) ;; *) std_err "② 종류 $k 는 상시 승인 범위(classes=$D2_CLASSES) 밖" ;; esac
  D2_CLS="$k"
}
d2_critical() {  # ⑤ <head> — 크리티컬 종류 0(ⓒ) · 판정 못 함 = 거절(닫힌 쪽)
  std_t7 python3 "${FT_SCOPE_CLASSIFY:-$HERE/autonomy_scope_classify.py}" classify "$1" --repo "$D2_REPO" --remote origin --target main --critical
  [ "$RC" = 0 ] && [ "$FIRST" = CRITICAL-OK ] && return 0
  [[ "$FIRST" =~ ^CRITICAL\ kind=([a-z]+)\ (.*)$ ]] && std_err "⑤ 크리티컬: ${BASH_REMATCH[1]} — ${BASH_REMATCH[2]}"
  std_err "⑤ 크리티컬 판정 실패 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
}
d2_write() {  # <head> <pr> <A> <원문> — log(standing-use → approve-merge) 먼저 · 승인 파일 · 원장 나중
  local now line dir="$STATE/autonomy-merge-approved"; now="$(now_epoch)"; line="approve-merge $1 D2 $now"
  mkdir -p "$dir" "$D2" || std_wfail "$dir"
  printf 'standing-use D2 %s %s pr=%s repo=%s da=%s\n' "$1" "$now" "$2" "$D2_RK" "$3" >> "$LOG" || std_wfail log
  printf '%s\n' "$line" >> "$LOG" || std_wfail log
  { printf '%s\n' "$line" > "$dir/$1.tmp" && mv "$dir/$1.tmp" "$dir/$1"; } || std_wfail "$dir/$1"
  printf '%s\t%s\t%s\tda=%s\t%s\t\t\n' "$now" "$1" "$2" "$3" "$4" >> "$D2/D2.ledger.tsv" || std_wfail "$D2/D2.ledger.tsv"
  echo "STANDING-OK $1 pr=$2 repo=$D2_RK da=$3 card=$(basename "$D2_CARD") by=$D2_BY${STD_EQ:+ equiv=$STD_EQ}"
}
cmd_standing_approve() {
  local d="${1:-}" head pr="" rk="" vf="" card=""
  [ "$d" = D2 ] || std_usage "usage: standing-approve D2 <head40> --pr <N> --repo byz|pack --verdict <판정문.md> --card <카드.md>"
  shift; head="${1:-}"; [[ "$head" =~ ^[0-9a-f]{40}$ ]] || std_usage "sha 형식 틀림(40hex 소문자): $head (usage: standing-approve D2 <head40> --pr <N> --repo byz|pack --verdict <판정문.md> --card <카드.md>)"
  STD_SHA="$head"; shift
  while [ $# -gt 0 ]; do [ $# -ge 2 ] || std_err "$1 값 없음"; case "$1" in --pr) [[ "$2" =~ ^[0-9]+$ ]] || std_err "--pr 값 틀림: $2"; pr="$2" ;;
    --repo) rk="$2" ;; --verdict) vf="$2" ;; --card) card="$2" ;; *) std_err "알 수 없는 인자: $1" ;; esac; shift 2; done
  [ -n "$pr" ] && [ -n "$vf" ] && [ -n "$card" ] || std_err "--pr·--verdict·--card 필수"
  D2_CARD="$card"; d2_seat
  lock; [ "$(mode)" = tamper ] && std_err "자율 상태 위변조(tamper) — 승인 기록 없음"
  d2_on || std_err "① 상시 승인 D2 꺼짐(approve-standing D2 줄 없음 또는 standing-stop 뒤)"
  d2_repo "$rk"
  if grep -q "^standing-use D2 $head " "$LOG" 2>/dev/null; then echo "STANDING-NOOP $head (이미 상시 승인함)"; return 0; fi
  d2_classify "$head"; std_verdict "$vf"; std_da_out "$V_OUT" "$V_A"; std_equiv "$V_A" "$head"
  [ "$D2_CLS" != code ] || scope_code_check "$head" "$card"   # ④ 카드 시험 세트(rc≠0 = scope_err = STANDING-REJECT)
  d2_critical "$head"; d2_write "$head" "$pr" "$V_A" "$V_OUT"
}
cmd_standing_stop() {
  local d="${1:-}" r="${2:-}"
  [ "$d" = D2 ] && [ -n "${r//[[:space:]]/}" ] || std_usage 'usage: standing-stop D2 "<사유>"'
  lock; grep -q '^approve-standing D2 ' "$LOG" 2>/dev/null || std_usage "그런 상시 승인 없음: D2"
  d2_on || { unlock; echo "STANDING-STOPPED D2 (이미 꺼짐)"; return 0; }; r="${r//[$'\t\n\r']/ }"
  printf 'standing-stop D2 %s %s\n' "$(now_epoch)" "$r" >> "$LOG" || std_wfail log
  unlock; echo "STANDING-STOPPED D2: $r"
}
