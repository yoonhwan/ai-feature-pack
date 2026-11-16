#!/usr/bin/env bash
# test_session_close_ledger_r2101.sh — r2101 세션 닫힘 원장(ft-session-close-ledger.sh) 반례 ①~⑫ (카드 design/harness/indices/대기/r2101-session-close-ledger.md)
#   닫기 도구 칸 = 가짜 tmux(kill-session 순간의 원장 줄 수를 적는다) + 임시 명부 · hook 칸 = 별도 소켓 실 tmux(`tmux -L r2101-<pid>` · 끝에 그 서버만 내림)
#   실 tmux 서버 · 실 명부 · 실 원장 0 · sleep 0(hook 기다림 = 둘째 hook 줄 «wait-for -S» + `wait-for`)
#   R2101_BIN = 시험할 bin(기본 팩 harness/bin · 변이 사본을 줄 때) · 기준판 = 같은 bin 에서 «note» 호출 줄만 뺀 사본(닫기 출력 · rc 대조)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 추적 사본 원본을 직접 부른다
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_SESSION_CLOSE_LEDGER FT_SEAT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd -- "${R2101_BIN:-$HERE/../bin}" && pwd)"; KIT="$HERE/../kit/fable-team/bin"; LED="$BIN/ft-session-close-ledger.sh"
TOOLS="ft-seat-close.sh ft-nano-close.sh ft-nano-spawn-undo.sh ft-resource-reclaim.sh"
REAL_TMUX="$(command -v tmux)"; SOCK="r2101-$$"
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'env -u TMUX "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null; rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T"' EXIT   # 그 서버와 그 소켓 파일만
fail=0; T0=$SECONDS; STAGES=""
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1:0:600}» ≠ «${2:0:600}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
stage(){ STAGES="$STAGES $1=$((SECONDS-T0))s"; T0=$SECONDS; echo "== $2"; }
nl()   { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
cols() { awk -F'\t' 'NF!=6' "$1" 2>/dev/null | wc -l | tr -d ' '; }
row()  { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
rd()   { bash "$LED" read "$@" 2>&1; }
REAL_HOOKS0="$(env -u TMUX_PANE "$REAL_TMUX" show-hooks -g 2>&1)"
ROOTS=""; for r in "${FT_ROOT:-}" "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; do
  [ -n "$r" ] && [ ! -e "$r/.fable-team/state/session-close" ] && ROOTS="$ROOTS $r"; done
# 기준판 = 호출 줄(«ft-session-close-ledger.sh" note»)만 뺀 bin 사본 · 원장 도구 없음
cp -R "$BIN" "$T/twin"; rm -f "$T/twin/ft-session-close-ledger.sh"
for f in $TOOLS; do grep -v 'ft-session-close-ledger.sh" note' "$BIN/$f" > "$T/x" && cat "$T/x" > "$T/twin/$f"; done

stage prep "①②③ note 줄 꼴 · 탭 · 동시 쓰기(S1 · S2)"
L="$T/l1.tsv"; out="$(FT_SESSION_CLOSE_LEDGER="$L" FT_SEAT='byz-x-master-pi#1' bash "$LED" note 'byz-x-nano-a#0' ft-seat-close.sh "판정 12 집행" 2>&1)"; rc=$?
eq "$rc|$out|$(nl "$L")" "0||1" "① rc 0 · 출력 0 · 원장 1줄"
eq "$(awk -F'\t' '{print NF"|"$2"|"$3"|"$4"|"$5"|"$6}' "$L" 2>/dev/null)" "6|tool|byz-x-nano-a#0|ft-seat-close.sh|byz-x-master-pi#1|판정 12 집행" "① 탭 6칸 · 2칸 tool · 3칸 세션 · 5칸 좌석"
[[ "$(cut -f1 "$L" 2>/dev/null)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && ok "① 1칸 = ISO 초" || bad "① 1칸 시각 꼴: $(cut -f1 "$L" 2>/dev/null)"
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s2 t r >/dev/null 2>&1
eq "$(sed -n 2p "$L" | cut -f5)" "-" "① FT_SEAT 없이 → 5칸 «-»"
L="$T/l2.tsv"; FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s t $'a\tb' >/dev/null 2>&1
eq "$(nl "$L")|$(cols "$L")|$(cut -f6 "$L" 2>/dev/null)" "1|0|a b" "② 값 속 탭 → 1줄 · 6칸 · 탭 = 공백"
: > "$T/afile"; out="$(FT_SESSION_CLOSE_LEDGER="$T/afile/x.tsv" bash "$LED" note s t r 2>&1 >/dev/null)"; rc=$?
eq "$rc|$out" "1|판정 불가 원장 쓰기 실패 $T/afile/x.tsv" "② 원장 쓰기 실패 = stderr «판정 불가» rc 1"
L="$T/l3.tsv"; for i in $(seq 1 20); do FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note "s$i" tool "사유 $i" >/dev/null 2>&1 & done; wait
eq "$(nl "$L")|$(cols "$L")" "20|0" "③ note 20개 동시 → 20줄 · 6칸 아닌 줄 0"

stage note "④⑥ ft-seat-close(S3) — 가짜 tmux · 임시 명부"
mkdir -p "$T/sc/fake" "$T/sc/resume"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/sc/reap.sh"; chmod +x "$T/sc/reap.sh"
cat > "$T/sc/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ] && ! grep -q '^kill-session' "$TMUX_LOG" 2>/dev/null || exit 1;;
  show-options) echo 1;;
  kill-session) n=0; [ -f "${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=$(wc -l < "$FT_SESSION_CLOSE_LEDGER"); echo "$* lines=${n// /}" >> "$TMUX_LOG"; exit 0;;
  list-sessions) for x in ${FAKE_LIVE:-}; do echo "$x"; done;;
  display-message) case "$*" in *session_attached*) echo 0;; *) echo caller#0;; esac;;
