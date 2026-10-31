#!/usr/bin/env bash
# ft-test-run.sh <시험 명령…> — 나노 시험 1회 러너 (r1113b · 오빠 «테스트 끝나면 그때마다 정리» · r1041 시험 안전선)
#   ① 인자 중 있는 *.sh 파일 = ft-test-reentry-lint.sh 먼저(rc≠0 = 시험 안 돌림 · 그 rc 그대로 — 단 위반이 BGNOTRAP·TIMEOUTNOK 뿐이면 «WARN <그 줄>» stderr 뒤 시험 실행 · r1234)
#   ② 시험 = 따로 묶은 프로세스 묶음(set -m · 묶음 번호 = 시험 pid) 안에서 `ulimit -S -u <지금 내 프로세스 수 + FT_TEST_PROC_SLACK(256)>`(소프트만 — 하드까지 낮추면 안쪽 러너가 다시 못 정한다) + `timeout -k FT_TEST_KILL_AFTER_SEC(5) FT_TEST_TIMEOUT_SEC(70)`(r1234: TERM 무시 자식도 상한+5초에 KILL)
#   ③b r1234 ③ 뒤(quiesce 가 LSP·node 를 가려 센 다음) 시험 묶음(pgid=시험 pid)에 남은 프로세스를 TERM → KILL 로 끝정리 · 1줄 `[묶음 정리] 남은 <n> · TERM <a> · KILL <b> · 남은 묶음 <c>` (pgrep 실패 = «묶음 판정 불가» 1줄 · 시험 rc 그대로)
#   ③ 시험 rc 를 받은 직후`ft-seat-quiesce.sh --scope test $$ --pgid <시험 pid>` = 이 시험이 띄운 LSP·node 자식(HEAVY_NAME)만 정리 · 마지막 2줄 `[시험 정리] …` · `남은 자식 <n>`
#   rc = 시험 rc 그대로(정리 rc≠0 = `WARN 시험 정리 rc=<n>` 1줄 · 시험 판정 변경 0) · 사용법 2 · ps 실패(내 프로세스 수 0)·ulimit 실패 = 판정 불가 1줄 rc 20
#   시험용 env: FT_SEAT_QUIESCE_BIN · FT_TEST_REENTRY_LINT_BIN · FT_TEST_TIMEOUT_BIN
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <시험 명령…>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
Q="${FT_SEAT_QUIESCE_BIN:-$HERE/ft-seat-quiesce.sh}"; L="${FT_TEST_REENTRY_LINT_BIN:-$HERE/ft-test-reentry-lint.sh}"
files=(); for a in "$@"; do case "$a" in *.sh) [ -f "$a" ] && files+=("$a");; esac; done
if [ "${#files[@]}" -gt 0 ]; then
  lo="$(bash "$L" "${files[@]}")"; lrc=$?; [ -z "$lo" ] || printf '%s\n' "$lo"
  # r1234 반송 1: 위반이 BGNOTRAP·TIMEOUTNOK 뿐(rc3)이면 «WARN » 줄로 알리고 시험을 돌린다 · REENTRY·FLOATBASE·그 밖 rc 는 지금처럼 lint rc 로 멈춤
  if [ "$lrc" != 0 ]; then
    if [ "$lrc" = 3 ] && printf '%s\n' "$lo" | grep -Eq '^(BGNOTRAP|TIMEOUTNOK) ' && ! printf '%s\n' "$lo" | grep -Eq '^(REENTRY|FLOATBASE) '; then
      printf '%s\n' "$lo" | grep -E '^(BGNOTRAP|TIMEOUTNOK) ' | sed 's/^/WARN /' >&2
    else exit "$lrc"; fi
  fi
fi
n="$(ps -U "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')"
[ "${n:-0}" -gt 0 ] || { echo "TEST-RUN 판정 불가 — ps 로 내 프로세스 수를 못 셈(ulimit -u 상한 0 방지 · 시험 0)"; exit 20; }
grp() { local o r; o="$(pgrep -g "$1" 2>/dev/null)"; r=$?; case $r in 0) printf '%s\n' "$o" | grep -c .;; 1) echo 0;; *) echo -1;; esac; }
reap() { local m a=0 b=0 i c f  # r1234: 시험 묶음(pgid=$1)에 남은 프로세스 TERM → 폴링(0.2초·최대 3초) → KILL · 묶음 밖(setsid)은 범위 밖
  m="$(grp "$1")"; [ "$m" -ge 0 ] || { echo "[묶음 정리] 묶음 판정 불가 — pgrep 실패 · 시험 rc 그대로"; return 0; }
  if [ "$m" -gt 0 ]; then a=$m; kill -TERM -- "-$1" 2>/dev/null
    for i in $(seq 15); do c="$(grp "$1")"; [ "$c" -gt 0 ] || break; sleep 0.2; done
    if [ "$c" -gt 0 ]; then b=$c; kill -KILL -- "-$1" 2>/dev/null; for i in 1 2 3 4 5; do c="$(grp "$1")"; [ "$c" -gt 0 ] || break; sleep 0.2; done; fi
  fi
  f="$(grp "$1")"; [ "$f" -ge 0 ] || f="판정 불가"; echo "[묶음 정리] 남은 $m · TERM $a · KILL $b · 남은 묶음 $f"; }
set -m
( ulimit -S -u "$(( n + ${FT_TEST_PROC_SLACK:-256} ))" || { echo "TEST-RUN 판정 불가 — ulimit -S -u 실패(시험 0)"; exit 20; }; exec "${FT_TEST_TIMEOUT_BIN:-timeout}" -k "${FT_TEST_KILL_AFTER_SEC:-5}" "${FT_TEST_TIMEOUT_SEC:-70}" "$@" ) & tp=$!
set +m
wait "$tp"; rc=$?
bash "$Q" --scope test $$ --pgid "$tp"; qrc=$?
[ "$qrc" = 0 ] || echo "WARN 시험 정리 rc=$qrc — 남은 자식은 위 줄 · 시험 rc=$rc 그대로" >&2
reap "$tp"   # quiesce 뒤 — quiesce 가 LSP·node 를 이름·RSS 로 가려 센 다음, 묶음에 남은 나머지를 끝낸다(r1113b term=n 줄 보존)
exit "$rc"
