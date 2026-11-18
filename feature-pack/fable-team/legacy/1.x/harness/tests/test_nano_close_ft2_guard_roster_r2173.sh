#!/usr/bin/env bash
# test_nano_close_ft2_guard_roster_r2173.sh — 카드 r2173: r2168 ft2 좌석 가림이 명부 그 좌석 행의 worktree 칸도 셋째 후보로 본다.
#   세션 없음 · --wt 없음인 ft2 좌석(명부 worktree = <데이터 루트>/.fable-team/teams/<팀>/worktrees/<폴더>)을 1.x 로 닫으려 하면
#   «FT2-SEAT …» 줄 1개(마지막 줄) + rc 5 · 명부 · 원장 · 원장 WT · tmux · 워크트리 · 가지 손 0.
# 반례 ①~⑩ (⑪ = 기존 시험 재실행 · 이 파일 밖). 기준판 = 아래 BASE 커밋의 ft-nano-close.sh(원본 대조 · 기준판 Red ① ② ③).
# 픽스처 = r2168 시험 꼴(임시 데이터 루트 리포 + 팩 꼴 리포 + 가짜 tmux + 키트 bin 임시 사본) · 실 명부 · 실 tmux · 실 우편함 0 · sleep 0.
# R2173_BIN=<bin 폴더> = 시험 대상 ft-nano-close.sh 가 있는 폴더(변이 사본 대조용 · 기본 = 키트 사본).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE=62973028e4ed03cab5b816f90593af366050755b   # 기준판(이 카드 직전 main)
KREL=feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── bin 두 벌: 새 판(키트 사본 또는 R2173_BIN) · 기준판(같은 사본에 ft-nano-close.sh 만 BASE 로)
bash "$HERE/lib/kit_bin_copy.sh" "$T/new" >/dev/null || bad "kit_bin_copy new"
[ -n "${R2173_BIN:-}" ] && cp "$R2173_BIN/ft-nano-close.sh" "$T/new/ft-nano-close.sh"
bash "$HERE/lib/kit_bin_copy.sh" "$T/base" >/dev/null || bad "kit_bin_copy base"
git -C "$HERE" show "$BASE:$KREL/ft-nano-close.sh" > "$T/base/ft-nano-close.sh" 2>/dev/null || bad "기준판 못 읽음($BASE)"
for b in new base; do printf '#!/bin/sh\necho "OK cherry stub"\n' > "$T/$b/ft-nano-cherry-gate.sh"; chmod +x "$T/$b/"*; done
bash -n "$T/new/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

# ── 가짜 tmux: list-panes = FAKE_PANES 내용(빈 값 rc 0 = 세션 없음 · FAKE_TMUX_RC≠0 = 조회 실패) · display-message = FAKE_CWD · 변경 동사 = FAKE_LOG
mkdir -p "$T/fake" "$T/home" "$T/comm/bodies" "$T/sheet/.fable-team/state" "$T/wtclean"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG.all"
case "$1" in
  list-panes|ls) [ "${FAKE_TMUX_RC:-0}" = 0 ] || { echo "error connecting to /tmp/fake (Operation not permitted)"; exit "$FAKE_TMUX_RC"; }; cat "$FAKE_PANES";;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  *) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/fake/tmux"
echo res > "$T/result.md"; echo seq > "$T/comm/bodies/1.txt"; : > "$T/panes"

# ── 데이터 루트 꼴 리포(R) · 팩 꼴 리포(P) · ft2 좌석 워크트리(W2) · 1.x 좌석 워크트리(W1) — r2168 픽스처 그대로
SEAT='byz-harness-nano-k#0'
R="$T/root"; P="$T/pack"; W2="$R/.fable-team/teams/t/worktrees/k@a1"; W1="$R/.worktrees/v65-k"; LWT="$R/.worktrees/ledger"
SEATS="$R/.fable-team/seats-harness.json"; LEDGER="$R/design/harness/NANO-LEDGER.md"
mkdir -p "$R/design/harness/indices/진행" "$R/.fable-team/bin-harness" "$P"
git -C "$R" init -q -b main; printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"; : > "$LEDGER"
GC "$R" add -A; GC "$R" commit -qm init; git -C "$R" update-ref refs/remotes/origin/main main
GC "$R" worktree add -q "$LWT" -b lw main; : > "$LWT/scratch.txt"          # 낡은 원장 WT = ref 보다 1 뒤 + 미커밋 1(②)
GC "$R" checkout -q -b ops; rm -rf "$R/design/harness/indices"
git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m init
GC "$P" worktree add -q "$W2" -b nano/r2168-k main
mkdir -p "$R/design/harness/indices/진행"
printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$W2" rev-parse HEAD)" > "$R/design/harness/indices/진행/k.md"
GC "$R" add design/harness/indices/진행/k.md; GC "$R" commit -qm card; git -C "$R" update-ref refs/remotes/origin/ops ops; GC "$R" checkout -q -f main
LOK="$R/.worktrees/ledger-ok"; GC "$R" worktree add -q --detach "$LOK" ops   # 기본 원장 WT = 최신
GC "$R" worktree add -q "$W1" -b nano/k main   # 1.x 이름 좌석 워크트리 — 있으면 기준판 ① 이 CLOSED-ABSENT 까지 간다(카드 ⓧ4 꼴)
mkdir -p "$W2/sub/dir" "$R/.fable-team/teams/t/runtime/x" "$R/.fable-team/teams/worktrees/k"
ln -s "$W2" "$T/link-w2"
TENV="$R/.fable-team/bin-harness/harness-env.sh"; printf 'export FT_SEATS_JSON=%s\n' "$SEATS" > "$TENV"
cp "$LEDGER" "$T/ledger.keep"

