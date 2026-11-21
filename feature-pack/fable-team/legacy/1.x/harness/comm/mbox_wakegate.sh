#!/bin/bash
# mbox.sh 가 source 하는 «깨움 게이트» (r1476 · 예산은 mbox_wakebudget.sh). 단독 실행 0 — DIR·SELF·MBOXPY·_seats_json 은 mbox.sh/mbox_doorbell.sh 가 정한다.
#   doorbell_gate <좌석> <머리>   : enqueue «전» 판정 → sent | held | budget | quiet (seq 는 py 가 그 뒤에 발급한다 — 판정에 seq 가 없다)
#   doorbell_record_held <좌석> <seq> <사유> : 억제분 seq 를 state/doorbell-held/<좌석> 에 적는다(닫는 사건 = 후속 doorbell 뒤 삭제)
#   doorbell_followup_sweep             : 창이 끝난 억제분에 «후속 doorbell 1회» → doorbell=sent 일 때만 파일 삭제
# ★왜 send 한 곳인가★ — 깨움은 doorbell 한 곳에서만 나간다. 그 «앞»에 판정을 두면 «쪽지 N통 = 깨움 N회» 가 «쪽지 N통 = 깨움 1회» 가 된다.
# ★왜 fail-closed 인가★ — 예산 소진·장부 손상·잠금 초과는 «울리지 않는다»(budget). 반대로 «미읽음 수 조회» 실패는 울리는 쪽(sent)이다
#   — 안 울려 못 받는 쪽이 더 나쁘다(mbox_doorbell.sh:75 와 같은 원칙 · no_silent_fallback).
# 본문 머리(첫 `[...]`) — 여러 낱말 머리(`[완료 보고]`)까지 정확히 잡는다(첫 토큰만 보면 «[완료» 가 된다).
#   r1829 B1 — 회신 불요 머리 5개 + «첫 줄» 의 «회신 불요»(둘째 줄 아래는 보지 않는다 · 앞 머리가 있으면 그 머리가 이긴다) = [회신 불요] → quiet.
_wg_head() { local b="$1" h; for h in '[받음]' '[전파]' '[정보]' '[독려]' '[참고]' '[완료 보고]' '[정지 레디]' '[정리]' '[회신]' '[긴급]' '[인계]' '[레디]' '[HIL]' '[결정]' '[질문]' '[완료]'; do case "$b" in "$h"*) printf '%s' "$h"; return 0;; esac; done; case "${b%%$'\n'*}" in *"회신 불요"*) printf '[회신 불요]';; esac; return 0; }
# r1829 B3 — quiet 첫 적재 시각·그때 doorbell 스탬프를 state/doorbell-quiet/<좌석> 에 남긴다(gate = subshell · 파일이라야 sweep 이 본다 · 있으면 그대로).
_wg_quiet_mark() { local d f; d="$(_wg_state)/doorbell-quiet"; f="$d/$(_wg_key "$1")"; [ -f "$f" ] && return 0; mkdir -p "$d" 2>/dev/null
  printf 'quiet ts=%s seat=%s last=%s\n' "$(_wg_now)" "$1" "$(stat -f %m "${TMPDIR:-/tmp}/mbox-doorbell-$(_wg_key "$1")" 2>/dev/null || echo 0)" > "$f" 2>/dev/null; return 0; }

# ★사람 글 판정★ — 예산 밖 즉시(발주·[HIL] 과 같은 등급). 좁게 잡는다: 미등록 좌석은 사람이 «아니다»(예산 우회 0).
#   근거 = planner desk(`seats-planner.json _master`) 와 사람 표식 이름(slack-*·*-oppa).
_wg_human_sender() {
  local f="$1"
  if user_facing "$f"; then return 0; fi
  case "$f" in slack-*|*-oppa|oppa) return 0;; esac
  return 1
}

