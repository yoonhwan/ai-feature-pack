#!/usr/bin/env bash
# ft-seat-close.sh <좌석> --reason "<1줄>" [--seats <파일>] — «세션만 닫기»(R297): tmux 세션 kill + 명부 행 role=stop-ready·_closed 표기. nano-close 를 안 타고 세션만 끈 좌석이 명부 행 잔류로 ft-tick «죽은 좌석 재개» 대상이 되어 되살아나는 일을 막는다(v65 판정 2050 노출 나노).
#   틱 코드 변경 0 — resume_rows 가 role=stop-ready 행을 이미 뺀다. 워크트리·브랜치·원장·행 삭제 0(지우는 건 nano-close 만). 명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <좌석> 을 가진 파일 정확히 1개(ft-seat-retire.sh 와 같은 규칙).
#   거절: 좌석이 어느 명부의 `_*` 문자열 칸(_master·_arch·_hil_route·_desk …) 값 = 현역 역할 좌석 → 승계 경로(ft-successor-open · ft-seat-retire).
#   순서(되돌림 쉬운 것 먼저): ①명부 .bak-close-<ts> + 표기(tmp→mv) ②@zc_v65_active 태그 해제 ③세션 kill. ②③ 실패 = FAIL rc 1(표기는 남김 — 재개 0 이 안전한 쪽). ③ 은 표준승인 범위만: 같은 계보(# 앞)로 더 큰 번호 세션이 살아 있고 (그 좌석 재개 기록 ~/.claude/state/seat-resume/<좌석>.json 있음 ∨ 더 큰 번호 2개+ 생존)일 때. 아니면 kill=held rc 3(표기는 남음).
#   rc 0 = CLOSED-SESSION · 1 = REJECT/FAIL(사유 stdout) · 2 = usage · 3 = kill=held. kill 근거: 전역 「tmux 세션 정리 표준승인 2026-07-11」(kill-server 아님).
#   R400 «역할 좌석 닫기» `--verdict <번호>`(판정 2304 — 사람 승인 1건의 번호): ⓪실행 세션 == 좌석 → REJECT ①재개 기록(ft-seat-retire --record-only --verdict · env FT_SEAT_RETIRE_BIN) 실패 = HELD rc 3(명부 쓰기 0 · kill 0) ②행 있음 → 위 표기 + _closed.verdict + 어느 명부든 값 == 좌석인 최상위 `_*` 문자열 칸 "" (파일마다 .bak-close-<ts> · tmp→mv) · 행 없음 = NOROW rc 3(kill 0 · 그 리포 루트에서) ③lineage_ok 건너뜀 → 태그 해제 → kill · 원장 <ft_data_root>/.fable-team/state/seat-close-verdict.log 1행/좌석. --verdict 없는 호출은 위 동작 그대로.
#   r427 죽은 좌석(--verdict · tmux 세션 없음): 재개 기록 = --keep-existing(기존 보존 · 없으면 대화 기록 탐색 · 둘 다 없으면 NORECORD 도 진행) → 위 ② 표기 + _closed.dead · kill 0 · 비운 칸은 행 `_closed_from`. `--reopen <좌석>` = zombie-clean resume 으로 되살린 좌석: role=_closed_role(없으면 active)·tick 복원 · _closed* 제거 · `REOPENED <좌석> roles=<칸들>`.
#   ★r960 — 닫기 결과 출력은 finish() "하나"★: 어느 종료 갈래(CLOSED-ROLE · CLOSED-DEAD · CLOSED-SESSION · HELD · FAIL)든 결과 줄 다음에 record=NORECORD 면 `NORECORD <좌석> <사유>` 1줄을 반드시 남긴다(갈래마다 출력을 따로 두면 다음 갈래가 또 빠뜨린다 — DA r1·r2 반례). 갈래 안 exit 는 이 함수로만. pi 좌석 재개 기록 근거 = ft-seat-retire.sh ⓒ(pi 세션 파일) · model 은 ft_roster_lib._pi_model · 살아 있는 좌석의 NORECORD 수용은 «명부 agent 칸 = pi» 일 때만(r4: 출력 글자 판정 0).
set -uo pipefail
USAGE="usage: $0 <좌석> --reason \"<1줄>\" [--seats <파일>] [--verdict <번호>] | $0 --reopen <좌석> [--seats <파일>]"
REOPEN=0; [ "${1:-}" != --reopen ] || { REOPEN=1; shift; }
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; REASON=""; ARG=""; VERDICT=""; REC=""; NOLINE=""; DEAD=0
while [ $# -gt 0 ]; do case "$1" in --reason) REASON="${2:-}"; shift 2;; --seats) ARG="${2:-}"; shift 2;; --reopen) REOPEN=1; shift;; --verdict) VERDICT="${2:-}"; [[ "$VERDICT" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || { echo "$USAGE — --verdict <번호>" >&2; exit 2; }; shift 2;; *) echo "unknown $1" >&2; echo "$USAGE" >&2; exit 2;; esac; done
[ "$REOPEN" = 1 ] || [ -n "${REASON//[[:space:]]/}" ] || { echo "$USAGE — --reason 필요" >&2; exit 2; }
[ "$REOPEN" = 0 ] || [ -z "$VERDICT" ] || { echo "$USAGE — --reopen 과 --verdict 는 같이 쓰지 않는다" >&2; exit 2; }
[ "$REOPEN" = 0 ] || tmux has-session -t "=$SEAT" 2>/dev/null || { echo "REJECT $SEAT tmux 세션 없음 — zombie-clean.sh resume '$SEAT' 먼저(명부 쓰기 0)"; exit 1; }
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
BY="unknown"; [ -z "${TMUX_PANE:-}" ] || BY="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || echo unknown)"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
finish() {   # r960 — 닫기 결과 출력 «한 곳»: 결과 줄들 다음에 record=NORECORD 면 `NORECORD <좌석> <사유>` 1줄(결과 줄에 이미 있으면 중복 0 · 원문을 못 잡았으면 안전망 문구). 모든 종료 갈래는 이 함수로만 끝난다
  local rc="$1" b; shift; b="$(printf '%s\n' "$@")"; [ -z "$b" ] || printf '%s\n' "$b"
  case "$b" in "$NOLINE") exit "$rc";; esac   # 본문이 이미 그 NORECORD 줄 뿐이면 중복 0
  if [ -n "$NOLINE" ]; then printf '%s\n' "$NOLINE"; elif [ "$REC" = NORECORD ]; then printf 'NORECORD %s pi 세션 없음 — 산출 커밋 보존\n' "$SEAT"; elif [ -n "$REC" ]; then case "$b" in *"$REC"*) ;; *) printf 'RESUME ok %s\n' "$REC";; esac; fi
  exit "$rc"
}
if [ -n "$VERDICT" ]; then   # R400 ⓪① — 원장 루트를 먼저 풀고(못 풀면 쓰기 0) 재개 기록 → 실패면 명부·kill 0
  [ "$BY" != "$SEAT" ] || { echo "REJECT $SEAT 은 지금 이 명령을 실행하는 세션 자신 — 다른 좌석에서 닫는다"; exit 1; }
  . "$HERE/ft-harness-root.sh" && DATA="$(ft_data_root "$HERE")" || { echo "REJECT 원장 루트를 못 풂 — FT_ROOT=<설치본 루트> 를 주고 --seats <그 루트>/.fable-team/seats.json 로 (쓰기 0 · kill 0)"; exit 1; }
  tmux has-session -t "=$SEAT" 2>/dev/null || DEAD=1   # r427 — 세션 없음 = pane 결속 불가 → 기존 기록 보존 · 없으면 대화 기록 탐색(살아 있는 좌석 경로는 그대로)
  ROUT="$(bash "${FT_SEAT_RETIRE_BIN:-$HERE/ft-seat-retire.sh}" "$SEAT" --record-only --verdict "$VERDICT" ${ARG:+--seats "$ARG"} $([ "$DEAD" = 0 ] || echo --keep-existing) 2>&1)"; rrc=$?; NOLINE="$(printf '%s\n' "$ROUT" | grep -m1 '^NORECORD ')"   # r960 ⓡⓣ — 어느 갈래(수용·HELD·죽은 좌석)든 NORECORD 원문 줄은 finish 가 책임진다 — case 보다 먼저 잡는다
  AGENT="$(cd "$HERE" && python3 -c 'import sys,glob,os;sys.path[:0]=[os.getcwd()];from ft_roster_lib import load;a,r,s=sys.argv[1:4];fs=[a] if a else sorted(glob.glob(r+"/.fable-team/seats*.json"));print(next((d[s].get("agent") or "" for d in map(load,fs) if isinstance(d,dict) and isinstance(d.get(s),dict)),""))' "$ARG" "$ROOT" "$SEAT" 2>/dev/null)"   # r960 r4 ⓥⓦ — 수용 판정 근거 = «명부 agent 칸»(ft_roster_lib.load 재사용) · 출력 글자(«pi 세션 없음»·경로 이름)로 판정 0 · 못 읽으면 빈 값 = 수용 0
  held() { if [ -n "$NOLINE" ]; then finish 3 "HELD $SEAT 재개 기록 실패 — 명부 쓰기 0 · kill 0 · rc=$rrc"; else finish 3 "HELD $SEAT 재개 기록 실패 — 명부 쓰기 0 · kill 0 · rc=$rrc $(printf '%s' "$ROUT" | head -1)"; fi; }
  case "$DEAD:$rrc $ROUT" in ?":0 RESUME ok "*) RK=new;; "1:0 RESUME kept "*) RK=kept;; "1:0 NORECORD "*) RK=NORECORD;; "0:0 NORECORD "*) [ "$AGENT" = pi ] && RK=NORECORD || held;; *) held;; esac   # r960 ⓓ: 살아 있는 좌석의 NORECORD 수용 = 명부 agent 칸이 pi 일 때만(산출 커밋은 브랜치 보존) · claude·못 읽음은 그대로 HELD rc 3
  REC="${ROUT#RESUME * }"; REC="${REC%%[[:space:]]*}"; [ "$RK" != NORECORD ] || REC=NORECORD
