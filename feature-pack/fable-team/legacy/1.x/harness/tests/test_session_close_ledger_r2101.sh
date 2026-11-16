#!/usr/bin/env bash
# test_session_close_ledger_r2101.sh — r2101 세션 닫힘 원장(ft-session-close-ledger.sh) 반례 ①~⑲ (카드 design/harness/indices/대기/r2101-session-close-ledger.md · 최종판 24dbd0fcf3)
#   닫기 도구 칸 = 가짜 tmux(kill-session 순간의 원장 줄 수를 적는다 · 세션 id 조회 답 · kill rc 는 사례가 정함) + 임시 명부 · hook 칸 = 별도 소켓 실 tmux(`tmux -L r2101-<pid>` · 끝에 그 서버만 내림)
#   실 tmux 서버 · 실 명부 · 실 원장 0 · sleep 0(hook 기다림 = 둘째 hook 줄 «wait-for -S» + `wait-for`)
#   R2101_BIN = 시험할 bin(기본 팩 harness/bin · 변이 사본을 줄 때) · 기준판 = 같은 bin 에서 원장 호출(note 줄 · fail 조각)만 뺀 사본(닫기 출력 · rc 대조)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 추적 사본 원본을 직접 부른다
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_SESSION_CLOSE_LEDGER FT_SEAT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd -- "${R2101_BIN:-$HERE/../bin}" && pwd)"; KIT="$HERE/../kit/fable-team/bin"; LED="$BIN/ft-session-close-ledger.sh"
TOOLS="ft-seat-close.sh ft-nano-close.sh ft-nano-spawn-undo.sh ft-resource-reclaim.sh"
REAL_TMUX="$(command -v tmux)"; SOCK="r2101-$$"
T="$(cd "$(mktemp -d)" && pwd -P)"; HX="$(mktemp -d /tmp/r2101hXXXXXX)"   # HX = 점 없는 임시 폴더(tmux 는 세션 이름의 «.» 을 바꾼다)
trap 'env -u TMUX "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null; rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T" "$HX"' EXIT   # 그 서버와 그 소켓 파일만
fail=0; T0=$SECONDS; STAGES=""
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1:0:600}» ≠ «${2:0:600}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
stage(){ STAGES="$STAGES $1=$((SECONDS-T0))s"; T0=$SECONDS; echo "== $2"; }
nl()   { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
cols() { awk -F'\t' 'NF!=8' "$1" 2>/dev/null | wc -l | tr -d ' '; }
kinds(){ cut -f2 "$1" 2>/dev/null | tr '\n' ',' ; }
pairok() { awk -F'\t' 'NR==1{a=$3 FS $4 FS $8} NR==2{b=$3 FS $4 FS $8} END{print (NR==2 && a==b) ? "same" : "diff"}' "$1" 2>/dev/null; }   # tool · fail 줄의 3·4·8칸
row()  { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
REAL_HOOKS0="$(env -u TMUX_PANE "$REAL_TMUX" show-hooks -g 2>&1)"
ROOTS=""; for r in "${FT_ROOT:-}" "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; do
  [ -n "$r" ] && [ ! -e "$r/.fable-team/state/session-close" ] && ROOTS="$ROOTS $r"; done
cp -R "$BIN" "$T/twin"; rm -f "$T/twin/ft-session-close-ledger.sh"
for f in $TOOLS; do grep -v -e 'ft-session-close-ledger.sh" note' -e 'ft-session-close-ledger.sh" id' "$BIN/$f" | sed 's/bash "\$HERE\/ft-session-close-ledger.sh" fail [^;]*; //' > "$T/x" && cat "$T/x" > "$T/twin/$f"; done

stage prep "①②③④ note · fail 줄(S1 · S2) — 가짜 tmux"
mkdir -p "$T/nf"; printf '#!/bin/bash\necho "$*" >> "$NF_LOG"\n[ "${NF_RC:-0}" = 0 ] || exit 1\ncase "$1" in list-sessions) printf "%%s\\n" "${NF_SESS:-}";; esac\nexit 0\n' > "$T/nf/tmux"; chmod +x "$T/nf/tmux"
NF() { PATH="$T/nf:$PATH" NF_LOG="$T/nf/log" "$@"; }
L="$T/l1.tsv"; out="$(NF env NF_SESS='$7 byz-x-nano-a#0' FT_SESSION_CLOSE_LEDGER="$L" FT_SEAT='byz-x-master-pi#1' bash -c 'bash "$1" note byz-x-nano-a#0 ft-seat-close.sh "판정 12 집행" 2>&1; echo "rc=$? pid=$$"' _ "$LED")"
eq "$(nl "$L")|${out%% pid=*}" "1|rc=0" "① rc 0 · 출력 0 · 원장 1줄"
eq "$(awk -F'\t' '{print NF"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"$8}' "$L" 2>/dev/null)" "8|tool|byz-x-nano-a#0|ft-seat-close.sh|byz-x-master-pi#1|판정 12 집행|\$7|${out##*pid=}" "① 탭 8칸 · tool · 세션 · 좌석 · 7칸 id «\$7» · 8칸 = 부른 셸 pid"
[[ "$(cut -f1 "$L" 2>/dev/null)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] && ok "① 1칸 = ISO 초" || bad "① 1칸 시각 꼴: $(cut -f1 "$L" 2>/dev/null)"
NF env FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s2 t r >/dev/null 2>&1
eq "$(sed -n 2p "$L" | cut -f5)" "-" "① FT_SEAT 없이 → 5칸 «-»"
for c in "LF|인계 완료"$'\n'"후속 없음|인계 완료 후속 없음" "탭|a"$'\t'"b c|a b c" "CR|a"$'\r'"b|a b"; do
  nm="${c%%|*}"; r="${c#*|}"; v="${r%|*}"; w="${r##*|}"; L="$T/l2-$nm.tsv"
  NF env FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s t "$v" >/dev/null 2>&1
  eq "$(nl "$L")|$(cols "$L")|$(cut -f6 "$L" 2>/dev/null)" "1|0|$w" "② 사유 속 $nm → 원장 1줄 · 8칸 · 그 자리 공백 1개"; done
: > "$T/afile"; out="$(NF env FT_SESSION_CLOSE_LEDGER="$T/afile/x.tsv" bash "$LED" note s t r 2>&1 >/dev/null)"; rc=$?
eq "$rc|$out" "1|판정 불가 원장 쓰기 실패 $T/afile/x.tsv" "② 원장 쓰기 실패 = stderr «판정 불가» rc 1"
L="$T/l3.tsv"; for i in $(seq 1 20); do NF env FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note "s$i" tool "사유 $i" >/dev/null 2>&1 & done; wait
eq "$(nl "$L")|$(cols "$L")" "20|0" "③ note 20개 동시 → 20줄 · 8칸 아닌 줄 0"
L="$T/l4.tsv"; S4=$'$5 A\n$6 A2'
NF env NF_SESS="$S4" FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note A t r >/dev/null 2>&1; r1=$?
NF env NF_SESS="$S4" FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note Z t r >/dev/null 2>&1; r2=$?
NF env NF_SESS="$S4" NF_RC=1 FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note A t r >/dev/null 2>&1; r3=$?
eq "$r1$r2$r3|$(cut -f7 "$L" | tr '\n' ,)" "000|\$5,-,-," "④ id = 이름 글자 그대로 같은 세션(A → \$5 · A2 아님) · 없는 이름 · 조회 rc 1 → «-» rc 0"
L="$T/l4b.tsv"; out="$(NF env NF_SESS="$S4" FT_SESSION_CLOSE_LEDGER="$L" bash -c 'bash "$1" note A t r; : > "$NF_LOG"; bash "$1" fail A ft-seat-close.sh; echo "rc=$?"' _ "$LED" 2>&1)"
eq "$out|$(sed -n 2p "$L" | awk -F'\t' '{print $2"|"$3"|"$4"|"$6"|"$7}')|$(nl "$T/nf/log")" "rc=0|fail|A|ft-seat-close.sh|kill 실패|-|0" "④ fail 줄 1(fail · kill 실패 · id «-») · fail 의 tmux 호출 0"
eq "$(cut -f8 "$L" | sort -u | wc -l | tr -d ' ')" 1 "④ fail 줄 8칸 = 앞 note 줄 8칸"

stage note "⑤⑦⑧ ft-seat-close(S3) — 가짜 tmux · 임시 명부"
mkdir -p "$T/sc/fake" "$T/sc/resume"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/sc/reap.sh"; chmod +x "$T/sc/reap.sh"
cat > "$T/sc/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ] && ! grep -q '^kill-session' "$TMUX_LOG" 2>/dev/null || exit 1;;
  show-options) echo 1;;
  set-option) exit "${FAKE_TAG_RC:-0}";;
  kill-session) n=0; [ -f "${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=$(wc -l < "$FT_SESSION_CLOSE_LEDGER"); echo "$* lines=${n// /}" >> "$TMUX_LOG"; exit "${FAKE_KILL_RC:-0}";;
  list-sessions) case "$*" in *session_id*) for x in ${FAKE_LIVE:-}; do echo "\$5 $x"; done;; *) for x in ${FAKE_LIVE:-}; do echo "$x"; done;; esac;;
  display-message) case "$*" in *session_attached*) echo 0;; *) echo caller#0;; esac;;
