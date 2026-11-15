#!/usr/bin/env bash
# test_mbox_guard_chain_end_lint_r2076.sh — r2076 E7·E8: 개명 사슬 끝 이름이 이름 검사 rc 1 이면 REJECT 대신 그 끝 이름 우편함에 받는다.
#   반례 ⑧ ⑨(카드 그대로) + 변이 M9·M10(임시 comm 사본에서만 · 변이마다 원본으로 같은 사례 1회 = 반대 결과 대조)
#   임시 comm 사본 + 임시 명부(FT_SEATS_JSON · FT_MBOX_DIR · FT_ROOT) + 팩 ft-name-lint.sh 사본 — 실 우편함·실 명부·실 ft2 쓰기 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0; t0="$(date +%s)"
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
I57='byz-issues-master-claude#57'; I60='byz-issues-master-sol#60'; FROM='byz-planner-master-pi#322'
ROSTER='{"_master": "", "byz-issues-master-claude#57": {"role": "stop-ready", "agent": "claude", "_replaced_by": "byz-issues-master-sol#58"}, "byz-issues-master-sol#58": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-claude#57"], "_replaced_by": "byz-issues-master-sol#59"}, "byz-issues-master-sol#59": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-sol#58"], "_replaced_by": "byz-issues-master-sol#60"}, "byz-issues-master-sol#60": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-sol#59"], "_closed": {"by": "x", "at": "2026-11-13T12:47:55"}}}'
OKCHAIN='{"_master": "", "byz-issues-master-claude#57": {"role": "stop-ready", "agent": "claude", "_replaced_by": "byz-issues-master-pi#58"}, "byz-issues-master-pi#58": {"role": "master", "agent": "pi", "_replaces": ["byz-issues-master-claude#57"]}}'
CLOSEDCHAIN="$(printf '%s' "$ROSTER" | sed 's/"byz-issues-master-sol#60": {"role": "stop-ready"/"byz-issues-master-sol#60": {"role": "closed"/')"
M="$T/mroot"; C="$M/.fable-team/comm"; GL="$M/.fable-team/state/mbox-guard.log"
mkdir -p "$T/home" "$T/emptybin" "$T/rc2bin"; printf '#!/bin/sh\nexit 2\n' > "$T/rc2bin/ft-name-lint.sh"
mb() {   # mb <to> <본문> [env…] — 매번 새 임시 comm 사본(SRC = 원본 또는 변이 사본) · 명부 = $ROS 또는 실사건 꼴
  local to="$1" body="$2"; shift 2
  rm -rf "$M"; mkdir -p "$M/.fable-team/bin" "$M/.fable-team/state"; cp -Rp "${SRC:-$REPO/comm}" "$C"; rm -f "$C/LIVE_BIN"
  cp -p "$REPO/bin/ft-name-lint.sh" "$M/.fable-team/bin/"; printf '%s\n' "${ROS:-$ROSTER}" > "$M/.fable-team/seats-issues.json"; : > "$C/mailbox.jsonl"
  ( cd "$M" && unset FT_PLANNER_HEAD_MODE FT_BIN; for kv in "$@"; do export "$kv"; done; env FT_ROOT="$M" FT_SEATS_JSON="$M/.fable-team/seats-issues.json" FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 HOME="$T/home" \
      bash "$C/mbox.sh" send "$to" "$FROM" "$body" ) > "$T/mb.out" 2>&1
  RC=$?; Q="$(python3 -c 'import json,sys; print(",".join(json.loads(l)["to"] for l in open(sys.argv[1]) if l.strip()) or "-")' "$C/mailbox.jsonl")"
  FWD="$(grep -c ' forward ' "$GL" 2>/dev/null)"; FWD="${FWD:-0}"
}
has() { grep -qF -- "$1" "$T/mb.out"; }
cnt() { grep -cF -- "$1" "$T/mb.out"; }
BUILD='[발주] issues 접수 1건'
W7="WARN 은퇴한 좌석 $I57 → 사슬 끝 $I60 이름 검사 FAIL — 끝 이름 우편함에 받음 — 후계 $I60 로 전달"
RJ="REJECT 은퇴한 좌석 $I57 → 현역"

