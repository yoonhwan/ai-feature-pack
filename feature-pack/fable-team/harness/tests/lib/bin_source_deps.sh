#!/usr/bin/env bash
# bin_source_deps.sh — 시험 임시 bin 의 «같은 폴더 source 대상» 도우미 (r686 · r672 새 lib 2개가 이름 골라 복사한 사본에서 빠져 rc4/REJECT).
# source 해서 쓴다. 함수 2개:
#   missing_source_deps <dir>          — <dir>/*.sh 가 `. "$HERE/…"`·`. "$(dirname …)/…"`·`source …` 로 부르는 같은 폴더 ft 파일 중 <dir> 에 없는 이름을 1줄씩
#   copy_source_deps <src_bin> <dir>   — 없는 것만 <src_bin> 에서 채운다(반복 · 이미 있는 파일 = 시험의 가짜는 덮지 않는다) · 원본에도 없으면 stderr 1줄 + rc1
# `bash "$HERE/ft-x.sh"` 로 «부르는» 도구는 대상이 아니다 — 시험이 가짜로 둘지 진짜로 둘지 정한다.
_bsd_names() {
  grep -hE '(^|[^A-Za-z0-9_])(\.|source) +"\$' "$1"/*.sh 2>/dev/null \
    | grep -oE '(\$HERE|\$BINDIR|\$SCRIPT_DIR|\))/ft[-_][A-Za-z0-9_.-]+\.sh"' | sed -E 's#.*/##; s/"$//' | sort -u
}
missing_source_deps() {
  local n; _bsd_names "$1" | while read -r n; do [ -f "$1/$n" ] || echo "$n"; done
}
copy_source_deps() {
  local src="$1" dst="$2" n miss
  while miss="$(missing_source_deps "$dst")"; [ -n "$miss" ]; do
    for n in $miss; do
      [ -f "$src/$n" ] || { echo "copy_source_deps: 원본에도 없음 $src/$n" >&2; return 1; }
      cp -p "$src/$n" "$dst/$n" || return 1
    done
  done
}