fi
OUT="$(python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$SEAT" "$REASON" "$BY" "$VERDICT" "$REC" "$HERE/ft-seat-close.sh" "$DEAD" "$REOPEN" <<'PY'
import json, glob, shutil, shlex, datetime, collections, os, sys
arg, root, seat, reason, by, verdict, rec, tool, dead, reopen = sys.argv[1:11]
sys.path.insert(0, os.path.dirname(tool))   # 명부 읽기·원자 쓰기(쓰기 중 죽어도 원본 무손상) = 같은 폴더 lib(retire 와 공용)
from ft_roster_lib import load, dump as save
files = [arg] if arg else sorted(glob.glob(root + "/.fable-team/seats*.json"))
for f in (files if not (verdict or reopen == "1") else []):   # ⓐ 현역 역할 좌석(_master·_arch·_hil_route·_desk …)은 세션만 닫지 않는다(--verdict = 판정 승인 경로만 예외)
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
if reopen == "1":   # r427 ⓖ — 닫힘 표기 되돌림 · 비웠던 칸은 지금도 "" 일 때만 다시 채운다(그새 교대된 칸은 덮지 않음)
    if not o.get("_closed"): print(f"NOOP {seat} 닫힌 행 아님(_closed 없음) file={p}"); sys.exit(0)
    shutil.copy(p, p + ".bak-reopen-" + ts); back, held = [], []
    o["role"] = o.pop("_closed_role", None) or "active"; o["tick"] = o.pop("_closed_tick", o.get("tick"))
    for c in o.pop("_closed_from", []):
        f, _, k = c.rpartition(":"); dd = d if f == p else load(f); cur = dd.get(k) if isinstance(dd, dict) else None
        if cur not in ("", seat): held.append(f"{c}={cur}"); continue
        dd[k] = seat; back.append(k)
        if f != p: shutil.copy(f, f + ".bak-reopen-" + ts); save(f, dd)
    o.pop("_closed", None); save(p, d)
    print(f"REOPENED {seat} roles={','.join(back) or '-'} role={o['role']} file={p}" + (f" · 교대된 칸(복원 0): {';'.join(held)}" if held else "")); sys.exit(0)
