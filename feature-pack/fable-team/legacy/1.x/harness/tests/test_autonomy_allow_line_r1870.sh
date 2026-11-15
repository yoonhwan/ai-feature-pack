#!/usr/bin/env bash
# test_autonomy_allow_line_r1870.sh — r1870: `ft-autonomy.sh allow-line` = 자율 ON + 활성 범위 + DA ALLOW-RECORD 1줄 → 원장 1행 + 허용 장부·기준선 1줄
# ① 정상 allow → 원장 1행 + 허용 1줄 rc0 (기준판 = 동사 없음 → Red) ② 다시 → ALREADY 쓰기 0 ③ 자율 OFF → REJECT ④ 범위 끝남 → REJECT
# ⑤ 줄에 "claude" → REJECT ⑥ tmux 아님 → REJECT ⑦ DA seq 없음·from nano·레코드 없음 → REJECT ⑧ 쓴 뒤 mode/status 위변조 아님
# ⑨ 쓴 뒤 판정기 ALLOW · 다른 파일 ["claude"] REJECT ⑩ baseline 추가 → 판정기 G3 통과 ⑪ 동적 지점 아닌 줄 → REJECT
# ⑫ 같은 키·sha16 다른 결합 + old 없음 → REJECT ⑬ 산문 HOLD 만 → REJECT ⑭ 뒤에 REVOKE → REJECT ⑮ allow 줄 바뀜 → REJECT
# ⑯ baseline 결합 sha 바뀜(옛 comb 레코드) → REJECT ⑰ 교체 정상(old·comb) → 원장 old·new · 그 행만 바뀜 · G3 통과 ⑱ bin·kit cmp0
# 임시 루트·가짜 mailbox.log 만 · 실 장부·우편 0 · 외부 호출 0 · sleep 0 · 변이 = R1870_BIN=<변이 bin 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1870_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; OUT=""; RC=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$RC out=${OUT:0:300}"; fail=$((fail+1)); fi; }
R="$T/root"; S="$R/.fable-team/state"; MB="$R/.fable-team/comm/mailbox.log.jsonl"; F="$T/ft2"; LOG="$S/autonomy.log"
AT="$S/launchd-llm-allow.tsv"; BT="$S/launchd-dyncall-baseline.tsv"; DA='byz-harness-da-codex#11'
export FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$S" FT_NOW=2000 FT_AUTONOMY_LEVEL=each
LINE='    "tmux": ["tmux", "new-session", "-d", "-s", "h"] + ["pi"]}'
lc() { echo $(( $(wc -l < "$1") )); }
h16() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].strip().encode()).hexdigest()[:16])' "$1"; }
H="$(h16 "$LINE")"
fresh() {  # [until] — 자율 ON A1 + 범위 S1 + 빈 우편 + 코드 폴더(launch_plan.py:2 = LINE)
  rm -rf "$R" "$F"; mkdir -p "$S" "${MB%/*}" "$F"
  printf '1000\ton\tA1\napprove-scope S1 A1 1000 until=%s max=5 daily=5 classes=docs\n' "${1:-9000}" > "$LOG"
  printf '{"mode":"on","since":1000,"event":"A1","until":null}\n' > "$S/autonomy.json"; : > "$MB"
  printf 'x = {\n%s\n' "$LINE" > "$F/launch_plan.py"
}
mail() {  # <seq> <from> <body>
  python3 -c 'import json,sys; print(json.dumps({"seq": int(sys.argv[1]), "ts": "t", "to": "x", "from": sys.argv[2], "body": sys.argv[3]}, ensure_ascii=False))' "$@" >> "$MB"
}
rec() { printf 'ALLOW-RECORD verdict=%s kind=%s label=ft2-current path=%s line=%s card=c1870 sha16=%s%s' "${6:-APPROVE}" "$1" "$2" "$3" "$4" "${5:+ $5}"; }
run() { OUT="$(bash "$BIN/ft-autonomy.sh" allow-line "$@" 2>&1)"; RC=$?; }
AL() { run ft2-current launch_plan.py 2 --kind allow --root-dir "$F" --da "${1:-10}" --card c1870; }
BL() { run ft2-current x.py "${2:-3}" --kind baseline --root-dir "$F" --da "${1:-20}" --card c1870; }
gate() { OUT="$(python3 "$BIN/ft_launchd_llm_gate.py" check --root-dir "$F" --root-key ft2-current --allow "$AT" --baseline "$BT" 2>&1)"; RC=$?; }
nolog() { [ "$(lc "$LOG")" = 2 ] && [ ! -s "$AT" ] && [ ! -s "$BT" ]; }
rej() { [ "$RC" = 2 ] && grep -q '^REJECT allow-line ' <<<"$OUT" && nolog; }

