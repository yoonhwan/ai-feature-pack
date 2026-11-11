#!/usr/bin/env bash
# test_press_evidence_ops_canon_r1697.sh — r1697: 목록이 «원래 없는» 대상 가지(ops/main-base 꼴)는 정본 main 목록으로 press 검사를 판정한다.
#   ⓐ ops 대상 · head·ops 둘 다 목록 없음 · 음성 경로 변경 0 → press=out rc0 + «목록 출처 = 정본 main» 1줄(지금 = 판정 불가 REJECT)
#   ⓑ 같은 꼴에서 head 가 정본 목록의 음성 경로를 바꿈 → 대상 안 · 묶음 없으면 지금 main 대상과 같은 거절 문구
#   ⓒ main 대상 · head 가 목록 지움 → 판정 불가(지금과 같다) ⓓ ops 에 목록 있음 · head 가 지움 → 판정 불가(지금과 같다)
#   ⓔ canon(main) ref 없음 → 지금과 같은 판정 불가 ⓕ main 대상 · 목록 있음 → 출력·rc 지금과 같다(출처 줄 0)
# 전부 mktemp(임시 bare 원격 + clone) · 실 리포·실 gh·실 push 0 · sleep 0 · 사례 70초
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../../harness/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"
U=git@github.com:SecondWindStudio/byz-agents.git
git -C "$W" config remote.origin.url "$U"; git -C "$W" config url."$ORIGIN".insteadOf "$U"
VP=docs/rules/press_voice_paths.md
printf '# press\n- 참고: 이 파일은 시험용이다.\n' > "$T/empty-seed"   # (사용 안 함)
# main = 목록 있음(정본) · 목록 신설 커밋의 «부모»(BASE)에서 ops 를 가른다
mkdir -p "$W/docs/rules"; printf '# 음성 경로 정본\n\n## 목록\n- `clients/web/src/domains/realtime/**`\n' > "$W/$VP"
cm "$W" "목록 신설"; MAINL="$(sha "$W" HEAD)"; printf '%s\n' "$MAINL" > "$T/MainList"
git -C "$W" push -q origin main
BASE="$(sha "$W" HEAD~1)"
git -C "$W" checkout -q -b ops/main-base "$BASE"; mkdir -p "$W/gateway"; printf 'gw\n' > "$W/gateway/app.py"; cm "$W" "ops work"
git -C "$W" push -q origin ops/main-base; OPS="$(sha "$W" HEAD)"
head_() { git -C "$W" checkout -q -B "$1" "$2"; }
P="$BIN/press_evidence_land.py"
pl() { out="$(cd "$T" && FT_ROOT="$T" python3 "$P" land --repo "$W" --remote origin --main "$1" --head "$2" --landing "$3" --pr 1 --root "$T" 2>&1)"; rc=$?; }

# ⓐ ops 대상 · 양쪽 목록 없음 · 음성 경로 변경 0 → press=out + 출처 줄
head_ pr-a origin/ops/main-base; printf 'x\n' > "$W/other.txt"; cm "$W" "other only"; HA="$(sha "$W" HEAD)"
pl origin/ops/main-base "$HA" "$(sha "$W" HEAD)"
{ [ "$rc" = 0 ] && [[ "$out" == *"press=out"* ]] && [[ "$out" == *"음성 경로 목록 출처 = 정본 main"* ]]; } \
  && ck "ⓐ ops 대상 · 목록 없는 가지 → press=out rc0 + «목록 출처 = 정본 main»" 0 \
  || ck "ⓐ ops 대상 · 목록 없는 가지 → press=out rc0 + «목록 출처 = 정본 main»" 1
