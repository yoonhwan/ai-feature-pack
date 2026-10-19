#!/usr/bin/env bash
# install.sh — fable-team harness 설치 입구 (설계 DESIGN-harness-repo-split-and-teams-move-20261018 §9-3 입구 표 · r385 B1)
# 사용: bash harness/install.sh [--dry-run|--apply] --project <프로젝트 루트> [--home DIR] [--machine NAME] [--live-root DIR]
#   버전 = ../manifest.json "version" 하나(손으로 적지 않는다). 설치 폴더 = <home>/.claude/fable-team/live/<version>/{bin,templates,HARNESS_ROOT}
#   --project 필수(dry-run·apply 둘 다 · cwd 추론 0 · 없으면 rc2 쓰기 0). 프로젝트에 .fable-team/bin 이 있어야 한다
#     — r494: 없고 --project 가 git 워크트리면 dry-run `PLAN shim-init` · apply = 설치본 shim --init(LIVE_ROOT 기본 = 공용 루트) · 공용 루트 bin 없음 = REJECT rc2.
#   --apply: 키트 kit/fable-team/{bin,templates} 일반 파일을 버전 폴더에 cp -p → cmp · <버전>/HARNESS_ROOT = 이 하네스 루트 1줄
#            → 설치본 ft-root-bin-shim.sh 로 프로젝트 LIVE_BIN(=<버전>/bin) · LIVE_ROOT(있으면 보존 · 없으면 --live-root 또는 프로젝트) · 루트 연결 파일.
#   멱등: 같은 명령 2회째 = 복사 0(cmp 같음) · 연결 파일 MOVED 0. 남는 설치본 파일(키트에 없는 이름)은 지우지 않고 EXTRA 로 센다.
#   되돌림 = 프로젝트 .fable-team/LIVE_BIN 1줄을 이전 값으로(버전 폴더는 남는다).
#   r426: 설치기 관리 launchd plist(ft_plist_env.py list · 지금 = 쪽지→슬랙 미러)는 «설치된 것만» 템플릿 렌더본으로 갱신 — 다를 때만 .bak-r426 + 재적재.
#         --dry-run 은 PENDING plist-env 줄만 · launchctl 은 FT_LAUNCHCTL(시험 주입).
#   r457: plist 갱신은 --project 가 git 공용 루트일 때만 — 워크트리면 SKIP plist-env 1줄(shim 설치는 그대로).
#   r459: 팩 comm 도구(harness/comm 의 일반 파일 · 우편함·큐 데이터 제외)를 <공용 루트>/.fable-team/comm 에 cp -p(덮기 전 .bak-<버전> · 루트 전용 파일 유지 · 삭제 0)
#         dry-run = COMM 줄 + `COMM copied=N same=M` · 워크트리 --project 는 SKIP comm · apply 끝 = 기동 뒤 스크립트가 바뀐 launchd 데몬 RESTART 줄(실행 0 · master 집행).
#   r464: plist 단계는 LIVE_BIN 전환 «뒤» · 교체 전 직전 사본 .bak-<version> · bootstrap 1초 간격 최대 3회(7초 안)
#         · 그래도 실패면 직전 사본 원복 + 다시 올림 → PLIST RESTORED + 마지막 줄 INSTALLED <version> · PLIST ERROR rc1.
#   r512: 공용 루트 설치는 shim 단계 뒤 등록 워크트리 중 bin 이 이미 연결 파일(shim)인 곳마다 같은 설치본 shim 을 다시 돌린다
#         (연결 파일은 «자기 워크트리 ../LIVE_BIN» 을 읽는다 — 공용 루트만 바꾸면 그 워크트리는 옛 판) · 옛 통째 사본 bin = SKIP(손대지 않음)
#         · 끝줄 `WT-SHIM refreshed=N skip=M fail=K` · K>0 = 끝 rc1 · dry-run = `PLAN wt-shim <wt> <옛> -> <새>` · 워크트리 --project = 순회 0.
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
[ -d "$PROJECT" ] || { echo "REJECT 프로젝트 폴더 없음: $PROJECT (쓰기 0)" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd -P)"
# r457: launchd plist 는 git 공용 루트 설치에서만 — 워크트리 --project(r413 shim 설치)는 plist 를 건드리지 않는다
COMMON="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"; COMMON="${COMMON%/.git}"
[ -z "$COMMON" ] || [ ! -d "$COMMON" ] || COMMON="$(cd "$COMMON" && pwd -P)"
# r494: 새 워크트리(bin 없음)는 설치본 shim --init 으로 bin 을 만든다 · 공용 루트(·git 밖) bin 없음 = REJECT 그대로
SHIM_INIT=0
if [ ! -d "$PROJECT/.fable-team/bin" ]; then
  [ -n "$COMMON" ] && [ "$PROJECT" != "$COMMON" ] || { echo "REJECT 프로젝트에 .fable-team/bin 없음: $PROJECT (쓰기 0)" >&2; exit 2; }
  SHIM_INIT=1
