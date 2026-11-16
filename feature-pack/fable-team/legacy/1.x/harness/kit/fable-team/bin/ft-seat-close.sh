#!/usr/bin/env bash
# ft-seat-close.sh <좌석> --reason "<1줄>" [--seats <파일>] — «세션만 닫기»(R297): tmux 세션 kill + 명부 행 role=stop-ready·_closed 표기. nano-close 를 안 타고 세션만 끈 좌석이 명부 행 잔류로 ft-tick «죽은 좌석 재개» 대상이 되어 되살아나는 일을 막는다(v65 판정 2050 노출 나노).
#   틱 코드 변경 0 — resume_rows 가 role=stop-ready 행을 이미 뺀다. 워크트리·브랜치·원장·행 삭제 0(지우는 건 nano-close 만). 명부 = --seats · FT_SEATS_JSON · <루트>/.fable-team/seats*.json 중 키 <좌석> 을 가진 파일 정확히 1개(ft-seat-retire.sh 와 같은 규칙).
#   거절: 좌석이 어느 명부의 `_*` 문자열 칸(_master·_arch·_hil_route·_desk …) 값 = 현역 역할 좌석 → 승계 경로(ft-successor-open · ft-seat-retire).
#   순서(되돌림 쉬운 것 먼저): ①명부 .bak-close-<ts> + 표기(tmp→mv) ②@zc_v65_active 태그 해제 ③세션 kill. ②③ 실패 = FAIL rc 1(표기는 남김 — 재개 0 이 안전한 쪽). ③ 은 표준승인 범위만: 같은 계보(# 앞)로 더 큰 번호 세션이 살아 있고 (그 좌석 재개 기록 ~/.claude/state/seat-resume/<좌석>.json 있음 ∨ 더 큰 번호 2개+ 생존)일 때. 아니면 kill=held rc 3(표기는 남음). r1013 — 재개 기록은 «이미 있으면 쓴다»: --verdict 는 살아 있든 죽었든 언제나 --keep-existing 을 넘기고(기존 기록 있으면 새 시도 0) `0:0 RESUME kept`(살아 있는 좌석 + 기존 기록)도 kept 로 받는다(1차 CLOSE-FAIL 뒤 2차가 막히던 자리).
#   rc 0 = CLOSED-SESSION · 1 = REJECT/FAIL(사유 stdout) · 2 = usage · 3 = kill=held · 4 = WAIT(r2080 승계 창 안 후계 [레디] 기다림 · 명부 쓰기 0 · kill 0). kill 근거: 전역 「tmux 세션 정리 표준승인 2026-07-11」(kill-server 아님).
#   R400 «역할 좌석 닫기» `--verdict <번호>`(판정 2304 — 사람 승인 1건의 번호): ⓪실행 세션 == 좌석 → REJECT ①재개 기록(ft-seat-retire --record-only --verdict · env FT_SEAT_RETIRE_BIN) 실패 = HELD rc 3(명부 쓰기 0 · kill 0) ②행 있음 → 위 표기 + _closed.verdict + 어느 명부든 값 == 좌석인 최상위 `_*` 문자열 칸 "" (파일마다 .bak-close-<ts> · tmp→mv) · 행 없음 = NOROW rc 3(kill 0 · 그 리포 루트에서) ③lineage_ok 건너뜀 → 태그 해제 → kill · 원장 <ft_data_root>/.fable-team/state/seat-close-verdict.log 1행/좌석. --verdict 없는 호출은 위 동작 그대로.
#   r1319 close-check C7 — [인계] 는 보냈는데 retire 를 안 돌린 채 닫으려 하면 close-check 가 REJECT 한다. 면제 = --verdict(사람 판정 1건 · R400) 와 «후계 행 없음»(개설 실패·승계 취소) 둘뿐 — --verdict 닫기는 close-check 에 --verdict 를 넘긴다. · r427 죽은 좌석(--verdict · tmux 세션 없음): 재개 기록 = --keep-existing(기존 보존 · 없으면 대화 기록 탐색 · 둘 다 없으면 NORECORD 도 진행) → 위 ② 표기 + _closed.dead · kill 0 · 비운 칸은 행 `_closed_from`. `--reopen <좌석>` = zombie-clean resume 으로 되살린 좌석: role=_closed_role(없으면 active)·tick 복원 · _closed* 제거 · `REOPENED <좌석> roles=<칸들>`.
#   ★r960 — 닫기 결과 출력은 finish() "하나"★: 어느 종료 갈래(CLOSED-ROLE · CLOSED-DEAD · CLOSED-SESSION · HELD · FAIL)든 결과 줄 다음에 record=NORECORD 면 `NORECORD <좌석> <사유>` 1줄을 반드시 남긴다(갈래마다 출력을 따로 두면 다음 갈래가 또 빠뜨린다 — DA r1·r2 반례). 갈래 안 exit 는 이 함수로만. pi 좌석 재개 기록 근거 = ft-seat-retire.sh ⓒ(pi 세션 파일) · model 은 ft_roster_lib._pi_model · 살아 있는 좌석의 NORECORD 수용은 «명부 agent 칸 = pi» 일 때만(r4: 출력 글자 판정 0). ★r5★ 명부 경로·행·agent·role·재개 기록 경로는 «입구에서 1회» 확정(ft_roster_lib.seat_facts)해 갈래·자식에 값으로 넘긴다 — 확정 밖 명부에 같은 좌석이 다른 agent/role 로 있으면 판정 아님(REJECT rc 1 · 명부 쓰기 0 · kill 0).
#   r2075 수동 닫기 지원 — «표준승인 밖» 자리(manual_close)만: 부른 좌석이 planner _master·_desk 이면 자율 모드(ft_autonomy_mode)를 읽어 ON = ft-proxy-decide --kind seat-close 1회(«대리» 원장 1줄) 뒤 기존 닫기 · OFF = held rc 3 + «[오빠 질문 필요]» 1줄 · 그 밖 좌석 = 기존 held 그대로.
#   r1481 ``--verdict`` 원장 관문 — ②③ 면제의 근거는 «사람 판정 1건»이므로 번호가 planner 판정 원장(``${FT_TEAMS_REF:-origin/main}``:``design/teams/planner/VERDICTS-planner-*.md`` · fetch 0)에 실재할 때만 닫는다. 못 읽음·번호 없음 = REJECT rc 1(명부 쓰기 0 · kill 0).
#   r1568 — 승계 끝 확인: reap 이 남기면 «1회 더» 보고(짧은 git 자식이 스스로 사라지는 사이), kill 뒤에 «세션 부재 ∧ 최종 재조사 left=0» 을 한 번 더 재서 CLOSED(둘 중 하나라도 거짓 = CLOSE-FAIL rc≠0 — 거짓 성공 0). 최종 실패 = 기록 1개(<루트>/.fable-team/state/close-fail/<좌석>.txt · 좌석·담당·이유·남은 것·다음 실행) + master 쪽지 1통(다음 닫기 성공 때만 지운다) · 최종 재조사 원문(reap 줄)은 stderr 에 남는다.
set -uo pipefail
# r1718 A5·A7: 자기 감싸기 1곳 — 본 작업은 자식 1회 · 출력·rc 그대로 · rc 1 REJECT 에 «진행» 아닌 사유가 있으면 desk [크리티컬] 1통 · rc 0 = 해결
[ "${FT_CRITICAL_IN:-}" = "$PPID" ] || [ "${FT_CRITICAL_OFF:-0}" = 1 ] || [ ! -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-critical-notify.sh" ] || exec bash "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-critical-notify.sh" --wrap ft-seat-close "${BASH_SOURCE[0]:-$0}" "$@"   # r1718-mut:seatcall
#   r1656 `--done`(2.0 세션 수명 · 팀장 role=master 만): 관문 넷 ①우편함 큐+로그의 마지막 발신 머리 `[다음 없음` ②ft-seat-open-work rc0(7초) ③close-check --no-ready rc0 ④retire --record-only --verdict <①seq> + 기록 실재 — 하나라도 아니면 REJECT rc1(쓰기 0 · kill 0). 통과 = 행 _closed.done{ts,seq} · role·_master 칸 그대로 · reap→태그→kill→final · CLOSED-DONE. 틱은 그 행을 받을 일 0 이면 «쉬는 중» 으로 본다.
USAGE="usage: $0 <좌석> --reason \"<1줄>\" [--seats <파일>] [--verdict <번호> | --done] | $0 --reopen <좌석> [--seats <파일>]"
REOPEN=0; [ "${1:-}" != --reopen ] || { REOPEN=1; shift; }
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; REASON=""; ARG=""; VERDICT=""; REC=""; NOLINE=""; DEAD=0; RN=""; DONE=0; DSEQ=""   # RN = renamed_ok 가 확정한 후계(r1691)
while [ $# -gt 0 ]; do case "$1" in --reason) REASON="${2:-}"; shift 2;; --seats) ARG="${2:-}"; shift 2;; --reopen) REOPEN=1; shift;; --done) DONE=1; shift;; --verdict) VERDICT="${2:-}"; [[ "$VERDICT" =~ ^[0-9]+$ ]] || { echo "$USAGE — --verdict <번호>" >&2; exit 2; }; shift 2;; *) echo "unknown $1" >&2; echo "$USAGE" >&2; exit 2;; esac; done
[ "$REOPEN" = 1 ] || [ -n "${REASON//[[:space:]]/}" ] || { echo "$USAGE — --reason 필요" >&2; exit 2; }
[ "$REOPEN" = 0 ] || [ -z "$VERDICT" ] || { echo "$USAGE — --reopen 과 --verdict 는 같이 쓰지 않는다" >&2; exit 2; }
[ "$DONE" = 0 ] || { [ -z "$VERDICT" ] && [ "$REOPEN" = 0 ]; } || { echo "$USAGE — --done 은 --verdict·--reopen 과 같이 쓰지 않는다" >&2; exit 2; }
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
FACTS="$(cd "$HERE" && python3 -c 'import sys;from ft_roster_lib import seat_facts;print("\x1f".join(seat_facts(*sys.argv[1:6])))' "$ARG" "${FT_SEATS_JSON:-}" "${ROOT:-.}" "$SEAT" "${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}")" || finish 1 "${FACTS:-REJECT 좌석 사실 확정 실패 — 판정 안 함(명부 쓰기 0 · kill 0)}"   # r5 ①② — 명부 경로·행·agent·role·재개 기록 경로 «입구 1회» 확정(명부 후보 2개+ · 명부 불일치 = REJECT rc 1)
IFS=$'\x1f' read -r SEATS_FILE AGENT ROLE RECF MST <<<"$FACTS"; if [ -n "$VERDICT" ]; then   # r1481 — ②③ 면제 근거(사람 판정 1건)를 원장에서 먼저 확인한다 — close-check «앞» · --verdict 있을 때만(빠른 종료 = 쓰기 0 · kill 0)
  . "$HERE/ft-verdict-row.sh" && . "$HERE/ft-team-lib.sh" || finish 1 "REJECT $SEAT 판정 원장 확인 불가(도우미 ft-verdict-row.sh·ft-team-lib.sh 없음 — 설치본 bin) — 쓰기 0 · kill 0"; VR="${FT_TEAMS_REF:-origin/main}"; VC="$(ft_team_cands_ref "${ROOT:-.}" planner "$VR" 2>/dev/null)" || finish 1 "REJECT $SEAT 판정 원장 확인 불가($VR:design/TEAMS.md) — 쓰기 0 · kill 0"   # 원장 조회 = ft-index-lint.sh:47 과 같은 호출(명단 ref · 함수 복사 0)
  VH=0; RE="$(fv_row_re "$VERDICT" 2>/dev/null)"; RRC=$?; [ "$RRC" = 0 ] && [ -n "$RE" ] || finish 1 "REJECT $SEAT 판정 $VERDICT 꼴이 원장 꼴(숫자)이 아님(fv_row_re rc=$RRC) — 쓰기 0 · kill 0"   # DA 반례 1(r1481 r2) — 빈 정규식이면 git grep -E "" 가 원장 아무 줄에나 일치한다(통과 0)
  while IFS= read -r C; do [ -n "$C" ] || continue; git -C "${ROOT:-.}" grep -q -E "$RE" "$VR" -- "${C#"${ROOT:-.}"/}/VERDICTS-planner-*.md" 2>/dev/null; VRC=$?; case "$VRC" in 0) VH=1; break;; 1) ;; *) finish 1 "REJECT $SEAT 판정 원장 확인 불가(git grep rc=$VRC) — 쓰기 0 · kill 0";; esac; done <<< "$VC"   # rc 1 = 그 후보에 없음(다음 후보) · rc>1 = 판정 불가(하드 룰 20)
  [ "$VH" = 1 ] || finish 1 "REJECT $SEAT 판정 $VERDICT 이 $VR 원장(VERDICTS-planner-*.md)에 없음 — 쓰기 0 · kill 0"   # 두 꼴 다 · 번호 경계 엄격(`| 41380 |` · `- **4138a**` 는 4138 이 아님 = fv_row_re)