shutil.copy(p, p + ".bak-close-" + ts)
role = o.get("role")
if role != "stop-ready":   # 이미 stop-ready 면 첫 닫기의 원래 role 을 덮지 않는다
    o["_closed_role"] = role
    if o.get("tick"): o["_closed_tick"] = o["tick"]   # r427 — --reopen 이 되돌린다
o["role"] = "stop-ready"; o["tick"] = None
o["_closed"] = collections.OrderedDict(by=by, at=now.isoformat(timespec="seconds"), reason=reason)
cells, froms = [], []
if verdict:   # R400 ② — 그 좌석 값인 최상위 `_*` 문자열 칸만 "" (다른 칸·행 삭제 0)
    o["_closed"]["verdict"] = verdict
    if dead == "1": o["_closed"]["dead"] = True   # r427 — role 은 stop-ready 그대로(틱 resume_rows·lint·stall 이 이 값으로 «재개 0» 을 판정)
    for f in files:
        dd = d if f == p else load(f)
        ks = [k for k, v in dd.items() if k.startswith("_") and isinstance(v, str) and v == seat] if isinstance(dd, dict) else []
        if not ks: continue
        for k in ks: dd[k] = ""
        if f != p: shutil.copy(f, f + ".bak-close-" + ts); save(f, dd)
        cells.append(f + ":" + ",".join(ks)); froms += [f + ":" + k for k in ks]
    if froms: o["_closed_from"] = sorted(set(o.get("_closed_from", []) + froms))
