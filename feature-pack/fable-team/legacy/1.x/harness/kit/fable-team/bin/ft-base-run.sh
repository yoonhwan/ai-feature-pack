#!/usr/bin/env bash
# ft-base-run.sh — «기준판에서도 같은 시험이 FAILED 인가» 비교를 한 명령으로 (r2377). 사본은 한 곳($TMPDIR 아래)에서 살고 그 자리에서 죽는다.
#   사용: ft-base-run.sh <sha|ref> [--repo <리포>] [--path <폴더>]… [--git] -- <시험 명령…>
#     사본 = `$TMPDIR/tmp.ftbase.<6>` · 그 안 `tree/` 에 트리를 풀고 → `tree/` 에서 `ft-test-run.sh <시험 명령…>` → 끝나면(rc 무관) 그 폴더 하나만 지운다.
#     --repo <리포>  기본 = 지금 리포 · --path <폴더> = 트리에서 그 폴더만 풀기(반복 · 없으면 통째) · --git = `tree/` 에 git 을 붙인다
#     첫 줄 stdout = `BASE <그 폴더>/tree <sha 10>` · 남은 사본은 이름꼴(tmp.ftbase.*)로 `ft-scratch-repo.sh --sweep`(240분)이 줍는다 — SIGKILL 로 죽었을 때만 그 길이다
#     푸는 몫은 시험 70초 밖이다(BYZ 통째 1.7G 는 풀기만 수십 초) — 좁힐 땐 --path 를 쓴다.
#   rc 표: 시험 rc 그대로 · 사용법 틀림(`--` 없음·시험 명령 없음) = 2 · 판정 불가(ref·archive·tar·git) = 20 (`BASE-RUN 판정 불가 — <사유>` 1줄 · 사본 0 · 시험 0) · 지움 실패 = rc 그대로 + `WARN 기준판 사본 남음 <경로>` 1줄(stderr)
#   env: FT_BASE_ARCHIVE_SEC(60 · 하드 룰 12 배치 상한 70 안) · FT_BASE_REF_SEC(7) · FT_BASE_RUN_RUNNER(기본 = 같은 폴더 ft-test-run.sh)
#   하드 룰 12(외부 호출 상한) · 19(사본도 일반 폴더) · 20(외부 명령 실패 판정은 이 파일 한 곳) · 22 · «만들면 지운다»(R246)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { echo "usage: ft-base-run.sh <sha|ref> [--repo <리포>] [--path <폴더>]… [--git] -- <시험 명령…>" >&2; exit 2; }
REF=""; REPO=""; PATHS=(); GITMODE=0; CMD=(); DD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --) DD=1; shift; CMD=("$@"); break;;
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || usage; REPO="$2"; shift 2;;
    --path) [ $# -ge 2 ] && [ -n "$2" ] || usage; PATHS+=("$2"); shift 2;;
    --git) GITMODE=1; shift;;
    -*) usage;;
    *) [ -z "$REF" ] || usage; REF="$1"; shift;;
  esac
done
[ -n "$REF" ] || usage; [ "$DD" = 1 ] || usage; [ "${#CMD[@]}" -gt 0 ] || usage

TMO=""; command -v gtimeout >/dev/null 2>&1 && TMO="$(command -v gtimeout)"; [ -n "$TMO" ] || { command -v timeout >/dev/null 2>&1 && TMO="$(command -v timeout)"; }
bound() { local s="$1"; shift; if [ -n "$TMO" ]; then "$TMO" -k 5 "$s" "$@"; else "$@"; fi; }   # r2377: 외부 호출은 상한을 두고 부른다(상한 도구가 없으면 그대로 — 판정은 아래 한 곳)
BASE_ROOT="${TMPDIR:-/tmp}"; while [ "${BASE_ROOT%/}" != "$BASE_ROOT" ]; do BASE_ROOT="${BASE_ROOT%/}"; done
DIR=""; TREE=""; CHILD=""

