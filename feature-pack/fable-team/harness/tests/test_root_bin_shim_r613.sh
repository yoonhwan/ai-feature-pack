#!/usr/bin/env bash
# test_root_bin_shim_r613.sh — r613: 루트 bin 정리(③)가 «git 추적 파일» 과 «로드된 LaunchAgent 인자 경로» 를 옮기지 않고 남긴다 · ⓐ~ⓓ
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
build() {  # $1 = 작업 폴더 · $2 = 루트가 git 리포인가(1/0) · 키트 리포는 따로($1/kit — git 밖 루트에서도 --repo 가 풀리게)
  local W="$1" g="${2:-1}"; rm -rf "$W"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live" "$W/kit/$KP"
  git init -q -b main "$W/kit"
  printf 'x\n' > "$W/kit/$KP/ft-a.sh"; printf 'y\n' > "$W/kit/$KP/ft-b.py"
  git -C "$W/kit" add -A && git -C "$W/kit" -c user.email=t@t -c user.name=t commit -q -m kit
  if [ "$g" = 1 ]; then git init -q -b main "$W/root"; fi
  # git 추적 파일 = tour/a.py (카드 ⓐ · rag-transplant 실사건의 tour/ 54개)
  mkdir -p "$W/root/.fable-team/bin/tour"; printf 'catalog\n' > "$W/root/.fable-team/bin/tour/a.py"
  if [ "$g" = 1 ]; then git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m tracked; fi
  printf '#!/usr/bin/env bash\necho A\n' > "$W/live/ft-a.sh"; printf 'import sys\nprint("B")\n' > "$W/live/ft-b.py"
  # 루트 옛 사본 + 키트 밖 이름(예약 대상 team-x.sh / 그냥 old.sh) + .bak + __pycache__
  printf '#!/usr/bin/env bash\necho OLD-A\n' > "$W/root/.fable-team/bin/ft-a.sh"
  printf 'echo team-x\n' > "$W/root/.fable-team/bin/team-x.sh"
  printf 'echo old\n' > "$W/root/.fable-team/bin/old.sh"
  printf 'bak\n' > "$W/root/.fable-team/bin/ft-a.sh.bak-1"
  mkdir -p "$W/root/.fable-team/bin/__pycache__"; printf 'c\n' > "$W/root/.fable-team/bin/__pycache__/x.pyc"
}
fake_lctl() {  # $1 = 작업 폴더 · $2 = rc(0 = 목록 읽힘 · 1 = 못 읽음) · $3 = print 에 넣을 경로
  local D="$1" rc="$2" p="$3"
  printf '#!/usr/bin/env bash\ncase "$1" in\n  list) [ "%s" = 0 ] || exit 1; printf "PID\\tStatus\\tLabel\\n-\\t0\\tcom.test.teamx\\n"; exit 0;;\n  print) printf "arguments = {\\n\\t%s\\n}\\n"; exit 0;;\nesac\nexit 2\n' "$rc" "$p" > "$D/fake-lctl"; chmod 755 "$D/fake-lctl"
}
RUN() { local W="$1"; shift; FT_SHIM_LAUNCHCTL="$W/fake-lctl" bash "$SH" --root "$W/root" --live "$W/live" --ref HEAD --repo "$W/kit" --path "$KP" "$@"; }

