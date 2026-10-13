#!/usr/bin/env bash
# magazine_from_news.sh [magazine_doc.py 인자…] — 08:00 매거진 원본 연결 (R118b · 판정 1430)
# 그날 08:00 직전 24시간 안의 «마지막 POLISHED» (design/planner/news/POLISHED-YYYYMMDD-HHMM.md) 를 원본으로 magazine_doc.py(r117)를 부른다.
# 없거나(그날 다듬은 판 0) 커밋 전이면 «매거진 원본 없음» ERROR + rc≠0 · 커밋 뒤 고쳤으면 «미커밋 수정» ERROR + rc 5 — 빈 매거진을 만들지 않는다(#0 RULE · 폴백 0).
# env: FT_ROOT(필수 · POLISHED 가 든 git 루트) · FT_NEWS_DIR(기본 <루트>/design/planner/news) · FT_NEWS_NOW("YYYY-MM-DD HH:MM" · 시험) · FT_MAGAZINE_DOC(시험용 대역)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FT_ROOT:?magazine_from_news: FT_ROOT 필요}"
NEWS="${FT_NEWS_DIR:-$ROOT/design/planner/news}"
NOW="${FT_NEWS_NOW:-$(date '+%Y-%m-%d %H:%M')}"
END="$(python3 -c 'import sys;print(sys.argv[1][:10].replace("-","")+"-0800")' "$NOW")"
START="$(python3 -c 'import sys,datetime as d;print((d.date.fromisoformat(sys.argv[1][:10])-d.timedelta(days=1)).strftime("%Y%m%d")+"-0800")' "$NOW")"
last=""
for f in "$NEWS"/POLISHED-*.md; do
  [ -f "$f" ] || continue
  stamp="${f##*/POLISHED-}"; stamp="${stamp%.md}"
  { [[ "$stamp" > "$START" ]] && [[ ! "$stamp" > "$END" ]]; } && last="$f"   # 파일 이름이 시각 순 — 마지막 통과분
done
[ -n "$last" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — $START ~ $END 사이 POLISHED 0 (빈 매거진 발행 0)" >&2; exit 2; }
REL="${last#"$ROOT"/}"
SHA="$(git -C "$ROOT" log -1 --format=%H -- "$REL" 2>&1)" || { echo "ERROR magazine_from_news: git log 실패 — $SHA" >&2; exit 4; }
[ -n "$SHA" ] || { echo "ERROR magazine_from_news: 매거진 원본 없음 — $REL 이 커밋되지 않았다(magazine_doc 은 git 원문을 읽는다)" >&2; exit 3; }
# 커밋 뒤 고친 POLISHED 는 옛 커밋 내용이 넘어간다 — 지금 파일과 그 커밋의 blob 이 같을 때만 진행한다
NOW_BLOB="$(git -C "$ROOT" hash-object -- "$last")"
SHA_BLOB="$(git -C "$ROOT" rev-parse "$SHA:$REL" 2>&1)" || { echo "ERROR magazine_from_news: git rev-parse 실패 — $SHA_BLOB" >&2; exit 4; }
[ "$NOW_BLOB" = "$SHA_BLOB" ] || { echo "ERROR magazine_from_news: 매거진 원본 미커밋 수정 — $REL 의 지금 내용이 커밋 $SHA 와 다르다(커밋 뒤 다시)" >&2; exit 5; }
exec python3 "${FT_MAGAZINE_DOC:-$HERE/magazine_doc.py}" --src-repo "$ROOT" --src-sha "$SHA" --src-path "$REL" "$@"