esac
exit 0
EOF
chmod +x "$T/sc/fake/tmux"
sc() {  # sc <bin> <원장> [인자…] → $T/sc/out · rc · 가짜 tmux 로그 $T/sc/log
  local b="$1" l="$2"; shift 2; : > "$T/sc/log"; echo '{}' > "$T/sc/resume/W#1.json"
  printf '%s' '{"_master": "M#1", "_hil_route": "P#1", "M#1": {"role": "master", "tick": "t"}, "P#1": {"role": "planner", "tick": "t"}, "W#1": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}' > "$T/sc/seats.json"
  mkdir -p "$T/sc/comm" "$T/sc/state"   # 크리티컬 알림·우편함 = 임시 폴더(실 우편함 쓰기 0 · master #316920)
  ( cd "$T" && unset FT_ROOT FT_MBOX && FT_MBOX_DIR="$T/sc/comm" FT_CRITICAL_STATE_DIR="$T/sc/state" PATH="$T/sc/fake:$PATH" TMUX_LOG="$T/sc/log" FT_SEAT_REAP_BIN="$T/sc/reap.sh" ZC_RESUME_DIR="$T/sc/resume" FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' \
    bash "$b/ft-seat-close.sh" 'W#1' --seats "$T/sc/seats.json" "$@" > "$T/sc/out" 2>&1 ); echo $?; }
L="$T/l5.tsv"; rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason "판정 2050 노출 나노")"; o="$(cat "$T/sc/out")"; k="$(grep '^kill-session' "$T/sc/log")"
r2="$(FAKE_LIVE="W#1 W#2" sc "$T/twin" "$T/l5b.tsv" --reason "판정 2050 노출 나노")"; o2="$(cat "$T/sc/out")"
eq "$rc|$o" "$r2|$o2" "⑤ 닫기 출력 · rc = 기준판"
has "$o" "CLOSED-SESSION W#1" "⑤ 닫힘 길(CLOSED-SESSION)"
eq "$(nl "$L")|$(cut -f2-7 "$L" 2>/dev/null)" "1|tool	W#1	ft-seat-close.sh	byz-t-master#1	판정 2050 노출 나노	\$5" "⑤ tool 줄 1 · 도구 칸 ft-seat-close.sh · 세션 칸 = 그 좌석 · fail 줄 0"
eq "$k" "kill-session -t =W#1 lines=1" "⑤ kill 인자 그대로 · kill 때 원장 줄 수 = 1(note 가 먼저)"
rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$T/afile/x.tsv" --reason "판정 2050 노출 나노")"
eq "$rc|$(cat "$T/sc/out")" "$r2|$o2" "⑤ 원장 쓰기 실패여도 닫기 출력 · rc = 기준판"
L="$T/l7.tsv"; rc="$(FAKE_LIVE="W#1" sc "$BIN" "$L" --reason r)"; o="$(cat "$T/sc/out")"
r2="$(FAKE_LIVE="W#1" sc "$T/twin" "$T/l7b.tsv" --reason r)"
eq "$rc|$o" "$r2|$(cat "$T/sc/out")" "⑦ HELD 출력 · rc = 기준판"
eq "$rc|$(nl "$L")|$(grep -c '^kill-session' "$T/sc/log")" "3|0|0" "⑦ seat-close HELD rc 3 → tool · fail 줄 0 · kill 0"
rc="$(FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason r --verdict 99999)"; o="$(cat "$T/sc/out")"
eq "$rc|${o:0:6}|$(nl "$L")|$(grep -c '^kill-session' "$T/sc/log")" "1|REJECT|0|0" "⑦ seat-close REJECT → tool · fail 줄 0 · kill 0"
L="$T/l7t.tsv"; rc="$(FAKE_TAG_RC=1 FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason r)"; o="$(cat "$T/sc/out")"
r2="$(FAKE_TAG_RC=1 FAKE_LIVE="W#1 W#2" sc "$T/twin" "$T/l7u.tsv" --reason r)"
eq "$rc|$o" "$r2|$(cat "$T/sc/out")" "⑦ seat-close 태그 해제 실패 출력 · rc = 기준판(DA 구현 R1)"
eq "$rc|$(grep -c '^FAIL tag W#1' <<<"$o")|$(nl "$L")|$(grep -c '^kill-session' "$T/sc/log")" "1|1|0|0" "⑦ seat-close 태그 해제 실패 rc 1 · kill 0 → tool · fail 줄 0(DA 구현 R1)"
L="$T/l8a.tsv"; rc="$(FAKE_KILL_RC=1 FAKE_LIVE="W#1 W#2" sc "$BIN" "$L" --reason r)"; o="$(cat "$T/sc/out")"
r2="$(FAKE_KILL_RC=1 FAKE_LIVE="W#1 W#2" sc "$T/twin" "$T/l8x.tsv" --reason r)"
eq "$rc|$o" "$r2|$(cat "$T/sc/out")" "⑧ seat-close kill 실패 출력 · rc = 기준판"
eq "$(kinds "$L")|$(pairok "$L")" "tool,fail,|same" "⑧ seat-close kill 실패 → tool 줄 + fail 줄(3 · 4 · 8칸 같음)"

stage seat-close "⑥⑧ ft-nano-close 2곳(닫기 · 재실행)"
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
  kill-session) n=0; [ -f "${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=$(wc -l < "$FT_SESSION_CLOSE_LEDGER"); echo "$* lines=${n// /}" >> "$FAKE_LOG"; exit "${FAKE_KILL_RC:-0}";;
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
  o="$(cd "$REPO" && env -i HOME="$HOME" PATH="$NC/fake:$PATH" FT_PACK_ROOT="$PACK" FT_SHEET_ROOT="$NC/sheet" FAKE_PANES="$NC/panes" FAKE_CWD="$NC/cwd" FAKE_LOG="$NC/tlog" FAKE_GH_JSON="$NC/gh.json" FAKE_KILL_RC="${FAKE_KILL_RC:-0}" \
    FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$NC/ledger.md" FT_NANO_FEAT=main \
    FT_EVENT_DIR="$NC/events" FT_INBOX_ROOT="$NC/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$NC/wtclean" FT_WT_AUTOCLEAN=0 bash "$NC/$d/ft-nano-close.sh" "$SEAT" --result "$NC/result.md" --recv 1 "$@" 2>&1)"; r=$?
  o="$(printf '%s\n' "$o" | grep -v '^STEP ' | sed 's/ · 재측정: .*$//')"; printf '%s\nrc=%s\n' "${o//$NC\/$d/<bin>}" "$r"; }
