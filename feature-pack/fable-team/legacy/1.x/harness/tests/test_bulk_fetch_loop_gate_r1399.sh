#!/usr/bin/env bash
# test_bulk_fetch_loop_gate_r1399.sh — r1399: kit/hooks/bulk-fetch-loop-gate.sh
#   (원격 가지 목록을 돌며 가지마다 git fetch = 거절 · 11-05 issues 좌석 52분 · load 87).
# 픽스처 = 훅 직접 실행 + stdin PreToolUse JSON · 임시 폴더의 가짜 스크립트 파일.
# 실 git·실 fetch 0 · 실 settings 0 · 자기 재호출 0 · 가짜 git 이 불리면 표식(ⓙ).
# GATE 환경변수로 다른 판(기준판·변이판)을 넣을 수 있다.
set -uo pipefail
ulimit -u $(( $(ps -U "$(id -u)" -o pid= | wc -l) + 128 )) 2>/dev/null || true   # 사용자 단위 상한 = 지금 + 128(고정값은 fork 실패)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${GATE:-$HERE/../kit/hooks/bulk-fetch-loop-gate.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mkdir -p "$T/fakebin"
printf '#!/bin/sh\ntouch "%s/called-git"\n' "$T" > "$T/fakebin/git"; chmod +x "$T/fakebin/git"
export PATH="$T/fakebin:$PATH"

# gate <command> [tool] [cwd] → rc (stdout+stderr 는 $T/err) · 1회 70초 상한
gate() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[2],"cwd":sys.argv[3],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "${2:-Bash}" "${3:-$T}" | timeout 70 bash "$GATE" >"$T/err" 2>&1
}
expect() { gate "$3" "${4:-Bash}" "${5:-$T}"; rc=$?; [ "$rc" = "$1" ] && ok "$2 rc=$rc" || bad "$2 — rc=$rc 기대 $1 · $(head -c 300 "$T/err")"; }
WANT='원격 가지 전부를 하나씩 fetch 금지(11-05 issues 52분 · load 87) · 대조는 origin/main 한 곳 · 꼭 필요하면 refspec 1회 fetch(25초)'

[ -f "$GATE" ] || { bad "훅 파일 없음: $GATE"; echo "== 결과: FAIL=$fail"; exit 1; }

echo "== B1~B3 명령 글자 = REJECT + 안내 1줄"
expect 2 "B1 for b in \$(git ls-remote 'refs/heads/*') … git fetch" \
  "for b in \$(git ls-remote origin 'refs/heads/*' | awk '{print \$2}'); do git fetch origin \"\$b\"; done"