fi
dead_seat() {   # r1520 dead-seat 갈래(DESIGN-r1498 §5 ⓑ) — 입구 = close-check REJECT «[인계] 없음» · 조건 3 전부 참 = retire --record-only → 명부 _closed → CLOSED-DEAD(kill 0) · 하나라도 거짓·판정 불가 = 멈춤 1줄(명부 쓰기 0 · 하드 룰 20·23)
  [ -z "$VERDICT" ] && [[ "$1" == *"[인계] 없음"* ]] || return 1
  local o r n s="명부 쓰기 0 · kill 0"; o="$(tmux has-session -t "=$SEAT" 2>&1)"; r=$?
  [ "$r" != 0 ] || { w="$(python3 - "${ROOT:-.}/.fable-team/state/successor/$SEAT.json" "$SEAT" "${FT_NOW:-}" "${FT_HANDOVER_READY_WAIT_S:-}" <<'PY5'
import datetime, json, sys, time   # r2089 C1 — 도달 파일(개설 도구) reached_at 나이 0..창 = 승계 중 · 그 밖·못 읽음 = 지금 REJECT(C2)
p, seat, now, v = sys.argv[1:5]; s = int(v) if v.isdigit() else 600
try: d = json.load(open(p, encoding="utf-8")); n = d["successor"]; a = float(now or time.time()) - datetime.datetime.strptime(d["reached_at"], "%Y-%m-%dT%H:%M:%S%z").timestamp()
except (OSError, ValueError, KeyError, TypeError): sys.exit(1)
if isinstance(n, str) and n and 0 <= a <= s: print(f"WAIT {seat} 후계 {n} [인계] 기다림({int(a)}초 · 창 {s}초) — bash mbox.sh handover {seat} {n} (명부 쓰기 0 · kill 0)"); sys.exit(0)
sys.exit(1)
PY5
)" && finish 4 "$w"; finish 1 "REJECT $SEAT [인계] 없음 · 세션 살아 있음 — handover 먼저 또는 --verdict($s)"; }
  case "$o" in *"can't find session"*|*"no server running"*|*"No such file or directory"*) ;; *) finish 1 "REJECT $SEAT dead-seat 판정 불가 생존 확인(tmux rc=$r ${o%%$'\n'*}) — $s";; esac   # tmux 실패를 «세션 없음» 으로 읽지 않는다
  o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" --dry-run 2>/dev/null)"; r=$?; n="$(printf '%s\n' "$o" | sed -n 's/^reap .* found=\([0-9][0-9]*\) dry-run.*/\1/p' | tail -1)"
  [ "$r" = 0 ] && [ -n "$n" ] || finish 1 "REJECT $SEAT dead-seat 판정 불가 생존 확인(reap --dry-run rc=$r) — $s"; [ "$n" = 0 ] || finish 1 "REJECT $SEAT dead-seat 조건 미충족 생존 확인(그 이름 pane 자손 $n) — $s"
  o="$(python3 - "$HERE" "$SEATS_FILE" "$SEAT" <<'PY3'
