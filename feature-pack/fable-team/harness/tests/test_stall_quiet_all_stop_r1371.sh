#!/usr/bin/env bash
# test_stall_quiet_all_stop_r1371.sh — r1371 전팀 정지 표식(ALL_STOP.json)이 켜져 있으면 감시기가 경보를 쌓지 않는다.
#   본문 = tests/scripts/test_stall_quiet_all_stop_r1371.py (S1~S7 · 판정 = ft_stall_detect.all_stop 한 곳)
#   S8 = ft-mbox.sh watch_alarm (표식 on → [긴급 · planner watch 없음] 0통 + «보류 watch … — 전팀 정지(since HH:MM)» · off 다음 send → 긴급 1통)
#   변이 4종(사본 bin 치환 → 그 시험 FAIL → 복구) + 회귀 3종 + 짝 사본 cmp0 · 새 시험 모드 100644
#   격리: 합성 jsonl · 가짜 명부·tmux·mbox·pgrep(임시 폴더 · FT_ROOT 임시 루트) — 실 좌석·실 우편함·실 tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"; SK="$HERE/../../skill/scripts"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
eq() { [ "$2" = "$3" ] && ck "$1" 0 || { ck "$1 (기대 '$3' 실제 '$2')" 1; }; }
has() { grep -qF -- "$2" "$3" && ck "$1" 0 || ck "$1 (없음 «$2» · $(tr '\n' ' ' < "$3" 2>/dev/null | cut -c1-240))" 1; }
run_py() { (cd "$SC" && R1371_BIN="$1" pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1); }

# ── R1 — python 본문 S1~S7 ────────────────────────────────────────────────────────────
run_py "$KIT" test_stall_quiet_all_stop_r1371.py; ck "S1~S7 $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?

# ── S8 — ft-mbox.sh watch_alarm: 표식 on = 긴급 0 · 보류 1줄 · off = 긴급 1 ──────────────────
R="$T/s8"; C="$R/.fable-team/comm"; ST="$R/.fable-team/state"; mkdir -p "$C" "$ST" "$T/fakebin"
P='byz-planner-master-claude#72'; H='byz-harness-master-claude#9'
printf '{}\n' > "$R/.fable-team/seats.json"
printf '{"_master":"%s"}\n' "$P" > "$R/.fable-team/seats-planner.json"
printf '{"_master":"%s"}\n' "$H" > "$R/.fable-team/seats-harness.json"
printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/bin/sh\nexit 0\n' > "$T/fake-pgrep"; chmod +x "$T/fake-pgrep"          # 감시 프로세스 0
SF="$ST/planner-watch-absent-since.$P"; MK="$ST/planner-watch-missing.$P"
sf() { local n; n="$(date +%s)"; printf '%s\t%s\n' "$((n - 60))" "$((n - 600))" > "$SF"; }   # 표본 신선 · 처음 없음 10분 전 = 유예 밖
env8() { env PATH="$T/fakebin:$PATH" FT_ROOT="$R" FT_MBOX_DIR="$C" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_PGREP="$T/fake-pgrep" FT_BIN="$KIT" "$@"; }
snd8() { env8 bash "$KIT/ft-mbox.sh" send "$P" "t1#1" "[결정] r1371 S8 $1" >"$T/s8.out" 2>"$T/s8.err"; }
alarms8() { python3 - "$C/mailbox.jsonl" "$H" <<'PY'
import json, sys
try:
    f = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
for line in f:
    if not line.strip():
        continue
    row = json.loads(line)
    if row.get("to") == sys.argv[2] and row.get("from") == "ft-watch-alarm":
        print(str(row.get("body", "")).replace("\n", " "))
PY
}
ano8() { local n; n="$(alarms8 | grep -c 'planner watch 없음' || true)"; printf '%s' "${n:-0}"; }
SINCE="$(( $(date +%s) - 3600 ))"; HM8="$(date -r "$SINCE" +%H:%M 2>/dev/null || date -d "@$SINCE" +%H:%M)"
sf; printf '{"since": %s, "by": "x", "reason": "r1371 시험", "notify_failed": []}\n' "$SINCE" > "$ST/ALL_STOP.json"
snd8 on
eq "S8 표식 on → [긴급 · planner watch 없음] 0통" "$(ano8)" 0
has "S8 표식 on → stderr «보류 watch … — 전팀 정지(since $HM8)»" "보류 watch $P — 전팀 정지(since $HM8)" "$T/s8.err"
[ ! -e "$MK" ] && ck "S8 표식 on → 10분 막이 표식 0(재개 뒤 바로 1통)" 0 || ck "S8 표식 on 인데 표식 생성됨" 1
printf 'not json\n' > "$ST/ALL_STOP.json"      # 깨짐 = 판정 불가 → 경보 그대로
snd8 broken
eq "S8 깨진 표식 → 긴급 1통(경보 그대로)" "$(ano8)" 1
has "S8 깨진 표식 → stderr «판정 불가 ALL_STOP»" "판정 불가 ALL_STOP " "$T/s8.err"
rm -f "$MK"; sf; rm -f "$ST/ALL_STOP.json"     # 사람이 재개(ft-all-stop.sh off)
snd8 off
eq "S8 off 다음 send → 긴급 1통" "$(ano8)" 2
has "S8 off 다음 send → «planner watch 없음» 본문" "planner watch 없음" <(alarms8 | tail -1)

