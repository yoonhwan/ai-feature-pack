#!/usr/bin/env bash
# test_root_bin_shim_r657.sh — r657: 루트 연결 파일(shim)이 부른 쪽의 -p(특권 모드)를 «다음 bash» 에 이어 준다 · 축 ⓐ~ⓕ.
#   사건: 루트 shim 은 -p 로 돌지만 끝줄 `exec bash <라이브 도구>` 가 -p 를 떨궈, 첫 줄에서 «-p 아니면 거절» 하는
#   도구(ft-redis-readonly-user.sh)가 rc2 로 막혔다(오빠 h38 · r623 실사건). 고침 = 생성기가 «부른 쪽이 -p 면 -p» 를 이어 준다.
#   도구 쪽 검사는 그대로 — -p 없이 부르면 지금처럼 거절된다(약화 0 · 축 ⓒ 가 그대로 확인).
# mktemp 만 쓴다(임시 «루트» 리포 + 임시 «라이브 bin»(가짜 도구 3종)) — 진짜 루트 .fable-team/bin 쓰기 0 · press 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SH="${FT_R657_SHIM:-$HERE/../../harness/bin/ft-root-bin-shim.sh}"                    # 추적 짝(생성기)
KITSH="${FT_R657_KITSH:-$HERE/../../harness/kit/fable-team/bin/ft-root-bin-shim.sh}"  # 키트 정본
#   ★FT_R657_* 는 «생성기 판» 입력 주입점이다 — 고치기 전(base) 판을 넣어 «실패 시험 먼저» 를 남기는 자리(제품 우회 플래그 0).★
REL="feature-pack/fable-team/harness/kit/fable-team/bin/ft-root-bin-shim.sh"
BASE="${FT_R657_BASE:-949cc998}"    # base = origin/main(팩 · spawn 2026-10-21) — «고치기 전 FAIL» 대조용
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
PENV=(env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin)   # -p 로 부르는 쪽과 같은 «깨끗한 환경»(BASH_ENV·별칭 0)

bash -n "$SH" && ok "bash -n (추적 짝)" || bad "bash -n (추적 짝)"
bash -n "$KITSH" && ok "bash -n (키트)" || bad "bash -n (키트)"
cmp -s "$SH" "$KITSH" && ok "추적 짝 = 키트(cmp0)" || bad "추적 짝 ≠ 키트"

git -C "$HERE" show "$BASE:$REL" > "$T/base-shim.sh" 2>/dev/null && ok "base 판 생성기 추출($BASE)" || bad "base 판 생성기 추출 실패($BASE:$REL)"
grep -q 'bash" -p' "$T/base-shim.sh" && bad "base 판에 -p 이어주기가 이미 있다(대조 불가)" || ok "base 판 = -p 이어주기 없음(사건 재현 전제)"

KP="scripts/harness-install/fable-team/bin"
build() {  # $1 = 작업 폴더 → 루트 리포($1/root) + 라이브($1/live)
  local W="$1"; rm -rf "$W"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live"
  git init -q -b main "$W/root"
  printf 'echo kit-p\n'  > "$W/root/$KP/ft-p.sh"    # «-p 아니면 거절» 도구(ft-redis-readonly-user.sh 대역)
  printf 'echo kit-a\n'  > "$W/root/$KP/ft-a.sh"    # 보통 .sh 도구
  printf 'print(1)\n'    > "$W/root/$KP/ft-b.py"    # .py 도구
  git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m kit
  # 라이브 ft-p.sh = 실제 도구의 첫 검사 2개(-p · BASH_ENV)만 옮긴 가짜(그 뒤 성공 출력)
  cat > "$W/live/ft-p.sh" <<'EOS'
#!/usr/bin/env bash
case "$-" in *p*) ;; *) echo "REJECT -p 아님: \$-" ; exit 2;; esac
[ -z "${BASH_ENV+x}" ] || { echo "REJECT BASH_ENV 있음"; exit 2; }   # 실제 도구(r623 r6)와 같은 꼴: «설정됨» 자체를 거절
pfl=0; case "$-" in *p*) pfl=1;; esac
echo "OK PFLAG=$pfl args=$*"
exit 0
EOS
  # 라이브 ft-a.sh = 자기 $HERE·인자·stdin 을 찍고 rc7(«보통 .sh 도구» 꼴 그대로)
  printf '#!/usr/bin/env bash\nHERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"\necho "LIVE-A HERE=$HERE args=$*"; cat; exit 7\n' > "$W/live/ft-a.sh"
  printf 'import sys,os\nprint("LIVE-B", os.path.dirname(os.path.abspath(__file__)), sys.argv[1:])\n' > "$W/live/ft-b.py"
  printf 'old-p\n' > "$W/root/.fable-team/bin/ft-p.sh"   # 옛 사본(stale 로 갈 것)
}
GEN() { local gen="$1" W="$2"; shift 2; bash "$gen" --root "$W/root" --live "$W/live" --ref HEAD --repo "$W/root" --path "$KP" "$@"; }

