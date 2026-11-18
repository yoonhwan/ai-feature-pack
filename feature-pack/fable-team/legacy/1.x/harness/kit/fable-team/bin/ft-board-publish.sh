#!/usr/bin/env bash
# ft-board-publish.sh — 보드 발행 (판정 421·423·430·431 · 설계 §2-3): 스냅샷 «먼저» → 하루 1 뿌리 글 갱신 + 변화 답글 + 날짜 동결.
#   ft-board-publish.sh        rc: snapshot rc≠0 → 발행 0 · 그 rc 그대로 | update rc(1 실패 · 3 답글만 실패=reply_pending) 그대로 | 4 전날 동결 실패 | 0
# env: FT_ROOT(루트) · FT_BOARD_BIN(기본 같은 폴더 ft-board.py · 시험은 스텁) · FT_THREAD_POST(기본 ~/.hermes/scripts/byz_thread_post.py)
#      FT_BOARD_LEDGER(장부 · 기본은 도구 기본값) · FT_BOARD_POST_ARGS(도구에 덧붙일 인자 · 예 `--slack-base http://127.0.0.1:PORT --token-file F`)
#      FT_BOARD_NOW(날짜 주입 · 시험) · FT_BOARD_ONLY_CHANGED=1(주기 틱용 — 뿌리 글이 안 바뀌었으면 스냅샷·발행 0 · 기본 0 = 항상 발행)
#      FT_SHEET_VERIFY=1 = --sheet 발행 성공 뒤 ft-sheet-verify.sh 1회(S3 · 기본 0)
#      --news = 보드 뉴스 채널 최상위 글(r2058 → r2120): collect 1회 → ft_board_news.py 본문·열쇠 → 직전 발행(state/board/news-last.json)과 열쇠가 다르고
#               300초가 지났을 때만 byz_thread_post.py post(채널 = FT_BOARD_POST_ARGS 의 --channel) 1회 · rc 0 일 때만 news-last 갱신 · --channel 없음 = rc 2
#               FT_BOARD_THREAD_TS 는 읽지 않는다(r2120)
#      --sheet = 현황판 시트 발행(ft-sheet-publish.sh · 트리 뿌리 글 + 발행 rev 변화 때만 PDF 첨부 · PLAN-status-sheet §4) — 기본 경로는 그대로
# 발행 본문은 날짜 폴더 published.txt 에 남겨 다음 날 동결 때 쓴다. 실제 슬랙 호출은 도구가 한다 — 이 스크립트는 직접 부르지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BOARD="${FT_BOARD_BIN:-$HERE/ft-board.py}"
TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
ROOT="${FT_ROOT:-}"   # r385b: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 2
# 조율 몫·주간 환산 보드(카드 usage-monitor-coord-weekly U9) — 덧 호출 1줄: 실패·시간 초과·도구 없음이어도 아래 rc·출력·발행은 그대로.
SHARE="${FT_CTX_SHARE_BIN:-$HOME/.local/bin/ctx-share}"; { [ -x "$SHARE" ] && perl -e "alarm ${FT_CTX_SHARE_TIMEOUT:-25}; exec @ARGV" "$SHARE" --out "$ROOT/.fable-team/state/usage-monitor" >/dev/null 2>&1; } || :
DAY="${FT_BOARD_NOW:+${FT_BOARD_NOW:0:10}}"; DAY="${DAY:-$(date +%F)}"
SD="$ROOT/.fable-team/state/board"
[ -f "$TP" ] || { echo "ft-board-publish: 도구 없음 $TP (#0 RULE · 폴백 0)" >&2; exit 2; }

