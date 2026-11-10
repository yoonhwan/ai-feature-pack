#!/bin/bash
# fable-team retired-seat-guard — 은퇴 좌석 판정 주입 (UserPromptSubmit · R30)
# 입력마다 `ft-seat-handover.sh status <내 세션>` 을 돌려 RETIRED/MISMATCH 면 additionalContext 로 행동 규칙을 주입한다.
# ACTIVE 면 출력 0. tmux 밖이면 좌석이 아니므로 출력 0. status 실패 = 보이는 오류 주입(조용한 통과 0).
# 세션은 $TMUX_PANE 으로 고정(ambient/default 세션 오독 차단 · DA H3).
set +e
cat >/dev/null 2>&1
[ -n "${TMUX_PANE:-}" ] || exit 0
# 루트 = git 공용 디렉터리의 상위(워크트리 좌석도 메인 루트로 풀림). 그 루트에 명부(seats*.json)가 없으면 팀 좌석이 아니다 → 출력 0.
if [ -z "${FT_ROOT:-}" ]; then
  COMMON="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$COMMON" ] || exit 0
  FT_ROOT="$(dirname "$COMMON")"
fi
ls "$FT_ROOT"/.fable-team/seats*.json >/dev/null 2>&1 || exit 0
FT_BIN="${FT_BIN:-$FT_ROOT/.fable-team/bin}"
emit() {
  jq -cn --arg m "$1" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
  exit 0
}
ME="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)"
[ -n "$ME" ] || emit "[retired-seat-guard 오류] 내 tmux 세션명을 읽지 못함(TMUX_PANE=$TMUX_PANE) — 은퇴 여부 판정 불가. 하네스 master 에 알릴 것."
[ -x "$FT_BIN/ft-seat-handover.sh" ] || emit "[retired-seat-guard 오류] $FT_BIN/ft-seat-handover.sh 없음 — 은퇴 여부 판정 불가. 하네스 master 에 알릴 것."
OUT="$("$FT_BIN/ft-seat-handover.sh" status "$ME" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] || emit "[retired-seat-guard 오류] status 실패 rc=$RC: $OUT"
case "$OUT" in
  ACTIVE) exit 0;;
  "RETIRED "*)
    X="${OUT#RETIRED }"
    emit "[R30 은퇴 좌석] 이 좌석($ME)은 후계 $X 로 승계됐다. 읽기 전용 질의(직전 세션 기록·근거 질문)는 자기 이력으로 답한다. 새 작업·새 판정·판정 번호 부여 0. 새 요청이면 원문 그대로 mbox send $X $ME \"[relay 오빠 원문] …\" 1통 → QUEUED seq 확인 + ft-reach-check.sh $X <seq> 도달 확인 뒤에만 오빠께 「후계 $X 에 전달했어요(쪽지 seq)」 1줄. 도달 미확인이면 「$X 에 보냈지만 도착 확인 안 됨」 그대로 전한다. 「창은 이미 옮겨 둠」 같은 현재 창 상태 단정 문구 0."
    ;;
  "MISMATCH"*)
    # 세션당 1회만 mbox 지시(옛 좌석이 매 입력·틱마다 master 에 쪽지를 쏟는 것 차단)
    if [ "$(tmux show-option -t "=$ME" -qv @handover_mismatch_reported 2>/dev/null)" = 1 ]; then
      emit "[R30 후계 관계 불일치 · 이미 보고됨] 이 좌석($ME)은 불일치($OUT)를 이미 하네스 master 에 보고했다. 새 판정·relay 0. 추가 mbox 발신 0."
    fi
    tmux set-option -t "=$ME" @handover_mismatch_reported 1 2>/dev/null
    emit "[R30 후계 관계 불일치] 이 좌석($ME)의 후계 관계가 장부·명부에서 어긋남($OUT). 새 판정·relay 0. 오빠께 「이 좌석의 후계 관계가 장부·명부에서 어긋남 — 하네스 master 에 확인 요청함」 1줄 + 하네스 master 에 mbox send … \"[handover-mismatch] $OUT\" 1통."
    ;;
  *) emit "[retired-seat-guard 오류] status 출력 해석 불가: $OUT";;
esac
