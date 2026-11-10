#!/usr/bin/env bash
# tmux_isolate.sh — spawn 계열 시험이 «진짜 tmux 서버»에 좌석을 남기지 않게 하는 공용 격리 1곳 (r957)
#
# 사건: 2026-10-26 13:29 시험 몇 개를 돌렸더니 실 tmux 서버에 byz-alpha-nano-x#0~#9 10석이 생겨 335분 방치됐다
#       (오빠 «테스트 환경 모두 죽이고»). 원인 = 시험이 가짜 `tmux` 만 PATH 앞에 두고 가짜 `tmuxc` 는 두지 않았고,
#       좌석(TMUX env) 안에서 돌면 클라이언트가 $TMUX 소켓으로 직행했다 — spawn 의 `tmuxc open`/`tmux has-session` 이 실 서버에 닿았다.
#
# ★구조로 닫는다(r3 재설계 · DA⑥ r2 HOLD 1)★ — 환경 변수 꾸미기에 기대지 않는다:
#   ① 준비 실패 = 시험 시작 0: 격리 폴더·소켓·진짜 tmux 경로를 못 만들면 ERROR 1줄 + exit 2(본문 진입 0).
#   ② PATH 맨 앞 `tmux` shim: 진짜 tmux 를 **늘 `-S <격리 소켓>`** 으로만 부른다. 호출자가 준 `-S`·`-L` 이
#      격리 폴더 밖이면 거절(rc≠0). 격리 값이 비면 shim 자체가 거절. → 진짜 바이너리·진짜 tmuxc 가 불려도
#      실 서버로 가는 길이 shim 단계에서 끊긴다. TMUX·TMUX_PANE·TMPDIR·TMUX_TMPDIR 이 어떤 값이어도 같다.
#   ③ 실 서버 읽기는 한 곳: 도우미가 시작 때 저장한 «진짜 tmux 절대경로 + 원래 소켓» 으로 `ls` 만 부른다
#      (tmux_isolate_real_ls). 그 밖 동사는 이 파일 어디에도 없다.
#
# 쓰는 법(시험 파일 위쪽 1줄 + 끝 1줄):
#   . "$HERE/lib/tmux_isolate.sh"   # source = 격리 시작(실패하면 그 자리에서 exit 2)
#   tmux_isolate_leak_check         # 시험 끝 — 실 서버 시험 세션이 늘었으면 FAIL 1줄 + rc1
#   tmux_isolate_end                # 격리 소켓 세션 정리(시험 trap 에서 부른다)

TMUX_ISOLATE_DIR=""
_ti_shim=""; _ti_iso_sock=""; _ti_real_tmux=""; _ti_sock="${TMUX-}"; _ti_sock="${_ti_sock%%,*}"; _ti_before=""

_ti_die() { echo "ERROR r957-tmux-isolate: $1 — 시험 본문 진입 0(실 서버로 내려가지 않는다)" >&2; exit 2; }

# 실 서버 읽기 «유일한 곳» — ls 만. (진짜 tmux 절대경로 + 원래 소켓)
tmux_isolate_real_ls() {
  [ -n "$_ti_real_tmux" ] || return 0
  if [ -n "${_ti_sock:-}" ]; then "$_ti_real_tmux" -S "$_ti_sock" ls 2>/dev/null
  else env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR "$_ti_real_tmux" ls 2>/dev/null; fi
  return 0
}

tmux_isolate_real_matching() { # <정규식>
  tmux_isolate_real_ls | sed 's/:.*//' | grep -E "${1:-^}" | sort
}

