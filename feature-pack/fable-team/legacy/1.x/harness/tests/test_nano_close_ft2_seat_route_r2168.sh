#!/usr/bin/env bash
# test_nano_close_ft2_seat_route_r2168.sh — 카드 r2168: ft2 가 연 나노 좌석(워크트리 = <데이터 루트>/.fable-team/teams/<팀>/worktrees/<폴더>)을
#   1.x ft-nano-close 로 닫으려 하면 닫기 판정에 들어가지 않고 «FT2-SEAT … 닫는 길 = ft2 keeper …» 줄 1개(마지막 줄) + rc 5 로 끝난다.
#   감싼 도구(ft-critical-notify --wrap)는 그 종료에 [크리티컬] · refused · 막힘 장부 raise 를 하지 않는다.
# 반례 ①~⑩ · ⑭ · ⑮ (호출자 ⑫ ⑬ = test_nano_close_ft2_callers_r2168.sh). 기준판 = 아래 BASE 커밋의 4파일(원본 대조 · 기준판 Red).
# 픽스처 = 임시 데이터 루트 꼴 git 리포 1 + 팩 꼴 git 리포 1(그 worktree 를 teams/t/worktrees/k@a1 에) + 가짜 tmux(PATH 앞) + 키트 bin 임시 사본
#   · 실 명부 · 실 tmux · 실 우편함 · 실 워크트리 0 · sleep 0.
# R2168_BIN=<bin 폴더> = 시험 대상 bin(변이 사본 대조용 · 기본 = 키트 사본).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE=02fb965c1492bd7a6ae80dc43db87aee79764e2e   # 기준판(이 카드 직전 main)
KREL=feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── bin 두 벌: 새 판(키트 사본 또는 R2168_BIN) · 기준판(같은 사본에 4파일만 BASE 로)
bash "$HERE/lib/kit_bin_copy.sh" "$T/new" >/dev/null || bad "kit_bin_copy new"
[ -n "${R2168_BIN:-}" ] && for f in ft-nano-close.sh ft-critical-notify.sh ft_nano_record_auto.py ft_stall_scan.py; do cp "$R2168_BIN/$f" "$T/new/$f"; done
bash "$HERE/lib/kit_bin_copy.sh" "$T/base" >/dev/null || bad "kit_bin_copy base"
for f in ft-nano-close.sh ft-critical-notify.sh ft_nano_record_auto.py ft_stall_scan.py; do
  git -C "$HERE" show "$BASE:$KREL/$f" > "$T/base/$f" 2>/dev/null || bad "기준판 $f 못 읽음($BASE)"
done
for b in new base; do printf '#!/bin/sh\necho "OK cherry stub"\n' > "$T/$b/ft-nano-cherry-gate.sh"; chmod +x "$T/$b/"*; done
bash -n "$T/new/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

# ── 가짜 tmux: list-panes = FAKE_PANES 내용(비면 FAKE_TMUX_RC 로 실패) · display-message = FAKE_CWD · 변경 동사 = FAKE_LOG 기록
mkdir -p "$T/fake" "$T/home" "$T/comm/bodies" "$T/sheet/.fable-team/state" "$T/wtclean"
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

