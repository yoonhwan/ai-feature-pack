#!/usr/bin/env bash
# test_head_lag_remind_per_wt_r836.sh — R836: [베이스 뒤처짐] 재발송 막기 기록 키 = 워크트리 하나(main sha 무관)
# 임시 origin+clone+워크트리 · 시험용 tmux 서버(-L) · 가짜 명부·mbox · 시각 고정(FT_HEAD_LAG_NOW) — 실 저장소·실 tmux·실 mbox 0
# R836_PY=<다른 ft_head_lag.py> 로 변이본을 같은 시험에 돌린다(옆에 ft_head_lag_seats.py · ft-head-skip.txt 필요).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; PY="${R836_PY:-$BIN/ft_head_lag.py}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; SOCK="r836$$"
TM() { tmux -L "$SOCK" "$@"; }
cleanup() { TM kill-server 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
mkrepo "$T"; mkdir -p "$T/.fable-team/state"
SF="$T/.fable-team/state/head-lag.json"
export FT_ROOT="$T" FT_HEAD_LAG_TMUX_ARGS="-L $SOCK" FT_HEAD_LAG_MBOX="$T/mbox" MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
cat > "$T/mbox" <<'EOF'
#!/bin/bash
n=$(( $(wc -l < "$MBOX_LOG") + 1 )); printf '%s\t%s\t%s\n' "$2" "$3" "$(printf '%s' "$4" | tr '\n' '~')" >> "$MBOX_LOG"; echo "QUEUED seq=$((9000+n)) to=$2"
EOF
printf '#!/bin/bash\necho nope; exit 1\n' > "$T/mbox-fail"; chmod +x "$T/mbox" "$T/mbox-fail"
echo '{"_master":"byz-teama-master-claude#1"}' > "$T/.fable-team/seats-teama.json"; echo '{"_master":"byz-teamb-master-claude#2"}' > "$T/.fable-team/seats-teamb.json"
NOW0="$(date +%s)"; export FT_HEAD_LAG_NOW="$NOW0"
msgs() { wc -l < "$MBOX_LOG" | tr -d ' '; }
run() { out="$(python3 -I "$PY" "$@" --repo "$W" --base origin/main --bin "$BIN" 2>&1)"; rc=$?; }
mainc() { git -C "$W" checkout -q main; echo "$1" >> "$W/m.txt"; cm "$W" "main $1"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; }
mkwt() { git -C "$W" worktree add -q -b "$2" "$T/$1" "$3"; TM new-session -d -s "$4" -c "$T/$1"; }
keys() { python3 -c 'import json,sys;print(" ".join(sorted(json.load(open(sys.argv[1]))["seats"])))' "$SF"; }   # 새 판 꼴 {"v":2,"seats":{…}}
rec() { python3 -c 'import json,sys;r=json.load(open(sys.argv[1]))["seats"][sys.argv[2]];print(r["seq"],r["ts"],r["n"])' "$SF" "$2" 2>/dev/null; }
ver() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(type(d.get("v")).__name__, d.get("v"))' "$SF"; }
L="$(sha "$W" HEAD)"; mkwt wa nano/wa "$L" 'byz-teama-nano-claude#0'; RA="$(cd "$T/wa" && pwd -P)"
mainc c1

# ── ⓐ 같은 W · main 이 움직여도 재발송 0 (지금 판 = 2통)
run --event; [ "$rc" = 0 ] && [ "$(msgs)" = 1 ]; ck "ⓐ W 뒤처짐 → --event 1통" $?
mainc c2; run --event; [ "$rc" = 0 ] && [ "$(msgs)" = 1 ]; ck "ⓐ main 커밋 1 더 → --event 다시 → 재발송 0(합 1통)" $?
mainc c3; run --cron; [ "$(msgs)" = 1 ]; ck "ⓐ --cron 도 재발송 0" $?
[ "$(keys)" = "$RA" ]; ck "ⓐ 상태 키 = 워크트리 실제 경로 하나(@sha 0)" $?
# ── ⓑ REMIND_H(6시간) 뒤 다시 1 · 그 뒤 n 규칙(n ≥ 2 그만)
export FT_HEAD_LAG_NOW="$(( NOW0 + 6*3600 + 60 ))"; run --event; [ "$(msgs)" = 2 ]; ck "ⓑ 6시간 뒤 → 다시 알림 1(합 2)" $?
mainc c4; export FT_HEAD_LAG_NOW="$(( NOW0 + 13*3600 ))"; run --event; [ "$(msgs)" = 2 ]; ck "ⓑ 그 뒤(새 main 커밋 · 13시간) 0 — n ≥ 2" $?
# ── ⓒ 따라잡음 → 기록 삭제 → 다시 뒤처지면 바로 발송(새 사건)
git -C "$T/wa" merge -q --no-edit origin/main >/dev/null 2>&1; run --event
[ "$rc" = 0 ] && [ "$(keys)" = "" ] && [ "$(msgs)" = 2 ]; ck "ⓒ W 가 main 따라잡음 → W 기록 삭제 · 발송 0" $?
mainc c5; run --event; [ "$(msgs)" = 3 ] && [ "$(rec x "$RA" | cut -d' ' -f3)" = 1 ]; ck "ⓒ 다시 뒤처짐 → 바로 발송 1(새 사건 · n=1)" $?
# ── ⓓ 워크트리 2 · 팀 2 → 팀별 1통 · 문구 = 기준판(origin/main ft_head_lag.py)과 글자 같음
OLD="$T/old"; mkdir -p "$OLD"; cp "$BIN/ft_head_lag_seats.py" "$BIN/ft-head-skip.txt" "$OLD/"
git -C "$HERE" show origin/main:feature-pack/fable-team/harness/bin/ft_head_lag.py > "$OLD/ft_head_lag.py"
mkwt wb nano/wb "$L" 'byz-teamb-nano-claude#0'
rm -f "$SF"; : > "$MBOX_LOG"; PY="$OLD/ft_head_lag.py" run --event; cp "$MBOX_LOG" "$T/old.log"
rm -f "$SF"; : > "$MBOX_LOG"; run --event
[ "$(msgs)" = 2 ] && [ "$(grep -c '^byz-teama-master-claude#1' "$MBOX_LOG")" = 1 ] && [ "$(grep -c '^byz-teamb-master-claude#2' "$MBOX_LOG")" = 1 ]; ck "ⓓ 팀 A·B 각 1통" $?
[ -s "$T/old.log" ] && cmp -s <(sed 's/~조치:.*//' "$T/old.log") <(sed 's/~조치:.*//' "$MBOX_LOG") && grep -qF "$RA " "$MBOX_LOG"; ck "ⓓ 묶음 문구 기준판과 글자 같음(R749 절대 경로 · 조치 줄은 R882 가 바꿈)" $?
# ── ⓔ 옛 상태 파일(<경로>@<sha>) → 워크트리 키로 합침(가장 최근 ts · n 최대)
N="$FT_HEAD_LAG_NOW"; RB="$(cd "$T/wb" && pwd -P)"; S1="$(printf 'a%.0s' $(seq 40))"; S2="$(printf 'b%.0s' $(seq 40))"
python3 -c 'import json,sys;a,b,n,s1,s2=sys.argv[2:];n=int(n);json.dump({a+"@"+s1:{"seq":11,"ts":n-3600,"n":1},a+"@"+s2:{"seq":12,"ts":n-36000,"n":2},b+"@"+s1:{"seq":21,"ts":n-3600,"n":1}},open(sys.argv[1],"w"))' "$SF" "$RA" "$RB" "$N" "$S1" "$S2"
: > "$MBOX_LOG"; run --event
[ "$rc" = 0 ] && [ "$(msgs)" = 0 ]; ck "ⓔ 옛 키 기록(1시간 전 · n 최대 2) 기준 → 발송 0" $?
[ "$(keys)" = "$RA $RB" ] && [ "$(rec x "$RA")" = "11 $((N-3600)) 2" ] && [ "$(rec x "$RB")" = "21 $((N-3600)) 1" ]; ck "ⓔ 합친 기록 = 최근 ts 의 seq·ts · n 최대 · @sha 키 0" $?
[ "$(ver)" = "int 2" ]; ck "r3 옛 판 읽은 뒤 저장 = 새 판(v=2)" $?
export FT_HEAD_LAG_NOW="$(( N + 6*3600 ))"; run --event; [ "$(msgs)" = 1 ] && grep -q '^byz-teamb' "$MBOX_LOG"; ck "ⓔ 6시간 뒤 → n=1 인 B 만 다시 1 · n=2 인 A 0" $?
# ── ⓕ --summary · 발송 실패 rc5 · 기준 확인 실패 rc4
run --summary; [ "$rc" = 0 ] && [[ "$out" == "베이스 뒤처짐 2곳(가장 오래 "* ]]; ck "ⓕ --summary 1줄" $?
rm -f "$SF"; n0="$(msgs)"; FT_HEAD_LAG_MBOX="$T/mbox-fail" run --event; [ "$rc" = 5 ] && [ "$(keys)" = "" ]; ck "ⓕ 발송 실패 → rc 5 · 기록 0" $?
out="$(python3 -I "$PY" --event --repo "$W" --base origin/nope --bin "$BIN" 2>&1)"; rc=$?; [ "$rc" = 4 ] && [[ "$out" == *ERROR* ]] && [ "$(msgs)" = "$n0" ]; ck "ⓕ 기준 확인 실패 → rc 4 · 알림 0" $?
# ── r2(DA r1 반례): 꼴 틀린 기록은 그 줄만 버리고 WARN · 파일이 JSON·dict 아님 = 빈 상태 + WARN — 발송 판정은 «기록 없음»
git -C "$T/wb" merge -q --no-edit origin/main >/dev/null 2>&1   # 이제 뒤처진 곳 = wa(팀 A) 하나
bad() {  # bad <칸 이름> <상태 파일 내용> — rc0 · 발송 1(wa) · WARN 1 · 저장 뒤 키 = wa 하나
  printf '%s' "$2" > "$SF"; : > "$MBOX_LOG"; run --event
  [ "$rc" = 0 ] && [ "$(msgs)" = 1 ] && grep -q '^byz-teama' "$MBOX_LOG" && [ "$(grep -c '^WARN head-lag 상태' <<<"$out")" = 1 ] && [ "$(keys)" = "$RA" ]; ck "r2 $1 → rc0 · 발송 1 · WARN 1 · 저장 뒤 그 기록 없음" $?
}
A40="$(printf 'a%.0s' $(seq 40))"
bad "DA 반례(목록 밖 옛 키 · ts 없음)" "{\"$T/removed@$A40\": {\"seq\": 1, \"n\": 1}}"
grep -q "WARN head-lag 상태 기록 꼴 오류 — $T/removed@" <<<"$out"; ck "r2 WARN 문구 = 키 앞부분 · 버림" $?
bad "새 판 값 = 문자열" "{\"v\": 2, \"seats\": {\"$RA\": \"x\"}}"
bad "새 판 ts = 문자열" "{\"v\": 2, \"seats\": {\"$RA\": {\"seq\": 1, \"ts\": \"1\", \"n\": 1}}}"
bad "새 판 n = true" "{\"v\": 2, \"seats\": {\"$RA\": {\"seq\": 1, \"ts\": $FT_HEAD_LAG_NOW, \"n\": true}}}"
bad "목록 안 옛 키 · seq = null" "{\"$RA@$A40\": {\"seq\": null, \"ts\": $FT_HEAD_LAG_NOW, \"n\": 1}}"
bad "파일 = []" "[]"
bad "파일 = { 깨짐" "{"
OK1="{\"$RA\": {\"seq\": 1, \"ts\": $FT_HEAD_LAG_NOW, \"n\": 1}}"   # 꼴 맞는 기록(있으면 6시간 안 → 발송 0) — 판 꼴이 틀려 버려져야 발송 1
bad "r3 v = \"2\"(문자열)" "{\"v\": \"2\", \"seats\": $OK1}"
bad "r3 v = true" "{\"v\": true, \"seats\": $OK1}"
bad "r3 v = 3" "{\"v\": 3, \"seats\": $OK1}"
bad "r3 v = 2 · seats 가 list" "{\"v\": 2, \"seats\": [$OK1]}"
bad "r3 v = 2 · seats 없음" "{\"v\": 2}"
printf '{"v": 2, "seats": {"%s": {"ts": %s, "n": 1}}}' "$RA" "$FT_HEAD_LAG_NOW" > "$SF"; : > "$MBOX_LOG"; run --event
[ "$rc" = 0 ] && [ "$(msgs)" = 0 ] && ! grep -q WARN <<<"$out"; ck "r2 seq 없는 기록 = 꼴 맞음(6시간 안 → 발송 0 · WARN 0)" $?
run --event; ! grep -q WARN <<<"$out"; ck "r2 다음 실행 WARN 0" $?
# ── r3(DA r2 반례): 이름 끝이 @<40hex> 인 실제 워크트리 — 새 판 키는 글자 그대로(해석 0)
echo '{"_master":"byz-teamc-master-claude#3"}' > "$T/.fable-team/seats-teamc.json"
mkwt "wx@$A40" nano/wx "$L" 'byz-teamc-nano-claude#0'; RX="$(cd "$T/wx@$A40" && pwd -P)"; rm -f "$SF"; : > "$MBOX_LOG"
w=0; for i in 1 2 3; do run --event; grep -q WARN <<<"$out" && w=1; mainc "x$i"; done
[ "$(grep -c '^byz-teamc' "$MBOX_LOG")" = 1 ] && [ "$(rec x "$RX" | cut -d' ' -f3)" = 1 ] && [ "$w" = 0 ]; ck "r3 DA r2 반례: wx@<a×40> --event 3회(main 커밋 사이) → 발송 1 · 그 경로 기록 n=1 · WARN 0" $?
printf '{"v": 2, "seats": {"%s": {"seq": 5, "ts": %s, "n": 1}}}' "$RX" "$(( FT_HEAD_LAG_NOW - 3600 ))" > "$SF"; : > "$MBOX_LOG"; run --event
! grep -q '^byz-teamc' "$MBOX_LOG" && [ "$(rec x "$RX")" = "5 $(( FT_HEAD_LAG_NOW - 3600 )) 1" ]; ck "r3 새 판 키 <경로>@<a×40> = 그 워크트리 기록 그대로(1시간 전 → 발송 0 · seq 5 유지)" $?
# ── 정적
[ "$(wc -l < "$BIN/ft_head_lag.py" | tr -d ' ')" -le 150 ] && [ "$(wc -l < "$BIN/ft_head_lag_seats.py" | tr -d ' ')" -le 150 ]; ck "ft_head_lag.py · ft_head_lag_seats.py ≤ 150줄" $?
cmp -s "$BIN/ft_head_lag.py" "$BIN/../kit/fable-team/bin/ft_head_lag.py" && cmp -s "$BIN/ft_head_lag_seats.py" "$BIN/../kit/fable-team/bin/ft_head_lag_seats.py"; ck "짝 사본(kit) cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
