#!/usr/bin/env bash
# test_team_status_head_r2390.sh — desk 머리 줄 8칸 · 칸 출처 · 실측 실패 = «?» (r2390 반례 ①~⑥ · 변이 M1~M4).
#   ① 칸 8개 꼴·순서·2행 출처 구·3행부터 바이트 같음 ② 기준판 Red(«인터뷰 0») → 새 판 «오빠 답 기다림 2»
#   ③ r2389 «오빠 할 일» 목록 줄 수 = 칸 수(같은 함수 · 다른 수 0) ④ 출처마다 실패 주입 → 그 칸만 «?» · rc0
#   ⑤ 모든 출처 0 → 숫자 칸 모두 «0»(«?» 0) ⑥ planner [정리] 40분 전 → «(40분 전)» · 0통 → «?»
# 전부 합성(임시 루트 · 가짜 장부 · 스텁 3) · 네트워크 0 · sleep 0.
# r2389 미착지 = 대기 세기 모듈 «사본 스텁»(카드 한계 1) — 착지 뒤 실모듈 대조는 arch·DA 몫.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/.."
REPO="$(git -C "$H" rev-parse --show-toplevel 2>/dev/null)"
PREFIX="$(git -C "$H" rev-parse --show-prefix 2>/dev/null)"
P="${FT_HEAD_PY:-$H/bin/ft_team_status_line.py}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NOW=1795000000
P40="$(date -r $((NOW-2400)) +%H:%M)"

# ── 스텁 2 = 자율 · 지시 감시 + r2389 대기 세기 사본(tests/fixtures/wait_r2390 · 카드 한계 1)
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\n[ -n "${FAKE_AUTONOMY_RC:-}" ] && exit "$FAKE_AUTONOMY_RC"\necho "[자율 ON A19 · 08:57~ · 끝 없음 · 대리 3 · 큐 1 · 레벨 풀자동 · 범위 S58]"\n' > "$T/bin/ft-autonomy.sh"
printf '#!/usr/bin/env bash\n[ -n "${FAKE_DIRECTIVE_ODD:-}" ] && { echo "지시 감시 판정 불가 · 사유"; exit 3; }\necho "담당 없는 오빠 지시 3 · 멈춘 오빠 지시 4 · 판본 x · 원장 끝 1"\n' > "$T/bin/ft-directive-watch.sh"
export FT_DESK_HEAD_AUTONOMY="$T/bin/ft-autonomy.sh" FT_DESK_HEAD_DIRECTIVE="$T/bin/ft-directive-watch.sh" FT_BOARD_NEWS_WAIT_BIN="$HERE/fixtures/wait_r2390"
export FT_GOAL_PROGRESS_MD="$T/ledger.md"

ledger10() {  # 10줄: 답 온 8(notified_ts ≥ at) · 답 안 온 2(하나는 15시간 전) — 전부 kind=thread
  python3 - "$1" "$NOW" <<'PY'
import json, sys
p, now = sys.argv[1], int(sys.argv[2])
rows = [{"q_ts": f"p{ i }", "kind": "thread", "state": "closed", "at": now - 600,
             "notified_ts": str(now - 300), "notified_at": now - 300, "closed": "manual:cli"} for i in range(8)]
rows += [{"q_ts": "pr10249-approve", "kind": "thread", "state": "open", "at": now - 54000},
         {"q_ts": "pr10459-approve", "kind": "thread", "state": "open", "at": now - 7200}]
open(p, "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
}
digest() {  # planner _master 발신 «[정리]» 1통(40분 전) — <루트> 기준
  python3 - "$1" "$NOW" 2400 <<'PY'
import json, sys, time
p, now, ago = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now - ago))
rec = {"seq": 1, "ts": ts, "from": "byz-planner-master-pi#398", "to": "byz-harness-master-pi#368",
       "body": "[byz-planner-master-pi#398->byz-harness-master-pi#368] [정리] 대기 카드 28장"}
