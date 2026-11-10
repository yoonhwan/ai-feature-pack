#!/usr/bin/env bash
# test_inbox_haiku_retire_r1560.sh — 쪽지 분류기 haiku 호출 퇴역(r1560) 시험.
#   ⓐ 미상 ingest = Popen 0 · cls 미상 · prio 1.5 · 스텁·가짜 claude 호출 0 · hook-errors 0줄
#   ⓑ 규칙표 ①~⑥ = 지금과 같은 cls·via
#   ⓒ show 그대로 · show --compact = 인자 오류 rc≠0 1줄 · 큐 무변경 · 호출 0
#   ⓓ classify 하위 명령 = 알 수 없는 명령 rc≠0 1줄
#   ⓔ 옛 큐 줄(via=haiku · 라벨 있음) = 읽기·닫기 그대로(via 키 보존)
#   ⓕ FT_INBOX_HAIKU 값을 바꿔도 동작 같음(호출 0)
#   ⓖ 코드에 haiku·claude 실행 문자열 0(퇴역 주석 1줄 제외) · bin·kit 같은 blob
#   변이 M1 = ingest 미상 Popen 되살림 → ⓐ FAIL 조건(자식 생김) · M2 = show 에 claude 호출 되살림 → ⓒ·ⓖ FAIL 조건
# 격리만: mktemp FT_ROOT · 가짜 claude(불리면 파일에 적음) · 실 claude 0 · 라이브 .fable-team 쓰기 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/.."   # feature-pack/fable-team/harness
BIN="$H/bin"; KIT="$H/kit/fable-team/bin"; INBOX="$BIN/ft-inbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/comm/bodies" "$T/fakebin"
MB="$FT_ROOT/.fable-team/comm/mailbox.jsonl"; Q="$FT_ROOT/.fable-team/state/inbox"
ERRLOG="$FT_ROOT/.fable-team/state/hook-errors.log"
fail=0; s_a=$SECONDS; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
# 가짜 실행기 — «불리면 파일에 적는다». 그 파일이 없음이 «호출 0» 의 증거다.
printf '#!/bin/sh\necho called >> "%s/claude-called"\nexit 1\n' "$T" > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"
printf '#!/bin/sh\necho called >> "%s/haiku-called"\ncat >/dev/null\nexit 1\n' "$T" > "$T/haiku-stub.sh"; chmod +x "$T/haiku-stub.sh"
export PATH="$T/fakebin:$PATH" FT_INBOX_HAIKU="$T/haiku-stub.sh"
M=master-x; ME="$M#9"; export FT_SEAT="$ME"
add_mail() { python3 - "$MB" "$@" <<'PY'
import json, sys
p, seq, to, frm, body = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
open(p, "a", encoding="utf-8").write(json.dumps({"seq": seq, "ts": "2026-11-10T15:00:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
PY
}
field() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    x=json.loads(l)
    if x["seq"]==int(sys.argv[2]): print(x[sys.argv[3]])' "$@"; }
ing() { add_mail "$1" "$ME" a#1 "$2"; bash "$INBOX" ingest "$1" >/dev/null 2>&1; }
# Popen 감시 아래 ingest — «분류기 자식 0» 을 직접 본다(스텁 파일은 비동기 자식을 못 잡는다)
ingest_spy() {  # <ft-inbox.py> <seq> <spawn 기록 파일>
  python3 - "$1" "$2" "$3" <<'PY'
import runpy, subprocess, sys
path, seq, log = sys.argv[1], sys.argv[2], sys.argv[3]
def spy(*a, **k):
    open(log, "a", encoding="utf-8").write(repr(a) + "\n")
    raise RuntimeError("Popen 금지(퇴역 r1560)")
subprocess.Popen = spy
sys.argv = ["ft-inbox.py", "ingest", seq]
try:
    runpy.run_path(path, run_name="__main__")
except SystemExit:
    pass
PY
}
none_if() { [ -f "$1" ] && echo present || echo none; }
code_hits() { grep -n -i -E 'haiku|claude' "$1" | grep -v '퇴역' || true; }

# ⓐ 미상 ingest = 스폰 0
SP="$T/spawn-a.log"; add_mail 101 "$ME" a#1 "[a#1->$ME] 이상한 문장 가나다"
ingest_spy "$BIN/ft-inbox.py" 101 "$SP" >/dev/null 2>&1
eq "ⓐ 미상 ingest → Popen 0" "$(none_if "$SP")" "none"
eq "ⓐ cls=미상" "$(field "$Q/$M.jsonl" 101 cls)" "미상"
eq "ⓐ prio 1.5" "$(field "$Q/$M.jsonl" 101 prio)" "1.5"
eq "ⓐ 가짜 claude 호출 0" "$(none_if "$T/claude-called")" "none"
eq "ⓐ FT_INBOX_HAIKU 스텁 호출 0" "$(none_if "$T/haiku-called")" "none"
eq "ⓐ hook-errors.log 0줄(분류 자식 0)" "$(none_if "$ERRLOG")" "none"
eq "ⓐ 큐 줄은 미상 그대로(라벨 갱신 0)" "$(field "$Q/$M.jsonl" 101 cls)" "미상"

# ⓑ 규칙표 ①~⑥ = 그대로
ing 102 "[a#1->$ME] 오빠 원문: 확인"
ing 103 "[a#1->$ME] [HIL] 행#3"
ing 104 "[a#1->$ME] [BLOCK] 막힘"
ing 105 "[a#1->$ME] 판정 430 집행 완료"
ing 106 "[a#1->$ME] 참고: 접수"
ing 107 "[a#1->$ME] [완료·휴식] 골 끝"
for pair in 102:① 103:② 104:④ 105:⑤ 106:⑥ 107:⑤; do
  eq "ⓑ 규칙표 ${pair%%:*} cls=${pair##*:}" "$(field "$Q/$M.jsonl" "${pair%%:*}" cls)" "${pair##*:}"
  eq "ⓑ 규칙표 ${pair%%:*} via=rule" "$(field "$Q/$M.jsonl" "${pair%%:*}" via)" "rule"
done
eq "ⓑ 규칙표 경로에서도 스텁 호출 0" "$(none_if "$T/haiku-called")" "none"
s_b=$SECONDS

# ⓒ show 그대로 · show --compact = 오류
SH="$(bash "$INBOX" show "$ME" 2>&1)"; SHRC=$?
eq "ⓒ show rc 0" "$SHRC" "0"
echo "$SH" | grep -q "seq=102" && ok "ⓒ show 에 규칙표 줄이 보임" || bad "ⓒ show 에 seq=102 없음"
H_Q="$(md5 -q "$Q/$M.jsonl")"
OC="$(bash "$INBOX" show "$ME" --compact 2>&1)"; ORC=$?
[ "$ORC" -ne 0 ] && ok "ⓒ show --compact → rc≠0($ORC)" || bad "ⓒ show --compact 인데 rc 0"
eq "ⓒ show --compact 오류 1줄" "$(printf '%s\n' "$OC" | wc -l | tr -d ' ')" "1"
printf '%s\n' "$OC" | grep -q '퇴역' && ok "ⓒ 오류 문구가 퇴역을 말함" || bad "ⓒ 오류 문구: $OC"
eq "ⓒ show --compact 큐 무변경" "$(md5 -q "$Q/$M.jsonl")" "$H_Q"
eq "ⓒ show --compact 스텁·claude 호출 0" "$(none_if "$T/haiku-called")$(none_if "$T/claude-called")" "nonenone"

# ⓓ classify 하위 명령 = 알 수 없는 명령
DC="$(bash "$INBOX" classify 101 "$ME" 2>&1)"; DRC=$?
[ "$DRC" -ne 0 ] && ok "ⓓ classify → rc≠0($DRC)" || bad "ⓓ classify 가 아직 동작"
eq "ⓓ classify 오류 1줄" "$(printf '%s\n' "$DC" | wc -l | tr -d ' ')" "1"
printf '%s\n' "$DC" | grep -q 'usage: ft-inbox.sh' && ok "ⓓ classify 는 usage 1줄" || bad "ⓓ classify 문구: $DC"
s_c=$SECONDS

# ⓔ 옛 큐 줄(via=haiku · 라벨 있음) = 읽기·닫기 그대로
python3 - "$Q/$M.jsonl" "$FT_ROOT/.fable-team/comm/bodies/901.txt" <<'PY'
import json, sys
q, bp = sys.argv[1], sys.argv[2]
open(bp, "w", encoding="utf-8").write("[old#1->master-x#9] 판정 요청: 옛 줄\n")
row = {"seq": 901, "ts": "2026-11-10T14:00:00", "from": "old#1", "cls": "③", "prio": 3,
       "group": "old-g-901", "body_path": bp, "mark": None, "reported": False, "via": "haiku"}
open(q, "a", encoding="utf-8").write(json.dumps(row, ensure_ascii=False) + "\n")
PY
bash "$INBOX" show "$ME" | grep -q "seq=901" && ok "ⓔ 옛 줄 show 에 보임" || bad "ⓔ 옛 줄 누락"
eq "ⓔ 옛 줄 via 키 보존" "$(field "$Q/$M.jsonl" 901 via)" "haiku"
bash "$INBOX" mark 901 처리 "옛 줄 처리" >/dev/null && ok "ⓔ 옛 줄 mark rc 0" || bad "ⓔ 옛 줄 mark 실패"
bash "$INBOX" report 901 >/dev/null && ok "ⓔ 옛 줄 report rc 0" || bad "ⓔ 옛 줄 report 실패"
bash "$INBOX" show "$ME" | grep -q "seq=901" && bad "ⓔ 옛 줄이 report 뒤에도 남음" || ok "ⓔ 옛 줄 report 로 닫힘"
eq "ⓔ 옛 줄 via 키는 그대로(고쳐 쓰기 0)" "$(field "$Q/$M.jsonl" 901 via)" "haiku"

# ⓕ FT_INBOX_HAIKU 값을 바꿔도 같다
add_mail 902 "$ME" a#1 "[a#1->$ME] 환경값 무관 문장"
FT_INBOX_HAIKU="false" bash "$INBOX" ingest 902 >/dev/null 2>&1
eq "ⓕ FT_INBOX_HAIKU=false → cls 미상" "$(field "$Q/$M.jsonl" 902 cls)" "미상"
add_mail 903 "$ME" a#1 "[a#1->$ME] 환경값 무관 문장 둘"
ingest_spy "$BIN/ft-inbox.py" 903 "$T/spawn-f.log" >/dev/null 2>&1
eq "ⓕ 다른 env 에서도 Popen 0" "$(none_if "$T/spawn-f.log")" "none"
eq "ⓕ 다른 env 에서도 스텁 호출 0" "$(none_if "$T/haiku-called")" "none"

# ⓖ 코드 검사 — 실행 문자열 0 · bin·kit 같은 blob
for f in ft_inbox_core.py ft-inbox.py; do
  eq "ⓖ $f 코드에 haiku·claude 문자열 0(퇴역 주석 제외)" "$(code_hits "$BIN/$f" | wc -l | tr -d ' ')" "0"
  eq "ⓖ $f bin·kit 같은 blob" "$(md5 -q "$BIN/$f")" "$(md5 -q "$KIT/$f")"
done
eq "ⓖ r1343 시험(haiku 전용) 삭제됨" "$([ -f "$HERE/test_inbox_haiku_cwd_r1343.sh" ] && echo 있음 || echo 없음)" "없음"
s_d=$SECONDS

# 변이 M1 — ingest 의 미상 Popen 되살림 → ⓐ FAIL 조건(자식 생김)
M1="$T/m1"; mkdir -p "$M1"; cp "$BIN/ft_inbox_core.py" "$BIN/ft_inbox_rotate.py" "$BIN/ft_inbox_window.py" "$M1/"; cp "$BIN/ft-inbox.py" "$M1/"
python3 - "$M1/ft-inbox.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
marker = '    print(f"INGEST seq={seq}'
inject = ('    if cls == "미상":\n        subprocess.Popen([sys.executable, __file__, "classify", str(seq)], start_new_session=True)\n')
assert marker in s, "M1 주입 지점 없음"
s = s.replace("import glob\n", "import glob\nimport subprocess\n", 1).replace(marker, inject + marker, 1)
open(p, "w", encoding="utf-8").write(s)
PY
add_mail 911 "$ME" a#1 "[a#1->$ME] 변이 문장 마바사"
ingest_spy "$M1/ft-inbox.py" 911 "$T/spawn-m1.log" >/dev/null 2>&1
eq "변이 M1 검출 — Popen 되살리면 ⓐ(Popen 0) FAIL" "$(none_if "$T/spawn-m1.log")" "present"

# 변이 M2 — show 의 --compact 자리에 claude 호출 되살림 → ⓒ·ⓖ FAIL 조건
M2="$T/m2"; mkdir -p "$M2"; cp "$BIN/ft_inbox_core.py" "$BIN/ft_inbox_rotate.py" "$BIN/ft_inbox_window.py" "$M2/"; cp "$BIN/ft-inbox.py" "$M2/"
python3 - "$M2/ft-inbox.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
marker = '    if flag == ["--count"]:'
inject = ('    if flag == ["--compact"]:\n        print(subprocess.run(["claude", "-p", "압축"], capture_output=True, text=True).stdout)\n')
assert marker in s, "M2 주입 지점 없음"
s = s.replace("import glob\n", "import glob\nimport subprocess\n", 1).replace(marker, inject + marker, 1)
open(p, "w", encoding="utf-8").write(s)
PY
rm -f "$T/claude-called"
python3 "$M2/ft-inbox.py" show "$ME" --compact >/dev/null 2>&1
eq "변이 M2 검출 — claude 호출 되살리면 ⓒ(호출 0) FAIL" "$(none_if "$T/claude-called")" "present"
eq "변이 M2 는 ⓖ(문자열 0) 에도 걸림" "$([ -n "$(code_hits "$M2/ft-inbox.py")" ] && echo 걸림 || echo 안걸림)" "걸림"

echo "단계 초: ⓐ-ⓑ=$((s_b - s_a))s ⓒ-ⓓ=$((s_c - s_b))s ⓔ-ⓖ=$((s_d - s_c))s 변이=$((SECONDS - s_d))s"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
