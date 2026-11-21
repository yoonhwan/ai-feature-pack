#!/usr/bin/env bash
# test_nano_close_ft2_hint_r2401.sh — 카드 r2401 K5: 1.x ft-nano-close 가 ft2 좌석을 거절(rc 5)할 때 마지막 줄 «FT2-SEAT …» 앞에
#   «닫는 명령 = python3 <ft2 CURRENT>/core/cli.py keeper --root <루트> --close-seat <석> --verdict <N> --approve "<planner 좌석> #<seq>" --reason "<사유>" · 닫기 요청 = planner master 에 1통» 1줄을 더한다.
# 반례 ⑫ — ① 안내 줄 1개(FT2-SEAT 바로 앞 · 마지막 줄 그대로) · ② 기준판(BASE) = 그 줄 없음(Red) · ③ ft2 판 못 찾음 = 글자 그대로(추측 0) · ④ 1.x 좌석 = 기준판과 같음(회귀 0).
# 픽스처 = 임시 데이터 루트 꼴 git 리포 1 + 팩 꼴 git 리포 1(그 worktree 를 teams/t/worktrees/k@a1 에) + 가짜 tmux(PATH 앞) + 키트 bin 임시 사본.
#   실 명부 · 실 tmux · 실 우편함 · 실 워크트리 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE=42f98b9936d0235aede0401b335b96c48797e381   # 기준판(이 카드 직전 팩 main) — r2401 K5 줄이 없는 판
KREL=feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── bin 두 벌: 새 판(작업 나무 키트 사본) · 기준판(같은 사본에 ft-nano-close.sh 만 BASE 로)
bash "$HERE/lib/kit_bin_copy.sh" "$T/new" >/dev/null || bad "kit_bin_copy new"
[ -n "${R2401_BIN:-}" ] && cp "$R2401_BIN/ft-nano-close.sh" "$T/new/ft-nano-close.sh"   # R2401_BIN=<bin 폴더> = 시험 대상(변이 사본 대조용 · 기본 = 작업 나무 키트)
bash "$HERE/lib/kit_bin_copy.sh" "$T/base" >/dev/null || bad "kit_bin_copy base"
git -C "$HERE" show "$BASE:$KREL/ft-nano-close.sh" > "$T/base/ft-nano-close.sh" 2>/dev/null || bad "기준판 ft-nano-close.sh 못 읽음($BASE)"
for b in new base; do printf '#!/bin/sh\necho "OK cherry stub"\n' > "$T/$b/ft-nano-cherry-gate.sh"; chmod +x "$T/$b/"*; done
bash -n "$T/new/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

# ── 가짜 tmux: list-panes = FAKE_PANES · display-message = FAKE_CWD · 변경 동사 = FAKE_LOG 기록
mkdir -p "$T/fake" "$T/home" "$T/comm/bodies" "$T/sheet/.fable-team/state" "$T/wtclean" "$T/ft2/versions/9.9.9/core"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG.all"
case "$1" in
  list-panes|ls) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "${FAKE_TMUX_ERR:-no server running on /tmp/fake}"; exit "${FAKE_TMUX_RC:-1}"; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  *) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/fake/tmux"
echo res > "$T/result.md"; echo seq > "$T/comm/bodies/1.txt"
printf '9.9.9\n' > "$T/ft2/CURRENT"; printf 'print("stub")\n' > "$T/ft2/versions/9.9.9/core/cli.py"

# ── 데이터 루트 꼴 리포(R) · 팩 꼴 리포(P) · ft2 좌석 워크트리(W2) · 1.x 좌석 워크트리(W1)
SEAT='byz-harness-nano-k#0'
R="$T/root"; P="$T/pack"; W2="$R/.fable-team/teams/t/worktrees/k@a1"; W1="$R/.worktrees/v65-k"; LWT="$R/.worktrees/ledger"
SEATS="$R/.fable-team/seats-harness.json"; LEDGER="$R/design/harness/NANO-LEDGER.md"
mkdir -p "$R/design/harness/indices/진행" "$R/.fable-team/bin-harness" "$P"
git -C "$R" init -q -b main; printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"; : > "$LEDGER"
GC "$R" add -A; GC "$R" commit -qm init; git -C "$R" update-ref refs/remotes/origin/main main
GC "$R" worktree add -q "$LWT" -b lw main
git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m init
GC "$P" worktree add -q "$W2" -b nano/r2401-k main
GC "$R" worktree add -q "$W1" -b nano/k main
printf '{"%s":{"role":"nano","agent":"pi","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
TENV="$R/.fable-team/bin-harness/harness-env.sh"; printf 'export FT_SEATS_JSON=%s\n' "$SEATS" > "$TENV"
LOK="$R/.worktrees/ledger-ok"; GC "$R" worktree add -q --detach "$LOK" main

