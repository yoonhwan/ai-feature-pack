#!/usr/bin/env bash
# install.sh — fable-team harness 설치 입구 (설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-3 입구 표 · r385 B1)
# 사용: bash harness/install.sh [--dry-run|--apply] --project <프로젝트 루트> [--home DIR] [--machine NAME] [--live-root DIR]
#   버전 = ../manifest.json "version" 하나(손으로 적지 않는다). 설치 폴더 = <home>/.claude/fable-team/live/<version>/{bin,templates,HARNESS_ROOT}
#   --project 필수(dry-run·apply 둘 다 · cwd 추론 0 · 없으면 rc2 쓰기 0). 프로젝트에 .fable-team/bin 이 있어야 한다.
#   --apply: 키트 kit/fable-team/{bin,templates} 일반 파일을 버전 폴더에 cp -p → cmp · <버전>/HARNESS_ROOT = 이 하네스 루트 1줄
#            → 설치본 ft-root-bin-shim.sh 로 프로젝트 LIVE_BIN(=<버전>/bin) · LIVE_ROOT(있으면 보존 · 없으면 --live-root 또는 프로젝트) · 루트 연결 파일.
#   멱등: 같은 명령 2회째 = 복사 0(cmp 같음) · 연결 파일 MOVED 0. 남는 설치본 파일(키트에 없는 이름)은 지우지 않고 EXTRA 로 센다.
#   되돌림 = 프로젝트 .fable-team/LIVE_BIN 1줄을 이전 값으로(버전 폴더는 남는다).
#   r426: 설치기 관리 launchd plist(ft_plist_env.py list · 지금 = 쪽지→슬랙 미러)는 «설치된 것만» 템플릿 렌더본으로 갱신 — 다를 때만 .bak-r426 + 재적재.
#         --dry-run 은 PENDING plist-env 줄만 · launchctl 은 FT_LAUNCHCTL(시험 주입).
#   r457: plist 갱신은 --project 가 git 공용 루트일 때만 — 워크트리면 SKIP plist-env 1줄(shim 설치는 그대로).
#   r459: 팩 comm 도구(harness/comm 의 일반 파일 · 우편함·큐 데이터 제외)를 <공용 루트>/.fable-team/comm 에 cp -p(덮기 전 .bak-<버전> · 루트 전용 파일 유지 · 삭제 0)
#         dry-run = COMM 줄 + `COMM copied=N same=M` · 워크트리 --project 는 SKIP comm · apply 끝 = 기동 뒤 스크립트가 바뀐 launchd 데몬 RESTART 줄(실행 0 · master 집행).
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
# r457: launchd plist 는 git 공용 루트 설치에서만 — 워크트리 --project(r413 shim 설치)는 plist 를 건드리지 않는다
COMMON="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"; COMMON="${COMMON%/.git}"
[ -z "$COMMON" ] || [ ! -d "$COMMON" ] || COMMON="$(cd "$COMMON" && pwd -P)"
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
# 홈 훅 = 키트 kit/hooks 의 이 목록만 <home>/.claude/hooks/ 로 cp -p → cmp (settings.json 훅 등록은 별도 = master)
HOME_HOOKS="harness-freeze-gate.sh old-team-path-new-file-gate.sh op-vault-develop-gate.sh"

