#!/usr/bin/env bash
# test_all_stop_off_paused_left_r2085.sh — 전팀 정지 끄기(off)가 팀 정지 표식(state/<팀>-tick/PAUSED)이 남은 팀 수·이름을 1줄로 낸다 (r2085).
# 격리: 임시 git 루트(FT_ROOT · 시나리오마다 틀 복사) + 임시 명부 2팀 + 가짜 mbox(FAKE_MAIL 에 받은 인자만) — 실 상태 폴더·mbox·명부 쓰기 0 · sleep 0.
# 기준판 = 같은 코드에서 표식 줄 함수(paused_left)만 빈 함수로 바꾼 실행(FT_R2085_BASE_BIN = 다른 bin 폴더 · 기본 = 시험 대상 bin).
# 대상 bin 바꾸기(변이·기준판 Red 확인) = FT_R2085_BIN=<bin 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -u
export LC_ALL=C FT_ALLOW_TRACKED_BIN=1 FT_ALL_STOP_BY=r2085 FT_NOW=1793000000
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R2085_BIN:-$HERE/../../harness/kit/fable-team/bin}"; BASE="${FT_R2085_BASE_BIN:-$BIN}"
fail=0; out=""; rc=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/lib/fake_resource_env.sh"
TPL="$TMP/tpl"; mkdir -p "$TPL"
fake_comm_root "$TPL" || bad "fake_comm_root"
printf '#!/usr/bin/env bash\nprintf "%%s\\t" "$@" >> "$FAKE_MAIL"; echo >> "$FAKE_MAIL"\ncase "$2" in *bb-master*) [ -n "${FAKE_FAIL:-}" ] && exit 1;; esac\nexit 0\n' > "$TMP/mbox.sh"
export FT_MBOX_SH="$TMP/mbox.sh"
mkdir -p "$TPL/design/teams/aa" "$TPL/design/teams/bb"
echo '{"_label":"aa","_master":"byz-aa-master-claude#1","byz-aa-master-claude#1":{"role":"master"}}' > "$TPL/.fable-team/seats-aa.json"
echo '{"_label":"bb","_master":"byz-bb-master-claude#2","byz-bb-master-claude#2":{"role":"master"}}' > "$TPL/.fable-team/seats-bb.json"
echo '{}' > "$TPL/.fable-team/seats.json"
printf '| aa | `design/teams/aa/` | a | 현역 |\n| bb | `design/teams/bb/` | b | 현역 |\n' >> "$TPL/design/TEAMS.md"
git -C "$TPL" add design/TEAMS.md && git -C "$TPL" -c user.name=t -c user.email=t@t commit -q -m teams && git -C "$TPL" update-ref refs/remotes/origin/main HEAD || bad "명단 고정"

# run <impl new|base> <명령…> — FT_ROOT=$D 에서 실행 · out·rc
run() {
  local impl="$1"; shift
  if [ "$impl" = new ]; then out="$(cd "$D" && FT_ROOT="$D" bash "$BIN/ft-all-stop.sh" "$@" 2>&1)"; rc=$?
  else out="$(cd "$D" && FT_ROOT="$D" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_all_stop as a; a.paused_left = lambda: None; sys.exit(a.main(sys.argv[2:]))' "$BASE" "$@" 2>&1)"; rc=$?; fi
}
# scen <이름> <impl> <표식 팀…> — 틀 복사 → 표식 → on → 통지 비움 → off (FAKE_FAIL 은 부른 쪽 env)
scen() {
  local name="$1" impl="$2"; shift 2
  D="$TMP/s-$name-$impl"; cp -R "$TPL" "$D"; export FAKE_MAIL="$D/mail.log"
  for t in "$@"; do mkdir -p "$D/.fable-team/state/$t-tick"; : > "$D/.fable-team/state/$t-tick/PAUSED"; done
  FAKE_FAIL= run new on "r2085 시험" >/dev/null; : > "$FAKE_MAIL"
  run "$impl" off
}
L2="팀 정지 표식 2팀 남음: a · b — 전팀 정지와 별개 · 이 팀들은 계속 멈춰 있다"
marks() { python3 -c 'import os,sys
for dp,_,fs in sorted(os.walk(sys.argv[1])):
  for f in sorted(fs):
    if dp.endswith("-tick"): p=os.path.join(dp,f); print(p[len(sys.argv[1]):], os.stat(p).st_mtime_ns)' "$1/.fable-team/state"; }

# ── ① 남은 팀 (P1) ──
scen m1 new a b; o1="$out"; r1=$rc; D1="$D"
o1="$(printf '%s\n' "$o1" | grep -v '^WARN ')"
[ "$r1" = 0 ] && [ "$(printf '%s\n' "$o1" | sed -n 1p | cut -c1-22)" = "all_stop=off released=" ] && [ "$(printf '%s\n' "$o1" | sed -n 2p)" = "$L2" ] && [ "$(printf '%s\n' "$o1" | wc -l | tr -d ' ')" = 2 ]
ck "① 표식 a·b + 끄기 → 결과 줄 다음 «2팀 남음: a · b» · rc0" $?
scen m7 new a b c d e f g; out="$(printf '%s\n' "$out" | grep -v '^WARN ')"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "팀 정지 표식 7팀 남음: a · b · c · d · e 외 2 — 전팀 정지와 별개 · 이 팀들은 계속 멈춰 있다" ]
ck "① 표식 7팀 → 이름 5개 + « 외 2»" $?
D="$D1"; export FAKE_MAIL="$D/mail.log"; run new off
[ "$rc" = 0 ] && [ "$out" = "all_stop=off (이미 꺼짐) — 변경 0
$L2" ]; ck "① 이미 꺼진 상태 off → «이미 꺼짐» 줄 다음 같은 줄" $?
FAKE_FAIL=1 scen nf new a b; out="$(printf '%s\n' "$out" | grep -v '^WARN ')"
[ "$rc" = 3 ] && printf '%s\n' "$out" | sed -n 2p | grep -q '^상태 바뀜 · 통지 실패 1: byz-bb-master-claude#2' && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "$L2" ]
ck "① 통지 실패 → rc3 · 실패 줄 다음 같은 줄" $?
D="$TMP/s-nf-new"; export FAKE_MAIL="$D/mail.log"; run new off; out="$(printf '%s\n' "$out" | grep -v '^WARN ')"
[ "$rc" = 0 ] && printf '%s\n' "$out" | sed -n 1p | grep -q '^all_stop=off (이미 꺼짐 · 실패분 재통지 1)' && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$L2" ]
ck "① 실패분 재통지 갈래 → 결과 줄 다음 같은 줄" $?