mkdir -p "$NC/sheet/.fable-team/state"
L="$T/l6a.tsv"; ncset; o="$(ncrun bin "$L" --landed-pr 77)"; k="$(grep '^kill-session' "$NC/tlog")"
ncset; o2="$(ncrun twin "$T/l6x.tsv" --landed-pr 77)"
eq "$o" "$o2" "⑥ nano-close 닫기 출력 · rc = 기준판"
has "$o" "KILLED $SEAT" "⑥ nano-close 닫기 길(KILLED)"
eq "$(nl "$L")|$(cut -f2-5 "$L" 2>/dev/null)|$k" "1|tool	$SEAT	ft-nano-close.sh	byz-t-master#1|kill-session -t %9 lines=1" "⑥ nano-close(닫기) tool 줄 1 · fail 0 · kill 때 원장 줄 수 1"
L="$T/l6b.tsv"; : > "$NC/tlog"; o="$(ncrun bin "$L")"; k="$(grep '^kill-session' "$NC/tlog")"
ncset; ncrun twin "$T/l6y.tsv" --landed-pr 77 >/dev/null; : > "$NC/tlog"; o2="$(ncrun twin "$T/l6y.tsv")"
eq "$o" "$o2" "⑥ nano-close 재실행 출력 · rc = 기준판"
has "$o" "재실행 — 명부에 없고 원장 닫힘 행 있음" "⑥ nano-close 재실행 길"
eq "$(nl "$L")|$(cut -f2-6 "$L" 2>/dev/null)|$k" "1|tool	$SEAT	ft-nano-close.sh	byz-t-master#1	재실행|kill-session -t %9 lines=1" "⑥ nano-close(재실행) tool 줄 1 · fail 0 · kill 때 원장 줄 수 1"
export FAKE_KILL_RC=1
L="$T/l8b.tsv"; ncset; o="$(ncrun bin "$L" --landed-pr 77)"; ncset; o2="$(ncrun twin "$T/l8y.tsv" --landed-pr 77)"
eq "$o" "$o2" "⑧ nano-close(닫기) kill 실패 출력 · rc = 기준판"
eq "$(kinds "$L")|$(pairok "$L")" "tool,fail,|same" "⑧ nano-close(닫기) kill 실패 → tool 줄 + fail 줄"
L="$T/l8c.tsv"; o="$(ncrun bin "$L")"; ncset; ncrun twin "$T/l8z.tsv" --landed-pr 77 >/dev/null; o2="$(ncrun twin "$T/l8z.tsv")"
eq "$o" "$o2" "⑧ nano-close(재실행) kill 실패 출력 · rc = 기준판"
eq "$(kinds "$L")|$(pairok "$L")|$(cut -f6 "$L" | head -1)" "tool,fail,|same|재실행" "⑧ nano-close(재실행) kill 실패 → tool 줄 + fail 줄"
unset FAKE_KILL_RC