save(p, d)
print(f"MARKED\t{p}\t{o.get('_closed_role')}" + (f"\t{';'.join(cells) or '-'}" if verdict else ""))
PY
)"; rc=$?
[ "$REOPEN" = 0 ] || { printf '%s\n' "$OUT"; exit "$rc"; }
[ "$rc" = 0 ] || { printf '%s\n' "$OUT"; [ "$rc" = 3 ] && [ -n "$VERDICT" ] && exit 3; exit 1; }
FILE="$(printf '%s' "$OUT" | cut -f2)"; WAS="$(printf '%s' "$OUT" | cut -f3)"; CELLS="$(printf '%s' "$OUT" | cut -f4)"
vlog() { [ -z "$VERDICT" ] || { mkdir -p "$DATA/.fable-team/state" && printf '%s\tverdict=%s\t%s\trecord=%s\tcells=%s\tkill=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$VERDICT" "$SEAT" "$REC" "$CELLS" "$1" >> "$DATA/.fable-team/state/seat-close-verdict.log"; }; }
if [ "$DEAD" = 1 ]; then   # r427 — 죽은 좌석: kill 할 것 0 · 명부만 닫는다
  vlog dead; [ "$CELLS" = - ] && finish 0 "CLOSED-DEAD $SEAT record=$RK handoff=$CELLS" || finish 0 "CLOSED-DEAD $SEAT record=$RK handoff=$CELLS" "  - 교대 0 · planner 1줄: 비운 칸 $CELLS — 후임 지정은 planner(자동 선정 0)"
fi
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
  vlog fail-reap; finish 1 "CLOSE-FAIL reap ${RL:-left=?} rc=$r — $SEAT 세션 보존(명부 표기는 남음 file=$FILE)"
}
if tmux has-session -t "=$SEAT" 2>/dev/null; then
  [ -n "$VERDICT" ] || lineage_ok || finish 3 "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])"   # --verdict = 판정 승인 1건 + 재개 기록 확인됨
  reap
  if [ -n "$(tmux show-options -qv -t "=$SEAT" @zc_v65_active 2>/dev/null)" ]; then
    tmux set-option -t "=$SEAT" -u @zc_v65_active || { vlog fail-tag; finish 1 "FAIL tag $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; }
  fi
  tmux kill-session -t "=$SEAT" || { vlog fail-kill; finish 1 "FAIL kill $SEAT — kill-session 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; }
  KILL=ok
else reap; KILL=none; fi
[ -z "$VERDICT" ] || { vlog "$KILL"; finish 0 "CLOSED-ROLE $SEAT verdict=$VERDICT record=$REC cells=$CELLS kill=$KILL reap left=0 rc=0"; }   # r960 ⓣⓤ — 결과 줄 형식 그대로 · NORECORD 줄은 finish 가 붙인다
finish 0 "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=$KILL reap left=0 rc=0"
