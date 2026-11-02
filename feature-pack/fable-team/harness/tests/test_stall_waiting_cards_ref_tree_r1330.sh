#!/usr/bin/env bash
# test_stall_waiting_cards_ref_tree_r1330.sh — r1330 ft-stall-scan a 가 대기·진행 카드를 «기준 ref 트리» 에서 읽는다.
#   본문 = tests/scripts/test_stall_waiting_cards_ref_tree_r1330.py (S1~S6)
#   + 기준판(팩 origin/main) 대조: S1·S2·S3·S4·S5 FAIL · S6 PASS(바이트 같음)
#   + 변이 4종(사본 bin 치환 → 그 시험 FAIL → 복구): W1 디스크 glob · W2 선행 대조 디스크 · W3 상한 조용히 0 · W4 ref origin/main 고정
#   + 회귀(stall 시험 py 11종) — STEPS=0 이면 회귀 건너뜀(변이·기준판만 빠르게)
# 격리: 임시 리포(bare origin + 체크아웃)·가짜 명부·tmux·mbox — 네트워크 0 · 실 루트 0 · 실 좌석 깨우기 0 · 자기 재호출 0(가드 RSG_ACTIVE 가 막는다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-t0))초"; t0=$SECONDS; }
run_py() {  # $1=bin $2=시험 파일 [$3=-k]
  (ulimit -u 2000; cd "$SC" && R1330_BIN="$1" R1330_BASE_BIN="${BASE:-}" timeout 70 python3.11 -m pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1)
}

# ① 신판 green
run_py "$KIT" test_stall_waiting_cards_ref_tree_r1330.py; ck "S1~S6 $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?; lap green

# ② 기준판(팩 origin/main) — S1~S5 FAIL · S6 PASS
mkdir -p "$T/base"; git -C "$PACK" archive origin/main feature-pack/fable-team/harness/kit/fable-team/bin | tar -x -C "$T/base"
BASE="$T/base/feature-pack/fable-team/harness/kit/fable-team/bin"
for k in s1 s2 s3 s4 s5; do run_py "$BASE" test_stall_waiting_cards_ref_tree_r1330.py "test_$k"; [ $? -ne 0 ]; ck "기준판 $k FAIL" $?; done
run_py "$BASE" test_stall_waiting_cards_ref_tree_r1330.py test_s6; ck "기준판 s6 PASS(회귀 대조)" $?; lap 기준판
run_py "$KIT" test_stall_waiting_cards_ref_tree_r1330.py test_s6; ck "신판 s6 = 기준판과 출력 바이트 같음" $?

# ③ 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 -I - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" test_stall_waiting_cards_ref_tree_r1330.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "W1 대기 목록을 디스크 glob 으로" ft_stall_detect.py 'verdicts = _ref_verdicts(cards, lint, root)' 'verdicts = None' "s1 or s2"
mutate "W2 선행 대조 stems 를 디스크로" ft_stall_detect.py 'card_ready(f, cards, lint, stems, bodies[n])' 'card_ready(f, cards, lint, None, bodies[n])' s3
mutate "W3 git 상한을 조용히 0장으로" ft_stall_scan.py 'notes.append(f"a? {t['"'"'team'"'"']} 대기 카드 판정 불가 — {e}")' 'pass' s4
mutate "W4 ref 를 origin/main 고정" ft_stall_detect.py 'ref = basis_ref(root) if root else "origin/main"' 'ref = "origin/main"' s5
sha_after="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?; lap 변이

# ④ 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 100644
for n in ft_stall_detect.py ft_stall_scan.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
for f in "$HERE/test_stall_waiting_cards_ref_tree_r1330.sh" "$SC/test_stall_waiting_cards_ref_tree_r1330.py"; do
  [ "$(stat -f %Lp "$f")" = 644 ]; ck "새 시험 모드 644 $(basename "$f")" $?
done

# ⑤ 회귀 — 기존 stall 시험(신판 rc 가 모두 0 이어야 한다 · 기준판도 같은 시험이 rc0)
if [ "${STEPS:-1}" != 0 ]; then
  for t in test_ft_stall_scan.py test_ft_stall_scan_off_roster.py test_ft_stall_scan_wake_r638.py test_ft_stall_news_cell.py test_stall_heartbeat_promoted_r1154.py test_stall_lead_alert_cron_r1152.py test_stall_scan_headline_age.py test_stall_scan_headline_seats_r1290.py test_stall_scan_heartbeat_desk_r1143.py test_stall_scan_lead_heartbeat_r1001.py test_stall_scan_skip_paused_r1307.py; do
    run_py "$KIT" "$t"; ck "회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
  done
  lap 회귀
fi
echo "FAIL=$fail"; [ "$fail" = 0 ]
