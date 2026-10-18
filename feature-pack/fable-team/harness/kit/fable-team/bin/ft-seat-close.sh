#!/usr/bin/env bash
# ft-seat-close.sh <좌석> --reason "<1줄>" [--seats <파일>] — «세션만 닫기»(R297): tmux 세션 kill + 명부 행 role=stop-ready·_closed 표기.
#   nano-close 를 안 타고 세션만 끈 좌석이 명부 행 잔류로 ft-tick «죽은 좌석 재개» 대상이 되어 되살아나는 일을 막는다(v65 판정 2050 노출 나노).
#   틱 코드 변경 0 — resume_rows 가 role=stop-ready 행을 이미 뺀다. 워크트리·브랜치·원장·행 삭제 0(지우는 건 nano-close 만).
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <좌석> 을 가진 파일 정확히 1개(ft-seat-retire.sh 와 같은 규칙).
#   거절: 좌석이 어느 명부의 `_*` 문자열 칸(_master·_arch·_hil_route·_desk …) 값 = 현역 역할 좌석 → 승계 경로(ft-successor-open · ft-seat-retire).
#   순서(되돌림 쉬운 것 먼저): ①명부 .bak-close-<ts> + 표기(tmp→mv) ②@zc_v65_active 태그 해제 ③세션 kill. ②③ 실패 = FAIL rc 1(표기는 남김 — 재개 0 이 안전한 쪽).
#   ③ 은 표준승인 범위만: 같은 계보(# 앞)로 더 큰 번호 세션이 살아 있고 (그 좌석 재개 기록 ~/.claude/state/seat-resume/<좌석>.json 있음 ∨ 더 큰 번호 2개+ 생존)일 때. 아니면 kill=held rc 3(표기는 남음).
#   rc 0 = CLOSED-SESSION · 1 = REJECT/FAIL(사유 stdout) · 2 = usage · 3 = kill=held. kill 근거: 전역 「tmux 세션 정리 표준승인 2026-07-11」(kill-server 아님).
set -uo pipefail
USAGE="usage: $0 <좌석> --reason \"<1줄>\" [--seats <파일>]"
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; REASON=""; ARG=""
while [ $# -gt 0 ]; do case "$1" in --reason) REASON="${2:-}"; shift 2;; --seats) ARG="${2:-}"; shift 2;; *) echo "unknown $1" >&2; echo "$USAGE" >&2; exit 2;; esac; done
[ -n "${REASON//[[:space:]]/}" ] || { echo "$USAGE — --reason 필요" >&2; exit 2; }
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
BY="unknown"; [ -z "${TMUX_PANE:-}" ] || BY="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || echo unknown)"
OUT="$(python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$SEAT" "$REASON" "$BY" <<'PY'
import json, glob, shutil, datetime, collections, os, sys
arg, root, seat, reason, by = sys.argv[1:6]
def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None
files = [arg] if arg else sorted(glob.glob(root + "/.fable-team/seats*.json"))
for f in files:   # ⓐ 현역 역할 좌석(_master·_arch·_hil_route·_desk …)은 세션만 닫지 않는다
    d = load(f)
    if isinstance(d, dict) and any(k.startswith("_") and v == seat for k, v in d.items()):
        print(f"REJECT {seat} 은 {f} 의 _ 칸 값(현역 역할 좌석) — 승계 경로(ft-successor-open · ft-seat-retire) 로"); sys.exit(1)
cand = [f for f in files if isinstance(load(f), dict) and seat in load(f)]
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {seat}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(seat)
if not isinstance(o, dict): print(f"REJECT {p} 의 {seat} 행이 객체가 아님"); sys.exit(1)
now = datetime.datetime.now()
shutil.copy(p, p + ".bak-close-" + now.strftime("%Y%m%d%H%M%S"))
role = o.get("role")
if role != "stop-ready": o["_closed_role"] = role   # 이미 stop-ready 면 첫 닫기의 원래 role 을 덮지 않는다
o["role"] = "stop-ready"; o["tick"] = None
o["_closed"] = collections.OrderedDict(by=by, at=now.isoformat(timespec="seconds"), reason=reason)
tmp = p + ".tmp-" + str(os.getpid())   # 쓰기 중 죽어도 원본 무손상
with open(tmp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
shutil.copymode(p, tmp); os.replace(tmp, p)
print(f"MARKED\t{p}\t{o.get('_closed_role')}")
PY
)"; rc=$?
[ "$rc" = 0 ] || { printf '%s\n' "$OUT"; exit 1; }
FILE="$(printf '%s' "$OUT" | cut -f2)"; WAS="$(printf '%s' "$OUT" | cut -f3)"
# ③ kill 범위 = 전역 표준승인(2026-07-11): 계보 최신은 보존 · 직전 세대는 «재개 기록 있음 ∨ 더 큰 번호 2개+ 생존(keep-last-2)» 일 때만. 밖은 kill=held rc 3(나노는 ft-nano-close · 그 밖은 [HIL]).
lineage_ok() {
  local base="${SEAT%#*}" n="${SEAT##*#}" up=0 s rec="${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}/$SEAT.json"
  [ "$base" != "$SEAT" ] && [[ "$n" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r s; do [ "${s%#*}" = "$base" ] && [[ "${s##*#}" =~ ^[0-9]+$ ]] && [ "${s##*#}" -gt "$n" ] && up=$((up+1)); done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  [ "$up" -ge 2 ] || { [ "$up" -ge 1 ] && [ -f "$rec" ]; }
}
if tmux has-session -t "=$SEAT" 2>/dev/null; then
  lineage_ok || { echo "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])"; exit 3; }
  if [ -n "$(tmux show-options -qv -t "=$SEAT" @zc_v65_active 2>/dev/null)" ]; then
    tmux set-option -t "=$SEAT" -u @zc_v65_active || { echo "FAIL tag $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; exit 1; }
  fi
  tmux kill-session -t "=$SEAT" || { echo "FAIL kill $SEAT — kill-session 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; exit 1; }
  KILL=ok
else KILL=none; fi
echo "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=$KILL"
