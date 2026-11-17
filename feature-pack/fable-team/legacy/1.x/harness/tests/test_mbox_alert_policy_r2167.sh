#!/usr/bin/env bash
# test_mbox_alert_policy_r2167.sh — r2167: 도구 알림 5갈래는 mbox send 가 큐에 넣기 전에 comm/alert-policy.tsv 를 보고 거른다.
#  ① 유지 통 → SKIPPED  ② 대상 밖(다른 낱말 · 좌석 발신 · --urgent · ft-idle-scan-x)  ③④ [5분 점검] 지문 3종  ⑤ [계정 안내] 전문 지문 · 받는 좌석별
#  ⑥ [틱] 15분 · [aifp] 30분 주기  ⑦ 적재만 실패 → 기록 0 → 재시도 QUEUED  ⑧ 거른 흔적(stdout · skipped.log · 큐 · doorbell · state 불변)
#  ⑨ 판정 불가 = 넣음(표 없음 · 머리 줄만 · 깨진 행 · 기록 깨짐 · 판정 rc 1 · 판정 7초 초과(대역 상한 1초) · FT_ALERT_POLICY=0)
#  ⑩ 불변(좌석 쪽지 · 표 밖 도구 · 머리 없음 = 표 없는 사본과 같음 · 가드 거절 rc 3)  ⑫ 옛 주소 승계 · holder rc 1
# 격리: 정본 comm 사본 + 가짜 명부 + 임시 우편함 · state · TMPDIR · tmux 스텁 · 실 우편함·명부 0 · sleep 0(⑨ 7초 대역만 상한 1초 대기).
# env: R2167_SRC = 다른 comm(기준판 Red) · R2167_CASES = "1 3 6" 처럼 일부만 · R2167_MUT = comm 사본에 돌릴 셸 한 줄(변이).
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="${R2167_SRC:-$REPO/harness/comm}"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3]) :: ${OUT:0:200} :: ${ERR:0:200}"; fi; }
want() { case " ${R2167_CASES:-1 2 3 4 5 6 7 8 9 10 12} " in *" $1 "*) return 0;; esac; return 1; }
mkdir -p "$T/stub"; printf 'import sys\nsys.exit(0)\n' > "$T/stub/desk_gate.py"   # desk 경로 판정기 대역(통과) — ft-desk-tick 이름의 «-desk-» 설치 순서 가드용
printf '#!/bin/sh\necho "$*" >> "$TMUX_LOG"\ncase "$1" in list-panes) exit 0;; *) exit 1;; esac\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
M1="byz-hrd-master-pi#1"; M2="byz-hrd-master-pi#2"; D="byz-hrd-coord-pi#3"; A="byz-hrd-arch-pi#4"; G="byz-hrd-gone-pi#9"

