#!/bin/sh
# r2383 pre-push 나노 가드 시간 칸 시험 — 반례 ⑱ · 변이 M7 (7초 상한 두 번 · 15초 안).
# ⑱ 만 sleep 을 쓴다(가짜 python3 가 8초 멈춤 · rc 2) — 70초 상한 때문에 이 칸을 따로 뒀다.
# 공통 대역 = tests/pre_push_nano_guard_r2383_lib.sh · 실 원격 0.
# 실행: sh tests/test_pre_push_nano_guard_legacy_time_r2383.sh
. "$(dirname "$0")/pre_push_nano_guard_r2383_lib.sh"

run_case 18 c18

mtest M7 18 '    124|126|127)▸    1000)'

lib_done "반례 ⑱ · 변이 M7"