esac
exit 0
EOF
chmod +x "$T/sc/fake/tmux"
sc() {  # sc <bin> <원장> [인자…] → $T/sc/out · rc · 가짜 tmux 로그 $T/sc/log
  local b="$1" l="$2"; shift 2; : > "$T/sc/log"; echo '{}' > "$T/sc/resume/W#1.json"
  printf '%s' '{"_master": "M#1", "_hil_route": "P#1", "M#1": {"role": "master", "tick": "t"}, "P#1": {"role": "planner", "tick": "t"}, "W#1": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}' > "$T/sc/seats.json"
  ( cd "$T" && PATH="$T/sc/fake:$PATH" TMUX_LOG="$T/sc/log" FT_SEAT_REAP_BIN="$T/sc/reap.sh" ZC_RESUME_DIR="$T/sc/resume" FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' \
    bash "$b/ft-seat-close.sh" 'W#1' --seats "$T/sc/seats.json" "$@" > "$T/sc/out" 2>&1 ); echo $?; }
L="$T/l4.tsv"; rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason "판정 2050 노출 나노")"; o="$(cat "$T/sc/out")"; k="$(grep '^kill-session' "$T/sc/log")"
r2="$(FAKE_LIVE="W#1 W#2" sc "$T/twin" "$T/l4b.tsv" --reason "판정 2050 노출 나노")"; o2="$(cat "$T/sc/out")"
eq "$rc|$o" "$r2|$o2" "④ 닫기 출력 · rc = 기준판"
has "$o" "CLOSED-SESSION W#1" "④ 닫힘 길(CLOSED-SESSION)"
eq "$(nl "$L")|$(cut -f2-6 "$L" 2>/dev/null)" "1|tool	W#1	ft-seat-close.sh	byz-t-master#1	판정 2050 노출 나노" "④ tool 줄 1 · 도구 칸 ft-seat-close.sh · 세션 칸 = 그 좌석"
eq "$k" "kill-session -t =W#1 lines=1" "④ kill 인자 그대로 · kill 때 원장 줄 수 = 1(note 가 먼저)"
rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$T/afile/x.tsv" --reason "판정 2050 노출 나노")"
eq "$rc|$(cat "$T/sc/out")" "$r2|$o2" "④ 원장 쓰기 실패여도 닫기 출력 · rc = 기준판"
L="$T/l6.tsv"; rc="$(FAKE_LIVE="W#1" sc "$BIN" "$L" --reason r)"; o="$(cat "$T/sc/out")"
r2="$(FAKE_LIVE="W#1" sc "$T/twin" "$T/l6b.tsv" --reason r)"
eq "$rc|$o" "$r2|$(cat "$T/sc/out")" "⑥ HELD 출력 · rc = 기준판"
eq "$rc|$(nl "$L")|$(grep -c '^kill-session' "$T/sc/log")" "3|0|0" "⑥ seat-close HELD rc 3 → tool 줄 0 · kill 0"
rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason r --verdict 99999)"; o="$(cat "$T/sc/out")"
eq "$rc|${o:0:6}|$(nl "$L")|$(grep -c '^kill-session' "$T/sc/log")" "1|REJECT|0|0" "⑥ seat-close REJECT → tool 줄 0 · kill 0"

