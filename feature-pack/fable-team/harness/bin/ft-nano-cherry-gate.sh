#!/usr/bin/env bash
# ft-nano-cherry-gate.sh <feat 브랜치> <nano 브랜치> [--repo <dir>]
#   ft-nano-close.sh 의 «산출물이 들어왔는가» 게이트 (G4 · 골좌표 M7 — 나노 브랜치에만 남은 커밋은 feat push 가 따라오지 않는다).
#   `git cherry <feat> <nano>` 의 «+»(feat 에 같은 patch 가 없는 커밋): design/ 밖 경로를 건드린 것이 있으면 목록 출력 + exit 1 ·
#   design/ 만 건드린 «+» 는 WARN 목록 + exit 0(브랜치 보존으로 복구 가능 — G4 실측 docs-only 134 를 전부 막으면 닫기 정지) · «+» 0 이면 `OK` + exit 0. 우회 플래그·면제 목록 없음.
#   exit 0 = 통과 · 1 = REJECT(+ 있음 / ref 없음 / git 실패 — 전부 사유 stdout) · 2 = usage. ★침묵 통과 0★ — 어느 경로든 한 줄 이상 출력한다.
set -uo pipefail
FEAT="${1:-}"; NANO="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <feat-branch> <nano-branch> [--repo <dir>]" >&2; exit 2; }
REPO="."; [ "${1:-}" = "--repo" ] && REPO="${2:-.}"
for r in "$FEAT" "$NANO"; do
  git -C "$REPO" rev-parse --verify -q "refs/heads/$r" >/dev/null || { echo "REJECT cherry 게이트 — 브랜치 없음: $r (refs/heads/)"; exit 1; }
done
out="$(git -C "$REPO" cherry "$FEAT" "$NANO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "REJECT cherry 게이트 — git cherry 실패(rc=$rc): ${out:0:120}"; exit 1; }
plus="$(printf '%s\n' "$out" | grep '^+' || true)"
# «+» 커밋을 둘로 가른다 — design/ 밖 경로(코드·시험·스크립트)를 건드린 것 = 차단 · design/ 만 건드린 것 = WARN 통과(브랜치가 남아 복구 가능 · arch#137)
#   ★경로 목록은 변수로 «완독» 한 뒤 분류한다(DA 575 H2: `diff-tree | grep -qv` 는 grep 조기 종료 → SIGPIPE → 큰 혼합 커밋이 «design/ 만» 으로 판정) · diff-tree·log 각 rc 를 따로 본다(H1: 실패가 WARN 통과)★
block=""; warn=""
while read -r _ sha; do
  [ -n "$sha" ] || continue
  line="$(git -C "$REPO" log -1 --format='  + %h %s' "$sha")"; lrc=$?
  [ "$lrc" -eq 0 ] && [ -n "$line" ] || { echo "REJECT cherry 게이트 — git log 실패(rc=$lrc) 커밋 ${sha:0:9}"; exit 1; }
  line="${line:0:120}"
  paths="$(git -C "$REPO" diff-tree --no-commit-id --name-only -r -m --root "$sha")"; prc=$?
  [ "$prc" -eq 0 ] || { echo "REJECT cherry 게이트 — git diff-tree 실패(rc=$prc) 커밋 ${sha:0:9} — 경로를 못 읽어 분류 불가"; exit 1; }
  outside=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in design/*) ;; *) outside=1; break ;; esac
  done <<< "$paths"
  if [ "$outside" -eq 1 ]; then block="${block}${line}"$'\n'; else warn="${warn}${line}"$'\n'; fi
done <<< "$plus"
nb="$(printf '%s' "$block" | grep -c . || true)"; nw="$(printf '%s' "$warn" | grep -c . || true)"
if [ "$nb" -gt 0 ]; then
  echo "REJECT cherry 게이트 — $NANO 에 $FEAT 로 안 들어온 코드·시험·스크립트 커밋 ${nb}개 (git cherry '+' · design/ 밖 경로):"
  printf '%s' "$block" | head -20
  [ "$nb" -le 20 ] || echo "  … 외 $((nb - 20))개"
  [ "$nw" -eq 0 ] || { echo "  (별도 WARN: design/ 만 건드린 미랜딩 문서 커밋 ${nw}개)"; printf '%s' "$warn" | head -5; }
  echo "  → cherry-pick -x 로 $FEAT 에 반영하거나 폐기 사유를 값으로 적은 뒤 닫는다"
  exit 1
fi
if [ "$nw" -gt 0 ]; then
  echo "WARN cherry 게이트 — $NANO 의 design/ 문서 커밋 ${nw}개가 $FEAT 에 없음(코드 0 · 브랜치 보존으로 복구 가능) — 통과:"
  printf '%s' "$warn" | head -20
  [ "$nw" -le 20 ] || echo "  … 외 $((nw - 20))개"
  exit 0
fi
echo "OK cherry 게이트 — $NANO 의 모든 커밋이 $FEAT 에 patch 단위로 존재(+ 0)"
exit 0
