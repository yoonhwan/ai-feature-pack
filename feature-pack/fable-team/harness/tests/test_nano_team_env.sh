#!/usr/bin/env bash
# test_nano_team_env.sh — 카드 nano-spawn-close-team-env: ①팀 env 자동 로드(close·spawn) ②spawn 에이전트별 기본 모델 ③--base · close base 정합 ④--shared-wt 닫기
# 임시 git 리포 + 가짜 tmux/tmuxc(PATH 앞) + 스크립트 사본(가짜 lint)만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-planner-master-claude#1 byz-planner-arch-claude#1 byz-harness-master-claude#1 byz-v65-master-claude#1   # r975 r4: 살아 있는 좌석 목록 대역
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

for f in ft-nano-close.sh ft-nano-spawn.sh ft-nano-evidence-check.sh; do bash -n "$SRC/$f" || bad "bash -n $f"; done
ok "bash -n 3종"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-spawn.sh" "$SRC/ft-proposal-gate.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-name-lint.sh" "$T/bin/"   # r975 r6: 역할 집합 출처
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-resource-gate.sh" "$SRC/ft_raised.py" "$SRC/ft_teamset.py" "$SRC/ft_spawn_queue.py" "$T/bin/"   # spawn 이 부르는 자원 문지기(R161)·상향 판정기 — 임시 bin 에도 있어야 한다
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin"/ft-all-stop.sh   # r626 DA⑥ r2: spawn 이 .fable-team 있으면 늘 전팀 정지 check — 사본 bin 에 없으면 REJECT · 이 시험 주제 밖이라 통과 스텁
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"   # 사건 원장 훅(PLAN-status-sheet §3-1) 의존 — 설치 폴더 밖 시험이라 FT_SHEET_ROOT 로 임시 루트
. "$HERE/lib/bin_source_deps.sh"; copy_source_deps "$SRC" "$T/bin" || bad "r686 사본 source 대상 채우기"   # r686: 고른 도구가 source 하는 같은 폴더 lib(r672 swap · research-seat …) — 새 lib 가 생겨도 따라간다
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-index-lint.sh"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # r455a: close 의 reap(r448) = 스텁(실기계 프로세스 0 · run 이 env -i 라 기본 경로 $HERE 에 둔다) · reap 자체는 test_seat_reap_left0.sh
printf '#!/usr/bin/env bash\necho called > "%s/cherry.called"\necho "REJECT cherry stub"; exit 1\n' "$T" > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*"\n' > "$T/fake/tmuxc"
chmod +x "$T/bin/"* "$T/fake/"*

# 임시 리포
REPO="$T/repo"; mkdir -p "$REPO"
mkdir -p "$REPO/design"; printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"   # R383: spawn·설치 게이트가 팀 폴더 명단을 읽는다
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
mkdir -p "$REPO/.fable-team/bin-planner" "$REPO/design/planner/indices/대기" "$REPO/design/planner/indices/진행" "$REPO/design/v65/indices/대기" "$T/comm/bodies"
cat > "$REPO/.fable-team/bin-planner/planner-env.sh" <<EOF
export FT_SEATS_JSON=$REPO/.fable-team/seats-planner.json
export FT_NANO_PREFIX=byz-planner-nano-
export FT_NANO_WT_PREFIX=planner-
export FT_NANO_LEDGER=$T/ledger.md
export FT_IMPL_MODEL='claude-sonnet-5-5[1m]'
EOF
echo '{"_master":"byz-planner-master-claude#1","byz-planner-master-claude#1":{"role":"master"}}' > "$REPO/.fable-team/seats-planner.json"; echo '{"_master":"byz-harness-master-claude#1","byz-harness-master-claude#1":{"role":"master"}}' > "$REPO/.fable-team/seats.json"   # r975: 회신 대상 = 명부 _master
: > "$T/ledger.md"   # R400 r3 ②: 원장은 «이미 있는» 파일만 쓴다(없으면 입구 REJECT · 첫 append 로 만들지 않는다)
echo card > "$REPO/design/planner/indices/대기/c.md"; echo card > "$REPO/design/v65/indices/대기/c.md"
echo seq > "$T/comm/bodies/1.txt"

