#!/usr/bin/env bash
# ft-seat-handover.sh — 승계 때 오빠 탭(tmux 클라이언트) 이관 + 은퇴 좌석 판정 (R30)
#   snapshot <구> <후계>                 후계 open «직전» 구 세션 클라이언트를 장부에 pending 으로 기록
#   apply <구> <후계>                    후계 부팅 보고 «수신» 뒤 — follow 탭만 switch-client (identity 3중 재확인)
#   apply <구> <후계> --client <tty> --confirmed-by <쪽지 seq>   legacy·ambiguous 단발(HIL 값 근거 필수)
#   status [<세션>]                      ACTIVE | RETIRED <X> | MISMATCH ... (세션 생략 = $TMUX_PANE 의 세션)
# 근거: design/harness/DESIGN-r30-succession-window-handover-20261008.md §2 r2 + §6 · 판정문 DA-r30-handover-20261008.md
# env: FT_ROOT · FT_HANDOVER_LEDGER(장부 jsonl) · FT_SEATS_JSON(명부 1개 고정; 없으면 .fable-team/seats*.json 전부) · FT_MBOX · FT_HIL_ROUTE
# 금지: 구 세션 kill · T0 클라이언트 2개 이상 자동 전환 · 이름 문자열로 후계 추측 · 오빠께 질문 발신
set -uo pipefail
ROOT="${FT_ROOT:-}"; [ -n "$ROOT" ] || { HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; . "$HERE/ft-harness-root.sh"; ROOT="$(ft_data_root "$HERE")"; } || exit 1   # r385 r3: 설치본(git 밖)의 ../.. 는 데이터 루트가 아니다
LEDGER="${FT_HANDOVER_LEDGER:-$ROOT/.fable-team/state/handover.jsonl}"
MBOX="${FT_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
die() { echo "ft-seat-handover: $2" >&2; exit "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
append() { mkdir -p "$(dirname "$LEDGER")" && printf '%s\n' "$1" >> "$LEDGER"; }
lines_to_json() { jq -R -s -c "$1"; }   # stdin 줄들 → JSON 배열(변환식 $1)

# 명부 키 찾기: 값의 계보(# 앞)가 <세션들> 중 하나인 `_<역할>` 키 → "<파일>\t<키>\t<값>" (없으면 빈 출력)
roster_of() {
  local f files bs
  bs="$(printf '%s\n' "$@" | sed 's/#.*//' | jq -R -s -c 'split("\n")|map(select(length>0))')"
  if [ -n "${FT_SEATS_JSON:-}" ]; then files=("$FT_SEATS_JSON"); else files=("$ROOT"/.fable-team/seats*.json); fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    jq -r --arg f "$f" --argjson bs "$bs" 'to_entries[]
      | select((.key|startswith("_")) and .key != "_hil_route" and (.value|type=="string") and ((.value|split("#")[0]) as $b | $bs|index($b)))
      | [$f,.key,.value]|@tsv' "$f" 2>/dev/null
  done | head -1
}

cmd_snapshot() {
  local old="${1:-}" new="${2:-}" rows arr n follow amb
  [ -n "$old" ] && [ -n "$new" ] || die 2 "usage: snapshot <구> <후계>"
  rows="$(tmux list-clients -t "=$old" -F '#{client_tty} #{client_pid} #{client_created}')" || die 1 "list-clients 실패: $old"
  arr="$(printf '%s\n' "$rows" | lines_to_json 'split("\n")|map(select(length>0)|split(" ")|{tty:.[0],pid:.[1],created:.[2]})')"
  n="$(jq 'length' <<<"$arr")"
  follow='[]'; amb='[]'
  if [ "$n" -eq 1 ]; then follow="$arr"; elif [ "$n" -ge 2 ]; then amb="$arr"; fi
  append "$(jq -cn --arg o "$old" --arg n "$new" --arg ts "$(now)" --argjson f "$follow" --argjson a "$amb" \
    '{state:"pending",old:$o,new:$n,follow:$f,ambiguous:$a,ts:$ts}')"
  echo "SNAPSHOT $old -> $new follow=$(jq length <<<"$follow") ambiguous=$(jq length <<<"$amb")"
}

client_row() { tmux list-clients -F '#{client_tty} #{client_pid} #{client_created} #{client_session}' 2>/dev/null | awk -v t="$1" '$1==t' | head -1; }

# try_move <tty> <pid|""> <created|""> <구> <후계> → moved | gone | identity-changed | moved-by-user | switch-failed
try_move() {
  local tty="$1" pid="$2" cr="$3" old="$4" new="$5" row cp cc cs
  row="$(client_row "$tty")"; [ -n "$row" ] || { echo gone; return; }
  read -r _ cp cc cs <<<"$row"
  if [ -n "$pid" ] && { [ "$cp" != "$pid" ] || [ "$cc" != "$cr" ]; }; then echo identity-changed; return; fi
  [ "$cs" = "$old" ] || { echo moved-by-user; return; }
  tmux switch-client -c "$tty" -t "=$new" 2>/dev/null || { echo switch-failed; return; }
  read -r _ _ _ cs <<<"$(client_row "$tty")"
  [ "$cs" = "$new" ] && echo moved || echo switch-failed
}

notify_ambiguous() {  # <구> <후계> <tty 목록>
  local route="${FT_HIL_ROUTE:-}" f
  if [ -z "$route" ]; then f="$(roster_of "$1" "$2" | cut -f1)"; [ -n "$f" ] && route="$(jq -r '._hil_route // empty' "$f")"; fi
  [ -n "$route" ] || { echo "ft-seat-handover: _hil_route 없음 — ambiguous 통보 못 함(tty=$3)" >&2; return 1; }
  "$MBOX" send "$route" "$1" "[handover-ambiguous] $1->$2 tty=$3 전환 보류 — 은퇴 좌석 relay 로 입력 손실 0" >/dev/null || {
    echo "ft-seat-handover: ambiguous 통보 mbox 실패 (route=$route)" >&2; return 1; }
}

cmd_apply() {
  local client="" seq="" pos=() old new r rv last mode=snapshot rc=0 amb_json='[]'
  while [ $# -gt 0 ]; do
    case "$1" in --client) client="${2:-}"; shift 2;; --confirmed-by) seq="${2:-}"; shift 2;; *) pos+=("$1"); shift;; esac
  done
  old="${pos[0]:-}"; new="${pos[1]:-}"
  [ -n "$old" ] && [ -n "$new" ] || die 2 "usage: apply <구> <후계> [--client <tty> --confirmed-by <seq>]"
  if [ -n "$client$seq" ]; then
    [ -n "$client" ] && [[ "$seq" =~ ^[0-9]+$ ]] || die 1 "--client 는 --confirmed-by <쪽지 seq(숫자)> 와 함께만 — 근거 없는 단발 이관 금지"
    mode=client
  fi
  tmux has-session -t "=$new" 2>/dev/null || die 1 "후계 세션 없음: $new"
  r="$(roster_of "$old" "$new")"; [ -n "$r" ] || die 1 "명부에 $old/$new 계보 키 없음"
  rv="$(cut -f3 <<<"$r")"; [ "$rv" = "$new" ] || die 1 "명부 불일치: $(cut -f2 <<<"$r")=$rv != $new"
  local moved=() skipped=() t p c why
  if [ "$mode" = client ]; then
    why="$(try_move "$client" "" "" "$old" "$new")"
    if [ "$why" = moved ]; then moved+=("$client"); else skipped+=("$client $why"); fi
  else
    last="$(jq -c --arg o "$old" --arg n "$new" 'select(.old==$o and .new==$n)' "$LEDGER" 2>/dev/null | tail -1)"
    [ -n "$last" ] || die 1 "snapshot 없음: $old -> $new (legacy 는 --client --confirmed-by)"
    [ "$(jq -r .state <<<"$last")" = "done" ] && { echo "OK already-done $old -> $new"; return 0; }
    amb_json="$(jq -c '.ambiguous // []' <<<"$last")"
    while IFS=$'\t' read -r t p c; do
      [ -n "$t" ] || continue
      why="$(try_move "$t" "$p" "$c" "$old" "$new")"
      if [ "$why" = moved ]; then moved+=("$t"); else skipped+=("$t $why"); fi
    done < <(jq -r '.follow[]? | [.tty,.pid,.created]|@tsv' <<<"$last")
  fi
  local mj sj tag="" amb_n amb_list
  mj="$(printf '%s\n' "${moved[@]:-}" | lines_to_json 'split("\n")|map(select(length>0))')"
  sj="$(printf '%s\n' "${skipped[@]:-}" | lines_to_json 'split("\n")|map(select(length>0)|split(" ")|{tty:.[0],reason:.[1]})')"
  append "$(jq -cn --arg o "$old" --arg n "$new" --arg ts "$(now)" --arg m "$mode" --arg s "$seq" \
    --argjson mv "$mj" --argjson sk "$sj" --argjson am "$amb_json" \
    '{state:"done",old:$o,new:$n,mode:$m,confirmed_by:(if $s=="" then null else ($s|tonumber) end),moved:$mv,skipped:$sk,ambiguous:$am,ts:$ts}')"
  tmux set-option -t "=$old" @handed_over_to "$new" 2>/dev/null || echo "ft-seat-handover: WARN @handed_over_to 캐시 설정 실패($old)" >&2
  amb_n="$(jq length <<<"$amb_json")"; amb_list="$(jq -r 'map(.tty)|join(",")' <<<"$amb_json")"
  [ "$(jq length <<<"$mj")" -eq 0 ] && [ "$(jq length <<<"$sj")" -eq 0 ] && [ "$amb_n" -eq 0 ] && tag="no-client"
  [ "$amb_n" -gt 0 ] && tag="ambiguous tty=$amb_list 전환 보류"
  [ "$(jq length <<<"$sj")" -gt 0 ] && tag="$tag $(jq -r 'map(.tty+":"+.reason)|join(" ")' <<<"$sj")"
  tag="${tag# }"
  echo "HANDOVER $old -> $new moved=$(jq length <<<"$mj") skipped=$(jq length <<<"$sj") ambiguous=$amb_n${tag:+ ($tag)}"
  [ "$amb_n" -gt 0 ] && { notify_ambiguous "$old" "$new" "$amb_list" || rc=1; }
  case "$sj" in *switch-failed*) rc=1;; esac
  return "$rc"
}

