#!/usr/bin/env bash
# test_root_bin_shim_source_r1694.sh — r1694: 루트 shim(.fable-team/bin/*.sh)을 «. 파일» 로 source 해도 부른 셸이 살아남는다(source = 라이브 파일을 같은 셸에 source + return · 실행 = 지금처럼 exec)
#   사건: 11-11 19:44 소스 안의 exec 가 부른 mbox.sh 를 바꿔 모든 명령이 출력 0·rc0 으로 끝났다.
#   사례 ⓐ source 뒤 부른 셸 계속 ⓑ 실행 = exec 그대로 ⓒ LIVE_BIN 없음(source = return 3 · 셸 생존 / exec = rc3) ⓓ 부른 셸에 _src·_f 0
#        ⓔ r1675 꼴(루트 bin lib 를 source 하는 mbox.sh) peek 출력 1줄 이상 ⓕ -p 실행은 -p 유지 ⓖ 멱등(두 번째 실행 쓰기 0) · 변이 M1~M3
#   픽스처 = 임시 루트 리포 + 임시 라이브 bin(가짜 도구) — 실 루트·실 라이브 쓰기 0 · sleep 0 · 사례 70초
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SH="$HERE/../bin/ft-root-bin-shim.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3" "없음 «$2» ← ${1:0:200}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "있으면 안 됨 «$2»";; *) ok "$3";; esac; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got=[$2] want=[$3])"; }
KP="scripts/harness-install/fable-team/bin"; W="$T/w"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live"
git init -q -b main "$W/root"
printf 'echo kit-lib\n' > "$W/root/$KP/ft-lib.sh"; printf 'echo kit-a\n' > "$W/root/$KP/ft-a.sh"
printf 'echo kit-p\n' > "$W/root/$KP/ft-p.sh"; printf 'echo kit-sw\n' > "$W/root/$KP/ft20-switch-lib.sh"
git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m kit
git -C "$W/root" update-ref refs/remotes/origin/main HEAD   # 생성기는 --ref(기본 origin/main) 트리에서 키트를 읽는다
printf '#!/usr/bin/env bash\nL_LIB=1\nlibfn() { echo "LIBFN $*"; }\necho "LIVE-LIB loaded"\n' > "$W/live/ft-lib.sh"   # source 되는 라이브 lib
printf '#!/usr/bin/env bash\necho "LIVE-A args=$*"\nexit 7\n' > "$W/live/ft-a.sh"                                        # 실행 도구
printf '#!/usr/bin/env bash\ncase "$-" in *p*) echo "LIVE-P p=1 args=$*";; *) echo "LIVE-P p=0 args=$*";; esac\n' > "$W/live/ft-p.sh"
printf '#!/usr/bin/env bash\nL_SW=1\nswfn() { echo "SWFN"; }\n' > "$W/live/ft20-switch-lib.sh"
gen() { bash "${GEN:-$SH}" --root "$W/root" --live "$W/live" --repo "$W/root" --path "$KP" "$@" 2>&1; }
out="$(gen)"; rc=$?
eq "생성기 rc0 · SHIM 4" "$rc $(grep -c '^SHIM 4' <<<"$out")" "0 1"
RB="$W/root/.fable-team/bin"

echo "== ⓐ source — 부른 셸이 계속 살아 있고 lib 함수를 쓴다"
cat > "$T/caller.sh" <<'EOS'
. "$1/ft-lib.sh"
echo "AFTER1"
libfn one
echo "AFTER1-END"
EOS
out="$(bash "$T/caller.sh" "$RB" 2>&1)"; rc=$?
eq "ⓐ rc0 · AFTER1 · LIBFN · AFTER1-END" "$rc $(grep -c '^AFTER1$' <<<"$out") $(grep -c '^LIBFN one$' <<<"$out") $(grep -c '^AFTER1-END$' <<<"$out")" "0 1 1 1"

echo "== ⓑ 실행 — 지금처럼 exec(라이브 도구가 인자를 받고 그 rc 를 돌려준다)"
out="$(bash "$RB/ft-a.sh" a b 2>&1)"; rc=$?
eq "ⓑ rc=7(라이브 rc) · 인자 a b" "$rc $(grep -c 'LIVE-A args=a b' <<<"$out")" "7 1"

