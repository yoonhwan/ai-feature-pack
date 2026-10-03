#!/usr/bin/env bash
# ft-index-move.sh <indices/<from>/X.md> <대기|진행|완성> [--da <판정문경로#§N>] [--seat <좌석명>]
#   Seatbelt 0.3 · 인덱스 상태 = 폴더. «닫힘» 글자를 손으로 쓸 자리를 없앤다.
#   exit 0 = 이동 · 1 = REJECT · 2 = usage
# 규칙:
#   대기→진행 : lint 통과 + --seat 필수(누가 들고 가는지). §상태 에 한 줄 append.
#   진행→완성 : --da 필수. 판정문 파일이 실재하고 그 §N 절에 「닫힘」 또는 「CLOSE」가 있어야 한다.
#               (DA 가 안 쓴 「닫힘」은 없다 — pm·master 가 대신 쓸 길을 두지 않는다.)
#   기타 방향 : 되돌리기(진행→대기 등)는 --seat 로 사유만 남기고 허용.
set -uo pipefail
SRC="${1:-}"; DST="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <index.md> <대기|진행|완성> [--da <file#§N>] [--seat <name>]" >&2; exit 2; }
DA=""; SEAT=""
while [ $# -gt 0 ]; do case "$1" in --da) DA="$2"; shift 2;; --seat) SEAT="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$DST" in 대기|진행|완성) ;; *) echo "REJECT dst 는 대기|진행|완성" >&2; exit 2;; esac
[ -f "$SRC" ] || { echo "REJECT 없음: $SRC"; exit 1; }
SRC="$(cd -- "$(dirname -- "$SRC")" && pwd)/$(basename -- "$SRC")"   # 절대경로 — 상대경로면 아래 git -C ls-files 추적 판정이 untracked 로 떨어져 mv 가 된다(DA r1 R5)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
IDX_ROOT="$(cd "$(dirname "$SRC")/.." && pwd)"
FROM="$(basename "$(dirname "$SRC")")"
[ "$FROM" != "$DST" ] || { echo "REJECT 이미 $DST 에 있다"; exit 1; }
if [ "$DST" = 진행 ]; then
  bash "$HERE/ft-index-lint.sh" "$SRC" || { echo "REJECT lint 실패 — 위 사유"; exit 1; }
  [ -n "$SEAT" ] || { echo "REJECT 대기→진행 은 --seat <좌석명> 필수"; exit 1; }
fi
if [ "$DST" = 완성 ]; then
  [ -n "$DA" ] || { echo "REJECT 진행→완성 은 --da <판정문#§N> 필수 — DA 판정 없이 닫지 않는다"; exit 1; }
  DAF="${DA%%#*}"; SEC="${DA#*#}"
  [ -f "$DAF" ] || { echo "REJECT DA 판정문 없음: $DAF"; exit 1; }
  # §N 절 본문에 닫힘/CLOSE 가 있어야 한다 (## 헤더가 §N 을 포함하는 절)
  body="$(awk -v s="$SEC" 'index($0,"## ")==1{f=index($0,s)>0; if(f){print;next}} f' "$DAF")"
  [ -n "$body" ] || { echo "REJECT $DAF 에 절 «$SEC» 없음"; exit 1; }
  printf '%s' "$body" | grep -qE '닫힘|CLOSE' || { echo "REJECT $DAF $SEC 에 「닫힘」/「CLOSE」 없음 — DA 가 닫지 않았다"; exit 1; }
fi
mkdir -p "$IDX_ROOT/$DST"
NEW="$IDX_ROOT/$DST/$(basename "$SRC")"
TRACKED=0; git -C "$IDX_ROOT" ls-files --error-unmatch "$SRC" >/dev/null 2>&1 && TRACKED=1
if [ "$TRACKED" = 1 ]; then git mv "$SRC" "$NEW"; else mv "$SRC" "$NEW"; fi || { echo "REJECT 이동 실패: $SRC → $NEW"; exit 1; }
if [ "$DST" = 완성 ]; then
  # 하네스 0.5 행 3 — «완성 이동»이 원장 close 의 유일한 기록자. 원장 없는 완성은 없다(#0 RULE).
  #   트랙 = FT_TRACK(기본 default · 카드가 design/v65/indices 아래면 v65) · $ROOT/STATE_DIR 은 ft-index-gate.sh 와 같은 규약.
  ROOT="$(git -C "$IDX_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  STATE_DIR="${FT_INDEX_STATE_DIR:-$ROOT/.fable-team/state}"
  TRACK="${FT_TRACK:-}"
  [ -n "$TRACK" ] || case "$IDX_ROOT" in */design/v65/indices) TRACK=v65;; *) TRACK=default;; esac
  LEDGER="$STATE_DIR/index-ledger.$TRACK.jsonl"
  ID="$(basename "$SRC" .md)"
  row="{\"ts\":\"$(date '+%Y-%m-%dT%H:%M:%S%z')\",\"ev\":\"close\",\"id\":\"$ID\",\"da\":\"$DA\",\"seat\":\"${SEAT:--}\",\"via\":\"index-move\"}"
  if ! printf '%s\n' "$row" >> "$LEDGER" 2>/dev/null; then
    # 되돌리기도 실패할 수 있다(DA r1 R1) — 성공 문구는 되돌리기가 «실제로» 성공했을 때만.
    if { [ "$TRACKED" = 1 ] && git mv "$NEW" "$SRC"; } || { [ "$TRACKED" != 1 ] && mv "$NEW" "$SRC"; }; then
      echo "REJECT 원장에 못 썼다: $LEDGER — 이동을 되돌렸다"; exit 1
    fi
    echo "REJECT 원장에 못 썼다: $LEDGER" >&2
    echo "★되돌리기 실패 — 카드 ${NEW} · 원장 0 · 복구: git mv ${NEW} ${SRC}★" >&2; exit 3
  fi
fi
printf -- '- %s — %s→%s%s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$FROM" "$DST" "${SEAT:+ · 좌석 $SEAT}" "${DA:+ · DA $DA}" >> "$NEW"
printf 'MOVED %s→%s %s\n' "$FROM" "$DST" "$NEW"