roster() {   # roster <1 = #1 은퇴 · #2 현역>
  python3 - "$E/seats/seats-hrd.json" "$1" "$M1" "$M2" "$D" "$A" "$G" <<'PY'
import json, sys
p, r, m1, m2, d, a, g = sys.argv[1], sys.argv[2] == "1", *sys.argv[3:]
j = {"_master": m2 if r else m1, m1: {"role": "stop-ready", "_replaced_by": m2} if r else {"role": "master"}, d: {"role": "coord"}, a: {"role": "arch"}, g: {"role": "closed"}}
if r: j[m2] = {"role": "master", "_replaces": [m1]}
json.dump(j, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [nopolicy] — 격리 우편함 · state · TMPDIR
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; Q="$C/mailbox.jsonl"; ST="$E/.fable-team/state"; SK="$ST/alert-policy/skipped.log"
  export TMUX_LOG="$E/tmux.log"; mkdir -p "$C" "$ST" "$E/seats" "$E/tmp"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; cp "$SRC"/alert-policy.tsv "$C/" 2>/dev/null
  printf '{}\n' > "$E/seats/seats.json"; roster 0; : > "$Q"; : > "$TMUX_LOG"
  [ "${1:-}" != nopolicy ] || rm -f "$C/alert-policy.tsv" "$C/mbox_alert_policy.py"
  [ -z "${R2167_MUT:-}" ] || [ "${1:-}" = nopolicy ] || (cd "$C" && eval "$R2167_MUT")
}
xsh() { ( unset FT_ALERT_POLICY; for kv in ${XENV[@]+"${XENV[@]}"}; do export "$kv"; done   # XENV = env 앞 하위 셸에서 export(env ↔ bash 사이 펼침 0)
  env -u FT_PLANNER_HEAD_MODE -u FT_MBOX_STATE_DIR -u FT_BIN PATH="$T/stub:$PATH" TMPDIR="$E/tmp" FT_SEATS_JSON="$E/seats/seats.json" \
  FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
  FT_MBOX_PY="$C/mbox.py" FT_BIN="$BIN" FT_DESK_GATE="$T/stub/desk_gate.py" FT_MBOX_NOW="${NOW:-1763340000}" bash "$C/mbox.sh" send "$@" ); }
sh_() { OUT="$(cd "$E" && xsh "$@" 2>"$E/err")"; RC=$?; ERR="$(cat "$E/err")"; }
st() { find "$ST" -type f ! -path '*/alert-policy/*' -exec cksum {} + 2>/dev/null | sort; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
nwarn() { printf '%s\n' "$ERR" | grep -c '^WARN alert-policy'; }
# r <기대 Q|S> <이름> <sh_ 인자…> — Q = QUEUED · S = SKIPPED + 큐 · doorbell · state 바이트 불변 · skipped.log +1 · rc 0
r() {
  local w="$1" n="$2" q0 t0 s0 k0; shift 2; q0="$(cksum < "$Q")"; t0="$(cksum < "$TMUX_LOG")"; s0="$(st)"; k0="$(lines "$SK")"
  sh_ "$@"
  if [ "$w" = Q ]; then case "$OUT" in *QUEUED*) ok "$n → QUEUED";; *) bad "$n → QUEUED 아님 rc=$RC :: ${OUT:0:200} :: ${ERR:0:200}";; esac; return; fi
  local fl; fl="$([ "$(cksum < "$Q")" = "$q0" ] && echo q)$([ "$(cksum < "$TMUX_LOG")" = "$t0" ] && echo t)$([ "$(st)" = "$s0" ] && echo s)"
  case "$OUT" in *QUEUED*) fl="${fl}QUEUED";; esac
  chk "$n → SKIPPED" "$RC|${OUT%%갈래=*}|$fl|$(( $(lines "$SK") - k0 ))" "0|SKIPPED alert-policy |qts|1"
}
XENV=()
IDLE="[유휴 점검 11:55] 유지 — 명부 _arch 1석 — lecture-arch-pi#41 14분
할 일: 유지 규칙 좌석 — 닫기 후보 아님"
chk5() {   # chk5 <시각> <닫기> <시간 모름> <미발송> <유휴 수>
  printf '[5분 점검 %s] 작업 7 · 10분↑ 유휴 %s · 시간 모름 1\n%s\n유휴: a#1 %s분[유지]\n%s\n팀장 통보: 보냄 %s통 · 미발송 %s\n할 일: 닫기 대상 줄 먼저' "$1" "$5" "$2" "$5" "$3" "$5" "$4"; }
ACC() { printf '[계정 안내] 풀 claude: 가용 %s/10 · 풀림 2026-11-17 %s · 불명 0 · 정지: codex 있음 until %s(자동)' "$1" "$2" "$2"; }

if want 1; then new_env
  r S "① ft-idle-scan 유지 통" "$D" ft-idle-scan "$IDLE"   # r S = ⑧ 흔적 검사(stdout 1줄 · rc 0 · skipped.log +1 · QUEUED 0 · 큐 · doorbell · state 바이트 불변)
  chk "⑧ stdout 1줄 · skipped.log 꼴" "$(printf '%s\n' "$OUT" | grep -c .) $(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}	SKIPPED alert-policy 갈래=안 넣음 from=ft-idle-scan to='"$D"' head=\[유휴 점검 N:N\]$' "$SK")" "1 1"
