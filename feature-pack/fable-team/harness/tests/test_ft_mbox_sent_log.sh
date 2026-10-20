#!/usr/bin/env bash
# test_ft_mbox_sent_log.sh — r488: 키트 `ft-mbox.sh send/relay` 도 보관 로그 mailbox.log.jsonl 에 1행 (루트 모듈판 mbox_guard._log_sent 와 같은 계약)
#  ⓐ send 뒤 mailbox.jsonl 1행 + mailbox.log.jsonl 같은 seq 1행(키 seq·ts·to·from·body 동일)
#  ⓑ recv 소비 뒤 mailbox.jsonl 0 · log 1 유지  ⓒ relay 도 log 1
#  ⓓ log 가 FT_MBOX_LOG_MAX_BYTES 넘으면 .1 회전 + 새 파일 1행(ft_inbox_core.mail_files 가 읽는 꼴)
#  ⓖ r553: `FT_MBOX_LOG_KEEP=3` 이면 `.1`·`.2`·`.3` 로 밀어 보관(`.4` 없음 · seq 오름차순·빈틈 0) · 기본값도 3벌
#  ⓔ 자가 점검: log 를 읽기 전용으로 막으면 stdout QUEUED 그대로 · rc 0 · stderr `WARN sent-log 0`
#  ⓕ 변이: py 의 _log_sent 호출을 빼면 ⓐ 가 FAIL + WARN sent-log 0
# 임시 FT_ROOT(키트 bin 사본) + FT_MBOX_DIR 임시 comm + 가짜 tmux(doorbell 0) + 가짜 Haiku — 실 우편함·외부 호출 0 · GIT_* 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

mkroot() {  # <이름> → $T/<이름> 에 키트 bin 사본
  local R="$T/$1"; mkdir -p "$R/.fable-team/bin" "$R/.fable-team/comm"
  cp "$KIT"/ft-mbox.sh "$KIT"/ft-mbox.py "$KIT"/ft-lib.sh "$KIT"/ft-inbox.sh "$KIT"/ft-inbox.py "$KIT"/ft_inbox_core.py "$R/.fable-team/bin/"
  echo "$R"
}
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/bin/sh\ncat >/dev/null; exit 1\n' > "$T/haiku-fail.sh"; chmod +x "$T/haiku-fail.sh"
echo '{"a#1": {"tick": "ft-master-tick"}, "r#1": {"tick": "ft-master-tick"}, "z#1": {"tick": "ft-master-tick"}}' > "$T/seats.json"
export PATH="$T/fakebin:$PATH" FT_SEATS_JSON="$T/seats.json" FT_INBOX_HAIKU="$T/haiku-fail.sh" FT_MBOX_RELAY_DIR="$T/relay"
unset FT_ROOT FT_MBOX_LOG_MAX_BYTES

seqof() { sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' <<<"$1" | head -1; }
rows() {  # <파일> <seq> → 그 seq 행 수
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
try:
    print(sum(1 for l in open(sys.argv[1], encoding="utf-8") if l.strip() and json.loads(l)["seq"] == int(sys.argv[2])))
except FileNotFoundError:
    print(0)
PYEOF
}
same_keys() {  # <큐> <로그> <seq> → 키 seq·ts·to·from·body 동일이면 same
  python3 - "$1" "$2" "$3" <<'PYEOF'
import json, sys
pick = lambda p: [json.loads(l) for l in open(p, encoding="utf-8") if l.strip() and json.loads(l)["seq"] == int(sys.argv[3])][0]
a, b = pick(sys.argv[1]), pick(sys.argv[2])
print("same" if all(a[k] == b[k] for k in ("seq", "ts", "to", "from", "body")) else "diff")
PYEOF
}

ROOT="$(mkroot main)"; BIN="$ROOT/.fable-team/bin"; C="$ROOT/.fable-team/comm"
export FT_MBOX_DIR="$C"

# ⓐ send → 큐 1 + 로그 1 · 키 동일
out="$(bash "$BIN/ft-mbox.sh" send a#1 b#1 "x r488 보관 로그" 2>"$T/err")"; rc=$?; S="$(seqof "$out")"
eq "ⓐ send rc 0" "$rc" 0
eq "ⓐ 큐 1행" "$(rows "$C/mailbox.jsonl" "$S")" 1
eq "ⓐ 로그 1행" "$(rows "$C/mailbox.log.jsonl" "$S")" 1
eq "ⓐ 키 동일" "$(same_keys "$C/mailbox.jsonl" "$C/mailbox.log.jsonl" "$S")" same
grep -q 'WARN sent-log' "$T/err" && bad "ⓐ WARN 0 (실제: $(cat "$T/err"))" || ok "ⓐ WARN 0"

# ⓑ recv 소비 뒤 큐 0 · 로그 1
bash "$BIN/ft-mbox.sh" recv a#1 >/dev/null 2>&1
eq "ⓑ recv 뒤 큐 0" "$(rows "$C/mailbox.jsonl" "$S")" 0
eq "ⓑ recv 뒤 로그 1" "$(rows "$C/mailbox.log.jsonl" "$S")" 1

# ⓒ relay 도 로그 1
printf '긴 본문\n' > "$T/long.txt"
out="$(bash "$BIN/ft-mbox.sh" relay r#1 rr#1 "$T/long.txt" "요약 한 줄" 2>"$T/err")"; rc=$?; S="$(seqof "$out")"
eq "ⓒ relay rc 0" "$rc" 0
eq "ⓒ relay 로그 1행" "$(rows "$C/mailbox.log.jsonl" "$S")" 1
grep -q 'WARN sent-log' "$T/err" && bad "ⓒ WARN 0" || ok "ⓒ WARN 0"

# ⓓ 한도 초과 → .1 회전 + 새 파일 1행
before="$(wc -l < "$C/mailbox.log.jsonl" | tr -d ' ')"
out="$(FT_MBOX_LOG_MAX_BYTES=10 bash "$BIN/ft-mbox.sh" send z#1 d#1 "회전 시험" 2>"$T/err")"; S="$(seqof "$out")"
eq "ⓓ .1 에 옛 행 전부" "$(wc -l < "$C/mailbox.log.jsonl.1" | tr -d ' ')" "$before"
eq "ⓓ 새 로그 1행" "$(wc -l < "$C/mailbox.log.jsonl" | tr -d ' ')" 1
eq "ⓓ 새 로그 = 이번 seq" "$(rows "$C/mailbox.log.jsonl" "$S")" 1
mf="$(cd "$BIN" && FT_ROOT="$ROOT" python3 -c 'import ft_inbox_core as c; print(" ".join(sorted(p.rsplit("/",1)[1] for p in c.mail_files())))' 2>/dev/null)"
case "$mf" in *mailbox.log.jsonl.1*) ok "ⓓ mail_files 가 .1 을 읽음" ;; *) bad "ⓓ mail_files 가 .1 을 읽음 (실제 '$mf')" ;; esac