# ── 억제분 기록 — state/doorbell-held/<좌석>. 첫 줄 `held ts= reason= window= seat=`, 그 뒤 `seq=<N>` 줄. ──
doorbell_record_held() {
  local seat="$1" seq="$2" why="$3" d f now win
  case "$why" in held|budget) ;; *) return 0;; esac
  d="$(_wg_state)/doorbell-held"
  mkdir -p "$d" 2>/dev/null || { echo "WARN held 기록 실패 — $d" >&2; return 0; }
  f="$d/$(_wg_key "$seat")"
  now="$(_wg_now)"; win=$(( now / 3600 ))
  if [ ! -f "$f" ]; then
    printf 'held ts=%s reason=%s window=%s seat=%s\n' "$now" "$why" "$win" "$seat" > "$f" 2>/dev/null \
      || { echo "WARN held 기록 실패 — $f" >&2; return 0; }
  fi
  case "$seq" in
    ''|*[!0-9]*) return 0;;
  esac
  grep -qx "seq=$seq" "$f" 2>/dev/null || printf 'seq=%s\n' "$seq" >> "$f" 2>/dev/null || true
  return 0
}

# 억제분의 닫는 사건 ⓐ — recv 가 전부 읽었으면(남은 큐 0) 파일 삭제. 남았으면 다음 sweep 이 잡는다.
#   r1829 fix1 — quiet 기록도 여기서 닫는다(빈 큐 뒤 새 quiet = 새 묶음 · 옛 ts 로 즉시 깨움 0).
doorbell_clear_held() {
  local f; f="$(_wg_state)/doorbell-held/$(_wg_key "$1")"
  [ -f "$f" ] && rm -f "$f" 2>/dev/null
  rm -f "$(_wg_state)/doorbell-quiet/$(_wg_key "$1")" 2>/dev/null
  return 0
}

# ── send 게이트: ①머리 종류 ②예산 원자 예약 ③미읽음 수(새 쪽지 제외 = 호출이 enqueue «전» 이라 자동) ──
#   echoes: sent | held | budget | quiet. 판정 실패 경로는 «울리는 쪽»(sent) 아니면 «안 울리는 쪽»(budget) 하나로 못 박는다(중간 없음).
doorbell_gate() {
  local seat="$1" head="$2" out rc p pn stamp last now
  case "$head" in
    '[받음]'|'[전파]'|'[정보]'|'[독려]'|'[참고]'|'[회신 불요]'|'[정리]'|'[회신]'|'[완료 보고]') _wg_quiet_mark "$seat"; printf 'quiet'; return 0;;   # 보고·회신 불요 = 큐만(예산 0)
    '[긴급]'|'[인계]'|'[레디]')      printf 'sent'; return 0;;          # 즉시 · 예산 밖(기존 force 경로 그대로)
  esac
  out="$(wake_budget_reserve "$seat" send)"; rc=$?
  if [ "$rc" != 0 ]; then printf 'budget'; return 0; fi                    # 소진·장부 손상·잠금 초과 = fail-closed
  if [ -n "${FT_MBOX_PEEK_CMD:-}" ]; then p="$(_wg_timeout 7 $FT_MBOX_PEEK_CMD "$seat" 2>/dev/null)"; rc=$?
  else p="$(_wg_timeout 7 python3 "$MBOXPY" peek "$seat" 2>/dev/null)"; rc=$?; fi
  pn=""
  if [ "$rc" = 0 ]; then pn="$(printf '%s\n' "$p" | sed -n 's/^pending=\([0-9][0-9]*\).*/\1/p' | head -1)"; fi
  if [ -z "$pn" ]; then
    echo "WARN 미읽음 판정 불가 — 예산 안 doorbell ($seat)" >&2
    printf 'sent'; return 0                                                  # 예약은 됐다 = 예산 안
  fi
  stamp="${TMPDIR:-/tmp}/mbox-doorbell-$(_wg_key "$seat")"
  now="$(_wg_now)"
  last="$(stat -f %m "$stamp" 2>/dev/null || echo 0)"
  # 미읽은 쪽지가 있고 «마지막 doorbell 이 5분 안» 이면 한 번 울린 것으로 충분하다 — 대신 억제분을 적어 둔다.
  if [ "$pn" -ge 1 ] && [ "$last" -gt 0 ] && [ "$(( now - last ))" -lt "${FT_MBOX_WAKE_HOLD_SEC:-300}" ]; then
    wake_budget_refund "$seat" send >/dev/null 2>&1 || true                # 안 울렸으니 차감 되돌린다
    printf 'held'; return 0
  fi
  printf 'sent'; return 0
}

