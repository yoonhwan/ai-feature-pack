#!/usr/bin/env bash
# test_bg_cpu_burner_gate.sh — r523: kit/hooks/bg-cpu-burner-gate.sh (시간 상한 없는 백그라운드 CPU 소모기 = 거절).
#   픽스처 = 훅 직접 실행 + stdin PreToolUse JSON · 임시 폴더의 가짜 스크립트 파일 · 가짜 kill/pgrep/ps(불리면 표식).
# mktemp 만 쓴다 — 실제 burner 실행 0 · 외부 호출 0 · GIT_* env 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../kit/hooks/bg-cpu-burner-gate.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 가짜 kill·pgrep·ps — 훅이 부르면 표식이 생긴다(ⓙ 외부 프로세스 0)
mkdir -p "$T/fakebin"
for b in kill pgrep ps pkill; do printf '#!/bin/sh\ntouch "%s/called-%s"\n' "$T" "$b" > "$T/fakebin/$b"; chmod +x "$T/fakebin/$b"; done
export PATH="$T/fakebin:$PATH"

# gate <command> [bg] [tool] [cwd] → rc (stdout+stderr 는 $T/err)
gate() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"cwd":sys.argv[4],"tool_input":{"command":sys.argv[1],"run_in_background":sys.argv[2]=="1"}}))' \
    "$1" "${2:-0}" "${3:-Bash}" "${4:-$T}" | bash "$GATE" >"$T/err" 2>&1
}
expect() { gate "$3" "${4:-0}" "${5:-Bash}" "${6:-$T}"; rc=$?; [ "$rc" = "$1" ] && ok "$2 rc=$rc" || bad "$2 — rc=$rc 기대 $1 · $(head -c 300 "$T/err")"; }
WANT='시간 상한 없는 백그라운드 CPU 소모기 0(10-20 고아 yes 사건) · 부하 재현이 꼭 필요하면 timeout <≤600s> 로 감싸고 같은 스크립트에서 wait · 흔들리는 시험 증명은 사건 대기 + mutation(되돌리면 RED)'

[ -f "$GATE" ] || { bad "훅 파일 없음: $GATE"; echo "== 결과: FAIL=$fail"; exit 1; }