# 자원 문지기(R161)는 이 시험의 대상이 아니라 통과로 고정한다 — env -i 라 문턱을 run 이 직접 넘긴다(머신 부하에 따라 RED/GREEN 이 바뀌지 않게 — R169).
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_TEAMSET=0 FT_RES_ROOT="$FT_RES_ROOT" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
: > "$T/panes"

echo "== close · 팀 env 자동 로드"
out="$(run bash "$T/bin/ft-nano-close.sh" 'byz-planner-nano-x#0')"
has "$out" "ENV team=planner prefix=byz-planner-nano- seats=$REPO/.fable-team/seats-planner.json" "close planner → 팀 env 로드"
out="$(run bash "$T/bin/ft-nano-close.sh" 'byz-zzz-nano-x#0')"
has "$out" "REJECT 팀 env 없음: $REPO/.fable-team/bin-zzz/zzz-env.sh" "close 없는 팀 → REJECT"
out="$(run bash "$T/bin/ft-nano-close.sh" 'ft-v65-temp-x#0')"
has "$out" "ENV team=v65 prefix=ft-v65-temp- seats=$REPO/.fable-team/seats.json" "close 옛 이름 → v65(규칙이 팀을 안다 · r655) — 접두는 그 좌석이 실제로 쓰는 접두"
out="$(run FT_NANO_PREFIX=byz-planner-nano- bash "$T/bin/ft-nano-close.sh" 'byz-planner-nano-x#0')"
hasnt "$out" "ENV team=" "close 접두 명시 → 자동 로드 안 함"; hasnt "$out" "팀 env 없음" "close 접두 명시 → env 파일 안 찾음"
out="$(run bash "$T/bin/ft-nano-close.sh" 'byz-harness-arch-claude#5')"
has "$out" "REJECT 나노 좌석 이름이 아니다(byz-harness-arch-claude#5)" "close 역할 좌석 → 이름 게이트 REJECT(r655: 나노 이름 규칙 밖)"

echo "== spawn · 팀 env · 기본 모델 · --base"
sp() { run bash "$T/bin/ft-nano-spawn.sh" "$@" --dry-run; }
out="$(sp design/planner/indices/대기/c.md)"
has "$out" "ENV team=planner prefix=byz-planner-nano-" "spawn planner 카드 → team=planner"
has "$out" "PLAN seat=byz-planner-nano-c#0 agent=claude model=claude-sonnet-5-5[1m]" "spawn 팀 env 의 FT_IMPL_MODEL 이 기본 모델에 반영"
out="$(sp design/v65/indices/대기/c.md)"
has "$out" "ENV team=v65 prefix=byz-v65-nano-" "spawn v65 카드 → 기본 접두 byz-v65-nano-(r655)"
has "$out" "PLAN seat=byz-v65-nano-c#0 agent=claude model=claude-sonnet-5-5[1m]" "spawn v65 PLAN 줄 — 이름 접두만 새 규칙(r655) · 모델 기본 불변(claude sonnet-5-5)"
out="$(sp design/v65/indices/대기/c.md --agent codex)"
has "$out" "agent=codex model=gpt-6-luna" "spawn codex 모델 미지정 → luna"
out="$(sp design/v65/indices/대기/c.md --agent cmd)"
has "$out" "agent=cmd model=deepseek/deepseek-v4-flash" "spawn cmd 모델 미지정 → deepseek"
out="$(sp design/v65/indices/대기/c.md --agent codex --model gpt-x)"
has "$out" "agent=codex model=gpt-x" "spawn --model 명시가 이긴다"
out="$(sp design/v65/indices/대기/c.md --agent opencode)"
has "$out" "agent=opencode model=opencode/deepseek-v4.1-flash-free" "spawn opencode 모델 미지정 → 기본 deepseek-v4.1-flash-free(r286)"
out="$(sp design/v65/indices/대기/c.md --base origin/main)"
has "$out" "base=origin/main" "spawn --base → PLAN base"
out="$(sp design/v65/indices/대기/c.md)"
has "$out" "base=$(git -C "$REPO" rev-parse --abbrev-ref HEAD) " "spawn --base 없음 → 현재 HEAD 브랜치"
out="$(sp design/v65/indices/대기/c.md --base no/such/ref)"
has "$out" "REJECT 기준 ref(--base) HEAD 조회 실패: no/such/ref" "spawn --base 없는 ref → REJECT"

