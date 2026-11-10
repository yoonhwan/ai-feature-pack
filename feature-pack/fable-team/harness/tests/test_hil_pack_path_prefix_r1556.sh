#!/usr/bin/env bash
# test_hil_pack_path_prefix_r1556.sh — r1556: 설치 h 는 팩 1.x 경로를 «PACK_1X 변수 하나»로만 쓴다.
#   사례 ⓐ~ⓘ = ft-pack-1x-prefix.sh(ref→접두 1줄 · 둘 다·둘 다 없음·git 실패 = 판정 불가) + ft-hil 등록 검사(날 접두 REJECT)
#   변이 M1~M3 3/3(둘 다=legacy 고름 · 사슬에서 판정기 뺌 · 주석 줄도 검사) — 각각 ⓒ·ⓕ·ⓗ 를 FAIL 로 만든다
#   격리: 임시 git 리포 4개 · 임시 HIL_DIR·계획 · FT_*_JUDGE 대역 · 실 /tmp/h·실 팩·실 h 등록 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + 재진입 표지(RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
run() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

mkdir -p "$T/home" "$T/comm" "$T/notarepo"
mkrepo() {  # <이름> <팩 하위 폴더…> — 임시 git 리포 + 커밋 1(폴더마다 파일 1)
  local d="$T/$1"; shift; mkdir -p "$d"; git -C "$d" init -q -b main 2>/dev/null || git -C "$d" init -q
  local p; for p in "$@"; do mkdir -p "$d/$p"; : > "$d/$p/harness-marker"; done
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm one >/dev/null 2>&1
}
mkrepo main feature-pack/fable-team/harness
mkrepo legacy feature-pack/fable-team/legacy/1.x/harness
mkrepo both feature-pack/fable-team/harness feature-pack/fable-team/legacy/1.x/harness
mkrepo none docs

p_case() {  # <bin> <리포> <ref> — PV=rc · PO=stdout · PE=stderr
  PO="$(bash "$1/ft-pack-1x-prefix.sh" "$2" "$3" 2>"$T/err.txt")"; PV=$?; PE="$(cat "$T/err.txt")"
}
undec() { [ "$PV" != 0 ] && [ -z "$PO" ] && case "$PE" in *"판정 불가 $1"*) return 0;; esac; return 1; }
c_a() { p_case "$1" "$T/legacy" HEAD; [ "$PV" = 0 ] && [ "$PO" = "feature-pack/fable-team/legacy/1.x" ]; }
c_b() { p_case "$1" "$T/main" HEAD;   [ "$PV" = 0 ] && [ "$PO" = "feature-pack/fable-team" ]; }
c_c() { p_case "$1" "$T/both" HEAD;   undec "둘 다 있음"; }
c_d() { p_case "$1" "$T/none" HEAD;   undec "둘 다 없음"; }
c_e() {  # 없는 ref · 리포 아님 = 판정 불가 1줄(대체 실행 0)
  p_case "$1" "$T/main" nosuchref; undec "git 실패" || return 1
  p_case "$1" "$T/notarepo" HEAD;  undec "git 실패"
}

HD="$T/hil"; mkdir -p "$HD"
hil() {  # <bin> <계획> [대역=on|off] — 임시 HIL_DIR 등록 1회(대역 on 이면 다른 판정기는 건너뛴다)
  local a=(env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_MBOX_DIR="$T/comm")
  [ "${3:-on}" = on ] && a+=(FT_SECRET_JUDGE="$T/none.py" FT_TRAFFIC_JUDGE="$T/none.py" FT_SCOPE_JUDGE="$T/none.py" FT_MIX_JUDGE="$T/none.py")
  "${a[@]}" bash "$1/ft-hil.sh" --add "$2" 2>&1
}
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
plan() { printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-planner-master-claude#1\nset -uo pipefail\n%s\n' "$2" > "$T/$1.hil"; }
plan raw 'git show $R:feature-pack/fable-team/harness/bin/ft-hil.sh'
plan rawlegacy 'git show "$R:feature-pack/fable-team/legacy/1.x/harness/bin/ft-hil.sh"'
plan varform 'PACK_1X=$(bash ft-pack-1x-prefix.sh $R $REF) || exit 1; git show $R:${PACK_1X}/harness/bin/ft-hil.sh'
plan comment '# 옛 길: git show $R:feature-pack/fable-team/harness/bin/ft-hil.sh'
plan plain 'git show $R:docs/README.md'

rejected() { case "$1" in *"REJECT"*"PACK_1X 변수로 쓴다"*"줄 4"*) return 0;; esac; return 1; }
c_f() {  # 날 접두 2종 = REJECT rc1 · 등록 0 · 줄 번호 + «PACK_1X 변수로 쓴다» 1줄
  local o n0 k rc; for k in raw rawlegacy; do
    n0="$(nh)"; o="$(hil "$1" "$T/$k.hil" on)"; rc=$?
    [ "$rc" = 1 ] && [ "$(nh)" = "$n0" ] || return 1
    rejected "$o" || return 1
  done
  return 0
}
c_g() { local o; o="$(hil "$1" "$T/varform.hil" on)"; case "$o" in *REJECT*|*ERROR*) return 1;; esac; return 0; }
c_h() { local o; o="$(hil "$1" "$T/comment.hil" on)"; case "$o" in *REJECT*|*ERROR*) return 1;; esac; return 0; }
c_i() { local o; o="$(hil "$1" "$T/plain.hil" off)"; case "$o" in *REJECT*|*ERROR*) return 1;; esac; return 0; }