echo "== ⓐ 명령 글자 yes & = REJECT + 안내 1줄"
expect 2 "ⓐ yes > /dev/null &" 'yes > /dev/null &'
[ "$(grep -c '^REJECT bg-cpu-burner ' "$T/err")" = 1 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && ok "ⓐ stderr REJECT 1줄" || bad "ⓐ stderr: $(cat "$T/err")"
grep -qF "$WANT" "$T/err" && ok "ⓐ 안내 원문" || bad "ⓐ 안내 원문 없음: $(cat "$T/err")"

echo "== ⓑ 감싸개 nice · 여러 개"
expect 2 "ⓑ nice -n 19 yes & yes &" 'nice -n 19 yes > /dev/null & yes >/dev/null &'
expect 2 "ⓑ nohup yes 2>&1 &" 'nohup yes > /dev/null 2>&1 &'
expect 2 "ⓑ env X=1 /usr/bin/yes &" 'env X=1 /usr/bin/yes >/dev/null &'
expect 2 "ⓑ for … do yes & done" 'for i in 1 2 3; do yes > /dev/null & done'

echo "== ⓒ 실행되는 스크립트 파일 속(trap 은 면제 아님)"
printf '#!/bin/bash\ntrap '"'"'kill $(jobs -p)'"'"' EXIT\nfor i in 1 2 3; do\n  nice -n 19 yes > /dev/null &\ndone\nsleep 5\n' > "$T/loadrep.sh"; chmod +x "$T/loadrep.sh"
expect 2 "ⓒ bash <절대경로>/loadrep.sh" "bash $T/loadrep.sh"
grep -q 'loadrep.sh:4' "$T/err" && ok "ⓒ 파일:줄 = loadrep.sh:4" || bad "ⓒ 파일:줄 없음: $(cat "$T/err")"
expect 2 "ⓒ cwd 기준 bash loadrep.sh" 'bash loadrep.sh'
expect 2 "ⓒ ./loadrep.sh" './loadrep.sh'
expect 2 "ⓒ sh -x loadrep.sh" 'sh -x loadrep.sh'
expect 2 "ⓒ source loadrep.sh" 'source loadrep.sh'
expect 2 "ⓒ timeout 60 bash loadrep.sh(바깥 timeout 은 안의 & 고아를 못 끈다)" 'timeout 60 bash loadrep.sh'
printf "# don't run this\nyes > /dev/null &\n" > "$T/quote.sh"
expect 2 "ⓒ 주석 속 따옴표가 뒤 줄을 삼키지 않음" 'bash quote.sh'
grep -q 'quote.sh:2' "$T/err" && ok "ⓒ 파일:줄 = quote.sh:2" || bad "ⓒ quote 줄: $(cat "$T/err")"
printf 'while true; do\n  :\ndone &\n' > "$T/loop.sh"
expect 2 "ⓒ 파일 속 여러 줄 while true … done &" 'bash loop.sh'
grep -q 'loop.sh:1' "$T/err" && ok "ⓒ 파일:줄 = loop.sh:1" || bad "ⓒ loop 줄: $(cat "$T/err")"

echo "== ⓓ cat /dev/zero · dd · while true · while :"
expect 2 "ⓓ cat /dev/zero &" 'cat /dev/zero > /dev/null &'
expect 2 "ⓓ cat /dev/urandom &" 'cat /dev/urandom > /dev/null &'
expect 2 "ⓓ dd if=/dev/zero &" 'dd if=/dev/zero of=/dev/null &'
expect 2 "ⓓ while true … done &" 'while true; do :; done &'
expect 2 "ⓓ while : … done &" 'while :; do :; done &'
expect 2 "ⓓ while [ 1 ] … done &" 'while [ 1 ]; do :; done &'
expect 2 "ⓓ bash -c 문자열 안 yes &" "bash -c 'yes > /dev/null &'"

echo "== ⓔ run_in_background: true"
expect 2 "ⓔ bg=true + yes > /dev/null" 'yes > /dev/null' 1
expect 2 "ⓔ bg=true + while true; do :; done" 'while true; do :; done' 1
expect 0 "ⓔ bg=true + while true; do sleep 5; done(sleep = r448 영역)" 'while true; do sleep 5; done' 1
expect 0 "ⓔ bg=true + sleep 30" 'sleep 30' 1
expect 0 "ⓔ bg=false + yes | head" 'yes | head -5' 0

echo "== ⓕ 통과"
for c in 'timeout 60 yes > /dev/null &' 'yes | head -5' 'yes y | apt-get install x' 'cmd && other' \
         'echo "yes &"' '# yes > /dev/null &' 'git commit -m "yes > /dev/null & 막음"' \
         'while true; do sleep 1; done &' 'dd if=/dev/zero of=/tmp/x bs=1k count=10 &' \
         'make &> build.log &' 'yes > /dev/null && echo ok' 'yes 2>&1 | head -5' '# while true; do :; done &' 'cat <<EOF > x.sh
yes > /dev/null &
EOF' 'sleep 30 &'; do
  expect 0 "ⓕ $(printf '%s' "$c" | tr '\n' ' ')" "$c"
done
expect 0 "ⓕ tool_name≠Bash = 통과" 'yes > /dev/null &' 0 Edit
expect 0 "ⓕ 이 시험 파일 자체 실행 = 통과" "bash $HERE/test_bg_cpu_burner_gate.sh"

echo "== ⓖ 없는 파일 · 256KB 넘는 파일 = 읽기 생략 · 경고 0"
expect 0 "ⓖ bash <없는 파일>" "bash $T/nope.sh"
[ -s "$T/err" ] && bad "ⓖ 없는 파일 stderr: $(cat "$T/err")" || ok "ⓖ 없는 파일 stderr 0"
{ printf 'yes > /dev/null &\n'; head -c 300000 /dev/zero | tr '\0' '#'; printf '\n'; } > "$T/big.sh"
expect 0 "ⓖ 256KB 넘는 파일" 'bash big.sh'
[ -s "$T/err" ] && bad "ⓖ 큰 파일 stderr: $(cat "$T/err")" || ok "ⓖ 큰 파일 stderr 0"

echo "== ⓗ 입력 깨짐 = 통과 + 경고(fail-open)"
printf 'not json' | bash "$GATE" >"$T/err" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'WARN bg-cpu-burner-gate' "$T/err" && ok "ⓗ JSON 못 읽음 = rc0 + WARN" || bad "ⓗ rc=$rc $(cat "$T/err")"
printf '' | bash "$GATE" >/dev/null 2>&1 && ok "ⓗ 빈 입력 = 통과" || bad "ⓗ 빈 입력"

echo "== ⓘ timeout 상한 600초"
expect 2 "ⓘ timeout 2h yes &" 'timeout 2h yes > /dev/null &'
grep -q '상한 600s 초과' "$T/err" && ok "ⓘ 상한 문구" || bad "ⓘ 상한 문구 없음: $(cat "$T/err")"
expect 2 "ⓘ timeout 601 yes &" 'timeout 601 yes &'
expect 0 "ⓘ timeout 600 yes &" 'timeout 600 yes > /dev/null &'
expect 0 "ⓘ timeout -k 5 10m yes &" 'timeout -k 5 10m yes > /dev/null &'
expect 0 "ⓘ gtimeout 30s nice yes &" 'gtimeout 30s nice -n 19 yes > /dev/null &'

echo "== ⓙ 1초 안 · 외부 프로세스 0"
el=$(python3 -c 'import json,subprocess,sys,time
d=json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":"bash loadrep.sh"}})
t=time.perf_counter(); subprocess.run(["bash",sys.argv[1]],input=d.encode(),capture_output=True); print("%.3f"%(time.perf_counter()-t))' "$GATE" "$T")
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 1.0 else 1)' "$el" && ok "ⓙ 훅 1회 ${el}s < 1s" || bad "ⓙ 훅 ${el}s"
called=$(find "$T" -maxdepth 1 -name 'called-*' | wc -l | tr -d ' ')
[ "$called" = 0 ] && ok "ⓙ kill·pgrep·ps·pkill 호출 0" || bad "ⓙ 외부 프로세스 호출 $called: $(find "$T" -maxdepth 1 -name 'called-*')"
grep -nE 'subprocess|os\.system|os\.kill|popen' "$GATE" && bad "ⓙ 훅 본문에 프로세스 호출 글자" || ok "ⓙ 훅 본문 프로세스 호출 글자 0"

echo "== 설치 목록 · 스니펫"
python3 - "$HERE/../kit/fable-team/templates/settings-hooks.snippet.json" <<'PY' && ok "스니펫 PreToolUse Bash 1항(JSON 유효)" || bad "스니펫 항 없음"
import json, sys
d = json.load(open(sys.argv[1]))
hits = [e for e in d["hooks"]["PreToolUse"] if e.get("matcher") == "Bash"
        and any(h.get("command") == "$HOME/.claude/hooks/bg-cpu-burner-gate.sh" for h in e.get("hooks", []))]
sys.exit(0 if len(hits) == 1 else 1)
PY
[ -x "$GATE" ] && ok "훅 실행 권한" || bad "훅 실행 권한 없음"
bash -n "$GATE" && ok "bash -n" || bad "bash -n"

echo "== 결과: FAIL=$fail"
[ "$fail" = 0 ]