stage seat-close "⑤ ft-nano-close 2곳(닫기 · 재실행)"
NC="$T/nc"; mkdir -p "$NC/fake" "$NC/comm/bodies"; echo seq > "$NC/comm/bodies/1.txt"; echo res > "$NC/result.md"
for d in bin twin; do mkdir -p "$NC/$d"; src="$BIN"; [ "$d" = bin ] || src="$T/twin"
  for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-wt-sweep.sh ft-session-close-ledger.sh \
           ft-team-lib.sh ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py ft_board_mail.py \
           ft-approval-equiv.sh ft_approval_equiv.py ft-event-check.sh; do [ ! -f "$src/$f" ] || cp "$src/$f" "$NC/$d/"; done
  printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$NC/$d/ft-seat-quiesce.sh"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$NC/$d/ft-seat-reap.sh"; chmod +x "$NC/$d/"*
done
cat > "$NC/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option) echo "$*" >> "$FAKE_LOG";;
  kill-session) n=0; [ -f "${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=$(wc -l < "$FT_SESSION_CLOSE_LEDGER"); echo "$* lines=${n// /}" >> "$FAKE_LOG";;
esac
EOF
printf '#!/usr/bin/env bash\ncat "$FAKE_GH_JSON"\n' > "$NC/fake/gh"; chmod +x "$NC/fake/"*
REPO="$NC/repo"; PACK="$NC/pack"; mkdir -p "$REPO" "$PACK"
for r in "$REPO" "$PACK"; do git -C "$r" init -q -b main && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; done
git -C "$REPO" remote add origin 'https://github.com/lptest/byz.git'; git -C "$REPO" config "url.$REPO.insteadOf" 'https://github.com/lptest/byz.git'
git -C "$PACK" remote add origin 'https://github.com/lptest/pack.git'
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행"
SEAT='byz-planner-nano-bf#0'; BR='nano/bf'; NW="$REPO/.worktrees/v65-bf"; CARD_REL='design/planner/indices/진행/bf.md'
git -C "$REPO" worktree add -q "$NW" -b "$BR"; mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/landed.py"
git -C "$NW" add scripts/landed.py && git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "세트"; SHA0="$(git -C "$NW" rev-parse HEAD)"
git -C "$REPO" worktree remove --force "$NW"; git -C "$REPO" update-ref refs/remotes/origin/main HEAD
ncset() {  # 세션 1(%9) · 워크트리 · 명부 행 · 카드 · gh MERGED
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$NC/tlog"; : > "$NC/ledger.md"; rm -rf "$NC/wtclean" "$NC/events"; git -C "$REPO" worktree remove --force "$NW" 2>/dev/null; git -C "$REPO" worktree prune
  git -C "$REPO" worktree add -q "$NW" "$BR"; find "$NW" -type f -exec touch -t 202001010000 {} +
  printf '%s|%%9\n' "$SEAT" > "$NC/panes"; printf '%s' "$NW" > "$NC/cwd"
  printf '# 인덱스: bf\n## 상태\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 대상: %s/scripts/landed.py\n- 착지: PR #77 squash\n' "$SHA0" "$REPO" > "$REPO/$CARD_REL"
  printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$SHA0" "$SHA0" > "$NC/gh.json"; }
ncrun() {  # ncrun <bin 폴더 이름> <원장> [인자…] → 출력(STEP 줄 · 재측정 칸 · bin 경로 제외) + 마지막 줄 rc=
  local d="$1" l="$2" o r; shift 2
  o="$(cd "$REPO" && env -i HOME="$HOME" PATH="$NC/fake:$PATH" FT_PACK_ROOT="$PACK" FT_SHEET_ROOT="$NC/sheet" FAKE_PANES="$NC/panes" FAKE_CWD="$NC/cwd" FAKE_LOG="$NC/tlog" FAKE_GH_JSON="$NC/gh.json" \
    FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$NC/ledger.md" FT_NANO_FEAT=main \
    FT_EVENT_DIR="$NC/events" FT_INBOX_ROOT="$NC/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$NC/wtclean" FT_WT_AUTOCLEAN=0 bash "$NC/$d/ft-nano-close.sh" "$SEAT" --result "$NC/result.md" --recv 1 "$@" 2>&1)"; r=$?
  o="$(printf '%s\n' "$o" | grep -v '^STEP ' | sed 's/ · 재측정: .*$//')"; printf '%s\nrc=%s\n' "${o//$NC\/$d/<bin>}" "$r"; }
mkdir -p "$NC/sheet/.fable-team/state"
L="$T/l5a.tsv"; ncset; o="$(ncrun bin "$L" --landed-pr 77)"; k="$(grep '^kill-session' "$NC/tlog")"
ncset; o2="$(ncrun twin "$T/l5x.tsv" --landed-pr 77)"
eq "$o" "$o2" "⑤ nano-close 닫기 출력 · rc = 기준판"
has "$o" "KILLED $SEAT" "⑤ nano-close 닫기 길(KILLED)"
eq "$(nl "$L")|$(cut -f2-5 "$L" 2>/dev/null)|$k" "1|tool	$SEAT	ft-nano-close.sh	byz-t-master#1|kill-session -t %9 lines=1" "⑤ nano-close(닫기) tool 줄 1 · kill 때 원장 줄 수 1"
L="$T/l5b.tsv"; : > "$NC/tlog"; o="$(ncrun bin "$L")"; k="$(grep '^kill-session' "$NC/tlog")"
ncset; ncrun twin "$T/l5y.tsv" --landed-pr 77 >/dev/null; : > "$NC/tlog"; o2="$(ncrun twin "$T/l5y.tsv")"
eq "$o" "$o2" "⑤ nano-close 재실행 출력 · rc = 기준판"
has "$o" "재실행 — 명부에 없고 원장 닫힘 행 있음" "⑤ nano-close 재실행 길"
eq "$(nl "$L")|$(cut -f2-6 "$L" 2>/dev/null)|$k" "1|tool	$SEAT	ft-nano-close.sh	byz-t-master#1	재실행|kill-session -t %9 lines=1" "⑤ nano-close(재실행) tool 줄 1 · kill 때 원장 줄 수 1"

stage nano-close "⑤ ft-nano-spawn-undo(롤백) · ft-resource-reclaim"
undo() {  # undo <bin> <원장> → «rc␟출력␟kill 로그␟좌석»
  python3 - "$1" "$2" "$HERE/scripts" "$(mktemp -d "$T/u.XXXX")" <<'PY'
import pathlib, sys
b, led, sp, tmp = sys.argv[1:5]; sys.path.insert(0, sp)
import _nano_rollback_env as E
E.BIN = pathlib.Path(b); env = E.make_env(pathlib.Path(tmp))
kill = 'case "$1" in\n  kill-session) n=0; [ -f "$R2101_L" ] && n=$(wc -l < "$R2101_L"); echo "$* lines=${n// /}" >> "$R81_DIR/kill.log" ;;'
E.exe(env["sh"] / "tmux", E.TMUX.replace('case "$1" in', kill, 1))
r = E.roll(env, FT_SESSION_CLOSE_LEDGER=led, R2101_L=led, FT_SEAT="byz-t-master#1")
k = env["tmp"] / "kill.log"
print("\x1f".join([str(r.returncode), r.stdout.strip(), k.read_text().strip() if k.exists() else "", E.SEAT]))
PY
}
L="$T/l5c.tsv"; IFS=$'\x1f' read -r rc o k us <<<"$(undo "$BIN" "$L")"; IFS=$'\x1f' read -r r2 o2 _ _ <<<"$(undo "$T/twin" "$T/l5z.tsv")"
eq "$rc|$o" "$r2|$o2" "⑤ spawn-undo 출력 · rc = 기준판"
eq "$rc|$o" "0|UNDONE $us" "⑤ spawn-undo 롤백 길(UNDONE)"
eq "$(nl "$L")|$(cut -f2-5 "$L" 2>/dev/null)|$k" "1|tool	$us	ft-nano-spawn-undo.sh	byz-t-master#1|kill-session -t %1 lines=1" "⑤ spawn-undo tool 줄 1 · kill 때 원장 줄 수 1"
. "$HERE/lib/fake_reclaim_world.sh"
mv "$F/tmux" "$F/tmux.world"
cat > "$F/tmux" <<EOF
#!/bin/bash
[ "\$1" != kill-session ] || { n=0; [ -f "\${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=\$(wc -l < "\$FT_SESSION_CLOSE_LEDGER"); echo "lines=\${n// /}" >> "$ST/killlines"; }
exec "$F/tmux.world" "\$@"
EOF
chmod +x "$F/tmux"
rcl() { local b="$1" l="$2" o r; shift 2; o="$(FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' run "$b/ft-resource-reclaim.sh" --caller byz-t-master-claude#1 --need 2 "$@")"; r=$?; printf '%s\nrc=%s\n' "${o//$b/<bin>}" "$r"; }
L="$T/l5d.tsv"; setup; o="$(rcl "$BIN" "$L")"; k="$(cat "$ST/killlines" 2>/dev/null)"; setup; o2="$(rcl "$T/twin" "$T/l5w.tsv")"
eq "$o" "$o2" "⑤ reclaim 출력 · rc = 기준판"
eq "$(nl "$L")|$(cut -f2-6 "$L" 2>/dev/null)|$k" "1|tool	byz-t-role-claude#1	ft-resource-reclaim.sh	byz-t-master#1	판정 1344 · tmux 정리 2026-07-11|lines=1" "⑤ reclaim tool 줄 1 · kill 때 원장 줄 수 1"
L="$T/l6d.tsv"; setup; o="$(rcl "$BIN" "$L" --dry-run)"
has "$o" "WOULD-CLOSE(kill-session)" "⑥ reclaim DRY → WOULD-CLOSE"
eq "$(nl "$L")|$(cat "$ST/killlines" 2>/dev/null | wc -l | tr -d ' ')" "0|0" "⑥ reclaim DRY → tool 줄 0 · kill 0"

stage undo-reclaim "⑦⑧ hook(S4) — 별도 소켓 실 tmux"
mkdir -p "$T/tb"; printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCK" > "$T/tb/tmux"; chmod +x "$T/tb/tmux"
TB() { env -u TMUX -u TMUX_PANE PATH="$T/tb:$PATH" "$@"; }
wait_lines() { local i; for i in $(seq 1 2000); do [ "$(nl "$1")" -ge "$2" ] && return 0; done; return 1; }
mine() { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF "$LED hook #{hook_session_name}"; }
other() { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF '@r2101_other'; }
L="$T/l7.tsv"; TB env FT_SESSION_CLOSE_LEDGER="$L" tmux -f /dev/null new-session -d -s keep cat
TB tmux set-hook -g session-closed 'set-option -g @r2101_other 1'
o1="$(TB bash "$LED" hook-on 2>&1)"; r1=$?; o2="$(TB bash "$LED" hook-on 2>&1)"; r2=$?
eq "$r1|$r2|$(mine)|$(other)" "0|0|1|1" "⑧ hook-on 2회 → 내 줄 1 · 남의 줄 1 그대로"
eq "$(TB bash "$LED" hook-status 2>&1)" "HOOK on" "⑧ hook-status «HOOK on»"
TB tmux set-hook -ag session-closed 'wait-for -S r2101-closed'
TB tmux new-session -d -s 'r2101-a#0' cat; TB tmux kill-session -t '=r2101-a#0'
timeout 10 env -u TMUX "$REAL_TMUX" -L "$SOCK" wait-for r2101-closed; wait_lines "$L" 1
TB tmux new-session -d -s 'r2101-b#1' "\"$REAL_TMUX\" -L $SOCK wait-for r2101-go"; TB tmux wait-for -S r2101-go
timeout 10 env -u TMUX "$REAL_TMUX" -L "$SOCK" wait-for r2101-closed; wait_lines "$L" 2
eq "$(nl "$L")|$(cols "$L")|$(cut -f2-6 "$L" 2>/dev/null | sort | tr '\t\n' '|;')" "2|0|hook|r2101-a#0|-|-|-;hook|r2101-b#1|-|-|-;" "⑦ kill-session 1 · pane 명령 끝 1 → hook 줄 2 · 4~6칸 «-»"
eq "$(TB bash "$LED" hook "x#9" 2>&1; echo "rc=$?")" "rc=0" "⑦ hook = 화면 출력 0 · rc 0"
o="$(TB bash "$LED" hook-off 2>&1)"; eq "$?|$(mine)|$(other)" "0|0|1" "⑧ hook-off → 내 줄 0 · 남의 줄 1"
eq "$(TB bash "$LED" hook-status 2>&1)" "HOOK off" "⑧ hook-status «HOOK off»"
TB tmux kill-server 2>/dev/null; o="$(TB bash "$LED" hook-status 2>&1)"; rc=$?
eq "$([ "$rc" -ne 0 ] && echo nz)|${o:0:5}|$(printf '%s\n' "$o" | wc -l | tr -d ' ')" "nz|판정 불가|1" "⑧ tmux 조회 실패 → «판정 불가» 1줄 rc≠0"

stage hook "⑨⑩⑪ read(S5)"
E="닫힘 0 · 도구 줄 있음 0 · 도구 줄 없음 0 · hook 줄 없음 0 · 깨진 줄 0"
L="$T/l9.tsv"; D=2026-11-16T
{ row ${D}12:00:00 tool s1 ft-seat-close.sh 'M#1' "판정 1"; row ${D}12:00:02 hook s1 - - -; row ${D}12:10:00 hook s2 - - -; row ${D}12:20:00 tool s3 X - r
  row ${D}12:29:59 tool s4 Y - r; row ${D}12:31:00 hook s4 - - -; row ${D}12:40:00 hook s5 - - -; row ${D}12:40:06 tool s5 Z - r
  row ${D}12:49:00 tool s6 V - r6; row ${D}12:50:00 hook s6 - - -; row ${D}13:00:00 hook s7 - - -; row ${D}13:00:05 tool s7 W - r7; } > "$L"
W9="${D}12:00:02 s1 ← ft-seat-close.sh · M#1 · 판정 1
${D}12:10:00 s2 ← 도구 줄 없음
${D}12:20:00 s3 ← hook 줄 없음(X)
${D}12:29:59 s4 ← hook 줄 없음(Y)
${D}12:31:00 s4 ← 도구 줄 없음
${D}12:40:00 s5 ← 도구 줄 없음
${D}12:40:06 s5 ← hook 줄 없음(Z)
${D}12:50:00 s6 ← V · - · r6
${D}13:00:00 s7 ← W · - · r7
닫힘 6 · 도구 줄 있음 3 · 도구 줄 없음 3 · hook 줄 없음 3 · 깨진 줄 0"
o="$(FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" read 2>&1)"; eq "$?|$o" "0|$W9" "⑨ 짝 · 도구 줄 없음 · hook 줄 없음 · 61초 앞 / 6초 뒤 = 짝 없음 · 60초 앞 / 5초 뒤 = 짝"
L="$T/l10.tsv"; { row ${D}10:00:00 tool x ft-nano-close.sh 'M#1' close; row ${D}10:00:01 hook x - - -; row ${D}10:00:30 hook x - - -; } > "$L"
o="$(FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" read 2>&1)"
eq "$o" "${D}10:00:01 x ← ft-nano-close.sh · M#1 · close
${D}10:00:30 x ← 도구 줄 없음
닫힘 2 · 도구 줄 있음 1 · 도구 줄 없음 1 · hook 줄 없음 0 · 깨진 줄 0" "⑩ 같은 이름 다시 씀 → 첫 hook 짝 · 둘째 hook 도구 줄 없음"
o="$(FT_SESSION_CLOSE_LEDGER="$T/l9.tsv" bash "$LED" read --since ${D}12:15:00 2>&1)"
eq "$(printf '%s\n' "$o" | grep -c ' s[12] ')|$(printf '%s\n' "$o" | tail -1)" "0|닫힘 4 · 도구 줄 있음 2 · 도구 줄 없음 2 · hook 줄 없음 3 · 깨진 줄 0" "⑪ --since → 앞 줄 빠짐"
o="$(FT_SESSION_CLOSE_LEDGER="$T/l9.tsv" bash "$LED" read --session s2 2>&1)"
eq "$o" "${D}12:10:00 s2 ← 도구 줄 없음
닫힘 1 · 도구 줄 있음 0 · 도구 줄 없음 1 · hook 줄 없음 0 · 깨진 줄 0" "⑪ --session → 그 이름만"
L="$T/l11.tsv"; { row ${D}09:00:00 hook y - - -; printf '%s\t%s\t%s\t%s\t%s\n' ${D}09:00:01 tool y t s; } > "$L"
o="$(FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" read 2>&1)"; eq "$o" "${D}09:00:00 y ← 도구 줄 없음
닫힘 1 · 도구 줄 있음 0 · 도구 줄 없음 1 · hook 줄 없음 0 · 깨진 줄 1" "⑪ 칸 5개 줄 → 세지 않고 «깨진 줄 1»"
o="$(FT_SESSION_CLOSE_LEDGER="$T/none.tsv" bash "$LED" read 2>&1)"; eq "$?|$o" "0|$E" "⑪ 원장 없음 → 끝 줄만 rc 0"

stage read "⑫ 불변(S6) · bin = kit · 줄 상한"
eq "$(env -u TMUX_PANE "$REAL_TMUX" show-hooks -g 2>&1)" "$REAL_HOOKS0" "⑫ 실 tmux show-hooks -g 앞뒤 같음"
for r in $ROOTS; do [ ! -e "$r/.fable-team/state/session-close" ] && ok "⑫ $r/.fable-team/state/session-close 안 생김" || bad "⑫ 시험이 $r/.fable-team/state/session-close 를 만듦"; done
if [ -z "${R2101_BIN:-}" ]; then for f in $TOOLS ft-session-close-ledger.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "⑫ bin = kit $f" || bad "⑫ bin ≠ kit $f"; done; fi
eq "$([ -f "$LED" ] && [ "$(wc -l < "$LED")" -le 200 ] && echo yes)" yes "⑫ ft-session-close-ledger.sh ≤ 200줄"
for f in $TOOLS; do n=1; [ "$f" != ft-nano-close.sh ] || n=2; eq "$(grep -c 'ft-session-close-ledger.sh" note' "$BIN/$f")" "$n" "⑫ $f 호출 줄 수 $n"; done

stage invariant "끝"
echo "STAGES$STAGES"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