echo "== close · --shared-wt"
SHARED="$REPO/.worktrees/shared"
GIT worktree add -q "$SHARED" -b planning
mkdir -p "$SHARED/out"; echo res > "$SHARED/out/result.md"
git -C "$SHARED" -c user.email=t@t -c user.name=t add out/result.md && git -C "$SHARED" -c user.email=t@t -c user.name=t commit -q -m "result"
SHA_OLD="$(git -C "$SHARED" rev-parse HEAD)"
git -C "$SHARED" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "other session moved HEAD"   # 공유 HEAD 는 증거 sha 보다 앞으로 간다
SHA_SIDE="$(git -C "$REPO" commit-tree "$(git -C "$REPO" rev-parse 'HEAD^{tree}')" -p HEAD -m side)"      # 공유 HEAD 의 조상이 아닌 커밋
SEAT='byz-planner-nano-s#0'; CARD="$REPO/design/planner/indices/진행/s.md"
setup() {  # setup <증거 sha> <cwd> — 명부·pane·카드를 리셋
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/s.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$2" > "$T/cwd"; : > "$T/tlog"; rm -f "$T/cherry.called"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$1" > "$CARD"
}
close() { run FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --recv 1 "$@"; }

setup "$SHA_OLD" "$SHARED"
out="$(close --result "$SHARED/out/result.md")"
has "$out" "REJECT" "--shared-wt 없이 공유 cwd 좌석 → 지금처럼 REJECT"; has "$out" "추측 금지" "  └ 사유 = 추측 금지(기존 fail-closed)"

GIT worktree add -q "$REPO/.worktrees/planner-s" -b nano/s   # planner 팀 좌석의 전용 워크트리 접두 = planner- (FT_NANO_WT_PREFIX)
setup "$SHA_OLD" "$SHARED"
out="$(close --shared-wt --result "$SHARED/out/result.md")"
has "$out" "전용 경로로 닫아라" "전용 워크트리 있는 좌석 + --shared-wt → REJECT(전용 경로로)"
GIT worktree remove --force "$REPO/.worktrees/planner-s"; GIT branch -q -D nano/s

GIT worktree add -q "$REPO/.worktrees/other" -b nano/other
setup "$SHA_OLD" "$REPO/.worktrees/other"
out="$(close --shared-wt --result "$SHARED/out/result.md")"
has "$out" "나노 브랜치(nano/other)" "공유 cwd 가 nano/* 브랜치 → REJECT"
GIT worktree remove --force "$REPO/.worktrees/other"; GIT branch -q -D nano/other

echo untracked > "$SHARED/out/new.md"
setup "$SHA_OLD" "$SHARED"
out="$(close --shared-wt --result "$SHARED/out/new.md")"
has "$out" "추적 중이 아니다" "result 경로 미추적 → REJECT"
rm -f "$SHARED/out/new.md"

echo changed >> "$SHARED/out/result.md"
setup "$SHA_OLD" "$SHARED"
out="$(close --shared-wt --result "$SHARED/out/result.md")"
has "$out" "미커밋 변경이 있다" "result 경로 미커밋 → REJECT"
git -C "$SHARED" checkout -q -- out/result.md