# ⑧ 사슬 끝 이름 받기
mb "$I57" "$BUILD"
ck "⑧ claude#57 [발주] → rc=$RC(0) · 큐 to=$Q · WARN $(cnt "$W7")줄 · guard log forward ${FWD}줄" "$([ "$RC" = 0 ] && [ "$Q" = "$I60" ] && [ "$(cnt "$W7")" = 1 ] && [ "$FWD" = 1 ] && echo 0 || echo 1)"
mkdir -p "$M/design/teams/issues/indices" "$M/.fable-team/state/ft20-switch"
printf '{"team":"issues","h":"1794494025.738289"}\n' > "$M/.fable-team/state/ft20-switch/issues.json"
printf 'import json\nprint(json.dumps({"result": "접수 성공", "remaining": 0}))\n' > "$T/ft2cli0.py"
OUT="$(HOME="$T/home" FT2_CLI="$T/ft2cli0.py" python3 "$REPO/bin/ft-seat-open-work.py" "$I60" --root "$M" --mbox-dir "$C" 2>&1)"; RC=$?
ck "⑧ 그 우편함으로 open-work sol#60(remaining 0) → rc=$RC(1) «쪽지 일 1»" "$([ "$RC" = 1 ] && [ "$OUT" = 'OPEN-WORK 있음 이유=쪽지 일 1' ] && echo 0 || echo 1)"
ROS="$OKCHAIN" mb "$I57" "$BUILD"
ck "⑧ 사슬 끝 pi#58(lint 통과 · 개명) → rc=$RC(3) · 큐 $Q" "$([ "$RC" = 3 ] && [ "$Q" = - ] && has "$RJ byz-issues-master-pi#58 — 후계 이름으로 다시 보내라" && echo 0 || echo 1)"
mb "$I57" "$BUILD" FT_BIN="$T/emptybin"
ck "⑧ lint 도구 없음(FT_BIN 빈 폴더) → rc=$RC(3) · 큐 $Q" "$([ "$RC" = 3 ] && [ "$Q" = - ] && has "$RJ $I60 — 후계 이름으로 다시 보내라" && echo 0 || echo 1)"
mb "$I57" "$BUILD" FT_BIN="$T/rc2bin"
ck "⑧ lint 스텁 rc 2 → rc=$RC(3) · 큐 $Q" "$([ "$RC" = 3 ] && [ "$Q" = - ] && has "$RJ $I60 — 후계 이름으로 다시 보내라" && echo 0 || echo 1)"

# ⑨ 불변(기준판과 같은 출력)
ROS="$CLOSEDCHAIN" mb "$I57" "$BUILD"
ck "⑨ 사슬 끝 sol#60 closed → rc=$RC(3) · 도 닫힘 · 큐 $Q" "$([ "$RC" = 3 ] && [ "$Q" = - ] && has "REJECT 은퇴한 좌석 $I57 → 후계 $I60 도 닫힘(" && echo 0 || echo 1)"
mb "$I60" "$BUILD"
ck "⑨ sol#60 직접 → rc=$RC(0) · 큐 $Q · 정지 레디 WARN" "$([ "$RC" = 0 ] && [ "$Q" = "$I60" ] && has "WARN 정지 레디 좌석 $I60 — 전송" && echo 0 || echo 1)"
mb "$I57" '[긴급] issues 팀장 확인'
ck "⑨ claude#57 [긴급] → rc=$RC(0) · 큐 $Q · WARN 기준판 글자" "$([ "$RC" = 0 ] && [ "$Q" = "$I60" ] && has "WARN 은퇴한 좌석 $I57 → 현역 $I60 — 후계 이름으로 다시 보내라 — 후계 $I60 로 전달" && ! has '이름 검사 FAIL' && echo 0 || echo 1)"
mb 'byz-issues-master-sol#58' "$BUILD"
ck "⑨ sol#58(같은 계보 옛 번호) → rc=$RC(0) · 큐 $Q · 옛 번호 WARN" "$([ "$RC" = 0 ] && [ "$Q" = 'byz-issues-master-sol#58' ] && has "WARN 옛 번호 byz-issues-master-sol#58 → 역할 우편함(현역 $I60) — 그대로 전송" && echo 0 || echo 1)"

# ── 변이(임시 comm 사본에서만) — 변이 사본은 틀리고, 원본은 같은 사례에서 맞다 ──
mut() {  # mut <이름> <원문> <바꿀 글>
  SRC="$T/mut-$1"; rm -rf "$SRC"; cp -Rp "$REPO/comm" "$SRC"
  python3 - "$SRC/mbox_guard.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut M9 'if lrc == 1:' 'if True:'
ROS="$OKCHAIN" mb "$I57" "$BUILD"; m="$RC/$Q"; SRC=""; ROS="$OKCHAIN" mb "$I57" "$BUILD"
ck "M9 lint 판정 지움 · 사슬 끝 pi#58 → 변이 $m(0/큐 1) · 원본 $RC/$Q(3/-)" "$([ "$m" = "0/byz-issues-master-pi#58" ] && [ "$RC/$Q" = "3/-" ] && echo 0 || echo 1)"
mut M10 'if lint else None' 'if lint else 1'
mb "$I57" "$BUILD" FT_BIN="$T/emptybin"; m="$RC/$Q"; SRC=""; mb "$I57" "$BUILD" FT_BIN="$T/emptybin"
ck "M10 lint 도구 없음 = FAIL · → 변이 $m(0/큐 1) · 원본 $RC/$Q(3/-)" "$([ "$m" = "0/$I60" ] && [ "$RC/$Q" = "3/-" ] && echo 0 || echo 1)"
SRC=""

echo "RUN 1회차 $(( $(date +%s) - t0 ))초 · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
