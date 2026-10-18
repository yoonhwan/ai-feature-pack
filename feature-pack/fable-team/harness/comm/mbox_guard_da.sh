#!/bin/bash
# mbox_guard.sh 가 source 하는 문 ④ 본체 — 같은 카드 DA 보류 2회 가드(판정 2282 · R387 · 200줄 규칙 분리 · 단독 실행 0 · DIR·GUARD_STATE·guard_log·_seats_json·_ft_live_bin 은 mbox_guard.sh·lib 가 둔다).
# 대상 = 수신자 `*-da-*` ∧ 머리 `[DA②|DA⑥ [rN] 발주 …]`(꼬리 `· 마지막` 허용). 판정기 하나 = ft_da_hold_gate.py(사건 키·해제·소진 계산은 거기).
# fail-closed — 발주서(본문 + relay 첨부)에 `- 카드: <indices/(대기|진행)/…md>` 가 정확히 1개 · 파일 실재 · 카드 «상태» 에 같은 (단계, rN) 의 `발주` 줄 — 하나라도 어긋나면 REJECT rc 3(큐 적재 0) · 판정기 부재·실행 실패도 REJECT.
# 입장을 허용하는 순간 판정기가 카드 «상태» 끝에 `- DA 입장: <단계>r<N> · 발주서 <경로> · 해제 #<seq|없음> · <시각>` 1줄을 쓴다(유일한 쓰기 · 실패 = REJECT) — 같은 (단계, rN) 재입장 = DUP-ENTRY.
# 안전 보고([HIL]·[긴급]) 는 머리가 [DA… 발주 가 아니라 대상 밖이다. 외부 호출 0.

_da_refuse() { guard_log mbox-guard-da.log "REJECT to=$1 ${2:0:120}"; echo "REJECT $2" >&2; return 3; }

# _guard_da_lint <수신자> <본문> [relay 첨부] — rc 3 = REJECT.
_guard_da_lint() {
  local to="$1" body="$2" attach="${3:-}" first text cards n card tool res rc stage rnd root fl
  first="${body%%$'\n'*}"; first="${first#"${first%%[![:space:]]*}"}"
  case "$to" in *-da-*) ;; *) return 0;; esac
  [[ "$first" =~ ^\[DA(②|⑥)(\ r([0-9]+))?\ 발주 ]] || return 0
  stage="${BASH_REMATCH[1]}"; rnd="${BASH_REMATCH[3]:-1}"
  text="$body"; [ -z "$attach" ] || { [ -r "$attach" ] || { _da_refuse "$to" "DA 발주 첨부를 읽지 못했다($attach)"; return $?; }; text="$body"$'\n'"$(cat "$attach")"; }
  cards="$(printf '%s\n' "$text" | sed -n 's/^- 카드:[[:space:]]*//p' | sed 's/[[:space:]`]*$//; s/^`//' | sort -u)"
  n="$(printf '%s' "$cards" | grep -c . || true)"
  [ "$n" = 1 ] || { _da_refuse "$to" "카드 경로 ${n:-0}개 — DA 발주서 머리에 «- 카드: <indices/(대기|진행)/….md>» 1줄이 정확히 1개 있어야 한다(fail-closed · 복수·없음 거절)"; return $?; }
  card="$cards"; root="$(cd "$DIR/../.." 2>/dev/null && pwd)"
  [[ "$card" =~ (^|/)indices/(대기|진행)/[^/]+\.md$ ]] || { _da_refuse "$to" "카드 경로 형식 아님($card) — indices/(대기|진행)/….md"; return $?; }
  case "$card" in /*) ;; *) card="$root/$card";; esac
  [ -f "$card" ] || { _da_refuse "$to" "없는 카드 파일($card)"; return $?; }
  tool="$(_ft_live_bin ft_da_hold_gate.py 2>&1)" || { _da_refuse "$to" "판정기 없음($tool) — DA 발주는 확인 없이 보내지 않는다(fail-closed) · ft_da_hold_gate.py 를 먼저 설치하라"; return $?; }
  res="$(python3 "$tool" "$card" --entry "$stage" "r$rnd" --record --order-file "${attach:-본문}" --root "$root" --comm "$DIR" --seats-dir "$(dirname "$(_seats_json)")" 2>&1)"; rc=$?
  fl="${res%%$'\n'*}"
  case "$rc:$fl" in
    0:*) return 0;;
    3:UNPARSED*) _da_refuse "$to" "DA 보류 판정 불가 — ${fl:0:100} · 카드 «## 상태» 의 그 줄을 «DA② rN HOLD …» 꼴로 정규화한 뒤 다시(fail-closed)";;
    3:DUP-ENTRY*) _da_refuse "$to" "같은 입장 재사용 — ${fl} · 카드에 이미 «- DA 입장:» 줄이 있다(본문이 바뀌어도 막는다) · 새 라운드 r<N+1> + 새 재설계 해제가 있어야 입장";;
    3:ENTRY-WRITE-FAIL*) _da_refuse "$to" "입장 기록 쓰기 실패 — ${fl} (fail-closed · 카드 쓰기 권한 확인)";;
    3:NO-ORDER-LINE*) _da_refuse "$to" "카드 발주 줄 없음 — 카드 «## 상태» 에 «DA${stage} r${rnd} 발주 …» 줄을 먼저 쓰고 다시(${fl})";;
    3:*) _da_refuse "$to" "DA 보류 2회 — 3번째 검증 0 · 재설계(상위 master·planner 의 [재설계 해제 <카드>.md] 쪽지 + 카드 «- 재설계 해제: #seq» 줄) 또는 리서치 나노(ft-nano-spawn <카드> --agent opencode --model deepseek/deepseek-v4-flash --research) · BOOT 40 · ${fl}";;
    *) _da_refuse "$to" "DA 보류 판정기 실행 실패 rc=$rc ${fl:0:80} — fail-closed";;
  esac
}
