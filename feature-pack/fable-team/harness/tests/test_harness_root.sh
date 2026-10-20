#!/usr/bin/env bash
# test_harness_root.sh — r385b: 데이터 루트 해석기 2종(ft-harness-root.sh ft_repo_root · ft_data_root) + 소비자 도구.
#   ⓖ 새 설치본(임시 HOME/.claude/fable-team/live/<ver>/bin · git 밖)에서 cwd=git 밖 · env 없음 → 도구 ERROR rc≠0 + 임시 HOME 밑 새 파일 0
#   ⓗ cwd=픽스처 리포 워크트리(.fable-team/LIVE_ROOT 있음) → ft_repo_root = 리포 공용 루트 · ft_data_root = LIVE_ROOT 값
#   ⓘ env 명시(FT_ROOT·FT_RES_ROOT) → 그 값 · ⓙ 옛 설치 꼴(<리포>/.fable-team/bin) → 옛 식 값(회귀 0) · ⓚ LIVE_ROOT 값 오류 → ERROR
#   ⓛ 새 설치본 drift-check(--repo 생략) = 하네스 코드 루트(FT_HARNESS_ROOT)의 키트로 대조.
# mktemp 만 쓴다 — 실 HOME·실 리포 상태·쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HROOT="$(cd -- "$HERE/.." && pwd -P)"
KBIN="$HROOT/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «$1» 기대 «$2»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
unset FT_ROOT FT_RES_ROOT FT_SECRET_SCAN_ROOT FT_HARNESS_ROOT FT_AUTONOMY_STATE_DIR