# ── ⓐ 추적 1(tour) + 예약 대상 1(team-x.sh) 은 남고, 옛 사본·.bak·__pycache__·old.sh 만 옮긴다 ──
W="$T/a"; build "$W"; RB="$W/root/.fable-team/bin"; fake_lctl "$W" 0 "$RB/team-x.sh"
out="$(RUN "$W" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓐ rc0"
has "$out" "남김(추적 1 · 예약 대상 1): team-x.sh, tour" "ⓐ 남김 줄(추적 1 · 예약 대상 1 · 이름 5개)"
has "$out" "SHIM 2 · MOVED 4 · UNKNOWN 1" "ⓐ SHIM 2 · MOVED 4 · UNKNOWN 1(옮긴 것만 셈)"
[ -e "$RB/team-x.sh" ] && ok "ⓐ 예약 대상 team-x.sh = bin 에 남음" || bad "ⓐ 예약 대상 team-x.sh 가 옮겨졌다"
[ -e "$RB/tour/a.py" ] && ok "ⓐ git 추적 tour/a.py = bin 에 남음" || bad "ⓐ 추적 tour/a.py 가 옮겨졌다"
[ ! -e "$RB/old.sh" ] && [ ! -e "$RB/ft-a.sh.bak-1" ] && [ ! -e "$RB/__pycache__" ] && ok "ⓐ 옛 사본·.bak·__pycache__·키트 밖 old.sh 는 옮김" || bad "ⓐ 옮겨야 할 것이 bin 에 남음 :: $(ls "$RB")"
ST="$(ls -d "$W/root/.fable-team"/bin.stale-* 2>/dev/null | head -1)"
[ -n "$ST" ] && [ -f "$ST/old.sh" ] && [ -f "$ST/ft-a.sh" ] && [ -f "$ST/ft-a.sh.bak-1" ] && ok "ⓐ stale 폴더에 옮긴 것 4개(삭제 0)" || bad "ⓐ stale 내용 부족 :: $(ls "$ST" 2>/dev/null)"
[ ! -e "$ST/team-x.sh" ] && [ ! -e "$ST/tour" ] && ok "ⓐ stale 에 남긴 것 0" || bad "ⓐ stale 에 남겨야 할 것이 들어감"
has "$out" "UNKNOWN team-x.sh (키트 밖 — 연결 0 · 남김)" "ⓐ 키트 밖 남긴 이름 = «남김» 으로 보고"
[ "$(bash "$RB/ft-a.sh" 2>&1)" = "A" ] && ok "ⓐ 연결 파일 생성(라이브 도구 호출 = A)" || bad "ⓐ 연결 파일 미생성"
# 멱등: 두 번째 실행 = MOVED 0 · 남김 줄 그대로
out="$(RUN "$W" 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓐ 두 번째 실행"
has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "ⓐ 두 번째 MOVED 0"
has "$out" "남김(추적 1 · 예약 대상 1): team-x.sh, tour" "ⓐ 두 번째도 남김 줄 1"

# ── ⓑ git 밖 루트 = 추적 판정 생략 + WARN 1줄 · 예약 대상 판정은 그대로 ──
W="$T/b"; build "$W" 0; RB="$W/root/.fable-team/bin"; fake_lctl "$W" 0 "$RB/team-x.sh"
out="$(RUN "$W" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓑ git 밖 rc0"
has "$out" "WARN git 밖 — 추적 판정 생략: $W/root" "ⓑ WARN 1줄(추적 판정 생략)"
has "$out" "남김(추적 0 · 예약 대상 1): team-x.sh" "ⓑ 추적 0 · 예약 대상 1"
[ ! -e "$RB/tour" ] && ok "ⓑ git 밖에서는 추적 판정 0 → tour 도 옮김(추적 아님)" || bad "ⓑ git 밖인데 tour 가 남음"
[ -e "$RB/team-x.sh" ] && ok "ⓑ 예약 대상 판정은 git 밖에서도 그대로" || bad "ⓑ 예약 대상이 옮겨졌다"

# ── ⓒ launchctl 목록 못 읽음 = fail-closed(키트 밖 이름 옮기기 0) · .bak·__pycache__ 는 그대로 옮김 ──
W="$T/c"; build "$W"; RB="$W/root/.fable-team/bin"; fake_lctl "$W" 1 ""
out="$(RUN "$W" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓒ rc0"
has "$out" "남김 판정 불가 — 키트 밖 이름 옮기기 0 (launchctl 목록 못 읽음)" "ⓒ 판정 불가 1줄"
[ -e "$RB/team-x.sh" ] && [ -e "$RB/old.sh" ] && ok "ⓒ 키트 밖 이름 옮기기 0(team-x.sh·old.sh 둘 다 남음)" || bad "ⓒ 키트 밖 이름이 옮겨졌다"
[ ! -e "$RB/ft-a.sh.bak-1" ] && [ ! -e "$RB/__pycache__" ] && ok "ⓒ .bak·__pycache__ 는 그대로 옮김(키트 밖 이름만 멈춤)" || bad "ⓒ .bak·__pycache__ 가 남음"
[ -e "$RB/tour/a.py" ] && ok "ⓒ 추적 판정은 launchctl 과 무관(남음)" || bad "ⓒ 추적 파일이 옮겨졌다"

# ── ⓓ 기존 root-bin-shim 시험 전부 PASS ──
out="$(bash "$HERE/test_root_bin_shim.sh" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓓ 기존 test_root_bin_shim.sh"
has "$out" "== fail=0" "ⓓ 기존 시험 fail=0"
echo "== fail=$fail"; [ "$fail" = 0 ]
