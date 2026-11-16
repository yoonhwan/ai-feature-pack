#!/usr/bin/env bash
# ft-block-lib.sh — source 전용 (r2067 A1 · 막힘 장부에 올리는 한 길)
#   ft_block raise <도구> <seat|card|team> <대상> --cause <글> --fix <글> [--period <초>]  ·  ft_block clear <도구> <대상>
#   장부 도구 = env FT_BLOCK_BIN › <데이터 루트>/.fable-team/state/ft20-r1483-watch/block.sh (데이터 루트 = ft_data_root)
#   데이터 루트를 못 풂 · 장부 도구 없음 · FT_CRITICAL_OFF=1 = 호출 0 · 부를 때 env FT20_SCAN_ROOT=<데이터 루트>
#   상한 7초(FT_BLOCK_TIMEOUT_S 는 더 짧게만) · 출력 버림 · 반환 0 고정 — 부른 도구의 rc·stdout·stderr 불변(하드 룰 12·20)
#   --cause 글 = 첫 줄 · 160자 안(넘으면 자름)
ft_block() {
  [ "${FT_CRITICAL_OFF:-0}" = 1 ] && return 0
  local here root bin
  here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  root="$( . "$here/ft-harness-root.sh" 2>/dev/null && ft_data_root "$here" 2>/dev/null )" || return 0
  [ -n "$root" ] || return 0
  bin="${FT_BLOCK_BIN:-$root/.fable-team/state/ft20-r1483-watch/block.sh}"
  [ -f "$bin" ] || return 0
  FT20_SCAN_ROOT="$root" python3 - "$bin" "$@" >/dev/null 2>&1 </dev/null <<'PY'
import os, signal, subprocess, sys
bin_, args = sys.argv[1], sys.argv[2:]
for i in range(len(args) - 1):
    if args[i] == "--cause":
        args[i + 1] = (args[i + 1].split("\n") or [""])[0][:160]
try: lim = min(7.0, float(os.environ.get("FT_BLOCK_TIMEOUT_S") or 7))
except ValueError: lim = 7.0
p = subprocess.Popen(["bash", bin_, *args], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
try: p.wait(timeout=lim)
except subprocess.TimeoutExpired:
    try: os.killpg(p.pid, signal.SIGKILL)
    except OSError: pass
PY
  return 0
}
