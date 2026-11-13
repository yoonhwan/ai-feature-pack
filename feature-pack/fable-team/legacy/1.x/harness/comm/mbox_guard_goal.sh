#!/bin/bash
# mbox_guard.sh 가 source 하는 문 ③ 본체 — 골 표 상시 게재(R362 · 200줄 규칙 분리 · 단독 실행 0 · DIR·GUARD_STATE·GOAL_HEADS·goal_armed·_goal_sender_in_roles·_goal_refuse 는 mbox_guard.sh 가 둔다).
# 대상 = 어느 명부(seats*.json)든 `_master`·`_desk`·`_arch` 값인 발신자 ∧ 머리 `[부팅`·`[틱`·`[발주`·`[팀 발주`·`[착지 차례`·`[A6`·`[완료·휴식`
#   (제외 = [HIL]·[긴급]·[반송]·[spawn 정지]·[정지]·[회신]·[착지] — 안전 보고·집행 회신은 막지 않는다 · 나노·tester·DA 발신은 검사 0 · 명부를 못 읽어 판정 불가 = 무장이면 REJECT).
# 판정 = ft-goal-table.sh check (블록 + `골좌표:` 줄 · 판정기 하나). 본문 머리는 «1행» 그대로 · 골 표는 2행부터.
# 무장 표식 = $GUARD_STATE/goal-gate.armed — 있으면 REJECT rc 3(큐 적재 0) · 없으면 WOULD-REJECT 로그만 남기고 통과(설치 전환 · 되돌림 = 표식 삭제).
# relay(H2) = 대상이면 첨부를 «먼저 복사한 사본»에서 검사하고 그 사본만 전달한다 — 복사·읽기 실패 = 검사 실패(원본으로 후퇴 0) · 사본 폴더 = GUARD_TMP(mbox.sh 가 지운다) · 사본 파일 = GUARD_FILE.
#   독립 검증 둘: ①첨부 사본에 골 표 블록 ②요약(본문)에 `골좌표:` 줄 — 좌표는 첨부의 블록 + 요약만으로 판정한다(첨부 안의 골좌표 줄은 요약 대신이 아니다).
# 판정기 부재·실행 실패 = 무장이면 REJECT(fail-closed) · 아니면 WOULD-REJECT. 외부 호출 0.
# r726 r3: 유예로 통과한 판정(«옛 번호표(유예 …)») 은 `GL-GRACE …` 1줄로 stderr 에 보인다 — ★본문 판정 rc0 때만★(relay 첨부 검사에서는 내지 않는다: 경고가 2줄이 되거나 REJECT 출력 앞에 붙는다 · r4).

guard_tmp_clean() { [ -z "${GUARD_TMP:-}" ] || rm -rf "$GUARD_TMP"; }  # relay 검사 사본 폴더 정리(mbox.sh 가 끝에 부른다)

# r726 r3(DA 질문 6): 유예로 통과한 판정은 송신자에게 «보여야» 한다 — 판정 출력의 유예 줄을 stderr 로 1줄(송신은 그대로 통과).
_goal_grace_note() {
  local line
  line="$(printf '%s\n' "$1" | grep -m1 '옛 번호표(유예')" || return 0
  [ -n "$line" ] && printf 'GL-GRACE %s\n' "$line" >&2
  return 0
}

_goal_block_of() { awk '/^★골 표 A6 \(/{f=1} f{print} /^★\/골 표★$/{f=0}' "$1"; }  # 파일에서 마커 블록만
_goal_trim() { awk '/^★골 표 A6 \(/{f=1} !f{print} /^★\/골 표★$/{f=0}'; }  # r1830 G3: 마커 블록만 뗀다(나머지 줄 그대로)