import glob, os, re, sys
sys.path.insert(0, sys.argv[1]); from ft_roster_lib import load
f, seat = sys.argv[2:4]; d = load(f) if f else None; o = d.get(seat) if isinstance(d, dict) else None; n = o.get("_replaced_by") if isinstance(o, dict) else None
if not (isinstance(n, str) and n): print("명부 참조(_replaced_by 없음)"); sys.exit(4)
for g in sorted({f, *glob.glob(os.path.dirname(f) + "/seats*.json")}):
    dd = load(g)
    if not isinstance(dd, dict): print("판정 불가 명부 참조(%s 못 읽음)" % g); sys.exit(1)
    ks = [k for k, v in dd.items() if k.startswith("_") and v == seat]
    if ks: print("명부 참조(%s:%s 칸 값)" % (os.path.basename(g), ",".join(ks))); sys.exit(4)
print(int(re.sub(r"#\d+$", "", n) == re.sub(r"#\d+$", "", seat)))   # 1 = 후계가 같은 역할 우편함(mbox_conf.role_key)
PY3
)"; r=$?; case "$r" in 0) ;; 4) finish 1 "REJECT $SEAT dead-seat 조건 미충족 $o — $s";; *) finish 1 "REJECT $SEAT dead-seat ${o:-판정 불가 명부 참조(rc=$r)} — $s";; esac
  n="$(python3 "$G" peek "$SEAT" 2>/dev/null)"; r=$?; n="$(printf '%s\n' "$n" | sed -n 's/^pending=\([0-9][0-9]*\).*/\1/p' | head -1)"; [ "$r" = 0 ] && [ -n "$n" ] || finish 1 "REJECT $SEAT dead-seat 판정 불가 미처리 보존(peek rc=$r) — $s"   # DA#10 R1 — 조회 실패의 부분 출력은 근거 아님
  [ "$n" = 0 ] || [ "$o" = 1 ] || finish 1 "REJECT $SEAT dead-seat 조건 미충족 미처리 보존(pending $n · 후계 역할 우편함 아님) — $s"
  o="$(bash "${FT_SEAT_RETIRE_BIN:-$HERE/ft-seat-retire.sh}" "$SEAT" --record-only --keep-existing --seats "$SEATS_FILE" 2>&1)"; r=$?; NOLINE="$(printf '%s\n' "$o" | grep -m1 '^NORECORD ')"
  case "$r $(printf '%s\n' "$o" | grep -m1 -E '^(RESUME (ok|kept) |NORECORD )')" in "0 RESUME ok "*) RK=new;; "0 RESUME kept "*) RK=kept;; "0 NORECORD "*) RK=NORECORD; REC=NORECORD;; *) finish 3 "HELD $SEAT dead-seat 재개 기록 실패 — $s · rc=$r ${o%%$'\n'*}";; esac
  [ "$RK" = NORECORD ] || { REC="$(printf '%s\n' "$o" | grep -m1 '^RESUME ')"; REC="${REC#RESUME * }"; REC="${REC%%[[:space:]]*}"; }; DS=1
}
G="${FT_MBOX_PY:-${ROOT:-.}/.fable-team/comm/mbox.py}"; [ "$REOPEN" = 1 ] || [ "$DONE" = 1 ] || [ ! -f "$G" ] || GO="$(python3 "$G" close-check "$SEAT" ${VERDICT:+--verdict} 2>&1)" || { [ $? != 4 ] || finish 4 "$(printf '%s\n' "$GO" | grep -m1 '^WAIT ') (명부 쓰기 0 · kill 0)"; dead_seat "$GO" || finish 1 "REJECT $SEAT 승계 마무리 전 닫기 거절(r1116 ②③ · 명부 쓰기 0 · kill 0) — ${GO:-close-check 실패}"; }   # r2080 B2 — close-check rc 4(승계 창 안 [레디] 기다림) = WAIT 결과 줄 + rc 4(rc 1 아님 = [크리티컬] 0)   # r5 ③ 확정 값은 갈래·자식에 «값으로»(재해석 0) · r1116 ②③ 후계 있는 옛 세션 = 미표시 0 + [인계] 뒤 후계 [레디] 항목 전부 «받음»
if [ "$DONE" = 1 ]; then   # r1656 ⓐⓑ — 팀장만 · 관문 넷(첫 실패 사유 1줄 · 쓰기 0 · kill 0)
  s="쓰기 0 · kill 0"; [ "$ROLE" = master ] || finish 1 "REJECT $SEAT --done 은 팀장만(role=${ROLE:--}) — $s"
  [ "$BY" != "$SEAT" ] || finish 1 "REJECT $SEAT 은 지금 이 명령을 실행하는 세션 자신 — 다른 좌석에서 닫는다($s)"
  . "$HERE/ft-harness-root.sh" && DATA="$(ft_data_root "$HERE")" || finish 1 "REJECT $SEAT 원장 루트를 못 풂 — $s"
  DSEQ="$(python3 - "${FT_MBOX_DIR:-$(dirname "$G")}" "$SEAT" "${FT_SEAT_OPEN_WORK:-$HERE/ft-seat-open-work.py}" "${ROOT:-.}" <<'PY4'
