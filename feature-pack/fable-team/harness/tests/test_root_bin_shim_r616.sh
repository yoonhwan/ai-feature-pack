#!/usr/bin/env bash
# test_root_bin_shim_r616.sh — r616: r613 의 «남김» 판정에 «의존 1단계» 를 더한다 —
#   예약 대상으로 남긴 스크립트 본문이 같은 bin 의 «키트 밖 이름» 을 부르면 그 이름도 남긴다(폴더·바이너리 본문 검사 생략 · 1단계만).
#   픽스처 = mktemp 임시 리포(루트)·임시 라이브 bin·가짜 launchctl(FT_SHIM_LAUNCHCTL) — 실 루트 bin·실 launchd·실 라이브 0.
#   기준 판 대조는 FT_ROOT_BIN_SHIM_SH=<base 사본> 으로 같은 시험을 돌려 «전(FAIL)» 을 만든다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SH="${FT_ROOT_BIN_SHIM_SH:-$HERE/../../harness/bin/ft-root-bin-shim.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

bash -n "$SH" && ok "bash -n" || bad "bash -n"

KP="scripts/harness-install/fable-team/bin"
build() {  # $1 = 작업 폴더 · $2 = 루트가 git 리포인가(1/0)
  local W="$1" g="${2:-1}"; rm -rf "$W"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live" "$W/kit/$KP"
  git init -q -b main "$W/kit"
  printf 'x\n' > "$W/kit/$KP/ft-a.sh"; printf 'y\n' > "$W/kit/$KP/ft-b.py"
  git -C "$W/kit" add -A && git -C "$W/kit" -c user.email=t@t -c user.name=t commit -q -m kit
  if [ "$g" = 1 ]; then git init -q -b main "$W/root"; fi
  printf '#!/usr/bin/env bash\necho A\n' > "$W/live/ft-a.sh"; printf 'import sys\nprint("B")\n' > "$W/live/ft-b.py"
  printf '#!/usr/bin/env bash\necho OLD-A\n' > "$W/root/.fable-team/bin/ft-a.sh"
}
fake_lctl() {  # $1 = 작업 폴더 · $2 = rc · $3 = print 에 넣을 경로
  local D="$1" rc="$2" p="$3"
  printf '#!/usr/bin/env bash\ncase "$1" in\n  list) [ "%s" = 0 ] || exit 1; printf "PID\\tStatus\\tLabel\\n-\\t0\\tcom.test.teamx\\n"; exit 0;;\n  print) printf "arguments = {\\n\\t%s\\n}\\n"; exit 0;;\nesac\nexit 2\n' "$rc" "$p" > "$D/fake-lctl"; chmod 755 "$D/fake-lctl"
}
RUN() { local W="$1"; shift; FT_SHIM_LAUNCHCTL="$W/fake-lctl" bash "$SH" --root "$W/root" --live "$W/live" --ref HEAD --repo "$W/kit" --path "$KP" "$@"; }

# ── ⓐ 예약 대상 team-x.sh 가 부르는 같은 bin 의 team-dep.sh(추적 아님·예약 대상 아님) → 남김 · old.sh 만 옮김 ──
W="$T/a"; build "$W"; RB="$W/root/.fable-team/bin"
printf '#!/usr/bin/env bash\nCHECK="$ROOT/.fable-team/bin/team-dep.sh"\nbash "$CHECK"\n' > "$RB/team-x.sh"
printf '#!/usr/bin/env bash\necho DEP\n' > "$RB/team-dep.sh"
printf 'echo old\n' > "$RB/old.sh"
fake_lctl "$W" 0 "$RB/team-x.sh"
out="$(RUN "$W" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓐ rc0"
has "$out" "남김(추적 0 · 예약 대상 1 · 의존 1): team-x.sh, team-dep.sh" "ⓐ 남김 줄(의존 1 · 이름 2개)"
has "$out" "SHIM 2 · MOVED 2 · UNKNOWN 1" "ⓐ SHIM 2 · MOVED 2(옛 사본·old.sh) · UNKNOWN 1(old.sh)"
hasnt "$out" "PLAN move team-dep.sh" "ⓐ team-dep.sh 옮김 계획 0"
[ -e "$RB/team-dep.sh" ] && ok "ⓐ 의존 team-dep.sh = bin 에 남음" || bad "ⓐ 의존 team-dep.sh 가 옮겨졌다"
[ ! -e "$RB/old.sh" ] && ok "ⓐ 범위 밖 old.sh 는 옮김" || bad "ⓐ old.sh 가 남음"
ST="$(ls -d "$W/root/.fable-team"/bin.stale-* 2>/dev/null | head -1)"
[ ! -e "$ST/team-dep.sh" ] && [ -f "$ST/old.sh" ] && ok "ⓐ stale 에 의존 파일 0" || bad "ⓐ stale 내용 :: $(ls "$ST" 2>/dev/null)"
out="$(RUN "$W" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓐ 두 번째 실행"
has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "ⓐ 두 번째 MOVED 0(멱등)"
has "$out" "남김(추적 0 · 예약 대상 1 · 의존 1): team-x.sh, team-dep.sh" "ⓐ 두 번째도 남김 줄 그대로"