# ── ⓕ 회귀 — 기존 stall 판정·헤드라인 시험은 기대 변경 0 ─────────────────────────────────
for t in test_ft_stall_scan.py test_stall_scan_skip_paused_r1307.py test_stall_scan_headline_age.py; do
  run_py "$KIT" "$t"; ck "ⓕ 회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
done

# ── 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만) ────
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" "$KIT/ft_stall_headline.py" "$KIT/ft_stall_detect.py" | awk '{print $1}' | tr '\n' ' ')"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" test_stall_quiet_all_stop_r1371.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "표식 보류 끔(f·a)" ft_stall_scan.py '            if astop == "on":' '            if False:' s1
mutate "h 보류 끔" ft_stall_headline.py '        if mark == "on":  # r1371' '        if False:  # r1371' s2
mutate "깨진 표식을 on 으로" ft_stall_detect.py '        return "unknown", None, type(error).__name__' '        return "on", 0.0, ""' s5
mutate "c 까지 보류" ft_stall_scan.py 'or f.get("all_stop") or self.now' 'or self.astop[0] == "on" or self.now' s4
sha_after="$(shasum "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" "$KIT/ft_stall_headline.py" "$KIT/ft_stall_detect.py" | awk '{print $1}' | tr '\n' ' ')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?

# ── 짝 사본(bin ↔ kit · kit ↔ skill/scripts) 바이트 동일 · 새 시험 모드 100644 ────────────────
for n in ft_stall_scan.py ft_stall_headline.py ft_stall_detect.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
cmp -s "$KIT/ft-mbox.sh" "$SK/ft-mbox.sh"; ck "짝 사본 ft-mbox.sh(kit ↔ skill/scripts)" $?
grep -q 'all_stop(self.root)' "$KIT/ft_stall_scan.py"; ck "판정 = ft_stall_detect.all_stop 한 곳" $?
grep -q 'from ft_stall_detect import all_stop, all_stop_note' "$KIT/ft_stall_headline.py"; ck "h 도 같은 표식(같은 함수)" $?
grep -q '_all_stop_mark' "$KIT/ft-mbox.sh"; ck "w watch_alarm 도 같은 표식" $?
[ "$(stat -f %Lp "$HERE/test_stall_quiet_all_stop_r1371.sh")" = 644 ]; ck "새 셸 시험 모드 644" $?
[ "$(stat -f %Lp "$SC/test_stall_quiet_all_stop_r1371.py")" = 644 ]; ck "새 python 시험 모드 644" $?
echo "ft_stall_scan.py $(wc -l <"$KIT/ft_stall_scan.py")줄 · ft_stall_headline.py $(wc -l <"$KIT/ft_stall_headline.py")줄 · ft_stall_detect.py $(wc -l <"$KIT/ft_stall_detect.py")줄"
echo "FAIL=$fail"; [ "$fail" = 0 ]
