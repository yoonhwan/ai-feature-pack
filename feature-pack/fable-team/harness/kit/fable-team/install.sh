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

# 홈 훅 확인(읽기 전용) — 키트 훅이 «실제로 도는» 홈 훅과 같은가 · settings.json 에 등록됐나. 복사·등록은 하지 않는다.
SETTINGS="$HOME_DIR/.claude/settings.json"
H_SAME=0; H_DIFF=0; H_ABSENT=0; H_REG=0
for tpl in "$KIT"/templates/hooks/*.sh "$KIT"/templates/hooks/*.py; do
  [ -f "$tpl" ] || continue
  name="$(basename "$tpl")"
  if [ ! -f "$HOME_DIR/.claude/hooks/$name" ]; then h_state="absent"; H_ABSENT=$((H_ABSENT+1))
  elif cmp -s "$tpl" "$HOME_DIR/.claude/hooks/$name"; then h_state="same"; H_SAME=$((H_SAME+1))
  else h_state="diff"; H_DIFF=$((H_DIFF+1)); fi
  if [[ "$name" == *.py ]]; then s_state="n/a"  # 판정기 등 부속 파일 — settings 등록 대상 아님
  elif [ -f "$SETTINGS" ] && grep -qF "hooks/$name" "$SETTINGS"; then s_state="registered"; H_REG=$((H_REG+1))
  else s_state="absent"; fi
  echo "hook $name home=$h_state settings=$s_state"
done
echo "hooks same=$H_SAME diff=$H_DIFF absent=$H_ABSENT registered=$H_REG"

# R115 hil 싱크 허용 목록 — block-destructive 판정기가 «ft-hil.sh 등록» 구간을 글 싱크로 인정할 때 쓰는 realpath 줄(줄마다 1개).
# 이 키트가 설치한 ft-hil.sh + KIT_HIL_EXTRA(콜론 구분 · 리포 런타임 사본 등)만. 실재하지 않는 경로는 적지 않는다. 훅 폴더가 이미 있을 때만 쓴다.
HIL_LIST="$HOME_DIR/.claude/hooks/hil-paths.txt"
HIL_LINES=""
for p in "$DEST/bin/ft-hil.sh" $(printf '%s' "${KIT_HIL_EXTRA:-}" | tr ':' ' '); do
  [ -f "$p" ] && HIL_LINES+="$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"$'\n'
done
if [ "$APPLY" = 1 ] && [ -d "$HOME_DIR/.claude/hooks" ] && [ -n "$HIL_LINES" ]; then
  printf '%s' "$HIL_LINES" > "$HIL_LIST"
  echo "hil-paths $HIL_LIST lines=$(printf '%s' "$HIL_LINES" | wc -l | tr -d ' ')"
else
  echo "hil-paths (쓰지 않음: apply=$APPLY 훅폴더=$([ -d "$HOME_DIR/.claude/hooks" ] && echo 있음 || echo 없음) 대상=$(printf '%s' "$HIL_LINES" | wc -l | tr -d ' ')줄)"
fi

[ "$MODE" = "dry-run" ] && echo "(dry-run: 쓰지 않았다 — 설치하려면 --apply)"
echo "== 끝 =="
