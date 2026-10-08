#!/usr/bin/env bash
# ft-board-publish.sh — 보드 발행 (판정 421·423·430·431 · 설계 §2-3): 스냅샷 «먼저» → 하루 1 뿌리 글 갱신 + 변화 답글 + 날짜 동결.
#   ft-board-publish.sh        rc: snapshot rc≠0 → 발행 0 · 그 rc 그대로 | update rc(1 실패 · 3 답글만 실패=reply_pending) 그대로 | 4 전날 동결 실패 | 0
# env: FT_ROOT(루트) · FT_BOARD_BIN(기본 같은 폴더 ft-board.py · 시험은 스텁) · FT_THREAD_POST(기본 ~/.hermes/scripts/byz_thread_post.py)
#      FT_BOARD_LEDGER(장부 · 기본은 도구 기본값) · FT_BOARD_POST_ARGS(도구에 덧붙일 인자 · 예 `--slack-base http://127.0.0.1:PORT --token-file F`)
#      FT_BOARD_NOW(날짜 주입 · 시험) · FT_BOARD_ONLY_CHANGED=1(주기 틱용 — 뿌리 글이 안 바뀌었으면 스냅샷·발행 0 · 기본 0 = 항상 발행)
# 발행 본문은 날짜 폴더 published.txt 에 남겨 다음 날 동결 때 쓴다. 실제 슬랙 호출은 도구가 한다 — 이 스크립트는 직접 부르지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BOARD="${FT_BOARD_BIN:-$HERE/ft-board.py}"
TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
ROOT="${FT_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir | xargs dirname)}"
DAY="${FT_BOARD_NOW:+${FT_BOARD_NOW:0:10}}"; DAY="${DAY:-$(date +%F)}"
SD="$ROOT/.fable-team/state/board"
[ -f "$TP" ] || { echo "ft-board-publish: 도구 없음 $TP (#0 RULE · 폴백 0)" >&2; exit 2; }

# shellcheck disable=SC2206
POST_ARGS=(${FT_BOARD_POST_ARGS:-}); [ -n "${FT_BOARD_LEDGER:-}" ] && POST_ARGS+=(--ledger "$FT_BOARD_LEDGER")
tp() { python3 "$TP" update ${POST_ARGS[@]+"${POST_ARGS[@]}"} "$@"; }

