#!/usr/bin/env bash
# ft-index-lint.sh <indices/…/X.md> [more…] — Seatbelt 0.3 · 인덱스 파일이 «누가 읽어도 착수 가능»한지 검사.
#   exit 0 = OK · 1 = REJECT(사유 stdout) · 2 = usage
# 검사 (SEATBELT-README §5): ①골 3줄 바이트 일치 ②필수 6절 ③골좌표의 닫는 증거가 GOAL-LEDGER 에 실재(20자+ 복붙)
#   ④배경 절 정본 인용 ≤4 ⑤구현 범위·완료 조건 절이 비어 있지 않음.
# ★판정기가 아니다★ — 내용의 옳고 그름은 보지 않는다. «형식이 갖춰졌나»만 답한다(#0 RULE: 조용한 통과 없음).
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <index.md> [more…]" >&2; exit 2; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DEFAULT_LEDGER="$ROOT/${FT_GOAL_LEDGER:-design/v65/GOAL-LEDGER-v65.md}"
# 하네스 자체 작업(Seatbelt 단위)은 제품 골 원장에 행이 없다. 파일 머리에 `<!-- ledger: <경로> -->` 를 «선언»하면
# 그 문서를 닫는 증거의 정본으로 쓴다 — 예외 목록이 아니라 파일이 스스로 밝히고, 결과 줄에 어느 정본을 봤는지 찍는다.
ledger_for() { local d; d="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$1" | head -1 | sed -E 's/<!-- *ledger: *([^ >]+) *-->/\1/')"; [ -n "$d" ] && printf '%s' "$ROOT/$d" || printf '%s' "$DEFAULT_LEDGER"; }
# 골 3줄 — FT_GOAL_LINES_FILE(3행 텍스트)이 있으면 그 파일, 비어 있으면 v65 3줄(예시).
if [ -n "${FT_GOAL_LINES_FILE:-}" ] && [ -f "$FT_GOAL_LINES_FILE" ]; then
  GOAL1="$(sed -n 1p "$FT_GOAL_LINES_FILE")"; GOAL2="$(sed -n 2p "$FT_GOAL_LINES_FILE")"; GOAL3="$(sed -n 3p "$FT_GOAL_LINES_FILE")"
else
  GOAL1='목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.'
  GOAL2='LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.'
  GOAL3='단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.'