open(p, "w").write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
}
world() {  # world <이름> — ① 세계: 장부 10(답 안 온 2) · stall 2 · 원장 신선 · 정리 40분 전 · 지시 3/4
  R="$T/$1"; S="$R/.fable-team/state"; mkdir -p "$S/planner-tick" "$R/.fable-team/comm"
  ledger10 "$S/desk-reply-wait.jsonl"
  printf '{"ts": %s, "c": 0, "teams": {"a": {"f": 1}, "b": {"f": 2}, "c": {"f": 0}, "x": {"diag": "_master 빔"}}}\n' \
    "$((NOW-60))" > "$S/stall-scan.last.json"
  printf '스크립트 0 · 인터뷰 0 · 막힌 팀 대기 0\n옛 설명\n## 옛 기록 1\n바이트 그대로\t끝\n' > "$S/planner-tick/TEAM-STATUS.md"
  printf '{"_master":"byz-planner-master-pi#398","_desk":"byz-planner-desk-claude#121"}\n' > "$R/.fable-team/seats-planner.json"
  digest "$R/.fable-team/comm/mailbox.log.jsonl"
  printf '## 골 진행\n\n| 1 | a |\n\n## 끝\n' > "$T/ledger.md"
  python3 -c 'import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$T/ledger.md" "$((NOW-600))"
  F="$S/planner-tick/TEAM-STATUS.md"
}
tool() { python3 "$P" --root "$R" --now "$NOW" "$@" 2>&1; }
line() { sed -n "${2}p" "$1"; }
tail3() { tail -n +3 "$1" | shasum | cut -d' ' -f1; }
L1="자율 ON A19 풀자동 · 오빠 답 기다림 2(가장 오래 15시간) · 스크립트 2 · 막힌 팀 2 · planner [정리] $P40(40분 전) · 원장 낡음 0 · 오빠 지시 멈춤 4 · 담당 없음 3"
[ -f "$P" ] || { echo "FAIL ft_team_status_line.py 없음(기준판 Red)"; echo "FAILED 1"; exit 1; }

# ① 칸 8개 · 순서 · 2행 출처 구 8 · 3행부터 바이트 같음
world w1; before="$(tail3 "$F")"
out="$(tool --hil 2)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$L1" ] && ok "① 출력 = 1행(칸 8)" || bad "① rc=$rc out=$out"
[ "$(line "$F" 1)" = "$L1" ] && ok "① 1행 = 칸 8 · 순서" || bad "① 1행 $(line "$F" 1)"
[ "$(line "$F" 2 | awk -F' · ' '{print NF}')" = 9 ] && ok "① 2행 = 출처 구 8" || bad "① 2행 $(line "$F" 2)"
line "$F" 2 | grep -q "· 원장 낡음 ft_board_news.read_md [0-9][0-9]:[0-9][0-9] · 오빠 지시 멈춤 ft-directive-watch.sh status [0-9][0-9]:[0-9][0-9]" && ok "① 2행 출처 이름·잰 시각" || bad "① 2행 꼴"
[ "$(tail3 "$F")" = "$before" ] && ok "① 3행부터 바이트 같음" || bad "① 3행부터 바뀜"

# ② 기준판 Red — 옛 파일(origin/main)은 같은 장부에서 «인터뷰 0» · 새 판은 «오빠 답 기다림 2»
world w2; OLD="$T/old_ft_team_status_line.py"
git -C "$H" show "origin/main:${PREFIX}bin/ft_team_status_line.py" > "$OLD" 2>/dev/null
if [ -s "$OLD" ]; then
  old="$(python3 "$OLD" --root "$R" --now "$NOW" --hil 2 2>&1)"
  printf '%s' "$old" | grep -q '인터뷰 0' && ok "② 기준판 Red = «인터뷰 0»(같은 장부 10)" || bad "② 기준판 $(printf '%s' "$old")"
else
  echo "SKIP ② 기준판(origin/main 파일 못 읽음)"
fi
[ "$(tool --hil 2)" = "$L1" ] && ok "② 새 판 = «오빠 답 기다림 2»" || bad "② 새 판 $(line "$F" 1)"

# ③ r2389 «오빠 할 일» 목록 줄 수 = 칸 수 · 같은 함수 · 다른 수 0
world w3
n23="$(cd "$HERE/fixtures/wait_r2390" && python3 -c 'import sys; sys.path.insert(0,"."); import ft_board_news_wait as w; print(len(w.todo_lines(sys.argv[1], int(sys.argv[2]))))' "$R" "$NOW")"
n3="$(tool --hil 2 | sed -E 's/^.*오빠 답 기다림 ([0-9?]+)\(.*$/\1/')"
[ "$n3" = "$n23" ] && ok "③ 칸 수 $n3 = 목록 줄 수(r2389 사본)" || bad "③ 칸 $n3 ≠ 목록 $n23"