stage nano-close "⑥⑦⑧ ft-nano-spawn-undo(롤백) · ft-resource-reclaim"
undo() {  # undo <bin> <원장> <kill rc> → «rc␟출력␟kill 로그␟좌석»
  python3 - "$1" "$2" "$HERE/scripts" "$(mktemp -d "$T/u.XXXX")" "$3" <<'PY'
import pathlib, sys
b, led, sp, tmp, krc = sys.argv[1:6]; sys.path.insert(0, sp)
import _nano_rollback_env as E
E.BIN = pathlib.Path(b); env = E.make_env(pathlib.Path(tmp))
kill = 'case "$1" in\n  kill-session) n=0; [ -f "$R2101_L" ] && n=$(wc -l < "$R2101_L"); echo "$* lines=${n// /}" >> "$R81_DIR/kill.log"; exit "$R2101_KRC" ;;'
E.exe(env["sh"] / "tmux", E.TMUX.replace('case "$1" in', kill, 1))
r = E.roll(env, FT_SESSION_CLOSE_LEDGER=led, R2101_L=led, R2101_KRC=krc, FT_SEAT="byz-t-master#1")
k = env["tmp"] / "kill.log"
print("\x1f".join([str(r.returncode), r.stdout.strip(), k.read_text().strip() if k.exists() else "", E.SEAT]))
PY
}
L="$T/l6c.tsv"; IFS=$'\x1f' read -r rc o k us <<<"$(undo "$BIN" "$L" 0)"; IFS=$'\x1f' read -r r2 o2 _ _ <<<"$(undo "$T/twin" "$T/l6z.tsv" 0)"
eq "$rc|$o" "$r2|$o2" "⑥ spawn-undo 출력 · rc = 기준판"
eq "$rc|$o" "0|UNDONE $us" "⑥ spawn-undo 롤백 길(UNDONE)"
eq "$(nl "$L")|$(cut -f2-5 "$L" 2>/dev/null)|$k" "1|tool	$us	ft-nano-spawn-undo.sh	byz-t-master#1|kill-session -t %1 lines=1" "⑥ spawn-undo tool 줄 1 · fail 0 · kill 때 원장 줄 수 1"
L="$T/l8d.tsv"; IFS=$'\x1f' read -r rc o _ _ <<<"$(undo "$BIN" "$L" 1)"; IFS=$'\x1f' read -r r2 o2 _ _ <<<"$(undo "$T/twin" "$T/l8w.tsv" 1)"
eq "$rc|$o" "$r2|$o2" "⑧ spawn-undo kill 실패 출력 · rc = 기준판"
eq "$(kinds "$L")|$(pairok "$L")" "tool,fail,|same" "⑧ spawn-undo kill 실패 → tool 줄 + fail 줄"
. "$HERE/lib/fake_reclaim_world.sh"
mv "$F/tmux" "$F/tmux.world"
cat > "$F/tmux" <<EOF
#!/bin/bash
[ "\$1" != kill-session ] || { n=0; [ -f "\${FT_SESSION_CLOSE_LEDGER:-/nonexistent}" ] && n=\$(wc -l < "\$FT_SESSION_CLOSE_LEDGER"); echo "lines=\${n// /}" >> "$ST/killlines"; [ "\${FAKE_KILL_RC:-0}" = 0 ] || exit 1; }
exec "$F/tmux.world" "\$@"
EOF
chmod +x "$F/tmux"
rcl() { local b="$1" l="$2" o r; shift 2; o="$(FT_SESSION_CLOSE_LEDGER="$l" FT_SEAT='byz-t-master#1' run "$b/ft-resource-reclaim.sh" --caller byz-t-master-claude#1 --need 2 "$@")"; r=$?; printf '%s\nrc=%s\n' "${o//$b/<bin>}" "$r"; }
L="$T/l6d.tsv"; setup; o="$(rcl "$BIN" "$L")"; k="$(cat "$ST/killlines" 2>/dev/null)"; setup; o2="$(rcl "$T/twin" "$T/l6w.tsv")"
eq "$o" "$o2" "⑥ reclaim 출력 · rc = 기준판"
eq "$(nl "$L")|$(cut -f2-6 "$L" 2>/dev/null)|$k" "1|tool	byz-t-role-claude#1	ft-resource-reclaim.sh	byz-t-master#1	판정 1344 · tmux 정리 2026-07-11|lines=1" "⑥ reclaim tool 줄 1 · fail 0 · kill 때 원장 줄 수 1"
L="$T/l7d.tsv"; setup; o="$(rcl "$BIN" "$L" --dry-run)"
has "$o" "WOULD-CLOSE(kill-session)" "⑦ reclaim DRY → WOULD-CLOSE"
eq "$(nl "$L")|$(cat "$ST/killlines" 2>/dev/null | wc -l | tr -d ' ')" "0|0" "⑦ reclaim DRY → tool · fail 줄 0 · kill 0"
L="$T/l8e.tsv"; setup; o="$(FAKE_KILL_RC=1 rcl "$BIN" "$L")"; setup; o2="$(FAKE_KILL_RC=1 rcl "$T/twin" "$T/l8v.tsv")"
eq "$o" "$o2" "⑧ reclaim kill 실패 출력 · rc = 기준판"
eq "$(kinds "$L")|$(pairok "$L")" "tool,fail,|same" "⑧ reclaim kill 실패 → tool 줄 + fail 줄"

