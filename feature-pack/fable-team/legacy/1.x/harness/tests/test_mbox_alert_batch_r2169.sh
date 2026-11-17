#!/usr/bin/env bash
# test_mbox_alert_batch_r2169.sh — r2169: 도구 일반 알림 = 큐 행에 wake_at(15분 뒤) · 긴급 = 첫 통만 즉시, 같은 지문 반복(60분 창) = wake_at.
#  ① 묶음 칸(큐 · 기록 행 · 기준판 Red)  ② 묶음 13꼴 + 표 밖 5통  ③ [크리티컬] 첫 통 · 반복 · PR 번호 · 받는 좌석 · 승계  ④ 60분 창(마지막 통 기준)
#  ⑤ 지문 ⓐ 좌석 이름 통째 · ⓑ 카드 번호 r숫자  ⑥ 적재 실패 → 기록 0  ⑦ 거름 먼저(SKIPPED = wake_judge 호출 0 · batched 0 · 첫 통 기록 불변)
#  ⑧ 판정 불가 = 칸 0  ⑨ 불변(좌석 쪽지 · --urgent · --force · 표 밖 · tmux 좌석 · 호출 환경 값)  ⑩ recv · peek · 접기  ⑪ batched.log
# 격리: 정본 comm 사본 + 가짜 명부(팀장 agent pi · agent claude · planner _master · _desk) + 확장 파일 대역(HOME) + 임시 우편함 · state · tmux 스텁 · 실 우편함 0 · sleep 0.
# env: R2169_SRC = 다른 comm(기준판 Red · 변이) · R2169_BASE = 기준판 comm(없으면 git archive 2a2a13bf22 = r2167 착지판) · R2169_CASES = "1 3" 처럼 일부만.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_MBOX_WAKE_AT; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="${R2169_SRC:-$REPO/harness/comm}"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3]) :: ${OUT:0:200} :: ${ERR:0:300}"; fi; }
want() { case " ${R2169_CASES:-1 2 3 4 5 6 7 8 9 10 11} " in *" $1 "*) return 0;; esac; return 1; }
BASE="${R2169_BASE:-}"
if [ -z "$BASE" ]; then mkdir -p "$T/base"
  if (cd "$REPO" && git archive 2a2a13bf22 -- harness/comm 2>/dev/null | tar -x -C "$T/base" 2>/dev/null) && [ -f "$T/base/harness/comm/mbox.sh" ]; then BASE="$T/base/harness/comm"; fi
fi
[ -n "$BASE" ] || echo "NOTE 기준판 없음(git archive 실패) — ⑨ ⑩ 대조는 FT_ALERT_POLICY=0 길로 한다"
mkdir -p "$T/stub"; printf 'import sys\nsys.exit(0)\n' > "$T/stub/desk_gate.py"
printf '#!/bin/sh\necho "$*" >> "$TMUX_LOG"\ncase "$1" in list-panes) exit 0;; *) exit 1;; esac\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
M1="byz-hrd-master-pi#1"; M2="byz-hrd-master-pi#2"; D="byz-hrd-coord-pi#3"; GC="byz-gfx-master-claude#1"; PM="byz-planner-master-pi#7"; PD="byz-planner-desk-pi#8"
T0=1763340000