# _guard_goal_lint <본문> <발신자> [첨부 파일] — rc 3 = REJECT. 첨부가 있고 대상이면 GUARD_FILE·GUARD_TMP 를 정한다.
_guard_goal_lint() {
  local body="$1" from="${2:-}" attach="${3:-}" first tool res rc why text coord="" cut=0
  first="${body%%$'\n'*}"; first="${first#"${first%%[![:space:]]*}"}"
  if ! printf '%s' "$first" | grep -qE "$GOAL_TABLE_HEADS|$GOAL_COORD_HEADS"; then   # r1847 표·좌표 머리 밖 = 붙은 표만 뗀다(머리·발신자 검사 앞 · 판정 0 · 좌표 머리는 아래 r1830 그대로)
    case "$GUARD_BODY" in *"★골 표 A6 ("*) text="$(printf '%s\n' "$GUARD_BODY" | _goal_trim)"
      cut=$(( $(printf '%s' "$GUARD_BODY" | wc -c) - $(printf '%s' "$text" | wc -c) )); GUARD_BODY="$text";; esac
    [ -n "$attach" ] && grep -q '^★골 표 A6 (' "$attach" 2>/dev/null && GUARD_TMP="$(mktemp -d "$GUARD_STATE/goal-relay.XXXXXX" 2>/dev/null)" \
      && _goal_trim < "$attach" > "$GUARD_TMP/$(basename "$attach")" && GUARD_FILE="$GUARD_TMP/$(basename "$attach")" && cut=$(( cut + $(wc -c < "$attach") - $(wc -c < "$GUARD_FILE") ))   # relay = 사본만(원본 손 0)
    [ "$cut" = 0 ] || echo "GOAL-TRIM ${cut}B" >&2; return 0; fi
  printf '%s' "$first" | grep -qE "$GOAL_HEADS" || return 0
  [ -n "$from" ] || return 0
  _goal_sender_in_roles "$from"; rc=$?
  [ "$rc" = 1 ] && return 0
  [ "$rc" = 0 ] || { _goal_refuse "$from" "$first" "발신자 대상 여부 판정 불가(명부 읽기 실패)"; return $?; }
  tool="$(_ft_live_bin ft-goal-table.sh 2>&1)" || { _goal_refuse "$from" "$first" "판정기 없음($tool)"; return $?; }
  [ -n "${GOAL_COORD_HEADS:-}" ] && printf '%s' "$first" | grep -qE "$GOAL_COORD_HEADS" && coord=1   # r1830 G2 좌표 머리 = `check - --coord-only`(블록 요구 0)
  [ -n "$coord" ] && case "$body" in *"★골 표 A6 ("*) text="$(printf '%s\n' "$body" | _goal_trim)"   # G3 붙은 표는 떼고 적재(GUARD_BODY)
    cut=$(( $(printf '%s' "$body" | wc -c) - $(printf '%s' "$text" | wc -c) )); body="$text"; GUARD_BODY="$text";; esac
  if [ -n "$attach" ]; then
    GUARD_TMP="$(mktemp -d "$GUARD_STATE/goal-relay.XXXXXX" 2>/dev/null)" && [ -f "$attach" ] && cp "$attach" "$GUARD_TMP/$(basename "$attach")" 2>/dev/null \
      && GUARD_FILE="$GUARD_TMP/$(basename "$attach")" && [ -r "$GUARD_FILE" ] || { GUARD_FILE=""; _goal_refuse "$from" "$first" "relay 첨부 사본 생성·읽기 실패($attach)"; return $?; }
    if [ -n "$coord" ]; then { ! grep -q '^★골 표 A6 (' "$GUARD_FILE" || { cut=$(( cut + $(wc -c < "$GUARD_FILE") )); _goal_trim < "$GUARD_FILE" > "$GUARD_FILE.t" && mv "$GUARD_FILE.t" "$GUARD_FILE" && cut=$(( cut - $(wc -c < "$GUARD_FILE") )); }; }; text="$body"; else   # G3 사본만 뗀다(원본 손 0)
    res="$(bash "$tool" check - --block-only < "$GUARD_FILE" 2>&1)"; rc=$?
    [ "$rc" = 0 ] || { _goal_refuse "$from" "$first" "첨부 사본: ${res#REJECT 골 없음 — }"; return $?; }
    text="$(_goal_block_of "$GUARD_FILE")"$'\n'"$body"; fi   # 좌표는 요약에서만(첨부의 좌표 줄은 세지 않는다)
  else text="$body"; fi
  [ "$cut" = 0 ] || echo "GOAL-TRIM ${cut}B" >&2   # fix1(DA HOLD R1): 요약·relay 사본에서 뗀 바이트 합 = 쪽지당 1줄
  res="$(printf '%s' "$text" | bash "$tool" check - ${coord:+--coord-only} 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then _goal_grace_note "$res"; return 0; fi
  why="${res#REJECT 골 없음 — }"; [ "$rc" = 3 ] || why="판정기 실행 실패 rc=$rc ${res:0:80}"
  _goal_refuse "$from" "$first" "$why"
}