fi
[ -f "$MANIFEST" ] || { echo "ERROR: manifest 없음: $MANIFEST" >&2; exit 1; }
[ -d "$KIT/bin" ] && [ -d "$KIT/templates" ] || { echo "ERROR: 키트 없음: $KIT/{bin,templates}" >&2; exit 1; }
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
[ -n "$VERSION" ] || { echo "ERROR: manifest version 이 비었다" >&2; exit 1; }

LIVE="$HOME_DIR/.claude/fable-team/live/$VERSION"
LR_FILE="$PROJECT/.fable-team/LIVE_ROOT"
if [ -z "$LROOT" ]; then
  if [ -f "$LR_FILE" ]; then LROOT="$(sed -n '1p' "$LR_FILE" | tr -d '\r')"; elif [ "$SHIM_INIT" = 1 ]; then LROOT="$COMMON"; else LROOT="$PROJECT"; fi
fi
# 설치 대상 = 키트 bin·templates 의 일반 파일(파이썬 캐시 제외) — 상대경로 정렬
FILES="$(cd "$KIT" && find bin templates -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | LC_ALL=C sort)"
COUNT="$(printf '%s\n' "$FILES" | grep -c .)"
# 홈 훅 = 키트 kit/hooks 의 일반 파일 전부 → <home>/.claude/hooks/ 로 cp -p → cmp → chmod +x (settings.json 훅 등록은 별도 = master)
#   r491: 손 cp 는 실행 비트를 안 따라온다(664 훅 1개 = 전 좌석 매 Bash «Permission denied») — 목록 고정 0 · 실행 비트까지 설치기가 본다
HOME_HOOKS="$(cd "$HARNESS/kit/hooks" && find . -maxdepth 1 -type f ! -name '*.pyc' | sed 's|^\./||' | LC_ALL=C sort)"