# 새 설치본 = 키트 bin 통째 복사(git 밖)
H="$T/home"; LB="$H/.claude/fable-team/live/9.9.9/bin"; mkdir -p "$LB"; cp -p "$KBIN"/* "$LB/" 2>/dev/null
[ -f "$LB/ft-harness-root.sh" ] && ok "설치본에 해석기 있음" || bad "설치본에 해석기 없음"
NOGIT="$T/nogit"; mkdir -p "$NOGIT"
printf '#!/bin/sh\necho "$@" >> "%s/mbox.log"\n' "$T" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"
snap() { (cd "$H" && find . -type f | LC_ALL=C sort); }
BEFORE="$(snap)"

# ── ⓖ 새 설치본 · cwd git 밖 · env 없음 → ERROR rc≠0 + 쓰기 0 ──
run() { (cd "$NOGIT" && env HOME="$H" FT_MBOX_SH="$T/mbox.sh" FT_RES_WATCH_SH="$T/noop.sh" FT_SCRATCH_REPO_SH="$T/noop.sh" FT_DOCKER_REAP_SH="$T/noop.sh" \
  FT_HOLD_GATE="$T/noop.sh" bash "$LB/$1" "${@:2}" 2>&1); }
for c in "ft-spawn-hold.sh status" "ft-disk-alarm.sh" "ft-autonomy.sh status"; do
  # shellcheck disable=SC2086
  out="$(run $c)"; rc=$?
  [ "$rc" != 0 ] && ok "ⓖ $c → rc=$rc(≠0)" || bad "ⓖ $c → rc=0 (조용히 통과)"
  has "$out" "ERROR" "ⓖ $c → ERROR 줄"
done
eq "$(snap)" "$BEFORE" "ⓖ 임시 HOME 밑 새 파일 0(~/.claude 로 안 풀림)"
[ ! -e "$H/.claude/fable-team/live/9.9.9/.fable-team" ] && ok "ⓖ live/<ver>/.fable-team 생성 0" || bad "ⓖ live 밑에 .fable-team 생김"

# ── 픽스처 리포: main + 워크트리 · LIVE_ROOT = 별도 라이브 루트 ──
R="$T/repo"; L="$T/liveroot"; mkdir -p "$R/.fable-team" "$L/.fable-team/state"
git -C "$R" init -q -b main && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
git -C "$R" worktree add -q "$T/wt" -b wt 2>/dev/null
printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"
res() { (cd "$1" && env -u FT_ROOT HOME="$H" bash -c '. "$1/ft-harness-root.sh"; '"$2"' "$1"' _ "$3" 2>&1); }

# ⓗ cwd = 워크트리 → 공용 루트 · LIVE_ROOT
eq "$(res "$T/wt" ft_repo_root "$LB")" "$R" "ⓗ ft_repo_root(cwd=워크트리) = 리포 공용 루트"
eq "$(res "$T/wt" ft_data_root "$LB")" "$L" "ⓗ ft_data_root(cwd=워크트리) = LIVE_ROOT 값"
eq "$(res "$R" ft_data_root "$LB")" "$L" "ⓗ ft_data_root(cwd=메인) = LIVE_ROOT 값"
out="$(res "$NOGIT" ft_repo_root "$LB")"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR" "ⓗ ft_repo_root(cwd git 밖) → ERROR rc≠0" || bad "ⓗ ft_repo_root git 밖 rc=$rc «$out»"
out="$(res "$NOGIT" ft_data_root "$LB")"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR" "ⓗ ft_data_root(cwd git 밖) → ERROR rc≠0" || bad "ⓗ ft_data_root git 밖 rc=$rc «$out»"
# 공용 루트에 .fable-team/ 없는 리포 → ft_repo_root ERROR
R2="$T/plain"; git init -q "$R2"; out="$(res "$R2" ft_repo_root "$LB")"; rc=$?
[ "$rc" != 0 ] && ok "ⓗ .fable-team/ 없는 리포 → ft_repo_root ERROR" || bad "ⓗ .fable-team/ 없는 리포인데 «$out»"

# 도구 수준: cwd=워크트리 → 리포 루트 묶음은 메인 state · 라이브 루트 묶음은 LIVE_ROOT state
out="$(cd "$T/wt" && env HOME="$H" FT_MBOX_SH="$T/mbox.sh" FT_HOLD_GATE="$T/noop.sh" bash "$LB/ft-spawn-hold.sh" status 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ⓗ ft-spawn-hold status(cwd=워크트리) rc0 — 루트 풀림" || bad "ⓗ spawn-hold status rc=$rc «${out:0:200}»"
out="$(cd "$T/wt" && env HOME="$H" bash "$LB/ft-autonomy.sh" status 2>&1)"; rc=$?
case "$out" in *"라이브 루트를 못 풂"*) bad "ⓗ ft-autonomy status 가 루트를 못 풂 «${out:0:200}»";; *) ok "ⓗ ft-autonomy status(cwd=워크트리) 루트 풀림 rc=$rc";; esac
[ ! -e "$R/.fable-team/state/autonomy.json" ] && ok "ⓗ 자율 상태가 메인 리포로 새지 않음" || bad "ⓗ 메인 리포에 autonomy.json 생김"

# ── ⓘ env 명시 → 그 값 ──
eq "$(cd "$NOGIT" && FT_ROOT="$T/x" bash -c '. "$1/ft-harness-root.sh"; ft_data_root "$1"' _ "$LB")" "$T/x" "ⓘ FT_ROOT → 그 값(cwd 무관)"
out="$(cd "$NOGIT" && env HOME="$H" FT_RES_ROOT="$R" FT_MBOX_SH="$T/mbox.sh" FT_HOLD_GATE="$T/noop.sh" bash "$LB/ft-spawn-hold.sh" status 2>&1)"; rc=$?
eq "$rc" 0 "ⓘ FT_RES_ROOT 명시 → spawn-hold status rc0(cwd git 밖이어도)"

# ── ⓙ 옛 설치 꼴(<리포>/.fable-team/bin) → 옛 식 값 ──
OB="$R/.fable-team/bin"; mkdir -p "$OB"; cp -p "$KBIN/ft-harness-root.sh" "$OB/"
rm -f "$R/.fable-team/LIVE_ROOT"
eq "$(res "$NOGIT" ft_repo_root "$OB")" "$R" "ⓙ 옛 꼴 · cwd git 밖 → ft_repo_root = git -C HERE 공용 루트"
eq "$(res "$NOGIT" ft_data_root "$OB")" "$R" "ⓙ 옛 꼴 · cwd git 밖 · LIVE_ROOT 없음 → ft_data_root = HERE/../.."
NB="$T/nongit-root/.fable-team/bin"; mkdir -p "$NB"; cp -p "$KBIN/ft-harness-root.sh" "$NB/"
eq "$(res "$NOGIT" ft_repo_root "$NB")" "$T/nongit-root" "ⓙ 옛 꼴 · git 밖 설치 → ft_repo_root = HERE/../..(옛 fallback 그대로)"

# ── ⓚ LIVE_ROOT 값 오류 → ERROR ──
printf 'relative/path\n' > "$R/.fable-team/LIVE_ROOT"
out="$(res "$T/wt" ft_data_root "$LB")"; rc=$?; [ "$rc" != 0 ] && has "$out" "LIVE_ROOT 가 절대경로 폴더가 아님" "ⓚ LIVE_ROOT 상대경로 → ERROR" || bad "ⓚ rc=$rc «$out»"
rm -f "$R/.fable-team/LIVE_ROOT"

# ── ⓛ 새 설치본 drift-check · --repo 생략 → 하네스 코드 루트(팩)의 키트(HEAD)와 대조 ──
cp -p "$KBIN"/* "$LB/" 2>/dev/null
out="$(cd "$NOGIT" && FT_HARNESS_ROOT="$HROOT" bash "$LB/ft-live-bin-drift-check.sh" --bin "$LB" --ref HEAD 2>&1)"; rc=$?
case "$rc" in 0|1) has "$out" "ref=HEAD@" "ⓛ 새 설치본 drift-check(--repo 생략) 키트 트리를 풂 rc=$rc";; *) bad "ⓛ drift-check rc=$rc «${out:0:300}»";; esac
out="$(cd "$NOGIT" && bash "$LB/ft-live-bin-drift-check.sh" --bin "$LB" 2>&1)"; rc=$?
eq "$rc" 3 "ⓛ 하네스 루트 못 풂(env·HARNESS_ROOT 없음) → ERROR rc3"
for f in ft-nano-spawn.sh ft-nano-close.sh ft-tick.sh; do
  grep -qF '*/fable-team/live/*/bin' "$KBIN/$f" && ok "ⓛ $f 드리프트 입구가 새 설치 꼴 인정" || bad "ⓛ $f 새 설치 꼴 패턴 없음"
done

# ══ r459 자리 규칙 3줄(코드 = LIVE_BIN · 데이터 = 공용 루트 · 정본 = ref origin/main) ══
# ── ⓐ ft_comm_dir: FT_MBOX_DIR → FT_ROOT → 옛 설치 꼴 공용 루트 → cwd 공용 루트 · LIVE_ROOT 는 읽지 않는다 ──
mkdir -p "$L/.fable-team/comm"; printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"
out="$(res "$T/wt" ft_comm_dir "$LB")"; rc=$?
[ "$rc" != 0 ] && has "$out" "ERROR comm 폴더 없음: $R/.fable-team/comm" "ⓐ LIVE_ROOT 에만 comm · 공용 루트 comm 없음 → ERROR rc≠0(LIVE_ROOT 후퇴 0)" || bad "ⓐ rc=$rc «$out»"
mkdir -p "$R/.fable-team/comm"
eq "$(res "$T/wt" ft_comm_dir "$LB")" "$R/.fable-team/comm" "ⓐ cwd=워크트리 · LIVE_ROOT 있음 → 공용 루트 comm"
eq "$(res "$R" ft_comm_dir "$LB")" "$R/.fable-team/comm" "ⓐ cwd=메인 → 공용 루트 comm"
mkdir -p "$T/mbx" "$T/froot/.fable-team/comm"
eq "$(cd "$T/wt" && FT_MBOX_DIR="$T/mbx" FT_ROOT="$T/froot" bash -c '. "$1/ft-harness-root.sh"; ft_comm_dir "$1"' _ "$LB")" "$T/mbx" "ⓐ FT_MBOX_DIR 이 1순위"
eq "$(cd "$NOGIT" && FT_ROOT="$T/froot" bash -c '. "$1/ft-harness-root.sh"; ft_comm_dir "$1"' _ "$LB")" "$T/froot/.fable-team/comm" "ⓐ FT_ROOT → <FT_ROOT>/.fable-team/comm"
eq "$(res "$NOGIT" ft_comm_dir "$OB")" "$R/.fable-team/comm" "ⓐ 옛 설치 꼴 · cwd git 밖 → git -C 폴더 공용 루트 comm"
out="$(res "$NOGIT" ft_comm_dir "$LB")"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR comm 폴더를 못 풂" "ⓐ 설치본 · cwd git 밖 · env 0 → ERROR" || bad "ⓐ git 밖 rc=$rc «$out»"
rm -f "$R/.fable-team/LIVE_ROOT"

# ── ⓑ 옛 통째 사본이 shim 폴더에서 돌면 exit 3 (상세 = test_tick_shim_guard.sh) ──
SB="$T/shimbin"; mkdir -p "$SB"; cp -p "$KBIN/ft-tick.sh" "$SB/"; printf '#!/usr/bin/env bash\n# ft-root-bin-shim: ft_raised.py → LIVE_BIN\n' > "$SB/ft_raised.py"
out="$(cd "$T/wt" && bash "$SB/ft-tick.sh" --once --dry-run 2>&1)"; rc=$?
eq "$rc" 3 "ⓑ shim 폴더의 ft-tick.sh → exit 3"; has "$out" "ERROR shim 폴더에서 실행" "ⓑ ERROR shim 폴더 줄"

# ── ⓒ ft_team_doc_ref: 명단 = ref · 실재 1 → 그 경로 · 실재 0 → ref 본문 임시 파일 · 2+·ref 없음 = ERROR ──
D="$T/docrepo"; mkdir -p "$D/design/teams/v65/20260912" "$D/.fable-team/comm"; git -C "$D" init -q -b main
printf '| 팀 | 폴더 |\n|---|---|\n| v65 | `design/teams/v65/` |\n' > "$D/design/TEAMS.md"
printf '🔄 TREE-R459\n' > "$D/design/teams/v65/NEWS-TREE.md"   # 🔄 줄 = 실 렌더러 요약본이 싣는 꼴(r509)
printf '# 틱\n```\nPROMPT-R459 <세션명>\n```\n' > "$D/design/teams/v65/20260912/TICK-PROMPT-v65-unified.md"
git -C "$D" add -A && git -C "$D" -c user.email=t@t -c user.name=t commit -q -m ref && git -C "$D" update-ref refs/remotes/origin/main HEAD
# 체크아웃은 뒤(옛 명단 · v65 폴더 0) — 112632 재현
printf '| 팀 | 폴더 |\n|---|---|\n| cfo | `design/cfo/` |\n' > "$D/design/TEAMS.md"; git -C "$D" rm -rq design/teams/v65; git -C "$D" -c user.email=t@t -c user.name=t commit -qam behind
lib() { (cd "$D" && TMPDIR="$T/tmpd" bash -c '. "$1/ft-team-lib.sh"; '"$1" _ "$KBIN" 2>&1); }
mkdir -p "$T/tmpd"
out="$(lib 'ft_team_in "'"$D"'" v65')"; rc=$?; [ "$rc" != 0 ] && ok "ⓒ 재현: 옛 ft_team_in(체크아웃 명단) → rc≠0" || bad "ⓒ 재현 실패 rc=$rc «$out»"
out="$(lib 'p="$(ft_team_doc_ref "'"$D"'" v65 NEWS-TREE.md)" && cat "$p" && ft_team_doc_tmp "$p" && echo TMP && rm -f "$p"')"; rc=$?
eq "$rc" 0 "ⓒ 실재 0 → ref 본문 rc0"; has "$out" "TREE-R459" "ⓒ ref 본문 내용"; has "$out" "TMP" "ⓒ ft_team_doc_tmp = 임시 본문"
eq "$(ls "$T/tmpd" | grep -c ft-team-doc)" 0 "ⓒ 부르는 쪽 정리 뒤 임시 파일 0"
mkdir -p "$D/design/teams/v65"; printf 'LOCAL\n' > "$D/design/teams/v65/NEWS-TREE.md"
eq "$(lib 'ft_team_doc_ref "'"$D"'" v65 NEWS-TREE.md')" "$D/design/teams/v65/NEWS-TREE.md" "ⓒ 루트 실재 1 → 그 경로"
mkdir -p "$D/design/v65"; printf 'TWIN\n' > "$D/design/v65/NEWS-TREE.md"
out="$(lib 'ft_team_doc_ref "'"$D"'" v65 NEWS-TREE.md')"; rc=$?; [ "$rc" = 1 ] && has "$out" "실재 후보 2개" "ⓒ 쌍둥이 2 → ERROR rc1" || bad "ⓒ 2+ rc=$rc «$out»"
rm -rf "$D/design/v65" "$D/design/teams/v65"
out="$(lib 'ft_team_doc_ref "'"$D"'" v65 NEWS-TREE.md no/such/ref')"; rc=$?; [ "$rc" = 1 ] && has "$out" "못 읽음" "ⓒ ref 못 읽음 → ERROR rc1" || bad "ⓒ ref rc=$rc «$out»"
out="$(lib 'ft_team_doc_ref "'"$D"'" v65 NOPE.md')"; rc=$?; [ "$rc" = 1 ] && has "$out" "도 없음" "ⓒ ref 에도 없음 → ERROR rc1" || bad "ⓒ 없음 rc=$rc «$out»"
# goal-tick: 체크아웃에 v65 폴더 0 · 옛 명단이어도 프롬프트를 ref 로 풀고 다음 단계(대상 좌석 확인)까지 간다
printf '#!/bin/sh\nexit 0\n' > "$D/.fable-team/comm/mbox.sh"; chmod 755 "$D/.fable-team/comm/mbox.sh"
out="$(cd "$D" && TMPDIR="$T/tmpd" FT_GOAL_TICK_ROOT="$D" FT_GOAL_TICK_CHECK="$T/noop.sh" FT_GOAL_TICK_TARGET="no-such-seat-r459" FT_GOAL_TICK_STREAK="$T/streak" bash "$KBIN/ft-goal-tick.sh" 2>&1)"; rc=$?
eq "$rc" 0 "ⓒ goal-tick rc0(112632 → 통과)"; has "$out" "target absent: no-such-seat-r459" "ⓒ goal-tick 프롬프트 풀고 대상 확인까지"
case "$out" in *ERROR*) bad "ⓒ goal-tick ERROR 줄 «$out»";; *) ok "ⓒ goal-tick ERROR 0";; esac
eq "$(ls "$T/tmpd" | grep -c ft-team-doc)" 0 "ⓒ goal-tick 임시 본문 정리(trap)"
# news-tick: FT_NEWS_ROOT 픽스처 · 트리 렌더러 = 같은 bin 의 실 ft-news-tree.py(r484 $HERE · 옛 v6 워크트리 가짜 렌더러는 안 쓰인다 · r509) · docker 가짜
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 1\n' > "$FB/docker"; chmod 755 "$FB/docker"; echo '{}' > "$D/.fable-team/seats.json"   # 실 렌더러는 공용 루트 명부를 읽는다
out="$(cd "$D" && PATH="$FB:$PATH" TMPDIR="$T/tmpd" FT_NEWS_ROOT="$D" FT_ME=me bash "$KBIN/ft-news-tick.sh" 2>&1)"
has "$out" "🔄 TREE-R459" "ⓒ news-tick 트리 = ref 본문(체크아웃 v65 폴더 0)"
case "$out" in *"트리 원본 없음"*|*"미해석"*|*Traceback*) bad "ⓒ news-tick 트리 미해석·Traceback";; *) ok "ⓒ news-tick 트리 ERROR 0";; esac
eq "$(ls "$T/tmpd" | grep -c ft-team-doc)" 0 "ⓒ news-tick 임시 본문 정리(trap)"
! grep -nE '/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents($|[^/]|/\.worktrees/v6-realtime-live)' "$KBIN/ft-goal-tick.sh" "$KBIN/ft-news-tick.sh" >/dev/null && ok "ⓒ goal·news 틱 글자 ROOT 0" || bad "ⓒ 글자 ROOT 남음"

# ── ⓓ install.sh --dry-run: 팩 comm 도구 ↔ <공용 루트>/.fable-team/comm cmp → COMM 줄 · 쓰기 0 ──
P2="$T/proj2"; mkdir -p "$P2/.fable-team/bin" "$P2/.fable-team/comm/bodies" "$P2/.fable-team/comm/relay"; git init -q -b main "$P2"; P2="$(cd "$P2" && pwd -P)"
printf 'old\n' > "$P2/.fable-team/comm/mbox.sh"; printf '{}\n' > "$P2/.fable-team/comm/mailbox.jsonl"; printf 'q\n' > "$P2/.fable-team/comm/queues.conf"; printf 'b\n' > "$P2/.fable-team/comm/bodies/1.txt"
H2="$T/h2"; LA="$H2/Library/LaunchAgents"; mkdir -p "$LA"
printf '#!/bin/sh\necho "$@" >> "%s/lc.log"\n[ "$1" = list ] && printf "{\\n\\t\\"PID\\" = 4242;\\n};\\n"\nexit 0\n' "$T" > "$FB/launchctl"; chmod 755 "$FB/launchctl"
printf '#!/bin/sh\necho "${R459_LSTART:-Mon Jan  1 00:00:00 2024}"\n' > "$FB/ps"; chmod 755 "$FB/ps"
NCOMM="$(cd "$HROOT/comm" && find . -maxdepth 1 -type f ! -name 'mailbox*.jsonl' ! -name '.mbox-seq' ! -name '.mbox-guard.json' ! -name 'queues.conf' ! -name '*.pyc' ! -name '.*' | grep -c .)"
inst() { env HOME="$H2" FT_LAUNCHCTL="$FB/launchctl" FT_PS="$FB/ps" bash "$HROOT/install.sh" "$@" --project "$P2" --home "$H2" 2>&1; }
SNAP2="$(cd "$P2/.fable-team/comm" && find . -type f -exec cksum {} + | LC_ALL=C sort)"
out="$(inst --dry-run)"; rc=$?
eq "$rc" 0 "ⓓ install --dry-run rc0"; has "$out" "COMM copied=$NCOMM same=0 dest=$P2/.fable-team/comm" "ⓓ COMM copied=$NCOMM(팩 도구 전부) same=0"
has "$out" "COMM $P2/.fable-team/comm/mbox.sh <- $HROOT/comm/mbox.sh (다름" "ⓓ 다른 파일 = COMM 줄 + (다름)"
case "$out" in *"comm/mailbox.jsonl <-"*|*"comm/queues.conf <-"*|*"bodies"*) bad "ⓓ 데이터 파일이 대상에 들어감";; *) ok "ⓓ 데이터 파일(우편함·큐·본문) 대상 밖";; esac
eq "$(cd "$P2/.fable-team/comm" && find . -type f -exec cksum {} + | LC_ALL=C sort)" "$SNAP2" "ⓓ dry-run 쓰기 0"
has "$out" "RESTART 0" "ⓓ dry-run 도 RESTART 판정 줄(읽기만 · 적재 데몬 0)"
WT2="$T/wt2"; git -C "$P2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i; git -C "$P2" worktree add -q "$WT2" -b w2; mkdir -p "$WT2/.fable-team/bin"
out="$(env HOME="$H2" FT_LAUNCHCTL="$FB/launchctl" bash "$HROOT/install.sh" --dry-run --project "$WT2" --home "$H2" 2>&1)"
has "$out" "SKIP comm (--project 가 git 공용 루트 아님" "ⓓ 워크트리 --project → SKIP comm"

# ── ⓔ install.sh --apply: comm cp(.bak) · 루트 전용 유지 · 2회째 same · RESTART 줄(실행 0) ──
mkdir -p "$T/other/.fable-team/bin"; DM="$T/other/.fable-team/bin/ft-daemon-r459.sh"; printf '#!/bin/sh\n' > "$DM"
cat > "$LA/com.t.r459.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>com.t.r459</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$DM</string></array></dict></plist>
EOF
: > "$T/lc.log"; out="$(inst --apply)"; rc=$?
VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$HROOT/../manifest.json")"
eq "$rc" 0 "ⓔ install --apply rc0"; has "$out" "COMM copied=$NCOMM same=0" "ⓔ COMM copied=$NCOMM"
cmp -s "$HROOT/comm/mbox.sh" "$P2/.fable-team/comm/mbox.sh" && ok "ⓔ comm/mbox.sh cmp0" || bad "ⓔ comm/mbox.sh 다름"
eq "$(cat "$P2/.fable-team/comm/mbox.sh.bak-$VER" 2>/dev/null)" "old" "ⓔ 덮기 전 .bak-$VER"
eq "$(cat "$P2/.fable-team/comm/mailbox.jsonl")$(cat "$P2/.fable-team/comm/queues.conf")$(cat "$P2/.fable-team/comm/bodies/1.txt")" "{}qb" "ⓔ 루트 전용 파일 3 유지"
has "$out" "RESTART com.t.r459 — launchctl kickstart -k gui/$(id -u)/com.t.r459" "ⓔ 기동 < mtime → RESTART 줄"
grep -q kickstart "$T/lc.log" && bad "ⓔ launchctl kickstart 실행됨" || ok "ⓔ kickstart 실행 0(master 집행)"
out="$(R459_LSTART="Fri Jan  1 00:00:00 2038" inst --apply)"; rc=$?
eq "$rc" 0 "ⓔ 2회째 rc0"; has "$out" "COMM copied=0 same=$NCOMM" "ⓔ 2회째 same(멱등)"; has "$out" "RESTART 0" "ⓔ 기동 > mtime → RESTART 0"
eq "$(cat "$P2/.fable-team/comm/mbox.sh.bak-$VER")" "old" "ⓔ .bak 첫 원본 보존(2회째 안 덮음)"
! grep -nE '\b(600|300)\b' "$KBIN/ft-harness-root.sh" "$KBIN/ft-team-lib.sh" "$KBIN/ft-goal-tick.sh" "$HROOT/install.sh" >/dev/null && ok "ⓔ 고친 파일 600/300 0" || bad "ⓔ 600/300 있음"

echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