stage undo-reclaim "⑨⑩ hook(S4) — 별도 소켓 실 tmux"
mkdir -p "$T/tb"; printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCK" > "$T/tb/tmux"; chmod +x "$T/tb/tmux"
TB() { env -u TMUX -u TMUX_PANE PATH="$T/tb:$PATH" "$@"; }
wait_lines() { local i; for i in $(seq 1 2000); do [ "$(nl "$1")" -ge "$2" ] && return 0; done; return 1; }
closed() { timeout 10 env -u TMUX "$REAL_TMUX" -L "$SOCK" wait-for r2101-closed; wait_lines "$1" "$2"; }
mine() { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF "$LED hook #{q:hook_session} #{q:hook_session_name}"; }
other() { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF '@r2101_other'; }
L="$T/l9.tsv"; TB env FT_SESSION_CLOSE_LEDGER="$L" tmux -f /dev/null new-session -d -s keep cat
TB tmux set-hook -g session-closed 'set-option -g @r2101_other 1'
o1="$(TB bash "$LED" hook-on 2>&1)"; r1=$?; o2="$(TB bash "$LED" hook-on 2>&1)"; r2=$?
eq "$r1|$r2|$(mine)|$(other)" "0|0|1|1" "⑩ hook-on 2회 → 내 줄 1 · 남의 줄 1 그대로"
eq "$(TB bash "$LED" hook-status 2>&1)" "HOOK on" "⑩ hook-status «HOOK on»"
TB tmux set-hook -ag session-closed 'wait-for -S r2101-closed'
N9=("plain-a" "review room" "a;touch $HX/x" "\$(touch $HX/y)"); WANT=""; n=0
sid() { TB tmux list-sessions -F '#{session_id} #{session_name}' | S="$1" awk '{i=$1; sub(/^[^ ]+ /,"")} $0==ENVIRON["S"]{print i}'; }
for s in "${N9[@]}"; do TB tmux new-session -d -s "$s" cat
  id="$(sid "$s")"; WANT="$WANT$s|$id;"
  TB tmux kill-session -t "$id"; n=$((n+1)); closed "$L" "$n"; done