# ── 데이터 루트 꼴 리포(R) · 팩 꼴 리포(P) · ft2 좌석 워크트리(W2) · 1.x 좌석 워크트리(W1)
SEAT='byz-harness-nano-k#0'
R="$T/root"; P="$T/pack"; W2="$R/.fable-team/teams/t/worktrees/k@a1"; W1="$R/.worktrees/v65-k"; LWT="$R/.worktrees/ledger"
SEATS="$R/.fable-team/seats-harness.json"; LEDGER="$R/design/harness/NANO-LEDGER.md"
mkdir -p "$R/design/harness/indices/진행" "$R/.fable-team/bin-harness" "$P"
git -C "$R" init -q -b main; printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"; : > "$LEDGER"
GC "$R" add -A; GC "$R" commit -qm init; git -C "$R" update-ref refs/remotes/origin/main main
GC "$R" worktree add -q "$LWT" -b lw main; : > "$LWT/scratch.txt"          # 원장 WT = ref 보다 1 뒤 + 미커밋 1(③)
GC "$R" checkout -q -b ops; rm -rf "$R/design/harness/indices"
git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m init
GC "$P" worktree add -q "$W2" -b nano/r2168-k main
mkdir -p "$R/design/harness/indices/진행"   # 카드 = ref(origin/ops) 에만(디스크 사본 0 → 기준판은 원장 WT 신선도까지 간다)
printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$W2" rev-parse HEAD)" > "$R/design/harness/indices/진행/k.md"
GC "$R" add design/harness/indices/진행/k.md; GC "$R" commit -qm card; git -C "$R" update-ref refs/remotes/origin/ops ops; GC "$R" checkout -q -f main
LOK="$R/.worktrees/ledger-ok"; GC "$R" worktree add -q --detach "$LOK" ops   # 기본 원장 WT = 최신(카드 사본 있음) — ③ 만 낡은 원장 WT
mk_w1() { GC "$R" worktree add -q "$W1" -b nano/k main; }   # 1.x 좌석 워크트리 — ①~③ 기준판 Red 뒤에 만든다(있으면 좌석 이름 후보 1개가 된다)
mkdir -p "$W2/sub/dir" "$R/.fable-team/teams/t/runtime/x" "$R/.fable-team/teams/worktrees/k"
ln -s "$W2" "$T/link-w2"; ln -s "$R" "$T/link-root"
printf '{"%s":{"role":"nano","agent":"pi","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
TENV="$R/.fable-team/bin-harness/harness-env.sh"; printf 'export FT_SEATS_JSON=%s\n' "$SEATS" > "$TENV"

# run <bin 판> <pane cwd|-> [env=값 …] -- [인자 …] → stdout 만(stderr = $T/err) · rc
run() {
  local b="$1" pc="$2"; shift 2; local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; [ $# -gt 0 ] && shift
  if [ "$pc" = - ]; then : > "$T/panes"; else printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$pc" > "$T/cwd"; fi
  ( cd "${RUN_CWD:-$R}" && env -i HOME="$T/home" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
      FT_CRITICAL_OFF=1 FT_ROOTS_TSV="$T/none.tsv" FT_SEATS_JSON="$SEATS" FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/ops \
      FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER_WT="$LOK" "${envs[@]}" \
      bash "$T/$b/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>"$T/err" ); }
ft2_ok() {   # <이름> <출력> <rc> — T3: FT2-SEAT 줄 정확히 1개 = 마지막 줄 · rc 5 · REJECT/CLOSED/HELD/WAIT 줄 0
  local n last; n="$(printf '%s\n' "$2" | grep -c '^FT2-SEAT ')"; last="$(printf '%s\n' "$2" | awk 'NF{l=$0} END{print l}')"
  [ "$3" = 5 ] && [ "$n" = 1 ] && case "$last" in "FT2-SEAT $SEAT — 1.x 닫기 대상 아님 · 닫는 길 = ft2 keeper"*"워크트리=$W2") true;; *) false;; esac \
    && ! printf '%s\n' "$2" | grep -qE '^(REJECT|CLOSED|HELD|WAIT)' && ok "$1 FT2-SEAT 1줄(마지막) · rc 5" || bad "$1 rc=$3 FT2-SEAT=$n ← ${2:0:500}"
}
red() {      # <이름> <기준판 출력> <rc> <기준판에 있어야 할 글> — 기준판 Red(가림 없음 = 다른 거절)
  case "$2" in *"$4"*) [ "$3" != 5 ] && ! printf '%s\n' "$2" | grep -q '^FT2-SEAT ' && ok "$1 기준판 Red rc=$3 «$4»" || bad "$1 기준판 rc=$3";; *) bad "$1 기준판에 «$4» 없음 ← ${2:0:400}";; esac
}
same() {     # <이름> <pane cwd|-> [env …] -- [인자 …] — 새 판 = 기준판(stdout · rc)
  local nm="$1"; shift; local o1 r1 o2 r2
  o1="$(run new "$@")"; r1=$?; o2="$(run base "$@")"; r2=$?
  o1="${o1//$T\/new/BIN}"; o2="${o2//$T\/base/BIN}"
  [ "$o1" = "$o2" ] && [ "$r1" = "$r2" ] && ! printf '%s\n' "$o1" | grep -q '^FT2-SEAT ' && ok "$nm 기준판과 같음(rc=$r1)" || bad "$nm 새 rc=$r1 기준 rc=$r2 ← 새 ${o1:0:300} ‖ 기준 ${o2:0:300}"
}
snap() { { cat "$SEATS" "$LEDGER"; git -C "$P" worktree list --porcelain; git -C "$P" branch -a; git -C "$R" worktree list --porcelain; git -C "$R" branch -a; git -C "$LWT" rev-parse HEAD; git -C "$LWT" status --porcelain; cat "$T/tlog" 2>/dev/null; } | shasum; }

