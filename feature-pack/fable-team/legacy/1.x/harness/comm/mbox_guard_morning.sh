#!/bin/bash
# mbox_guard.sh 가 source 하는 문 ⑤ 본체 — 아침 묶음 «결정» 줄의 대리 시도 칸(R410 · 판정 2326 · 200줄 규칙 분리 · 단독 실행 0 · guard_log 는 mbox_guard.sh 가 둔다).
# 대상 = 머리 `[아침 묶음…` 쪽지(본문 + relay 첨부). 그 안의 `결정 N:` 줄(앞 `- ` 허용)마다 같은 줄에
#   `대리=PROXY <판정 번호>` 또는 `대리=QUEUE <사유>` 가 있어야 한다 — 없으면 REJECT rc 3(큐 적재 0).
#   자율 ON 이면 되돌릴 수 있는 선택은 ft-proxy-decide 로 그 턴 대리하고, 아침 큐엔 결과만 싣는다(BOOT 33).
# «결정» 줄이 없는 아침 묶음은 검사 0. 첨부를 못 읽으면 fail-closed REJECT. 외부 호출 0.

_morning_refuse() { guard_log mbox-guard-morning.log "REJECT ${1:0:160}"; echo "REJECT $1" >&2; return 3; }

# _guard_morning_lint <본문> [relay 첨부] — rc 3 = REJECT.
_guard_morning_lint() {
  local body="$1" attach="${2:-}" first text bad
  first="${body%%$'\n'*}"; first="${first#"${first%%[![:space:]]*}"}"
  case "$first" in '[아침 묶음'*) ;; *) return 0;; esac
  text="$body"; [ -z "$attach" ] || { [ -r "$attach" ] || { _morning_refuse "아침 묶음 첨부를 읽지 못했다($attach) — 결정 줄 검사 불가(fail-closed)"; return $?; }; text="$body"$'\n'"$(cat "$attach")"; }
  bad="$(printf '%s\n' "$text" | grep -E '^[[:space:]]*(-[[:space:]]*)?결정[[:space:]]*[0-9]+[[:space:]]*:' | grep -vE '대리=(PROXY[[:space:]]+[0-9]+|QUEUE[[:space:]]+[^[:space:]])' | head -1)"
  [ -z "$bad" ] || { _morning_refuse "아침 묶음 결정 줄에 대리 시도 칸(대리=PROXY <판정번호>|QUEUE <사유>) 없음 — 되돌릴 수 있는 선택은 ft-proxy-decide(--kind wt-clean|press-order …)로 먼저 대리하고 그 결과를 줄에 적어라 · 줄: ${bad:0:80}"; return $?; }
  return 0
}
