#!/usr/bin/env bash
# test_da_arch_idle_close_r1671.sh — r1671(오빠 결정 3): ft-seat-close-due.sh(DA·arch «닫기 차례» · --close) + ft_stall_scan.auto_close_da_arch 사례 ⓐ~ⓕ.
#   임시 루트(TEAMS.md·명부·카드·우편함) + 좌석마다 임시 git WT + 가짜 tmux·좌석 상태·조용함·ft-seat-close 스텁만 쓴다 — 실 명부·실 tmux kill·네트워크 0 · sleep 0.
#   변이 사본 = R1671_BIN=<사본 bin>(close-due·stall_scan 둘 다 그 폴더 것) · M1 미답 발주 확인 삭제 → ⓐ FAIL · M2 env 확인 삭제 → ⓓ FAIL · M3 _master 제외 삭제 → ⓔ FAIL.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; KIT="$HERE/../kit/fable-team/bin"; BIN="${R1671_BIN:-$HERE/../bin}"; TOOL="$BIN/ft-seat-close-due.sh"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"; fail=0; t0=$SECONDS
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음 «$2» ← ${1:0:600}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨 «$2» ← ${1:0:600}";; *) ok "$3";; esac; }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got=[$1] want=[$2])"; }
if [ -z "${R1671_BIN:-}" ]; then for f in ft-seat-close-due.sh ft_stall_scan.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; done
  [ ! -x "$BIN/ft-seat-close-due.sh" ] && ok "100644" || bad "실행 비트"; /bin/bash -n "$TOOL" && ok "/bin/bash 3.2 -n" || bad "bash -n"; fi
