#!/usr/bin/env bash
# r2377_fixture.sh — r2377 두 시험(본·변이)이 함께 쓰는 임시 세계. source 해서 쓴다.
#   임시 리포(커밋 2 · 폴더 2 A/B) · 가짜 git(archive 멈춤) · 러너 사본(부작용 도구는 스텁) · 신호용 sleep30 · probe(사본 안 확인)
#   T 아래는 모두 EXIT trap 이 지운다 · 실 BYZ 리포·실 /tmp 사본 0 · sleep 은 신호 대기 polling 만
#   내주는 값: BIN · SUT · LINT_RUN · RUN · BASE_MODE · T · SRC · A · B · EBIN · T4 · RES · MSG · fail
LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HERE="$(cd -- "$LIB/.." && pwd)"
BIN="${R2377_BIN:-$HERE/../bin}"; BASE_MODE=0; [ -n "${R2377_BIN:-}" ] && BASE_MODE=1
SUT="$BIN/ft-base-run.sh"; LINT_RUN="$BIN/ft-test-reentry-lint.sh"; RUN="$SUT"
fail=0; RES=0; MSG=""; T0=$SECONDS; T4=0
ck() { if [ "$2" = 1 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:0:400}"; fail=$((fail+1)); fi; }
sk() { echo "SKIP $1 :: $2"; }

TT="${TMPDIR:-/tmp}"; T="$(mktemp -d "${TT%/}/r2377.XXXXXX")"; T="${T%/}"; TD=""
trap 'rm -rf "$T" ${TD:+"$TD"}' EXIT

SRC="$T/src"; git init -q "$SRC" || { echo "FAIL 임시 리포 못 만듦"; exit 1; }
git -C "$SRC" config user.email t@t.local; git -C "$SRC" config user.name t
mkdir -p "$SRC/d1" "$SRC/d2"; printf 'A\n' > "$SRC/d1/a.txt"; printf 'B\n' > "$SRC/d2/b.txt"
git -C "$SRC" add -A; git -C "$SRC" commit -q -m A; A="$(git -C "$SRC" rev-parse HEAD)"
printf 'A2\n' > "$SRC/d1/a.txt"; git -C "$SRC" add -A; git -C "$SRC" commit -q -m B; B="$(git -C "$SRC" rev-parse HEAD)"
git -C "$SRC" show "$A:d1/a.txt" > "$T/expect-a.txt"
GIT_REAL="$(command -v git)"

cat > "$T/probe" <<'PROBE'
#!/usr/bin/env bash
# probe — 사본 안에서 pwd·파일 목록·cmp·git 상태를 PROBE_OUT 에 남긴다
set -uo pipefail
O="${PROBE_OUT:?}"; {
  echo "pwd=$PWD"
  echo "files=$(find . -type f -not -path './.git/*' | sed 's|^\./||' | sort | tr '\n' '|')"
  if [ -n "${EXPECT:-}" ]; then cmp -s d1/a.txt "$EXPECT"; echo "cmp=$?"; fi
  if [ -n "${CHECK_D2:-}" ]; then [ -e d2 ] && echo "d2=yes" || echo "d2=no"; fi
  if [ -n "${CHECK_GIT:-}" ]; then
    h="$(git rev-parse HEAD 2>/dev/null)"; echo "head_rc=$?"; echo "head=$h"
    echo "status=$(git status --porcelain 2>/dev/null | grep -c .)"
    echo "log1=$(git log --oneline -1 2>/dev/null)"
    echo "alt=$(cat .git/objects/info/alternates 2>/dev/null)"
  fi
} > "$O" 2>&1
exit "${PROBE_RC:-0}"
PROBE
printf '%s\n' '#!/usr/bin/env bash' 'sleep 30' > "$T/sleep30"   # ⑨·⑩: 시험이 사는 동안 신호를 준다
chmod +x "$T/probe" "$T/sleep30"

FGIT="$T/fgit"; mkdir -p "$FGIT"
cat > "$FGIT/git" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = archive ] && exec sleep 30; done
exec "$GIT_REAL" "\$@"
FAKE
chmod +x "$FGIT/git"

EBIN="$T/ebin"; mkdir -p "$EBIN"
for f in ft-test-run.sh ft-test-reentry-lint.sh; do [ -f "$BIN/$f" ] && cp -p "$BIN/$f" "$EBIN/"; done
cp -p "$HERE/stubs/kit-side-effect.sh" "$EBIN/ft-seat-quiesce.sh"
[ -f "$SUT" ] && cp -p "$SUT" "$EBIN/"

newtmp() { TD="$(mktemp -d "$T/tmpd.XXXXXX")"; }
leftovers() { find "$TD" -maxdepth 1 -mindepth 1 -name 'tmp.ftbase.*' 2>/dev/null | wc -l | tr -d ' '; }
first() { printf '%s\n' "$OUT" | head -1; }
field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }
# split_base <첫 줄> → BASE_OK=1 이면 BPATH·BSHA
split_base() { BPATH=""; BSHA=""; BASE_OK=0; local w p s; read -r w p s <<< "$1"; [ "$w" = BASE ] || return 0
  [ -n "${p:-}" ] && [ -n "${s:-}" ] || return 0; BPATH="$p"; BSHA="$s"; BASE_OK=1; }