sec "ⓐ~ⓔ 접두 도구 — ref 마다 1줄 · 판정 불가 = 1줄 · stdout 0"
run "ⓐ legacy/1.x 만 = feature-pack/fable-team/legacy/1.x rc0" c_a "$BIN0"
run "ⓑ harness 만 = feature-pack/fable-team rc0" c_b "$BIN0"
run "ⓒ 둘 다 = rc≠0 · stdout 0 · «판정 불가 둘 다 있음»" c_c "$BIN0"
run "ⓓ 둘 다 없음 = rc≠0 · stdout 0 · «판정 불가 둘 다 없음»" c_d "$BIN0"
run "ⓔ 없는 ref·리포 아님 = rc≠0 · «판정 불가» 1줄(대체 실행 0)" c_e "$BIN0"
sec "ⓕ~ⓘ ft-hil 등록 검사"
run "ⓕ 날 접두 2종 = REJECT rc1 · 등록 0 · «PACK_1X 변수로 쓴다» + «줄 4»" c_f "$BIN0"
run "ⓖ «\${PACK_1X}/harness/…» 꼴 = 등록 rc0" c_g "$BIN0"
run "ⓗ 주석 줄의 날 접두 = 검사 밖(등록 rc0)" c_h "$BIN0"
run "ⓘ 팩 경로 없는 계획 = 실 판정기 그대로 rc0" c_i "$BIN0"

sec "줄·사본"
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" = 200 ] && ok "ft-hil.sh ${n}줄(늘지 않음)" || bad "ft-hil.sh ${n}줄 ≠200"
n="$(wc -l < "$BIN0/ft_pack_path_plan_judge.py" | tr -d ' ')"; [ "$n" -le 60 ] && ok "판정기 ${n}줄 ≤60" || bad "판정기 ${n}줄 >60"
n="$(wc -l < "$BIN0/ft-pack-1x-prefix.sh" | tr -d ' ')"; [ "$n" -le 40 ] && ok "접두 도구 ${n}줄 ≤40" || bad "접두 도구 ${n}줄 >40"
for f in ft-pack-1x-prefix.sh ft_pack_path_plan_judge.py ft-hil.sh; do
  cmp -s "$BIN0/$f" "$HERE/../kit/fable-team/bin/$f" && ok "bin=kit $f" || bad "bin≠kit $f"
done

sec "변이 M1~M3 — 각각 ⓒ·ⓕ·ⓗ 를 FAIL 로 만드는지"
caught() {  # <설명> <사례함수> <변이 bin> — 변이 사본에서 그 사례가 깨지면 잡은 것
  rm -rf "$HD"; mkdir -p "$HD"
  if "$2" "$3" >/dev/null 2>&1; then bad "변이 $1 를 못 잡음($2 가 변이 사본에서도 통과)"; else ok "변이 $1 → 사례 FAIL 검출"; fi
}
mut() {  # <사본이름> <파일> <옛 줄> <새 줄> — 바꾼 사본 경로를 stdout(옛 줄이 없으면 rc1)
  local d="$T/$1"; cp -R "$BIN0" "$d" || return 1
  python3 - "$BIN0/$2" "$d/$2" "$3" "$4" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit("옛 줄 없음: " + old)
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s\n' "$d"
}
M1="$(mut mut1 ft-pack-1x-prefix.sh '  11) undecidable "둘 다 있음 $ref" ;;' '  11) echo "$BASE/legacy/1.x" ;;')"
[ -n "$M1" ] && caught "M1(둘 다=legacy 고름)" c_c "$M1" || bad "M1 사본 못 만듦"
M2="$(mut mut2 ft-hil.sh ' && lint "$f" "${FT_PACK_PATH_JUDGE:-$l/ft_pack_path_plan_judge.py}" "팩 1.x 경로 접두" ""' '')"
[ -n "$M2" ] && caught "M2(사슬에서 판정기 뺌)" c_f "$M2" || bad "M2 사본 못 만듦"
M3="$(mut mut3 ft_pack_path_plan_judge.py 'if line.lstrip().startswith("#"):' 'if False:')"
[ -n "$M3" ] && caught "M3(주석 줄도 검사)" c_h "$M3" || bad "M3 사본 못 만듦"

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
