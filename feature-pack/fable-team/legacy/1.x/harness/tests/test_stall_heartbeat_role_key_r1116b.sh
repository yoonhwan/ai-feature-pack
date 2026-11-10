#!/usr/bin/env bash
# test_stall_heartbeat_role_key_r1116b.sh — 팀장 심박([정리])은 받는이 «역할» 로 센다(r1116b ② · Issue #4760).
# 실사건: planner#165→#166 승계 뒤 cfo·graphics·ccu·issues 의 [정리] 가 옛 번호 planner#165 앞으로 남아(r1116 = 옛 번호 그대로 적재)
#   ft-stall-scan 이 현역 이름(#166)만 받는이로 세서 «한 번도 안 보냄» [멈춤] 오탐(cfo #192549 · issues #191783·#192367).
# 가짜 나무·가짜 로그만(임시 폴더) — 실 mbox 쓰기 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRK="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
P=byz-planner-master-claude; CFO=byz-cfo-master-claude#120

world() {   # world <받는이 이름> — 명부(planner #165 은퇴 → #166 현역 · cfo#120 현역) + 큐 빈 파일 + 읽은 로그에 [정리] 1줄(5분 전)
  R="$(mktemp -d "$T/w.XXXXXX")"; mkdir -p "$R/.fable-team/comm"; : > "$R/.fable-team/comm/mailbox.jsonl"
  printf '{"_master": "%s#166", "%s#165": {"role": "stop-ready", "_replaced_by": "%s#166"}, "%s#166": {"role": "master"}}\n' "$P" "$P" "$P" "$P" > "$R/.fable-team/seats-planner.json"
  printf '{"_master": "%s", "%s": {"role": "master"}}\n' "$CFO" "$CFO" > "$R/.fable-team/seats-cfo.json"
  python3 - "$R/.fable-team/comm/mailbox.log.jsonl" "$1" "$CFO" <<'PY'
import json, sys, time
p, to, frm = sys.argv[1:4]
ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 300))
open(p, "w", encoding="utf-8").write(json.dumps({"seq": 192354, "ts": ts, "to": to, "from": frm, "body": "[정리] cfo 심박"}, ensure_ascii=False) + "\n")
PY
}
alert() {   # alert <bin 폴더> → «경보 나이 판정불가» 1줄
  (cd "$1" && python3 -c 'import sys,time;from pathlib import Path;import ft_stall_detect as d
a,age,u=d.lead_alert(Path(sys.argv[1]),Path(sys.argv[1])/".fable-team/comm",sys.argv[2],time.time());print(a,"none" if age is None else int(age),u)' "$R" "$CFO")
}

world "$P#165"; got="$(alert "$TRK")"
[ "$got" = "False 5 False" ] && ok "ⓐ 옛 번호 $P#165 앞 [정리] = planner 역할 심박(경보 0 · 5분)" || bad "ⓐ 옛 번호 심박 :: $got"
world "$P#166"; got="$(alert "$TRK")"
[ "$got" = "False 5 False" ] && ok "ⓑ 현역 이름 앞 [정리] 그대로(회귀 0)" || bad "ⓑ 현역 :: $got"
world "byz-planner-arch-claude#26"; got="$(alert "$TRK")"
[ "$got" = "True none False" ] && ok "ⓒ 다른 역할(planner arch) 앞 [정리] 는 심박 아님(멈춤)" || bad "ⓒ 다른 역할 :: $got"

# 변이: role_key 무효(이름 그대로) → ⓐ 가 «한 번도 안 보냄» 경보로 FAIL 이어야 한다(사본만)
M="$T/mut"; mkdir -p "$M"; cp "$TRK"/*.py "$M/"; printf '\ndef role_key(name):\n    return name or ""\n' >> "$M/ft_stall_detect.py"
world "$P#165"; got="$(alert "$M")"
[ "$got" = "True none False" ] && ok "변이(role_key 무효) → ⓐ FAIL 확인(실사건 오탐 재현)" || bad "변이가 ⓐ 에 안 잡힘 :: $got"

cmp -s "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" && ok "ⓓ kit 짝 cmp0" || bad "ⓓ kit 짝 다름"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