reap_dir() { # 이 실행이 만든 사본 하나만 지운다 — 경로 대조 = 바깥 TMPDIR 바로 아래 ∧ 이름 머리 tmp.ftbase. (r2377 K3) · 지웠으면 0
  [ -n "$DIR" ] && [ -e "$DIR" ] || return 0
  case "${DIR%/*}" in "$BASE_ROOT") ;; *) echo "WARN 기준판 사본 남음 $DIR" >&2; return 1;; esac
  case "${DIR##*/}" in tmp.ftbase.*) ;; *) echo "WARN 기준판 사본 남음 $DIR" >&2; return 1;; esac
  rm -rf -- "$DIR" 2>/dev/null
  [ -e "$DIR" ] && { echo "WARN 기준판 사본 남음 $DIR" >&2; return 1; }
  return 0
}
bad20() { reap_dir >/dev/null 2>&1; echo "BASE-RUN 판정 불가 — $1"; exit 20; }   # r2377: 판정 불가는 이 한 곳(하드 룰 20)
on_signal() { # r2377 K3: 자식(ft-test-run)에 TERM → 상한 5초 wait → 사본 지움 → 128+신호
  local n="$1" i
  if [ -n "$CHILD" ]; then kill -TERM "$CHILD" 2>/dev/null; for i in $(seq 25); do kill -0 "$CHILD" 2>/dev/null || break; sleep 0.2; done; fi
  CHILD=""; reap_dir >/dev/null 2>&1; exit $((128+n))
}
trap 'on_signal 1' HUP
trap 'on_signal 2' INT
trap 'on_signal 15' TERM

if [ -n "$REPO" ]; then REPO_ABS="$(cd -- "$REPO" 2>/dev/null && pwd -P)" || bad20 "repo $REPO — 폴더 아님"
else REPO_ABS="$(git rev-parse --show-toplevel 2>/dev/null)" || bad20 "repo — git 저장소 밖(--repo 로 지정)"; fi
OUT_REF="$(bound "${FT_BASE_REF_SEC:-7}" git -C "$REPO_ABS" rev-parse --verify --quiet "$REF^{commit}" 2>/dev/null)"; RC=$?
[ "$RC" = 0 ] && [ -n "$OUT_REF" ] || bad20 "ref $REF — 커밋으로 못 풂(git rc=$RC)"
SHA="${OUT_REF%%$'\n'*}"
case "$SHA" in *[!0123456789abcdef]*|"") bad20 "ref $REF — 40자 sha 아님";; esac
[ "${#SHA}" = 40 ] || bad20 "ref $REF — 40자 sha 아님"

DIR="$(mktemp -d "$BASE_ROOT/tmp.ftbase.XXXXXX" 2>/dev/null)" || { DIR=""; bad20 "사본 폴더 못 만듦 — $BASE_ROOT"; }
TREE="$DIR/tree"; mkdir -p "$TREE" 2>/dev/null || bad20 "사본 tree 폴더 못 만듦"
ARCH_SEC="${FT_BASE_ARCHIVE_SEC:-60}"; ARCH_RC=0
{ bound "$ARCH_SEC" git -C "$REPO_ABS" archive "$SHA" ${PATHS[@]+"${PATHS[@]}"}; } | tar -x -C "$TREE" || ARCH_RC=$?
if [ "$ARCH_RC" != 0 ]; then bad20 "archive — git archive/tar 실패 또는 상한 ${ARCH_SEC}초 초과(rc=$ARCH_RC)"; fi

if [ "$GITMODE" = 1 ]; then
  GD="$(git -C "$REPO_ABS" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || bad20 "git — 원 리포 git-common-dir 못 읽음"   # r2377 I2: 원 리포가 worktree 여도 objects 는 common dir 아래
  [ -n "$GD" ] || bad20 "git — 원 리포 git-common-dir 못 읽음"
  git -C "$TREE" init -q >/dev/null 2>&1 || bad20 "git — 사본 init 실패"
  mkdir -p "$TREE/.git/objects/info" 2>/dev/null || bad20 "git — 사본 objects/info 못 만듦"
  printf '%s\n' "$GD/objects" > "$TREE/.git/objects/info/alternates" || bad20 "git — 사본 alternates 못 씀"
  ( cd "$TREE" && git add -A >/dev/null 2>&1 && git -c user.name=ft-base-run -c user.email=ft-base-run@localhost -c commit.gpgsign=false commit -q -m "base ${SHA:0:10}" >/dev/null 2>&1 ) || bad20 "git — 사본 커밋 실패"
fi

RUNNER="${FT_BASE_RUN_RUNNER:-$HERE/ft-test-run.sh}"
[ -f "$RUNNER" ] || bad20 "러너 없음 — $RUNNER"
printf 'BASE %s %s\n' "$TREE" "${SHA:0:10}"
( cd "$TREE" && exec bash "$RUNNER" ${CMD[@]+"${CMD[@]}"} ) & CHILD=$!; wait "$CHILD"; rc=$?
CHILD=""
reap_dir end
exit "$rc"
