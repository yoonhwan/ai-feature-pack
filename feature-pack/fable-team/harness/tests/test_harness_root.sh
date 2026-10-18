#!/usr/bin/env bash
# test_harness_root.sh — r385b: 데이터 루트 해석기 2종(ft-harness-root.sh ft_repo_root · ft_data_root) + 소비자 도구.
#   ⓖ 새 설치본(임시 HOME/.claude/fable-team/live/<ver>/bin · git 밖)에서 cwd=git 밖 · env 없음 → 도구 ERROR rc≠0 + 임시 HOME 밑 새 파일 0
#   ⓗ cwd=픽스처 리포 워크트리(.fable-team/LIVE_ROOT 있음) → ft_repo_root = 리포 공용 루트 · ft_data_root = LIVE_ROOT 값
#   ⓘ env 명시(FT_ROOT·FT_RES_ROOT) → 그 값 · ⓙ 옛 설치 꼴(<리포>/.fable-team/bin) → 옛 식 값(회귀 0) · ⓚ LIVE_ROOT 값 오류 → ERROR
#   ⓛ 새 설치본 drift-check(--repo 생략) = 하네스 코드 루트(FT_HARNESS_ROOT)의 키트로 대조.
# mktemp 만 쓴다 — 실 HOME·실 리포 상태·쪽지 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HROOT="$(cd -- "$HERE/.." && pwd -P)"
KBIN="$HROOT/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
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

echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