import json, os, subprocess, sys
mdir, seat, ow, root = sys.argv[1:5]; best, body = -1, ""
for n in ("mailbox.jsonl", "mailbox.log.jsonl"):   # ① 큐+로그에서 그 좌석이 보낸 가장 큰 seq(r1647 _last_sent 와 같은 규칙)
    try: ls = open(os.path.join(mdir, n), encoding="utf-8", errors="replace").read().splitlines()
    except FileNotFoundError: continue
    except OSError as e: print("① 판정 불가 우편함 %s %s" % (n, type(e).__name__)); sys.exit(1)
    for l in ls:
        try: r = json.loads(l); q = int(r.get("seq") or 0)
        except (ValueError, TypeError, AttributeError): continue
        if r.get("from") == seat and q > best: best, body = q, str(r.get("body") or "")
if not body.lstrip().startswith("[다음 없음"): print("① 마지막 발신 머리가 [다음 없음 아님(seq=%s «%s»)" % (best, body.lstrip()[:30])); sys.exit(1)
try: rc = subprocess.run([sys.executable, ow, seat, "--root", root, "--mbox-dir", mdir], capture_output=True, timeout=7).returncode   # ② 하드 룰 12
except subprocess.TimeoutExpired: rc = "시간 초과 7초"
if rc != 0: print("② 받을 일 %s(open-work rc=%s)" % ("있음" if rc == 1 else "판정 불가", rc)); sys.exit(1)
print(best)
PY4
)" || finish 1 "REJECT $SEAT --done ${DSEQ:-①② 판정 불가} — $s"
  GO="$(python3 "$G" close-check "$SEAT" --no-ready 2>&1)" || finish 1 "REJECT $SEAT --done ③ ${GO%%$'\n'*} — $s"
  RO="$(bash "${FT_SEAT_RETIRE_BIN:-$HERE/ft-seat-retire.sh}" "$SEAT" --record-only --verdict "$DSEQ" --seats "$SEATS_FILE" 2>&1)"; rrc=$?; R4="$(printf '%s\n' "$RO" | grep -m1 -E '^RESUME (ok|kept) ')"; R4="${R4#RESUME * }"; R4="${R4%% (명부 model 다름: *}"; R4="${R4%% · 이전 기록 *}"   # DA#10 R1 — 공백 있는 경로도 통째로(retire 112·134줄 꼬리만 뗀다)
  [ "$rrc" = 0 ] && [ -n "$R4" ] && [ -f "$R4" ] || finish 1 "REJECT $SEAT --done ④ 재개 기록 실패(rc=$rrc ${RO%%$'\n'*}) — $s"; REC="$R4"