TB tmux new-session -d -s 'end one' "\"$REAL_TMUX\" -L $SOCK wait-for r2101-go"; id="$(sid 'end one')"; WANT="${WANT}end one|$id;"
TB tmux wait-for -S r2101-go; closed "$L" 5
eq "$(nl "$L")|$(cols "$L")|$(awk -F'\t' '{print $3"|"$7";"}' "$L" | tr -d '\n')" "5|0|$WANT" "⑨ 5개 닫힘(kill 4 · pane 명령 끝 1) → hook 줄 5 · 3칸 = 이름 글자 그대로 · 7칸 = 닫기 전 id"
eq "$(awk -F'\t' '{print $2 $4 $5 $6 $8}' "$L" | sort -u)" "hook----" "⑨ 2칸 hook · 4 · 5 · 6 · 8칸 «-»"
eq "$(ls "$HX")" "" "⑨ <임시>/x · <임시>/y 안 생김(세션 이름을 셸 글로 읽지 않음)"
eq "$(TB bash "$LED" hook '$1' 2>&1; echo "rc=$?")|$(TB bash "$LED" hook '$1' a b 2>&1; echo "rc=$?")|$(nl "$L")" "rc=0|rc=0|5" "⑨ hook 인자 1개 · 3개 → 줄 0 · 출력 0 · rc 0"
o="$(TB bash "$LED" hook-off 2>&1)"; eq "$?|$(mine)|$(other)" "0|0|1" "⑩ hook-off → 내 줄 0 · 남의 줄 1"
eq "$(TB bash "$LED" hook-status 2>&1)" "HOOK off" "⑩ hook-status «HOOK off»"
TB tmux kill-server 2>/dev/null; o="$(TB bash "$LED" hook-status 2>&1)"; rc=$?
eq "$([ "$rc" -ne 0 ] && echo nz)|${o:0:5}|$(printf '%s\n' "$o" | wc -l | tr -d ' ')" "nz|판정 불가|1" "⑩ tmux 조회 실패 → «판정 불가» 1줄 rc≠0"