# ── r2378 K1·K2·K3 — 세션 없는 좌석의 깨움 기록을 done/ 으로 닫는다(예약·ring 0). 근거 = 죽은 좌석 기록이 send 마다 예약·ring·환불을 되풀이해 결과 줄이 7초를 넘겼다(실측 25초 끊김). ──
#   ★목록은 sweep 1회에 한 번★ — 기록마다 tmux 를 부르면 죽은 기록 N개에 tmux N번이고 7초 상한 계산이 흔들린다(DA#52 H3).
#   ★rc 를 본다★ — pane_of 는 tmux rc 를 버려(2>/dev/null | awk) 서버 없음도 absent 로 본다. 그 길로 닫으면 안 되므로 판정을 따로 둔다(K2).
_WG_SOK=0; _WG_TRIED=0; _WG_SESS=""
_wg_session_list() {
  local out rc
  out="$(_wg_timeout 7 tmux list-panes -a -F '#{session_name}' 2>/dev/null)"; rc=$?
  if [ "$rc" != 0 ]; then echo "판정 불가 tmux 목록 실패 — 기록 유지" >&2; _WG_SOK=0; return 1; fi
  _WG_SESS="$out"; _WG_SOK=1; return 0
}
# 처음 필요할 때 1회만 — 기록 0 이면 tmux 호출도 0(send 지연에 새 몫 0).
_wg_list_once() { [ "$_WG_TRIED" = 1 ] && return 0; _WG_TRIED=1; _wg_session_list; }
# ★정확히 같은 이름으로만 잰다★ — `tmux has-session -t <이름>` 은 접두어로도 맞아서 죽은 `X#5` 가 산 `X#52` 때문에 «있음» 이 된다(DA#52 H3).
#   `<이름>|<pane>` 꼴(pane_of · 옛 스텁)도 같은 이름으로 읽는다 — `|` 뒤는 버린다.
_wg_session_has() { local s; while IFS= read -r s; do [ "${s%%|*}" = "$1" ] && return 0; done <<<"$_WG_SESS"; return 1; }
# K2 — holder 직접 호출 + rc + 7초. rc≠0·빈 값 = 판정 불가(holder_of 본문은 손대지 않는다 — mbox.sh:197 은 실패해도 받은 이름을 rc 0 으로 돌려준다 · DA#52 H1).
_wg_holder_rc() { local h; h="$(_wg_timeout 7 python3 "$MBOXPY" holder "$1" 2>/dev/null)" || h="";
  [ -n "$h" ] || { echo "판정 불가 holder 실패 — 기록 유지" >&2; return 1; }
  printf '%s' "$h"; }
