#!/usr/bin/env bash
# test_from_current_r730.sh — r730 «보내는 사람 = 명부 현역» 해석(ft_from_current)이 계보를 지키며 동작하는가.
#   원인: 팀 env 의 FT_SEND_FROM 은 고정 글자라 팀장 승계(명부 `_master` 교체)를 따라오지 않는다
#         → 새 팀장이 연 나노의 발주문이 «산출 경로를 mbox 로 <옛 팀장>» 이라고 적히고 송신 from 도 죽은 좌석으로 갔다(챗봇 나노 보고 5통).
#   ⓑ 같은 계보(#N 만 다름) → 명부 `_master` + INFO 1줄 · ⓒ 계보 다름 → 그대로 · ⓓ 명부 못 읽음/`_master` 없음/lint 실패 → 그대로 + WARN 1줄
#   ⓔ --from 명시 → 그 값 그대로(해석 안 함) · ⓕ 세 곳이 «같은 한 함수» 를 부른다 · ⓖ 변이 2종 · ⓗ 실 쪽지·tmux 0(순수 함수)
# 꼴 = test_nano_spawn_body_search_roster.sh(정적 대조 + 실제 줄 eval) — 실 스폰·실 명부·tmux 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; BIN="$HERE/../bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '{"_version":"1","_master":"byz-x-master-claude#5","byz-x-master-claude#5":{"role":"master"}}\n' > "$TMP/seats-x.json"
printf '{"_master":"FB_KK#4"}\n' > "$TMP/seats-kk.json"
printf '{"_version":"1"}\n' > "$TMP/seats-nomaster.json"

# ── 사본 정합: kit ↔ tracked 동률(짝 사본) · 문법
for f in ft-team-lib.sh ft-nano-spawn.sh ft-role-spawn.sh; do
  bash -n "$KIT/$f" && ok "bash -n kit/$f" || bad "bash -n kit/$f"
  cmp -s "$KIT/$f" "$BIN/$f" && ok "cmp0 kit↔bin $f" || bad "cmp0 kit↔bin $f"
done
bash -n "$KIT/ft-send-verified.sh" && ok "bash -n kit/ft-send-verified.sh" || bad "bash -n kit/ft-send-verified.sh"

# run_from <lib> <값> [<명부>] → stdout 값 · stderr 는 그대로 흘린다
run_from() { bash -c '. "$1"; shift; ft_from_current "$@"' _ "$@"; }

# ── ⓑ 같은 계보 → 명부 현역 + INFO 1줄
out="$(run_from "$KIT/ft-team-lib.sh" 'byz-x-master-claude#2' "$TMP/seats-x.json" 2>"$TMP/err")"; rc=$?
[ "$out" = "byz-x-master-claude#5" ] && ok "ⓑ 같은 계보 → #5" || bad "ⓑ 같은 계보 결과 '$out' (기대 byz-x-master-claude#5)"
[ "$rc" = 0 ] && ok "ⓑ rc0" || bad "ⓑ rc=$rc"
[ "$(cat "$TMP/err")" = "INFO FT_SEND_FROM 옛 세대(#2) → 명부 현역(#5)" ] && ok "ⓑ INFO 1줄 원문" || bad "ⓑ INFO 줄 다름: $(cat "$TMP/err")"
# 이미 현역이면 조용하다(INFO 0) — send-verified 가 두 번 풀어도 로그가 안 늘어난다
out="$(run_from "$KIT/ft-team-lib.sh" 'byz-x-master-claude#5' "$TMP/seats-x.json" 2>"$TMP/err2")"
[ "$out" = "byz-x-master-claude#5" ] && [ ! -s "$TMP/err2" ] && ok "ⓑ 현역이면 침묵" || bad "ⓑ 현역인데 stderr: $(cat "$TMP/err2")"

# ── ⓒ 계보가 다르면 그대로(옛 이름·다른 역할은 자동으로 안 바꾼다) · stderr 0
for v in 'ft-issue-manager#0' 'byz-planner-arch#0' 'byz-y-master-claude#2'; do
  out="$(run_from "$KIT/ft-team-lib.sh" "$v" "$TMP/seats-x.json" 2>"$TMP/err")"
  [ "$out" = "$v" ] && [ ! -s "$TMP/err" ] && ok "ⓒ 계보 다름 그대로: $v" || bad "ⓒ 계보 다름인데 '$out' / stderr=$(cat "$TMP/err")"
done

# ── ⓓ 못 풀면 «지금 값 그대로» + WARN 1줄 (발신을 막지 않는다 = 안전 쪽)
chk_warn() { local label="$1" val="$2" seat="$3"
  local out; out="$(run_from "$KIT/ft-team-lib.sh" "$val" "$seat" 2>"$TMP/err")"
  [ "$out" = "$val" ] && ok "ⓓ $label 값 그대로" || bad "ⓓ $label 값이 '$out' 로 바뀜"
  [ "$(grep -c '^WARN FT_SEND_FROM 현역 해석 못 함' "$TMP/err")" = 1 ] && ok "ⓓ $label WARN 1줄" || bad "ⓓ $label WARN: $(cat "$TMP/err")"
  grep -q '값 그대로' "$TMP/err" && ok "ⓓ $label WARN 에 값 병기" || bad "ⓓ $label WARN 에 값 없음"; }