roster() {   # roster <1 = #1 은퇴 · #2 현역> — 팀장 agent pi(확장 좌석) · 다른 팀 팀장 agent claude(tmux 좌석) · planner _master · _desk
  python3 - "$E/seats" "$1" "$M1" "$M2" "$D" "$GC" "$PM" "$PD" <<'PY'
import json, os, sys
d, r, m1, m2, dd, gc, pm, pd = sys.argv[1], sys.argv[2] == "1", *sys.argv[3:]
j = {"_master": m2 if r else m1, m1: {"role": "stop-ready", "agent": "pi", "_replaced_by": m2} if r else {"role": "master", "agent": "pi"}, dd: {"role": "coord", "agent": "pi"}}
if r: j[m2] = {"role": "master", "agent": "pi", "_replaces": [m1]}
json.dump(j, open(os.path.join(d, "seats-hrd.json"), "w", encoding="utf-8"))
json.dump({"_master": gc, gc: {"role": "master", "agent": "claude"}}, open(os.path.join(d, "seats-gfx.json"), "w", encoding="utf-8"))
json.dump({"_master": pm, "_desk": pd, pm: {"role": "master", "agent": "pi"}, pd: {"role": "desk", "agent": "pi"}}, open(os.path.join(d, "seats-planner.json"), "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [<comm 폴더>] — 격리 우편함 · state · TMPDIR · HOME(확장 파일 대역)
  local from="${1:-$SRC}"
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; Q="$C/mailbox.jsonl"; L="$C/mailbox.log.jsonl"; ST="$E/.fable-team/state"; AP="$ST/alert-policy"
  export TMUX_LOG="$E/tmux.log"; mkdir -p "$C" "$ST" "$E/seats" "$E/tmp" "$E/home/.pi/agent/extensions"
  : > "$E/home/.pi/agent/extensions/ft-mbox-wake.ts"
  cp "$from"/mbox*.py "$from"/mbox*.sh "$from"/bang_command_check.py "$C/"; cp "$from"/alert-policy.tsv "$C/" 2>/dev/null
  printf '{}\n' > "$E/seats/seats.json"; roster 0; : > "$Q"; : > "$TMUX_LOG"
}
xsh() { local verb="$1"; shift; ( unset FT_ALERT_POLICY; for kv in ${XENV[@]+"${XENV[@]}"}; do export "$kv"; done
  env -u FT_PLANNER_HEAD_MODE -u FT_MBOX_STATE_DIR -u FT_BIN PATH="$T/stub:$PATH" TMPDIR="$E/tmp" HOME="$E/home" FT_SEATS_JSON="$E/seats/seats.json" \
  FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
  FT_MBOX_PY="$C/mbox.py" FT_BIN="$BIN" FT_DESK_GATE="$T/stub/desk_gate.py" FT_MBOX_NOW="${NOW:-$T0}" bash "$C/mbox.sh" "$verb" "$@" ); }
sh_() { OUT="$(cd "$E" && xsh send "$@" 2>"$E/err")"; RC=$?; ERR="$(cat "$E/err")"; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
nwarn() { printf '%s\n' "$ERR" | grep -c '^WARN alert-policy'; }
# rowf <파일> [<seq>] — 그 seq(없으면 마지막) 행의 wake_at · 칸 없음 = «-»
rowf() { python3 - "$1" "${2:-}" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
if sys.argv[2]: rows = [r for r in rows if str(r.get("seq")) == sys.argv[2]]
print(rows[-1].get("wake_at", "-") if rows else "none")
PY
}
seq_out() { printf '%s\n' "$OUT" | sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
# w <기대 wake_at | -> <이름> <sh_ 인자…> — 큐를 비우고(같은 본문 접기 0) 보냄 · QUEUED · rc 0 · 그 seq 큐 행의 wake_at
w() { local x="$1" n="$2"; shift 2; [ "${KEEPQ:-0}" = 1 ] || : > "$Q"; sh_ "$@"
  case "$OUT" in *QUEUED*) ;; *) bad "$n → QUEUED 아님 rc=$RC :: ${OUT:0:200} :: ${ERR:0:300}"; return;; esac
  chk "$n → wake_at=$x" "$RC $(rowf "$Q" "$(seq_out)")" "0 $x"; }
norm() { printf '%s\n' "$1" | sed -E 's/seq=[0-9]+/seq=N/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}/TS/g; s#/[^ ]*/e\.[A-Za-z0-9]{6}/#E/#g'; }
qnorm() { python3 -c 'import json,sys
for l in open(sys.argv[1], encoding="utf-8"):
    if l.strip(): r = json.loads(l); r.pop("seq", None); r.pop("ts", None); print(json.dumps(r, ensure_ascii=False, sort_keys=True))' "$1"; }
# same <이름> <sh_ 인자…> — 기준판(BASE · 없으면 FT_ALERT_POLICY=0)과 새 판에서 같은 send → 큐 행(seq · 시각 제외) · stdout · rc 가 같음
same() { local n="$1" o1 r1 q1; shift
  if [ -n "$BASE" ]; then new_env "$BASE"; else new_env; fi; roster "${ROSTER:-0}"
  if [ -n "$BASE" ]; then sh_ "$@"; else XENV=(FT_ALERT_POLICY=0); sh_ "$@"; XENV=(); fi; o1="$(norm "$OUT")"; r1="$RC"; q1="$(qnorm "$Q")"
  new_env; roster "${ROSTER:-0}"; sh_ "$@"
  chk "$n = 기준판(큐 행 · stdout · rc)" "$RC|$(norm "$OUT")|$(qnorm "$Q")" "$r1|$o1|$q1"; }
XENV=()
STALL="[멈춤] 팀장 심박 없음 byz-hrd-master-pi#1 · 마지막 박동 11:02 · 23분째 — 하네스 확인 필요"
ML() { printf '[크리티컬] ft-merge-land 착지 실패 PR #%s — 무엇: push 거부(non-fast-forward) · 전문=/tmp/ft/push-%s-20261116T%s-83298.log' "$1" "$1" "$2"; }
IDLE5() {   # IDLE5 <시각> <분째> <5번째 줄 좌석> <2번째 줄 좌석> — 전문 500자 이상 · 줄마다 좌석 1개
  printf '[긴급] 배정 막힘 5줄 · %s · 조건 23\n' "$1"
  printf '① byz-aifp-master-pi#41 · 대기 카드 r2033-usage-monitor-coord-weekly 배정 0 · 다음 수 없음 · %s분째\n' "$2"
  printf '② %s · 대기 카드 r2101-session-close-ledger 배정 0 · 다음 수 판독 필요 · %s분째\n' "$4" "$2"
  printf '③ byz-qa-master-pi#12 · 대기 카드 r2140-qa-smoke-matrix 배정 0 · 다음 수 없음 · %s분째\n' "$2"
  printf '④ byz-graphics-master-claude#3 · 대기 카드 r2150-graphics-asset-sync 배정 0 · 다음 수 없음 · 마지막 박동 11:02 · 팀장 심박 정상 · 배정 판정 대기열 3번째 · %s분째\n' "$2"
  printf '⑤ %s · 대기 카드 r2160-harness-goal-table-refresh 배정 0 · 다음 수 없음 · %s분째\n' "$3" "$2"
  printf '할 일: 막힌 좌석 팀장에 배정 1줄 · 배정 불가면 planner 에 사유 1줄'; }
KP() { printf '[긴급] UNKNOWN harness %s-session-close-ledger byz-harness-nano-%s-session-close-ledger#0 mail-pending · 미읽음 판독 --rows · 다음 수 판독 확인' "$1" "$1"; }

if want 1; then new_env
  NOW=$T0 w $((T0+900)) "① ft-stall-scan [멈춤] → 확장 좌석" "$M1" ft-stall-scan "$STALL"
  chk "① 기록 행(mailbox.log.jsonl)에도 같은 칸" "$(rowf "$L" "$(seq_out)")" "$((T0+900))"
  chk "① QUEUED 줄 꼴 · gate=quiet · alert-policy stderr 0" "$(norm "$OUT" | grep -c '^QUEUED seq=N .*gate=quiet') $(nwarn)" "1 0"
  q="$OUT"; qe="$ERR"; new_env "${BASE:-$SRC}"; NOW=$T0 sh_ "$M1" ft-stall-scan "$STALL"
  [ -z "$BASE" ] || chk "① stdout · stderr · rc = 기준판" "$RC|$(norm "$OUT")|$(norm "$ERR")" "0|$(norm "$q")|$(norm "$qe")"
  [ -z "$BASE" ] || chk "① 기준판 Red = 칸 없음(기준판 큐 행)" "$(rowf "$Q")" -
fi
if want 2; then new_env
  i=0
  while IFS='|' read -r f b; do i=$((i+1)); NOW=$T0 w $((T0+900)) "② 묶음 $i $f ${b%%]*}]" "$M1" "$f" "$b"; done <<'ROWS'
ft-stall-scan|[멈춤] 팀장 심박 없음 x
ft-goal-table|[골 번호 바뀜] 5 → 6 · 하네스 운영 정리
ft2-keeper|[다음 없음] harness r2101 · 다음 수 0
ft2-keeper|[다음 막힘] harness r2101 · 선행 r2100 미착지
ft-nano-record|[정리 차례 · 주인 없음] byz-harness-nano-r2101#0
ft-nano-record|[정리 차례 · 깨움 실패] byz-harness-nano-r2101#0
ft-nano-record|[정리 차례 · 대리] byz-harness-nano-r2101#0
ft-nano-record|[정리 차례 · 카드 없음] byz-harness-nano-r2101#0
ft-nano-record|[정리 차례 · 닫기 거절] byz-harness-nano-r2101#0
ft-idle-scan|[5분 점검 10:57] 작업 7 · 닫기 대상 0
ft-tick|[계정 안내] 풀 claude: 가용 8/10
ft-desk-tick|[틱 10:57] 5분 정기 프로그레스
ft-desk-tick|[aifp 15분 점검 10:57] aifp master Working
ROWS
  while IFS='|' read -r f b; do NOW=$T0 w - "② 표 밖 $f ${b%%]*}]" "$M1" "$f" "$b"; done <<'ROWS'
ft-nano-record|[정리 차례] byz-harness-nano-r2101#0 착지 끝 — 닫기
ft-hil-h12|[완료 h12] rc=0 · 결과 전문 /tmp/h12.out
ft-hil-h12|[HIL] h12 승인 필요
ft2-slack-listen|[Slack] 오빠: 상태 알려줘
ft-idle-scan|[유휴 점검 11:55] 판정 필요 — x
ROWS
fi
if want 3; then new_env
  NOW=$T0 w - "③ [크리티컬] PR #8751 첫 통" "$M1" ft-merge-land "$(ML 8751 165743)"
  NOW=$((T0+300)) w $((T0+300+900)) "③ 5분 뒤 같은 본문(로그 날짜 · 시각 숫자만 다름)" "$M1" ft-merge-land "$(ML 8751 170243)"
  NOW=$((T0+300)) w - "③ 같은 때 PR #8783" "$M1" ft-merge-land "$(ML 8783 170243)"
  NOW=$((T0+300)) w - "③ 받는 좌석이 다른 같은 본문(planner _master)" "$PM" ft-merge-land "$(ML 8751 170243)"
  roster 1
  NOW=$((T0+360)) w - "③ 승계 뒤(현역 #1 → #2 · 주소 옛 #1) 같은 본문" "$M1" ft-merge-land "$(ML 8751 170343)"
  NOW=$((T0+420)) w $((T0+420+900)) "③ 승계 뒤 현역 #2 주소로 같은 본문 = 현역 이름 열쇠의 반복" "$M2" ft-merge-land "$(ML 8751 170443)"
fi
if want 4; then new_env
  NOW=$T0 w - "④ 첫 통" "$M1" ft-merge-land "$(ML 8751 165743)"
  t=$((T0+3599)); NOW=$t w $((t+900)) "④ 59분 59초 뒤" "$M1" ft-merge-land "$(ML 8751 175742)"
  t=$((t+3540)); NOW=$t w $((t+900)) "④ 그 통 뒤 59분(첫 통에서 약 119분)" "$M1" ft-merge-land "$(ML 8751 185642)"
  t=$((t+3600)); NOW=$t w - "④ 마지막 통에서 60분 0초" "$M1" ft-merge-land "$(ML 8751 195642)"
fi
if want 5; then new_env
  A5="byz-aifp-arch-pi#55"; B5="byz-qa-arch-pi#66"
  b="$(IDLE5 18:51 12 "$A5" 'byz-x-master-pi#107')"; chk "⑤ 배정 막힘 전문 500자 이상" "$(python3 -c 'import sys;print(len(sys.argv[1])>=500)' "$b")" True
  NOW=$T0 w - "⑤ [긴급] 배정 막힘 첫 통" "$M1" ft-idle-scan "$b"
  NOW=$((T0+300)) w $((T0+1200)) "⑤ 머리 시각 · N분째만 다름" "$M1" ft-idle-scan "$(IDLE5 18:56 17 "$A5" 'byz-x-master-pi#107')"
  NOW=$((T0+300)) w - "⑤ 5번째 줄 좌석이 다른 좌석" "$M1" ft-idle-scan "$(IDLE5 18:56 17 "$B5" 'byz-x-master-pi#107')"
  NOW=$((T0+300)) w - "⑤ 2번째 줄 좌석 번호만(#107 → #108)" "$M1" ft-idle-scan "$(IDLE5 18:56 17 "$A5" 'byz-x-master-pi#108')"
  NOW=$T0 w - "⑤ keeper r2101 좌석 통 첫 통" "$M1" ft2-keeper "$(KP r2101)"
  NOW=$((T0+300)) w - "⑤ 5분 뒤 r2102 좌석 통(다른 좌석)" "$M1" ft2-keeper "$(KP r2102)"
  NOW=$((T0+600)) w $((T0+1500)) "⑤ 그 5분 뒤 r2101 통 다시" "$M1" ft2-keeper "$(KP r2101)"
  NOW=$((T0+600)) w - "⑤ 좌석 낱말 없는 r2101 통" "$M1" ft2-keeper "[긴급] UNKNOWN harness r2101-session-close-ledger mail-pending"
  NOW=$((T0+600)) w - "⑤ 좌석 낱말 없는 r2102 통" "$M1" ft2-keeper "[긴급] UNKNOWN harness r2102-session-close-ledger mail-pending"
  NOW=$T0 w - "⑤ master-0 좌석 통 첫 통" "$M1" ft2-keeper "[긴급] byz-qa-master-0-pi#1 판정 필요"
  NOW=$((T0+300)) w - "⑤ 5분 뒤 master-1 좌석 통(r숫자 밖 숫자만 다름)" "$M1" ft2-keeper "[긴급] byz-qa-master-1-pi#1 판정 필요"
fi
wrap_py() {   # 사본 mbox.py 감싸기 — 표지 FAIL_SEND = send 만 rc 1 · EMPTY_HOLDER = holder 가 빈 글 rc 0
  mv "$C/mbox.py" "$C/mbox_real_r2169.py"
  printf 'import os, runpy, sys\nh = os.path.dirname(os.path.abspath(__file__))\nv = sys.argv[1:2]\nif v == ["send"] and os.path.exists(os.path.join(h, "FAIL_SEND")): sys.exit(1)\nif v == ["holder"] and os.path.exists(os.path.join(h, "EMPTY_HOLDER")): print(""); sys.exit(0)\nsys.argv[0] = os.path.join(h, "mbox_real_r2169.py")\nrunpy.run_path(sys.argv[0], run_name="__main__")\n' > "$C/mbox.py"
}
if want 6; then new_env; wrap_py; : > "$C/FAIL_SEND"
  NOW=$T0 sh_ "$M1" ft-merge-land "$(ML 8751 165743)"
  chk "⑥ 적재만 실패 → rc≠0 · 첫 통 기록 0" "$([ "$RC" != 0 ] && echo nz) $([ -f "$AP/first.json" ] && echo rec || echo norec)" "nz norec"
  rm -f "$C/FAIL_SEND"
  NOW=$((T0+60)) w - "⑥ 표지를 치운 뒤 같은 통 = 첫 통" "$M1" ft-merge-land "$(ML 8751 165843)"
  NOW=$((T0+120)) w $((T0+120+900)) "⑥ 그 다음 같은 통" "$M1" ft-merge-land "$(ML 8751 165943)"
fi
wrap_wj() {   # 판정 모듈을 불러 wake_judge 를 호출 수를 세는 대역으로 감싼다(WJ_COUNT 1줄 = 1회) · 나머지 원본 그대로
  mv "$C/mbox_alert_policy.py" "$C/mbox_alert_policy_real.py"
  printf 'import importlib.util, os, sys\nh = os.path.dirname(os.path.abspath(__file__))\ns = importlib.util.spec_from_file_location("ap", os.path.join(h, "mbox_alert_policy_real.py")); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)\no = m.wake_judge\ndef c(*a, **k):\n    open(os.path.join(h, "WJ_COUNT"), "a").write("1\\n"); return o(*a, **k)\nm.wake_judge = c\nsys.exit(m.main(sys.argv[1:]))\n' > "$C/mbox_alert_policy.py"
}
if want 7; then new_env; wrap_wj
  TK() { printf '[틱 %s] 5분 정기 프로그레스 — ft-desk-tick.sh 1회' "$1"; }
  NOW=$T0 w $((T0+900)) "⑦ [틱] 첫 통 → QUEUED + wake_at" "$M1" ft-desk-tick "$(TK 10:57)"
  chk "⑦ 첫 통 = wake_judge 호출 1(실 mbox.sh send 길)" "$(lines "$C/WJ_COUNT")" 1
  b0="$(lines "$AP/batched.log")"; f0="$(cksum "$AP/first.json" 2>/dev/null || echo none)"
  NOW=$((T0+300)) sh_ "$M1" ft-desk-tick "$(TK 11:02)"
  chk "⑦ 5분 뒤 [틱] → SKIPPED · wake_judge 호출 0 · batched 줄 0 · 첫 통 기록 불변" \
    "${OUT%%갈래=*}|$(lines "$C/WJ_COUNT")|$(( $(lines "$AP/batched.log") - b0 ))|$(cksum "$AP/first.json" 2>/dev/null || echo none)" "SKIPPED alert-policy |1|0|$f0"
  C5() { printf '[5분 점검 %s] 작업 7 · 10분↑ 유휴 3 · 시간 모름 1\n%s\n유휴: a#1 3분[유지]\n시간 모름: 0\n팀장 통보: 보냄 3통 · 미발송 0\n할 일: 닫기 대상 줄 먼저' "$1" "$2"; }
  NOW=$T0 w $((T0+900)) "⑦ [5분 점검] 첫 통" "$M1" ft-idle-scan "$(C5 10:55 '닫기 대상 0')"
  NOW=$((T0+300)) w $((T0+1200)) "⑦ [5분 점검] 닫기 대상 줄이 바뀐 통 → QUEUED + wake_at" "$M1" ft-idle-scan "$(C5 11:00 '닫기 대상 1 — x-nano#0 22분[착지 끝 — 닫기]')"
fi
if want 8; then
  e8() {   # e8 <이름> <준비 셸 한 줄> [<① 기대> <③ 둘째 기대>] — 기대 기본 = 둘 다 칸 0 · QUEUED · rc 0
    new_env; (cd "$C" && eval "$2"); local x1="${3:--}" x3="${4:--}"
    NOW=$T0 w "$x1" "⑧ $1 · ①" "$M1" ft-stall-scan "$STALL"
    NOW=$T0 w - "⑧ $1 · ③ 첫 통" "$M1" ft-merge-land "$(ML 8751 165743)"
    [ "${PREP3:-}" = "" ] || (cd "$C" && eval "$PREP3")
    NOW=$((T0+300)) w "$x3" "⑧ $1 · ③ 둘째 통" "$M1" ft-merge-land "$(ML 8751 170243)"; }
  e8 "표 파일 없음" 'rm -f alert-policy.tsv'
  e8 "머리 줄만" 'head -1 alert-policy.tsv > t && mv t alert-policy.tsv'
  e8 "탭 모자란 깨움 행 + 정상 깨움 행(정상 행만 묶음)" 'python3 -c "import re;p=\"alert-policy.tsv\";s=open(p,encoding=\"utf-8\").read();open(p,\"w\",encoding=\"utf-8\").write(s.replace(\"ft-stall-scan\t[멈춤]\t\t묶음\t15분\",\"ft-stall-scan\t[멈춤]\t묶음\t15분\"))"' - $((T0+300+900))
  chk "⑧ 깨진 행 WARN 1줄" "$(nwarn)" 1
  e8 "값 칸 x분" 'sed -i.bak -e "s/	15분\$/	x분/" -e "s/	60분 · 15분\$/	x분 · 15분/" alert-policy.tsv'
  PREP3='printf "\377\376garbage" > ../state/alert-policy/first.json' e8 "첫 통 기록 파일 쓰레기 바이트" 'mkdir -p ../state/alert-policy; printf "\377\376garbage" > ../state/alert-policy/first.json'
  e8 "판정 스크립트 rc 1 대역" 'printf "import sys\nsys.exit(1)\n" > mbox_alert_policy.py'
  e8 "현역 이름 풀이 빈 글 대역" 'mv mbox.py mbox_real_r2169.py; printf "import os, runpy, sys\nh = os.path.dirname(os.path.abspath(__file__))\nif sys.argv[1:2] == [\"holder\"]: print(\"\"); sys.exit(0)\nsys.argv[0] = os.path.join(h, \"mbox_real_r2169.py\")\nrunpy.run_path(sys.argv[0], run_name=\"__main__\")\n" > mbox.py'
  chk "⑧ 빈 현역 이름 = 첫 통 기록 0" "$([ -f "$AP/first.json" ] && echo rec || echo norec)" norec
  XENV=(FT_ALERT_POLICY=0); e8 "FT_ALERT_POLICY=0" ':'; XENV=()
fi
if want 9; then
  same "⑨ 좌석 쪽지(발신 #N) ① 본문" "$M1" "byz-hrd-arch-pi#4" "$STALL"
  same "⑨ --urgent ①" "$M1" ft-stall-scan "$STALL" --urgent
  same "⑨ --force ①" "$M1" ft-stall-scan "$STALL" --force
  same "⑨ 표 밖 도구" "$M1" ft-other-tool "$STALL"
  same "⑨ tmux 좌석(agent claude 팀장) ①" "$GC" ft-stall-scan "$STALL"
  new_env; NOW=$T0 w - "⑨ tmux 좌석 ① → 칸 0" "$GC" ft-stall-scan "$STALL"
  chk "⑨ tmux 좌석 batched 줄 0" "$(lines "$AP/batched.log")" 0
  new_env; XENV=(FT_MBOX_WAKE_AT=1763349999); NOW=$T0 w - "⑨ 호출 환경에 넘김 값을 둔 좌석 쪽지 → 칸 0" "$M1" "byz-hrd-arch-pi#4" "$STALL"
  NOW=$T0 w $((T0+900)) "⑨ 호출 환경 값은 mbox.sh 판정 값으로 덮임(도구 ①)" "$M1" ft-stall-scan "$STALL"
  XENV=()
fi
if want 10; then
  q10() { python3 - "$Q" "$M1" "$T0" <<'PY'
import json, sys
q, to, t0 = sys.argv[1], sys.argv[2], int(sys.argv[3])
rows = [{"seq": 1, "ts": "2026-11-17T10:00:00", "to": to, "from": "ft-stall-scan", "body": "[멈춤] a", "wake_at": t0 + 900},
        {"seq": 2, "ts": "2026-11-17T10:00:01", "to": to, "from": "ft-desk-tick", "body": "[틱 10:00] b", "wake_at": t0 + 600},
        {"seq": 3, "ts": "2026-11-17T10:00:02", "to": to, "from": "byz-hrd-arch-pi#4", "body": "c"}]
open(q, "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PY
  }
  rp() { R="$(cd "$E" && xsh recv "$M1" byz-hrd-arch-pi#4 2>&1)"; P="$(cd "$E" && xsh peek "$M1" 2>&1)"; }
  if [ -n "$BASE" ]; then new_env "$BASE"; q10; rp; R0="$R"; P0="$P"; fi
  new_env; q10; rp
  chk "⑩ READ 줄에 wake_at 글자 0" "$(printf '%s\n' "$R" | grep -c wake_at)" 0
  [ -z "$BASE" ] || chk "⑩ recv(발신 1개) 출력 = 기준판" "$(norm "$R")" "$(norm "$R0")"
  [ -z "$BASE" ] || chk "⑩ peek 출력 = 기준판" "$(norm "$P")" "$(norm "$P0")"
  chk "⑩ 남은 행의 wake_at 그대로" "$(rowf "$Q" 1) $(rowf "$Q" 2) $(rowf "$Q" 3)" "$((T0+900)) $((T0+600)) none"
  KEEPQ=1 sh_ "$M1" ft-stall-scan "[멈춤] a"
  chk "⑩ 같은 본문 접기(QUEUED-DUP) 뒤 접힌 행 wake_at 그대로 · batched 줄 0" "$(case "$OUT" in QUEUED-DUP*) echo dup;; esac) $(rowf "$Q" 1) $(lines "$AP/batched.log")" "dup $((T0+900)) 0"
fi
if want 11; then new_env
  NOW=$T0 w $((T0+900)) "⑪ ① 칸 단 통" "$M1" ft-stall-scan "$STALL"
  s1="$(seq_out)"
  chk "⑪ batched.log 1줄 · 칸 7개 · 값" "$(lines "$AP/batched.log")|$(awk -F'\t' '{print NF}' "$AP/batched.log")|$(cut -f2- "$AP/batched.log")" \
    "1|7|$s1	ft-stall-scan	$M1	[멈춤]	묶음	$((T0+900))"
  NOW=$T0 w - "⑪ 칸 0 통(첫 통)" "$M1" ft-merge-land "$(ML 8751 165743)"
  chk "⑪ 칸 0 통 = batched 줄 0" "$(lines "$AP/batched.log")" 1
  NOW=$((T0+60)) w $((T0+960)) "⑪ 첫 통 갈래 반복" "$M1" ft-merge-land "$(ML 8751 165843)"
  chk "⑪ 반복 통 = batched 1줄 더(갈래 첫 통)" "$(lines "$AP/batched.log") $(tail -1 "$AP/batched.log" | cut -f6)" "2 첫 통"
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
[ "$fail" = 0 ]