echo "== fable-team harness 설치 ($([ "$APPLY" = 1 ] && echo apply || echo 'dry-run · 쓰기 0')) =="
echo "version=$VERSION machine=$MACHINE live=$LIVE/ files=$COUNT"
echo "HARNESS_ROOT $LIVE/HARNESS_ROOT <- $HARNESS"
[ "$SHIM_INIT" = 0 ] || echo "PLAN shim-init $PROJECT (새 워크트리 · bin 없음 → 설치본 ft-root-bin-shim.sh --init · 공용 루트 $COMMON)"
echo "LIVE_BIN  $PROJECT/.fable-team/LIVE_BIN  <- $LIVE/bin"
echo "LIVE_ROOT $LR_FILE <- $LROOT$([ -f "$LR_FILE" ] && echo ' (있으면 보존)')"
for h in $HOME_HOOKS; do echo "HOOK $HOME_DIR/.claude/hooks/$h <- $HARNESS/kit/hooks/$h (exec)"; done
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
PLIST_FAIL=0
# r464: bootout 은 비동기(launchd 가 프로세스 종료를 기다림) — 바로 bootstrap 하면 실패할 수 있다 → 1초 간격 최대 3회 · 7초 안(7초 룰)
#   BOOT_TRY = 실패한 횟수 · BOOT_WHY = 마지막 launchctl 출력 1줄
boot_retry() {
  local t0=$SECONDS out
  BOOT_TRY=0; BOOT_WHY=""
  while :; do
    if out="$("$LC" bootstrap "gui/$(id -u)" "$1" 2>&1)"; then return 0; fi
    BOOT_WHY="$(printf '%s\n' "$out" | grep . | tail -1 || true)"; BOOT_WHY="${BOOT_WHY:-출력 없음}"
    BOOT_TRY=$((BOOT_TRY + 1))
    [ "$BOOT_TRY" -lt 3 ] && [ $((SECONDS - t0)) -lt 6 ] || return 1
    sleep 1
  done
}
# r464: 새 렌더본 적용 실패 → 직전 사본을 되돌리고 다시 올린 «뒤» 에 실패 표식(절반 상태 0 · 되돌림이 글자뿐인 것 0)
plist_restore() {
  local label="$1" dst="$2" why="$3"
  "$LC" bootout "gui/$(id -u)/$label" 2>/dev/null || true
  cp -p "$dst.bak-$VERSION" "$dst"
  if boot_retry "$dst"; then echo "PLIST RESTORED $label — 새 렌더본 적용 실패($why) · 직전 plist($dst.bak-$VERSION) 로 되돌리고 다시 올림"
  else echo "ERROR: plist 원복본 bootstrap 도 실패 $label ($BOOT_WHY) — 미러 내려감 · 손 복구 = launchctl bootstrap gui/$(id -u) '$dst'" >&2; fi
  PLIST_FAIL=1
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
    cp -p "$dst" "$dst.bak-$VERSION"
    printf '%s\n' "$new" > "$dst"
    "$LC" bootout "gui/$(id -u)/$label" 2>/dev/null || true
    if ! boot_retry "$dst"; then plist_restore "$label" "$dst" "bootstrap ${BOOT_TRY}회 실패: $BOOT_WHY"; continue; fi
    "$LC" kickstart -k "gui/$(id -u)/$label" || { plist_restore "$label" "$dst" "kickstart 실패"; continue; }
    echo "PLIST applied $label (retry=$BOOT_TRY · 되돌림 = $dst.bak-$VERSION · kickstart)"
  done < <(python3 "$KIT/bin/ft_plist_env.py" list)
}
perm() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
# r459: 먼저 기동한 데몬은 메모리의 옛 사본으로 돈다 — 기동 < 스크립트(shim·LIVE_BIN 지도·라이브 도구) mtime 인 라벨을 RESTART 줄로(판정식 = ft_live_install_check restart_due 하나 · 읽기만 · dry-run 은 설치 전 시점 값)
restart_scan() { python3 "$KIT/bin/ft_live_install_check.py" --restart-scan "$HOME_DIR/Library/LaunchAgents" || { echo "ERROR: RESTART 판정 실패" >&2; exit 1; }; }
# r491: settings.json 에 등록된 훅 경로(…/hooks/<파일> · $HOME/… · ~/…) 전수 — 실재 + (명령 첫 낱말로 직접 실행되면) 실행 비트 · 읽기만(settings 쓰기 0)
#   출력 = 문제마다 `HOOK-EXEC <경로> <없음|실행 비트 없음>` + 끝 줄 `HOOKS registered=N ok=N bad=M` · settings 없음 = registered=0 · JSON 깨짐 = rc1
#   `bash <경로>`·`if [ -x <경로> ]…` 처럼 인터프리터·가드로 부르는 경로는 실재만 본다(644 여도 돈다 — 과차단 0)
audit_registered_hooks() {
  python3 -I - "$1" "$2" <<'PY'
import json, os, re, sys
settings, home = sys.argv[1], sys.argv[2]
if not os.path.isfile(settings):
    print("HOOKS registered=0 ok=0 bad=0 (settings 없음: %s)" % settings); sys.exit(0)
try:
    cfg = json.load(open(settings, encoding="utf-8"))
except (OSError, ValueError) as e:
    print("ERROR settings.json 못 읽음: %s (%s)" % (settings, e)); sys.exit(1)
need = {}  # 경로 → 실행 비트 필요 여부(직접 실행이 한 번이라도 있으면 True)
for groups in (cfg.get("hooks") or {}).values():
    for g in groups or []:
        for h in g.get("hooks") or []:
            words = re.findall(r"""[^\s'";&|()]+""", h.get("command") or "")
            for i, w in enumerate(words):
                if "hooks/" not in w or not re.match(r"(/|~/|\$HOME/|\$\{HOME\}/)", w):
                    continue
                p = re.sub(r"^(~|\$HOME|\$\{HOME\})/", home.rstrip("/") + "/", w)
                need[p] = need.get(p, False) or i == 0
bad = 0
for p in sorted(need):
    why = "없음" if not os.path.isfile(p) else ("실행 비트 없음" if need[p] and not os.access(p, os.X_OK) else "")
    if why:
        bad += 1; print("HOOK-EXEC %s %s" % (p, why))
print("HOOKS registered=%d ok=%d bad=%d" % (len(need), len(need) - bad, bad))
PY
}
HOOK_FAIL=0
hook_audit() {  # dry-run = PENDING (rc 불변) · apply = ERROR + HOOK_FAIL=1(끝 rc1)
  local out ln tag=PENDING
  [ "$APPLY" = 1 ] && tag=ERROR
  out="$(audit_registered_hooks "$HOME_DIR/.claude/settings.json" "$HOME_DIR")" || { printf '%s\n' "$out" >&2; exit 1; }
  while IFS= read -r ln; do
    case "$ln" in HOOK-EXEC\ *) echo "$tag $ln"; HOOK_FAIL=1;; *) echo "$ln";; esac
  done <<< "$out"
}
WT_FAIL=0
wt_is_shim() {  # $1 = bin 폴더 → 머리 2줄에 연결 파일 표식이 있는 일반 파일 1개 이상
  local f
  for f in "$1"/*; do [ -f "$f" ] || continue; case "$(head -2 "$f")" in *'# ft-root-bin-shim:'*) return 0;; esac; done
  return 1
}
wt_state() { (cd "$1/.fable-team" && cat LIVE_BIN LIVE_ROOT 2>/dev/null; ls -A bin; cksum bin/* 2>/dev/null) || true; }
wt_shim_refresh() {  # r512: 공용 루트 설치에서만 · 워크트리마다 실패해도 다음 계속 · 실패 수 > 0 = WT_FAIL(끝 rc1)
  local wt old out rc before n=0 skip=0 nfail=0 lrarg
  [ -n "$COMMON" ] && [ "$PROJECT" = "$COMMON" ] || return 0
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    if [ ! -d "$wt" ]; then echo "SKIP wt-shim $wt (폴더 없음)"; skip=$((skip + 1)); continue; fi
    [ "$(cd "$wt" && pwd -P)" != "$COMMON" ] || continue
    [ -f "$wt/.fable-team/LIVE_BIN" ] || continue
    wt_is_shim "$wt/.fable-team/bin" || { echo "SKIP wt-shim $wt (shim 아님)"; skip=$((skip + 1)); continue; }
    old="$(sed -n '1p' "$wt/.fable-team/LIVE_BIN")"
    if [ "$APPLY" != 1 ]; then echo "PLAN wt-shim $wt ${old:-없음} -> $LIVE/bin"; n=$((n + 1)); continue; fi
    before="$(wt_state "$wt")"
    lrarg=(); [ -f "$wt/.fable-team/LIVE_ROOT" ] || lrarg=(--live-root "$COMMON")   # 있으면 보존(인자 0) · 없을 때만 공용 루트(라이브 bin/../.. 유도 방지)
    if out="$(bash "$LIVE/bin/ft-root-bin-shim.sh" --root "$wt" --live "$LIVE/bin" --repo "$REPO" --path "$KPATH" --ref "$REF" ${lrarg[@]+"${lrarg[@]}"} 2>&1)"; then
      if [ "$before" = "$(wt_state "$wt")" ]; then echo "OK wt-shim $wt (같음)"
      else n=$((n + 1)); echo "REFRESHED wt-shim $wt ${old:-없음} -> $LIVE/bin · $(printf '%s\n' "$out" | grep . | tail -1)"; fi
    else
      rc=$?; nfail=$((nfail + 1)); echo "ERROR wt-shim $wt rc=$rc: $(printf '%s\n' "$out" | grep . | tail -1)"
    fi
  done < <(git -C "$COMMON" worktree list --porcelain | sed -n 's/^worktree //p')
  if [ "$APPLY" != 1 ]; then echo "WT-SHIM plan=$n skip=$skip (dry-run · 쓰기 0)"; return 0; fi
  echo "WT-SHIM refreshed=$n skip=$skip fail=$nfail"
  [ "$nfail" = 0 ] || WT_FAIL=1
}
if [ "$APPLY" != 1 ]; then wt_shim_refresh; plist_sync; comm_sync; restart_scan; hook_audit; echo "(dry-run: 쓰지 않았다 — 설치하려면 --apply)"; exit 0; fi

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
hcopied=0; hsame=0; hchmod=0
for h in $HOME_HOOKS; do
  src="$HARNESS/kit/hooks/$h"; dst="$HOME_DIR/.claude/hooks/$h"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    hsame=$((hsame + 1))
  else
    mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"
    cmp -s "$src" "$dst" || { echo "ERROR: 훅 복사 불일치: $h" >&2; exit 1; }
    hcopied=$((hcopied + 1))
  fi
  # r491: cmp 는 내용만 — 실행 비트는 따로(키트 644 · 손 cp 664 여도 홈에선 실행돼야 한다)
  [ -x "$dst" ] || { chmod +x "$dst"; hchmod=$((hchmod + 1)); echo "HOOK $dst chmod +x"; }
done
echo "HOOKS copied=$hcopied same=$hsame chmod=$hchmod (settings.json 등록은 별도)"

# 프로젝트 LIVE_BIN·LIVE_ROOT·연결 파일 — 설치본 도구로(키트 트리 = 이 하네스 체크아웃의 HEAD)
REPO="$(git -C "$HARNESS" rev-parse --show-toplevel)"; REPO="$(cd "$REPO" && pwd -P)"
REF="$(git -C "$REPO" rev-parse HEAD)"
KPATH="${HARNESS#"$REPO"/}/kit/fable-team/bin"
INIT_ARG=(); [ "$SHIM_INIT" = 0 ] || INIT_ARG=(--init)   # r494: rc≠0 = set -e 로 여기서 멈춘다(ERROR 줄 그대로)
bash "$LIVE/bin/ft-root-bin-shim.sh" --root "$PROJECT" --live "$LIVE/bin" --live-root "$LROOT" \
  --repo "$REPO" --path "$KPATH" --ref "$REF" ${INIT_ARG[@]+"${INIT_ARG[@]}"}
wt_shim_refresh   # r512: 공용 루트 전환 «뒤» 등록 워크트리 연결 파일 갱신
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
if [ -n "$PREV" ] && [ "$PREV" != "$LIVE/bin" ]; then echo "되돌림 1줄: printf '%s\\n' '$PREV' > '$PROJECT/.fable-team/LIVE_BIN'"
else echo "되돌림: 이전 LIVE_BIN 값 ${PREV:-없음}(이번 값과 같거나 없음 — 되돌릴 것 0)"; fi
# r464: plist 는 LIVE_BIN 전환 «뒤» — plist 실패가 코드 전환을 막지 못한다(1.1.25 «새 폴더만 생김» 사고)
plist_sync
restart_scan   # r459: plist 단계(재적재한 라벨은 새로 기동) «뒤» 의 기동 시각으로 판정
hook_audit     # r491: 등록 훅 전수 — 손으로 들어온 훅의 실행 비트·실재도 여기서 걸린다
if [ "$HOOK_FAIL" = 1 ]; then echo "INSTALLED $VERSION · HOOK-EXEC ERROR — 설치는 끝났다 · 위 ERROR HOOK-EXEC 줄의 훅을 고친다(chmod +x 또는 settings 등록 정리 = master)"; echo "== 끝 =="; exit 1; fi
if [ "$PLIST_FAIL" = 1 ]; then echo "INSTALLED $VERSION · PLIST ERROR — LIVE_BIN 전환은 끝났다 · plist 는 위 RESTORED/ERROR 줄"; echo "== 끝 =="; exit 1; fi
if [ "$WT_FAIL" = 1 ]; then echo "INSTALLED $VERSION · WT-SHIM ERROR — LIVE_BIN 전환은 끝났다 · 위 ERROR wt-shim 줄의 워크트리는 옛 판 그대로(손 = bash $LIVE/bin/ft-root-bin-shim.sh --root <워크트리> --live $LIVE/bin)"; echo "== 끝 =="; exit 1; fi
echo "INSTALLED $VERSION · PLIST ok"
echo "== 끝 =="