# ── ⓐ 고치기 «전»(base 판) 재현 — -p 로 부르면 도구가 거절한다(이 시험이 잡아야 하는 FAIL 지점) ──
W1="$T/w1"; build "$W1"; RB1="$W1/root/.fable-team/bin"
out="$(GEN "$T/base-shim.sh" "$W1" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓐ base 판 생성"
has "$out" "SHIM 3 · MOVED 1 · UNKNOWN 0" "ⓐ base 판 숫자(SHIM 3 · MOVED 1 · UNKNOWN 0)"
hasnt "$(cat "$RB1/ft-p.sh")" 'bash" -p' "ⓐ base 판 연결 파일에 -p 이어주기 0"
out="$("${PENV[@]}" /bin/bash -p "$RB1/ft-p.sh" ensure 2>&1)"; rc=$?
rc_is "$rc" 2 "ⓐ base 판: /bin/bash -p <shim> → 도구 rc2(고치기 전 FAIL 지점)"
has "$out" "REJECT -p 아님" "ⓐ base 판: REJECT 원문"

# ── ⓑ 고친 판 — 같은 입력이 rc0 · 도구 안에서 $- 에 p ──
W2="$T/w2"; build "$W2"; RB2="$W2/root/.fable-team/bin"
out="$(GEN "$SH" "$W2" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓑ 고친 판 생성"
has "$out" "SHIM 3 · MOVED 1 · UNKNOWN 0" "ⓑ 고친 판 숫자(base 와 같음)"
has "$(cat "$RB2/ft-p.sh")" 'case "$-" in *p*) exec "${BASH:-bash}" -p "$_l/ft-p.sh" "$@"' "ⓑ 연결 파일에 -p 이어주기 1줄"
out="$("${PENV[@]}" /bin/bash -p "$RB2/ft-p.sh" ensure 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓑ 고친 판: /bin/bash -p <shim> ensure → rc0"
has "$out" "OK PFLAG=1 args=ensure" "ⓑ 도구 안 \$- 에 p · 인자 그대로"
# 부른 쪽이 -p 가 아니면 지금과 같은 줄로 넘어간다(맨 bash)
out="$(bash "$RB2/ft-p.sh" ensure 2>&1)"; rc=$?
has "$(cat "$RB2/ft-p.sh")" 'exec bash "$_l/ft-p.sh" "$@"' "ⓑ -p 없을 때 줄 = 이전 판 그대로(맨 bash)"

# ── ⓒ 도구 검사 약화 0 — -p 없이·BASH_ENV 를 둔 채로는 여전히 거절 ──
out="$("${PENV[@]}" /bin/bash "$RB2/ft-p.sh" ensure 2>&1)"; rc=$?
rc_is "$rc" 2 "ⓒ -p 없이 연결 파일 실행 → 도구 rc2 그대로"
has "$out" "REJECT -p 아님" "ⓒ -p 없음 REJECT 원문"
printf 'echo BENV-TRAP\n' > "$T/benv.sh"
out="$("${PENV[@]}" BASH_ENV="$T/benv.sh" /bin/bash -p "$RB2/ft-p.sh" ensure 2>&1)"; rc=$?
rc_is "$rc" 2 "ⓒ BASH_ENV 를 둔 채 -p 실행 → 도구 rc2 그대로"
has "$out" "REJECT BASH_ENV 있음" "ⓒ BASH_ENV REJECT 원문"
hasnt "$out" "BENV-TRAP" "ⓒ BASH_ENV 를 읽지 않는다(특권 모드 유지)"