# ⓔ 로그 읽기 전용 → QUEUED 그대로 · rc 0 · WARN sent-log 0
chmod 444 "$C/mailbox.log.jsonl"
out="$(bash "$BIN/ft-mbox.sh" send a#1 e#1 "읽기 전용 시험" 2>"$T/err")"; rc=$?; S="$(seqof "$out")"
chmod 644 "$C/mailbox.log.jsonl"
eq "ⓔ rc 0" "$rc" 0
[ -n "$S" ] && ok "ⓔ stdout QUEUED" || bad "ⓔ stdout QUEUED (실제 '$out')"
eq "ⓔ 큐 1행" "$(rows "$C/mailbox.jsonl" "$S")" 1
grep -q "WARN sent-log 0 seq=$S " "$T/err" && ok "ⓔ stderr WARN sent-log 0" || bad "ⓔ stderr WARN sent-log 0 (실제: $(cat "$T/err"))"

# ⓕ 변이: _log_sent 호출을 빼면 ⓐ 가 FAIL + WARN
M="$(mkroot mut)"; MB="$M/.fable-team/bin"; MC="$M/.fable-team/comm"
grep -q '^        _log_sent(CANON, row)' "$MB/ft-mbox.py" || bad "ⓕ 변이 대상 줄 없음"
sed -i.bak '/^        _log_sent(CANON, row)/d' "$MB/ft-mbox.py"
out="$(FT_MBOX_DIR="$MC" bash "$MB/ft-mbox.sh" send a#1 f#1 "변이" 2>"$T/err")"; S="$(seqof "$out")"
eq "ⓕ 변이 → 로그 0 (ⓐ FAIL)" "$(rows "$MC/mailbox.log.jsonl" "$S")" 0
grep -q "WARN sent-log 0 seq=$S " "$T/err" && ok "ⓕ 변이 → WARN sent-log 0" || bad "ⓕ 변이 → WARN sent-log 0"

# ⓖ r553: 밀어 보관 — `.1`~`.3` 살고 `.4` 없음 · seq 오름차순·빈틈 0
for i in $(seq 1 40); do
  FT_MBOX_LOG_MAX_BYTES=40 FT_MBOX_LOG_KEEP=3 bash "$BIN/ft-mbox.sh" send a#1 b#1 "밀어 보관 시험 $i xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" >/dev/null 2>&1
done
for n in 1 2 3; do [ -f "$C/mailbox.log.jsonl.$n" ] && ok "ⓖ .$n 산다" || bad "ⓖ .$n 산다"; done
[ -f "$C/mailbox.log.jsonl.4" ] && bad "ⓖ .4 없음" || ok "ⓖ .4 없음"
seqs="$(for n in 3 2 1; do python3 -c 'import json,sys;print("\n".join(str(json.loads(l)["seq"]) for l in open(sys.argv[1],encoding="utf-8") if l.strip()))' "$C/mailbox.log.jsonl.$n"; done; python3 -c 'import json,sys;print("\n".join(str(json.loads(l)["seq"]) for l in open(sys.argv[1],encoding="utf-8") if l.strip()))' "$C/mailbox.log.jsonl")"
echo "$seqs" | python3 -c 'import sys;s=[int(x) for x in sys.stdin.read().split()];print("gap0" if s==list(range(s[0],s[0]+len(s))) else "gap")' > "$T/gap"
eq "ⓖ seq 오름차순·빈틈 0" "$(cat "$T/gap")" gap0
echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