tmux_isolate_begin() {
  [ -z "$TMUX_ISOLATE_DIR" ] || return 0
  _ti_real_tmux="${R957_REAL_TMUX_OVERRIDE:-${R957_REAL_TMUX:-$(command -v tmux 2>/dev/null)}}"
  # 중첩(자식이 또 source 하거나 env -i 로 PATH 만 물려받은 경우): 앞선 shim 이면 그 shim 이 박아 둔 «진짜 경로» 를 쓴다
  if dirname_marker="$(dirname -- "${_ti_real_tmux:-/nonexistent}")/.r957-real" && [ -f "$dirname_marker" ]; then
    _ti_real_tmux="$(sed -n 1p "$dirname_marker")"
  fi
  [ -n "$_ti_real_tmux" ] && [ -x "$_ti_real_tmux" ] || _ti_die "진짜 tmux 바이너리를 못 찾음(PATH)"
  _ti_shim="$(mktemp -d "${TMPDIR:-/tmp}/r957-shim.XXXXXX" 2>/dev/null)" && [ -d "$_ti_shim" ] \
    || _ti_die "shim 폴더 생성 실패(TMPDIR=${TMPDIR-<빔>})"
  TMUX_ISOLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/r957-tmux.XXXXXX" 2>/dev/null)"
  [ -n "$TMUX_ISOLATE_DIR" ] && [ -d "$TMUX_ISOLATE_DIR" ] || _ti_die "격리 폴더 생성 실패(TMPDIR=${TMPDIR-<빔>})"
  _ti_iso_sock="$TMUX_ISOLATE_DIR/sock"
  case "$_ti_iso_sock" in "$TMUX_ISOLATE_DIR"/*) : ;; *) _ti_die "격리 소켓 경로가 격리 폴더 밖: $_ti_iso_sock" ;; esac
  # ── ② tmux shim — 격리 소켓 경로·진짜 tmux 절대경로를 «생성 시점에 파일 안에» 박는다 ──
  #   전역 옵션은 tmux 문법대로(getopts 문자열 2c:CDdf:hlL:NqS:T:uUvV) 읽는다 — 묶음(-uS<값>)·붙임(-S<값>)도 같은 규칙.
  #   -L 은 언제나 거절 · -S 는 «실제 경로»(cd -P 로 .. · 심볼릭 링크를 푼 값)가 격리 폴더 아래일 때만 통과 · 모르는 옵션 거절.
  #   진짜 tmux 는 «언제나» 우리 격리 소켓 하나로만 부른다(호출자 -S 를 그대로 넘겨 뒤 -S 가 이기는 규칙을 쓰지 않는다).
  cat > "$_ti_shim/tmux" <<SH
#!/usr/bin/env bash
iso='$_ti_iso_sock'; isodir='$TMUX_ISOLATE_DIR'; real='$_ti_real_tmux'
if [ -z "\$iso" ] || [ -z "\$isodir" ] || [ ! -x "\$real" ]; then
  echo "REJECT r957-tmux-shim: 박힌 격리 값 이상(iso=\$iso real=\$real)" >&2; exit 90
fi
OPTIND=1; caller=""
while getopts ":2c:CDdf:hlL:NqS:T:uUvV" o 2>/dev/null; do
  case "\$o" in
    c|f|T) : ;;                                   # 값 있는 전역 옵션 — 우리 -S 만 남기고 버린다
    S) caller="\$OPTARG" ;;
    L) echo "REJECT r957-tmux-shim: -L 소켓 이름 지정은 격리 안에서 못 쓴다" >&2; exit 91 ;;
    :) echo "REJECT r957-tmux-shim: 옵션 값 없음(-\$OPTARG)" >&2; exit 91 ;;
    *) echo "REJECT r957-tmux-shim: 모르는 전역 옵션(-\$o)" >&2; exit 91 ;;
  esac
done
shift \$((OPTIND-1))
if [ -n "\$caller" ]; then
  _d="\$(cd -P "\$(dirname -- "\$caller")" 2>/dev/null && pwd -P)" || { echo "REJECT r957-tmux-shim: 소켓 경로를 못 풂(\$caller)" >&2; exit 91; }
  _ri="\$(cd -P "\$isodir" 2>/dev/null && pwd -P)" || { echo "REJECT r957-tmux-shim: 격리 폴더 못 풂" >&2; exit 91; }
  case "\$_d/\$(basename -- "\$caller")" in
    "\$_ri"/*) : ;;
    *) echo "REJECT r957-tmux-shim: 격리 폴더 밖 소켓(\$_d/\$(basename -- "\$caller"))" >&2; exit 91 ;;
  esac
fi
[ \$# -gt 0 ] || { echo "REJECT r957-tmux-shim: 명령 없음" >&2; exit 91; }
case "\$1" in
  new-session|new|attach|attach-session) exec "\$real" -S "\$iso" "\$@" </dev/null >/dev/null 2>&1 ;;
  *) exec "\$real" -S "\$iso" "\$@" ;;
esac
SH
  chmod 755 "$_ti_shim/tmux" || _ti_die "shim 실행 권한 부여 실패"
  printf '%s\n' "$_ti_real_tmux" > "$_ti_shim/.r957-real"
  export R957_REAL_TMUX="$_ti_real_tmux"   # FT_TMUX_BIN 은 export 하지 않는다 — 시험의 가짜 tmux(FT_TMUX_BIN="$FAKE/tmux") 를 덮으면 r655·team_path 결과가 나빠진다(실측)
  PATH="$_ti_shim:$PATH"; export PATH TMUX_TMPDIR="$TMUX_ISOLATE_DIR"   # env -i 자식에도 같은 격리 폴더를 넘긴다(shim 이 -S 로 한 번 더 못박는다)
  export R957_ISO_ALLOW="$TMUX_ISOLATE_DIR"   # 기록·검사 쪽 «허용 목록» = 격리 폴더 아래 소켓만(값 비교 대신 · r5)
  unset TMUX TMUX_PANE
  _ti_before="$(tmux_isolate_real_matching "$TMUX_ISOLATE_PATTERN")"
  [ -x "$_ti_shim/tmux" ] || _ti_die "shim 실재 확인 실패"
  # shellcheck disable=SC2064
  trap 'tmux_isolate_end' EXIT
  return 0
}

# 격리 소켓의 세션만 정리 — 실 서버에는 손대지 않는다(kill-server 0)
tmux_isolate_clean_sessions() {
  [ -n "$_ti_iso_sock" ] && [ -n "$_ti_real_tmux" ] || return 0
  local s
  for s in $("$_ti_real_tmux" -S "$_ti_iso_sock" ls 2>/dev/null | sed 's/:.*//'); do
    "$_ti_real_tmux" -S "$_ti_iso_sock" kill-session -t "=$s" 2>/dev/null
  done
  return 0
}