BODY="$("$BOARD" render --slack)"; rc=$?
[ "$rc" -eq 0 ] && [ -n "$BODY" ] || { echo "ft-board-publish: render 실패 rc=$rc — 발행 0" >&2; exit "$((rc == 0 ? 1 : rc))"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 슬랙 뿌리 글 = 머리 + ⓪ + ④ + 끝줄, UTF-8 3500B 상한(chat.update 거부선 ~3.9KB) — 절 머리 없음·상한 실패 = 발행 0
printf '%s' "$BODY" | python3 "$HERE/ft_board_root.py" root > "$TMP/body.txt" \
  || { echo "ft-board-publish: 뿌리 글 본문 만들기 실패 — 발행 0" >&2; exit 1; }

# 바뀜 판정(FT_BOARD_ONLY_CHANGED=1 일 때만): 머리 시각·«정지 N분» 숫자만 지운 꼴이 직전 발행본과 같고 reply_pending 표식이 없으면 스냅샷·발행 0
# R62: 분마다 바뀌는 조각(원 쪽지 뒤 N분·턴 끝 HH:MM·작업중↔정지 N분)도 비교 키에서만 지운다 — ⚠(3분 넘김)는 «먼저» ⚠STALL 로 남긴다
norm() { sed -E -e '1s/[0-9]{2}:[0-9]{2}//' -e 's/정지 [0-9]+분/정지 N분/g' -e 's/원 쪽지 뒤 [0-9]+분/원 쪽지 뒤 N분/g' \
  -e 's/\(턴 끝 ([0-9]{2}:[0-9]{2}|확인 불가)\)/(턴 끝 *)/g' -e 's/⚠정지 N분\(턴 끝 \*\)/⚠STALL/g' \
  -e 's/정지 N분\(턴 끝 \*\)/활동/g' -e 's/작업중(\(pane\))?/활동/g' -e 's/확인 불가\(첫 턴 전\)/활동/g' "$1"; }
FIRST_OF_DAY=0; [ -f "$SD/$DAY/published.txt" ] || FIRST_OF_DAY=1
if [ "${FT_BOARD_ONLY_CHANGED:-0}" = 1 ]; then
  if [ "$FIRST_OF_DAY" = 0 ] && [ ! -f "$SD/$DAY/reply_pending" ] \
     && cmp -s <(norm "$TMP/body.txt") <(norm "$SD/$DAY/published.txt"); then
    echo "ft-board-publish: 변화 없음 — 스냅샷·발행 0"; exit 0
  fi
  # 날짜 첫 발행 = 스냅샷 7일 보존(판정 558 ③ ⓐ) · 실패는 기록만, 발행 rc 불변
  if [ "$FIRST_OF_DAY" = 1 ]; then
    "$BOARD" prune --days 7 >/dev/null || echo "ft-board-publish: prune 실패 rc=$? — 기록만(발행 계속)" >&2
  fi
fi

SNAP="$("$BOARD" snapshot)"; rc=$?
[ "$rc" -eq 0 ] && [ -n "$SNAP" ] || { echo "ft-board-publish: snapshot 실패 rc=$rc — 발행 0" >&2; exit "$((rc == 0 ? 1 : rc))"; }
# 변화 답글 1줄 = changes(최대 8건) + snap=전→후 · 변화 없으면 답글 0(reply_pending 은 도구가 따로 챙긴다)
REPLY="$(printf '%s' "$SNAP" | python3 -c 'import json,sys
d=json.load(sys.stdin); c=d["changes"]; s=d["snap"]
print(" · ".join(c[:8]) + (" 외 %d건" % (len(c)-8) if len(c)>8 else "") + " · snap=" + s if c else "")')" || { echo "ft-board-publish: snapshot 출력 해석 실패" >&2; exit 1; }
PREV="$(printf '%s' "$SNAP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("prev_day_last") or "")')"

ARGS=(--key "board:$DAY" --text-file "$TMP/body.txt"); [ -n "$REPLY" ] && ARGS+=(--reply "$REPLY")
tp "${ARGS[@]}"; rc=$?
{ [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; } || exit "$rc"   # update 자체 실패 = 본문 기록 0
mkdir -p "$SD/$DAY" && cp "$TMP/body.txt" "$SD/$DAY/published.txt" || { echo "ft-board-publish: published.txt 기록 실패" >&2; exit 1; }
# 답글만 실패(rc 3) = 표식 → 다음 틱이 본문 같아도 1회 더 부른다 · rc 0 이면 표식 삭제
if [ "$rc" -eq 3 ]; then : > "$SD/$DAY/reply_pending"; else rm -f "$SD/$DAY/reply_pending"; fi

# 날짜 첫 발행 = 전날 뿌리 글 끝에 마지막 스냅샷 id 를 박고 동결(update 1회 · 이후 전날 키 갱신 0)
if [ -n "$PREV" ]; then
  PD="$(ls -d "$SD"/????-??-?? 2>/dev/null | awk -v d="$SD/$DAY" '$0 < d' | tail -1)"
  if [ -n "$PD" ] && [ -f "$PD/published.txt" ] && [ ! -f "$PD/frozen" ]; then
    python3 "$HERE/ft_board_root.py" cap --tail "$(printf '\n동결 — 마지막 스냅샷 %s' "$PREV")" < "$PD/published.txt" > "$TMP/frozen.txt" \
      || { echo "ft-board-publish: 동결 본문 만들기 실패" >&2; [ "$rc" -eq 0 ] && rc=4; exit "$rc"; }
    if tp --key "board:$(basename "$PD")" --text-file "$TMP/frozen.txt" && : > "$PD/frozen"; then :; else
      echo "ft-board-publish: 전날($(basename "$PD")) 동결 실패" >&2; [ "$rc" -eq 0 ] && rc=4
    fi
  fi
fi
exit "$rc"
