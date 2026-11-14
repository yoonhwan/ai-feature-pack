#!/usr/bin/env bash
# test_name_lint.sh — C2 세션명 문법 lint 시험: 통과 3 · REJECT 3 (+ 경계 케이스). tmux·명부는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../../harness/bin/ft-name-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"

pass_case() { out="$(bash "$LINT" "$1" 2>&1)"; rc=$?; [ $rc -eq 0 ] && [ "${out%%$'\n'*}" = "PASS $1" ] && ok "통과 $1" || bad "통과여야 함 $1 → rc=$rc $out"; }   # r1641 첫 줄 계약(둘째 줄 = 옛 꼴 WARN)
new_case()  { pass_case "$1"; [ "$out" = "PASS $1" ] && ok "WARN 0 $1" || bad "WARN 0 이어야 함 $1 → $out"; }
old_case()  { pass_case "$1"; [ "$out" = "PASS $1"$'\n'"WARN 옛 꼴 — 다음 승계에서 $2" ] && ok "WARN 1줄 $1" || bad "WARN 1줄이어야 함 $1 → $out"; }
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
[ "$(bash "$LINT" --roles | awk '{print $NF}')" = "qa" ] && ok "예약어 끝 = qa" || bad "예약어 끝 = qa"   # r1650 ⓐ
pass_case "byz-harness-qa-ft20-pi#3"   # ⓑ qa 범위 1토큰 + 에이전트
pass_case "byz-harness-qa-pi#3"
pass_case "byz-planner-qa-claude#2"
rej_case "byz-harness-qa#1" "에이전트 꼬리 필수"            # ⓒ
rej_case "byz-harness-qa-ft20#1" "에이전트여야"
rej_case "byz-harness-qa-a-b-pi#1" "qa 범위는 1토큰만"
rej_case "byz-harness-da-ft20-pi#1" "에이전트여야"          # ⓓ 범위 꼬리는 qa 만
for n in byz-issues-master-sol#59 byz-harness-da-astra#1; do rej_case "$n" "에이전트여야"; done   # ⓔ sol·astra = 모델 이름 · 꼬리 에이전트 아님
rej_case "byz-harness-da-gpt#1" "에이전트여야"
# r1641 석 칸 — ⓐ 새 꼴 · ⓑ 옛 꼴 + WARN · ⓒ nano 불변 · ⓓ 거절 · ⓔ3 qa
for n in byz-harness-da-0-codex#129 byz-harness-da-1-codex#0 byz-harness-arch-0-pi#292 byz-harness-master-0-pi#191; do new_case "$n"; done
old_case "byz-harness-da-codex#9" "da-0-codex"; old_case "byz-harness-arch-pi#292" "arch-0-pi"
new_case "byz-harness-nano-r1641-seat-slot-name-lint#0"
rej_case "byz-harness-da-x-codex#0" "석 칸은 숫자"
rej_case "byz-harness-da-01-codex#0" "앞자리 0"
rej_case "byz-harness-da-1-2-codex#0" "에이전트 1토큰만"
rej_case "byz-harness-da-codex-2#0" "순서가 틀렸다"
rej_case "byz-harness-da-1-foo#0" "에이전트여야"
new_case "byz-harness-qa-ft20-pi#3"; new_case "byz-harness-qa-1-pi#0"
rej_case "byz-harness-qa-1-ft20-pi#0" "에이전트 1토큰만"
for n in $(bash "$LINT" --roles); do [ "$n" = nano ] || old_case "byz-t-$n-pi#0" "$n-0-pi"; done   # 옛 꼴 WARN = 역할 좌석 전부
# ⓔ 이름 → 칸 · ⓔ2 역할 → 석 목록 (ft_roster_lib · tmp 명부 = 메모리 dict)
r="$(cd "$HERE/../bin" && python3 -c '
import ft_roster_lib as L
c = [L.name_cell("byz-harness-" + n) for n in ("da-0-codex#5", "da-1-codex#0", "da-codex#9", "arch-2-pi#0", "master-1-pi#0", "nano-r1641-seat-slot-name-lint#0", "qa-1-pi#0", "da-01-codex#0")]
s = [L.role_seats(d, "master") for d in ({"_master": "m0#1", "_masterx": "z", "_master-1": "m1#0", "_master-01": "q", "_master-0": "w"}, {"_master-1": "", "_master": "m0#1"})]
print(c, s, L.role_cell({"byz-t-da-1-codex#0": {}}, "byz-t-da-1-codex#0"), L.succ_role({"role": "stop-ready"}, [], "byz-t-da-1-codex#0"))')"
[ "$r" = "['_da', '_da-1', '_da', '_arch-2', '_master-1', None, '_qa-1', None] [[(0, 'm0#1'), (1, 'm1#0')], [(0, 'm0#1')]] ('_da-1', None) da" ] && ok "ⓔ 이름 → 칸 · ⓔ2 석 목록" || bad "ⓔ 이름 → 칸 · ⓔ2 석 목록 → $r"
long="byz-v65-nano-$(printf 'a%.0s' $(seq 1 60))#0"
rej_case "$long" "길이"
bash "$LINT" >/dev/null 2>&1; [ $? -eq 2 ] && ok "인자 없음 exit 2" || bad "인자 없음 exit"

echo "fail=$fail"; [ $fail -eq 0 ]
