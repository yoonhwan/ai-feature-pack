#!/usr/bin/env bash
# ft-seat-close.sh <좌석> --reason "<1줄>" [--seats <파일>] — «세션만 닫기»(R297): tmux 세션 kill + 명부 행 role=stop-ready·_closed 표기.
#   nano-close 를 안 타고 세션만 끈 좌석이 명부 행 잔류로 ft-tick «죽은 좌석 재개» 대상이 되어 되살아나는 일을 막는다(v65 판정 2050 노출 나노).
#   틱 코드 변경 0 — resume_rows 가 role=stop-ready 행을 이미 뺀다. 워크트리·브랜치·원장·행 삭제 0(지우는 건 nano-close 만).
#   명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <좌석> 을 가진 파일 정확히 1개(ft-seat-retire.sh 와 같은 규칙).
#   거절: 좌석이 어느 명부의 `_*` 문자열 칸(_master·_arch·_hil_route·_desk …) 값 = 현역 역할 좌석 → 승계 경로(ft-successor-open · ft-seat-retire).
#   순서(되돌림 쉬운 것 먼저): ①명부 .bak-close-<ts> + 표기(tmp→mv) ②@zc_v65_active 태그 해제 ③세션 kill. ②③ 실패 = FAIL rc 1(표기는 남김 — 재개 0 이 안전한 쪽).
#   ③ 은 표준승인 범위만: 같은 계보(# 앞)로 더 큰 번호 세션이 살아 있고 (그 좌석 재개 기록 ~/.claude/state/seat-resume/<좌석>.json 있음 ∨ 더 큰 번호 2개+ 생존)일 때. 아니면 kill=held rc 3(표기는 남음).
#   rc 0 = CLOSED-SESSION · 1 = REJECT/FAIL(사유 stdout) · 2 = usage · 3 = kill=held. kill 근거: 전역 「tmux 세션 정리 표준승인 2026-07-11」(kill-server 아님).
#   R400 «역할 좌석 닫기» `--verdict <번호>`(판정 2304 — 사람 승인 1건의 번호): ⓪실행 세션 == 좌석 → REJECT ①재개 기록(ft-seat-retire --record-only --verdict · env FT_SEAT_RETIRE_BIN) 실패 = HELD rc 3(명부 쓰기 0 · kill 0)
#   ②행 있음 → 위 표기 + _closed.verdict + 어느 명부든 값 == 좌석인 최상위 `_*` 문자열 칸 "" (파일마다 .bak-close-<ts> · tmp→mv) · 행 없음 = NOROW rc 3(kill 0 · 그 리포 루트에서) ③lineage_ok 건너뜀 → 태그 해제 → kill
#   출력 `CLOSED-ROLE <좌석> verdict=<번호> record=<경로> cells=<파일:_칸,…;…> kill=ok|none` · 원장 <ft_data_root>/.fable-team/state/seat-close-verdict.log 1행/좌석. --verdict 없는 호출은 위 동작 그대로.
set -uo pipefail
USAGE="usage: $0 <좌석> --reason \"<1줄>\" [--seats <파일>] [--verdict <번호>]"
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; REASON=""; ARG=""; VERDICT=""; REC=""
while [ $# -gt 0 ]; do case "$1" in --reason) REASON="${2:-}"; shift 2;; --seats) ARG="${2:-}"; shift 2;; --verdict) VERDICT="${2:-}"; [[ "$VERDICT" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || { echo "$USAGE — --verdict <번호>" >&2; exit 2; }; shift 2;; *) echo "unknown $1" >&2; echo "$USAGE" >&2; exit 2;; esac; done
[ -n "${REASON//[[:space:]]/}" ] || { echo "$USAGE — --reason 필요" >&2; exit 2; }
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
BY="unknown"; [ -z "${TMUX_PANE:-}" ] || BY="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || echo unknown)"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -n "$VERDICT" ]; then   # R400 ⓪① — 원장 루트를 먼저 풀고(못 풀면 쓰기 0) 재개 기록 → 실패면 명부·kill 0
  [ "$BY" != "$SEAT" ] || { echo "REJECT $SEAT 은 지금 이 명령을 실행하는 세션 자신 — 다른 좌석에서 닫는다"; exit 1; }
  . "$HERE/ft-harness-root.sh" && DATA="$(ft_data_root "$HERE")" || { echo "REJECT 원장 루트를 못 풂 — FT_ROOT=<설치본 루트> 를 주고 --seats <그 루트>/.fable-team/seats.json 로 (쓰기 0 · kill 0)"; exit 1; }
  ROUT="$(bash "${FT_SEAT_RETIRE_BIN:-$HERE/ft-seat-retire.sh}" "$SEAT" --record-only --verdict "$VERDICT" ${ARG:+--seats "$ARG"} 2>&1)"; rrc=$?
  case "$rrc $ROUT" in "0 RESUME ok "*) REC="${ROUT#RESUME ok }"; REC="${REC%%[[:space:]]*}";; *) echo "HELD $SEAT 재개 기록 실패 — 명부 쓰기 0 · kill 0 · rc=$rrc $(printf '%s' "$ROUT" | head -1)"; exit 3;; esac
