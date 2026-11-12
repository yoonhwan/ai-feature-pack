#!/usr/bin/env bash
# ft-autonomy-try.sh — r1745 «묻기 전에 먼저 시도» 동사 1개 + 자율 상태 1줄 (ft-autonomy.sh 가 source 한다 · 단독 실행 금지)
#   try-auto <head40> --pr <N> --repo byz|pack --card <카드> [--verdict <판정문>]
#     자율 ON 이면 ①상시 승인 D2 → ②범위 승인 S 순서로 «기존 두 명령을 그대로» 부른다(판정·분류·원장·카운터 손 0).
#     통과 = `TRY-OK via=D2|S<n> <기존 명령 끝줄>` rc 0 · 둘 다 거절 = `TRY-REJECT <D2 사유> · <S 사유>` rc 2 · 자율 OFF = `TRY-SKIP 자율 OFF` rc 3
#     둘째 줄 = 사람 말 1줄(A7) · 통과면 `SHARE <사람 말> · PR <N>` — Slack 글 꼴만 내고 실 발신 0(A8)
#     어떤 거절도 통과로 바꾸지 않는다(A4) · 시간 상한 = 기존 두 명령 각자의 상한 그대로(A5)
#   brief — 자율 상태 1줄(읽기만): `자율 ON A17 · 범위 S44 ~23:30 · 사용 0/30(code 0/10) · 상시 D2 켜짐`
#     OFF = `자율 OFF · 병합·착수는 오빠 질문` · 범위 없음·만료 = `범위 없음` · D2 꺼짐 = `상시 D2 꺼짐` · 못 읽음 = `자율 상태 확인 불가(<사유>)`(추정 0)
#     try-auto 가 보는 상태와 «같은 함수»(mode · d2_on · scope_load · scope_block)에서만 나온다 — 사본 0
. "$HERE/ft-autonomy-standing-d2.sh"   # d2_on·scope_load·scope_block 재사용(이 파일은 쓰기 0 · 판정 규칙 손 0)

try_usage() { echo "TRY-REJECT $1 (usage: try-auto <head40> --pr <N> --repo byz|pack --card <카드> [--verdict <판정문>])" >&2; exit 2; }
try_last() { grep -v '^[[:space:]]*$' | tail -1; }   # 기존 명령 stdout 끝줄
try_why() {   # <stderr 파일> — 첫 줄에서 명령 표식만 떼어 «사유 1줄»
  local l; l="$(grep -v '^[[:space:]]*$' "$1" | head -1)"
  l="${l#STANDING-REJECT }"; l="${l#SCOPE-REJECT }"; l="${l#REJECT }"; printf '%s' "$l"
}
try_person() {  # <via> — A7 사람 말 1줄(내부 번호는 괄호 안에만)
  case "$1" in D2) echo "범위 안 · 질문 없이 진행(상시 D2)" ;; *) echo "범위 안 · 질문 없이 진행(범위 $1)" ;; esac
}
try_root() {   # <byz|pack> → 판정문 상대 경로의 기준(그 리포 최상위 · A10 ⓐ)
  [ "${1:-}" = pack ] || { printf '%s' "$ROOT"; return 0; }
  local h; h="$( . "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE" )" || { printf '%s' "$ROOT"; return 0; }
  git -C "$h" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$h"
}
try_verdict() { [ "${1#/}" != "$1" ] && printf '%s' "$1" || printf '%s/%s' "$(try_root "$2")" "$1"; }
try_sha_missing() {  # <판정문> — 파일이 있는데 «승인 sha:» 줄 0 = D2 판정문 꼴 아님(A10 ⓑ)
  [ -f "$1" ] && [ "$(grep -cE '^[-*]?[[:space:]]*승인 sha:[[:space:]]*[0-9a-f]{40}[[:space:]]*$' "$1")" = 0 ]
}