# 명부 = ROW 값으로 매 호출 새로 씀(기준판이 행을 지워도 다음 사례는 같은 입력) · ROW 꼴:
#   json:<worktree 칸 JSON 값> · omit(칸 없음) · raw:<명부 파일 전문> · missing(파일 없음)
put_seats() {
  case "$ROW" in
    missing) rm -f "$SEATS";;
    raw:*) printf '%s\n' "${ROW#raw:}" > "$SEATS";;
    omit) printf '{"%s":{"role":"stop-ready","agent":"pi","attempt":"a1","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS";;
    json:*) printf '{"%s":{"role":"stop-ready","agent":"pi","attempt":"a1","index":"design/harness/indices/진행/k.md","worktree":%s}}\n' "$SEAT" "${ROW#json:}" > "$SEATS";;
  esac
}
jstr() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
ROW="json:$(jstr "$W2")"

# run <bin 판> [env=값 …] -- [인자 …] → stdout 만(stderr = $T/err) · rc · 세션 없음(list-panes 빈 값) · --wt 없음이 기본
run() {
  local b="$1"; shift; local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; [ $# -gt 0 ] && shift
  put_seats; cp "$T/ledger.keep" "$LEDGER"
  ( cd "$R" && env -i HOME="$T/home" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
      FT_CRITICAL_OFF=1 FT_ROOTS_TSV="$T/none.tsv" FT_SEATS_JSON="$SEATS" FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/ops \
      FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER_WT="$LOK" \
      bash -c 'while [ "$1" != -- ]; do export "$1"; shift; done; shift; exec bash "$@"' _ "${envs[@]}" -- \
      "$T/$b/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>"$T/err" ); }
ft2_ok() {   # <이름> <출력> <rc> [워크트리] — G3: FT2-SEAT 줄 정확히 1개 = 마지막 줄 · rc 5 · REJECT/CLOSED/HELD/WAIT 줄 0
  local n last w="${4:-$W2}"; n="$(printf '%s\n' "$2" | grep -c '^FT2-SEAT ')"; last="$(printf '%s\n' "$2" | awk 'NF{l=$0} END{print l}')"
  [ "$3" = 5 ] && [ "$n" = 1 ] && case "$last" in "FT2-SEAT $SEAT — 1.x 닫기 대상 아님 · 닫는 길 = ft2 keeper"*"워크트리=$w") true;; *) false;; esac \
    && ! printf '%s\n' "$2" | grep -qE '^(REJECT|CLOSED|HELD|WAIT)' && ok "$1 FT2-SEAT 1줄(마지막) · rc 5" || bad "$1 rc=$3 FT2-SEAT=$n ← $(printf '%s\n' "$2" | tail -4 | cut -c1-300)"
}
red() {      # <이름> <기준판 출력> <rc> <기준판에 있어야 할 글> — 기준판 Red(가림 없음 = 1.x 판정이 돈다)
  case "$2" in *"$4"*) [ "$3" != 5 ] && ! printf '%s\n' "$2" | grep -q '^FT2-SEAT ' && ok "$1 기준판 Red rc=$3 «$4»" || bad "$1 기준판 rc=$3";; *) bad "$1 기준판에 «$4» 없음 ← $(printf '%s\n' "$2" | tail -4 | cut -c1-300)";; esac
}
norm() { printf '%s\n' "$1" | sed -E 's/^(STEP .*) \+[0-9]+s$/\1/'; }   # STEP 경과 초만 지움(실행마다 다름)
same() {     # <이름> [env …] -- [인자 …] — 새 판 = 기준판(stdout · rc) · stderr 도 같음
  local nm="$1"; shift; local o1 r1 o2 r2 e1 e2
  o1="$(run new "$@")"; r1=$?; e1="$(cat "$T/err")"; o2="$(run base "$@")"; r2=$?; e2="$(cat "$T/err")"
  o1="$(norm "${o1//$T\/new/BIN}")"; o2="$(norm "${o2//$T\/base/BIN}")"; e1="$(norm "${e1//$T\/new/BIN}")"; e2="$(norm "${e2//$T\/base/BIN}")"
  rm -rf "$T/wtclean"/* 2>/dev/null
  [ "$o1" = "$o2" ] && [ "$r1" = "$r2" ] && [ "$e1" = "$e2" ] && ! printf '%s\n' "$o1" | grep -q '^FT2-SEAT ' && ok "$nm 기준판과 같음(rc=$r1)" \
    || bad "$nm 새 rc=$r1 기준 rc=$r2 ← $(diff <(printf '%s\n' "$o1" "--- err" "$e1") <(printf '%s\n' "$o2" "--- err" "$e2") | head -8 | cut -c1-240)"
}
snap() { { cat "$SEATS" "$LEDGER"; git -C "$P" worktree list --porcelain; git -C "$P" branch -a; git -C "$R" worktree list --porcelain; git -C "$R" branch -a; git -C "$LWT" rev-parse HEAD; git -C "$LWT" status --porcelain; cat "$T/tlog" 2>/dev/null; } | shasum; }

put_seats; : > "$T/tlog"; S0="$(snap)"; h0="$(git -C "$LWT" rev-parse HEAD)"
echo "== ① 세션 없음 · --wt 없음 · 원장 WT 최신 · 명부 worktree = ft2 워크트리"
o1="$(run new)"; ft2_ok "①" "$o1" $?
echo "== ② ① + 원장 WT 뒤 1 · 미커밋 1"
o2="$(run new FT_NANO_LEDGER_WT="$LWT")"; ft2_ok "②" "$o2" $?
case "$o2" in *"원장 WT 낡음"*) bad "② «원장 WT 낡음» 줄이 나옴";; *) ok "② «원장 WT 낡음» 0줄";; esac
echo "== ③ ① + tmux 조회 실패(rc 1)"
o3="$(run new FAKE_TMUX_RC=1)"; ft2_ok "③" "$o3" $?
echo "== ⑨ ①②③ 뒤 명부 · 원장 · 원장 WT · worktree · 가지 · tmux 변경 동사 그대로"
[ "$S0" = "$(snap)" ] && ok "⑨ 앞뒤 지문 같음" || bad "⑨ 앞뒤 지문 다름"
[ "$(git -C "$LWT" rev-parse HEAD)" = "$h0" ] && ok "⑨ 원장 WT HEAD 그대로(ff 0)" || bad "⑨ 원장 WT HEAD 바뀜"
[ ! -s "$T/tlog" ] && ok "⑨ tmux 변경(kill · set-option) 0" || bad "⑨ tmux 변경: $(cat "$T/tlog")"
[ -z "$(ls -A "$T/wtclean")" ] && ok "⑨ 정리 계획 0" || bad "⑨ 정리 계획 생김"
echo "== ①②③ 기준판 Red"
o="$(run base)"; red "①" "$o" $? "CLOSED-ABSENT"
jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null 2>&1 && bad "① 기준판인데 명부 행 남음" || ok "① 기준판 = 명부 행 삭제"
o="$(run base FT_NANO_LEDGER_WT="$LWT")"; red "②" "$o" $? "원장 WT 낡음"
o="$(run base FAKE_TMUX_RC=1)"; rc=$?; [ "$rc" != 5 ] && ! printf '%s\n' "$o" | grep -q '^FT2-SEAT ' && ok "③ 기준판 Red rc=$rc(1.x 판정)" || bad "③ 기준판도 FT2-SEAT"
git -C "$LWT" reset -q --hard "$h0"; : > "$LWT/scratch.txt"; rm -rf "$T/wtclean"/*; : > "$T/tlog"
echo "== ④ 명부 worktree = W2 안 하위 폴더 · W2 를 가리키는 심링크 → 워크트리=W2"
ROW="json:$(jstr "$W2/sub/dir")"; o="$(run new)"; ft2_ok "④-a 하위 폴더" "$o" $?
ROW="json:$(jstr "$T/link-w2")"; o="$(run new)"; ft2_ok "④-b 심링크" "$o" $?
echo "== ⑤ 명부 worktree = 디스크에 없는 ft2 경로"
GONE="$R/.fable-team/teams/t/worktrees/gone@a1"; ROW="json:$(jstr "$GONE")"; o="$(run new)"; ft2_ok "⑤" "$o" $? "$GONE"
echo "== ⑥ 1.x 경로 · 칸 없음 · null · 숫자 · 목록 · 빈 글 → 기준판과 같음"
ROW="json:$(jstr "$W1")"; same "⑥-a 1.x 경로"
ROW=omit; same "⑥-b 칸 없음"
ROW=json:null; same "⑥-c null"
ROW=json:5; same "⑥-d 숫자"
ROW="json:[$(jstr "$W2")]"; same "⑥-e 목록"
ROW='json:""'; same "⑥-f 빈 글"
echo "== ⑦ 명부 파일 없음 · JSON 깨짐 · 좌석 행 없음 → 기준판과 같음"
ROW=missing; same "⑦-a 파일 없음"
ROW='raw:{"broken'; same "⑦-b JSON 깨짐"
ROW="raw:{\"byz-harness-nano-other#0\":{\"role\":\"nano\",\"worktree\":$(jstr "$W2")}}"; same "⑦-c 좌석 행 없음"
ROW="raw:{\"$SEAT\":$(jstr "$W2")}"; same "⑦-d 행이 객체 아님"
ROW="raw:[$(jstr "$W2")]"; same "⑦-e 명부가 목록"
echo "== ⑧ 경계: 폴더 자체 · runtime · 빈 팀 · 팀 없음 → 기준판과 같음"
ROW="json:$(jstr "$R/.fable-team/teams/t/worktrees")"; same "⑧-a worktrees 폴더 자체"
ROW="json:$(jstr "$R/.fable-team/teams/t/runtime/x")"; same "⑧-b runtime"
ROW="json:$(jstr "$R/.fable-team/teams//worktrees/k")"; same "⑧-c 빈 팀"
ROW="json:$(jstr "$R/.fable-team/teams/worktrees/k")"; same "⑧-d 팀 없음"
ROW="json:$(jstr "$W2")"

echo "== ⑩ wrap 경유(FT_CRITICAL_OFF 없이) · ② 입력 — 대역 mbox · 대역 ft-block-lib · critical 상태 임시"
for b in new base; do
  printf '#!/bin/sh\necho "mbox $*" >> %s/mbox.log\necho seq=7\n' "$T" > "$T/$b/mbox-fake.sh"
  printf 'ft_block() { echo "$*" >> %s/block.log; }\n' "$T" > "$T/$b/ft-block-lib.sh"
  printf '#!/bin/sh\necho "$*" >> %s/record.log\n' "$T" > "$T/$b/ft-nano-record.sh"; chmod +x "$T/$b/"*.sh
done
wrap() {  # <bin 판> — 그 판 ft-nano-close 를 ft-critical-notify --wrap 로 감싸 부름 · 세션 없음 · --wt 없음 · 낡은 원장 WT
  local b="$1"; rm -rf "$T/cstate" "$T/mbox.log" "$T/block.log" "$T/record.log"; put_seats; cp "$T/ledger.keep" "$LEDGER"; : > "$T/panes"
  ( cd "$R" && env -i HOME="$T/home" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
      FT_MBOX_DIR="$T/comm" FT_MBOX="$T/$b/mbox-fake.sh" FT_CRITICAL_STATE_DIR="$T/cstate" FT_ROOTS_TSV="$T/none.tsv" FT_SEATS_JSON="$SEATS" \
      FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" FT_CARD_REF=origin/ops FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER_WT="$LWT" \
      bash "$T/$b/ft-critical-notify.sh" --wrap ft-nano-close "$T/$b/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 >"$T/wout" 2>"$T/err" ); }
printf '{"_desk":"byz-harness-desk#0"}\n' > "$T/seats-planner.json"
cnt() { [ -f "$1" ] && grep -c . "$1" || echo 0; }
wrap new; rc=$?
[ "$rc" = 5 ] && grep -q '^FT2-SEAT ' "$T/wout" && ok "⑩ wrap 경유 rc 5 그대로 · FT2-SEAT" || bad "⑩ rc=$rc ← $(head -c 300 "$T/wout")"
[ "$(cnt "$T/mbox.log")" = 0 ] && ok "⑩ 대역 mbox 호출 0([크리티컬] · 닫기 거절 쪽지 0)" || bad "⑩ mbox: $(cat "$T/mbox.log")"
[ "$(cnt "$T/cstate/critical-pending.jsonl")" = 0 ] && ok "⑩ critical-pending 0줄" || bad "⑩ pending 있음"
[ "$(cnt "$T/record.log")" = 0 ] && ok "⑩ refused 기록 0" || bad "⑩ record: $(cat "$T/record.log")"
[ "$(cnt "$T/block.log")" = 0 ] && ok "⑩ 막힘 장부 raise · clear 0" || bad "⑩ block: $(cat "$T/block.log")"
wrap base; rc=$?
[ "$(cnt "$T/mbox.log")" -ge 1 ] && ! grep -q '^FT2-SEAT ' "$T/wout" && ok "⑩ 기준판 Red = [크리티컬] $(cnt "$T/mbox.log")통(rc=$rc)" || bad "⑩ 기준판 Red 아님 rc=$rc"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
