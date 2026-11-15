#!/usr/bin/env bash
# ft-autonomy-scope-alert.sh — 범위 승인 소진 경보 (r1792 · 오빠 지시 11-13 재발방지 B · S45 사건) — ft-autonomy-scope.sh 가 source 한다(단독 실행 금지)
#   scope_zero_tail   scope_load 뒤 · scope-status 살아 있는 줄의 `]` 앞 꼬리 — 전체 남은 0 = ` · 새 승인 없이 0건(전체 한도)`
#                     하루 남은 0 ∧ 끝 < 다음 빈자리(최근 24시간 창의 센 scope-use 중 가장 이른 시각 + 86400) = ` · 새 승인 없이 0건(끝 MM-DD HH:MM < 빈자리 MM-DD HH:MM)` · 그 밖 = 빈 값
#   scope-alert       사용률(전체·오늘·code) 하나라도 ≥75% → desk 에 [긴급] 1통 · `SCOPE-ALERT-SENT …` · 그 밖·범위 없음·정지 = `SCOPE-ALERT-NONE` rc0(쪽지 0)
#                     중복 억제 장부 $SDIR/alert.sent(일반 파일 · 추가 전용) 키 = `S<n> <total|daily|code> <YYYYMMDD>` + `S<n> zero`(0건 꼬리가 처음 생길 때 1통 더)
#                     발신 실패·desk 못 찾음 = 장부 쓰기 0 · rc1 «판정 불가» 1줄(다음 틱 재시도) · 새 승인 자동 발급 0(경보 = «준비하라» 신호뿐)
SCOPE_ALERT_PCT=75   # 오빠 지시 값 그대로(env 로 안 바꾼다 · 바꾸려면 PR)

scope_next_slot() {  # <S> → 최근 24시간 창의 센 scope-use(revert·equiv 뺌) 중 가장 이른 시각 + 86400 · 없으면 빈 값
  awk -v s="$1" -v c="$(( $(now_epoch) - 86400 ))" '$1=="scope-use" && $2==s && $4!="revert" && $4!="equiv" && $5>c && (m=="" || $5+0<m) {m=$5+0} END{if (m!="") print m+86400}' "$LOG" 2>/dev/null
}

scope_zero_tail() {  # scope_load 뒤 → stdout = 꼬리(없으면 빈 값)
  local nx
  [ "$(scope_used "$G_S")" -ge "$G_MAX" ] && { printf ' · 새 승인 없이 0건(전체 한도)'; return 0; }
  [ "$(scope_today "$G_S")" -ge "$G_DAILY" ] || return 0
  nx="$(scope_next_slot "$G_S")"; [ -n "$nx" ] && [ "$G_UNTIL" -lt "$nx" ] || return 0
  printf ' · 새 승인 없이 0건(끝 %s < 빈자리 %s)' "$(fmt "$G_UNTIL" '%m-%d %H:%M')" "$(fmt "$nx" '%m-%d %H:%M')"
}

scope_alert_desk() {  # interview_note 와 같은 길 → SA_DESK · FT_AUTONOMY_DESK → $ROOT 명부 → 공용 루트 명부 · 못 찾으면 rc1
  local rr p; SA_DESK="${FT_AUTONOMY_DESK:-}"; [ -z "$SA_DESK" ] || return 0
  rr="$(_roster_common_root "$ROOT")" || rr=""
  for p in "$ROOT/.fable-team/seats-planner.json" "${rr:+$rr/.fable-team/seats-planner.json}"; do
    [ -f "$p" ] || continue
    SA_DESK="$(python3 -c 'import json,sys;v=json.load(open(sys.argv[1])).get("_desk");print(v if isinstance(v,str) else "")' "$p" 2>/dev/null)"
    [ -z "$SA_DESK" ] || return 0
  done; return 1
}

cmd_scope_alert() {
  local f="$SDIR/alert.sent" day tail e k lab n m p best=-1 msg="" keys=() mb body
  scope_load || { echo "SCOPE-ALERT-NONE"; return 0; }
  scope_block; [ -z "$BLOCK" ] || { echo "SCOPE-ALERT-NONE"; return 0; }
  day="$(fmt "$(now_epoch)" %Y%m%d)"; tail="$(scope_zero_tail)"
  set -- "total 전체 $(scope_used "$G_S") $G_MAX" "daily 오늘 $(scope_today "$G_S") $G_DAILY"
  [ "$G_CODEMAX" -gt 0 ] && set -- "$@" "code code $(scope_code_used "$G_S") $G_CODEMAX"
  for e in "$@"; do
    read -r k lab n m <<<"$e"; p=$(( n * 100 / m )); [ "$p" -ge "$SCOPE_ALERT_PCT" ] || continue
    [ "$p" -gt "$best" ] && { best="$p"; msg="${p}%($lab $n/$m)"; }
    grep -qxF "$G_S $k $day" "$f" 2>/dev/null || keys+=("$G_S $k $day")
  done
  [ -z "$tail" ] || grep -qxF "$G_S zero" "$f" 2>/dev/null || keys+=("$G_S zero")
  [ ${#keys[@]} -gt 0 ] && [ -n "$msg" ] || { echo "SCOPE-ALERT-NONE"; return 0; }
  scope_alert_desk || { echo "WARN 판정 불가 — 범위 경보 못 보냄: desk 못 찾음(FT_AUTONOMY_DESK · planner 명부 _desk)" >&2; return 1; }
  mb="${FT_AUTONOMY_MBOX:-}"; [ -n "$mb" ] || mb="$(. "$HERE/ft-harness-root.sh" && ft_comm_dir "$HERE")/mbox.sh" || { echo "WARN 판정 불가 — 범위 경보 못 보냄: 우편함 못 풂" >&2; return 1; }
  body="[긴급] 범위 승인 $G_S 사용률 $msg · 끝 $(fmt "$G_UNTIL" '%m-%d %H:%M')$tail → 새 승인 h 준비"
  perl -e 'alarm 25; exec @ARGV' -- bash "$mb" send "$SA_DESK" ft-autonomy "$body" >/dev/null 2>&1 || { echo "WARN 판정 불가 — 범위 경보 못 보냄: mbox send rc≠0 → $SA_DESK" >&2; return 1; }
  { mkdir -p "$SDIR" && printf '%s\n' "${keys[@]}" >> "$f"; } || { echo "WARN 판정 불가 — 경보 장부 쓰기 실패: $f" >&2; return 1; }
  echo "SCOPE-ALERT-SENT $G_S $msg$tail → $SA_DESK"
}