echo "== fable-team harness 설치 ($([ "$APPLY" = 1 ] && echo apply || echo 'dry-run · 쓰기 0')) =="
echo "version=$VERSION machine=$MACHINE live=$LIVE/ files=$COUNT"
echo "HARNESS_ROOT $LIVE/HARNESS_ROOT <- $HARNESS"
echo "LIVE_BIN  $PROJECT/.fable-team/LIVE_BIN  <- $LIVE/bin"
echo "LIVE_ROOT $LR_FILE <- $LROOT$([ -f "$LR_FILE" ] && echo ' (있으면 보존)')"
for h in $HOME_HOOKS; do echo "HOOK $HOME_DIR/.claude/hooks/$h <- $HARNESS/kit/hooks/$h"; done
# r449: 프로젝트 git 훅 = 키트 kit/fable-team/githooks/* → <프로젝트>/.fable-team/githooks/ (core.hooksPath 가 가리키는 곳 · LIVE_BIN 연결 «뒤» 에 복사 — 새 pre-commit 이 새 bin 의 판정식을 찾게)
GH_DEST="$PROJECT/.fable-team/githooks"
for g in "$KIT"/githooks/*; do [ -f "$g" ] && echo "GITHOOK $GH_DEST/$(basename "$g") <- $g"; done
HP="$(git -C "$PROJECT" config --get core.hooksPath 2>/dev/null || true)"
[ -z "$HP" ] || [ "$HP" = "$GH_DEST" ] || [ "$HP" = .fable-team/githooks ] || echo "WARN core.hooksPath=$HP != $GH_DEST — 훅이 실제로 도는 곳과 다르다(--project 를 공용 루트로)"
# r426: 설치기 관리 launchd plist(ft_plist_env.py list) — «설치된 것만» 템플릿 렌더본(FT_ROOT=프로젝트 · inbox=LIVE_BIN)과 대조.
#   다르면 apply = .bak-r426(첫 원본 보존) + 교체 + bootout·bootstrap·kickstart(변경 때만) · 같으면 쓰기 0 · 렌더 실패 = ERROR(조용한 통과 0)
LC="${FT_LAUNCHCTL:-launchctl}"
# r459: comm 도구 동기화 — 데이터 파일(우편함·순번·가드 상태·큐 설정·본문·relay·캐시)은 대상 밖 · 이름 목록 = 팩 comm 의 최상위 일반 파일
COMM_SRC="$HARNESS/comm"; COMM_DST="${COMMON:-$PROJECT}/.fable-team/comm"
comm_sync() {
  local f n dst copied=0 same=0
  if [ -n "$COMMON" ] && [ "$PROJECT" != "$COMMON" ]; then echo "SKIP comm (--project 가 git 공용 루트 아님: 루트=$COMMON — comm 은 루트 설치에서만)"; return 0; fi
  [ -d "$COMM_SRC" ] || { echo "ERROR: 팩 comm 없음: $COMM_SRC" >&2; exit 1; }
  for f in "$COMM_SRC"/*; do
    n="$(basename "$f")"; [ -f "$f" ] || continue
    case "$n" in mailbox*.jsonl|.mbox-seq|.mbox-guard.json|queues.conf|*.pyc) continue;; esac
    dst="$COMM_DST/$n"
    if [ -f "$dst" ] && cmp -s "$f" "$dst" && [ "$(perm "$f")" = "$(perm "$dst")" ]; then same=$((same + 1)); continue; fi
    copied=$((copied + 1))
    if [ "$APPLY" != 1 ]; then echo "COMM $dst <- $f$([ -f "$dst" ] && echo ' (다름 · apply 때 .bak-'"$VERSION"')')"; continue; fi
    mkdir -p "$COMM_DST"; [ ! -f "$dst" ] || [ -e "$dst.bak-$VERSION" ] || cp -p "$dst" "$dst.bak-$VERSION"
    cp -p "$f" "$dst"; cmp -s "$f" "$dst" || { echo "ERROR: comm 복사 불일치: $dst" >&2; exit 1; }
  done
  echo "COMM copied=$copied same=$same dest=$COMM_DST$([ "$APPLY" = 1 ] && echo " (덮은 파일의 되돌림 = <파일>.bak-$VERSION)")"
}
plist_sync() {
  local label tpl dst new
  if [ -n "$COMMON" ] && [ "$PROJECT" != "$COMMON" ]; then
    echo "SKIP plist-env $(python3 "$KIT/bin/ft_plist_env.py" list | cut -f1 | tr '\n' ' ')(--project 가 git 공용 루트 아님: 루트=$COMMON — plist 는 루트 설치에서만)"
    return 0
  fi
  while IFS=$'\t' read -r label tpl; do
    dst="$HOME_DIR/Library/LaunchAgents/$label.plist"
    if [ ! -f "$dst" ]; then echo "SKIP plist $label (설치 안 됨 — 처음 설치는 kit/${tpl%%/*}/install.sh)"; continue; fi
    if [ "$APPLY" != 1 ] && [ ! -f "$LIVE/bin/ft-inbox.sh" ]; then echo "PLIST $label (설치본 bin 없음 — apply 때 렌더·대조)"; continue; fi
    new="$(python3 "$KIT/bin/ft_plist_env.py" render "$label" "$HARNESS/kit/$tpl" "$dst" "$PROJECT" "$LIVE/bin" "$HOME_DIR")" \
      || { echo "ERROR: plist 렌더 실패 $label: $new" >&2; exit 1; }
    if printf '%s\n' "$new" | cmp -s - "$dst"; then echo "OK plist-env $label"; continue; fi
    echo "PENDING plist-env $label (설치본 ≠ 템플릿 렌더본)"
    [ "$APPLY" = 1 ] || continue
    [ -f "$dst.bak-r426" ] || cp -p "$dst" "$dst.bak-r426"
    printf '%s\n' "$new" > "$dst"
    "$LC" bootout "gui/$(id -u)/$label" 2>/dev/null || true
    "$LC" bootstrap "gui/$(id -u)" "$dst" || { echo "ERROR: launchctl bootstrap 실패 $label — 되돌림 = cp -p '$dst.bak-r426' '$dst'" >&2; exit 1; }
    "$LC" kickstart -k "gui/$(id -u)/$label" || { echo "ERROR: launchctl kickstart 실패 $label" >&2; exit 1; }
    echo "PLIST applied $label (되돌림 = $dst.bak-r426 · kickstart)"
  done < <(python3 "$KIT/bin/ft_plist_env.py" list)
}
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
if [ "$APPLY" != 1 ]; then plist_sync; comm_sync; echo "(dry-run: 쓰지 않았다 — 설치하려면 --apply)"; exit 0; fi

[ -d "$LROOT" ] || { echo "ERROR: LIVE_ROOT 폴더 없음: $LROOT" >&2; exit 1; }
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
hcopied=0; hsame=0
for h in $HOME_HOOKS; do
  src="$HARNESS/kit/hooks/$h"; dst="$HOME_DIR/.claude/hooks/$h"
  [ -f "$src" ] || { echo "ERROR: 키트 훅 없음: $src" >&2; exit 1; }
  if [ -f "$dst" ] && cmp -s "$src" "$dst" && [ "$(perm "$src")" = "$(perm "$dst")" ]; then hsame=$((hsame + 1)); continue; fi
  mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"
  cmp -s "$src" "$dst" || { echo "ERROR: 훅 복사 불일치: $h" >&2; exit 1; }
  hcopied=$((hcopied + 1))
done
echo "HOOKS copied=$hcopied same=$hsame (settings.json 등록은 별도)"
plist_sync

# 프로젝트 LIVE_BIN·LIVE_ROOT·연결 파일 — 설치본 도구로(키트 트리 = 이 하네스 체크아웃의 HEAD)
REPO="$(git -C "$HARNESS" rev-parse --show-toplevel)"; REPO="$(cd "$REPO" && pwd -P)"
REF="$(git -C "$REPO" rev-parse HEAD)"
bash "$LIVE/bin/ft-root-bin-shim.sh" --root "$PROJECT" --live "$LIVE/bin" --live-root "$LROOT" \
  --repo "$REPO" --path "${HARNESS#"$REPO"/}/kit/fable-team/bin" --ref "$REF"
gcopied=0; gsame=0
for src in "$KIT"/githooks/*; do
  [ -f "$src" ] || continue
  dst="$GH_DEST/$(basename "$src")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst" && [ "$(perm "$src")" = "$(perm "$dst")" ]; then gsame=$((gsame + 1)); continue; fi
  mkdir -p "$GH_DEST"; [ ! -f "$dst" ] || cp -p "$dst" "$dst.bak-$VERSION"
  cp -p "$src" "$dst"; cmp -s "$src" "$dst" || { echo "ERROR: git 훅 복사 불일치: $dst" >&2; exit 1; }
  gcopied=$((gcopied + 1))
done
echo "GITHOOKS copied=$gcopied same=$gsame dest=$GH_DEST (덮은 파일의 되돌림 = <파일>.bak-$VERSION)"
comm_sync
# r459: 먼저 기동한 데몬은 메모리의 옛 사본으로 돈다 — 기동 < 스크립트(shim·LIVE_BIN 지도·라이브 도구) mtime 인 라벨을 RESTART 줄로(판정식 = ft_live_install_check restart_due 하나)
python3 "$KIT/bin/ft_live_install_check.py" --restart-scan "$HOME_DIR/Library/LaunchAgents" || { echo "ERROR: RESTART 판정 실패" >&2; exit 1; }
if [ -n "$PREV" ] && [ "$PREV" != "$LIVE/bin" ]; then echo "되돌림 1줄: printf '%s\\n' '$PREV' > '$PROJECT/.fable-team/LIVE_BIN'"
else echo "되돌림: 이전 LIVE_BIN 값 ${PREV:-없음}(이번 값과 같거나 없음 — 되돌릴 것 0)"; fi
echo "== 끝 =="