: > "$T/tlog"; S0="$(snap)"; h0="$(git -C "$LWT" rev-parse HEAD)"
echo "== ① pane cwd = ft2 워크트리 · --wt 없음"
o1="$(run new "$W2")"; ft2_ok "①" "$o1" $?
echo "== ② --wt <ft2 워크트리> --branch <그 가지> · 세션 없음"
o2="$(run new - -- --wt "$W2" --branch nano/r2168-k)"; ft2_ok "②" "$o2" $?
echo "== ③ 원장 WT 가 ref 보다 뒤 + 미커밋 1"
o3="$(run new "$W2" FT_NANO_LEDGER_WT="$LWT")"; ft2_ok "③" "$o3" $?
case "$o3" in *"원장 WT 낡음"*) bad "③ «원장 WT 낡음» 줄이 나옴";; *) ok "③ «원장 WT 낡음» 0줄";; esac
[ "$(git -C "$LWT" rev-parse HEAD)" = "$h0" ] && ok "③ 원장 WT HEAD 그대로(ff 0)" || bad "③ 원장 WT HEAD 바뀜"
S3="$(snap)"
echo "== ①②③ 기준판 Red"
o="$(run base "$W2")"; red "①" "$o" $? "후보도 0개"
o="$(run base - -- --wt "$W2" --branch nano/r2168-k)"; red "②" "$o" $? ".worktrees/ 아래 워크트리가 아니다"
o="$(run base "$W2" FT_NANO_LEDGER_WT="$LWT")"; red "③" "$o" $? "원장 WT 낡음"
case "$o" in *"미커밋 1"*) ok "③ 기준판 «미커밋 1»";; *) bad "③ 기준판 «미커밋 1» 없음";; esac
git -C "$LWT" reset -q --hard "$h0"; : > "$LWT/scratch.txt"
mk_w1
echo "== ④ pane cwd = ft2 워크트리 안 하위 폴더"
o="$(run new "$W2/sub/dir")"; ft2_ok "④" "$o" $?
echo "== ⑤ 경계: 폴더 자체 · runtime · 빈 팀 → ft2 아님 = 기준판과 같음"
same "⑤-a" "$R/.fable-team/teams/t/worktrees"
same "⑤-b" "$R/.fable-team/teams/t/runtime/x"
same "⑤-c" "$R/.fable-team/teams//worktrees/k"
echo "== ⑥ 심링크 pane cwd → 실제 경로가 ft2"
o="$(run new "$T/link-w2")"; ft2_ok "⑥" "$o" $?
echo "== ⑦ ①~③ 뒤 명부 · 원장 · worktree · 가지 · tmux 변경 동사 그대로"
[ "$S0" = "$S3" ] && ok "⑦ 앞뒤 지문 같음" || bad "⑦ 앞뒤 지문 다름"
[ ! -s "$T/tlog" ] && ok "⑦ tmux 변경(kill · set-option) 0" || bad "⑦ tmux 변경: $(cat "$T/tlog")"
[ -z "$(ls -A "$T/wtclean")" ] && ok "⑦ 정리 계획 0" || bad "⑦ 정리 계획 생김"
echo "== ⑨ --wt 없음 · tmux 조회 실패(rc 1) → 기준판과 같음"
same "⑨" - FAKE_TMUX_ERR="error connecting to /tmp/x (Operation not permitted)"
echo "== ⑩ 1.x 좌석(워크트리 $R/.worktrees/v65-k) → 기준판과 같음"
same "⑩" "$W1"
same "⑩-wt" "$W1" -- --wt "$W1" --branch nano/k
echo "== ⑭ 섞인 입력"
o="$(run new "$W2" -- --wt "$W1" --branch nano/k)"; ft2_ok "⑭-a --wt=1.x · pane=ft2" "$o" $?
o="$(run new "$W1" -- --wt "$W2" --branch nano/r2168-k)"; ft2_ok "⑭-b --wt=ft2 · pane=1.x" "$o" $?
o="$(run new "$W2" FT_ROOT="$T/link-root")"; ft2_ok "⑭-c 데이터 루트가 심링크 경로" "$o" $?
echo "== ⑮ 접두 출력 · 팀 env"
for pv in "" "FT_NANO_PREFIX=byz-harness-nano-"; do
  o1="$(run new "$W2" FT_NANO_PREFIX= $pv)"; r1=$?; o2="$(run base "$W2" FT_NANO_PREFIX= $pv)"
  ft2_ok "⑮ ${pv:-접두 없음}" "$o1" "$r1"
  head1="$(printf '%s\n' "$o1" | sed '$d')"; n1="$(printf '%s\n' "$head1" | grep -c .)"
  o2="${o2//$T\/base/$T/new}"; [ "$head1" = "$(printf '%s\n' "$o2" | head -n "$n1")" ] && ok "⑮ ${pv:-접두 없음} 앞 ${n1}줄 = 기준판 앞머리" || bad "⑮ 앞 줄 다름 ← ${head1:0:300}"
  case "$pv" in "") printf '%s\n' "$head1" | grep -q '^ENV team=harness' && ok "⑮ ENV 줄 있음" || bad "⑮ ENV 줄 없음";;
    *) printf '%s\n' "$head1" | grep -q '^ENV ' && bad "⑮ 접두 있는데 ENV 줄" || ok "⑮ 접두 있음 = ENV 줄 0";; esac
