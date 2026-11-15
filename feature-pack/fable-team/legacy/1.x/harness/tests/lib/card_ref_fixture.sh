#!/usr/bin/env bash
# card_ref_fixture.sh — source 전용 · 범위 승인 code 카드 fixture (r1951 · DA 설계 #301035 시험 메모)
# 카드 = <리포>/design/harness/indices/진행/<이름>(팀 카드 꼴) · 카드 루트 표 = <리포>/.fable-team/state/directive-roots.tsv harness 행 = origin/ops/main-base
# 쓰는 법: CARD="$(fx_card_path <리포> card.md)" → 작업 파일 쓰기 → fx_card_pub <리포> "$CARD" (그 카드 1장만 든 커밋 = refs/remotes/origin/ops/main-base · HEAD 무변경 · fetch 0)
fx_card_path() { mkdir -p "$1/design/harness/indices/진행" && printf '%s/design/harness/indices/진행/%s\n' "$1" "$2"; }
fx_card_pub() {  # <리포> <카드 작업 파일> [부모 ref] → 표 harness 행 + exclude(가지 커밋에 안 들어감) + ref 갱신
  local r="$1" f="$2" ix t ex p; ix="$(mktemp "${TMPDIR:-/tmp}/fx-ix.XXXXXX")"
  mkdir -p "$r/.fable-team/state"; printf 'harness\t.\torigin/ops/main-base\tdesign/harness/indices\n' > "$r/.fable-team/state/directive-roots.tsv"
  ex="$(git -C "$r" rev-parse --git-path info/exclude)"; case "$ex" in /*) ;; *) ex="$r/$ex";; esac; mkdir -p "${ex%/*}"
  for p in /design/harness/indices/ /.fable-team/; do grep -qxF "$p" "$ex" 2>/dev/null || echo "$p" >> "$ex"; done
  if [ -n "${3:-}" ]; then GIT_INDEX_FILE="$ix" git -C "$r" read-tree "$3"; else rm -f "$ix"; GIT_INDEX_FILE="$ix" git -C "$r" read-tree --empty; fi
  GIT_INDEX_FILE="$ix" git -C "$r" update-index --add --cacheinfo "100644,$(git -C "$r" hash-object -w "$f"),${f#"$r"/}"
  t="$(GIT_INDEX_FILE="$ix" git -C "$r" write-tree)"; rm -f "$ix"
  git -C "$r" update-ref refs/remotes/origin/ops/main-base "$(git -C "$r" commit-tree "$t" ${3:+-p "$3"} -m card)"; }