echo "== ⓒ LIVE_BIN 없음 — source = return 3 · 부른 셸 생존 / 실행 = rc3"
mv "$W/root/.fable-team/LIVE_BIN" "$T/LIVE_BIN.bak"
out="$(bash "$T/caller.sh" "$RB" 2>&1)"; rc=$?
eq "ⓒ 실행 rc3" "$(bash "$RB/ft-lib.sh" >/dev/null 2>&1; echo $?)" 3
has "$out" "ERROR LIVE_BIN" "ⓒ source = ERROR 1줄"
has "$out" "AFTER1" "ⓒ source 뒤 부른 셸이 계속 실행(AFTER1 출력)"
mv "$T/LIVE_BIN.bak" "$W/root/.fable-team/LIVE_BIN"

echo "== ⓓ source 뒤 부른 셸에 shim 지역 이름 0 (lib 가 정의한 이름은 남는다)"
cat > "$T/names.sh" <<'EOS'
. "$1/ft-lib.sh"
echo "NAMES _src=${_src-없음} _f=${_f-없음} _l=${_l-없음} _h=${_h-없음} L_LIB=${L_LIB-없음}"
EOS
out="$(bash "$T/names.sh" "$RB" 2>&1)"
has "$out" "NAMES _src=없음 _f=없음 _l=없음 _h=없음 L_LIB=1" "ⓓ shim 지역 이름 0 · lib 이름 유지"

echo "== ⓔ r1675 꼴(루트 bin lib 를 source 하는 mbox.sh) → peek 출력 1줄 이상"
cat > "$T/mbox1675.sh" <<'EOS'
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
FT20_LIB="${FT_BIN:-$DIR/../bin}/ft20-switch-lib.sh"
. "$FT20_LIB"
case "${1:-}" in peek) echo "pending=3 scanned=1";; esac
EOS
mkdir -p "$T/r1675/comm"; cp "$T/mbox1675.sh" "$T/r1675/comm/mbox.sh"; ln -sfn "$RB" "$T/r1675/bin"
out="$(bash "$T/r1675/comm/mbox.sh" peek x 2>&1)"; rc=$?
eq "ⓔ rc0 · 출력 1줄 이상" "$rc $([ -n "$out" ] && echo yes || echo no)" "0 yes"
has "$out" "pending=3" "ⓔ peek 내용"

echo "== ⓕ -p 셸에서 실행 → 라이브 도구가 -p 로 뜬다(r657 그대로)"
out="$(env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -p "$RB/ft-p.sh" z 2>&1)"
has "$out" "LIVE-P p=1" "ⓕ -p 유지"

echo "== ⓖ 멱등 — 두 번째 실행 = 쓰기 0"
h1="$(cat "$RB"/*.sh | shasum | cut -d' ' -f1)"; out2="$(gen)"; h2="$(cat "$RB"/*.sh | shasum | cut -d' ' -f1)"
eq "ⓖ 본문 불변 · SHIM 4" "$([ "$h1" = "$h2" ] && echo same) $(grep -c '^SHIM 4' <<<"$out2")" "same 1"

echo "== 변이(사본에서만) — source 분기·return·unset 을 하나씩 지우면 그 사례가 깨진다"
mut() { local d="$T/mut/$1"; mkdir -p "$d"; cp "$SH" "$d/gen.sh"; python3 - "$d/gen.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert old in s, "치환 자리 없음: " + old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  echo "$d/gen.sh"; }
rm -rf "$RB"/*; G1="$(mut M1 '&& _src=1' '&& _src=0')" && GEN="$G1" gen >/dev/null
out="$(bash "$T/caller.sh" "$RB" 2>&1)"; rc=$?
eq "M1 source 분기 삭제 → ⓐ 검출(AFTER1 0)" "$(grep -c '^AFTER1$' <<<"$out")" 0
rm -rf "$RB"/*; G2="$(mut M2 '[ "\$_src" = 1 ] && return 3 || exit 3' 'exit 3')" && GEN="$G2" gen >/dev/null
mv "$W/root/.fable-team/LIVE_BIN" "$T/lb.bak"; out="$(bash "$T/caller.sh" "$RB" 2>&1)"; mv "$T/lb.bak" "$W/root/.fable-team/LIVE_BIN"
eq "M2 return→exit → ⓒ 검출(부른 셸 죽음)" "$(grep -c '^AFTER1$' <<<"$out")" 0
rm -rf "$RB"/*; G3="$(mut M3 'unset _h _f _l _src; ' '')" && GEN="$G3" gen >/dev/null
out="$(bash "$T/names.sh" "$RB" 2>&1)"
has "$out" "NAMES _src=1" "M3 unset 삭제 → ⓓ 검출(_src 남음)"

echo; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAILED $fail"; exit 1
