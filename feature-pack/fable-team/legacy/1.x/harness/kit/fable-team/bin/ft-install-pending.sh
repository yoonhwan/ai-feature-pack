#!/usr/bin/env bash
# ft-install-pending.sh [--root <루트>] — 설치 대기 병합 수를 뉴스 1줄로 (R245 ⑦). 0 건이면 줄 0.
#   대기 파일 = <루트>/.fable-team/state/install-pending/<착지 sha>.txt (ft-merge-land.sh 가 INSTALL PENDING·ERROR 일 때 쓰고, 카드 완성 이동 통과 때 지운다). 읽기만.
set -uo pipefail
ROOT="${FT_ROOT:-}"
[ "${1:-}" = --root ] && [ -n "${2:-}" ] && ROOT="$2"
[ -n "$ROOT" ] || { HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; . "$HERE/ft-harness-root.sh"; ROOT="$(ft_data_root "$HERE")"; } || exit 1   # r385 r3: 설치본(git 밖)의 ../.. 는 데이터 루트가 아니다
D="$ROOT/.fable-team/state/install-pending"
shas=""; n=0
for f in "$D"/*.txt; do
  [ -f "$f" ] || continue
  n=$((n + 1)); b="$(basename "$f" .txt)"; shas="${shas:+$shas }${b:0:10}"
done
[ "$n" -eq 0 ] || echo "설치 대기 $n 병합 — $shas (ft-live-install-check.sh --range 로 항목 확인 · master 설치)"
