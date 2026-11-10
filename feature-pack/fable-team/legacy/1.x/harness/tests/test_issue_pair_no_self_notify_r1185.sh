#!/usr/bin/env bash
# test_issue_pair_no_self_notify_r1185.sh — 매니저 자기 등록 = 알림 0 · 우편함 경보 셈 = recv 규칙(자기 행 제외) 반례 R1~R6 + 변이 2.
# 실 gh·실 mbox·실 우편함 0 — PATH 맨 앞 가짜 gh·tmux · 가짜 mbox(인자 기록) · 임시 명부 · 자기 재호출 0(guard 의 RSG_ACTIVE 만).
# 기준판 대조: FT_T_PAIR · FT_T_QW 로 옛 판 경로를 주면 같은 반례를 옛 판에 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PAIR="${FT_T_PAIR:-$HERE/../bin/ft-issue-create-pair.sh}"
QW="${FT_T_QW:-$HERE/../bin/ft_queue_watch.py}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FT="$T/.fable-team"; mkdir -p "$T/bin" "$FT/comm"; SENDS="$T/sends.log"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "issue create" ] && echo "https://github.com/o/r/issues/91"
exit 0
EOF
# 가짜 mbox: send 인자를 1행씩 기록(to<TAB>from<TAB>body) · 우편함 파일은 건드리지 않는다
cat > "$FT/comm/mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = send ] && printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$FAKE_SENDS"
echo "QUEUED seq=7 stub"
EOF
chmod +x "$T/bin/gh" "$FT/comm/mbox.sh"
MGR="byz-issues-master-claude#38"; OLD="byz-issues-master-claude#37"; PLN="byz-planner-master-claude#9"
printf '#!/bin/bash\nprintf "%%s\\n" "%s" "%s" "%s"\n' "$MGR" "$OLD" "$PLN" > "$T/bin/tmux"; chmod +x "$T/bin/tmux"
echo "{\"_master\":\"$MGR\",\"$MGR\":{\"role\":\"master\"},\"$OLD\":{\"role\":\"arch\"}}" > "$FT/seats-issues.json"
echo "{\"_master\":\"$PLN\",\"$PLN\":{\"role\":\"master\"}}" > "$FT/seats-planner.json"
printf '증상: x\n담당 팀: harness-ops\n' > "$T/body.md"
export PATH="$T/bin:$PATH" FAKE_SENDS="$SENDS" FT_ISSUES_SEATS="$FT/seats-issues.json" FT_MBOX_CMD="$FT/comm/mbox.sh" FT_ISSUE_BOT_TOKEN="stub-bot"

# pair <스크립트> <등록 좌석> → out · rc · n(send 줄 수)
pair() { : > "$SENDS"; out="$(FT_ME="$2" bash "$1" "[harness] x" "$T/body.md" --apply 2>&1)"; rc=$?; n="$(wc -l < "$SENDS" | tr -d ' ')"; }
want_r1() {
  [ $rc -eq 0 ] && [ "$n" = 0 ] && grep -q "^PAIR issue=#91 team=harness-ops manager=$MGR 알림 0(등록 좌석 = 매니저)$" <<<"$out" \
    && ok "R1 매니저 자기 등록 → send 0 · PAIR 알림 0" || bad "R1 rc=$rc send=$n out=[$out]"
}
# mailbox <행…> — 각 행 «seq to from» · 우편함 새로 씀
mailbox() { local r s to from; : > "$FT/comm/mailbox.jsonl"; for r in "$@"; do IFS=' ' read -r s to from <<<"$r"
  printf '{"seq":%s,"to":"%s","from":"%s","body":"[Issue 등록] b"}\n' "$s" "$to" "$from" >> "$FT/comm/mailbox.jsonl"; done; }
# scan <ft_queue_watch> <좌석> → alerts(그 좌석 [우편함 거의 참] send 줄) · src · 감시가 못 돌면(rc≠0·REJECT·Traceback) FAIL 1 + alerts=-1(헛 0 방지)
scan() { local qrc; : > "$SENDS"; rm -f "$FT/state/qw.json"
  src="$(FT_ROOT="$T" PYTHONPATH="$HERE/../bin" FT_NOW=1800000000 FT_QUEUE_WATCH_TIMEOUT=5 timeout 60 python3 "$1" scan --mbox "$FT/comm/mbox.sh" --rosters "$FT" --state "$FT/state/qw.json" 2>&1)"; qrc=$?
  alerts="$(grep -c "\[우편함 거의 참\] $2 미읽음" "$SENDS")"
  [ $qrc -eq 0 ] && ! grep -qE 'REJECT|Traceback' <<<"$src" || { bad "감시 기동 실패 rc=$qrc src=[$src]"; alerts=-1; }; }
rows() { local i s=$1 to=$2 from=$3 k=$4; for i in $(seq 0 $((k-1))); do echo "$((s+i)) $to $from"; done; }

