#!/usr/bin/env bash
# test_roots_registry_r1309.sh — r1309 루트 명부(roots.tsv) + 정상화 장치 일반화(기획 3184 r3 · Issue #5941).
#   본문 = tests/scripts/test_roots_registry_r1309.py (X2~X12 · 임시 루트 2: BYZ 꼴 + origin 없는 하위 폴더 루트)
#   + 회귀 4종 + 변이 5종(사본 bin/comm 치환 → 그 시험이 FAIL → 복구) + 짝 사본 cmp0 + 새 시험 모드 644.
#   X1·X1b(kakao 루트 stall-scan plist 를 실제 적재한 뒤의 [멈춤] 판정)는 설치 h 뒤에만 잴 수 있다 — 이 시험은 재지 않는다(카드 B·C 소관).
#   ★rc 는 «명령이 낸 값» 을 먼저 변수로 받는다★ — ck "…$(grep…|tail…)" $? 꼴은 $? 가 tail rc 를 받아 실패를 PASS 로 찍는다(REWORK r1 반례 2).
#   사전 flake 1: test_card_assign_rosters_r1298 은 «date +%s 직후 prepare» 라 부하가 크면 1초 창을 넘겨 rc3 이 될 수 있다(내 변경과 무관 · 단독 재실행으로 판정).
# 격리: 실 launchd·실 우편함·실 /tmp 상태·실 좌석 tmux 0 — 가짜 tmux·가짜 launchctl 만 PATH 에, git 은 임시 폴더에만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; COMM="$HERE/../comm"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cp -Rp "$KIT" "$T/bin" && cp -Rp "$COMM" "$T/comm"
run_py() { (cd "$SC" && R1309_BIN="$1" R1309_COMM="${2:-$T/comm}" pytest -q -p no:cacheprovider test_roots_registry_r1309.py ${3:+-k "$3"} >"$T/py.log" 2>&1); return $?; }

run_py "$T/bin"; rc=$?; ck "X2~X12 (14) $(grep -Eo '[0-9]+ passed' "$T/py.log")" "$rc"

# ⓖ 회귀 — 기대 변경 0 (r1298 팀 attach · 배정 감시 명부 · stall 명부 밖 · mbox 가드)
( ulimit -u 2000; timeout 70 bash "$HERE/test_team_attach_r1298.sh" >"$T/r1.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 r1298 팀 attach $(tail -1 "$T/r1.log")" "$rc"
( ulimit -u 2000; timeout 70 bash "$HERE/test_card_assign_rosters_r1298.sh" >"$T/r2.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 r1298 배정 감시 $(tail -1 "$T/r2.log")" "$rc"
( ulimit -u 2000; timeout 70 bash "$HERE/test_mbox_guard.sh" >"$T/r3.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 mbox 가드 $(tail -1 "$T/r3.log")" "$rc"
( cd "$SC" && ulimit -u 2000; R1309_BIN="$KIT" R1309_COMM="$COMM" timeout 70 pytest -q -p no:cacheprovider test_ft_stall_scan_off_roster.py >"$T/r4.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 stall 명부 밖 $(grep -Eo '[0-9]+ passed' "$T/r4.log")" "$rc"

# 변이 — 사본의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험 $6 comm|bin
  local dir="$T/bin"; [ "${6:-bin}" = comm ] && dir="$T/comm"
  python3 - "$dir/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" "$T/comm" "$5"; rc=$?; [ "$rc" -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$([ "${6:-bin}" = comm ] && echo "$COMM" || echo "$KIT")/$2" "$dir/$2"
}
mutate "①명부 칸 무시" ft_team_lib.py 'first = roster_names(base)' 'first = {}' r2
mutate "②잠금 중복 검사 제거" ft_team_attach_roots.py '            if bad:
                raise AttachError("REJECT 루트 틱 잠금 경로 중복: " + " · ".join(bad))' '            if False:
                raise AttachError("REJECT 루트 틱 잠금 경로 중복: " + " · ".join(bad))' r5
mutate "③mbox 다리 제거" mbox_ops.py 'bridged = mbox_roots.bridge(to, frm, body)' 'bridged = None' r6 comm
mutate "④다른 루트 좌석 제외 제거" ft_stall_detect.py 'if s not in other]' 'if True]' r10
mutate "⑤ref 인자 무시(origin/main)" ft_team_attach_ops.py 'row = f"{team}\t.\t{basis_ref(root)}\t{rel}/indices\n"' 'row = f"{team}\t.\torigin/main\t{rel}/indices\n"' r3

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 644 · 새 도구 실행 비트 0
for n in ft_team_lib.py ft_team_attach.py ft_team_attach_lib.py ft_team_attach_ops.py ft_team_attach_roots.py \
         ft_tick_lock.py ft_stall_detect.py ft_card_assign_watch.py ft-tick.sh ft-root-hil.sh; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
[ "$(stat -f %Lp "$HERE/test_roots_registry_r1309.sh")" = 644 ]; ck "새 시험 모드 644(셸)" $?
[ "$(stat -f %Lp "$SC/test_roots_registry_r1309.py")" = 644 ]; ck "새 시험 모드 644(py)" $?
[ "$(stat -f %Lp "$KIT/ft-root-hil.sh")" = 644 ]; ck "새 도구 실행 비트 0(ft-root-hil.sh · bash 로 부른다)" $?
bash "$KIT/ft-test-reentry-lint.sh" "$SC/test_roots_registry_r1309.py" >/dev/null 2>&1; ck "재진입 표지 lint rc0" $?
# 200줄 규칙 — 이번에 늘어난 모듈은 전부 200줄 이하(REWORK r1 반례 6)
for n in ft_team_attach_ops.py ft_team_attach_roots.py ft_tick_lock.py ft_team_attach_lib.py; do
  [ "$(wc -l <"$KIT/$n")" -le 200 ]; ck "200줄 이하 $n ($(wc -l <"$KIT/$n")줄)" $?
done
# 설치 대상 고지 — mbox_ops 가 import 하는 mbox_roots.py 가 드리프트 목록에 있어야 한다(REWORK r1 반례 5)
grep -q '"mbox_roots.py|.fable-team/comm/mbox_roots.py"' "$COMM/check-drift.sh"; ck "설치 감시 목록에 comm/mbox_roots.py" $?
echo "새 시험 $(wc -l <"$SC/test_roots_registry_r1309.py")줄 · 본문 반례 X2~X12 + X6 되돌림"
echo "FAIL=$fail"; [ "$fail" = 0 ]
