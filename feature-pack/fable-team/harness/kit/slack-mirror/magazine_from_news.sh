#!/usr/bin/env bash
# magazine_from_news.sh [magazine_doc.py 인자…] — 08:00 매거진 원본 연결 (R125 · 판정 1437: 매거진 = 오빠 원장 전체)
# 원본 = 오빠 원장(PLAN-oppa-ledger.md)의 «지금 커밋» 한 판 — 뉴스(바뀐 줄만)와 같은 파일, 크기만 다르다. magazine_doc.py(r117)를 부른다.
# 원장이 없거나 커밋 전이면 ERROR + rc≠0 · 커밋 뒤 고쳤으면 «미커밋 수정» ERROR + rc 5 — 빈·낡은 매거진을 만들지 않는다(#0 RULE · 폴백 0).
# r503: 원본 사본은 뉴스와 같은 사본·같은 경로 — 시작에서 ft-ledger-repo-sync.sh 로 origin/main 전진(가지 위·더러움·fetch 실패 = exit 6 · 낡은 매거진 발행 0) · 같은 틱에 이미 했으면(FT_LEDGER_SYNCED=1) 건너뜀
# env: FT_ROOT(필수) · FT_LEDGER_REPO(기본 <루트>/.worktrees/news-ledger-main) · FT_LEDGER_PATH(기본 design/teams/planner/PLAN-oppa-ledger.md) · FT_LEDGER_SYNC(기본 <루트>/.fable-team/LIVE_BIN 의 ft-ledger-repo-sync.sh · 시험 대역) · FT_NEWS_NOW(판 날짜 · 시험) · FT_MAGAZINE_DOC(시험용 대역)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FT_ROOT:?magazine_from_news: FT_ROOT 필요}"
REPO="${FT_LEDGER_REPO:-$ROOT/.worktrees/news-ledger-main}"
REL="${FT_LEDGER_PATH:-design/teams/planner/PLAN-oppa-ledger.md}"
if [ "${FT_LEDGER_SYNCED:-}" != 1 ]; then
  SYNC="${FT_LEDGER_SYNC:-$(cat "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null)/ft-ledger-repo-sync.sh}"
  OUT="$(bash "$SYNC" "$REPO" 2>&1)" || { echo "ERROR magazine_from_news: 원장 사본 갱신 실패 — ${OUT:-$SYNC 실행 실패}" >&2; exit 6; }
  echo "$OUT" >&2
fi
[ -f "$REPO/$REL" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — 원장 $REPO/$REL 이 없다(빈 매거진 발행 0)" >&2; exit 2; }
SHA="$(git -C "$REPO" log -1 --format=%H -- "$REL" 2>&1)" || { echo "ERROR magazine_from_news: git log 실패 — $SHA" >&2; exit 4; }
[ -n "$SHA" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — $REL 이 커밋되지 않았다(magazine_doc 은 git 원문을 읽는다)" >&2; exit 3; }
# 커밋 뒤 고친 원장은 옛 커밋 내용이 넘어간다 — 지금 파일과 그 커밋의 blob 이 같을 때만 진행한다
NOW_BLOB="$(git -C "$REPO" hash-object -- "$REPO/$REL")"
SHA_BLOB="$(git -C "$REPO" rev-parse "$SHA:$REL" 2>&1)" || { echo "ERROR magazine_from_news: git rev-parse 실패 — $SHA_BLOB" >&2; exit 4; }
[ "$NOW_BLOB" = "$SHA_BLOB" ] || { echo "ERROR magazine_from_news: 매거진 원본 미커밋 수정 — $REL 의 지금 내용이 커밋 $SHA 와 다르다(커밋 뒤 다시)" >&2; exit 5; }
# r851 A2 — 원장 신선도: max(«마지막 갱신», 기계 채움 성공) 이 FT_LEDGER_FRESH_MIN(60)분 넘게 낡으면 발행 0(exit 6 과 같은 급 · planner [긴급] 1통은 도구가 같은 사건 1번)
#   FT_LEDGER_FRESH_GATE=0 = 끔(되돌림) · FT_LEDGER_FRESH = 도구 경로(시험 대역)
if [ "${FT_LEDGER_FRESH_GATE:-1}" != 0 ]; then
  FRESH="${FT_LEDGER_FRESH:-$(cat "$ROOT/.fable-team/LIVE_BIN" 2>/dev/null || true)/ft-ledger-fill}"
  OUT="$(bash "$FRESH" fresh --repo "$REPO" --path "$REL" --ref "$SHA" 2>&1)" || { echo "ERROR magazine_from_news: 원장 신선도 — ${OUT:-$FRESH 실행 실패} (낡은 매거진 발행 0)" >&2; exit 6; }
fi
# 오빠 원장 제목에는 날짜가 없다 — 판 날짜는 발행 시각(FT_NEWS_NOW 또는 지금)의 날짜
NOW="${FT_NEWS_NOW:-$(date '+%Y-%m-%d %H:%M')}"
exec python3 "${FT_MAGAZINE_DOC:-$HERE/magazine_doc.py}" --src-repo "$REPO" --src-sha "$SHA" --src-path "$REL" --date "${NOW:0:10}" "$@"