fi
if want 2; then new_env
  r Q "② 판정 필요" "$D" ft-idle-scan "[유휴 점검 11:55] 판정 필요 — x"
  r Q "② 착지 끝" "$D" ft-idle-scan "[유휴 점검 11:56] 착지 끝 — x"
  r Q "② 깨움" "$D" ft-idle-scan "[유휴 점검 11:57] 깨움 — x"
  r Q "② 좌석 발신(#1) 유지 통" "$D" "byz-x-master-pi#1" "$IDLE"
  r Q "② --urgent 유지 통" "$D" ft-idle-scan "$IDLE" --urgent
  r Q "② ft-idle-scan-x 유지 통" "$D" ft-idle-scan-x "$IDLE"
fi
if want 3 || want 4; then new_env
  r Q "③ [5분 점검] 첫 통" "$D" ft-idle-scan "$(chk5 11:55 '닫기 대상 0' '시간 모름: 0' 0 10)"
  r S "③ 시각 · 줄 1 · 유휴 · 보냄 N 만 다름" "$D" ft-idle-scan "$(chk5 12:00 '닫기 대상 0' '시간 모름: 0' 0 11)"
  if want 4; then
    r Q "④ 닫기 대상 1" "$D" ft-idle-scan "$(chk5 12:05 '닫기 대상 1 — x-nano#0 22분[착지 끝 — 닫기]' '시간 모름: 0' 0 9)"
    r S "④ 닫기 대상 분만 다름" "$D" ft-idle-scan "$(chk5 12:10 '닫기 대상 1 — x-nano#0 27분[착지 끝 — 닫기]' '시간 모름: 0' 0 8)"
    r Q "④ 닫기 대상 0" "$D" ft-idle-scan "$(chk5 12:15 '닫기 대상 0' '시간 모름: 0' 0 8)"
    r Q "④ 시간 모름 바뀜" "$D" ft-idle-scan "$(chk5 12:20 '닫기 대상 0' 'y-tester#2[pi 결속 불가]' 0 8 | sed 's/^y-tester/시간 모름: y-tester/')"
    r Q "④ 미발송 0 → 1" "$D" ft-idle-scan "$(chk5 12:25 '닫기 대상 0' 'y-tester#2[pi 결속 불가]' 1 8 | sed 's/^y-tester/시간 모름: y-tester/')"
  fi
fi
if want 5; then new_env
  r Q "⑤ [계정 안내] 첫 통" "$D" ft-tick "$(ACC 8 11:59)"
  r S "⑤ 풀림 시각만 다름" "$D" ft-tick "$(ACC 8 12:29)"
  r Q "⑤ 가용 8 → 7" "$D" ft-tick "$(ACC 7 12:29)"
  r Q "⑤ 같은 본문 · 다른 받는 좌석" "$A" ft-tick "$(ACC 7 12:29)"
  r S "⑤ 그 좌석 다시" "$A" ft-tick "$(ACC 7 12:29)"
fi
if want 6; then new_env
  T0=1763340000; TK() { printf '[틱 %s] 5분 정기 프로그레스 — ft-desk-tick.sh 1회' "$1"; }
  NOW=$T0 r Q "⑥ [틱] 첫 통" "$D" ft-desk-tick "$(TK 10:57)"
  NOW=$((T0+300)) r S "⑥ [틱] 5분 뒤" "$D" ft-desk-tick "$(TK 11:02)"
  NOW=$((T0+600)) r S "⑥ [틱] 10분 뒤" "$D" ft-desk-tick "$(TK 11:07)"
  NOW=$((T0+899)) r S "⑥ [틱] 14분 59초 뒤" "$D" ft-desk-tick "$(TK 11:11)"
  NOW=$((T0+600)) r Q "⑥ [틱] 다른 받는 좌석 따로 셈" "$A" ft-desk-tick "$(TK 11:07)"
  NOW=$((T0+900)) r Q "⑥ [틱] 15분 뒤" "$D" ft-desk-tick "$(TK 11:12)"
  AI() { printf '[aifp 15분 점검 %s] ①aifp master·arch Working/유휴' "$1"; }
  NOW=$T0 r Q "⑥ [aifp] 첫 통" "$D" ft-desk-tick "$(AI 10:57)"
  NOW=$((T0+900)) r S "⑥ [aifp] 15분 뒤" "$D" ft-desk-tick "$(AI 11:12)"
  NOW=$((T0+1800)) r Q "⑥ [aifp] 30분 뒤" "$D" ft-desk-tick "$(AI 11:27)"