fresh; mail 10 "$DA" "판정 APPROVE
$(rec allow launch_plan.py 2 "$H")"; AL
[ "$RC" = 0 ] && [ "$(tail -1 "$LOG")" = "allow-line allow ft2-current launch_plan.py $H A1 S1 da=10 2000" ] \
  && [ "$(cat "$AT")" = "$(printf 'ft2-current\tft2-current/launch_plan.py\t%s\t2000.0' "$H")" ]; ck "① 정상 allow → 원장 1행 + 허용 1줄" $?
AL; [ "$RC" = 0 ] && grep -q '^ALREADY' <<<"$OUT" && [ "$(lc "$LOG")" = 3 ] && [ "$(lc "$AT")" = 1 ]; ck "② 같은 호출 → ALREADY 쓰기 0" $?
[ "$(bash "$BIN/ft-autonomy.sh" mode)" = on ] && ! bash "$BIN/ft-autonomy.sh" status 2>&1 | grep -q '위변조'; ck "⑧ 쓴 뒤 mode on · status 위변조 아님" $?
gate; [ "$RC" = 0 ] && grep -q '^ALLOW ft2-current' <<<"$OUT"; ck "⑨ⓐ 판정기 그 줄 ALLOW" $?
printf 'import subprocess\nsubprocess.run(["claude"])\n' > "$F/y.py"; gate
[ "$RC" = 1 ] && grep -q 'ft2-current/y.py:2' <<<"$OUT"; ck "⑨ⓑ 다른 파일 [\"claude\"] → REJECT" $?

fresh; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$H")"; printf '1500\toff\tA1\n' >> "$LOG"
printf '{"mode":"off","since":1500,"event":"A1","until":null}\n' > "$S/autonomy.json"; AL
[ "$RC" = 2 ] && grep -q '^REJECT allow-line ' <<<"$OUT" && [ ! -e "$AT" ] && [ "$(lc "$LOG")" = 3 ]; ck "③ 자율 OFF → REJECT 쓰기 0" $?
fresh 1500; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$H")"; AL; rej; ck "④ 범위 끝남 → REJECT" $?
L5='    "tmux": ["tmux", "new-session", "-d"] + ["pi", "claude"]}'
fresh; printf 'x = {\n%s\n' "$L5" > "$F/launch_plan.py"; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$(h16 "$L5")")"; AL; rej; ck "⑤ 줄에 claude → REJECT" $?
L6='subprocess.run(["pi"])'
fresh; printf 'import subprocess\n%s\n' "$L6" > "$F/launch_plan.py"; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$(h16 "$L6")")"; AL; rej; ck "⑥ tmux 아님 → REJECT" $?
fresh; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$H")"; AL 99; rej; ck "⑦ⓐ DA seq 없음 → REJECT" $?
fresh; mail 10 'byz-harness-nano-x#0' "$(rec allow launch_plan.py 2 "$H")"; AL; rej; ck "⑦ⓑ from nano → REJECT" $?
fresh; mail 10 "$DA" "APPROVE launch_plan.py:2 c1870 sha16=$H"; AL; rej; ck "⑦ⓒ 레코드 없음(경로:줄 산문) → REJECT" $?
fresh; mail 10 "$DA" "$(rec allow launch_plan.py 3 "$H")"; AL; rej; ck "⑦ⓓ 레코드 경로:줄 다름(line=3) → REJECT" $?
fresh; mail 10 "$DA" "HOLD. 이전 APPROVE는 철회 … launch_plan.py:2 c1870"; AL; rej; ck "⑬ 산문 HOLD 만(레코드 0) → REJECT" $?
fresh; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$H")"; mail 11 "$DA" "$(rec allow launch_plan.py 2 "$H" "" REVOKE)"; AL; rej; ck "⑭ 뒤 REVOKE 레코드 → REJECT" $?
fresh; mail 10 "$DA" "$(rec allow launch_plan.py 2 "$H")"; printf 'x = {\n%s\n' '    "tmux": ["tmux", "new-session", "-x"] + ["pi"]}' > "$F/launch_plan.py"; AL; rej; ck "⑮ DA 뒤 줄 바뀜(sha16) → REJECT" $?

