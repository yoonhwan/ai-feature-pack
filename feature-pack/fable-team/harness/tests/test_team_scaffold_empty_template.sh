#!/usr/bin/env bash
# test_team_scaffold_empty_template.sh — R377: 틀 파일 0 인 틀 폴더 REJECT + 라이브 틀 폴더 설치 지도 행.
# 임시 git 리포·임시 틀 폴더·임시 FT_BIN 만 — 실 design/·실 라이브 쓰기 0. press 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"; KITROOT="$HERE/../../harness/kit"
KIT="$KITROOT/fable-team"; KITMAP="$KITROOT/LIVE-MAP.tsv"; CHK="$SRCDIR/ft-live-install-check.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAM_TEMPLATE_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 FT_TEAM_NO_STAMP=1

REPO="$T/repo"; mkdir -p "$REPO/design"
cat > "$REPO/design/TEAMS.md" <<'E'
| 팀 | 폴더 | 오케 좌석 | 상태 |
|---|---|---|---|
| demo | `design/demo/` | demo-master 계열 | 현역 |
E
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t && git -C "$REPO" add -A && git -C "$REPO" commit -qm base

# 가짜 라이브 폴더: <live>/bin/ft-team-scaffold.sh 의 «$HERE/../templates/team» = <live>/templates/team (VERSION 1파일 — R368 설치 상태)
LIVE="$T/live"; mkdir -p "$LIVE/bin" "$LIVE/templates/team"
cp "$SRCDIR/ft-team-scaffold.sh" "$SRCDIR/ft-team-lib.sh" "$LIVE/bin/"; cp "$KIT/templates/team/VERSION" "$LIVE/templates/team/VERSION"
LSC() { (cd "$REPO" && FT_REPO_ROOT="$REPO" bash "$LIVE/bin/ft-team-scaffold.sh" "$@" 2>&1); }

# ⓐ 라이브 틀 폴더가 VERSION 만 → dry-run REJECT + 후보 2 경로 + rc1
out="$(LSC --dry-run demo)"; rc=$?
[ "$rc" = 1 ] && has "REJECT 틀 파일 0: $LIVE/bin/../templates/team" && has "scripts/harness-install/fable-team/templates/team"; ck "ⓐ VERSION 만 → dry-run REJECT + 후보 2 경로 rc1" $?
! has "OK dry-run"; ck "ⓐ' 조용한 통과 문구 0" $?
# ⓑ 같은 조건 실행 모드도 REJECT · 쓰기 0
out="$(LSC demo)"; rc=$?
[ "$rc" = 1 ] && has "REJECT 틀 파일 0" && [ ! -e "$REPO/design/demo" ]; ck "ⓑ 실행 모드도 REJECT · design/demo 쓰기 0" $?
# ⓒ 틀 14파일이 있으면 기존 동작
mkdir -p "$T/full"; cp -R "$KIT/templates/team/." "$T/full/"
out="$(cd "$REPO" && FT_REPO_ROOT="$REPO" FT_TEAM_TEMPLATE_DIR="$T/full" bash "$SRCDIR/ft-team-scaffold.sh" --dry-run demo 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "OK dry-run would-create=14"; ck "ⓒ 틀 14파일 → OK dry-run would-create=14" $?
out="$(cd "$REPO" && FT_REPO_ROOT="$REPO" FT_TEAM_TEMPLATE_DIR="$T/full" bash "$SRCDIR/ft-team-scaffold.sh" demo 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "OK created=14"; ck "ⓒ' 실행 → OK created=14" $?
# ⓓ FT_TEAM_TEMPLATE_DIR 명시가 빈 폴더(또는 VERSION 만)여도 REJECT — 폴백 0
mkdir -p "$T/empty" "$T/veronly"; cp "$KIT/templates/team/VERSION" "$T/veronly/"
for d in "$T/empty" "$T/veronly"; do
  out="$(cd "$REPO" && FT_REPO_ROOT="$REPO" FT_TEAM_TEMPLATE_DIR="$d" bash "$SRCDIR/ft-team-scaffold.sh" --dry-run demo 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "REJECT 틀 파일 0: $d"; ck "ⓓ 명시 틀 폴더 ${d##*/} → REJECT (키트로 폴백 0)" $?
done

# ⓔ LIVE-MAP: 지도 첫 일치 — 틀 폴더 = cmp → $FT_BIN/../templates/team · hooks 틀 = 여전히 skip
firstrow() { python3 -I - "$KITMAP" "$1" <<'PY'
import fnmatch, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip() and not l.startswith("#")]
r = next((r for r in rows if fnmatch.fnmatch(sys.argv[2], r[0])), None)
print("|".join(r[:3]) if r else "NONE")
PY
}
out="$(firstrow fable-team/templates/team/README.md)"; rc=0
[ "$out" = 'fable-team/templates/team/*|cmp|$FT_BIN/../templates/team' ]; ck "ⓔ 틀 폴더 파일 → cmp \$FT_BIN/../templates/team" $?
out="$(firstrow fable-team/templates/team/indices/inbox/.gitkeep)"; rc=0
[ "$out" = 'fable-team/templates/team/*|cmp|$FT_BIN/../templates/team' ]; ck "ⓔ' 중첩 틀 파일도 같은 행" $?
out="$(firstrow fable-team/templates/hooks/x.sh)"; rc=0
[ "$out" = 'fable-team/templates/*|skip|-' ]; ck "ⓔ'' hooks 틀은 여전히 skip" $?