# ── ⓑ 본문 표기 3종(bash team-dep.sh · ./team-dep.sh · bin/team-dep.sh) 같은 결과 · 의존 0 이면 옛 꼴 그대로 ──
for form in 'bash team-dep.sh' './team-dep.sh' 'bin/team-dep.sh'; do
  W="$T/b-$(printf '%s' "$form" | tr -c 'a-z' '_')"; build "$W"; RB="$W/root/.fable-team/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$form" > "$RB/team-x.sh"
  printf '#!/usr/bin/env bash\necho DEP\n' > "$RB/team-dep.sh"
  fake_lctl "$W" 0 "$RB/team-x.sh"
  out="$(RUN "$W" 2>&1)"
  has "$out" "남김(추적 0 · 예약 대상 1 · 의존 1): team-x.sh, team-dep.sh" "ⓑ «${form}» → 의존 1"
  [ -e "$RB/team-dep.sh" ] && ok "ⓑ «${form}» team-dep.sh 남음" || bad "ⓑ «${form}» team-dep.sh 옮겨짐"
done
W="$T/b-none"; build "$W"; RB="$W/root/.fable-team/bin"
printf '#!/usr/bin/env bash\necho X\n' > "$RB/team-x.sh"
printf 'echo old\n' > "$RB/old.sh"
fake_lctl "$W" 0 "$RB/team-x.sh"
out="$(RUN "$W" 2>&1)"
has "$out" "남김(추적 0 · 예약 대상 1): team-x.sh" "ⓑ 의존 0 → 옛 꼴 그대로(의존 칸 없음)"
hasnt "$out" "의존 0" "ⓑ 의존 0 칸 안 붙임"

# ── ⓒ 예약 대상이 아닌(추적 파일) 본문에 나온 이름은 남김 아님 — 지금처럼 옮김 · 1단계만 ──
W="$T/c"; build "$W"; RB="$W/root/.fable-team/bin"
mkdir -p "$RB/tour"; printf 'bash team-dep.sh\n' > "$RB/tour/a.py"
printf '#!/usr/bin/env bash\nbash team-dep.sh\n' > "$RB/team-x.sh"
printf '#!/usr/bin/env bash\nbash team-deep.sh\n' > "$RB/team-dep.sh"    # 이 파일은 «의존» 으로만 남는다 — 그 본문의 team-deep.sh 는 2단계 = 범위 밖
printf '#!/usr/bin/env bash\necho DEEP\n' > "$RB/team-deep.sh"
printf 'plain\n' > "$RB/dep-binary.bin"; printf '\x00\x01\x02\n' > "$RB/blob.sh"   # 바이너리 = 본문 검사 생략
git -C "$W/root" add .fable-team/bin/tour && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m tracked
fake_lctl "$W" 0 "$RB/team-x.sh"
out="$(RUN "$W" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓒ rc0"
has "$out" "남김(추적 1 · 예약 대상 1 · 의존 1)" "ⓒ 추적 tour 는 의존 검사 대상 아님(의존 1 = team-dep.sh 뿐)"
[ ! -e "$RB/team-deep.sh" ] && ok "ⓒ 1단계만 — 의존의 의존(team-deep.sh)은 옮김" || bad "ⓒ 2단계까지 남겼다(team-deep.sh 남음)"
[ ! -e "$RB/blob.sh" ] && ok "ⓒ 바이너리 본문 검사 생략(blob.sh 옮김)" || bad "ⓒ 바이너리가 남음"

# ── ⓓ r613 시험·기존 shim 시험 전부 PASS ──
out="$(bash "$HERE/test_root_bin_shim_r613.sh" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓓ test_root_bin_shim_r613.sh"
has "$out" "== fail=0" "ⓓ r613 fail=0"
out="$(bash "$HERE/test_root_bin_shim.sh" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓓ 기존 test_root_bin_shim.sh"
has "$out" "== fail=0" "ⓓ 기존 시험 fail=0"
echo "== fail=$fail"; [ "$fail" = 0 ]