bash -n "$PAIR" && ok "bash -n" || bad "bash -n"
pair "$PAIR" "$MGR"; want_r1
pair "$PAIR" "byz-harness-master-claude#138"
[ $rc -eq 0 ] && [ "$n" = 1 ] && [ "$(cut -f1,2 "$SENDS")" = "$MGR	byz-harness-master-claude#138" ] \
  && grep -q '^\[Issue 등록\] Issue #91 등록 — 제목: \[harness\] x / 경로: 세션 에이전트(ft-origin: seat) / 등록 좌석: byz-harness-master-claude#138 — 접수 검사(라벨 6) 요청\.$' <<<"$(cut -f3 "$SENDS")" \
  && grep -q "^PAIR issue=#91 team=harness-ops manager=$MGR seq=7$" <<<"$out" \
  && ok "R2 다른 좌석 → send 1 · 본문·PAIR 그대로" || bad "R2 rc=$rc send=$n sends=[$(cat "$SENDS")] out=[$out]"

IFS=$'\n'
mailbox $(rows 100 "$MGR" "$MGR" 8); scan "$QW" "$MGR"
[ "$alerts" = 0 ] && ok "R3 자기 행 8 + 남 0 → 경보 0" || bad "R3 경보=$alerts src=[$src]"
mailbox $(rows 100 "$MGR" "$MGR" 3) $(rows 200 "$MGR" x 8); scan "$QW" "$MGR"
[ "$alerts" = 1 ] && grep -q "\[우편함 거의 참\] $MGR 미읽음 8/10" "$SENDS" && ok "R4 자기 3 + 남 8 → 미읽음 8 · 경보 1" || bad "R4 경보=$alerts sends=[$(cat "$SENDS")] src=[$src]"
mailbox $(rows 300 "$OLD" "$MGR" 8); scan "$QW" "$OLD"
[ "$alerts" = 1 ] && grep -q "\[우편함 거의 참\] $OLD 미읽음 8/10" "$SENDS" && ok "R5 후계 [레디] 꼴(to≠from) → 셈 그대로 · 경보 1" || bad "R5 경보=$alerts sends=[$(cat "$SENDS")]"
mailbox $(rows 202471 "$MGR" "$MGR" 7) "203100 $MGR byz-planner-master-claude#9"
before="$(shasum "$FT/comm/mailbox.jsonl")"; scan "$QW" "$MGR"
[ "$alerts" = 0 ] && [ "$(shasum "$FT/comm/mailbox.jsonl")" = "$before" ] && [ "$(wc -l < "$FT/comm/mailbox.jsonl" | tr -d ' ')" = 8 ] \
  && ok "R6 실사건 꼴(자기 7 + 남 1) → 경보 0 · 행 8 그대로(지우지 않음)" || bad "R6 경보=$alerts src=[$src]"
unset IFS

for f in ft-issue-create-pair.sh ft_queue_watch.py; do
  cmp -s "$HERE/../bin/$f" "$HERE/../kit/fable-team/bin/$f" && ok "bin·kit cmp0 $f" || bad "bin·kit 다름 $f"
done

# 변이 1: 자기 등록 조건 줄을 지운 사본 → R1 이 FAIL 로 잡혀야 한다
grep -v '^\[ "\$FROM" = "\$MANAGER" \]' "$PAIR" > "$T/mut.sh"
if cmp -s "$PAIR" "$T/mut.sh"; then bad "변이 1 사본이 원본과 같다"; else
  before=$fail; pair "$T/mut.sh" "$MGR"; want_r1 >/dev/null
  [ $fail -gt $before ] && { fail=$before; ok "변이 1(자기 등록 조건 삭제) → R1 FAIL 잡힘(send=$n)"; } || bad "변이 1 이 R1 을 통과함"
fi
# 변이 2: 셈의 자기 행 제외 줄을 지운 사본 → R3 가 FAIL 로 잡혀야 한다
python3 - "$QW" "$T/mut_qw.py" <<'EOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read().splitlines(keepends=True)
out = [l for i, l in enumerate(src) if not ('r.get("from") == r.get("to")' in l or (i and 'r.get("from") == r.get("to")' in src[i - 1]))]
open(sys.argv[2], "w", encoding="utf-8").writelines(out)
EOF
if cmp -s "$QW" "$T/mut_qw.py"; then bad "변이 2 사본이 원본과 같다"; else
  IFS=$'\n'; mailbox $(rows 100 "$MGR" "$MGR" 8); unset IFS; scan "$T/mut_qw.py" "$MGR"
  [ "$alerts" = 1 ] && ok "변이 2(자기 행 제외 삭제) → R3 FAIL 잡힘(경보=$alerts)" || bad "변이 2 가 R3 를 통과함 src=[$src]"
fi

echo "fail=$fail"; [ $fail -eq 0 ]