fi
wrap_py() {   # 시험 사본 mbox.py 를 감싼다 — 표지 파일 FAIL_SEND = send 만 rc 1 · FAIL_HOLDER = holder 만 rc 1 · 나머지 원본 그대로
  mv "$C/mbox.py" "$C/mbox_real_r2167.py"
  printf 'import os, runpy, sys\nh = os.path.dirname(os.path.abspath(__file__))\nv = sys.argv[1:2]\nif v == ["send"] and os.path.exists(os.path.join(h, "FAIL_SEND")): sys.exit(1)\nif v == ["holder"] and os.path.exists(os.path.join(h, "FAIL_HOLDER")): sys.exit(1)\nsys.argv[0] = os.path.join(h, "mbox_real_r2167.py")\nrunpy.run_path(sys.argv[0], run_name="__main__")\n' > "$C/mbox.py"
}
if want 7; then
  for k in acc tick; do new_env; wrap_py; : > "$C/FAIL_SEND"
    if [ $k = acc ]; then B="$(ACC 8 11:59)"; F=ft-tick; else B="[틱 10:57] 5분 정기"; F=ft-desk-tick; fi
    sh_ "$D" "$F" "$B"; chk "⑦ $k 적재만 실패 → rc≠0 · 기록 0" "$([ "$RC" != 0 ] && echo nz) $([ -f "$ST/alert-policy/last.json" ] && echo rec || echo norec)" "nz norec"
    rm -f "$C/FAIL_SEND"
    r Q "⑦ $k 같은 열쇠 재시도" "$D" "$F" "$B"
    r S "⑦ $k 한 번 더" "$D" "$F" "$B"
  done
fi
if want 9; then
  nine() {   # nine <이름> <WARN 줄 수> — ① 유지 통 · [계정 안내] 두 번 · 모두 QUEUED
    local n="$1" w="$2" tw=0; r Q "⑨ $n 유지 통" "$D" ft-idle-scan "$IDLE"; tw=$((tw + $(nwarn)))
    r Q "⑨ $n [계정 안내] 1" "$D" ft-tick "$(ACC 8 11:59)"; tw=$((tw + $(nwarn)))
    r Q "⑨ $n [계정 안내] 2" "$D" ft-tick "$(ACC 8 11:59)"; tw=$((tw + $(nwarn)))
    chk "⑨ $n stderr WARN 줄 수" "$tw" "$w"
  }
  new_env; rm -f "$C/alert-policy.tsv"; nine "표 없음" 0
  new_env; head -1 "$SRC/alert-policy.tsv" > "$C/alert-policy.tsv"; nine "머리 줄만" 3
  new_env; printf '{"x": garbage\n' > "$T/g"; mkdir -p "$ST/alert-policy"; cp "$T/g" "$ST/alert-policy/last.json"
  sh_ "$D" ft-idle-scan "$IDLE"; chk "⑨ 기록 깨짐 유지 통 → QUEUED · WARN 1" "$(case "$OUT" in *QUEUED*) echo Q;; esac) $(nwarn)" "Q 1"
  new_env; printf 'import sys\nsys.exit(1)\n' > "$C/mbox_alert_policy.py"; nine "판정 rc 1 대역" 3
  new_env; XENV=(FT_ALERT_POLICY=0); nine "FT_ALERT_POLICY=0" 0; XENV=()
  new_env; { head -1 "$SRC/alert-policy.tsv"; printf 'ft-idle-scan\t[유휴 점검 N:N]\n'; tail -n +2 "$SRC/alert-policy.tsv" | grep -v '유지'; } > "$C/alert-policy.tsv"
  r Q "⑨ 깨진 행(유지) → 유지 통 넣음" "$D" ft-idle-scan "$IDLE"; chk "⑨ 깨진 행 WARN 1" "$(nwarn)" 1
  r Q "⑨ 깨진 행 · 정상 행 첫 통" "$D" ft-tick "$(ACC 8 11:59)"
  r S "⑨ 깨진 행 · 정상 행은 거름" "$D" ft-tick "$(ACC 8 11:59)"
  new_env; printf 'import time\ntime.sleep(5)\n' > "$C/mbox_alert_policy.py"; sed -i.bak 's/"\$tm" 7}/"$tm" 1}/' "$C/mbox.sh"
  r Q "⑨ 판정 상한 초과(대역 상한 1초)" "$D" ft-tick "$(ACC 8 11:59)"; chk "⑨ 상한 초과 WARN" "$(nwarn) $(case "$ERR" in *'초과'*) echo y;; esac)" "1 y"
