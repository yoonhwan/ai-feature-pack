#!/usr/bin/env bash
# fake-tank.sh <comment|label> <번호> … — 가짜 Tank 래퍼 (R102 게이트 시험용 · 실 gh 호출 0)
# 호출을 FAKE_LOG 에 `step=<단계>` 로 남기고, 상태 파일(FAKE_STATE · GitHub 흉내)에 코멘트·라벨을 «실제로» 추가한다.
#   단계 = comment-keep(본문에 `-keep]`) · comment-marker(본문에 `-marker`) · comment · label
#   FAKE_FAIL=<단계>                 → 그 단계는 쓰지 않고 rc 1
#   FAKE_TIMEOUT_AFTER_WRITE=<단계>  → 쓰고 나서 rc 124 (결과 불명 흉내)
#   FAKE_SLEEP=<초>                  → 시작 전에 잠든다 (timeout 시험)
set -uo pipefail
ACT="${1:-}"; N="${2:-}"; shift 2 || true
[ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_SLEEP"
STEP=""; BODY=""
case "$ACT" in
  comment)
    BODY="$(cat "$1")"
    case "$BODY" in *-keep\]*) STEP=comment-keep;; *-marker*) STEP=comment-marker;; *) STEP=comment;; esac;;
  label) STEP=label;;
  *) echo "fake-tank: 지원 안 함 $ACT" >&2; exit 2;;
esac
echo "$ACT $N step=$STEP" >> "$FAKE_LOG"
[ "${FAKE_FAIL:-}" = "$STEP" ] && { echo "fake-tank: $STEP 실패(FAKE_FAIL)" >&2; exit 1; }
TMP="$FAKE_STATE.tmp.$$"
if [ "$ACT" = comment ]; then
  jq --arg b "$BODY" '.comments += [{body:$b}]' "$FAKE_STATE" > "$TMP" && mv "$TMP" "$FAKE_STATE"
else
  jq '.labels = ((.labels // []) + [{name:"status:observing"}] | unique_by(.name))' "$FAKE_STATE" > "$TMP" && mv "$TMP" "$FAKE_STATE"
fi
[ "${FAKE_TIMEOUT_AFTER_WRITE:-}" = "$STEP" ] && exit 124
exit 0
