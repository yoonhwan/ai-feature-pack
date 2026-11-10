#!/usr/bin/env bash
# test_seat_reap_services.sh — r505: 은퇴 reap(--orphans-only)·닫기 reap 이 press 서비스(gateway·worker)를 죽이지 않는다 · 루프 회수(r448)는 그대로.
#   ⓐ venv `…/bin/python` LISTEN 서비스 모사(ppid 1 · FT_SEAT=좌석) → --orphans-only 뒤 생존 · `reap-skip pid=<n> why=service-listen`
#   ⓑ LISTEN 없는 `python -m worker.x` 꼴 → 생존 · `why=service-cmd`
#   ⓒ `bash -c 'while :; do sleep 1; done'`(FT_SEAT=좌석 · ppid 1) → 정지 · stopped=1 left=0 rc=0
#   ⓓ 서비스의 자식(LISTEN 없는 bash sleep · FT_SEAT 상속) → 닫기 경로(--orphans-only 없음)에서도 생존 · 서비스 나무째 제외
#   ⓔ FT_REAP_SERVICE_RE 로 덮기 · lsof 실패 = rc 20(아무것도 안 죽임) · bash -n · 짝 cmp0 · 600/300 0
# 실프로세스 픽스처 = argv 에 표식 r505fx-<pid> 를 단 고아만 — trap 이 표식 프로세스 정리. tmux 세션 0 · 외부 호출 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; REAP="$BIN/ft-seat-reap.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r505fx-$$"; S="r505t-$$#1"
cleanup() { local p; for p in $(pgrep -f "$MK"); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
orphan() {  # orphan <실행 파일> <인자…> — FT_SEAT=$S · cwd $TMP/else · ppid 1 고아 1개 · pid 출력(argv 끝에 표식)
  ( cd "$TMP/else" || exit; FT_SEAT="$S" nohup "$@" </dev/null >/dev/null 2>&1 & )   # `&&` 로 이으면 & 가 목록 전체에 걸려 중간 셸이 남는다(ppid≠1)
  sleep 0.6; pgrep -f "$MK" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && ps -o command= -p "$p" | grep -qF -- "${*: -1}" && echo "$p"; done | tail -1
}
mkdir -p "$TMP/else/worker"; BASH_X="$(command -v bash)"
python3 -m venv --without-pip "$TMP/venv"   # venv 실행 파일 `…/venv/bin/python`(10-20 사건 꼴 · PROTECT_EXE 밖 — 프레임워크 빌드는 Python 으로 다시 뜨지만 역시 밖)
printf 'import sys, time\ntime.sleep(120)\n' > "$TMP/else/worker/x.py"; : > "$TMP/else/worker/__init__.py"

bash -n "$REAP" && ok "bash -n ft-seat-reap.sh" || bad "bash -n $REAP"
cmp -s "$REAP" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"

echo "== 픽스처 — ⓐ LISTEN 서비스(+ⓓ 자식) · ⓑ worker 명령 꼴 · ⓒ 감시 루프 (전부 ppid 1 · FT_SEAT=$S)"
SVC_SRC="import socket, subprocess, sys, time
s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen()
subprocess.Popen([sys.argv[1], '-c', 'sleep 120; : child-$MK'])
time.sleep(120)"
SA="$(orphan "$TMP/venv/bin/python" -c "$SVC_SRC" "$BASH_X" "listen-$MK")"
SB="$(orphan "$TMP/venv/bin/python" -m worker.x "cmd-$MK")"
LC="$(orphan "$BASH_X" -c "while :; do sleep 1; done # loop-$MK")"
SD="$(pgrep -P "${SA:-0}" -f "child-$MK" | head -1)"   # 서비스 소스 글자에도 child- 가 있다 — 부모로 고른다
chk "픽스처 4(ⓐ·ⓑ·ⓒ 고아 · ⓓ 자식)" "$([ -n "$SA" ] && [ -n "$SB" ] && [ -n "$LC" ] && [ -n "$SD" ] && echo 4)" 4
chk "ⓐ LISTEN 실재" "$(lsof -nP -a -p "${SA:-0}" -iTCP -sTCP:LISTEN -Fp 2>/dev/null | grep -c "^p$SA$")" 1
chk "ⓓ 자식 ppid = 서비스" "$(ps -o ppid= -p "${SD:-0}" | tr -d ' ')" "$SA"

echo "== ⓐⓑⓒ 은퇴 경로(--orphans-only) — 서비스 생존 · 루프만 정지"
dry="$(bash "$REAP" "$S" --orphans-only --dry-run)"
case "$dry" in *"reap-cand pid=$SA "*|*"reap-cand pid=$SB "*|*"reap-cand pid=$SD "*) bad "ⓐⓑ dry-run 후보에 서비스 ← $dry";; *) ok "ⓐⓑ dry-run 후보에 서비스 0";; esac
has "$dry" "reap-cand pid=$LC via=②" "ⓒ dry-run 루프 후보"
out="$(bash "$REAP" "$S" --orphans-only)"; rc=$?
has "$out" "reap-skip pid=$SA why=service-listen" "ⓐ reap-skip why=service-listen"
has "$out" "reap-skip pid=$SB why=service-cmd" "ⓑ reap-skip why=service-cmd"
chk "ⓐⓑ 서비스 생존 · ⓒ 루프 정지" "$(alive "$SA") $(alive "$SB") $(alive "$LC")" "alive alive dead"
chk "ⓒ 끝 줄 stopped=1 left=0 rc=0" "$rc $(tail -1 <<< "$out")" "0 reap $S stopped=1 left=0 rc=0"

echo "== ⓓ 닫기 경로(--orphans-only 없음) — 서비스 자식도 생존(서비스 나무째 제외)"
out="$(bash "$REAP" "$S")"; rc=$?
has "$out" "reap-skip pid=$SD why=service-listen" "ⓓ 자식 reap-skip why=service-listen"
chk "ⓓ 서비스·자식 생존 · 끝 줄 stopped=0 left=0 rc=0" "$(alive "$SA") $(alive "$SD") $rc $(tail -1 <<< "$out")" "alive alive 0 reap $S stopped=0 left=0 rc=0"

echo "== ⓔ FT_REAP_SERVICE_RE 덮기(서비스 명령 꼴 끔) → ⓑ 가 다시 후보 · lsof 실패 = rc 20"
dry="$(FT_REAP_SERVICE_RE='^$no-match' bash "$REAP" "$S" --orphans-only --dry-run)"
has "$dry" "reap-cand pid=$SB via=②" "ⓔ덮기 → ⓑ 후보(via=②)"
LE="$(orphan "$BASH_X" -c "while :; do sleep 1; done # loop2-$MK")"
mkdir -p "$TMP/fakelsof"; printf '#!/bin/sh\necho "lsof: boom" >&2\nexit 2\n' > "$TMP/fakelsof/lsof"; chmod +x "$TMP/fakelsof/lsof"
out="$(PATH="$TMP/fakelsof:$PATH" bash "$REAP" "$S" --orphans-only 2>&1)"; rc=$?
chk "ⓔlsof 실패 → rc 20 · left=? · 아무것도 안 죽임" "$rc $(tail -1 <<< "$out") $(alive "$LE") $(alive "$SA")" "20 reap $S stopped=0 left=? rc=20 alive alive"
kill "$LE" 2>/dev/null
chk "ⓔ 600/300 0" "$(grep -nE '\b(600|300)\b' "$REAP" | wc -l | tr -d ' ')" 0

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