# ⓑ 같은 꼴에서 head 가 정본 목록의 음성 경로를 바꿈 → 대상 안(거절 문구는 main 대상과 같다)
head_ pr-b origin/ops/main-base; mkdir -p "$W/clients/web/src/domains/realtime"; printf 'v\n' > "$W/clients/web/src/domains/realtime/x.ts"; cm "$W" "voice path"
HB="$(sha "$W" HEAD)"
pl origin/ops/main-base "$HB" "$(sha "$W" HEAD)"
A_OUT="$out"; A_RC="$rc"
# 같은 변경을 main 대상으로(대조군) — 목록이 있으니 지금 동작
head_ pr-b2 origin/main; git -C "$W" checkout -q -B pr-b2 origin/main; mkdir -p "$W/clients/web/src/domains/realtime"; printf 'v\n' > "$W/clients/web/src/domains/realtime/y.ts"; cm "$W" "voice path"; HB2="$(sha "$W" HEAD)"
pl origin/main "$HB2" "$(sha "$W" HEAD)"; B_OUT="$out"
{ [ "$A_RC" = 1 ] && [[ "$A_OUT" == *"press 증거"* ]] && [[ "$A_OUT" == *"음성 경로 목록 출처 = 정본 main"* ]]; } \
  && ck "ⓑ 정본 목록으로도 음성 경로는 대상 → 묶음 없음 거절(목록 출처 줄 유지)" 0 \
  || ck "ⓑ 정본 목록으로도 음성 경로는 대상 → 묶음 없음 거절(목록 출처 줄 유지)" 1
