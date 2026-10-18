#!/usr/bin/env bash
# install.sh — fable-team harness 설치 입구 (설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-3 입구 표)
# 사용: bash harness/install.sh [--dry-run] [--home DIR] [--machine NAME] [--project DIR]
#   버전 = ../manifest.json "version" 하나(손으로 적지 않는다). 설치 폴더 = <home>/.claude/fable-team/live/<version>/
#   지금은 --dry-run 만 — 설치 계획(폴더 + 프로젝트 LIVE_BIN·LIVE_ROOT 2줄)을 출력하고 쓰기 0.
#   실제 설치(--apply: kit/fable-team/install.sh 위임 + LIVE_BIN·LIVE_ROOT 쓰기 + shim)는 r385(B1).
set -euo pipefail

HARNESS="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HARNESS/../manifest.json"
HOME_DIR="$HOME"
MACHINE="$(hostname -s)"
PROJECT="$(pwd -P)"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) ;;
    --apply)   echo "ERROR: --apply 는 r385(B1) 범위 — 지금은 --dry-run 만" >&2; exit 2 ;;
    --home)    HOME_DIR="${2:?--home 값 필요}"; shift ;;
    --machine) MACHINE="${2:?--machine 값 필요}"; shift ;;
    --project) PROJECT="${2:?--project 값 필요}"; shift ;;
    *) echo "ERROR: 알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -f "$MANIFEST" ] || { echo "ERROR: manifest 없음: $MANIFEST" >&2; exit 1; }
[ -f "$HARNESS/kit/fable-team/install.sh" ] || { echo "ERROR: 키트 입구 없음: $HARNESS/kit/fable-team/install.sh" >&2; exit 1; }
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
[ -n "$VERSION" ] || { echo "ERROR: manifest version 이 비었다" >&2; exit 1; }

LIVE="$HOME_DIR/.claude/fable-team/live/$VERSION"
echo "== fable-team harness 설치 계획 (dry-run · 쓰기 0) =="
echo "version=$VERSION machine=$MACHINE live=$LIVE/"
echo "LIVE_BIN  $PROJECT/.fable-team/LIVE_BIN  <- $LIVE/bin"
echo "LIVE_ROOT $PROJECT/.fable-team/LIVE_ROOT <- $PROJECT"