fi
SECTIONS=('골 원문' '골좌표' '배경' '구현 범위' '완료 조건' '상태')
MAX_CITES="${FT_INDEX_MAX_CITES:-4}"
rc=0
section_body() {  # $1=file $2=heading-prefix → 그 절 본문(다음 ## 전까지)
  awk -v h="## $2" 'index($0,h)==1{f=1;next} /^## /{f=0} f' "$1"
}
# ★정규화★ — 정본(GOAL-LEDGER)은 강조 `**…**` 가 섞여 있고, 인덱스 파일은 「…」 안에서 줄을 바꾼다.
#   바이트 그대로 대조하면 «복붙인데 불일치»가 난다(실측 2026-09-14: M5 「…20초 초과…」 hit 0 —
#   정본이 `**20초 초과**`). 줄바꿈→공백, `**` 제거, 연속 공백 1개. 그 뒤 F 매칭.
norm() { tr '\n' ' ' | sed -e 's/\*\*//g' -e 's/  */ /g'; }
path_exists() { [ -e "$ROOT/$1" ] || [ -e "$1" ]; }  # $1=경로 → 리포 루트 기준 또는 그대로 실재하면 0
# ⑥ 전용(R154): 기존 path_exists 가 거짓이면 origin/main «트리»에 있는 저장소 상대 경로도 실재로 인정한다(나노 base = origin/main).
#   fallback 은 상대 경로만 — 앞의 `./` 는 반복 제거, 그 뒤가 비었거나 선행 `/`·`.`/`..` 성분·빈 성분(`//`)이면 거절(Git 의 경로 정규화에 기대지 않는다).
#   tracked 디렉터리(tree)도 실재(기존 `[ -e ]` 와 같은 정책). fetch 0 · origin/main ref 없으면 cat-file 이 실패해 기존 동작.
#   R174: 정규화는 norm_rel 로 뽑아 ⑥(scope_path_exists)과 ⑧(check_evidence)이 같은 거절 규칙을 쓴다. 성공 시 NORM_P 에 결과.
norm_rel() { NORM_P="$1"; while [[ "$NORM_P" == ./* ]]; do NORM_P="${NORM_P#./}"; done; case "/$NORM_P/" in //*|*//*|*/./*|*/../*) return 1;; esac; }
scope_path_exists() { path_exists "$1" && return 0; norm_rel "$1" || return 1; git -C "$ROOT" cat-file -e "refs/remotes/origin/main:$NORM_P" 2>/dev/null; }
# ⑦ 사전검증 · ⑧ 조사 근거 — 팀 env 스위치 FT_CARD_REQUIRE_PREVERIFY=1 일 때만 불린다(원장 R16: DA·조사 없이 열린 구현 나노 차단).
#   형식만 본다 — 판정문 «내용»이나 인용 «내용»은 대조하지 않는다.
NAME_LINT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-name-lint.sh"
last_verdict() { grep -owE 'APPROVE|HOLD|REJECT' "$1" | tail -1; }  # DA 판정 형식은 이 셋뿐(단어 경계 — SUPABASE_PASSWORD·시험 요약 «PASS» 에 안 걸린다)
hold_conditional() {  # $1=사전검증 본문 $2=카드 → 0=예외 성립(INFO 출력) · 1=불성립(HOLD_WHY=사유, 예외 줄 자체가 없으면 빈 값)
  local n rc; HOLD_WHY=""
  n="$(printf '%s\n' "$1" | sed -nE 's/^[-* ]*lint 예외 1건: *판정 ([0-9]+) ① 조건부 승인.*/\1/p' | head -1)"
  [ -n "$n" ] || return 1; . "$(dirname "${BASH_SOURCE[0]:-$0}")/ft-verdict-row.sh" 2>/dev/null || { HOLD_WHY="판정 줄 공용 함수(ft-verdict-row.sh) 없음"; return 1; }   # R255·R257 원장 두 꼴
  git -C "$ROOT" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 || { HOLD_WHY="원장 확인 불가 (origin/main ref 없음)"; return 1; }
  git -C "$ROOT" grep -qE -e "$(fv_row_re "$n").*조건부 승인" origin/main -- 'design/planner/VERDICTS-planner-*.md' >/dev/null 2>&1; rc=$?
  [ $rc -le 1 ] || { HOLD_WHY="원장 확인 불가 (git grep rc=$rc)"; return 1; }
  [ $rc -eq 0 ] || { HOLD_WHY="planner 원장에 판정 $n 조건부 승인 줄 없음(글머리 「- **$n**」·표 행 「| $n |」 둘 다)"; return 1; }
  section_body "$2" '완료 조건' | grep -q '잔여 HOLD' || { HOLD_WHY="완료 조건에 「잔여 HOLD」 표식 없음"; return 1; }
  echo "INFO 사전검증: DA 마지막 판정 HOLD — planner 판정 $n 조건부 승인으로 통과"
}
check_da_verdict() {  # $1=사전검증 본문 $2=카드 → bad+=
  local dpath v
  dpath="$(printf '%s\n' "$1" | grep -E '^[-* ]*DA: *[^ ]' | head -1 | tr -d '`' | sed -E 's/^[-* ]*DA: *//; s/[[:space:]].*$//; s/#.*$//')"
  [ -n "$dpath" ] || { bad+=("사전검증: 소환 예인데 「DA: <판정문 경로>」 줄 없음"); return; }
  path_exists "$dpath" || { bad+=("사전검증: DA 판정문 경로 없음 ($dpath)"); return; }
  v="$(last_verdict "$ROOT/$dpath" 2>/dev/null || true)"; [ -n "$v" ] || v="$(last_verdict "$dpath" 2>/dev/null || true)"
  case "$v" in APPROVE) ;; HOLD) hold_conditional "$1" "$2" || bad+=("사전검증: DA 판정문의 마지막 판정이 APPROVE 가 아니다 (HOLD)${HOLD_WHY:+ — lint 예외 불성립: $HOLD_WHY}");; *) bad+=("사전검증: DA 판정문의 마지막 판정이 APPROVE 가 아니다 (${v:-판정 단어 없음})");; esac
}
check_exemption() {  # $1=사전검증 본문 → bad+=
  local line reason seat role
  line="$(printf '%s\n' "$1" | grep -E '^[-* ]*면제: *.+ — arch 서명 +[^ ]' | head -1 | tr -d '`')"
  [ -n "$line" ] || { bad+=("사전검증: 소환 아니오인데 「면제: <사유> — arch 서명 <좌석명>」 줄 없음"); return; }
  reason="$(printf '%s' "$line" | sed -E 's/^[-* ]*면제: *//; s/ *— arch 서명 .*$//')"
  seat="$(printf '%s' "$line" | sed -E 's/^.* — arch 서명 +//; s/[[:space:]].*$//')"
  [ "${#reason}" -ge 10 ] || bad+=("사전검증: 면제 사유 10자 미만 (${#reason}자)")
  [ -f "$NAME_LINT" ] && bash "$NAME_LINT" "$seat" >/dev/null 2>&1 || { bad+=("사전검증: 서명 좌석명이 ft-name-lint 를 통과하지 못한다 ($seat)"); return; }
  IFS='-' read -r _ _ role _ <<< "${seat%#*}"
  [ "$role" = arch ] || bad+=("사전검증: 서명 좌석의 역할이 arch 가 아니다 ($role)")
}
check_preverify() {  # $1=file → bad+=
  local body mode
  grep -qE '^## 사전검증' "$1" || { bad+=("절 없음: 사전검증 (⑦)"); return; }
  body="$(section_body "$1" '사전검증')"
  mode="$(printf '%s\n' "$body" | grep -E '^[-* ]*소환: *(예|아니오) *$' | head -1 | sed -E 's/^[-* ]*소환: *//; s/ *$//')"
  case "$mode" in
    예) check_da_verdict "$body" "$1";;
    아니오) check_exemption "$body";;
    *) bad+=("사전검증: 「소환: 예」 또는 「소환: 아니오」 줄 없음");;
  esac
}
check_evidence() {  # $1=file → bad+=  (경로:줄 — 경로 실재 + 줄 번호 ≤ 파일 줄 수)
  # R174: 작업 트리 줄 수 안이면 그대로 통과(origin/main 조회 0). 아니면 origin/main «blob» 줄 수도 본다 — 둘 중 하나 안이면 OK, 둘 다 밖이면 큰 쪽 N 으로 REJECT.
  local refs ref p n q wt om total
  grep -qE '^## 조사 근거' "$1" || { bad+=("절 없음: 조사 근거 (⑧)"); return; }
  refs="$(section_body "$1" '조사 근거' | tr -d '`' | grep -oE '[^[:space:]:()]+\.[A-Za-z0-9]+:[0-9]+' | sort -u)"
  [ -n "$refs" ] || { bad+=("조사 근거: 「경로:줄」 인용이 하나도 없다"); return; }
  while IFS= read -r ref; do
    p="${ref%:*}"; n="${ref##*:}"; wt=-1; om=-1
    q="$p"; [ -f "$ROOT/$p" ] && q="$ROOT/$p"
    [ -f "$q" ] && wt="$(awk 'END{print NR}' "$q")"
    { [ "$wt" -ge 1 ] && [ "$n" -ge 1 ] && [ "$n" -le "$wt" ]; } && continue
    if norm_rel "$p" && [ "$(git -C "$ROOT" cat-file -t "refs/remotes/origin/main:$NORM_P" 2>/dev/null)" = blob ]; then
      om="$(git -C "$ROOT" show "refs/remotes/origin/main:$NORM_P" 2>/dev/null | awk 'END{print NR}')" || om=-1
    fi
    { [ "$wt" -lt 0 ] && [ "$om" -lt 0 ]; } && { bad+=("조사 근거: 경로 없음 ($ref)"); continue; }
    { [ "$om" -ge 1 ] && [ "$n" -ge 1 ] && [ "$n" -le "$om" ]; } && continue
    total=$(( wt > om ? wt : om ))
    bad+=("조사 근거: 줄 번호가 파일 줄 수(${total})를 벗어남 ($ref)")
  done <<< "$refs"
}
# ⑨ 머리 `- 제안서:` 줄 (R77 r1 · 판정 826) — 값 = `#<제안 Issue 번호>` 또는 `없음 — <사유>`(승인 증거 검사는 ft-proposal-gate.sh --card).
#   의무 = 새 카드(git 에 아직 없거나 첫 추가일 ≥ 2026-10-11). 옛 카드는 줄이 없거나 경로 값이면 WARN 만(rc 유지). 새 카드의 경로 값은 REJECT.
check_proposal_line() {  # $1=file → bad+=
  local val added new=1
  val="$(awk '/^##[[:space:]]/{exit} {print}' "$1" | sed -nE 's/^[[:space:]]*[-*][[:space:]]*제안서:[[:space:]]*(.*)$/\1/p' | head -1)"
  added="$(git -C "$(dirname "$1")" log --diff-filter=A --format=%as -- "$(basename "$1")" 2>/dev/null | tail -1)"
  { [ -z "$added" ] || [[ ! "$added" < "2026-10-11" ]]; } || new=0
  if [ -z "$val" ]; then
    bash "$(dirname "${BASH_SOURCE[0]:-$0}")/ft-proposal-gate.sh" --writing-card "$1" 2>/dev/null && return   # 제안서 «작성 카드»(proposal-* · 구현 범위 design/ 문서 1개+ 뿐)만 줄 면제 — spawn 게이트와 같은 판별
    if [ "$new" = 1 ]; then bad+=("머리 「- 제안서: #<제안 Issue 번호> | 없음 — 사유」 줄 없음 (새 카드 의무 · R77)")
    else echo "WARN $1 — 머리 「- 제안서:」 줄 없음 (옛 카드 · 2026-10-11 이후 새 카드부터 의무)"; fi
    return
  fi
  [[ "$val" =~ ^#[0-9]+([[:space:]]|$) || "$val" == "없음 — "?* ]] && return
  if [ "$new" = 1 ]; then bad+=("「- 제안서:」 값은 #<제안 Issue 번호> 또는 「없음 — 사유」 (경로 값은 R77 r1 부터 새 카드에서 금지): ${val:0:40}")
  else echo "WARN $1 — 「- 제안서:」 경로·기타 값(옛 카드 · 새 카드는 #M 또는 없음 — 사유): ${val:0:40}"; fi
}
for f in "$@"; do
  bad=()
  [ -f "$f" ] || { echo "REJECT $f — 파일 없음"; rc=1; continue; }
  LEDGER="$(ledger_for "$f")"
  [ -f "$LEDGER" ] || { echo "REJECT $f — 선언된 정본 없음: $LEDGER"; rc=1; continue; }
  LEDGER_N="$(norm < "$LEDGER")"
  grep -qxF -- "$GOAL1" "$f" || bad+=("골 1줄 불일치")
  grep -qxF -- "$GOAL2" "$f" || bad+=("골 2줄 불일치")
  grep -qxF -- "$GOAL3" "$f" || bad+=("골 3줄 불일치")
  for s in "${SECTIONS[@]}"; do grep -qE "^## $s" "$f" || bad+=("절 없음: $s"); done
  # ③ 닫는 증거: 「…」 안 문구 중 하나라도 GOAL-LEDGER 에 실재해야 한다.
  coords="$(section_body "$f" '골좌표' | norm)"
  hit=0
  while IFS= read -r q; do
    q="$(printf '%s' "$q" | sed 's/^ *//;s/ *$//')"
    [ "${#q}" -ge 20 ] || continue
    case "$LEDGER_N" in *"$q"*) hit=1; break;; esac
  done < <(printf '%s\n' "$coords" | python3 -c "import re,sys; [print(m) for m in re.findall('「([^」]+)」', sys.stdin.read())]")   # BSD grep 은 없는 locale(C)에서 [^」] 를 멀티바이트로 못 읽어 0건 — python 은 locale 무관(R175)
  [ "$hit" = 1 ] || bad+=("골좌표: 20자+ 닫는 증거 「…」 가 GOAL-LEDGER 에 없다(복붙이 아니다)")
  # ④ 배경 인용 수 — «정본 문서» 수만 센다(.md 경로). 백틱 코드 식별자는 읽을 문서가 아니다.
  n="$(section_body "$f" '배경' | grep -oE '[A-Za-z0-9_./\-]+\.md' | sort -u | wc -l | tr -d ' ')"
  [ "$n" -le "$MAX_CITES" ] || bad+=("배경 인용 문서 ${n}개 > ${MAX_CITES} — 이 좌석이 못 읽는다")
  # ⑤ 비어 있지 않은가 — env FT_INDEX_ALLOW_EMPTY_BODY=1 «그리고» 카드 머리에 「- 템플릿: 빈 카드(나노가 채움)」 줄이 있을 때만 ⑤⑥ 건너뜀(상속 env 단독으로는 우회 불가 · DA⑥ H1)
  allow_empty=""; [ "${FT_INDEX_ALLOW_EMPTY_BODY:-}" = 1 ] && awk '/^##[[:space:]]/{exit} {print}' "$f" | grep -q '^- 템플릿: 빈 카드(나노가 채움)' && allow_empty=1
  [ "$allow_empty" = 1 ] || for s in '구현 범위' '완료 조건'; do
    [ -n "$(section_body "$f" "$s" | grep -v '^\s*$')" ] || bad+=("절 비어 있음: $s")
  done
  # ⑥ 구현 범위의 파일 경로 중 «하나 이상 실재» (pm#3 #13080 — 경로가 틀리면 나노가 그 자리에서 막힌다).
  #   후보 = 백틱 안 경로(확장자 있는 것) + 맨 경로. 인덱스가 있는 워크트리 루트 기준으로 존재 확인.
  paths="$(section_body "$f" '구현 범위' | grep -oE '[A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.[a-z]{1,5}' | sort -u)"
  if [ -n "$paths" ] && [ "$allow_empty" != 1 ]; then
    ok=0; while IFS= read -r p; do scope_path_exists "$p" && { ok=1; break; }; done <<< "$paths"
    [ "$ok" = 1 ] || bad+=("구현 범위: 인용한 파일 경로가 하나도 실재하지 않는다 ($(printf '%s' "$paths" | head -3 | tr '\n' ' '))")
  fi
  check_proposal_line "$f"
  inst="$(bash "$(dirname "${BASH_SOURCE[0]:-$0}")/ft-index-lint-install.sh" "$f")" || bad+=("$inst")   # ⑩ 하네스 카드 「- 설치:」 줄 (R245)
  if [ "${FT_CARD_REQUIRE_PREVERIFY:-}" = 1 ]; then check_preverify "$f"; check_evidence "$f"; fi
  if [ "${#bad[@]}" -eq 0 ]; then echo "OK $f (ledger=${LEDGER#$ROOT/})${allow_empty:+ (empty-body allowed)}"; else printf 'REJECT %s (ledger=%s)\n' "$f" "${LEDGER#$ROOT/}"; printf '  - %s\n' "${bad[@]}"; rc=1; fi
done
exit $rc