fi
if [ -n "$VERDICT" ]; then   # R400 ⓪① — 원장 루트를 먼저 풀고(못 풀면 쓰기 0) 재개 기록 → 실패면 명부·kill 0
  [ "$BY" != "$SEAT" ] || { echo "REJECT $SEAT 은 지금 이 명령을 실행하는 세션 자신 — 다른 좌석에서 닫는다"; exit 1; }
  . "$HERE/ft-harness-root.sh" && DATA="$(ft_data_root "$HERE")" || { echo "REJECT 원장 루트를 못 풂 — FT_ROOT=<설치본 루트> 를 주고 --seats <그 루트>/.fable-team/seats.json 로 (쓰기 0 · kill 0)"; exit 1; }
  tmux has-session -t "=$SEAT" 2>/dev/null || DEAD=1   # r427 — 세션 없음 = pane 결속 불가 → 기존 기록 보존 · 없으면 대화 기록 탐색 · r1013 — 살아 있는 좌석도 기존 기록이 있으면 그대로 쓴다(기록 없으면 ft-seat-retire 가 지금 동작 그대로)
  ROUT="$(bash "${FT_SEAT_RETIRE_BIN:-$HERE/ft-seat-retire.sh}" "$SEAT" --record-only --verdict "$VERDICT" ${SEATS_FILE:+--seats "$SEATS_FILE"} --keep-existing 2>&1)"; rrc=$?; NOLINE="$(printf '%s\n' "$ROUT" | grep -m1 '^NORECORD ')"   # r960 ⓡⓣ — 어느 갈래(수용·HELD·죽은 좌석)든 NORECORD 원문 줄은 finish 가 책임진다 — case 보다 먼저 잡는다 · r5: --seats = 확정 경로를 ARG 유무 무관하게 항상 넘긴다
  held() { if [ -n "$NOLINE" ]; then finish 3 "HELD $SEAT 재개 기록 실패 — 명부 쓰기 0 · kill 0 · rc=$rrc"; else finish 3 "HELD $SEAT 재개 기록 실패 — 명부 쓰기 0 · kill 0 · rc=$rrc $(printf '%s' "$ROUT" | head -1)"; fi; }   # r5: 수용 판정 근거 = 입구에서 확정한 $AGENT 하나(명부 다시 읽기 0)
  # PI ADAPTER BEGIN
  PI_DEADLY=0; case "$rrc $NOLINE" in "0 NORECORD "*"pi 좌석 tmux 없음"*) PI_DEADLY=1;; esac   # r1679 — retire 가 이미 «PI_DEAD(pi 좌석 tmux 없음)» 로 판정한 죽은 좌석은 pane 이 없어 결속 확인이 언제나 실패한다 → 그 판정 하나만 믿고 건너뛴다(판정 불가 = rrc≠0 이라 여기 못 온다 · seat-close 자신의 DEAD 로는 가르지 않는다)
  if [ "$AGENT" = pi ] && [ "$rrc" = 0 ] && [ "$PI_DEADLY" = 0 ]; then
    python3 "$HERE/ft_seat_bind.py" "$SEAT" --expect "$RECF" >/dev/null || { rrc=1; held; }
  fi
  # PI ADAPTER END
  case "$DEAD:$rrc $ROUT" in ?":0 RESUME ok "*) RK=new;; ?":0 RESUME kept "*) RK=kept;; "1:0 NORECORD "*) RK=NORECORD;; "0:0 NORECORD "*) [ "$AGENT" = pi ] && RK=NORECORD || held;; *) held;; esac   # r960 ⓓ: 살아 있는 좌석의 NORECORD 수용 = 명부 agent 칸이 pi 일 때만(산출 커밋은 브랜치 보존) · claude·못 읽음은 그대로 HELD rc 3
  REC="${ROUT#RESUME * }"; REC="${REC%%[[:space:]]*}"; [ "$RK" != NORECORD ] || REC=NORECORD
fi
OUT="$(python3 - "${ARG:-${FT_SEATS_JSON:-}}" "${ROOT:-.}" "$SEAT" "$REASON" "$BY" "$VERDICT" "$REC" "$HERE/ft-seat-close.sh" "$DEAD" "$REOPEN" "$DSEQ" <<'PY'
import json, glob, shutil, shlex, datetime, collections, os, sys
arg, root, seat, reason, by, verdict, rec, tool, dead, reopen, done = sys.argv[1:12]
sys.path.insert(0, os.path.dirname(tool))   # 명부 읽기·원자 쓰기(쓰기 중 죽어도 원본 무손상) = 같은 폴더 lib(retire 와 공용)
from ft_roster_lib import load, dump as save, bak_cap
files = [arg] if arg else sorted(glob.glob(root + "/.fable-team/seats*.json"))
for f in (files if not (verdict or done or reopen == "1") else []):   # ⓐ 현역 역할 좌석(_master·_arch·_hil_route·_desk …)은 세션만 닫지 않는다(--verdict = 판정 승인 경로만 예외)
    d = load(f)
    if isinstance(d, dict) and any(k.startswith("_") and v == seat for k, v in d.items()):
        print(f"REJECT {seat} 은 {f} 의 _ 칸 값(현역 역할 좌석) — 승계 경로(ft-successor-open · ft-seat-retire) 로 · 후계 없이 닫으려면 --verdict <판정번호>(R400 · 사람 승인 1건)"); sys.exit(1)