# 세션 없음 = 0(닫는다) · 있음 = 1 · 판정 불가 = 2. stdout 0(부르는 쪽 출력줄 오염 0).
_wg_seat_absent() { local h; h="$(_wg_holder_rc "$1")" || return 2; _wg_session_has "$h" && return 1; return 0; }
# K3 — held·quiet 둘 다 `<state>/doorbell-held/done/` 한 곳(r1665 와 같은 폴더) · 이름이 있으면 `-1` `-2` … 빈 이름을 찾음 · mv(-f·-n 0) · 옮긴 뒤 «원 자리 없음 ∧ 대상 있음».
#   ★mv -f 는 덮어쓰고 macOS mv -n 은 안 옮기고 rc 0★(DA#52 H2 실측) — 그래서 둘 다 쓰지 않고 빈 이름을 먼저 찾는다.
_wg_stamp() { date -r "$1" +%Y%m%dT%H%M%S 2>/dev/null || date -d "@$1" +%Y%m%dT%H%M%S 2>/dev/null || date +%Y%m%dT%H%M%S; }
_wg_close_record() {  # <기록 파일> <좌석> [quiet] → 옮겼으면 0 · 실패 = stderr 1줄 + rc 1(부르는 쪽이 이번 sweep 에서 peek·예약·ring 0 · 다음 sweep 재시도)
  local f="$1" seat="$2" kind="${3:-}" d base dest n
  d="$(_wg_state)/doorbell-held/done"; mkdir -p "$d" 2>/dev/null || true
  base="$(_wg_key "$seat")-$(_wg_stamp "$(_wg_now)")"
  [ "$kind" != quiet ] || base="$(_wg_key "$seat")-quiet-$(_wg_stamp "$(_wg_now)")"
  dest="$d/$base"; n=1
  while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$d/$base-$n"; n=$((n + 1)); done
  if mv "$f" "$dest" 2>/dev/null && [ ! -e "$f" ] && [ -e "$dest" ]; then return 0; fi
  echo "WARN 깨움 기록 닫기 실패 $f" >&2
  [ -e "$f" ] || mv "$dest" "$f" 2>/dev/null || true    # 반쯤 옮겼으면 되돌린다(기록 그대로 = 다음 sweep 재시도)
  return 1
}

