#!/usr/bin/env bash
# test_try_auto_land_r2293.sh — r2293 try-auto --land(계약 C2·C3·C5 · 반례 ②~⑤ · ⑦ --land 없음 · 변이 M2·M4 · 카드 r2293-landing-wait-alarm-auto-land · 사전 DA#32 APPROVE-DESIGN)
#   격리: 임시 bin = 시험 대상 ft-autonomy-try.sh 사본 + 가짜 ft-autonomy.sh(자율 ON · D2/S 결과 대역) · 가짜 standing-d2 · 가짜 ft-merge-land(인자 기록)
#   실 상태·실 원격·실 gh·실 착지 0 · sleep 0 · R2293_BIN=<bin 폴더> 로 대상 바꿈(기준판 대조)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R2293_BIN:-$HERE/../bin}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H=0123456789abcdef0123456789abcdef01234567; fail=0; out=""; rc=0
export FT_ROOT="$T/root" LAND_LOG="$T/land.log"; mkdir -p "$FT_ROOT"
printf '# 판정\n\n- 승인 sha: %s\n' "$H" > "$T/verdict.md"
mkbin() {  # <try 파일> <폴더> — 가짜 곁 파일 3개
  mkdir -p "$2"; cp "$1" "$2/ft-autonomy-try.sh"
  printf 'd2_on() { [ "${STUB_D2:-1}" = 0 ]; }\nscope_load() { G_S=S1; }\n' > "$2/ft-autonomy-standing-d2.sh"
  cat > "$2/ft-autonomy.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"; ROOT="$FT_ROOT"; mode() { echo on; }
case "$1" in
  try-auto) . "$HERE/ft-autonomy-try.sh"; "cmd_try_auto" "${@:2}" ;;
  standing-approve|scope-approve) printf '%b' "$STUB_OUT"; [ "$STUB_RC" = 0 ] || echo "SCOPE-REJECT 대역 거절" >&2; exit "$STUB_RC" ;;
  *) exit 9 ;;
esac
EOF
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$LAND_LOG"\necho "LANDED 대역"\n' > "$2/ft-merge-land.sh"
}
run() {  # run <bin 폴더> <STUB_OUT> <STUB_RC> [try-auto 끝 인자…]
  local b="$1" so="$2" sr="$3"; shift 3; : > "$LAND_LOG"
  out="$(STUB_OUT="$so" STUB_RC="$sr" bash "$b/ft-autonomy.sh" try-auto "$H" --pr 7 --repo byz --card c.md "$@" 2>&1)"; rc=$?
}
lands() { grep -c . "$LAND_LOG"; }
OKS="SCOPE-OK $H class=code used=1/30 today=1/15"
c2() { run "$1" "CLASS code kind=harness-bin learned\n$OKS\n" 0 --land   # ② TRY-OK · kind 일반 · --land → 착지 1회(desk h 인자)
  [ "$rc" = 0 ] && [[ "$(head -1 <<<"$out")" == "TRY-OK via=S1 $OKS" ]] && [ "$(cat "$LAND_LOG")" = "7 --approve-sha $H --repo $FT_ROOT" ] && grep -q "LANDED 대역" <<<"$out"; }
c3() { run "$1" "CLASS code kind=harness-bin learned\n" 1 --land   # ③ TRY-REJECT · --land → 착지 0
  [ "$rc" = 2 ] && [[ "$out" == TRY-REJECT* ]] && [ "$(lands)" = 0 ]; }
c4() { STUB_D2=0 run "$1" "CLASS docs kind=global-rule d2\nSTANDING-OK $H pr=7\n" 0 --verdict "$T/verdict.md" --land   # ④ D2 rc0 · kind=global-rule · TRY-OK → 착지 0 · 제외 1줄
  [ "$rc" = 0 ] && [[ "$out" == "TRY-OK via=D2 "* ]] && [ "$(lands)" = 0 ] && [ "$(grep -c "자동 착지 제외 kind=global-rule" <<<"$out")" = 1 ]; }
c5() { run "$1" "CLASSIFY code kind=harness-bin\n$OKS\n" 0 --land   # ⑤ kind 판독 불가(꼴 다름) · TRY-OK → 착지 0 · h 길
  [ "$rc" = 0 ] && [[ "$out" == TRY-OK* ]] && [ "$(lands)" = 0 ] && grep -q "kind 판독 불가 · h 길" <<<"$out"; }
c7() { run "$1" "CLASS code kind=harness-bin learned\n$OKS\n" 0   # ⑦ --land 없음 = 지금 그대로(2줄 · 착지 0)
  [ "$rc" = 0 ] && [ "$(grep -c . <<<"$out")" = 2 ] && [ "$(lands)" = 0 ]; }
ck() { local s=$SECONDS; if "$2" "$3"; then echo "PASS $1 ($((SECONDS - s))s)"; else echo "FAIL $1 :: rc=$rc out=${out:0:300} land=$(cat "$LAND_LOG")"; fail=$((fail + 1)); fi; }
mkbin "$BIN/ft-autonomy-try.sh" "$T/o"
for c in c2 c3 c4 c5 c7; do ck "$c" "$c" "$T/o"; done
mut() {  # mut <이름> <사례> <옛 글자> <새 글자> — 사본에서만 · 사례 FAIL 이어야 · 원본 같은 사례 1회 더
  local m="$T/$1"; python3 - "$BIN/ft-autonomy-try.sh" "$T/$1.sh" "$3" "$4" <<'PY' || { echo "FAIL $1 :: 변이 글자 1곳 아님"; fail=$((fail + 1)); return; }
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
assert text.count(old) == 1, old
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
  mkbin "$T/$1.sh" "$m"
  if "$2" "$m"; then echo "FAIL $1 :: 변이가 $2 를 통과"; fail=$((fail + 1)); else echo "PASS $1 ($2 FAIL)"; fi
  ck "$1-원본" "$2" "$T/o"
}
mut M2 c3 '[ "$ok" = 1 ] && [ "$land" = 1 ] &&' '[ "$land" = 1 ] &&'   # TRY-OK 조건 삭제
mut M4 c4 '  for k in $4; do case "$k" in global-rule|billing|deps) echo "자동 착지 제외 kind=$k · h 길"; return 0 ;; esac; done
' ''   # kind 제외 검사 삭제
echo "r2293 try-auto --land fail=$fail"
[ "$fail" = 0 ]