cmd_status() {
  local me="${1:-}" x r rv opt
  if [ -z "$me" ]; then
    [ -n "${TMUX_PANE:-}" ] || die 2 "세션 미지정 — 인자 또는 \$TMUX_PANE 필요(ambient 세션 오독 차단)"
    me="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')" || die 1 "display-message 실패"
  fi
  x="$(jq -r --arg o "$me" 'select(.state=="done" and .old==$o)|.new' "$LEDGER" 2>/dev/null | tail -1)"
  opt="$(tmux show-option -t "=$me" -qv @handed_over_to 2>/dev/null)"
  r="$(roster_of "$me" "${x:-$me}")"
  if [ -z "$r" ]; then
    [ -z "$x" ] && { echo ACTIVE; return; }   # 명부 좌석이 아님(나노 등)
    echo "MISMATCH ledger=$x roster=none option=${opt:-none}"; return
  fi
  rv="$(cut -f3 <<<"$r")"
  if [ -n "$x" ]; then
    if [ "$rv" = "$x" ] && tmux has-session -t "=$x" 2>/dev/null; then
      [ "$opt" = "$x" ] || tmux set-option -t "=$me" @handed_over_to "$x" 2>/dev/null
      echo "RETIRED $x"
    else
      echo "MISMATCH ledger=$x roster=$rv option=${opt:-none}"
    fi
  elif [ "$rv" = "$me" ]; then echo ACTIVE
  else echo "MISMATCH ledger=none roster=$rv option=${opt:-none}"; fi
}

sub="${1:-}"; shift || true
case "$sub" in
  snapshot) cmd_snapshot "$@";;
  apply)    cmd_apply "$@";;
  status)   cmd_status "$@";;
  *) die 2 "usage: ft-seat-handover.sh snapshot|apply|status ...";;
esac