# ⓕ 착지 검사: 틀 폴더에 VERSION 만 → PENDING + MISSING 14 + HINT / 폴더째 cp 뒤 → OK
KR="$T/kit"; mkdir -p "$KR/scripts/harness-install/fable-team/templates"
cp "$KITMAP" "$KR/scripts/harness-install/LIVE-MAP.tsv"; cp -R "$KIT/templates/team" "$KR/scripts/harness-install/fable-team/templates/team"
git -C "$KR" init -q -b main . && git -C "$KR" config user.email t@t && git -C "$KR" config user.name t && git -C "$KR" add -A && git -C "$KR" commit -qm kit
git -C "$KR" update-ref refs/remotes/origin/main HEAD
export HOME="$T/home" FT_BIN="$T/ftbin"; mkdir -p "$HOME" "$FT_BIN" "$T/templates/team"
cp "$KIT/templates/team/VERSION" "$T/templates/team/VERSION"
out="$(bash "$CHK" --all --repo "$KR" 2>&1)"; rc=$?
n="$(printf '%s\n' "$out" | grep -c '^MISSING scripts/harness-install/fable-team/templates/team/')"
[ "$rc" = 1 ] && has "PENDING" && [ "$n" = 14 ] && has "HINT fable-team master: cp -pR"; ck "ⓕ VERSION 만 → PENDING + MISSING 14 + HINT (n=$n)" $?
cp -R "$KIT/templates/team/." "$T/templates/team/"
out="$(bash "$CHK" --all --repo "$KR" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "OK n=15"; ck "ⓕ' 폴더째 cp 뒤 → OK n=15 (중첩 경로 대조)" $?
echo drift >> "$T/templates/team/indices/inbox/.gitkeep"
out="$(bash "$CHK" --all --repo "$KR" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "DIFF scripts/harness-install/fable-team/templates/team/indices/inbox/.gitkeep -> $T/ftbin/../templates/team/indices/inbox/.gitkeep"; ck "ⓕ'' 중첩 파일 어긋남 → DIFF 가 중첩 라이브 경로로" $?

# ⓖ 같은 git 트리에 한글 파일 + non-UTF8(0xff) 파일 — 검사기 예외 0 · 한글 경로 원형 · 0xff 는 조용한 통과 0 (DA⑥ r1)
cp -R "$KIT/templates/team/." "$T/templates/team/"
TD="$KR/scripts/harness-install/fable-team/templates/team"
mkdir -p "$TD/indices/대기"; echo ko > "$TD/indices/대기/한글.md"; git -C "$KR" add -A
bblob="$(echo bad | git -C "$KR" hash-object -w --stdin)"
git -C "$KR" update-index --add --cacheinfo "100644,$bblob,scripts/harness-install/fable-team/templates/team/bad-"$'\xff'".txt"
git -C "$KR" commit -qm utf8 && git -C "$KR" update-ref refs/remotes/origin/main HEAD
for LC in C en_US.UTF-8; do
  out="$(LC_ALL=$LC bash "$CHK" --all --repo "$KR" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && ! has "Traceback" && ! has "ERROR" && has "MISSING scripts/harness-install/fable-team/templates/team/indices/대기/한글.md -> $T/ftbin/../templates/team/indices/대기/한글.md"; ck "ⓖ[$LC] 한글 경로 MISSING 줄 원형 · 예외 0" $?
  has 'MISSING scripts/harness-install/fable-team/templates/team/bad-\udcff.txt'; ck "ⓖ'[$LC] 0xff 파일은 조용히 지나가지 않고 MISSING 줄로 (\udcff 이스케이프)" $?
done

echo "fail=$fail"; [ "$fail" = 0 ]
