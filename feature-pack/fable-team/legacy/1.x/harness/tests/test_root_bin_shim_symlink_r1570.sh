#!/usr/bin/env bash
# test_root_bin_shim_symlink_r1570.sh — r1570: 루트 shim 이 심링크로 불려도 «심링크를 끝까지 푼 실제 위치» 옆 LIVE_BIN 을 찾는다
#   사건: h8047 — ~/.local/bin 링크 → 루트 shim 실행이 «<링크 폴더>/../LIVE_BIN 없음» rc3
#   사례 ⓐ 직접 ⓑ 링크 1단 ⓒ 링크 2단 ⓓ 상대 경로 링크 ⓔ LIVE_BIN 없음 = rc3 + 실제 폴더 기준 경로 ⓕ -p 유지 ⓢ 링크로 source · 변이 M1·M2
#   픽스처 = 임시 루트 리포 + 임시 라이브 bin — 실 루트·실 라이브 쓰기 0 · sleep 0
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SH="$HERE/../bin/ft-root-bin-shim.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got=[$2] want=[$3])"; }
KP="scripts/harness-install/fable-team/bin"; W="$T/w"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live" "$T/l1" "$T/l2" "$T/l3"
git init -q -b main "$W/root"
printf 'echo kit-a\n' > "$W/root/$KP/ft-a.sh"; printf 'echo kit-p\n' > "$W/root/$KP/ft-p.sh"; printf 'echo kit-lib\n' > "$W/root/$KP/ft-lib.sh"
git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m kit
git -C "$W/root" update-ref refs/remotes/origin/main HEAD
printf '#!/usr/bin/env bash\necho "LIVE-A args=$*"\n' > "$W/live/ft-a.sh"
printf '#!/usr/bin/env bash\ncase "$-" in *p*) echo "LIVE-P p=1";; *) echo "LIVE-P p=0";; esac\n' > "$W/live/ft-p.sh"
printf '#!/usr/bin/env bash\nlibfn() { echo "LIBFN"; }\n' > "$W/live/ft-lib.sh"
RB="$W/root/.fable-team/bin"
ln -s "$RB/ft-a.sh" "$T/l1/ft-a.sh"; ln -s "$T/l1/ft-a.sh" "$T/l2/ft-a.sh"          # ⓑ 1단 · ⓒ 2단(링크 → 링크 → shim)
ln -s "../w/root/.fable-team/bin/ft-a.sh" "$T/l3/ft-a.sh"                            # ⓓ 상대 경로 링크
ln -s "$RB/ft-p.sh" "$T/l1/ft-p.sh"; ln -s "$RB/ft-lib.sh" "$T/l1/ft-lib.sh"
gen() { rm -rf "$RB"/*; bash "${GEN:-$SH}" --root "$W/root" --live "$W/live" --repo "$W/root" --path "$KP" 2>&1; }
run() { bash "$1" x 2>&1; echo "rc=$?"; }
cases() {  # $1 = 이름 앞말 — ⓐ~ⓓ 결과 1줄
  local r=""; for p in "$RB/ft-a.sh" "$T/l1/ft-a.sh" "$T/l2/ft-a.sh" "$T/l3/ft-a.sh"; do
    case "$(run "$p")" in *"LIVE-A args=x"*rc=0) r="$r ok";; *) r="$r no";; esac; done; echo "${r# }"; }
out="$(gen)"; eq "생성기 rc0 · SHIM 3" "$? $(grep -c '^SHIM 3' <<<"$out")" "0 1"

echo "== ⓐ 직접 ⓑ 링크 1단 ⓒ 링크 2단 ⓓ 상대 경로 링크 — 모두 라이브 도구 rc0"
eq "ⓐⓑⓒⓓ" "$(cases)" "ok ok ok ok"

echo "== ⓔ LIVE_BIN 없음 — 링크로 불러도 rc3 + 실제 폴더 기준 경로 1줄"
mv "$W/root/.fable-team/LIVE_BIN" "$T/lb.bak"; out="$(run "$T/l2/ft-a.sh")"; mv "$T/lb.bak" "$W/root/.fable-team/LIVE_BIN"
eq "ⓔ rc3 · 경로 = 실제 폴더" "$(grep -c '^rc=3$' <<<"$out") $(grep -cF "ERROR LIVE_BIN 이 없거나 비었다: $RB/../LIVE_BIN" <<<"$out")" "1 1"

echo "== ⓕ -p 셸에서 링크로 실행 → -p 유지"
out="$(env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -p "$T/l1/ft-p.sh" 2>&1)"
eq "ⓕ LIVE-P p=1" "$(grep -c 'LIVE-P p=1' <<<"$out")" 1

echo "== ⓢ 링크로 source → lib 함수 · 부른 셸 이름 0"
out="$(bash -c '. "$1"; libfn; echo "N _s=${_s-없음} _t=${_t-없음} _h=${_h-없음}"' _ "$T/l1/ft-lib.sh" 2>&1)"
eq "ⓢ LIBFN · 이름 0" "$(grep -c '^LIBFN$' <<<"$out") $(grep -c '^N _s=없음 _t=없음 _h=없음$' <<<"$out")" "1 1"

echo "== 변이(생성기 사본) — 링크 풀기를 빼거나 1단만 풀면 그 사례가 깨진다"
mut() { local d="$T/mut/$1"; mkdir -p "$d"; cp "$SH" "$d/gen.sh"; python3 - "$d/gen.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert old in s, "치환 자리 없음: " + old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  echo "$d/gen.sh"; }
GEN="$(mut M1 'while [ -L "$_s" ]; do' 'while false; do')" gen >/dev/null
eq "M1 링크 풀기 제거 → ⓑ FAIL" "$(cases)" "ok no no no"
GEN="$(mut M2 'while [ -L "$_s" ]; do' 'for _o in 1; do [ -L "$_s" ] || break;')" gen >/dev/null
eq "M2 1단만 풀기 → ⓒ FAIL" "$(cases)" "ok ok no ok"

echo; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAILED $fail"; exit 1
