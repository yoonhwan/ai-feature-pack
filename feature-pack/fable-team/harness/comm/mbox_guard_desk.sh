#!/bin/bash
# mbox_guard.sh 가 source 하는 문 ⑥ 본체 — desk 창구 고정(r660 · 판정 1125 · 200줄 규칙 분리 · 단독 실행 0 · DIR·GUARD_STATE·guard_log·_seats_json·_ft_live_bin 은 mbox_guard.sh·lib 가 둔다).
# 규칙은 «판정기 하나» = ft_desk_route_gate.py — 키트 ft-mbox.py(다른 쪽지 길)가 같은 파일을 부른다(두 벌 금지 · 카드 ⓖ).
#   ⓐ desk → planner 팀 밖 REJECT · ⓑ planner 팀 밖 → desk REJECT(사유 문구는 판정기 한 곳에만) · 예외 = [HIL] · «[h<N> 결과]» 1줄 ∧ planner 발신 기록 · 도구 발신(ft-*) · slack-* · desk 계보 인계
#   ⓓ 명부 없음·깨짐·_desk 칸 없음 = 판정 0(통과 + 판정기 stderr WARN 그대로 — 조용히 막지 않는다 · 카드 ⓕ)
# 판정기 부재·실행 실패 = desk 가 걸린 쪽지(to·from 이름에 -desk-)만 REJECT(설치 순서 · fail-closed), 그 밖은 통과 — 통신 전체를 세우지 않는다.
# relay 도 같은 판정(카드 ⓖ) — 판정 재료 = «큐에 실리는 본문»(요약)뿐. 첨부 원문은 받는 쪽이 전문으로 읽는다(합치면 «1줄» 판정이 어긋난다).
_desk_refuse() { guard_log mbox-guard-desk.log "REJECT to=$1 from=$2 ${3:0:120}"; echo "REJECT $3" >&2; return 3; }
_desk_install_refuse() { guard_log mbox-guard-desk.log "REJECT to=$1 from=$2 판정기 없음"; echo "REJECT desk 경로 판정기 없음 — $3 (설치 순서 · desk 쪽지 통과 0)" >&2; return 3; }

# _guard_desk_lint <수신자> <본문> <발신자> [relay 첨부] — rc 3 = REJECT.
_guard_desk_lint() {
  local to="$1" body="$2" from="${3:-}" attach="${4:-}" tool res rc line tmp mb
  case "$to$from" in *-desk-*) ;; *) return 0;; esac   # desk 무관 = 판정 0(판정기도 같은 결론 — 빨리 끝낸다)
  tool="$(_ft_live_bin ft_desk_route_gate.py 2>&1)" || { _desk_install_refuse "$to" "$from" "$tool"; return $?; }
  tmp="$(mktemp "${TMPDIR:-/tmp}/ft-desk-route.XXXXXX")" || { _desk_install_refuse "$to" "$from" "임시 파일 실패"; return $?; }
  printf '%s' "$body" > "$tmp"
  mb="${FT_MBOX_DIR:-$DIR}"   # 보낸 로그(mailbox.log.jsonl) 자리 = 우편함 자리(설치 = $DIR · 시험·명시 = FT_MBOX_DIR)
  res="$("$tool" --to "$to" --from "$from" --body-file "$tmp" --seats-dir "$(dirname "$(_seats_json)")" --comm "$mb" 2>&1)"; rc=$?
  rm -f "$tmp"
  while IFS= read -r line; do
    case "$line" in
      WARN\ *) echo "$line" >&2;;
      REJECT\ *) _desk_refuse "$to" "$from" "${line#REJECT }"; return 3;;
    esac
  done <<< "$res"
  case "$rc" in
    0) return 0;;
    3) _desk_refuse "$to" "$from" "desk 경로 판정 실패(사유 줄 없음) · $res";;
    *) _desk_install_refuse "$to" "$from" "판정기 실행 실패 rc=$rc · ${res:0:120}";;
  esac
}