done
mv "$TENV" "$TENV.off"
o="$(run new "$W2" FT_NANO_PREFIX=)"; r1=$?; o2="$(run base "$W2" FT_NANO_PREFIX=)"; r2=$?
[ "$r1" = 1 ] && [ "$o" = "$o2" ] && [ "$r2" = 1 ] && case "$o" in *"REJECT 팀 env 없음"*) true;; *) false;; esac && ! printf '%s\n' "$o" | grep -q '^FT2-SEAT' \
  && ok "⑮ 팀 env 없음 = 기준판 REJECT rc 1 · FT2-SEAT 0" || bad "⑮ 팀 env 없음 rc=$r1/$r2 ← ${o:0:300}"
mv "$TENV.off" "$TENV"

echo "== ⑧ wrap 경유(FT_CRITICAL_OFF 없이) — 대역 mbox · 대역 ft-block-lib · critical 상태 임시"
for b in new base; do
  printf '#!/bin/sh\necho "mbox $*" >> %s/mbox.log\necho seq=7\n' "$T" > "$T/$b/mbox-fake.sh"
  printf 'ft_block() { echo "$*" >> %s/block.log; }\n' "$T" > "$T/$b/ft-block-lib.sh"
  printf '#!/bin/sh\necho "$*" >> %s/record.log\n' "$T" > "$T/$b/ft-nano-record.sh"; chmod +x "$T/$b/"*.sh
