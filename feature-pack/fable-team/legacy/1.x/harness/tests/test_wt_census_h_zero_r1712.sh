#!/usr/bin/env bash
# test_wt_census_h_zero_r1712.sh — r1712: ft-wt-census.sh --h 가 빈 표·대상 0 이면 h 를 쓰지 않고, h target 수 = 정리 가능 수 1줄을 낸다.
#   ① worktree list 실패 스텁 + --h → rc≠0 · «판정 불가 — 표 0행 · h 0» · h 파일 0
#   ② 정리 가능 0(모두 KEEP) + --h → rc0 · «대상 0 · h 0» · h 파일 0
#   ③ 정리 가능 2 + --h → h target 2줄 · «h target 2 = 정리 가능 2»
#   ④ --h 없이 같은 픽스처 → 출력 바이트·rc 가 기준판(팩 origin/main)과 같다
#   변이 W1(빈 표 검사 삭제)·W2(대상 0 검사 삭제)·W3(일치 줄 삭제) = 그 사례 FAIL · 변이마다 원본으로 같은 사례 PASS(반대 결과 대조)
#  격리: 임시 bare 원격 + 임시 리포 + 임시 워크트리 2개 · 실 리포·실 tmux 0 · sleep 0 · 사례 70초
#  R1712_TOOL=<파일> 이면 그 판으로 ①~④ 를 돈다(기준판 대조용). mode 100644 — `bash <이 파일>` 로 부른다.
set -uo pipefail
if [ "${R1712_INNER:-0}" != 1 ] && command -v timeout >/dev/null 2>&1; then R1712_INNER=1 exec timeout 70 bash "$0" "$@"; fi
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
BIN="$H/bin/ft-wt-census.sh"; KIT="$H/kit/fable-team/bin/ft-wt-census.sh"; TOOL="${R1712_TOOL:-$BIN}"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
T0=$(date +%s); st(){ echo "단계 $1 $(( $(date +%s) - T0 ))초" >&2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r1712.XXXXXX")"; T="$(cd "$T" && pwd -P)"; R="$T/repo"
trap 'rm -rf "$T"' EXIT INT TERM
export HOME="$T/home" FT_WT_CENSUS_TMUX=0 FT_WT_CENSUS_CONFIG="$T/none.json"; mkdir -p "$HOME"
git init -q --bare "$T/remote.git"; git init -q -b main "$R"; cd "$R" || exit 1
git config user.email a@b.c; git config user.name t; echo base > f.txt; git add f.txt; git commit -qm base
git remote add origin "$T/remote.git"; git push -q -u origin main
echo keep > "$R/untracked.txt"                      # 메인 워크트리 = KEEP:① (대상 밖)
git worktree add -q "$T/wt-a" -b nano/a; git worktree add -q "$T/wt-b" -b nano/b
cat > "$T/failgit" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = worktree ] && { echo "stub: worktree list 실패" >&2; exit 128; }; done
exec git "$@"
EOF
chmod +x "$T/failgit"; st 픽스처
# 사례 판정 = «rc|h파일|마지막 줄» · $1=도구 $2=사례
run(){ local t="$1" hf="$T/h.$RANDOM.sh" o rc; rm -f "$hf"
  case "$2" in
    1) o="$(cd "$T" && FT_WT_CENSUS_GIT="$T/failgit" bash "$t" --repo "$R" --h "$hf" 2>/dev/null)"; rc=$?;;
    2) o="$(cd "$T" && FT_WT_CENSUS_BASES="origin/none" bash "$t" --repo "$R" --h "$hf" 2>/dev/null)"; rc=$?;;
    3) o="$(cd "$T" && bash "$t" --repo "$R" --h "$hf" 2>/dev/null)"; rc=$?;;
  esac
  local hn=0; [ -e "$hf" ] && hn="$(grep -c '^target=' "$hf")"
  printf '%s|%s|%s\n' "$([ "$rc" = 0 ] && echo 0 || echo nz)" "$([ -e "$hf" ] && echo "h:$hn" || echo h0)" "$(printf '%s\n' "$o" | tail -1)"; rm -f "$hf"; }
WANT1="nz|h0|판정 불가 — 표 0행 · h 0"; WANT2="0|h0|대상 0 · h 0"; WANT3="0|h:2|h target 2 = 정리 가능 2"
eq "① 표 0행 = 판정 불가 · h 0 · rc≠0" "$(run "$TOOL" 1)" "$WANT1"; st ①
eq "② 대상 0 = h 0 · rc0" "$(run "$TOOL" 2)" "$WANT2"; st ②
eq "③ h target 2 = 정리 가능 2" "$(run "$TOOL" 3)" "$WANT3"; st ③
BASE="$T/base.sh"
if git -C "$H" show "origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/ft-wt-census.sh" > "$BASE" 2>/dev/null; then
  a="$(cd "$T" && bash "$BASE" --repo "$R" 2>/dev/null; echo "rc=$?")"; b="$(cd "$T" && bash "$TOOL" --repo "$R" 2>/dev/null; echo "rc=$?")"
  eq "④ --h 없음 = 기준판과 바이트·rc 같음" "$([ "$a" = "$b" ] && echo same || echo diff)" same
else bad "④ 기준판(origin/main) 읽기 실패"; fi; st ④
[ -n "${R1712_TOOL:-}" ] && { echo "합계 fail=$fail (도구 $TOOL)"; [ "$fail" = 0 ]; exit; }
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$BIN" "$1" "$2" "$3"; }
chk(){ # $1=이름 $2=사례 $3=기대 $4=변이 파일
  if [ "$(run "$4" "$2")" != "$3" ] && [ "$(run "$BIN" "$2")" = "$3" ]; then ok "$1 변이 검출 + 원본 대조 PASS"; else bad "$1 헛변이"; fi
  cmp -s "$BIN" "$KIT" && ok "$1 뒤 bin·kit cmp0" || bad "$1 뒤 bin·kit 다름"; }
mut "$T/w1.sh" 'if [ -z "$OUT" ]; then H_MSG="판정 불가 — 표 0행 · h 0"; H_RC=1; H_OUT=""; elif' 'if' && chk W1 1 "$WANT1" "$T/w1.sh"; st W1
mut "$T/w2.sh" 'elif [ "$H_N" = 0 ]; then H_MSG="대상 0 · h 0"; H_OUT=""; fi' 'fi' && chk W2 2 "$WANT2" "$T/w2.sh"; st W2
mut "$T/w3.sh" '; [ -z "$ONLY" ] && H_MSG="h target $(grep -c '"'^target='"' "$H_OUT") = 정리 가능 $H_N"' '' && chk W3 3 "$WANT3" "$T/w3.sh"; st W3
eq "S bin·kit cmp0" "$(cmp -s "$BIN" "$KIT" && echo 0 || echo 1)" 0
echo "합계 fail=$fail"; [ "$fail" = 0 ]