stage hook "⑪~⑱ read(S5)"
D=2026-11-16T; RD() { FT_SESSION_CLOSE_LEDGER="$1" bash "$LED" read "${@:2}" 2>&1; }
E0="닫힘 0 · 후보 0 · 도구 줄 없음 0 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0"
L="$T/l11.tsv"; i='$5'
{ row ${D}12:00:00 tool s1 ft-seat-close.sh 'M#1' "판정 1" "$i" 11; row ${D}12:00:02 hook s1 - - - "$i" -; row ${D}12:10:00 hook s2 - - - "$i" -; row ${D}12:20:00 tool s3 X - r "$i" 3
  row ${D}12:29:59 tool s4 Y - r "$i" 4; row ${D}12:31:00 hook s4 - - - "$i" -; row ${D}12:40:00 hook s5 - - - "$i" -; row ${D}12:40:06 tool s5 Z - r "$i" 5
  row ${D}12:49:00 tool s6 V - r6 "$i" 6; row ${D}12:50:00 hook s6 - - - "$i" -; row ${D}13:00:00 hook s7 - - - "$i" -; row ${D}13:00:05 tool s7 W - r7 "$i" 7; } > "$L"
W="${D}12:00:02 s1 후보 ← ft-seat-close.sh · M#1 · 판정 1
${D}12:10:00 s2 ← 도구 줄 없음
${D}12:20:00 s3 ← hook 줄 없음(X)
${D}12:29:59 s4 ← hook 줄 없음(Y)
${D}12:31:00 s4 ← 도구 줄 없음
${D}12:40:00 s5 ← 도구 줄 없음
${D}12:40:06 s5 ← hook 줄 없음(Z)
${D}12:50:00 s6 후보 ← V · - · r6
${D}13:00:00 s7 후보 ← W · - · r7
닫힘 6 · 후보 3 · 도구 줄 없음 3 · hook 줄 없음 3 · kill 실패 0 · 깨진 줄 0"
o="$(RD "$L")"; eq "$?|$o" "0|$W" "⑪ 짝 · 도구 줄 없음 · hook 줄 없음 · 61초 앞 / 6초 뒤 = 짝 없음 · 60초 앞 / 5초 뒤 = 짝"
L="$T/l12.tsv"; { row ${D}10:00:00 tool x ft-nano-close.sh 'M#1' close "$i" 1; row ${D}10:00:01 hook x - - - "$i" -; row ${D}10:00:30 hook x - - - "$i" -; } > "$L"
eq "$(RD "$L")" "${D}10:00:01 x 후보 ← ft-nano-close.sh · M#1 · close
${D}10:00:30 x ← 도구 줄 없음
닫힘 2 · 후보 1 · 도구 줄 없음 1 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0" "⑫ 같은 id 다시 씀 → 첫 hook 짝 · 둘째 hook 도구 줄 없음"
L="$T/l13a.tsv"; { row ${D}12:00:00 tool A T S r '$5' 1; row ${D}12:00:20 hook A - - - '$9' -; } > "$L"
eq "$(RD "$L")" "${D}12:00:00 A ← hook 줄 없음(T)
${D}12:00:20 A ← 도구 줄 없음
닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 1 · kill 실패 0 · 깨진 줄 0" "⑬ⓐ 같은 이름 · 다른 id → 짝 0"
L="$T/l13b.tsv"; { row ${D}12:00:00 tool A T S5 r5 '$5' 1; row ${D}12:00:00 tool A T S9 r9 '$9' 2; row ${D}12:00:00 hook A - - - '$9' -; } > "$L"; o="$(RD "$L")"
has "$o" "${D}12:00:00 A 후보 ← T · S9 · r9" "⑬ⓑ 같은 초 → hook 은 같은 id(\$9) tool 줄과 짝"
has "$o" "${D}12:00:00 A ← hook 줄 없음(T)" "⑬ⓑ \$5 tool 줄 = hook 줄 없음"
L="$T/l13c.tsv"; { row ${D}12:00:00 tool A T S r '$5' 1; row ${D}12:00:02 hook B - - - '$5' -; } > "$L"
eq "$(RD "$L" | tail -1)" "닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 1 · kill 실패 0 · 깨진 줄 0" "⑬ⓒ id 같고 이름 다름 → 짝 0"
L="$T/l14a.tsv"; { row ${D}12:00:00 tool A T S r '$5' 100; row ${D}12:00:00 fail A T S "kill 실패" - 100; row ${D}12:00:20 hook A - - - '$5' -; } > "$L"
eq "$(RD "$L")" "${D}12:00:00 A ← kill 실패(T)
${D}12:00:20 A ← 도구 줄 없음
닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 0 · kill 실패 1 · 깨진 줄 0" "⑭ⓐ kill 실패 뒤 손으로 닫힘 → kill 실패 · 도구 줄 없음"
L="$T/l14b.tsv"; { row ${D}12:00:00 tool A T X r '$5' 100; row ${D}12:00:00 tool A T Y r '$5' 200; row ${D}12:00:00 hook A - - - '$5' -; row ${D}12:00:00 fail A T Y "kill 실패" - 200; } > "$L"; o="$(RD "$L")"
has "$o" "${D}12:00:00 A 후보 ← T · X · r" "⑭ⓑ 두 도구 → hook 은 pid 100(좌석 X) 줄과 짝"
has "$o" "${D}12:00:00 A ← kill 실패(T)" "⑭ⓑ pid 200 줄 = kill 실패"
L="$T/l14c.tsv"; { row ${D}12:00:00 fail A T S "kill 실패" - 300; } > "$L"
eq "$(RD "$L")" "닫힘 0 · 후보 0 · 도구 줄 없음 0 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 1" "⑭ⓒ 앞 tool 줄 없는 fail 줄 → 깨진 줄 1"
L="$T/l15.tsv"; { row ${D}12:00:00 tool A T S r - 1; row ${D}12:00:02 hook A - - - '$5' -; } > "$L"
eq "$(RD "$L")" "${D}12:00:00 A ← hook 줄 없음(T · id 없음)
${D}12:00:02 A ← 도구 줄 없음
닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 1 · kill 실패 0 · 깨진 줄 0" "⑮ id 없는 tool 줄 → 짝 0 · «id 없음»"
L="$T/l16.tsv"; { row ${D}12:00:00 tool A T S r '$0' 100; row ${D}12:00:20 hook A - - - '$0' -; } > "$L"; o="$(RD "$L")"
eq "$o" "${D}12:00:20 A 후보 ← T · S · r
닫힘 1 · 후보 1 · 도구 줄 없음 0 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0" "⑯ 서버가 다시 뜬 뒤 같은 이름 · id → «후보» 1줄(열린 줄)"
eq "$(printf '%s\n' "$o" | grep -cE '확정|닫음|도구 줄 있음')" 0 "⑯ 출력에 «확정» · «닫음» · «도구 줄 있음» 0"
L="$T/l17.tsv"; { row ${D}12:00:00 tool A T S r '$5' 100; row ${D}12:00:20 hook A - - - '$5' -; } > "$L"; o="$(RD "$L")"
eq "$(printf '%s\n' "$o" | head -1)" "${D}12:00:20 A 후보 ← T · S · r" "⑰ fail 줄 전에 도구가 죽음 → «후보» 1줄(열린 줄)"
eq "$(printf '%s\n' "$o" | grep -cE '확정|닫음|도구 줄 있음')" 0 "⑰ 출력에 «확정» · «닫음» · «도구 줄 있음» 0"
o="$(RD "$T/l11.tsv" --since ${D}12:15:00)"
eq "$(printf '%s\n' "$o" | grep -c ' s[12] ')|$(printf '%s\n' "$o" | tail -1)" "0|닫힘 4 · 후보 2 · 도구 줄 없음 2 · hook 줄 없음 3 · kill 실패 0 · 깨진 줄 0" "⑱ --since → 앞 줄 빠짐"
eq "$(RD "$T/l11.tsv" --session s2)" "${D}12:10:00 s2 ← 도구 줄 없음
닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0" "⑱ --session → 그 이름만"
L="$T/l16.tsv"; { row ${D}09:00:00 hook y - - - "$i" -; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' ${D}09:00:01 tool y t s r "$i"; } > "$L"
eq "$(RD "$L")" "${D}09:00:00 y ← 도구 줄 없음
닫힘 1 · 후보 0 · 도구 줄 없음 1 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 1" "⑱ 칸 7개 줄 → 세지 않고 «깨진 줄 1»"
o="$(RD "$T/none.tsv")"; eq "$?|$o" "0|$E0" "⑱ 원장 없음 → 끝 줄만 rc 0"

stage read "⑲ 불변(S6) · bin = kit · 줄 상한"
eq "$(env -u TMUX_PANE "$REAL_TMUX" show-hooks -g 2>&1)" "$REAL_HOOKS0" "⑲ 실 tmux show-hooks -g 앞뒤 같음"
for r in $ROOTS; do [ ! -e "$r/.fable-team/state/session-close" ] && ok "⑲ $r/.fable-team/state/session-close 안 생김" || bad "⑲ 시험이 $r/.fable-team/state/session-close 를 만듦"; done
if [ -z "${R2101_BIN:-}" ]; then for f in $TOOLS ft-session-close-ledger.sh ft_session_close_read.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "⑲ bin = kit $f" || bad "⑲ bin ≠ kit $f"; done; fi
eq "$([ -f "$LED" ] && [ "$(wc -l < "$LED")" -le 200 ] && echo yes)" yes "⑲ ft-session-close-ledger.sh ≤ 200줄"
for f in $TOOLS; do n=1; [ "$f" != ft-nano-close.sh ] || n=2
  eq "$(grep -c 'ft-session-close-ledger.sh" note' "$BIN/$f")|$(grep -o 'ft-session-close-ledger.sh" fail' "$BIN/$f" | wc -l | tr -d ' ')" "$n|$n" "⑲ $f 호출 note $n · fail $n"; done

stage invariant "끝"
echo "STAGES$STAGES"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