setup "$SHA_SIDE" "$SHARED"
out="$(close --shared-wt --result "$SHARED/out/result.md")"
has "$out" "조상이 아니다" "증거 sha 가 공유 HEAD 의 조상 아님 → REJECT"

echo noise > "$SHARED/unrelated-other-session.txt"   # 공유 워크트리 «다른» 파일 미커밋은 보지 않는다
setup "$SHA_OLD" "$SHARED"
out="$(close --shared-wt --result "$SHARED/out/result.md")"; rc=$?
has "$out" "CLOSED $SEAT" "다른 파일 미커밋만 + 증거 sha 조상 → 통과"
has "$out" "OK 증거 줄" "  └ 증거 줄 통과(조상 모드)"
has "$(cat "$T/tlog")" "kill-session" "  └ 세션 kill(표준승인 경로)"
[ ! -e "$T/cherry.called" ] && ok "  └ cherry 호출 0" || bad "cherry 호출됨"
[ ! -e "$T/wtclean" ] && ok "  └ wt-clean 계획 파일 0" || bad "wt-clean 계획 생성: $(ls "$T/wtclean")"
has "$(cat "$T/ledger.md")" "mode=shared-wt wt=$SHARED (정리 0 · 브랜치 0)" "  └ 원장 행에 mode=shared-wt"
[ -d "$SHARED" ] && [ -f "$SHARED/unrelated-other-session.txt" ] && git -C "$REPO" rev-parse --verify -q refs/heads/planning >/dev/null && ok "  └ 워크트리·파일·브랜치 그대로" || bad "공유 워크트리/브랜치 변경됨"

echo "== close · base 정합 (FT_NANO_FEAT 미설정 → 워크트리 info base)"
GIT branch -q basefeat
GIT worktree add -q "$REPO/.worktrees/v65-b" -b nano/b basefeat
printf '{"branch":"nano/b","base":"basefeat"}\n' > "$REPO/.worktrees/v65-b/.worktree-info.json"
printf '{"byz-planner-nano-b#0":{"role":"nano","index":"design/planner/indices/진행/b.md"}}\n' > "$REPO/.fable-team/seats-planner.json"
printf 'byz-planner-nano-b#0|%%1\n' > "$T/panes"; printf '%s' "$REPO/.worktrees/v65-b" > "$T/cwd"; echo '## 상태' > "$REPO/design/planner/indices/진행/b.md"
# 가짜 cherry 게이트가 받은 첫 인자(feat)를 기록한다
printf '#!/usr/bin/env bash\necho "$1" > "%s/cherry.feat"\necho "REJECT cherry stub"; exit 1\n' "$T" > "$T/bin/ft-nano-cherry-gate.sh"
out="$(run FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 bash "$T/bin/ft-nano-close.sh" 'byz-planner-nano-b#0' --recv 1 --result "$REPO/.fable-team/seats-planner.json")"
[ "$(cat "$T/cherry.feat" 2>/dev/null)" = "basefeat" ] && ok "FT_NANO_FEAT 미설정 → cherry base = info base(basefeat)" || bad "cherry base=$(cat "$T/cherry.feat" 2>/dev/null) ← ${out:0:300}"
out="$(run FT_NANO_FEAT=feat/explicit FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 bash "$T/bin/ft-nano-close.sh" 'byz-planner-nano-b#0' --recv 1 --result "$REPO/.fable-team/seats-planner.json")"
[ "$(cat "$T/cherry.feat" 2>/dev/null)" = "feat/explicit" ] && ok "FT_NANO_FEAT 명시 → 그 값이 이긴다" || bad "cherry base=$(cat "$T/cherry.feat" 2>/dev/null)"
GIT worktree remove --force "$REPO/.worktrees/v65-b"

