#!/usr/bin/env bash
# test_test_only_lib.sh — r1026: tests/lib/test_only.sh(FT_TEST_ONLY 로 «그 칸만» 도는 공용 함수) 시험.
#   ⓐ 환경 없음(unset·빈 문자열 둘 다) → 칸 3개 전부 돈다 ⓑ FT_TEST_ONLY=ⓑ → ⓑ 만 ⓒ FT_TEST_ONLY=ⓐ,ⓒ → 둘만
#   ⓓ FT_TEST_ONLY=ⓩ(없는 칸) → ft_only_report 가 `BAD FT_TEST_ONLY=ⓩ 에 맞는 칸 0` 1줄 + rc1(오타로 «0 FAIL = 통과» 차단)
#   변이: ft_only 가 늘 rc0 → ⓑ 실행에서 ⓐ 가 같이 돌아 검출. 임시 폴더만 쓴다 — 실 tmux·baton·mbox·워크트리 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="$HERE/lib/test_only.sh"
[ -f "$LIB" ] || { echo "FAIL lib 없음: $LIB"; exit 1; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has3() { case "$1" in *"RAN $2"*) return 0;; esac; return 1; }   # 출력에 «RAN <칸>» 있나

# 칸 3개(ⓐⓑⓒ)를 도는 시험 절 시늉 — 실제 절 대신 «RAN <칸>» 1줄. $1 = FT_TEST_ONLY 값(「-」 = 환경 없음) · $2 = lib 경로(기본 정본)
run_cells() {
  (
    if [ "${1-}" = "-" ]; then unset FT_TEST_ONLY; else FT_TEST_ONLY="${1-}"; export FT_TEST_ONLY; fi
    . "${2:-$LIB}"
    ft_only ⓐ && echo "RAN ⓐ"
    ft_only ⓑ && echo "RAN ⓑ"
    ft_only ⓒ && echo "RAN ⓒ"
    ft_only_report; exit $?
  )
}

echo "== ⓐ 환경 없음 → 칸 3개 전부 돈다"
a1="$(run_cells -)"; rc1=$?
has3 "$a1" ⓐ && has3 "$a1" ⓑ && has3 "$a1" ⓒ && [ "$rc1" -eq 0 ] && ok "ⓐ FT_TEST_ONLY 없음 → ⓐⓑⓒ 전부 · rc=0" || bad "ⓐ 환경 없음인데 전부 안 돎(rc=$rc1) ← $a1"
a2="$(run_cells "")"; rc2=$?
has3 "$a2" ⓐ && has3 "$a2" ⓑ && has3 "$a2" ⓒ && [ "$rc2" -eq 0 ] && ok "  └ 빈 문자열도 같은 뜻(전부 · rc=0)" || bad "빈 문자열이 «전부 돈다» 가 아님(rc=$rc2) ← $a2"

echo "== ⓑ FT_TEST_ONLY=ⓑ → ⓑ 만 돈다"
b="$(run_cells ⓑ)"; rb=$?
has3 "$b" ⓑ && ! has3 "$b" ⓐ && ! has3 "$b" ⓒ && [ "$rb" -eq 0 ] && ok "ⓑ FT_TEST_ONLY=ⓑ → ⓑ 만 · rc=0" || bad "ⓑ 칸 가르기 실패(rc=$rb) ← $b"

echo "== ⓒ FT_TEST_ONLY=ⓐ,ⓒ → 둘만 돈다"
c="$(run_cells 'ⓐ,ⓒ')"; rc3=$?
has3 "$c" ⓐ && has3 "$c" ⓒ && ! has3 "$c" ⓑ && [ "$rc3" -eq 0 ] && ok "ⓒ FT_TEST_ONLY=ⓐ,ⓒ → ⓐ·ⓒ 만 · rc=0" || bad "ⓒ 쉼표 목록 실패(rc=$rc3) ← $c"
c2="$(run_cells ' ⓐ , ⓒ ')"; rc4=$?
has3 "$c2" ⓐ && has3 "$c2" ⓒ && ! has3 "$c2" ⓑ && [ "$rc4" -eq 0 ] && ok "  └ 값 양끝 공백은 무시" || bad "공백이 섞이면 못 고름(rc=$rc4) ← $c2"

echo "== ⓓ 없는 칸(오타) → ft_only_report BAD 1줄 + rc1"
d="$(run_cells ⓩ)"; rd=$?
n_bad="$(printf '%s\n' "$d" | grep -c '^BAD FT_TEST_ONLY=')"
[ "$rd" -eq 1 ] && [ "$n_bad" = 1 ] && ! has3 "$d" ⓐ && ! has3 "$d" ⓑ \
  && ok "ⓓ FT_TEST_ONLY=ⓩ → BAD 1줄 · 돈 칸 0 · rc=1" || bad "ⓓ 오타 방어 실패(rc=$rd · BAD=$n_bad) ← $d"
case "$d" in *"BAD FT_TEST_ONLY=ⓩ 에 맞는 칸 0"*) ok "  └ BAD 줄에 실제 값(ⓩ)이 그대로";; *) bad "BAD 줄에 값이 안 보임 ← $d";; esac

echo "== 변이 — ft_only 가 늘 rc0 이면 ⓑ 가 FAIL 해야 한다"
sed 's/^  return 1   # 목록에 없음$/  return 0   # 변이: 늘 rc0/' "$LIB" > "$T/mut_only.sh"
cmp -s "$T/mut_only.sh" "$LIB" && bad "변이가 lib 을 안 바꿈(앵커 어긋남)" || ok "변이 적용(ft_only 가 늘 rc0)"
m="$(run_cells ⓑ "$T/mut_only.sh")"
has3 "$m" ⓐ && ok "변이(늘 rc0) → ⓑ 실행에서 ⓐ 가 같이 돎 = 검출" || bad "변이(늘 rc0) 인데 ⓑ 실행에서 ⓐ 가 안 돎 — 칸 가르기가 무력"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
