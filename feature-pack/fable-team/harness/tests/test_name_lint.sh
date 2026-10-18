#!/usr/bin/env bash
# test_name_lint.sh — C2 세션명 문법 lint 시험: 통과 3 · REJECT 3 (+ 경계 케이스). tmux·명부는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../../scripts/fable-team-bin/ft-name-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"

pass_case() { out="$(bash "$LINT" "$1" 2>&1)"; rc=$?; [ $rc -eq 0 ] && [ "$out" = "PASS $1" ] && ok "통과 $1" || bad "통과여야 함 $1 → rc=$rc $out"; }
rej_case()  { out="$(bash "$LINT" "$1" 2>&1)"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "^REJECT $1: .*$2" && ok "REJECT $1 ($2)" || bad "REJECT 여야 함 $1 → rc=$rc $out"; }

# 통과 3 — 역할 좌석(에이전트 꼬리) · nano(slug) · 하이픈 든 slug
pass_case "byz-v65-master-claude#137"
pass_case "byz-harness-da-codex#2"
pass_case "byz-v65-nano-m7-p90-lang-update-gap#0"

# REJECT 3 — 구 문법(ft- 접두·역할 예약어 아님) · 에이전트 꼬리 없음 · 대문자/밑줄
rej_case "ft-harness-ops#4" "역할 'ops'"
rej_case "byz-v65-master#137" "역할 좌석은 에이전트 꼬리 필수"
rej_case "FB_CFO#52" "허용 문자"

# 경계
rej_case "byz-v65-master-claude" "계보 번호"
rej_case "byz-v65-master-claude#x" "정수"
rej_case "byz-v65-nano#0" "nano 는 카드 slug"
rej_case "byz-v65-master-gpt#1" "에이전트여야"
rej_case "byz-v65--master-claude#1" "빈 토큰"
rej_case "byz-v65#1" "토큰 부족"
long="byz-v65-nano-$(printf 'a%.0s' $(seq 1 60))#0"
rej_case "$long" "길이"
bash "$LINT" >/dev/null 2>&1; [ $? -eq 2 ] && ok "인자 없음 exit 2" || bad "인자 없음 exit"

echo "fail=$fail"; [ $fail -eq 0 ]