cand = [f for f in files if isinstance(load(f), dict) and seat in load(f)]
if verdict and not cand:   # R400 r3 §D — 명부 루트(cwd)와 원장 루트(FT_ROOT)를 같이 주는 한 줄(자동 탐색 0)
    print(f"NOROW {seat} 명부 행 없음({arg or root + '/.fable-team/seats*.json'}) — 기록 {rec} · kill 0 · 다른 리포 좌석이면: FT_ROOT=<그 설치본 루트> {tool} {shlex.quote(seat)} --verdict {verdict} --reason {shlex.quote(reason)} --seats <그 루트>/.fable-team/seats.json"); sys.exit(3)
def ft2_intent(seat, root):   # r1924 — 명부 밖 2.0 나노 = <루트>/.fable-team/teams/<팀>/runtime/launch/*.intent 의 FT2_HOLDER == seat 인 최신 1개(읽기만 · 못 읽음 = None)
    t = seat.split("-"); rt = f"{root}/.fable-team/teams/{t[1] if len(t) > 2 else '-'}/runtime"; hit = []
    for f in (glob.glob(rt + "/launch/*.intent") if len(t) > 2 and t[2] == "nano" else []):
        try: hit += [(os.path.getmtime(f), f)] if json.load(open(f, encoding="utf-8")).get("FT2_HOLDER") == seat else []
        except (OSError, ValueError, AttributeError): pass
    return (rt, os.path.basename(max(hit)[1])[:-7].rsplit("@", 1)) if hit else None
i = None if cand else ft2_intent(seat, root)
if i and len(i[1]) == 2: print(f"REJECT 명부 후보 0 (키 {seat}) — 2.0 나노(ft2 intent {i[1][0]}@{i[1][1]}) · 닫기 = {i[0]}/keeper-verdict-close.tsv 에 «{i[1][0]}\\t{i[1][1]}\\t판정 <N>\\t<승인 좌석> #<seq>» 1줄(사람·master) → keeper 다음 바퀴 · 이 도구 쓰기 0 · kill 0"); sys.exit(1)
if len(cand) != 1: print(f"REJECT 명부 후보 {len(cand)}개 (키 {seat}) — --seats 로 지정"); sys.exit(1)
p = cand[0]; d = load(p); o = d.get(seat)
if not isinstance(o, dict): print(f"REJECT {p} 의 {seat} 행이 객체가 아님"); sys.exit(1)
now = datetime.datetime.now(); ts = now.strftime("%Y%m%d%H%M%S")
if reopen == "1":   # r427 ⓖ — 닫힘 표기 되돌림 · 비웠던 칸은 지금도 "" 일 때만 다시 채운다(그새 교대된 칸은 덮지 않음)
    if not o.get("_closed"): print(f"NOOP {seat} 닫힌 행 아님(_closed 없음) file={p}"); sys.exit(0)
    shutil.copy(p, p + ".bak-reopen-" + ts); bak_cap(p, "reopen"); back, held = [], []
    o["role"] = o.pop("_closed_role", None) or "active"; o["tick"] = o.pop("_closed_tick", o.get("tick"))
    for c in o.pop("_closed_from", []):
        f, _, k = c.rpartition(":"); dd = d if f == p else load(f); cur = dd.get(k) if isinstance(dd, dict) else None
        if cur not in ("", seat): held.append(f"{c}={cur}"); continue
        dd[k] = seat; back.append(k)
        if f != p: shutil.copy(f, f + ".bak-reopen-" + ts); bak_cap(f, "reopen"); save(f, dd)
    o.pop("_closed", None); save(p, d)
    print(f"REOPENED {seat} roles={','.join(back) or '-'} role={o['role']} file={p}" + (f" · 교대된 칸(복원 0): {';'.join(held)}" if held else "")); sys.exit(0)
shutil.copy(p, p + ".bak-close-" + ts); bak_cap(p, "close")
if done:   # r1656 ⓒ — role·tick·_master 칸 그대로 · _closed.done 만(틱 = 받을 일 0 이면 쉬는 중)
    at = now.isoformat(timespec="seconds"); o["_closed"] = collections.OrderedDict(by=by, at=at, reason=reason, done=collections.OrderedDict(ts=at, seq=int(done)))
    save(p, d); print(f"MARKED\t{p}\t{o.get('role')}"); sys.exit(0)
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
        if f != p: shutil.copy(f, f + ".bak-close-" + ts); bak_cap(f, "close"); save(f, dd)
        cells.append(f + ":" + ",".join(ks)); froms += [f + ":" + k for k in ks]
    if froms: o["_closed_from"] = sorted(set(o.get("_closed_from", []) + froms))