cmd_try_auto() {
  local head="${1:-}" pr="" rk="" card="" vf="" d2r="" sr="" o e via="" last="" ok=0
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || try_usage "sha 형식 틀림(40hex 소문자): $head"; shift
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || try_usage "$1 값 없음"
    case "$1" in
      --pr) [[ "$2" =~ ^[0-9]+$ ]] || try_usage "--pr 값 틀림: $2"; pr="$2" ;;
      --repo) rk="$2" ;; --card) card="$2" ;; --verdict) vf="$2" ;;
      *) try_usage "알 수 없는 인자: $1" ;;
    esac; shift 2
  done
  [ -n "$pr" ] && [ -n "$card" ] || try_usage "--pr·--card 필수"
  case "$rk" in byz|pack) ;; *) try_usage "--repo 는 byz|pack(받은 값: ${rk:-없음})" ;; esac
  [ "$(mode)" = on ] || { printf 'TRY-SKIP 자율 OFF\n자율 OFF · 오빠 질문\n'; return 3; }   # ④ 자율 OFF = Slack 길 · D2·S 호출 0
  o="$(mktemp)"; e="$(mktemp)"
  if [ -n "$vf" ] && d2_on; then   # ① 상시 승인 D2 먼저 — 기존 명령 그대로
    vf="$(try_verdict "$vf" "$rk")"
    if try_sha_missing "$vf"; then d2r="DA 판정문 D2 꼴 아님(승인 sha: 줄 0)"
    elif bash "$HERE/ft-autonomy.sh" standing-approve D2 "$head" --pr "$pr" --repo "$rk" --verdict "$vf" --card "$card" >"$o" 2>"$e"; then
      ok=1; via=D2; last="$(try_last < "$o")"
    else d2r="$(try_why "$e")"; fi
  else
    if [ -n "$vf" ]; then d2r="상시 승인 D2 꺼짐"; else d2r="판정문 없음(--verdict)"; fi
  fi
  if [ "$ok" = 0 ]; then   # ② 범위 승인 S — D2 가 없거나 거절일 때만
    if bash "$HERE/ft-autonomy.sh" scope-approve "$head" --pr "$pr" --card "$card" --repo "$rk" >"$o" 2>"$e"; then
      ok=1; via="S?"; scope_load 2>/dev/null && via="$G_S"; last="$(try_last < "$o")"
    else sr="$(try_why "$e")"; fi
  fi
  rm -f "$o" "$e"
  if [ "$ok" = 1 ]; then printf 'TRY-OK via=%s %s\nSHARE %s · PR %s\n' "$via" "$last" "$(try_person "$via")" "$pr"; return 0; fi   # A2 · A8
  d2r="${d2r:-거절}"; sr="${sr:-거절}"
  printf 'TRY-REJECT %s · %s\n범위 밖 · 오빠 질문 — %s · %s\n' "$d2r" "$sr" "$d2r" "$sr"; return 2   # A1③ · A7
}

cmd_brief() {
  local m ev u s=""
  [ -d "$STATE" ] && [ -r "$STATE" ] || { echo "자율 상태 확인 불가(상태 폴더 없음: $STATE)"; return 0; }   # 못 읽음 = 추정 0
  m="$(mode)"
  case "$m" in
    on) ;;
    tamper) echo "자율 상태 확인 불가(위변조)"; return 0 ;;
    *) echo "자율 OFF · 병합·착수는 오빠 질문"; return 0 ;;
  esac
  ev="$(jfield event)"
  if scope_load 2>/dev/null && { scope_block; [ -z "$BLOCK" ]; }; then   # 살아 있는 범위만 «범위」로 센다
    s="범위 $G_S ~$(hhmm "$G_UNTIL") · 사용 $(scope_used "$G_S")/$G_MAX"
    [ "${G_CODEMAX:-0}" -gt 0 ] && s="$s(code $(scope_code_used "$G_S")/$G_CODEMAX)"
  else s="범위 없음"; fi
  if d2_on; then echo "자율 ON $ev · $s · 상시 D2 켜짐"; else echo "자율 ON $ev · $s · 상시 D2 꺼짐"; fi
}
