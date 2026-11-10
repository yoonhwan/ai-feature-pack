#!/usr/bin/env bash
# test_stall_scan_skip_paused_r1307.sh — r1307 팀 정지 표식(PAUSED) 팀은 ft-stall-scan 경보 대상이 아니다.
#   본문 = tests/scripts/test_stall_scan_skip_paused_r1307.py (R1~R8 · 판정 = ft_card_assign_pause.team_paused 재사용)
#   + 회귀(기존 stall 시험 4종 · team_paused 정본 r1291) + 변이 5종(사본 bin 치환 → 그 시험 FAIL → 복구)
# 격리: 합성 jsonl · 가짜 명부·tmux·mbox·seat-status(임시 폴더 · FT_ROOT 임시 루트) — 실 좌석 깨우기·ring·쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_py() { (cd "$SC" && R1307_BIN="$1" pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1); }

run_py "$KIT" test_stall_scan_skip_paused_r1307.py; ck "R1~R8 $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?

# ⓕ — 기존 stall 판정·페널티 시험은 기대 변경 0
for t in test_ft_stall_scan.py test_ft_stall_scan_off_roster.py test_ft_stall_scan_wake_r638.py test_ft_penalty.py; do
  run_py "$KIT" "$t"; ck "ⓕ 회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
done

# ⓖ — team_paused 정본(r1291) 무변경 확인: 그 카드 시험 그대로 통과
(ulimit -u 2000; timeout 200 bash "$HERE/test_card_assign_paused_held_r1291.sh" >"$T/r1291.log" 2>&1); ck "ⓖ 회귀 r1291 팀 정지 표식 정본 $(tail -1 "$T/r1291.log")" $?

# 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" test_stall_scan_skip_paused_r1307.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "표식 갈래 제거" ft_stall_scan.py '(penalty is not None and team not in resumed and team not in exempt) or paused(team)' '(penalty is not None and team not in resumed and team not in exempt)' r1
mutate "q 를 on 으로(조용한 처리 0)" ft_stall_scan.py 'pcache[team] = st == "on"' 'pcache[team] = st != "none"' r3
mutate "캐시 제거(좌석마다 호출)" ft_stall_scan.py 'if team != "-" and team not in pcache and os.environ.get(' 'if team != "-" and True and os.environ.get(' r4
mutate "WARN 을 self.notes 에" ft_stall_scan.py '                    notes.append(f"WARN 정지 표식 판정 불가' '                    self.notes.append(f"WARN 정지 표식 판정 불가' r3
mutate "held 건너뜀을 f·d 에만(b 제외)" ft_stall_scan.py 'f["attached"] or f["held"] or self.now' 'f["attached"] or (f["held"] and f["kind"] in "fd") or self.now' r8
sha_after="$(shasum "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 100644
for n in ft_stall_scan.py ft_card_assign_pause.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
grep -q 'pause.team_paused(self.root, team)' "$KIT/ft_stall_scan.py"; ck "판정 = ft_card_assign_pause.team_paused 재사용" $?
[ "$(stat -f %Lp "$HERE/test_stall_scan_skip_paused_r1307.sh")" = 644 ]; ck "새 시험 모드 644" $?
echo "ft_stall_scan.py $(wc -l <"$KIT/ft_stall_scan.py")줄(origin/main 366 · 늘린 줄 12)"
echo "FAIL=$fail"; [ "$fail" = 0 ]
