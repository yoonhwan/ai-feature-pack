#!/usr/bin/env bash
# test_root_bin_shim_py_python.sh — r746: 루트 연결 파일(shim) 중 이름이 *.py 인 것은 «올바른 python» 이다 · 축 ⓐ~ⓙ.
#   사건: ft-root-bin-shim.sh 가 이름이 .py 여도 bash 본문(`#!/usr/bin/env bash` … `exec python3 "$_l/<이름>"`)을 썼다 →
#   루트·워크트리 bin 의 .py 연결 파일 112개가 «python 으로 읽는 모든 길»(시험의 ast.parse · python3 직접 실행 · import)에서 SyntaxError.
#   고침 = .py 이름은 python 본문(1행 `#!/usr/bin/env python3` · 2행 표식 · LIVE_BIN 검사 3종 · import = ImportError · 실행 = os.execv 로 라이브 사본).
# mktemp 만 쓴다(임시 «루트» 리포 + 임시 «라이브 bin»(자기 폴더·인자를 찍는 가짜 도구)) — 진짜 루트·워크트리 bin 쓰기 0 · press 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SH="${FT_R746_SHIM:-$HERE/../../harness/bin/ft-root-bin-shim.sh}"                    # 추적 짝(생성기)
KITSH="${FT_R746_KITSH:-$HERE/../../harness/kit/fable-team/bin/ft-root-bin-shim.sh}"  # 키트 정본
#   ★FT_R746_* 는 «생성기 판» 입력 주입점이다 — 고치기 전(base) 판을 넣어 «실패 시험 먼저» 를 남기는 자리(제품 우회 플래그 0).★
REL="feature-pack/fable-team/harness/kit/fable-team/bin/ft-root-bin-shim.sh"
BASE="${FT_R746_BASE:-2e0bb166}"    # base = origin/main(팩 · spawn 2026-10-22) — «고치기 전 FAIL» 대조용
T="$(cd -- "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
AST()  { python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$1" 2>&1; }   # 시험이 .py 를 «python 으로 읽는» 길(사건 그 자리)

bash -n "$SH" && ok "bash -n (추적 짝)" || bad "bash -n (추적 짝)"
cmp -s "$SH" "$KITSH" && ok "추적 짝 = 키트(cmp0)" || bad "추적 짝 ≠ 키트"

git -C "$HERE" show "$BASE:$REL" > "$T/base-shim.sh" 2>/dev/null && ok "base 판 생성기 추출($BASE)" || bad "base 판 생성기 추출 실패($BASE:$REL)"
grep -q 'shim_body_py' "$T/base-shim.sh" && bad "base 판에 .py python 본문이 이미 있다(대조 불가)" || ok "base 판 = .py 도 bash 본문(사건 재현 전제)"

KP="scripts/harness-install/fable-team/bin"
build() {  # $1 = 작업 폴더 → 루트 리포($1/root) + 라이브($1/live)
  local W="$1"; rm -rf "$W"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live"
  git init -q -b main "$W/root"
  printf 'print(1)\n' > "$W/root/$KP/foo.py"; printf 'echo kit-bar\n' > "$W/root/$KP/bar.sh"
  git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m kit
  # 라이브 foo.py = 자기 폴더·인자를 찍고 rc7(«진짜 .py 도구» 꼴)
  printf 'import os,sys\nprint("LIVE-FOO", os.path.dirname(os.path.abspath(__file__)), sys.argv[1:])\nsys.exit(7)\n' > "$W/live/foo.py"
  printf '#!/usr/bin/env bash\necho "LIVE-BAR $*"\n' > "$W/live/bar.sh"
  printf 'old-foo\n' > "$W/root/.fable-team/bin/foo.py"; chmod 755 "$W/root/.fable-team/bin/foo.py"   # 루트 옛 사본(stale 로 갈 것)
}
GEN() { local gen="$1" W="$2"; shift 2; bash "$gen" --root "$W/root" --live "$W/live" --ref HEAD --repo "$W/root" --path "$KP" "$@"; }

# ── ⓐ 고치기 «전»(base 판) 재현 — .py 연결 파일이 bash 라 ast.parse·python3 실행이 SyntaxError(이 시험이 잡아야 하는 FAIL 지점) ──
W1="$T/w1"; build "$W1"; RB1="$W1/root/.fable-team/bin"
out="$(GEN "$T/base-shim.sh" "$W1" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓐ base 판 생성"
has "$out" "SHIM 2 · MOVED 1 · UNKNOWN 0" "ⓐ base 판 숫자(SHIM 2 · MOVED 1 · UNKNOWN 0)"
head -1 "$RB1/foo.py" | grep -q '^#!/usr/bin/env bash$' && ok "ⓐ base 판 foo.py 1행 = bash(사건 그대로)" || bad "ⓐ base 판 foo.py 1행이 bash 가 아니다"
out="$(AST "$RB1/foo.py")"; has "$out" "SyntaxError" "ⓐ base 판: ast.parse = SyntaxError(사건 재현)"
out="$(python3 "$RB1/foo.py" x 2>&1)"; rc=$?; has "$out" "SyntaxError" "ⓐ base 판: python3 <foo.py> = SyntaxError"; [ "$rc" != 0 ] && ok "ⓐ base 판: rc≠0 ($rc)" || bad "ⓐ base 판인데 rc=0"

# ── ⓑ 고친 판 — ast.parse 통과 · 1행 python3 셔뱅 · 2행 표식(지금 문구 그대로) ──
W2="$T/w2"; build "$W2"; RB2="$W2/root/.fable-team/bin"
out="$(GEN "$SH" "$W2" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓑ 고친 판 생성"
has "$out" "SHIM 2 · MOVED 1 · UNKNOWN 0" "ⓑ 고친 판 숫자(base 와 같음)"
out="$(AST "$RB2/foo.py")"; rc=$?; rc_is "$rc" 0 "ⓑ ast.parse 통과"; hasnt "$out" "SyntaxError" "ⓑ ast.parse SyntaxError 0"
[ "$(head -1 "$RB2/foo.py")" = '#!/usr/bin/env python3' ] && ok "ⓑ 1행 = #!/usr/bin/env python3" || bad "ⓑ 1행=$(head -1 "$RB2/foo.py")"
sed -n '2p' "$RB2/foo.py" | grep -qF '# ft-root-bin-shim:' && ok "ⓑ 2행 표식(# ft-root-bin-shim:) — r613·드리프트·틱 head -3 판정 그대로" || bad "ⓑ 2행 표식 없음: $(sed -n '2p' "$RB2/foo.py")"
has "$(sed -n '2p' "$RB2/foo.py")" "foo.py → LIVE_BIN" "ⓑ 2행 문구 = 지금 그대로(이름 → LIVE_BIN)"
has "$(cat "$RB2/foo.py")" "os.execv(sys.executable, [sys.executable, _t] + sys.argv[1:])" "ⓑ 실행 = os.execv(sys.executable, [..., 라이브 경로, *argv[1:]])"
has "$(cat "$RB2/foo.py")" 'if __name__ != "__main__":' "ⓑ import 가드(__name__ != __main__) 1줄"

# ── ⓒ 실행 3길: python3 <bin>/foo.py · <bin>/foo.py(셔뱅) = 라이브 foo.py 가 같은 argv 로 돈다 · 종료 코드 그대로 ──
out="$(python3 "$RB2/foo.py" a "b c" 2>&1)"; rc=$?; rc_is "$rc" 7 "ⓒ python3 <foo.py> rc 그대로(라이브 rc7)"
has "$out" "LIVE-FOO $W2/live ['a', 'b c']" "ⓒ python3 <foo.py>: \$HERE=라이브 · 인자 그대로"
[ -x "$RB2/foo.py" ] && ok "ⓒ 연결 파일 실행 비트 755" || bad "ⓒ 실행 비트 없음"
out="$("$RB2/foo.py" a "b c" 2>&1)"; rc=$?; rc_is "$rc" 7 "ⓒ <foo.py> 직접 실행(셔뱅) rc 그대로"
has "$out" "LIVE-FOO $W2/live ['a', 'b c']" "ⓒ <foo.py> 직접 실행: 인자 그대로"
out="$(printf 'IN\n' | "$RB2/foo.py" 2>&1)"; hasnt "$out" "SyntaxError" "ⓒ stdin 파이프에서도 SyntaxError 0"
out="$(bash "$RB2/bar.sh" one 2>&1)"; has "$out" "LIVE-BAR one" "ⓒ .sh 연결 파일은 지금처럼 bash 로 라이브 도구 실행"

# ── ⓓ import = ImportError 로 «크게» 실패 · 조용한 성공 0 ──
out="$(python3 -B -c "import sys;sys.path.insert(0,'$RB2');import foo" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok "ⓓ import foo rc≠0 ($rc)" || bad "ⓓ import foo 인데 rc=0(조용한 성공)"
has "$out" "ImportError" "ⓓ import foo → ImportError"
has "$out" "LIVE_BIN 사본을 import" "ⓓ ImportError 문구에 «LIVE_BIN 사본을 import»(어디로 가야 하는지)"
hasnt "$out" "LIVE-FOO" "ⓓ import 로 라이브 도구가 돌지 않는다(조용한 성공 0)"
out="$(python3 -B -c "import sys;sys.path.insert(0,'$RB2');import bar" 2>&1)"; hasnt "$out" "ImportError" "ⓓ .sh 이름은 import 대상이 아니다(ImportError 0 — 모듈 없음)"

# ── ⓔ 오류 3종 = 지금 bash 판과 «같은 문구» · rc 3 ──
BASEBIN="$W2/root/.fable-team/bin-bash"; mkdir -p "$BASEBIN"; cp "$RB1/foo.py" "$BASEBIN/foo.py"   # base 판(bash 본문) 사본 = 같은 루트의 형제 폴더(../LIVE_BIN 이 같은 파일)
mv "$W2/root/.fable-team/LIVE_BIN" "$T/lb.bak"
out="$(python3 "$RB2/foo.py" 2>&1)"; rc=$?; rc_is "$rc" 3 "ⓔ LIVE_BIN 없음 → rc3"; has "$out" "ERROR LIVE_BIN 이 없거나 비었다: $W2/root/.fable-team/bin/../LIVE_BIN" "ⓔ LIVE_BIN 없음 문구 = 지금 그대로(경로 꼴도 bash 판과 같다 · 정규화 0)"
outb="$(bash "$BASEBIN/foo.py" 2>&1)"; outb="${outb//bin-bash/bin}"; [ "$out" = "$outb" ] && ok "ⓔ base 판(bash 본문을 bash 로 실행)과 «같은 문구» 바이트 동일" || bad "ⓔ base 판 문구와 다르다 :: «${out}» ≠ «${outb}»"
: > "$W2/root/.fable-team/LIVE_BIN"
out="$(python3 "$RB2/foo.py" 2>&1)"; rc=$?; rc_is "$rc" 3 "ⓔ LIVE_BIN 빈 값 → rc3"; has "$out" "ERROR LIVE_BIN 이 없거나 비었다" "ⓔ 빈 값 문구"
printf 'live\n' > "$W2/root/.fable-team/LIVE_BIN"   # 상대 경로(cwd=$W2 에서 실재하는 폴더 — 검사가 없으면 라이브 도구가 돈다)
out="$(cd "$W2" && python3 "$RB2/foo.py" 2>&1)"; rc=$?; rc_is "$rc" 3 "ⓔ 상대 LIVE_BIN → rc3"
has "$out" "ERROR LIVE_BIN 이 절대경로(/ 로 시작)가 아니다: live ($W2/root/.fable-team/bin/../LIVE_BIN)" "ⓔ 절대경로 아님 문구 = 지금 그대로"
hasnt "$out" "LIVE-FOO" "ⓔ 상대 LIVE_BIN 인데 라이브 도구 실행 0"
printf '%s\n' "$W2/live" > "$W2/root/.fable-team/LIVE_BIN"; mv "$W2/live/foo.py" "$T/foo.bak"
out="$(python3 "$RB2/foo.py" 2>&1)"; rc=$?; rc_is "$rc" 3 "ⓔ 라이브 도구 없음 → rc3"; has "$out" "ERROR 라이브 도구 없음: $W2/live/foo.py" "ⓔ 라이브 도구 없음 문구 = 지금 그대로"
outb="$(bash "$BASEBIN/foo.py" 2>&1)"; outb="${outb//bin-bash/bin}"; [ "$out" = "$outb" ] && ok "ⓔ 라이브 도구 없음도 base 판과 같은 문구" || bad "ⓔ 라이브 도구 없음 문구가 base 판과 다름 :: «${out}» ≠ «${outb}»"
mv "$T/foo.bak" "$W2/live/foo.py"

# ── ⓕ .sh 연결 파일 = 지금 판과 바이트 동일(r657 -p 줄 포함) ──
cmp -s "$RB1/bar.sh" "$RB2/bar.sh" && ok "ⓕ .sh 연결 파일 = base 판과 바이트 동일" || bad "ⓕ .sh 연결 파일이 바뀌었다 :: $(diff "$RB1/bar.sh" "$RB2/bar.sh" | head -4 | tr '\n' ' ')"
has "$(cat "$RB2/bar.sh")" 'case "$-" in *p*) exec "${BASH:-bash}" -p "$_l/bar.sh" "$@"' "ⓕ r657 -p 이어주기 줄 그대로(.sh)"

# ── ⓖ 멱등 · 옛 bash 판 .py 연결 파일이 있는 루트에서 재실행 = 새 python 판으로 덮어씀(MOVED 0) ──
out="$(GEN "$SH" "$W1" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓖ base 판 루트에 새 판 실행"
has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "ⓖ 옛 bash 판 .py 도 «연결 파일» 로 인정(옮기기 0)"
head -1 "$RB1/foo.py" | grep -q '^#!/usr/bin/env python3$' && ok "ⓖ 옛 bash 판 foo.py → python 판으로 덮어씀" || bad "ⓖ 갱신 안 됨: $(head -1 "$RB1/foo.py")"
cmp -s "$RB1/foo.py" "$RB2/foo.py" && ok "ⓖ 덮어쓴 본문 = 새 판 본문(바이트 동일)" || bad "ⓖ 덮어쓴 본문이 새 판과 다르다"
snap1="$(cd "$RB2" && cksum * | sort)"; nst1="$(ls -d "$W2/root/.fable-team"/bin.stale-* 2>/dev/null | wc -l | tr -d ' ')"
out="$(GEN "$SH" "$W2" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓖ 두 번째 실행"
has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "ⓖ 두 번째 = MOVED 0 · 숫자 같음"
[ "$snap1" = "$(cd "$RB2" && cksum * | sort)" ] && [ "$nst1" = "$(ls -d "$W2/root/.fable-team"/bin.stale-* 2>/dev/null | wc -l | tr -d ' ')" ] && ok "ⓖ 멱등(바이트·stale 폴더 수 불변)" || bad "ⓖ 멱등 아님"
out="$(GEN "$SH" "$W2" --dry-run 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓖ --dry-run"

# ── ⓘ 변이: .py python 분기를 지운 판(bash 본문으로 되돌림) → ⓑ 단언이 깨진다(시험이 이빨이 있는지) ──
MUT="$T/shim-mut.sh"; grep -v 'shim_body_py "\$name"; return' "$SH" > "$MUT"
[ "$(grep -c 'shim_body_py "\$name"; return' "$MUT" || true)" = 0 ] && ok "ⓘ 변이 파일 생성(.py 분기 제거)" || bad "ⓘ 변이 생성 실패"
W3="$T/w3"; build "$W3"; RB3="$W3/root/.fable-team/bin"
bash "$MUT" --root "$W3/root" --live "$W3/live" --ref HEAD --repo "$W3/root" --path "$KP" >/dev/null 2>&1
head -1 "$RB3/foo.py" | grep -q '^#!/usr/bin/env bash$' && ok "ⓘ 변이 판 foo.py 1행 = bash(고치기 전으로 되돌아감)" || bad "ⓘ 변이 판이 bash 본문이 아니다"
has "$(AST "$RB3/foo.py")" "SyntaxError" "ⓘ 변이 시 ⓑ 단언이 깨진다(ast.parse SyntaxError — 시험이 변이를 잡는다)"

# ── ⓡ 옛 호출 꼴(bash/sh)도 계속 돈다 — 3행 겸용 줄 · 4길(bash·sh·python3·직접) argv·rc 같음 + 변이(겸용 줄 삭제 → bash FAIL) ──
sed -n '3p' "$RB2/foo.py" | grep -qxF '"exec" "python3" "$0" "$@"' && ok "ⓡ 3행 = bash·python 겸용 줄(\"exec\" \"python3\" \"$0\" \"$@\")" || bad "ⓡ 3행 겸용 줄 없음: $(sed -n '3p' "$RB2/foo.py")"
AST "$RB2/foo.py" >/dev/null 2>&1 && ok "ⓡ 겸용 줄이 있어도 ast.parse 통과(문자열 식)" || bad "ⓡ 겸용 줄 뒤 ast.parse 실패"
want="LIVE-FOO $W2/live ['a', 'b c']"
r1="$(bash "$RB2/foo.py" a "b c" 2>&1)"; rc1=$?
r2="$(sh "$RB2/foo.py" a "b c" 2>&1)"; rc2=$?
r3="$(python3 "$RB2/foo.py" a "b c" 2>&1)"; rc3=$?
r4="$("$RB2/foo.py" a "b c" 2>&1)"; rc4=$?
[ "$r1" = "$want" ] && ok "ⓡ bash <shim>.py — 옛 호출 꼴 그대로(라이브 사본으로 넘어간다)" || bad "ⓡ bash <shim>.py 출력: «${r1}»"
[ "$r2" = "$want" ] && ok "ⓡ sh <shim>.py" || bad "ⓡ sh <shim>.py 출력: «${r2}»"
[ "$r3" = "$want" ] && [ "$r4" = "$want" ] && ok "ⓡ python3 <shim>.py · <shim>.py 직접 실행 = 같은 argv" || bad "ⓡ python3/직접 출력: «${r3}» / «${r4}»"
[ "$rc1$rc2$rc3$rc4" = "7777" ] && ok "ⓡ 4길 종료 코드 모두 라이브 rc7 그대로" || bad "ⓡ 4길 rc = $rc1/$rc2/$rc3/$rc4 (7777 기대)"
MUT2="$T/shim-mut-noline.sh"; grep -v '"exec" "python3"' "$SH" > "$MUT2"   # 겸용 줄(생성기 본문은 \$0 \$@ 로 이스케이프) 삭제
[ "$(grep -cF '"exec" "python3"' "$MUT2" || true)" = 0 ] && ok "ⓡ 변이 파일 생성(겸용 줄 제거)" || bad "ⓡ 변이 생성 실패"
W4="$T/w4"; build "$W4"; RB4="$W4/root/.fable-team/bin"
bash "$MUT2" --root "$W4/root" --live "$W4/live" --ref HEAD --repo "$W4/root" --path "$KP" >/dev/null 2>&1
out="$(bash "$RB4/foo.py" a 2>&1)"; rc=$?
[ "$rc" != 0 ] && hasnt "$out" "LIVE-FOO" "ⓡ 변이 시 bash <shim>.py 가 깨진다(겸용 줄이 계약임을 시험이 잡는다 · rc=$rc)" || bad "ⓡ 변이인데도 bash <shim>.py 가 돈다"
python3 "$RB4/foo.py" a >/dev/null 2>&1; [ "$?" = 7 ] && ok "ⓡ 변이 판도 python3 길은 산다(겸용 줄은 bash 길 전용)" || bad "ⓡ 변이 판 python3 길이 죽었다"

# ── ⓗ 인접 시험 — shim 을 다루는 기존 시험 전부 PASS(이 카드가 깨뜨리지 않았다) ──
for t in test_root_bin_shim.sh test_root_bin_shim_r613.sh test_root_bin_shim_r616.sh test_root_bin_shim_r657.sh \
         test_install_worktree_shim.sh test_live_install_check_shim.sh \
         test_live_install_check_bin_row_shim.sh test_tick_shim_guard.sh; do
  out="$(bash "$HERE/$t" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && ok "ⓗ $t (rc=0 · $(printf '%s' "$out" | grep -c '^PASS') PASS)" \
                || bad "ⓗ $t — rc=$rc :: $(printf '%s' "$out" | grep '^FAIL' | head -3 | tr '\n' ' ')"
done

# ── ⓙ 격리 — 임시 루트·가짜 LIVE_BIN 만 썼다(실 상태 지문 = real_state_guard 가 시험 끝에 비교) ──
[ -f "$T/w1/root/.fable-team/LIVE_BIN" ] && [ -f "$T/w2/root/.fable-team/LIVE_BIN" ] && ok "ⓙ LIVE_BIN 은 임시 루트에만($T 아래) — 실 루트 쓰기 0" || bad "ⓙ 임시 루트 LIVE_BIN 없음"
case "$(cat "$W2/root/.fable-team/LIVE_BIN")" in "$T"/*) ok "ⓙ LIVE_BIN 값 = 가짜 라이브($T 아래)";; *) bad "ⓙ LIVE_BIN 값이 임시 밖: $(cat "$W2/root/.fable-team/LIVE_BIN")";; esac

echo "== fail=$fail"; [ "$fail" = 0 ]