save(p, d)
print(f"MARKED\t{p}\t{o.get('_closed_role')}" + (f"\t{';'.join(cells) or '-'}" if verdict else ""))
PY
)"; rc=$?
[ "$REOPEN" = 0 ] || { printf '%s\n' "$OUT"; exit "$rc"; }; [ "$rc" = 0 ] || { printf '%s\n' "$OUT"; [ "$rc" = 3 ] && [ -n "$VERDICT" ] && exit 3; exit 1; }
FILE="$(printf '%s' "$OUT" | cut -f2)"; WAS="$(printf '%s' "$OUT" | cut -f3)"; CELLS="$(printf '%s' "$OUT" | cut -f4)"
[ "${DS:-0}" = 0 ] || finish 0 "CLOSED-DEAD $SEAT record=$RK file=$FILE role_was=$WAS kill=0 dead-seat(세션 없음 · 자손 0 · _replaced_by · 미처리 보존)"   # r1520 — 죽일 것 0 · reap·kill 호출 0
vlog() { [ -z "$VERDICT$DSEQ" ] || { mkdir -p "$DATA/.fable-team/state" && printf '%s\tverdict=%s\t%s\trecord=%s\tcells=%s\tkill=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "${VERDICT:-done-$DSEQ}" "$SEAT" "$REC" "$CELLS" "$1" >> "$DATA/.fable-team/state/seat-close-verdict.log"; }; }
# ③ kill 범위 = 전역 표준승인(2026-07-11): 계보 최신은 보존 · 직전 세대는 «재개 기록 있음 ∨ 더 큰 번호 2개+ 생존(keep-last-2)» 일 때만. 밖은 kill=held rc 3(나노는 ft-nano-close · 그 밖은 [HIL]).
lineage_ok() {
  local base="${SEAT%#*}" n="${SEAT##*#}" up=0 s rec="$RECF"
  [ "$base" != "$SEAT" ] && [[ "$n" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r s; do [ "${s%#*}" = "$base" ] && [[ "${s##*#}" =~ ^[0-9]+$ ]] && [ "${s##*#}" -gt "$n" ] && up=$((up+1)); done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  [ "$up" -ge 2 ] || { [ "$up" -ge 1 ] && [ -f "$rec" ]; }
}
# r1691 — 이름 접두가 바뀐 승계(byz-aifp-arch-pi#0 → aifp-ft-arch-pi#0): 옛 행 _replaced_by=N(비어 있지 않은 문자열) ∧ 같은 파일 N 행 있음 ∧ 그 행 _replaces 에 옛 좌석 ∧ N 행에 _replaced_by 없음(현역) ∧ tmux "=N" 생존 ∧ 재개 기록($RECF) 있음 — «모두» 설 때만 같은 표준 닫기.
#   _replaces 는 list 일 때만·원소 정확 일치만(문자열 "… #00"·객체 {좌석:false} = 꼴 불일치 → held · DA R1).
#   넓히는 쪽이라 모르면 닫지 않는다(명부 읽기·꼴 불일치·tmux 조회 실패 = 거짓 · held 그대로 · 하드 룰 2). 통과하면 결과 줄 끝에 lineage=renamed:<N>.
renamed_ok() {
  local n
  n="$(python3 - "$FILE" "$SEAT" <<'PY2'
import json, sys
f, seat = sys.argv[1:3]
try: d = json.load(open(f, encoding="utf-8"))
except (OSError, ValueError): sys.exit(1)
o = d.get(seat) if isinstance(d, dict) else None
n = o.get("_replaced_by") if isinstance(o, dict) else None
nxt = d.get(n) if isinstance(n, str) and n else None
if not isinstance(nxt, dict) or nxt.get("_replaced_by") or not isinstance(nxt.get("_replaces"), list) or seat not in nxt["_replaces"]: sys.exit(1)   # 리스트일 때만 · 원소 정확 일치(문자열·객체는 꼴 불일치 = held)
print(n)
PY2
)" || return 1
  [ -n "$n" ] || return 1
  tmux has-session -t "=$n" 2>/dev/null || return 1
  [ -f "$RECF" ] || return 1
  RN="$n"
}
# r448: kill «앞» 그 좌석이 띄운 백그라운드 루프 정지(ft-seat-reap) — left≠0 ∨ rc≠0 = CLOSE-FAIL rc 1(세션 보존 · 명부 표기는 남음 · 사람 판단). 세션이 이미 없어도 고아 루프를 본다.
# r1568 ② — 정지·재조사 반복은 ft-seat-reap 안에서 끝났다(마지막 정지 1회 + 재조사 · 총 3회 상한). 여기서 남으면 CLOSE-FAIL 이유 1줄 rc≠0 — 세션 보존.
reap() {
  local o r; o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" 2>&1)"; r=$?; RL="$(printf '%s\n' "$o" | grep -oE 'left=[0-9?]+' | tail -1)"
  printf '%s\n' "$o" >&2
  [ "$r" -eq 0 ] && [ "$RL" = left=0 ] && return 0
  cfail fail-reap "reap ${RL:-left=?} rc=$r" "$o"
}
CFD="$(dirname "$FILE")/state/close-fail"; CF="$CFD/$SEAT.txt"
cfail() {   # r1568 ⑤⑥ — 실패 기록 1개(좌석·담당·이유·남은 것·다음 실행 1줄) + master 쪽지 1통 · «CLOSED»·«GONE» 거짓 글자 0
  local tag="$1" why="$2" m="$(dirname "$FILE")/comm/mbox.sh" h="$MST"   # r5 — master 칸은 입구 확정값(명부 재해석 0)
  mkdir -p "$CFD" && printf 'seat=%s\n담당=%s\n이유=%s\n%s\n다음 실행: %s %s --reason "<이유 1줄>"\n' "$SEAT" "$BY" "$why" "$3" "$HERE/ft-seat-close.sh" "$SEAT" > "$CF"
  [ -z "$h" ] || [ ! -f "$m" ] || bash "$m" send "$h" "$BY" "[$tag] $SEAT — $why · 기록 $CF · 세션 보존" >/dev/null 2>&1
  vlog "$tag"; finish 1 "CLOSE-FAIL $why — $SEAT 세션 보존(명부 표기는 남음 file=$FILE · 기록 $CF)"
}
final() {   # r1568 ④ — 닫힘 확인: 세션 부재 ∧ 최종 재조사 left=0 둘 다일 때만 닫는다 · 원문(⑥)은 stderr 에
  local o r g L; o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" 2>&1)"; r=$?
  printf 'reap-final %s\n' "$(printf '%s\n' "$o" | grep -E '^reap' | tail -3)" >&2
  tmux has-session -t "=$SEAT" 2>/dev/null && g=alive || g=gone
  [ "$r" -eq 0 ] && [ "$g" = gone ] && rm -f "$CF" && return 0
  L="$(printf '%s\n' "$o" | grep -oE 'left=[0-9?]+' | tail -1)"
  cfail fail-final "final ${L:-left=?} rc=$r session=$g" "$o"
}
seat_attached() {   # r1839 A1·A3 — 사람 화면 수 1회: free | attached <N> | unknown <사유> · 대상 `=<세션>:` 고정(콜론 없으면 rc0 빈 줄 = 전부 unknown)
  local o r; o="$(tmux display-message -p -t "=$SEAT:" '#{session_attached}' 2>&1)"; r=$?
  if [ "$r" = 0 ] && [[ "$o" =~ ^[0-9]+$ ]]; then if [ "$o" -ge 1 ]; then echo "attached $o"; else echo free; fi; else echo "unknown rc=$r ${o%%$'\n'*}"; fi
}
planner_owner() {   # r2075 C2 — 부른 좌석(BY = $TMUX_PANE 의 tmux 세션 이름)이 <데이터 루트>/.fable-team/seats-planner.json 의 _master·_desk 값과 글자 그대로 같을 때만 참 · 명부 없음·못 읽음·빈 칸 = 거짓
  local d; case "$BY" in ""|unknown) return 1;; esac
  d="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" && [ -n "$d" ] || return 1
  python3 - "$d/.fable-team/seats-planner.json" "$BY" 2>/dev/null <<'PY5'
import json, sys
try: d = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError): sys.exit(1)
sys.exit(0 if isinstance(d, dict) and any(isinstance(d.get(k), str) and d[k] != "" and d[k] == sys.argv[2] for k in ("_master", "_desk")) else 1)
PY5
}
manual_close() {   # r2075 C3 — «표준승인 밖» 한 자리: 주인 아님 = 기존 held 그대로(모드·대리 0) · 주인 ∧ off = held + 질문 글 1줄 · 주인 ∧ on = attached 판정 → 대리 1회 → rc 0 이면 아래 기존 닫기 길
  local h="CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=held(표준승인 밖 — 나노는 ft-nano-close · 그 밖은 [HIL])" o r
  planner_owner || finish 3 "$h"
  [ "$BY" != "$SEAT" ] || finish 1 "REJECT $SEAT 은 지금 이 명령을 실행하는 세션 자신 — 다른 좌석에서 닫는다(kill 0 · 명부 표기는 남음 file=$FILE)"
  { . "$HERE/ft-team-lib.sh" && [ "$(ft_autonomy_mode "${FT_AUTONOMY_BIN:-$HERE/ft-autonomy.sh}")" = on ]; } 2>/dev/null || finish 3 "$h" "[오빠 질문 필요] $SEAT 닫기 — 이유 $REASON · 되살리는 길 zombie-clean.sh resume '$SEAT'"   # 도구는 발신 0(Slack 은 desk 손)
  o="$(seat_attached)"; if [[ "$o" == unknown* ]]; then finish 3 "HELD $SEAT 판정 불가 attached(${o#unknown }) — kill 0 · reap 0 · 명부 표기는 남음 file=$FILE"; fi   # 기존 attached 판정을 대리보다 먼저(판정 불가 = 기존 HELD 줄 · 대리 호출 0)
  o="$(bash "${FT_PROXY_DECIDE_BIN:-$HERE/ft-proxy-decide.sh}" --kind seat-close --seat "$SEAT" --q "$SEAT 닫기(표준승인 밖 · 수동 닫기 지원)" --choice "$SEAT 닫기" --why "$REASON" --undo "zombie-clean.sh resume '$SEAT'" 2>&1)"; r=$?
  [ "$r" = 0 ] || finish 3 "$h" "${o%%$'\n'*}"
  printf '%s\n' "$o"
}
if tmux has-session -t "=$SEAT" 2>/dev/null; then
  [ -n "$VERDICT$DSEQ" ] || lineage_ok || renamed_ok || manual_close   # r2075 — 표준승인 밖 = manual_close 한 곳 · --verdict = 판정 승인 1건 + 재개 기록 확인됨 · r1691 = 이름 접두가 바뀐 승계도 같은 근거면 통과
  ATT="$(seat_attached)"; case "$ATT" in free) ;; attached*) echo "NOTE $SEAT 사람 화면 attached=${ATT#attached } — 오빠 지시로 닫음";; *) finish 3 "HELD $SEAT 판정 불가 attached(${ATT#unknown }) — kill 0 · reap 0 · 명부 표기는 남음 file=$FILE";; esac   # r1839 A4 — 계보 근거 뒤 · reap 앞 · r1976 attached N = NOTE 1줄 뒤 닫기 계속(오빠 지시) · 판정 불가 = HELD 그대로
  reap
  if [ -n "$(tmux show-options -qv -t "=$SEAT:" @zc_v65_active 2>/dev/null)" ]; then
    tmux set-option -t "=$SEAT:" -u @zc_v65_active || { vlog fail-tag; finish 1 "FAIL tag $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; }
  fi
  tmux kill-session -t "=$SEAT" || { vlog fail-kill; finish 1 "FAIL kill $SEAT — kill-session 실패(세션 잔존 · 명부 표기는 남음 file=$FILE)"; }
  KILL=ok
else reap; KILL=none; fi
final
if [ "$DEAD" = 1 ]; then   # r427 — 죽은 좌석: kill 할 것 0 · 명부만 닫는다 · r1568 ④(DA② R1) — 세션 부재만으로 성공하지 않는다(위 reap·final 이 자식 정리와 left=0 을 이미 쟀다)
  vlog dead; [ "$CELLS" = - ] && finish 0 "CLOSED-DEAD $SEAT record=$RK handoff=$CELLS" || finish 0 "CLOSED-DEAD $SEAT record=$RK handoff=$CELLS" "  - 교대 0 · planner 1줄: 비운 칸 $CELLS — 후임 지정은 planner(자동 선정 0)"
fi
[ -z "$DSEQ" ] || { vlog "$KILL"; finish 0 "CLOSED-DONE $SEAT seq=$DSEQ record=$REC kill=$KILL"; }   # r1656 ⓒ
[ -z "$VERDICT" ] || { vlog "$KILL"; finish 0 "CLOSED-ROLE $SEAT verdict=$VERDICT record=$REC cells=$CELLS kill=$KILL reap left=0 rc=0"; }   # r960 ⓣⓤ — 결과 줄 형식 그대로 · NORECORD 줄은 finish 가 붙인다
finish 0 "CLOSED-SESSION $SEAT file=$FILE role_was=$WAS kill=$KILL reap left=0 rc=0${RN:+ lineage=renamed:$RN}"
