#!/usr/bin/env bash
# install.sh — fable-team harness 설치 입구 (설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-3 입구 표 · r385 B1)
# 사용: bash harness/install.sh [--dry-run|--apply] --project <프로젝트 루트> [--home DIR] [--machine NAME] [--live-root DIR]
#   버전 = ../manifest.json "version" 하나(손으로 적지 않는다). 설치 폴더 = <home>/.claude/fable-team/live/<version>/{bin,templates,HARNESS_ROOT}
#   --project 필수(dry-run·apply 둘 다 · cwd 추론 0 · 없으면 rc2 쓰기 0). 프로젝트에 .fable-team/bin 이 있어야 한다.
#   --apply: 키트 kit/fable-team/{bin,templates} 일반 파일을 버전 폴더에 cp -p → cmp · <버전>/HARNESS_ROOT = 이 하네스 루트 1줄
#            → 설치본 ft-root-bin-shim.sh 로 프로젝트 LIVE_BIN(=<버전>/bin) · LIVE_ROOT(있으면 보존 · 없으면 --live-root 또는 프로젝트) · 루트 연결 파일.
#   멱등: 같은 명령 2회째 = 복사 0(cmp 같음) · 연결 파일 MOVED 0. 남는 설치본 파일(키트에 없는 이름)은 지우지 않고 EXTRA 로 센다.
#   되돌림 = 프로젝트 .fable-team/LIVE_BIN 1줄을 이전 값으로(버전 폴더는 남는다).
#   종료: 0 · 1 ERROR · 2 usage.
set -euo pipefail

HARNESS="$(cd "$(dirname "$0")" && pwd -P)"
MANIFEST="$HARNESS/../manifest.json"
KIT="$HARNESS/kit/fable-team"
HOME_DIR="$HOME"
MACHINE="$(hostname -s)"
PROJECT=""; LROOT=""; APPLY=0

usage() { echo "usage: $0 [--dry-run|--apply] --project <프로젝트 루트> [--home DIR] [--machine NAME] [--live-root DIR]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   APPLY=0 ;;
    --apply)     APPLY=1 ;;
    --home)      HOME_DIR="${2:?--home 값 필요}"; shift ;;
    --machine)   MACHINE="${2:?--machine 값 필요}"; shift ;;
    --project)   PROJECT="${2:?--project 값 필요}"; shift ;;
    --live-root) LROOT="${2:?--live-root 값 필요}"; shift ;;
    *) echo "ERROR: 알 수 없는 인자: $1" >&2; usage ;;
  esac
  shift
done

[ -n "$PROJECT" ] || { echo "REJECT --project <프로젝트 루트> 필수 — cwd 로 추론하지 않는다 (쓰기 0)" >&2; exit 2; }
[ -d "$PROJECT/.fable-team/bin" ] || { echo "REJECT 프로젝트에 .fable-team/bin 없음: $PROJECT (쓰기 0)" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd -P)"
[ -f "$MANIFEST" ] || { echo "ERROR: manifest 없음: $MANIFEST" >&2; exit 1; }
[ -d "$KIT/bin" ] && [ -d "$KIT/templates" ] || { echo "ERROR: 키트 없음: $KIT/{bin,templates}" >&2; exit 1; }
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
[ -n "$VERSION" ] || { echo "ERROR: manifest version 이 비었다" >&2; exit 1; }

LIVE="$HOME_DIR/.claude/fable-team/live/$VERSION"
LR_FILE="$PROJECT/.fable-team/LIVE_ROOT"
if [ -z "$LROOT" ]; then
  if [ -f "$LR_FILE" ]; then LROOT="$(sed -n '1p' "$LR_FILE" | tr -d '\r')"; else LROOT="$PROJECT"; fi
fi
# 설치 대상 = 키트 bin·templates 의 일반 파일(파이썬 캐시 제외) — 상대경로 정렬
FILES="$(cd "$KIT" && find bin templates -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | LC_ALL=C sort)"
COUNT="$(printf '%s\n' "$FILES" | grep -c .)"

echo "== fable-team harness 설치 ($([ "$APPLY" = 1 ] && echo apply || echo 'dry-run · 쓰기 0')) =="
echo "version=$VERSION machine=$MACHINE live=$LIVE/ files=$COUNT"
echo "HARNESS_ROOT $LIVE/HARNESS_ROOT <- $HARNESS"
echo "LIVE_BIN  $PROJECT/.fable-team/LIVE_BIN  <- $LIVE/bin"
echo "LIVE_ROOT $LR_FILE <- $LROOT$([ -f "$LR_FILE" ] && echo ' (있으면 보존)')"
if [ "$APPLY" != 1 ]; then echo "(dry-run: 쓰지 않았다 — 설치하려면 --apply)"; exit 0; fi

[ -d "$LROOT" ] || { echo "ERROR: LIVE_ROOT 폴더 없음: $LROOT" >&2; exit 1; }
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
PREV=""; [ -f "$PROJECT/.fable-team/LIVE_BIN" ] && PREV="$(sed -n '1p' "$PROJECT/.fable-team/LIVE_BIN")"
copied=0; same=0
while IFS= read -r rel; do
  if [ -f "$LIVE/$rel" ] && cmp -s "$KIT/$rel" "$LIVE/$rel" && [ "$(perm "$KIT/$rel")" = "$(perm "$LIVE/$rel")" ]; then same=$((same + 1)); continue; fi
  mkdir -p "$LIVE/$(dirname "$rel")"
  cp -p "$KIT/$rel" "$LIVE/$rel"
  cmp -s "$KIT/$rel" "$LIVE/$rel" || { echo "ERROR: 복사 불일치: $rel" >&2; exit 1; }
  copied=$((copied + 1))
done <<< "$FILES"
extra="$(cd "$LIVE" && find bin templates -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | LC_ALL=C sort | comm -23 - <(printf '%s\n' "$FILES") | grep -c . || true)"
cur=""; [ -f "$LIVE/HARNESS_ROOT" ] && cur="$(sed -n '1p' "$LIVE/HARNESS_ROOT")"
[ "$cur" = "$HARNESS" ] || printf '%s\n' "$HARNESS" > "$LIVE/HARNESS_ROOT"
echo "COPY copied=$copied same=$same extra=$extra"

# 프로젝트 LIVE_BIN·LIVE_ROOT·연결 파일 — 설치본 도구로(키트 트리 = 이 하네스 체크아웃의 HEAD)
REPO="$(git -C "$HARNESS" rev-parse --show-toplevel)"; REPO="$(cd "$REPO" && pwd -P)"
REF="$(git -C "$REPO" rev-parse HEAD)"
bash "$LIVE/bin/ft-root-bin-shim.sh" --root "$PROJECT" --live "$LIVE/bin" --live-root "$LROOT" \
  --repo "$REPO" --path "${HARNESS#"$REPO"/}/kit/fable-team/bin" --ref "$REF"
if [ -n "$PREV" ] && [ "$PREV" != "$LIVE/bin" ]; then echo "되돌림 1줄: printf '%s\\n' '$PREV' > '$PROJECT/.fable-team/LIVE_BIN'"
else echo "되돌림: 이전 LIVE_BIN 값 ${PREV:-없음}(이번 값과 같거나 없음 — 되돌릴 것 0)"; fi
echo "== 끝 =="