# ── 후속 sweep — 창(5분 · 또는 시각 창)이 끝난 억제분에 doorbell 1회. 삭제는 doorbell=sent 일 때만. ──
#   부르는 곳: send·relay 마다 1회 + CLI `mbox.sh sweep`(r1480 감지기 300초가 부른다 — send 가 없어도 재개).
#   ★예약 소유자 = 이 함수★ — ring 은 `--reserved` 로 부른다(깨움 1회 = 차감 1회 · 이중 차감 0).
doorbell_followup_sweep() {
  local d f ts why win now cur seat seqs lastseq out arc res rr fu="" nudge uw
  d="$(_wg_state)/doorbell-held"
  _WG_TRIED=0; _WG_SOK=0                                                    # 세션 목록 = 이 sweep 1회(아래 _wg_list_once)
  [ -d "$d" ] || { fu="$(_wg_quiet_sweep)"; [ -z "$fu" ] || printf '%s\n' "${fu# }"; return 0; }
  now="$(_wg_now)"; cur=$(( now / 3600 ))
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    ts="$(_wg_kv "$f" ts)"; why="$(_wg_kv "$f" reason)"; win="$(_wg_kv "$f" window)"; seat="$(_wg_kv "$f" seat)"
    case "$ts" in ''|*[!0-9]*) continue;; esac
    [ -n "$seat" ] || seat="$(basename "$f")"
    case "$why" in
      held)   [ "$(( now - ts ))" -ge "${FT_MBOX_WAKE_FOLLOWUP_SEC:-300}" ] || continue;;
      budget) [ -n "$win" ] && [ "$cur" != "$win" ] || continue;;
      *)      continue;;
    esac
    # r2378 K1 — 창이 끝난 기록이 «세션 없는 좌석» 이면 예약·ring 전에 닫는다. ring 갈래만(K4: user_facing·ext_wake_seat 은 nudge 갈래 그대로 = 아래 uw 갈래).
    uw=0; if user_facing "$seat" || ext_wake_seat "$seat"; then uw=1; fi
    if [ "$uw" = 0 ]; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat"; then fu="$fu closed=$seat via=absent"; fi
        continue                                                           # mv 실패도 이번 sweep 은 닫기만(peek·예약·ring 0 · K3)
      fi
    fi
    seqs="$(sed -n 's/^seq=\([0-9][0-9]*\)$/\1/p' "$f" 2>/dev/null | tail -1)"
    lastseq="${seqs:-}"
    out="$(wake_budget_reserve "$seat" followup)"; arc=$?
    [ "$arc" = 0 ] || continue                                             # 소진 = 그대로 둔다(다음 창)
    nudge=0; res=""
    if [ "$uw" = 1 ]; then                                                        # planner 대면(pi)·확장 감시 좌석 — pane 주입 0 · nudge 파일로 알린다(r1477 ⑦ · r1524 · r2378 K4 = K1 밖)
      mkdir -p "$(_wg_state)/pi-wake" 2>/dev/null
      if : >> "$(_wg_state)/pi-wake/$(_wg_key "$seat").nudge" 2>/dev/null; then nudge=1; fi
      res=sent
    else
      rr="$(bash "$SELF" ring "$seat" "$lastseq" --reserved 2>/dev/null)" || rr="doorbell=error"
      case "$rr" in *doorbell=sent*) res=sent;; *) res="$(printf '%s\n' "$rr" | sed -n 's/.*doorbell=\([a-z]*\).*/\1/p' | head -1)";; esac
      res="${res:-error}"
    fi
    if [ "$res" = sent ]; then
      rm -f "$f" 2>/dev/null || true
      if [ "$nudge" = 1 ]; then fu="$fu followup=$seat via=nudge"; else fu="$fu followup=$seat"; fi
    else
      # 전달 실패 = 보존 + 환불 + 흔적 1줄(stderr 0 — 다음 sweep 재시도).
      printf 'last_err=%s %s\n' "$res" "$now" >> "$f" 2>/dev/null || true
      wake_budget_refund "$seat" followup >/dev/null 2>&1 || true
    fi
  done
  fu="$fu$(_wg_quiet_sweep)"
  [ -z "$fu" ] || printf '%s\n' "${fu# }"
  return 0
}
# r1829 B3 굶김 상한 — 다른 깨움(스탬프 바뀜)·큐 0 = 기록만 지움 · 첫 적재 ≥ FT_MBOX_QUIET_MAX_SEC(1800) · 미읽음 ≥ FT_MBOX_QUIET_MAX_N(8) · 판정 불가 = doorbell 1회(예산 안).
_wg_quiet_sweep() { local f seat ts p pn now uw; now="$(_wg_now)"
  for f in "$(_wg_state)/doorbell-quiet"/*; do
    [ -f "$f" ] || continue; seat="$(_wg_kv "$f" seat)"; ts="$(_wg_kv "$f" ts)"; [ -n "$seat" ] || continue; case "$ts" in ''|*[!0-9]*) ts=0;; esac
    [ "$(stat -f %m "${TMPDIR:-/tmp}/mbox-doorbell-$(_wg_key "$seat")" 2>/dev/null || echo 0)" = "$(_wg_kv "$f" last)" ] || { rm -f "$f"; continue; }
    # r2378 K1 — 세션 없는 좌석 기록은 peek·예약·ring «전» 에 닫는다(DA#52 H3). peek 갈래 뒤에 두면 죽은 기록도 peek 비용을 다 낸다. ring 갈래만(K4).
    uw=0; if user_facing "$seat" || ext_wake_seat "$seat"; then uw=1; fi
    if [ "$uw" = 0 ]; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat" quiet; then printf ' closed=%s via=absent' "$seat"; fi
        continue
      fi
    fi
    if [ -n "${FT_MBOX_PEEK_CMD:-}" ]; then p="$(_wg_timeout 7 $FT_MBOX_PEEK_CMD "$seat" 2>/dev/null)"; else p="$(_wg_timeout 7 python3 "$MBOXPY" peek "$seat" 2>/dev/null)"; fi
    pn="$(printf '%s\n' "$p" | sed -n 's/^pending=\([0-9][0-9]*\).*/\1/p' | head -1)"; [ "$pn" != 0 ] || { rm -f "$f"; continue; }
    [ -z "$pn" ] || [ "$(( now - ts ))" -ge "${FT_MBOX_QUIET_MAX_SEC:-1800}" ] || [ "$pn" -ge "${FT_MBOX_QUIET_MAX_N:-8}" ] || continue
    wake_budget_reserve "$seat" followup >/dev/null 2>&1 || continue
    case "$(bash "$SELF" ring "$seat" --reserved 2>/dev/null)" in *doorbell=sent*) rm -f "$f"; printf ' followup=%s via=quiet' "$seat";;
      *) wake_budget_refund "$seat" followup >/dev/null 2>&1 || true;; esac
  done; return 0; }