# shellcheck disable=SC2206
POST_ARGS=(${FT_BOARD_POST_ARGS:-}); [ -n "${FT_BOARD_LEDGER:-}" ] && POST_ARGS+=(--ledger "$FT_BOARD_LEDGER")
if [ "${1:-}" = "--news" ]; then
  CH=""; for ((i = 0; i < ${#POST_ARGS[@]}; i++)); do [ "${POST_ARGS[i]}" = --channel ] && CH="${POST_ARGS[i + 1]:-}"; done
  [ -n "$CH" ] || { echo "ft-board-publish: ERROR 뉴스 채널 없음(FT_BOARD_POST_ARGS --channel) — 발행 0" >&2; exit 2; }
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  # r2126 H2: collect · ft_board_news · post 실패 = planner 명부 _desk 에 «[긴급] 자동 뉴스 실패 — <단계> rc=<n>» 1통(FT_MBOX → comm/mbox.sh · 25초)
  #   (단계, rc)별 30분 창 · 표식 state/board/news-fail-last.json = send 성공 뒤에만 · 좌석 없음 ∨ send 실패 = stderr 1줄 · 각 단계 rc 그대로
  fail_mark() { python3 - "$SD/news-fail-last.json" "$1" "$2" "${FT_BOARD_NOW:-}" <<'PY'
import json, sys
from datetime import datetime
from pathlib import Path
f, k, op, at = Path(sys.argv[1]), *sys.argv[2:5]
now = datetime.fromisoformat(at) if at else datetime.now()
try:
    d = json.loads(f.read_text(encoding="utf-8"))
except (OSError, ValueError):
    d = {}
if op == "check":
    sys.exit(0 if k not in d or (now - datetime.fromisoformat(d[k])).total_seconds() >= 1800 else 3)  # 3 = 창 안(그 밖 rc = 표식 못 읽음 → 보냄)
f.parent.mkdir(parents=True, exist_ok=True)
f.write_text(json.dumps({**d, k: now.isoformat()}, ensure_ascii=False), encoding="utf-8")
PY
  }
  news_fail() { local k="$1 rc=$2" mb="${FT_MBOX:-$ROOT/.fable-team/comm/mbox.sh}" desk
    fail_mark "$k" check 2>/dev/null; [ $? -eq 3 ] && return 0
    desk="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_desk") or "")' "$ROOT/.fable-team/seats-planner.json" 2>/dev/null)"
    if [ -n "$desk" ] && perl -e 'alarm 25; exec @ARGV' bash "$mb" send "$desk" ft-board-news "[긴급] 자동 뉴스 실패 — $k" >/dev/null 2>&1; then
      fail_mark "$k" mark
    else echo "ft-board-publish: 판정 불가 — desk 알림 실패($k)" >&2; fi; }
  "$BOARD" collect --out "$TMP/collect.json"; rc=$?
  [ "$rc" -eq 0 ] || { echo "ft-board-publish: collect 실패 rc=$rc — 발행 0" >&2; news_fail collect "$rc"; exit "$rc"; }
  V="$(FT_ROOT="$ROOT" python3 "$HERE/ft_board_news.py" --collect "$TMP/collect.json" --last "$SD/news-last.json" --body "$TMP/body.txt" --state "$TMP/state.json")"; rc=$?
  [ "$rc" -eq 0 ] || { news_fail ft_board_news "$rc"; exit "$rc"; }
  [ "$V" = POST ] || { echo "ft-board-publish: $V"; exit 0; }
  # r2108: 오빠 태그 1개만 진짜 태그로 — UID = env FT_OPPA_SLACK_UID ∨ ft_oppa_slack_check.OPPA_SLACK_UID(body 모듈과 같은 출처) · 읽기 실패 = 인자 없이
  #   python 1회 · 7초 상한(perl alarm · macOS 에 timeout 없음) · rc 0 일 때만 출력을 씀다(rc≠0 ∨ 7초 넘음 = 실패)
  OU="${FT_OPPA_SLACK_UID:-}"
  [ -n "$OU" ] || OU="$(perl -e 'alarm 7; exec @ARGV' python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from ft_oppa_slack_check import OPPA_SLACK_UID; print(OPPA_SLACK_UID)' "$HERE" 2>/dev/null)" || OU=""
  KM=(); [ -n "$OU" ] && KM=(--keep-mention "$OU") || echo "ft-board-publish: WARN 오빠 UID 읽기 실패 — 태그 인자 없이 발행" >&2
  python3 "$TP" post ${POST_ARGS[@]+"${POST_ARGS[@]}"} --no-status-head ${KM[@]+"${KM[@]}"} --text-file "$TMP/body.txt"; rc=$?
  [ "$rc" -eq 0 ] || { echo "ft-board-publish: post 실패 rc=$rc — news-last 그대로" >&2; news_fail post "$rc"; exit "$rc"; }
  mkdir -p "$SD" && cp "$TMP/state.json" "$SD/news-last.json.tmp" && mv "$SD/news-last.json.tmp" "$SD/news-last.json" \
    || { echo "ft-board-publish: news-last 기록 실패" >&2; exit 1; }
  echo "ft-board-publish: 글 1통 발행"; exit 0
fi
if [ "${1:-}" = "--sheet" ]; then
  bash "$HERE/ft-sheet-publish.sh"; rc=$?
  # S3: 발행 성공 뒤 검증 1회(FT_SHEET_VERIFY=1 인 plist 에서만) — 검증 실패는 발행 rc 를 바꾸지 않는다
  if [ "$rc" -eq 0 ] && [ "${FT_SHEET_VERIFY:-0}" = 1 ]; then bash "$HERE/ft-sheet-verify.sh" || echo "ft-board-publish: 시트 검증 rc=$? — 발행 rc 불변" >&2; fi
  exit "$rc"
fi
tp() { python3 "$TP" update ${POST_ARGS[@]+"${POST_ARGS[@]}"} "$@"; }

BODY="$("$BOARD" render --slack --refresh-gh)"; rc=$?
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

SNAP="$("$BOARD" snapshot --refresh-gh)"; rc=$?
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