# run <bin 판> <pane cwd|-> [env=값 …] -- [인자 …] → stdout 만(stderr = $T/err) · rc
run() {
  local b="$1" pc="$2"; shift 2; local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; [ $# -gt 0 ] && shift
  if [ "$pc" = - ]; then : > "$T/panes"; else printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$pc" > "$T/cwd"; fi
  ( cd "$R" && env -i HOME="$T/home" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
      FT_CRITICAL_OFF=1 FT_ROOTS_TSV="$T/none.tsv" FT_SEATS_JSON="$SEATS" FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/main \
      FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER_WT="$LOK" \
      bash -c 'while [ "$1" != -- ]; do export "$1"; shift; done; shift; exec bash "$@"' _ "${envs[@]}" -- \
      "$T/$b/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>"$T/err" ); }
last() { printf '%s\n' "$1" | awk 'NF{l=$0} END{print l}'; }
hint() { printf '닫는 명령 = python3 %s keeper --root %s --close-seat %s --verdict <N> --approve "<planner 좌석> #<seq>" --reason "<사유>" · 닫기 요청 = planner master 에 1통' "$1" "$R" "$SEAT"; }
ft2_ok() {   # <이름> <출력> <rc> — 마지막 줄 = FT2-SEAT 그대로 · 안내 줄 1개가 바로 앞 · REJECT/CLOSED/HELD/WAIT 줄 0
  local n; n="$(printf '%s\n' "$2" | grep -c '^FT2-SEAT ')"
  [ "$3" = 5 ] && [ "$n" = 1 ] && case "$(last "$2")" in "FT2-SEAT $SEAT — 1.x 닫기 대상 아님 · 닫는 길 = ft2 keeper"*"워크트리=$W2") true;; *) false;; esac \
    && ! printf '%s\n' "$2" | grep -qE '^(REJECT|CLOSED|HELD|WAIT)' && ok "$1 rc 5 · FT2-SEAT 1줄(마지막)" || bad "$1 rc=$3 FT2-SEAT=$n ← ${2:0:400}"
}

echo "== ① pane cwd = ft2 워크트리 · ft2 CURRENT 판 있음"
o="$(run new "$W2" FT2_HOME="$T/ft2")"; rc=$?
ft2_ok "①" "$o" "$rc"
want="$(hint "$T/ft2/versions/9.9.9/core/cli.py")"
[ "$(printf '%s\n' "$o" | grep -c '^닫는 명령 = ')" = 1 ] && ok "① 안내 줄 1개" || bad "① 안내 줄 $(printf '%s\n' "$o" | grep -c '^닫는 명령 = ')개"
[ "$(printf '%s\n' "$o" | grep -B1 '^FT2-SEAT ' | head -n 1)" = "$want" ] && ok "① 안내 줄 = FT2-SEAT 바로 앞 · 글자 그대로" || bad "① 안내 줄 다름 ← $(printf '%s\n' "$o" | grep -B1 '^FT2-SEAT ' | head -n 1)"

echo "== ② 기준판($BASE) = 안내 줄 없음 · 나머지 그대로(Red)"
o="$(run base "$W2" FT2_HOME="$T/ft2")"; rc=$?
ft2_ok "②" "$o" "$rc"
[ "$(printf '%s\n' "$o" | grep -c '^닫는 명령 = ')" = 0 ] && ok "② 기준판 안내 줄 0개 = Red" || bad "② 기준판에 안내 줄 있음"
[ "$(printf '%s\n' "$o")" = "$(printf '%s\n' "$o" | grep -v '^닫는 명령 = ')" ] && ok "② 기준판 출력 = FT2-SEAT 한 줄" || bad "② 기준판 출력에 다른 줄"

echo "== ③ ft2 판 못 찾음(FT2_HOME·FT2_CLI 없음) = 자리 글자 그대로 · 추측 0"
o="$(run new "$W2" FT2_HOME="$T/none" FT2_CLI=)"; rc=$?
ft2_ok "③" "$o" "$rc"
[ "$(printf '%s\n' "$o" | grep -B1 '^FT2-SEAT ' | head -n 1)" = "$(hint "$T/none/versions/<CURRENT>/core/cli.py")" ] && ok "③ 안내 줄 = <CURRENT> 자리 글자" || bad "③ 안내 줄 다름 ← $(printf '%s\n' "$o" | grep -B1 '^FT2-SEAT ' | head -n 1)"
o="$(run new "$W2" FT2_HOME="$T/none" FT2_CLI="$T/my cli.py")"; rc=$?
[ "$(printf '%s\n' "$o" | grep -B1 '^FT2-SEAT ' | head -n 1)" = "$(hint "$T/my cli.py")" ] && ok "③ FT2_CLI 있으면 그 값 그대로" || bad "③ FT2_CLI 무시됨"

echo "== ④ 1.x 좌석(워크트리 $W1) = 새 판 = 기준판(stdout · rc · 회귀 0)"
o1="$(run new "$W1" FT2_HOME="$T/ft2")"; r1=$?; o2="$(run base "$W1" FT2_HOME="$T/ft2")"; r2=$?
o1="${o1//$T\/new/BIN}"; o2="${o2//$T\/base/BIN}"
[ "$o1" = "$o2" ] && [ "$r1" = "$r2" ] && ! printf '%s\n' "$o1" | grep -q '^FT2-SEAT \|^닫는 명령 = ' && ok "④ 1.x 좌석 = 기준판과 같음(rc=$r1)" || bad "④ 새 rc=$r1 기준 rc=$r2 ← ${o1:0:300} ‖ ${o2:0:300}"

echo "== ⑤ tmux 변경 동사 0(닫기 손 0)"
[ ! -s "$T/tlog" ] && ok "⑤ tmux 변경(kill · set-option) 0" || bad "⑤ tmux 변경: $(cat "$T/tlog")"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