# ── ② 없는 경우 (P1 · 기준판과 바이트 같음) ──
for c in none dir bak; do
  for impl in new base; do
    D="$TMP/z2-$c-$impl"; cp -R "$TPL" "$D"; export FAKE_MAIL="$D/mail.log"
    case "$c" in dir) mkdir -p "$D/.fable-team/state/a-tick";; bak) mkdir -p "$D/.fable-team/state/a-tick"; : > "$D/.fable-team/state/a-tick/PAUSED.bak";; esac
    FAKE_FAIL= run new on "r2085 시험" >/dev/null; : > "$FAKE_MAIL"; run "$impl" off
    eval "o_$impl=\$out; r_$impl=\$rc"
  done
  # shellcheck disable=SC2154
  [ "$o_new" = "$o_base" ] && [ "$r_new" = "$r_base" ] && ! printf '%s\n' "$o_new" | grep -q '팀 정지 표식'
  ck "② 표식 ${c} → 줄 0 · 출력·rc 기준판과 바이트 같음" $?
done

# ── ③ 쓰기 0 (P2) ──
scen w new a b; mk_after="$(marks "$D")"; ln_new="$(grep -c . "$D/.fable-team/state/all-stop.log")"; mail_new="$D/mail.log"; on_new="$out"
cp -R "$TPL" "$TMP/w0"; D="$TMP/w0"; mkdir -p "$D/.fable-team/state/a-tick" "$D/.fable-team/state/b-tick"; : > "$D/.fable-team/state/a-tick/PAUSED"; : > "$D/.fable-team/state/b-tick/PAUSED"
export FAKE_MAIL="$D/mail.log"; run new on "r2085 시험" >/dev/null; : > "$FAKE_MAIL"; mk_before="$(marks "$D")"; run new off; mk_after0="$(marks "$D")"
[ "$mk_before" = "$mk_after0" ] && [ "$(printf '%s\n' "$mk_after0" | grep -c PAUSED)" = 2 ]; ck "③ 끄기 앞뒤 표식 파일 수·mtime 같음" $?
scen w base a b; ln_base="$(grep -c . "$D/.fable-team/state/all-stop.log")"
[ "$ln_new" = "$ln_base" ] && cmp -s "$mail_new" "$D/mail.log" && [ -s "$mail_new" ] && [ "$(printf '%s\n' "$mk_after" | cut -d' ' -f1)" = "$(marks "$D" | cut -d' ' -f1)" ]
ck "③ 원장 줄 수·통지 본문·표식 = 기준판 off 와 같음" $?
[ "$(printf '%s\n' "$on_new" | grep -vxF "$L2")" = "$out" ] && [ "$on_new" != "$out" ]; ck "③ 결과 줄·rc = 기준판과 같음(새 줄만 더함)" $?

# ── ④ 불변 (P3) ──
for cmd in "on|r2085 x" status check "on|r2085 x" status check; do
  for impl in new base; do
    D="$TMP/u-$impl"; [ -d "$D" ] || { cp -R "$TPL" "$D"; mkdir -p "$D/.fable-team/state/a-tick"; : > "$D/.fable-team/state/a-tick/PAUSED"; }
    export FAKE_MAIL="$D/mail.log"; IFS='|' read -r -a args <<<"$cmd"; run "$impl" "${args[@]}"
    eval "o_$impl=\$out; r_$impl=\$rc"
  done
  [ "$o_new" = "$o_base" ] && [ "$r_new" = "$r_base" ] && ! printf '%s\n' "$o_new" | grep -q '팀 정지 표식'
  ck "④ 표식 있음 · ${cmd%%|*} 출력·rc 기준판과 같음(rc=$r_new)" $?
done
D="$TMP/rej"; cp -R "$TPL" "$D"; mv "$D/.fable-team/state" "$D/.fable-team/state.x"; export FAKE_MAIL="$D/mail.log"; run new off
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^REJECT off 못 함 — 상태 폴더 없음' && ! printf '%s\n' "$out" | grep -q '팀 정지 표식'
ck "④ 상태 폴더 없음 → off REJECT rc1 · 표식 줄 0" $?
cmp -s "$HERE/../bin/ft_all_stop.py" "$HERE/../kit/fable-team/bin/ft_all_stop.py"; ck "④ bin = kit ft_all_stop.py cmp 0" $?

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