# ── ⓓ 보통 .sh·.py 도구는 이전 판과 같은 동작(.py 연결 파일 본문 바이트 동일) ──
out="$(printf 'IN\n' | bash "$RB2/ft-a.sh" one "two words" 2>&1)"; rc=$?
outb="$(printf 'IN\n' | bash "$RB1/ft-a.sh" one "two words" 2>&1)"; rcb=$?
has "$out" "LIVE-A HERE=$W2/live args=one two words" "ⓓ 보통 .sh: \$HERE=라이브 · 인자 그대로"
has "$out" "IN" "ⓓ 보통 .sh: stdin 그대로"
rc_is "$rc" 7 "ⓓ 보통 .sh: rc 그대로"
[ "${out//$W2/live/LIVE}" = "${outb//$W1/live/LIVE}" ] && [ "$rc" = "$rcb" ] && ok "ⓓ 보통 .sh: 출력·rc 이전 판과 같음(HERE 경로만 워크트리 차이)" || bad "ⓓ 보통 .sh 가 이전 판과 다르다 :: «${out//$W2/live/LIVE}» ≠ «${outb//$W1/live/LIVE}»"
out="$(bash "$RB2/ft-b.py" 1 2 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓓ .py: rc0"
has "$out" "LIVE-B $W2/live ['1', '2']" "ⓓ .py: \$HERE=라이브 · 인자 그대로"
cmp -s "$RB1/ft-b.py" "$RB2/ft-b.py" && ok "ⓓ .py 연결 파일 본문 바이트 동일(변경 0)" || bad "ⓓ .py 연결 파일이 바뀌었다"
dadd="$(diff "$RB1/ft-a.sh" "$RB2/ft-a.sh" | grep -c '^>')"; ddel="$(diff "$RB1/ft-a.sh" "$RB2/ft-a.sh" | grep -c '^<')"
[ "$dadd" = 1 ] && [ "$ddel" = 0 ] && ok "ⓓ .sh 연결 파일 차이 = 1줄 추가(-p 이어주기)뿐" || bad "ⓓ .sh 차이 = 추가 $dadd · 삭제 $ddel (1·0 기대)"

# ── ⓔ 생성기 멱등 · 이전 판 shim 이 있는 루트에 새 판을 돌리면 본문만 다시 쓴다(MOVED 0) ──
snap1="$(cd "$RB2" && cksum * | sort)"; nst1="$(ls -d "$W2/root/.fable-team"/bin.stale-* 2>/dev/null | wc -l | tr -d ' ')"
out="$(GEN "$SH" "$W2" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓔ 두 번째 실행"
has "$out" "SHIM 3 · MOVED 0 · UNKNOWN 0" "ⓔ 두 번째 = MOVED 0 · 숫자 같음"
[ "$snap1" = "$(cd "$RB2" && cksum * | sort)" ] && [ "$nst1" = "$(ls -d "$W2/root/.fable-team"/bin.stale-* 2>/dev/null | wc -l | tr -d ' ')" ] && ok "ⓔ 멱등(바이트·stale 폴더 수 불변)" || bad "ⓔ 멱등 아님"
out="$(GEN "$SH" "$W1" --dry-run 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓔ base 판 shim 이 있는 루트에 --dry-run"
has "$out" "SHIM 3 · MOVED 0 · UNKNOWN 0" "ⓔ base 판 shim 은 «연결 파일» 로 인정(옮기기 0)"
cmp -s "$RB1/ft-p.sh" "$RB2/ft-p.sh" && bad "ⓔ --dry-run 이 본문을 썼다" || ok "ⓔ --dry-run 쓰기 0(base 판 본문 그대로)"
out="$(GEN "$SH" "$W1" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓔ base 판 shim 이 있는 루트에 새 판 실행"
has "$out" "SHIM 3 · MOVED 0 · UNKNOWN 0" "ⓔ 본문만 다시 씀(MOVED 0 · 숫자 같음)"
cmp -s "$RB1/ft-p.sh" "$RB2/ft-p.sh" && ok "ⓔ base 판 shim → 새 판 본문으로 갱신" || bad "ⓔ 갱신 안 됨"
out="$("${PENV[@]}" /bin/bash -p "$RB1/ft-p.sh" ensure 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓔ 갱신된(base 판 자리) shim 도 -p 를 이어 줌"

# ── ⓕ 인접 시험 — shim 을 다루는 기존 시험 전부 PASS(이 카드가 깨뜨리지 않았다) ──
for t in test_root_bin_shim.sh test_root_bin_shim_r613.sh test_root_bin_shim_r616.sh \
         test_install_worktree_shim.sh test_live_install_check_shim.sh \
         test_live_install_check_bin_row_shim.sh test_tick_shim_guard.sh; do
  out="$(bash "$HERE/$t" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && ok "ⓕ $t (rc=0 · $(printf '%s' "$out" | grep -c '^PASS') PASS)" \
                || bad "ⓕ $t — rc=$rc :: $(printf '%s' "$out" | grep '^FAIL' | head -3 | tr '\n' ' ')"
done

echo "== fail=$fail"; [ "$fail" = 0 ]