fi
OUT="$(python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$SEAT" "$REASON" "$BY" "$VERDICT" "$REC" "$HERE/ft-seat-close.sh" <<'PY'
import json, glob, shutil, shlex, datetime, collections, os, sys
arg, root, seat, reason, by, verdict, rec, tool = sys.argv[1:9]
def load(f):
    try: return json.load(open(f, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError): return None
def save(p, d):
    tmp = p + ".tmp-" + str(os.getpid())   # 쓰기 중 죽어도 원본 무손상
    with open(tmp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    shutil.copymode(p, tmp); os.replace(tmp, p)
files = [arg] if arg else sorted(glob.glob(root + "/.fable-team/seats*.json"))
for f in (files if not verdict else []):   # ⓐ 현역 역할 좌석(_master·_arch·_hil_route·_desk …)은 세션만 닫지 않는다(--verdict = 판정 승인 경로만 예외)
    d = load(f)
    if isinstance(d, dict) and any(k.startswith("_") and v == seat for k, v in d.items()):
        print(f"REJECT {seat} 은 {f} 의 _ 칸 값(현역 역할 좌석) — 승계 경로(ft-successor-open · ft-seat-retire) 로 · 후계 없이 닫으려면 --verdict <판정번호>(R400 · 사람 승인 1건)"); sys.exit(1)
cand = [f for f in files if isinstance(load(f), dict) and seat in load(f)]
if verdict and not cand:   # R400 r3 §D — 명부 루트(cwd)와 원장 루트(FT_ROOT)를 같이 주는 한 줄(자동 탐색 0)
    print(f"NOROW {seat} 명부 행 없음({arg or root + '/.fable-team/seats*.json'}) — 기록 {rec} · kill 0 · 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> {tool} {shlex.quote(seat)} --verdict {verdict} --reason {shlex.quote(reason)} --seats <그 루트>/.fable-team/seats.json"); sys.exit(3)
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {seat}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(seat)
if not isinstance(o, dict): print(f"REJECT {p} 의 {seat} 행이 객체가 아님"); sys.exit(1)
now = datetime.datetime.now(); ts = now.strftime("%Y%m%d%H%M%S")
shutil.copy(p, p + ".bak-close-" + ts)
role = o.get("role")
if role != "stop-ready": o["_closed_role"] = role   # 이미 stop-ready 면 첫 닫기의 원래 role 을 덮지 않는다
o["role"] = "stop-ready"; o["tick"] = None
o["_closed"] = collections.OrderedDict(by=by, at=now.isoformat(timespec="seconds"), reason=reason)
cells = []
if verdict:   # R400 ② — 그 좌석 값인 최상위 `_*` 문자열 칸만 "" (다른 칸·행 삭제 0)
    o["_closed"]["verdict"] = verdict
    for f in files:
        dd = d if f == p else load(f)
        ks = [k for k, v in dd.items() if k.startswith("_") and isinstance(v, str) and v == seat] if isinstance(dd, dict) else []
        if not ks: continue
        for k in ks: dd[k] = ""
        if f != p: shutil.copy(f, f + ".bak-close-" + ts); save(f, dd)
        cells.append(f + ":" + ",".join(ks))
save(p, d)
print(f"MARKED\t{p}\t{o.get('_closed_role')}" + (f"\t{';'.join(cells) or '-'}" if verdict else ""))
PY
)"; rc=$?
[ "$rc" = 0 ] || { printf '%s\n' "$OUT"; [ "$rc" = 3 ] && [ -n "$VERDICT" ] && exit 3; exit 1; }
FILE="$(printf '%s' "$OUT" | cut -f2)"; WAS="$(printf '%s' "$OUT" | cut -f3)"; CELLS="$(printf '%s' "$OUT" | cut -f4)"
vlog() { [ -z "$VERDICT" ] || { mkdir -p "$DATA/.fable-team/state" && printf '%s\tverdict=%s\t%s\trecord=%s\tcells=%s\tkill=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$VERDICT" "$SEAT" "$REC" "$CELLS" "$1" >> "$DATA/.fable-team/state/seat-close-verdict.log"; }; }
# ③ kill 범위 = 전역 표준승인(2026-07-11): 계보 최신은 보존 · 직전 세대는 «재개 기록 있음 ∨ 더 큰 번호 2개+ 생존(keep-last-2)» 일 때만. 밖은 kill=held rc 3(나노는 ft-nano-close · 그 밖은 [HIL]).
lineage_ok() {
  local base="${SEAT%#*}" n="${SEAT##*#}" up=0 s rec="${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}/$SEAT.json"
  [ "$base" != "$SEAT" ] && [[ "$n" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r s; do [ "${s%#*}" = "$base" ] && [[ "${s##*#}" =~ ^[0-9]+$ ]] && [ "${s##*#}" -gt "$n" ] && up=$((up+1)); done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  [ "$up" -ge 2 ] || { [ "$up" -ge 1 ] && [ -f "$rec" ]; }
}
# r448: kill «앞» 그 좌석이 띄운 백그라운드 루프 정지(ft-seat-reap) — left≠0 ∨ rc≠0 = CLOSE-FAIL rc 1(세션 보존 · 명부 표기는 남음 · 사람 판단). 세션이 이미 없어도 고아 루프를 본다.
reap() {
  local o r; o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" 2>&1)"; r=$?; RL="$(printf '%s\n' "$o" | grep -oE 'left=[0-9?]+' | tail -1)"
  printf '%s\n' "$o" >&2
  [ "$r" -eq 0 ] && [ "$RL" = left=0 ] && return 0
  vlog fail-reap; echo "CLOSE-FAIL reap ${RL:-left=?} rc=$r — $SEAT 세션 보존(명부 표기는 남음 file=$FILE)"; exit 1
}
if tmux has-session -t "=$SEAT" 2>/dev/null; then
  [ -n "$VERDICT" ] || lineage_ok || { echo "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])"; exit 3; }   # --verdict = 판정 승인 1건 + 재개 기록 확인됨
  reap
  if [ -n "$(tmux show-options -qv -t "=$SEAT" @zc_v65_active 2>/dev/null)" ]; then
    tmux set-option -t "=$SEAT" -u @zc_v65_active || { vlog fail-tag; echo "FAIL tag $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; exit 1; }
  fi
  tmux kill-session -t "=$SEAT" || { vlog fail-kill; echo "FAIL kill $SEAT — kill-session 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; exit 1; }
  KILL=ok
else reap; KILL=none; fi
[ -z "$VERDICT" ] || { vlog "$KILL"; echo "CLOSED-ROLE $SEAT verdict=$VERDICT record=$REC cells=$CELLS kill=$KILL reap left=0 rc=0"; exit 0; }
echo "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=$KILL reap left=0 rc=0"