FK="$T/fake"; mkdir -p "$FK" "$T/cwd" "$T/ss" "$T/q"
printf '#!/usr/bin/env bash\ncase "$1" in list-sessions) [ -f "$T/tmuxfail" ] && exit 1; cat "$T/sess";; display-message) s="${4#=}"; cat "$T/cwd/${s%%:}";; *) exit 9;; esac\n' > "$FK/tmux"
printf '#!/usr/bin/env bash\ncat "$T/ss/$2"\n' > "$FK/ss.sh"; printf '#!/usr/bin/env bash\ncat "$T/q/$1" 2>/dev/null || echo OK\n' > "$FK/q.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$T/close-calls"; [ -f "$T/closefail" ] && { echo "REJECT x"; exit 1; }; [ -f "$T/closeslow" ] && exec sleep 8; echo "CLOSED-ROLE $1 verdict=1699 kill=ok"\n' > "$FK/close.sh"
chmod +x "$FK/tmux"; export T PATH="$FK:$PATH" FT_CLOSE_DUE_SEAT_STATUS="$FK/ss.sh" FT_CLOSE_DUE_QUIET="$FK/q.sh" FT_SEAT_CLOSE="$FK/close.sh"
ago() { python3 -c "import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec='seconds'))" "$1"; }
R="$T/root"; C="$R/.fable-team/comm"; mkdir -p "$C" "$R/design/teams/t/indices/진행" "$R/design/teams/u/indices/진행"; : > "$C/mailbox.jsonl"; : > "$C/mailbox.log.jsonl"; : > "$T/sess"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/teams/t/` | byz-t-master-x | 현역 |\n| u | `design/teams/u/` | byz-u-arch-pi | 현역 |\n' > "$R/design/TEAMS.md"
seat() {   # <좌석> <IDLE|WORKING> <유휴 분> [pane] — 살아 있는 세션 + 깨끗한 WT + 상태(pane = 턴 끝 «-» · 창 활동 시각으로)
  local w="$T/wt/${1//[#]/_}"; mkdir -p "$w"; git -C "$w" init -q; git -C "$w" commit -q --allow-empty -m 0
  printf '%s\n' "$1" >> "$T/sess"; printf '%s\t%s\n' "$w" "$(( $(date +%s) - $3 * 60 ))" > "$T/cwd/$1"
  if [ "${4:-}" = pane ]; then printf '%s - - - pane\n' "$2"; else printf '%s %s 1 - jsonl\n' "$2" "$(ago "$3")"; fi > "$T/ss/$1"
}
DA="byz-t-da-codex#1"; AR="byz-t-arch-pi#2"; MS="byz-t-master-x#0"; UL="byz-u-arch-pi#9"; CL="byz-t-da-codex#0"; W1="byz-t-da-codex#3"; Q1="byz-t-arch-pi#4"; D1="byz-t-arch-pi#5"
python3 - "$R" "$DA" "$AR" "$MS" "$UL" "$CL" "$W1" "$Q1" "$D1" <<'PY'
import json, sys
r, da, ar, ms, ul, cl, w1, q1, d1 = sys.argv[1:]
row = lambda role, **x: {"role": role, "agent": "codex", **x}
json.dump({"_master": ms, "_cards": "design/teams/t/indices", "_da": da, "_arch": ar, da: row("da"), ar: row("arch"), ms: row("master"), cl: row("da", _closed={"at": "x"}), w1: row("da"), q1: row("arch"), d1: row("arch")}, open(r + "/.fable-team/seats-t.json", "w"))
json.dump({"_master": ul, "_cards": "design/teams/u/indices", ul: row("arch")}, open(r + "/.fable-team/seats-u.json", "w"))   # 팀장 칸 값인 arch 행(ⓔ M3)
PY
seat "$DA" IDLE 40 pane; for s in "$AR" "$MS" "$UL" "$CL" "$Q1" "$D1"; do seat "$s" IDLE 40; done; seat "$W1" WORKING 40; echo "BUSY 도구 셸 실행" > "$T/q/$Q1"; echo x > "$T/wt/${D1//[#]/_}/dirty.txt"
run() { OUT="$(FT_ROOT="$R" FT_MBOX_DIR="$C" bash "$TOOL" "$@" 2>&1)"; RC=$?; }
msg() { printf '{"seq": %s, "to": "%s", "from": "%s", "body": "%s"}\n' "$2" "$3" "$4" "$5" >> "$C/$1"; }
echo "== ⓐ DA"; run; has "$OUT" "닫기 차례 $DA 갈래=유휴(da) end=" "ⓐ 발주 0·커밋 끝·유휴 40분(codex pane = 창 활동) → 닫기 차례(da)"; eq "$RC" 0 "ⓐ rc 0"
msg mailbox.log.jsonl 10 "$DA" "byz-t-arch-pi#2" "[판정 요청] r1 PR #5"; run; has "$OUT" "제외 $DA 미답 발주 #10" "ⓐ M1 회신 없는 발주 #10 → 닫기 0"
msg mailbox.log.jsonl 11 "$MS" "$DA" "[판정] APPROVE #10"; run; has "$OUT" "닫기 차례 $DA 갈래=유휴(da)" "ⓐ 발주 뒤 회신(본문 #10) → 다시 닫기 차례"
cp "$C/mailbox.log.jsonl" "$T/log0"; case0() { cp "$T/log0" "$C/mailbox.log.jsonl"; }   # 보정 R1 ⑧~⑪ — 사례마다 같은 원장에서 시작
case0; msg mailbox.log.jsonl 12 "$DA" "$AR" "[판정 요청] r2 PR #6"; msg mailbox.log.jsonl 13 "$AR" "$DA" "[판정] APPROVE #10"
run; has "$OUT" "제외 $DA 미답 발주 #12" "⑧ 발주 10·12 + «APPROVE #10» → 12 미답"; run --close "$DA"; has "$OUT" "NOT-DUE $DA 미답 발주 #12" "⑧ NOT-DUE"; [ ! -f "$T/close-calls" ] && ok "⑧ 닫기 호출 0" || bad "⑧ 가짜 닫기"
case0; msg mailbox.log.jsonl 20 "$DA" "$AR" "[판정 요청] r3"; msg mailbox.log.jsonl 21 "$AR" "$DA" "[진행] 검토 시작 #20"; run; has "$OUT" "제외 $DA 미답 발주 #20" "⑨ «[진행] 검토 시작 #20» = 회신 아님"
case0; msg mailbox.log.jsonl 12 "$DA" "$AR" "[판정 요청] r4"; msg mailbox.log.jsonl 13 "$MS" "$DA" "[판정] r4 APPROVE-IMPL 요청12"; run; has "$OUT" "닫기 차례 $DA 갈래=유휴(da)" "⑩ «APPROVE-IMPL 요청12» → 소거(받는 이 무관)"
: > "$C/mailbox.log.jsonl"; msg mailbox.log.jsonl 10 "$DA" "$AR" "[판정 요청] r5"; msg mailbox.log.jsonl 11 "$AR" "$DA" "[판정] APPROVE #104"; run; has "$OUT" "제외 $DA 미답 발주 #10" "⑪ 발주 10 + «APPROVE #104» → 미답(숫자 경계)"
case0
msg mailbox.jsonl 17 "$DA" "$MS" "[판정 요청] r3"; run; has "$OUT" "제외 $DA 받을 일" "ⓐ 우편함 pending 1 → 닫기 0"; : > "$C/mailbox.jsonl"
FT_SEAT_IDLE_CLOSE_MIN=60 run; has "$OUT" "제외 $DA 유휴 40분 < 문턱" "ⓐ 문턱 미달 → 닫기 0"
echo "== ⓑ arch"; run; has "$OUT" "닫기 차례 $AR 갈래=유휴(arch) end=" "ⓑ 받을 일 0·커밋 끝·유휴 → 닫기 차례(arch)"
echo x > "$R/design/teams/t/indices/진행/c.md"; run; has "$OUT" "제외 $AR 받을 일 OPEN-WORK 있음" "ⓑ 팀 진행 카드 = 받을 일 → 닫기 0"; rm "$R/design/teams/t/indices/진행/c.md"
mv "$R/design/teams/t" "$R/design/teams/t.x"; run; has "$OUT" "판정 불가 $AR ft-seat-open-work rc=3" "ⓑ 받을 일 판정 불가 → 판정 불가 1줄"; hasnt "$OUT" "닫기 차례 $AR" "ⓑ 판정 불가 = 닫기 0"; eq "$RC" 3 "ⓑ 판정 불가 rc 3"; mv "$R/design/teams/t.x" "$R/design/teams/t"
echo "== ⓔ 닫기 금지"; run
has "$OUT" "제외 $W1 상태 WORKING" "ⓔ WORKING → 닫기 0"; has "$OUT" "제외 $Q1 도구 셸 실행" "ⓔ 도구 셸 실행 → 닫기 0"; has "$OUT" "제외 $D1 미커밋 1줄" "ⓔ 미커밋 1줄 → 닫기 0"
hasnt "$OUT" "$MS" "ⓔ 팀장(role=master) 후보 0"; hasnt "$OUT" "$UL" "ⓔ M3 팀장 칸 값 좌석(role=arch여도) 후보 0"; hasnt "$OUT" "$CL" "ⓔ 닫힌 행 후보 0"
run --close "$UL"; eq "$RC" 1 "ⓔ --close 팀장 좌석 rc 1"; has "$OUT" "NOT-DUE $UL" "ⓔ --close 팀장 = NOT-DUE"; [ ! -f "$T/close-calls" ] && ok "ⓔ 닫기 호출 0" || bad "ⓔ 닫기 호출 있음"
touch "$T/tmuxfail"; run; has "$OUT" "판정 불가 $DA tmux list-sessions rc=1" "ⓔ 조회 rc≠0 → 판정 불가"; eq "$RC" 3 "ⓔ rc 3"; rm "$T/tmuxfail"
echo "== ⓒ 닫기 집행"; run --close "$W1"; eq "$RC" 1 "ⓒ 닫기 차례 아닌 좌석 --close rc 1"; [ ! -f "$T/close-calls" ] && ok "ⓒ 다시 판정 → 호출 0" || bad "ⓒ 호출 있음"
run --close "$DA"; eq "$OUT" "CLOSED $DA idle=1" "ⓒ 출력 CLOSED <좌석> idle=1"; eq "$RC" 0 "ⓒ rc 0"; CA="$(cat "$T/close-calls")"
has "$CA" "$DA --verdict 1699 --reason r1671 유휴 자동 닫기" "ⓒ ft-seat-close 표준 경로(--verdict) 1회"; has "$CA" "--seats $R/.fable-team/seats-t.json" "ⓒ 명부 경로 고정"; eq "$(wc -l < "$T/close-calls" | tr -d ' ')" 1 "ⓒ 1회"
hasnt "$CA" "branch" "ⓒ 브랜치·kill-server 인자 0"; touch "$T/closefail"; run --close "$DA"; has "$OUT" "CLOSE-FAIL $DA rc=1 — REJECT x" "ⓒ 닫기 실패 = CLOSE-FAIL"; eq "$RC" 1 "ⓒ 실패 rc 1"; rm "$T/closefail"
touch "$T/closeslow"; : > "$T/close-calls"; s12=$SECONDS; run --close "$DA"; has "$OUT" "판정 불가 $DA ft-seat-close rc=-" "⑫ 가짜 ft-seat-close 8초 → 7초 상한 판정 불가"; eq "$RC" 3 "⑫ rc 3"; hasnt "$OUT" "CLOSED" "⑫ CLOSED 0"; eq "$(wc -l < "$T/close-calls" | tr -d ' ')" 1 "⑫ 재시도 0(1회)"; echo "⑫ $((SECONDS-s12))초"; rm "$T/closeslow"
echo "== ⓕ 닫힌 좌석 앞 발주"; msg mailbox.jsonl 20 "$CL" "$MS" "[발주] 새 일"; S0="$(cksum < "$C/mailbox.jsonl")"; run; run --close "$CL"
eq "$(cksum < "$C/mailbox.jsonl")" "$S0" "ⓕ 닫힌 좌석 앞 발주 = 우편함에 남음"; has "$OUT" "NOT-DUE $CL" "ⓕ 닫힌 좌석 --close = NOT-DUE"
FT_SEAT_CLOSE_DUE_BUDGET=6 run; has "$OUT" "판정 불가 $AR 예산 — 다음 판" "ⓒ(R1) 남은 예산 < 7초 → 남은 좌석 판정 불가 «예산 — 다음 판»"; eq "$RC" 3 "ⓒ(R1) rc 3"
eq "$( { grep -E 'run\(' "$TOOL"; sed -n '/def auto_close_da_arch/,/def record_notify/p' "$BIN/ft_stall_scan.py" | grep -E 'run\('; } | grep -cE ', ?70[,)]')" 0 "ⓒ(R1) 바깥 호출 70초 상한 0"
echo "== ⓓ 주기 실행(stall_scan)"
PYO="$(FT_ROOT="$R" R1671_BIN="$BIN" python3 - "$T" 2>&1 <<'PY'
import json, os, sys, time
from pathlib import Path
t = Path(sys.argv[1]); sys.path.insert(0, os.environ["R1671_BIN"]); import ft_stall_scan as m
due = t / "due.sh"; calls = t / "due-calls"
due.write_text('#!/usr/bin/env bash\necho "$*" >> "%s"\n[ "${1:-}" = --close ] && { cat "%s/closeout"; exit $(cat "%s/closerc"); }\nprintf "닫기 차례 A#1 갈래=유휴(da) end=E1 idle=40\\n닫기 차례 B#2 갈래=유휴(arch) end=E2 idle=40\\n닫기 차례 N#0 팀=t 갈래=승인 set=x\\n판정 불가 C#3 git status rc=1\\n"; exit 3\n' % (calls, t, t))
o = object.__new__(m.Scan); o.root = t; o.state_dir = t / "st"; o.state_dir.mkdir(); o.now = time.time()
def go(env, out="CLOSED A#1 idle=1", rc=0):
    (t / "closeout").write_text(out + "\n"); (t / "closerc").write_text(str(rc)); calls.write_text("")
    for k in ("FT_SEAT_AUTO_CLOSE_DA_ARCH",): os.environ.pop(k, None)
    os.environ.update(env, FT_SEAT_CLOSE_DUE=str(due)); r = o.auto_close_da_arch("S"); return r, calls.read_text().splitlines()
def chk(c, n): print(("PASS " if c else "FAIL ") + n)
r, c = go({}); chk(r == [] and c == [], "ⓓ M2 꺼짐(기본 0) = 호출 0 · 출력 0줄")
r, c = go({"FT_SEAT_AUTO_CLOSE_DA_ARCH": "1"}, "REJECT x", 1); chk(c == ["", "--close A#1", "--close B#2"], f"ⓓ 켜짐 = 유휴 줄마다 --close 1회(승인 갈래 0) {c}")
chk(any("판정 불가 seat-auto-close C#3" in x for x in r) and sum("실패" in x for x in r) == 2, f"ⓓ 판정 불가 1줄 + 실패 2줄 {r}")
r, c = go({"FT_SEAT_AUTO_CLOSE_DA_ARCH": "1"}); chk(c == [""], f"ⓓ 같은 end 동안 실패 좌석 재시도 0 {c}")
json.dump({"A#1": "end=OLD"}, open(o.state_dir / "seat-auto-close.json", "w")); r, c = go({"FT_SEAT_AUTO_CLOSE_DA_ARCH": "1"})
chk("--close A#1" in c and "S seat-auto-close CLOSED A#1 idle=1" in r, f"ⓓ 상태 바뀜(end) → 다시 1회 · 성공 줄 {r}")
os.remove(o.state_dir / "seat-auto-close.json"); r, c = go({"FT_SEAT_AUTO_CLOSE_DA_ARCH": "1"}, "판정 불가 A#1 ft-seat-close rc=-", 3)
chk(not json.load(open(o.state_dir / "seat-auto-close.json")).get("A#1") and any("판정 불가 seat-auto-close A#1" in x for x in r), f"⑫ --close 판정 불가 = tried 0(다음 판이 다시 판정) {r}")
real, seen = m.run, []
m.run = lambda cmd, env=None, timeout=15, cwd=None: (seen.append((cmd[2:], timeout)), (99, ""))[1]
r, c = go({"FT_SEAT_AUTO_CLOSE_DA_ARCH": "1"}); m.run = real
chk(r == ["S 판정 불가 seat-auto-close close-due rc=99 — 닫기 0"] and seen == [([], 25)], f"⑬ due 25초 예산 초과 → 판정 불가 1줄 · 닫기 0 {r} {seen}")
PY
)"; echo "$PYO"; [ "$(grep -c '^PASS ' <<<"$PYO")" = 7 ] && ! grep -q '^FAIL ' <<<"$PYO" || bad "ⓓ PASS 7줄 아님"
echo "RUN r1671 단계 합 $((SECONDS-t0))초"
exit $(( fail > 0 ))