chk_warn "명부 없음" 'byz-x-master-claude#2' "$TMP/none.json"
chk_warn "_master 없음" 'byz-x-master-claude#2' "$TMP/seats-nomaster.json"
chk_warn "lint 실패(FB_KK#4)" 'FB_KK#3' "$TMP/seats-kk.json"
out="$(run_from "$KIT/ft-team-lib.sh" '' "$TMP/seats-x.json" 2>/dev/null)"; [ -z "$out" ] && ok "ⓓ 빈 값 → 빈 값(rc0)" || bad "ⓓ 빈 값이 '$out'"

# ── ⓔ --from 명시 → 해석하지 않는다 (r975 r4·오빠 결정 3 뒤: spawn 은 «아예 해석하지 않는다»)
#   spawn 의 보고 대상은 «살아 있는 좌석 목록»(tmm ls) 이 정한다 — 명부 파일(seats.json·팀 env·FT_SEATS_JSON)을 읽어
#   이름을 바꾸는 코드가 하나도 남아 있으면 그 자체가 r975 반례다(r1~r3 전부 그 원인이었다).
[ "$(grep -cE '^[^#]*ft_from_current|^[^#]*ft_from_gen' "$KIT/ft-nano-spawn.sh")" = 0 ] \
  && ok "ⓔ nano-spawn 은 발신자를 해석하지 않는다(승계 추적 0 · tmm 목록이 정한다)" \
  || bad "ⓔ nano-spawn 이 아직 명부로 발신자를 해석한다"
[ "$(LC_ALL=en_US.UTF-8 grep -c 'tmm ls' "$KIT/ft-nano-spawn.sh")" -ge 1 ] \
  && ok "ⓔ nano-spawn 이 살아 있는 좌석 목록(tmm ls)을 본다" || bad "ⓔ tmm ls 호출 0"
# r975 반송 r2(DA⑥ r2 ①): ft-send-verified 는 «부르는 쪽이 확정해 넘긴 발신자» 를 그대로 쓴다 — 재해석 0.
#   해석은 role-spawn 한 곳(= 해석할 «인자·env» 를 직접 받는 곳)에서만 1회.
for f in ft-role-spawn.sh; do
  [ "$(grep -c 'ft_from_current' "$KIT/$f")" = 1 ] && ok "ⓕ $f 가 함수 1회 호출" || bad "ⓕ $f 호출 $(grep -c 'ft_from_current' "$KIT/$f")회 (기대 1)"
done
[ "$(grep -cE '^[^#]*ft_from_current' "$KIT/ft-send-verified.sh")" = 0 ] \
  && ok "ⓕ ft-send-verified.sh 는 재해석 0(확정 발신자 그대로 · r975 r2)" \
  || bad "ⓕ ft-send-verified.sh 가 발신자를 다시 해석한다($(grep -cE '^[^#]*ft_from_current' "$KIT/ft-send-verified.sh")회) — 명시 --from 이 되돌려진다"
[ "$(grep -c '^ft_from_current()' "$KIT/ft-team-lib.sh")" = 1 ] && ok "ⓕ 정의는 ft-team-lib.sh 한 곳" || bad "ⓕ ft-team-lib.sh 의 ft_from_current 정의 $(grep -c '^ft_from_current()' "$KIT/ft-team-lib.sh")회 (기대 1)"

# ── ⓖ 변이 2종 — 지우면 ⓑ·ⓒ 가 무너진다
mut1="$TMP/mut-lineage.sh"; LC_ALL=en_US.UTF-8 grep -v '^  \[ "\$(_ft_from_lineage "\$v")" = "\$(_ft_from_lineage "\$m")" \]' "$KIT/ft-team-lib.sh" > "$mut1"
cmp -s "$KIT/ft-team-lib.sh" "$mut1" && bad "ⓖ 변이1 sed 미적용" || ok "ⓖ 변이1 적용(계보 비교 삭제)"
[ "$(run_from "$mut1" 'ft-issue-manager#0' "$TMP/seats-x.json" 2>/dev/null)" = 'byz-x-master-claude#5' ] \
  && ok "ⓖ 계보 비교 삭제 → ⓒ FAIL(그대로 안 됨)" || bad "ⓖ 계보 비교를 지웠는데 ⓒ 가 통과"
mut2="$TMP/mut-roster.sh"; LC_ALL=en_US.UTF-8 grep -v '^  m="\$(grep -o' "$KIT/ft-team-lib.sh" > "$mut2"
cmp -s "$KIT/ft-team-lib.sh" "$mut2" && bad "ⓖ 변이2 sed 미적용" || ok "ⓖ 변이2 적용(명부 해석 삭제)"
[ "$(run_from "$mut2" 'byz-x-master-claude#2' "$TMP/seats-x.json" 2>/dev/null)" = 'byz-x-master-claude#2' ] \
  && ok "ⓖ 명부 해석 삭제 → ⓑ FAIL(#5 안 됨)" || bad "ⓖ 명부 해석을 지웠는데 ⓑ 가 통과"

# ── ⓗ 격리: 이 함수는 읽기만 한다(쪽지·tmux·명부 쓰기 0)
grep -n 'mbox\|tmux\|redis\|>\s*"\$seats"' "$KIT/ft-team-lib.sh" | grep -q 'ft_from_current\|_ft_from' && bad "ⓗ ft_from_current 가 부작용 도구를 부른다" || ok "ⓗ ft_from_current 부작용 0(읽기만)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
