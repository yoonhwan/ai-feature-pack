#!/usr/bin/env bash
# ft-resource-sample.sh — 압력 표본 1줄을 .fable-team/state/pressure.tsv 에 덧붙인다 (R213 · 오빠 «스왑한도 황금값 재설정»).
#   줄 = `ts(epoch)\tswap_mib\tmemfree\tlevel\tswapouts` · 3일 넘은 줄은 같은 실행에서 잘라낸다(회전).
#   부르는 곳 = ft-resource-watch.sh tick(launchd 60초) — 문지기(ft-resource-gate.sh)가 마지막 6줄로 스왑 증가 속도를 낸다.
#   문지기가 표본 없음·낡음(>180초)이면 이 스크립트를 그 자리에서 1회 돌려 직접 잰다(R213 DA⑥ r2 H2 — 표식 파일 생명주기 폐기).
#   동시 호출(문지기 직접 측정 · 감시자 tick)은 mkdir 잠금(state/pressure.lock.d) 하나로 직렬화한다 — 읽기·추가·회전·교체 전체가 한 경계(R213 DA r3). 대기 상한 2초 · 못 잡으면 rc4.
#   잠금엔 `pid 시각` 을 적고, 그 pid 가 죽었거나 30초 넘었으면 회수한다(닫는 사건 · 영구 잠금 0). 같은 초 표본은 추가 0(dt=0 방지) · 시계 역행은 rc4.
#   측정 명령 rc≠0 이면 출력이 숫자여도 실패 · 실패 = stderr `ERROR resource sample <무엇>` + rc 4(줄 안 씀 · NO SILENT FALLBACK). bash 3.2 호환 · macOS 전용.
#   env(시험용): FT_RES_ROOT
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
RES_ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$RES_ROOT" ] || { . "$HERE/ft-harness-root.sh" && RES_ROOT="$(ft_repo_root "$HERE")"; } || exit 3
TSV="$RES_ROOT/.fable-team/state/pressure.tsv"; LOCK="$RES_ROOT/.fable-team/state/pressure.lock.d"
is_int() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
fail() { echo "ERROR resource sample $1" >&2; exit 4; }
mcap() { local n="$1"; shift; M_OUT="$("$@" 2>/dev/null)"; [ $? -eq 0 ] || fail "$n rc≠0"; }
for _c in sysctl memory_pressure vm_stat awk; do command -v "$_c" >/dev/null 2>&1 || fail "command-missing=$_c"; done
mkdir -p "$(dirname -- "$TSV")" 2>/dev/null || fail "mkdir $(dirname -- "$TSV")"
# 잠금 — mkdir 원자성. 소유자 `pid 시각` 기록 · 죽은 pid/30초 초과는 회수 · 대기 20×0.1초.
owner_stale() { # 0 = 회수 대상
  local op ot; read -r op ot < "$LOCK/owner" 2>/dev/null
  if ! is_int "$op" || ! is_int "$ot"; then ot="$(stat -f %m "$LOCK" 2>/dev/null)"; is_int "$ot" || return 1; [ $(( $(date +%s) - ot )) -gt 30 ]; return; fi
  kill -0 "$op" 2>/dev/null || return 0
  [ $(( $(date +%s) - ot )) -gt 30 ]
}
_i=0
until mkdir "$LOCK" 2>/dev/null; do
  if owner_stale; then _seen="$(cat "$LOCK/owner" 2>/dev/null)"; owner_stale && [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$_seen" ] && rm -rf "$LOCK"; continue; fi
  _i=$((_i+1)); [ "$_i" -le 20 ] || fail "lock 대기 2초 초과 $LOCK"; sleep 0.1
done
trap 'rm -rf "$LOCK"' EXIT
printf '%s %s\n' "$$" "$(date +%s)" > "$LOCK/owner"
mcap swap sysctl -n vm.swapusage
SWAP_MIB="$(printf '%s\n' "$M_OUT" | awk '{ if (match($0, /used = [0-9.]+[A-Za-z]/)) { s=substr($0, RSTART+7, RLENGTH-7); u=substr(s, length(s)); v=substr(s, 1, length(s)-1)+0; if (u=="G"||u=="g") v*=1024; else if (u=="K"||u=="k") v/=1024; printf "%d", v } }')"
is_int "$SWAP_MIB" || fail "swap swapusage"
mcap memfree memory_pressure
MEMFREE="$(printf '%s\n' "$M_OUT" | awk -F': ' '/free percentage/{v=$2; gsub(/[^0-9]/,"",v); print v; exit}')"
is_int "$MEMFREE" || fail "memfree memory_pressure=$MEMFREE"
mcap level sysctl -n kern.memorystatus_vm_pressure_level; LEVEL="$M_OUT"
is_int "$LEVEL" || fail "level sysctl=$LEVEL"
mcap swapouts vm_stat
SWAPOUTS="$(printf '%s\n' "$M_OUT" | awk '/^Swapouts:/{v=$2; gsub(/[^0-9]/,"",v); print v; exit}')"
is_int "$SWAPOUTS" || fail "swapouts vm_stat=$SWAPOUTS"
NOW="$(date +%s)"
_last="$(tail -n 1 "$TSV" 2>/dev/null | awk -F'\t' '$1~/^[0-9]+$/{print $1}')"
if is_int "$_last"; then
  [ "$_last" -le "$NOW" ] || fail "clock-backwards last=$_last now=$NOW"
  [ "$_last" -lt "$NOW" ] || exit 0   # 같은 초 표본은 추가 0
fi
printf '%s\t%s\t%s\t%s\t%s\n' "$NOW" "$SWAP_MIB" "$MEMFREE" "$LEVEL" "$SWAPOUTS" >> "$TSV" || fail "write $TSV"
# 회전 — 3일(259200s) 넘은 줄 제거. 실패하면 원본 유지.
TMP="$TSV.tmp.$$"
if awk -F'\t' -v c=$((NOW-259200)) '($1+0)>=c' "$TSV" > "$TMP" 2>/dev/null; then mv "$TMP" "$TSV"; else rm -f "$TMP"; fi
exit 0