# ===== baseline =====
bfresh() { fresh; printf 'import subprocess\nargv = %s\nsubprocess.run(argv)\n' "${1:-[\"git\", \"status\"]}" > "$F/x.py"; }
dyn() { python3 "$BIN/ft_launchd_llm_gate.py" list-dyncalls --root-dir "$F" --root-key ft2-current | grep -F "ft2-current/x.py:3 "; }
bfresh; D="$(dyn)"; BH="$(cut -f2 <<<"$D")"; C1="$(cut -f3 <<<"$D")"
mail 20 "$DA" "$(rec baseline x.py 3 "$BH" "comb=$C1")"; BL
[ "$RC" = 0 ] && [ "$(tail -1 "$LOG")" = "allow-line baseline ft2-current x.py $BH A1 S1 da=20 2000" ] \
  && [ "$(cut -f1-3 "$BT")" = "$(printf 'ft2-current/x.py\t%s\t%s' "$BH" "$C1")" ] && grep -q $'\tauto A1 S1 · DA #20 · c1870 · 2000$' "$BT"; ck "⑩ⓐ baseline 1줄(list-dyncalls 값 그대로)" $?
rm -f "$F/launch_plan.py"; gate; [ "$RC" = 0 ]; ck "⑩ⓑ 판정기 G3 통과" $?
[ "$(bash "$BIN/ft-autonomy.sh" mode)" = on ]; ck "⑩ⓒ baseline 원장 줄 위변조 아님" $?
bfresh; mail 20 "$DA" "$(rec baseline x.py 2 "$(h16 'argv = ["git", "status"]')" "comb=$C1")"; BL 20 2; rej; ck "⑪ 동적 지점 아닌 줄 → REJECT" $?
Z="$(printf '0%.0s' $(seq 64))"
bfresh; printf 'ft2-current/x.py\t%s\t%s\tsomeone\n' "$BH" "$Z" > "$BT"; cp "$BT" "$T/bt0"; mail 20 "$DA" "$(rec baseline x.py 3 "$BH" "comb=$C1")"; BL
[ "$RC" = 2 ] && cmp -s "$BT" "$T/bt0" && [ "$(lc "$LOG")" = 2 ]; ck "⑫ 같은 키·sha16 다른 결합 + old 없음 → REJECT 쓰기 0" $?
bfresh '["pi"]'; mail 20 "$DA" "$(rec baseline x.py 3 "$BH" "comb=$C1")"; BL; rej; ck "⑯ 결합 sha 바뀜 + 옛 comb 레코드 → REJECT" $?
bfresh '["git", "log"]'; C2="$(dyn | cut -f3)"
printf 'other/y.sh\t%s\t%s\tkeep\nft2-current/x.py\t%s\t%s\told\nz/z.py\t%s\t%s\tkeep2\n' "$BH" "$Z" "$BH" "$C1" "$BH" "$Z" > "$BT"
mail 21 "$DA" "$(rec baseline x.py 3 "$BH" "comb=$C2 old=$C1")"; BL 21
[ "$RC" = 0 ] && [ "$(tail -1 "$LOG")" = "allow-line baseline-replace ft2-current/x.py $BH old=$C1 new=$C2 A1 S1 da=21 2000" ] \
  && [ "$(sed -n 1p "$BT")$(sed -n 3p "$BT")" = "$(printf 'other/y.sh\t%s\t%s\tkeepz/z.py\t%s\t%s\tkeep2' "$BH" "$Z" "$BH" "$Z")" ] \
  && [ "$(sed -n 2p "$BT" | cut -f1-3)" = "$(printf 'ft2-current/x.py\t%s\t%s' "$BH" "$C2")" ] && [ "$(lc "$BT")" = 3 ]; ck "⑰ⓐ 교체 정상 → 원장 old·new · 그 행만" $?
rm -f "$F/launch_plan.py"; gate; [ "$RC" = 0 ]; ck "⑰ⓑ 교체 뒤 판정기 G3 통과" $?
BL 21; [ "$RC" = 0 ] && grep -q '^ALREADY' <<<"$OUT"; ck "⑰ⓒ 교체 뒤 같은 호출 → ALREADY" $?

[ -z "${R1870_BIN:-}" ] && { cmp -s "$BIN/ft-autonomy.sh" "$KIT/ft-autonomy.sh" && cmp -s "$BIN/ft-autonomy-allow-line.sh" "$KIT/ft-autonomy-allow-line.sh"; ck "⑱ bin·kit 사본 cmp0" $?; }
echo "fail=$fail"
[ "$fail" -eq 0 ]