[ "$(grep -c '^REJECT bulk-fetch-loop ' "$T/err")" = 1 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && ok "B1 stderr REJECT 1줄" || bad "B1 stderr: $(cat "$T/err")"
grep -qF "$WANT" "$T/err" && ok "B1 안내 원문" || bad "B1 안내 원문 없음: $(cat "$T/err")"
expect 2 "B2 ls-remote --heads | while read … fetch … done &" \
  'git ls-remote --heads origin | while read s r; do git fetch origin "$r"; done &'
expect 2 "B3 git branch -r | xargs -n1 git fetch origin" 'git branch -r | xargs -n1 git fetch origin'

echo "== B4 1단계 스크립트 파일 속"
printf '#!/bin/bash\n# 번호 대조\nfor b in $(git ls-remote origin "refs/heads/*" | cut -f2); do\n  git fetch -q origin "$b"\ndone\n' > "$T/x.sh"
expect 2 "B4 bash <절대경로>/x.sh" "bash $T/x.sh"
grep -q 'x.sh:3' "$T/err" && ok "B4 파일:줄 = x.sh:3" || bad "B4 파일:줄 없음: $(cat "$T/err")"
expect 2 "B4 cwd 기준 ./x.sh" './x.sh'

echo "== B1~B3 변형(같은 꼴)"
expect 2 "for-each-ref refs/remotes 루프" \
  "for r in \$(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin); do git -C . fetch origin \"\$r\"; done"
expect 2 "변수에 담은 목록" "bs=\$(git branch -r); for b in \$bs; do git fetch origin \"\${b#origin/}\"; done"
expect 2 "while … done < <(ls-remote --heads)" 'while read s r; do git fetch origin "$r"; done < <(git ls-remote --heads origin)'
expect 2 "xargs -I{} sh -c 'git fetch origin {}'" "git branch -r | xargs -I{} sh -c 'git fetch origin {}'"
expect 2 "bash -c 문자열 속 루프" "bash -c 'for b in \$(git branch -r); do git fetch origin \$b; done'"

echo "== B5~B9 통과"
expect 0 "B5 git fetch origin main" 'git fetch origin main'
expect 0 "B6 ls-remote refs/heads 만(fetch 없음)" "git ls-remote origin 'refs/heads/*' | wc -l"
expect 0 "B7 refspec 1회 fetch" "git fetch origin '+refs/heads/*:refs/remotes/origin/*'"
expect 0 "B8 따옴표 속 글자" "echo \"for b in \$(git ls-remote origin 'refs/heads/*'); do git fetch origin \$b; done\""
expect 0 "B9 목록 + fetch 1회(반복 없음)" "git ls-remote --heads origin > $T/h.txt; git fetch origin main"
for c in 'git fetch origin feat/x' 'git branch -r | grep r1399' 'for r in origin upstream; do git fetch "$r" main; done' \
         '# for b in $(git branch -r); do git fetch origin $b; done' 'git commit -m "for b in $(git branch -r); do git fetch; done 막음"' \
         'git ls-remote --heads origin | while read s r; do echo "$r"; done' 'cat <<EOF > y.sh
for b in $(git branch -r); do git fetch origin $b; done
EOF'; do
  expect 0 "통과 $(printf '%s' "$c" | tr '\n' ' ')" "$c"
done
expect 0 "tool_name≠Bash = 통과" 'git branch -r | xargs -n1 git fetch origin' Edit

echo "== 못 읽음·없는 파일 = 통과"
printf 'not json' | timeout 70 bash "$GATE" >"$T/err" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'WARN bulk-fetch-loop-gate' "$T/err" && ok "JSON 못 읽음 = rc0 + WARN" || bad "rc=$rc $(cat "$T/err")"
printf '' | timeout 70 bash "$GATE" >/dev/null 2>&1 && ok "빈 입력 = 통과" || bad "빈 입력"
expect 0 "bash <없는 파일>" "bash $T/nope.sh"
[ -s "$T/err" ] && bad "없는 파일 stderr: $(cat "$T/err")" || ok "없는 파일 stderr 0"

echo "== ⓙ 1초 안 · git 실행 0"
el=$(python3 -c 'import json,subprocess,sys,time
d=json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":"bash x.sh"}})
t=time.perf_counter(); subprocess.run(["bash",sys.argv[1]],input=d.encode(),capture_output=True,timeout=70); print("%.3f"%(time.perf_counter()-t))' "$GATE" "$T")
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 1.0 else 1)' "$el" && ok "ⓙ 훅 1회 ${el}s < 1s" || bad "ⓙ 훅 ${el}s"
[ -e "$T/called-git" ] && bad "ⓙ git 이 실행됨" || ok "ⓙ git 실행 0"
grep -nE 'subprocess|os\.system|os\.kill|popen' "$GATE" && bad "ⓙ 훅 본문에 프로세스 호출 글자" || ok "ⓙ 훅 본문 프로세스 호출 글자 0"
[ -x "$GATE" ] && ok "훅 실행 권한" || bad "훅 실행 권한 없음"
bash -n "$GATE" && ok "bash -n" || bad "bash -n"

echo "== 결과: FAIL=$fail"
[ "$fail" = 0 ]
