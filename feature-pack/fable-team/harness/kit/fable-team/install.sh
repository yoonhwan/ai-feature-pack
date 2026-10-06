#!/usr/bin/env bash
# install.sh — fable-team 키트(bin·templates)를 한 홈에 설치하고 팀 1개 부팅 보고를 출력한다.
# 사용: bash install.sh [--apply] [--home DIR] [--machine NAME] [--team NAME]
#   기본은 --dry-run: 파일을 쓰지 않고 «설치될 목록 + sha» 만 보고한다. --apply 가 있어야 복사한다.
#   --home 기본 $HOME · --machine 기본 hostname -s · --team 기본 harness. env 로도 받는다(KIT_HOME·KIT_MACHINE·KIT_TEAM).
# 이 스크립트는 원격 접속·launchd·글로벌 설정을 건드리지 않는다(= 사람 승인 뒤 별도 단계).
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${KIT_HOME:-$HOME}"
MACHINE="${KIT_MACHINE:-$(hostname -s)}"
TEAM="${KIT_TEAM:-harness}"
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --home)    HOME_DIR="${2:?--home 값 필요}"; shift ;;
    --machine) MACHINE="${2:?--machine 값 필요}"; shift ;;
    --team)    TEAM="${2:?--team 값 필요}"; shift ;;
    *) echo "ERROR: 알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$KIT/bin" ] && [ -d "$KIT/templates" ] || { echo "ERROR: 키트 디렉터리 없음: $KIT/{bin,templates}" >&2; exit 1; }
[ -n "$HOME_DIR" ] || { echo "ERROR: 홈 경로가 비었다" >&2; exit 1; }

DEST="$HOME_DIR/.fable-team/$TEAM"
sha12() { shasum -a 256 "$1" | cut -c1-12; }

# 설치 대상 = 키트 안의 모든 일반 파일(bin/·templates/). 상대경로 정렬 → 목록·종합 sha 가 결정적이다.
FILES="$(cd "$KIT" && find bin templates -type f | LC_ALL=C sort)"
COUNT="$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')"

LISTING=""
while IFS= read -r rel; do
  LISTING+="$(sha12 "$KIT/$rel")  $rel"$'\n'
done <<< "$FILES"
KIT_SHA="$(printf '%s' "$LISTING" | shasum -a 256 | cut -c1-12)"

if [ "$APPLY" = 1 ]; then
  while IFS= read -r rel; do
    mkdir -p "$DEST/$(dirname "$rel")"
    cp -p "$KIT/$rel" "$DEST/$rel"
    cmp -s "$KIT/$rel" "$DEST/$rel" || { echo "ERROR: 복사 불일치: $rel" >&2; exit 1; }
  done <<< "$FILES"
  MODE="apply"
else
  MODE="dry-run"
fi

echo "== fable-team 키트 부팅 보고 =="
echo "machine=$MACHINE team=$TEAM mode=$MODE dest=$DEST"
echo "files=$COUNT kit_sha=$KIT_SHA"
printf '%s' "$LISTING"
[ "$MODE" = "dry-run" ] && echo "(dry-run: 쓰지 않았다 — 설치하려면 --apply)"
echo "== 끝 =="
