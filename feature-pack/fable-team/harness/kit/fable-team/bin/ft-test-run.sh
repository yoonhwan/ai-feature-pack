#!/usr/bin/env bash
# ft-test-run.sh <시험 명령…> — 나노 시험 1회 러너 (r1113b · 오빠 «테스트 끝나면 그때마다 정리» · r1041 시험 안전선)
#   ① 인자 중 있는 *.sh 파일 = ft-test-reentry-lint.sh 먼저(rc≠0 = 시험 안 돌림 · 그 rc 그대로)
#   ② 시험 = 따로 묶은 프로세스 묶음(set -m · 묶음 번호 = 시험 pid) 안에서 `ulimit -S -u <지금 내 프로세스 수 + FT_TEST_PROC_SLACK(256)>`(소프트만 — 하드까지 낮추면 안쪽 러너가 다시 못 정한다) + `timeout FT_TEST_TIMEOUT_SEC(70)`
#   ③ 시험 rc 를 받은 직후 `ft-seat-quiesce.sh --scope test $$ --pgid <시험 pid>` = 이 시험이 띄운 LSP·node 자식(HEAVY_NAME)만 정리 · 마지막 2줄 `[시험 정리] …` · `남은 자식 <n>`
#   rc = 시험 rc 그대로(정리 rc≠0 = `WARN 시험 정리 rc=<n>` 1줄 · 시험 판정 변경 0) · 사용법 2 · ps 실패(내 프로세스 수 0)·ulimit 실패 = 판정 불가 1줄 rc 20
#   시험용 env: FT_SEAT_QUIESCE_BIN · FT_TEST_REENTRY_LINT_BIN · FT_TEST_TIMEOUT_BIN
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <시험 명령…>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
Q="${FT_SEAT_QUIESCE_BIN:-$HERE/ft-seat-quiesce.sh}"; L="${FT_TEST_REENTRY_LINT_BIN:-$HERE/ft-test-reentry-lint.sh}"
files=(); for a in "$@"; do case "$a" in *.sh) [ -f "$a" ] && files+=("$a");; esac; done
if [ "${#files[@]}" -gt 0 ]; then bash "$L" "${files[@]}" || exit $?; fi
n="$(ps -U "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')"
[ "${n:-0}" -gt 0 ] || { echo "TEST-RUN 판정 불가 — ps 로 내 프로세스 수를 못 셈(ulimit -u 상한 0 방지 · 시험 0)"; exit 20; }
set -m
( ulimit -S -u "$(( n + ${FT_TEST_PROC_SLACK:-256} ))" || { echo "TEST-RUN 판정 불가 — ulimit -S -u 실패(시험 0)"; exit 20; }; exec "${FT_TEST_TIMEOUT_BIN:-timeout}" "${FT_TEST_TIMEOUT_SEC:-70}" "$@" ) & tp=$!
set +m
wait "$tp"; rc=$?
bash "$Q" --scope test $$ --pgid "$tp"; qrc=$?
[ "$qrc" = 0 ] || echo "WARN 시험 정리 rc=$qrc — 남은 자식은 위 줄 · 시험 rc=$rc 그대로" >&2
exit "$rc"