done
printf '{"_desk":"byz-harness-desk#0"}\n' > "$T/seats-planner.json"
wrap() {  # <bin 판> <스크립트|-> [인자 …] — - = 그 판 ft-nano-close 를 스스로 감싸게 부름
  local b="$1" s="$2"; shift 2; rm -rf "$T/cstate" "$T/mbox.log" "$T/block.log" "$T/record.log"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$W2" > "$T/cwd"
  ( cd "$R" && env -i HOME="$T/home" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
      FT_MBOX_DIR="$T/comm" FT_MBOX="$T/$b/mbox-fake.sh" FT_CRITICAL_STATE_DIR="$T/cstate" FT_ROOTS_TSV="$T/none.tsv" FT_SEATS_JSON="$SEATS" \
      FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/ops FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER_WT="$LOK" \
      bash $( [ "$s" = - ] && echo "$T/$b/ft-nano-close.sh" || echo "$T/$b/ft-critical-notify.sh --wrap ft-nano-close $s" ) "$SEAT" "$@" >"$T/wout" 2>"$T/err" ); }
cnt() { [ -f "$1" ] && grep -c . "$1" || echo 0; }
wrap new - --result "$T/result.md" --recv 1; rc=$?
[ "$rc" = 5 ] && grep -q '^FT2-SEAT ' "$T/wout" && ok "⑧ wrap 경유 rc 5 그대로 · FT2-SEAT" || bad "⑧ rc=$rc ← $(head -c 300 "$T/wout")"
[ "$(cnt "$T/mbox.log")" = 0 ] && ok "⑧ 대역 mbox 호출 0" || bad "⑧ mbox: $(cat "$T/mbox.log")"
[ "$(cnt "$T/cstate/critical-pending.jsonl")" = 0 ] && ok "⑧ critical-pending 0줄" || bad "⑧ pending 있음"
[ "$(cnt "$T/record.log")" = 0 ] && ok "⑧ refused 기록 0" || bad "⑧ record: $(cat "$T/record.log")"
[ "$(cnt "$T/block.log")" = 0 ] && ok "⑧ ft_block raise · clear 0" || bad "⑧ block: $(cat "$T/block.log")"
wrap base - --result "$T/result.md" --recv 1; rc=$?
[ "$rc" != 5 ] || grep -q '^FT2-SEAT ' "$T/wout" || [ "$(cnt "$T/mbox.log")" -ge 1 ] || bad "⑧ 기준판도 조용함"
[ "$(cnt "$T/mbox.log")" -ge 1 ] && ok "⑧ 기준판 Red = [크리티컬] $(cnt "$T/mbox.log")통(rc=$rc)" || bad "⑧ 기준판 Red 아님 rc=$rc"
# 원본 대조 2건(같은 틀 · 새 판): 1.x 거절 rc 1 → [크리티컬] 1통 · «WAIT …» rc 3 → raise 1 · 표식 없는 rc 5 → raise 1(T5 · T7)
printf '#!/bin/sh\necho "REJECT %s 닫지 않음:"\necho "  - ⑥카드 세트 불일치"\nexit 1\n' "$SEAT" > "$T/rej.sh"
printf '#!/bin/sh\necho "WAIT %s 계보 세션 살아 있음"\nexit 3\n' "$SEAT" > "$T/wait.sh"
printf '#!/bin/sh\necho "INFO x"\necho "어딘가 FT2-SEAT 아님"\nexit 5\n' > "$T/rc5.sh"
wrap new "$T/rej.sh"; rc=$?; [ "$rc" = 1 ] && [ "$(cnt "$T/mbox.log")" = 1 ] && ok "⑧ 대조 rc 1 거절 = [크리티컬] 1통" || bad "⑧ 대조 rc 1 rc=$rc mbox=$(cnt "$T/mbox.log")"
wrap new "$T/wait.sh"; rc=$?; [ "$rc" = 3 ] && [ "$(grep -c '^raise ' "$T/block.log" 2>/dev/null)" = 1 ] && ok "⑧ 대조 WAIT rc 3 = raise 1" || bad "⑧ 대조 WAIT rc=$rc block=$(cat "$T/block.log" 2>/dev/null)"
wrap new "$T/rc5.sh"; rc=$?; [ "$rc" = 5 ] && [ "$(grep -c '^raise ' "$T/block.log" 2>/dev/null)" = 1 ] && ok "⑧ 대조 표식 없는 rc 5 = raise 1(기준판 같음)" || bad "⑧ 대조 표식 없는 rc 5 rc=$rc block=$(cat "$T/block.log" 2>/dev/null)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