echo "== close · 좌석 워크트리 접두 = FT_NANO_WT_PREFIX (세션 없음 ABSENT · cwd 없음 → ② 이름 규칙으로만 해석)"
mkdir -p "$REPO/.fable-team/bin-feature" "$REPO/design/feature/indices/진행"
cat > "$REPO/.fable-team/bin-feature/feature-env.sh" <<EOF
export FT_SEATS_JSON=$REPO/.fable-team/seats-feature.json
export FT_NANO_PREFIX=byz-feature-nano-
export FT_NANO_WT_PREFIX=feature-
export FT_NANO_LEDGER=$T/ledger.md
EOF
printf '{"byz-feature-nano-k#0":{"role":"nano","index":"design/feature/indices/진행/k.md"}}\n' > "$REPO/.fable-team/seats-feature.json"
echo '## 상태' > "$REPO/design/feature/indices/진행/k.md"; : > "$T/panes"
fclose() { run FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean2" bash "$T/bin/ft-nano-close.sh" 'byz-feature-nano-k#0' --recv 1 --result "$REPO/.fable-team/seats-feature.json"; }
GIT worktree add -q "$REPO/.worktrees/feature-k" -b nano/k
out="$(fclose)"
hasnt "$out" "⑥나노 워크트리" "feature 팀 · feature-k 워크트리 → ⑥ REJECT 아님(후보 1개로 해석)"
hasnt "$out" "후보도 0개" "  └ 0-후보 에러 없음"
has "$out" "⑥증거 줄 — 카드" "  └ 워크트리 해석을 지나 증거 줄 검사까지 도달(카드에 증거 줄 없음 = 이 시험의 기대 REJECT)"
GIT worktree remove --force "$REPO/.worktrees/feature-k"; GIT branch -q -D nano/k
GIT worktree add -q "$REPO/.worktrees/v65-k" -b nano/k
out="$(fclose)"
has "$out" "⑥나노 워크트리 없음: $REPO/.worktrees/feature-<key>[-rN]" "feature 팀 · 이름이 v65-k 면 0 후보(다른 팀 워크트리를 집지 않음) · 문구는 접두 반영"
GIT worktree remove --force "$REPO/.worktrees/v65-k"; GIT branch -q -D nano/k
GIT worktree add -q "$REPO/.worktrees/feature-k-r2" -b nano/k-r2
out="$(fclose)"
hasnt "$out" "⑥나노 워크트리" "feature 팀 · 재착수 feature-k-r2 → 해석됨"
has "$out" "⑥증거 줄 — 카드" "  └ 증거 줄 검사까지 도달"
GIT worktree remove --force "$REPO/.worktrees/feature-k-r2"; GIT branch -q -D nano/k-r2
out="$(run FT_NANO_WT_PREFIX='a.b' bash "$T/bin/ft-nano-close.sh" 'ft-v65-temp-k#0')"
has "$out" "REJECT FT_NANO_WT_PREFIX(a.b)" "접두에 정규식 문자 → REJECT(추측 0)"
printf '{"ft-v65-temp-k#0":{"role":"nano","index":"design/v65/indices/대기/c.md"}}\n' > "$REPO/.fable-team/seats.json"
# R400 r3: 기본 원장 해석(명단 = origin/main ref)은 이 시험 범위 밖 — 원장은 명시(워크트리 접두 해석만 본다)
GIT worktree add -q "$REPO/.worktrees/v65-k" -b nano/k
out="$(run FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean3" bash "$T/bin/ft-nano-close.sh" 'ft-v65-temp-k#0' --recv 1 --result "$REPO/.fable-team/seats.json")"
hasnt "$out" "⑥나노 워크트리" "env 없는 옛 좌석 · v65-k → 지금처럼 해석"
GIT worktree remove --force "$REPO/.worktrees/v65-k"; GIT branch -q -D nano/k
out="$(run FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 bash "$T/bin/ft-nano-close.sh" 'ft-v65-temp-k#0' --recv 1 --result "$REPO/.fable-team/seats.json")"
has "$out" "⑥나노 워크트리 없음: $REPO/.worktrees/v65-<key>[-rN]" "env 없는 옛 좌석 · 에러 문구 바이트 그대로(v65-<key>[-rN])"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