tmux_isolate_end() {
  [ -n "$TMUX_ISOLATE_DIR" ] || return 0
  tmux_isolate_clean_sessions
  rm -rf "$TMUX_ISOLATE_DIR" "$_ti_shim"; TMUX_ISOLATE_DIR=""
  return 0
}

# 시험 끝 1줄 — 실 서버의 시험 이름(기본 byz-alpha-·byz-v65-·ft-v65-temp-)이 늘면 FAIL
tmux_isolate_leak_check() { # [<정규식>]
  local pat="${1:-$TMUX_ISOLATE_PATTERN}" after
  after="$(tmux_isolate_real_matching "$pat")"
  if [ "$after" = "${_ti_before:-}" ]; then
    echo "PASS 누수 0 — 실 tmux 서버 시험 세션(${pat}) 수 불변: $(printf '%s' "$after" | grep -c . )"
    return 0
  fi
  echo "FAIL 실 tmux 서버 세션 누수 — 늘어난 이름: $(comm -13 <(printf '%s\n' "${_ti_before:-}") <(printf '%s\n' "$after") | tr '\n' ' ')"
  return 1
}

TMUX_ISOLATE_PATTERN="${TMUX_ISOLATE_PATTERN:-^(byz-alpha-|byz-r921-nano-|byz-v65-|ft-v65-temp-)}"
tmux_isolate_begin