# ⓒ main 대상 · head 가 목록 지움 → 판정 불가(지금과 같다)
head_ pr-c origin/main; git -C "$W" rm -q "$VP"; cm "$W" "목록 삭제"; HC="$(sha "$W" HEAD)"
pl origin/main "$HC" "$HC"
{ [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 없음"* ]] && [[ "$out" != *"목록 출처"* ]]; } \
  && ck "ⓒ main 대상 · 목록 지움 → 판정 불가(지금과 같다)" 0 || ck "ⓒ main 대상 · 목록 지움 → 판정 불가(지금과 같다)" 1
# ⓓ ops 에 목록 있음 · head 가 지움 → 판정 불가(지금과 같다)
git -C "$W" checkout -q -B ops2 origin/ops/main-base; mkdir -p "$W/docs/rules"; printf '# 음성 경로 정본\n\n## 목록\n- `clients/web/src/domains/realtime/**`\n' > "$W/$VP"; cm "$W" "ops 목록 신설"; git -C "$W" push -q origin ops2; git -C "$W" fetch -q origin
head_ pr-d origin/ops2; git -C "$W" rm -q "$VP"; cm "$W" "ops 목록 삭제"; HD="$(sha "$W" HEAD)"
pl origin/ops2 "$HD" "$HD"
{ [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 없음"* ]]; } \
  && ck "ⓓ 목록 있던 가지에서 지운 PR → 판정 불가(지금과 같다)" 0 || ck "ⓓ 목록 있던 가지에서 지운 PR → 판정 불가(지금과 같다)" 1
# ⓔ canon(main) ref 없음 → 지금과 같은 판정 불가 · 예외 0
git -C "$W" update-ref -d refs/remotes/origin/main 2>/dev/null; git -C "$W" update-ref refs/remotes/origin/main "$BASE" 2>/dev/null
pl origin/ops/main-base "$HA" "$HA"
{ [ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 없음"* ]]; } \
  && ck "ⓔ canon(main) 에 목록 없음 → 판정 불가(지금 동작)" 0 || ck "ⓔ canon(main) 에 목록 없음 → 판정 불가(지금 동작)" 1
git -C "$W" update-ref refs/remotes/origin/main "$MAINL"
# ⓕ main 대상 · 목록 있음 → 출력·rc 지금과 같다(출처 줄 0)
head_ pr-f origin/main; printf 'f\n' > "$W/f.txt"; cm "$W" "f only"; HF="$(sha "$W" HEAD)"
pl origin/main "$HF" "$HF"
{ [ "$rc" = 0 ] && [[ "$out" == *"press=out"* ]] && [[ "$out" != *"목록 출처"* ]]; } \
  && ck "ⓕ main 대상 · 목록 있음 → press=out · 출처 줄 0" 0 || ck "ⓕ main 대상 · 목록 있음 → press=out · 출처 줄 0" 1
# ⓖ 회귀 — press 시험 4파일 FAIL 줄이 앞 판과 같다 · bin·kit cmp
if [ -n "${FT_R1697_FULL:-}" ]; then   # 4파일 = 58초(부하) — 사례 70초 예산 밖이라 기본은 끄고 보고 때 따로 돌린다
  n=0; for t in test_press_evidence_gate_r1230.sh test_press_evidence_gate_b_r1230.sh test_press_evidence_poller_parts_r1268.sh test_press_evidence_push_budget_r1254.sh; do
    m="$(timeout 70 bash "$HERE/$t" 2>&1 | grep '^FAIL' | grep -vc '기준판을 못 꺼냄')"; n=$((n+m)); done
  [ "$n" = 0 ] && ck "ⓖ 회귀 press 시험 4파일 — 새 FAIL 0(«기준판을 못 꺼냄» 은 앞 판에도 있는 환경 몫)" 0 || ck "ⓖ 회귀 press 시험 새 FAIL $n" 1
else ck "ⓖ 회귀 press 시험 4파일 — FT_R1697_FULL=1 일 때만(58초 · 보고에서 따로 비교)" 0; fi
for f in press_evidence_verify.py press_evidence_land.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && ck "ⓖ bin·kit cmp 0 $f" 0 || ck "ⓖ bin·kit cmp 0 $f" 1; done
# ── 변이 3종(사본에서만 · 실 bin 불변) ──
mkx() {  # mkx <이름> <old> <new> → 사본 bin 경로(verify 만 고침 · land 는 그 사본을 import)
  local d="$T/m-$1"; mkdir -p "$d"; cp "$BIN/press_evidence_verify.py" "$BIN/press_evidence_land.py" "$BIN/press_evidence_parts.py" "$d/" 2>/dev/null
  python3 - "$d/press_evidence_verify.py" "$2" "$3" <<'PY'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert o in s, "변이 대상 없음: " + o[:60]
open(p, "w", encoding="utf-8").write(s.replace(o, n, 1))
PY
  printf '%s\n' "$d"; }
plx() { out="$(cd "$T" && FT_ROOT="$T" python3 "$1/press_evidence_land.py" land --repo "$W" --remote origin --main "$2" --head "$3" --landing "$3" --pr 1 --root "$T" 2>&1)"; rc=$?; }
git -C "$W" update-ref refs/remotes/origin/main "$MAINL"
CX="$(mkx m1 'if not (tgt and patterns(repo, tgt)) and canon and canon != tgt and patterns(repo, canon):' 'if False:')"
plx "$CX" origin/ops/main-base "$HA"; { [ "$rc" = 1 ] && [[ "$out" == *"판정 불가"* ]]; } && ck "M1 canon 갈래 삭제 → ⓐ FAIL(검출됨)" 0 || ck "M1 canon 갈래 삭제 → ⓐ FAIL(검출됨)" 1
CX="$(mkx m2 'if not (tgt and patterns(repo, tgt)) and canon and canon != tgt and patterns(repo, canon):' 'if canon and canon != tgt and patterns(repo, canon):')"
plx "$CX" origin/ops2 "$HD"; { [ "$rc" = 0 ]; } && ck "M2 «대상 가지에 목록 있으면 거절» 삭제 → ⓓ FAIL(검출됨)" 0 || ck "M2 «대상 가지에 목록 있으면 거절» 삭제 → ⓓ FAIL(검출됨)" 1
CX="$(mkx m3 'if not (tgt and patterns(repo, tgt)) and canon and canon != tgt and patterns(repo, canon):' 'if canon and patterns(repo, canon):')"   # M3: D1 가드·canon≠대상 가드 둘 다 없애 «canon=main 도 사용»
plx "$CX" origin/main "$HC"; { [ "$rc" = 0 ]; } && ck "M3 canon = main 일 때도 canon 사용 → ⓒ FAIL(검출됨)" 0 || ck "M3 canon = main 일 때도 canon 사용 → ⓒ FAIL(검출됨)" 1
MUT_N=1; [ -z "$(git -C "$W" diff --name-only)" ] || MUT_N=0; ck "변이는 사본에서만(실 리포 작업본 무변경)" $((1-MUT_N))
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