fi
if want 10; then
  ten() {   # 표 있는 사본과 표 없는 사본(기준판 꼴)에 같은 send → 큐 행(seq · ts 제외) · stdout · stderr · rc 같음
    local n="$1" a b; shift; new_env; sh_ "$@"; a="$RC|$OUT|$ERR|$(python3 -c 'import json,sys;[print({k:v for k,v in json.loads(l).items() if k not in("seq","ts")}) for l in open(sys.argv[1])]' "$Q")"
    new_env nopolicy; sh_ "$@"; b="$RC|$OUT|$ERR|$(python3 -c 'import json,sys;[print({k:v for k,v in json.loads(l).items() if k not in("seq","ts")}) for l in open(sys.argv[1])]' "$Q")"
    chk "⑩ $n = 표 없는 사본과 같음" "$(printf '%s' "$a" | sed -E 's/seq=[0-9]+//g; s#/e\.[A-Za-z0-9]+/#/e.X/#g')" "$(printf '%s' "$b" | sed -E 's/seq=[0-9]+//g; s#/e\.[A-Za-z0-9]+/#/e.X/#g')"
  }
  ten "좌석 쪽지" "$D" "byz-hrd-arch-pi#4" "[완료] 시험 끝"
  ten "ft-stall-scan [멈춤]" "$D" ft-stall-scan "[멈춤] x-nano#0 30분"
  ten "ft2-keeper [긴급]" "$D" ft2-keeper "[긴급] keeper 판정 불가"
  ten "ft-nano-record [정리 차례]" "$D" ft-nano-record "[정리 차례] x"
  ten "머리 없는 본문" "$D" ft-idle-scan "유지 — 머리 없음"
  new_env; sh_ "$G" ft-idle-scan "$IDLE"; chk "⑩ 가드 거절 유지 통 → rc 3 · SKIPPED 아님" "$RC $(case "$OUT" in *SKIPPED*) echo s;; esac)" "3 "
fi
if want 12; then
  for k in acc tick; do new_env; if [ $k = acc ]; then B="$(ACC 8 11:59)"; F=ft-tick; else B="[틱 10:57] 5분 정기"; F=ft-desk-tick; fi
    r Q "⑫ $k #1 첫 통" "$M1" "$F" "$B"
    r S "⑫ $k #1 다시" "$M1" "$F" "$B"
    roster 1
    r Q "⑫ $k 승계 뒤 옛 주소 #1 = 현역 #2 첫 통" "$M1" "$F" "$B"
    r S "⑫ $k 옛 주소 #1 다시" "$M1" "$F" "$B"
    r S "⑫ $k 현역 #2 로 = 같은 열쇠" "$M2" "$F" "$B"
  done
  new_env; wrap_py; : > "$C/FAIL_HOLDER"
  r Q "⑫ holder rc 1 대역" "$D" ft-tick "$(ACC 8 11:59)"
  chk "⑫ holder rc 1 → 기록 0 · WARN 1" "$([ -f "$ST/alert-policy/last.json" ] && echo rec || echo norec) $(nwarn)" "norec 1"
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
[ "$fail" = 0 ]