# ④ 출처 실패 주입 6종 → 그 칸만 «?» · 나머지 그대로 · rc0
fail_one() {  # fail_one <이름> <주입 명령> <기대 1행>
  world "w4$1"
  eval "$2"
  got="$(tool --hil 2)"; rc=$?
  [ "$rc" -eq 0 ] || bad "④ $1 rc=$rc"
  [ "$got" = "$3" ] && ok "④ $1 → 그 칸만 «?»" || bad "④ $1 = $got"
  unset FAKE_AUTONOMY_RC FAKE_DIRECTIVE_ODD; export FT_GOAL_PROGRESS_MD="$T/ledger.md"
}
G() { printf '%s' "$L1" | sed -E "$1"; }
fail_one aut    'export FAKE_AUTONOMY_RC=4' "$(G 's/^자율 ON A19 풀자동/자율 ?/')"
fail_one ledger 'printf "{깨짐\\n" > "$S/desk-reply-wait.jsonl"' "$(G 's/오빠 답 기다림 2\(가장 오래 15시간\)/오빠 답 기다림 ?/')"
fail_one stall  'printf "{\"ts\": %s, \"teams\": {\"a\": {\"f\": 1}}}\\n" "$((NOW-660))" > "$S/stall-scan.last.json"' "$(G 's/막힌 팀 2/막힌 팀 ?/')"
fail_one mail   'rm -f "$R/.fable-team/comm/mailbox.log.jsonl"' "$(G 's/planner \[정리\] [0-9:]+\(40분 전\)/planner [정리] ?/')"
fail_one goal   'export FT_GOAL_PROGRESS_MD="gitref:origin/main:없는/원장.md"' "$(G 's/원장 낡음 0/원장 낡음 ?/')"
fail_one dir    'export FAKE_DIRECTIVE_ODD=1' "$(G 's/오빠 지시 멈춤 4 · 담당 없음 3/오빠 지시 멈춤 ? · 담당 없음 ?/')"

# ⑤ 모든 출처 0 → 숫자 칸 모두 «0» · «?» 0 · 빈칸 0
world w5; : > "$S/desk-reply-wait.jsonl"
printf '{"ts": %s, "teams": {"a": {"f": 0}}}\n' "$((NOW-60))" > "$S/stall-scan.last.json"
printf '#!/usr/bin/env bash\necho "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0 · 판본 x"\n' > "$T/bin/ft-zero.sh"
out5="$(FT_DESK_HEAD_DIRECTIVE="$T/bin/ft-zero.sh" tool --hil 0)"
[ "$out5" = "자율 ON A19 풀자동 · 오빠 답 기다림 0(가장 오래 0시간) · 스크립트 0 · 막힌 팀 0 · planner [정리] $P40(40분 전) · 원장 낡음 0 · 오빠 지시 멈춤 0 · 담당 없음 0" ] \
  && ok "⑤ 모든 출처 0 → 숫자 칸 «0»" || bad "⑤ $out5"
printf '%s' "$out5" | grep -q '?' && bad "⑤ «?» 남음" || ok "⑤ «?» 0"

# ⑥ planner [정리] 40분 전 → «(40분 전)» · 0통 → «?» · 끝 2000줄 밖 → «?»
world w6
[ "$(tool --hil 2)" = "$L1" ] && ok "⑥ 1통 40분 전" || bad "⑥ $(line "$F" 1)"
printf '{"seq": 9, "ts": "%s", "from": "byz-harness-master-pi#368", "to": "x", "body": "[a->b] [완료] x"}\n' \
  "$(date -r $((NOW-600)) +%Y-%m-%dT%H:%M:%S)" > "$R/.fable-team/comm/mailbox.log.jsonl"
tool --hil 2 | grep -q 'planner \[정리\] ?' && ok "⑥ 0통 → «?»" || bad "⑥ 0통 $(line "$F" 1)"
: > "$R/.fable-team/comm/mailbox.log.jsonl"
digest "$T/digest.txt"
cat "$T/digest.txt" > "$R/.fable-team/comm/mailbox.log.jsonl"
for i in $(seq 1 2010); do echo '{"seq": 1, "ts": "2026-11-21T10:00:00", "from": "x#1", "to": "y#2", "body": "[x#1->y#2] z"}'; done >> "$R/.fable-team/comm/mailbox.log.jsonl"
tool --hil 2 | grep -q 'planner \[정리\] ?' && ok "⑥ 끝 2000줄 밖 → «?»" || bad "⑥ 2000줄 밖 $(line "$F" 1)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
