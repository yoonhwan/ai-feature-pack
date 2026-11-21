#!/usr/bin/env bash
# test_merge_lines_replace_head_r2374.sh — r2374 · 같은 리포 판정문 «후보 조상» 검사 기준 = 자동 병합 전 PR head(FT_REPLACE_HEAD) · 자동 병합 C 가 아님
#   이 파일 = 반례 ②~⑩ + ⑤′(진짜 ft-merge-gate.sh 를 거친 env) + 변이 M3~M6(사본 · 변이마다 원본 대조 1회)   # ① · M1 · M2 = _land.sh(70초 상한으로 쪼갬)
#   임시 리포: origin(bare) · W(작업 clone) · LIVE(W 의 detached worktree = 승인 루트) · Q(다른 clone) — r2308 꼴 · 자동 병합 C = commit-tree -p S0 -p main · 실 gh·실 원격 0 · sleep 0
#   R2374_BIN = 기준판 대조용 bin 폴더(지정하면 변이·cmp 생략 · 기준판 Red = ⑤)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R2374_BIN:-$HERE/../bin}"; T0=$SECONDS
. "$HERE/_merge_fixture.sh"
unset FT_ROOT FT_REPLACE_ROOT FT_REPLACE_REMOTE FT_REPLACE_TARGET FT_REPLACE_HEAD
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r2374.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
NOTREAD="DENY 판정 불가 replace-ok 판정문 못 읽음"

# W: main X = a.txt 에 «KIND == (1, 16)» · S0 = M0 에서 딴 PR 가지 → main 병합 → 17 로 교체(PR head · 소실 1줄 · r2308 꼴)
mkrepo "$T"; printf '.fable-team/\n' >> "$W/.git/info/exclude"
printf 'l1\nl2\nl3\nKIND == (1, 16)\n' > "$W/a.txt"; cm "$W" "main adds 16"; X="$(sha "$W" HEAD)"
git -C "$W" push -q origin main main:ops/main-base; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b pr "$M0"; echo own > "$W/own.txt"; cm "$W" "pr own"; git -C "$W" merge -q --no-edit origin/main
printf 'l1\nl2\nl3\nKIND == (1, 17)\n' > "$W/a.txt"; cm "$W" "pr 17"; S0="$(sha "$W" HEAD)"
LIVE="$T/live"; git -C "$W" worktree add -q --detach "$LIVE" "$X" 2>/dev/null
mkdir -p "$W/.fable-team"; printf '%s\n' "$LIVE" > "$W/.fable-team/LIVE_ROOT"

dac() {  # dac <가지> <시작> <파일> <head> → 판정문 커밋 sha (가지 = 새로 만듦)
  git -C "$W" checkout -q -b "$1" "$2"; mkdir -p "$W/design"
  printf '# DA r2374\n\n## §2 수용\n\n판정: **APPROVE — 시험**\n\n```gate-replace\nhead %s\na.txt\tKIND == (1, 16)\t1\n```\n' "$4" > "$W/design/$3"
  cm "$W" "DA $3"; sha "$W" HEAD; git -C "$W" checkout -q pr
}
automerge() {  # automerge <PR head> → C(ft-merge-land docam 꼴 · -p head -p origin/main)
  local t; t="$(git -C "$W" merge-tree --write-tree "$1" origin/main)" && git -C "$W" commit-tree "${t%%$'\n'*}" -p "$1" -p "$(sha "$W" origin/main)" -m "auto-merge main"
}
GB="$BIN/ft-merge-gate.sh"; LN="$BIN/ft_merge_lines.py"
gate() { out="$(cd "$W" && bash "$GB" "$@" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?; }
hgate() { local h="$1"; shift; out="$(cd "$W" && FT_REPLACE_HEAD="$h" bash "$GB" "$@" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?; }

# ⑧ 먼저(main 을 움직이기 전): 자동 병합 없음 · 판정문 = ops/main-base 위 새 커밋 · FT_REPLACE_HEAD = s → 통과(r2308 ① 꼴)
D8="$(dac da8 "$X" DA8.md "$S0")"; git -C "$W" push -q origin da8:ops/main-base; git -C "$W" fetch -q origin
S1=$SECONDS
hgate "$S0" "$S0" --replace-ok "design/DA8.md@$D8#§2"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [[ "$out" == *"REPLACE-OK 1줄"* ]]
ck "⑧ 자동 병합 없음 · FT_REPLACE_HEAD = s · 판정문 = 보호 줄기 위 · s 조상 아님 → ALLOW REPLACE-OK(r2308 ① 꼴)" $?

# main 이 앞섬: 판정문 D = origin/main 위 새 커밋(S0 조상 아님 · PR 10351 꼴) → C = 자동 병합(main 이 C 의 부모라 D 는 C 조상)
D="$(dac da "$X" DA.md "$S0")"; git -C "$W" push -q origin da:main; git -C "$W" fetch -q origin
C="$(automerge "$S0")"
D6P="$(dac pr6 "$S0" DA6.md "$S0")"; S6="$D6P"; C6="$(automerge "$S6")"           # ⑥ 판정문이 PR head 안(자기 승인)
D7="$(dac docs/x "$X" DA7.md "$S0")"; git -C "$W" push -q origin docs/x            # ⑦ 보호 줄기 밖(docs/* 가지)
git -C "$W" checkout -q -b other "$X"; echo z > "$W/z.txt"; cm "$W" "other"; Z="$(sha "$W" HEAD)"; git -C "$W" checkout -q pr   # ③ C 조상 아님

c2() { gate "$C" --replace-ok "design/DA.md@$D#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"* ]] && [[ "$out" == *"— 후보 조상 · 판정문을 후보 밖 보호 줄기 새 커밋으로 다시 올림"* ]]; }
c3() { hgate "$Z" "$C" --replace-ok "design/DA.md@$D#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"*"— 후보 머리 FT_REPLACE_HEAD 가 후보 조상 아님"* ]] && [[ "$out" != *"후보 조상 ·"* ]]; }
c4() { local v; for v in 0000000000000000000000000000000000000000 xyz --all "${S0:0:10}"; do
    hgate "$v" "$C" --replace-ok "design/DA.md@$D#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"*"— 후보 머리 판정 불가"* ]] && [[ "$out" != *"후보 조상 ·"* ]] || return 1; done; }
c5() { out="$(cd "$W" && FT_REPLACE_HEAD="$S0" FT_REPLACE_ROOT="$LIVE" FT_REPLACE_REMOTE=origin FT_REPLACE_TARGET=main python3 -I "$LN" "$W" "$(sha "$W" origin/main)" "$C" --replace-ok "design/DA.md@$D#§2" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [[ "$out" == PASS* ]] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; }
c5g() { hgate "$S0" "$C" --replace-ok "design/DA.md@$D#§2"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; }
c6() { hgate "$S6" "$C6" --replace-ok "design/DA6.md@$D6P#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"*"— 후보 조상 · 판정문을 후보 밖 보호 줄기 새 커밋으로 다시 올림"* ]]; }
c7() { hgate "$S0" "$C" --replace-ok "design/DA7.md@$D7#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"*"— 보호 줄기 조상 아님 · fetch 뒤 다시"* ]]; }
# ⑨ 다른 리포 Q(승인 루트 = W 의 LIVE) · C 를 origin 에 올려 Q 로 받음 · 판정문 = W 로컬 가지(보호 줄기 아님) → env 있든 없든 같은 결과(same_repo_root 부름 0)
git -C "$W" push -q origin "$C:refs/heads/cand" 2>/dev/null; Q="$T/q"; git clone -q "$ORIGIN" "$Q" 2>/dev/null
printf '.fable-team/\n' >> "$Q/.git/info/exclude"; mkdir -p "$Q/.fable-team"; printf '%s\n' "$LIVE" > "$Q/.fable-team/LIVE_ROOT"
c9() { local a; a="$(cd "$Q" && bash "$GB" "$C" --repo "$Q" --base-head-file "$T/none" --replace-ok "design/DA7.md@$D7#§2" 2>&1)"
  out="$(cd "$Q" && FT_REPLACE_HEAD=xyz bash "$GB" "$C" --repo "$Q" --base-head-file "$T/none" --replace-ok "design/DA7.md@$D7#§2" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 1줄"* ]] && [ "$out" = "$a" ]; }
c10() { out="$(R2308_BIN="$1" bash "$HERE/test_merge_gate_replace_ok_same_repo_r2308.sh" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == *"ALL PASS"* ]]; }

gate "$C"; [ "$rc" = 1 ] && [[ "$out" == *"DENY main 이 더한 줄을 지움"* ]]; ck "전제: C 에 --replace-ok 없이 DENY(소실 1줄)" $?
c2; ck "② C · 판정문 = main 위 · FT_REPLACE_HEAD 없음 → Fail «후보 조상»(옛 부름 보존)" $?
c3; ck "③ FT_REPLACE_HEAD = C 조상 아닌 커밋 → Fail «후보 머리 … 후보 조상 아님» · 판정문 읽기 0" $?
c4; ck "④ FT_REPLACE_HEAD = 없는 40hex · xyz · --all · 짧은 sha → Fail «후보 머리 판정 불가» · 판정문 읽기 0" $?
c5; ck "⑤ C · 판정문 = main 위(S0 조상 아님) · FT_REPLACE_HEAD=S0 → ft_merge_lines PASS REPLACE-OK(기준판 Red)" $?
c5g; ck "⑤′ 같은 사례를 진짜 ft-merge-gate.sh 에 env 앞 대입으로 → ALLOW REPLACE-OK(env 가 python 까지 닿음)" $?
c6; ck "⑥ 판정문이 PR head 안(S0 조상) · FT_REPLACE_HEAD=PR head → Fail «후보 조상» 그대로" $?
c7; ck "⑦ 판정문 = 보호 줄기 밖 · FT_REPLACE_HEAD=S0 → Fail «보호 줄기 조상 아님» 그대로" $?
c9; ck "⑨ 다른 리포 판정문 → FT_REPLACE_HEAD=xyz 여도 env 없는 부름과 같은 글자 · ALLOW(same_repo_root 부름 0)" $?
S2=$SECONDS
c10 "$BIN"; ck "⑩ r2308 시험 ①~⑦ 그대로 ALL PASS(이 bin)" $?
S3=$SECONDS

if [ -z "${R2374_BIN:-}" ]; then   # 변이(사본) — 변이마다 원본으로 같은 사례 1회 더(반대 결과)
  mut() { rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 - "$T/m/ft_merge_lines.py" "$1" "$2" <<'PY' || echo "FAIL 변이 패치 자리 없음"
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]; s = p.read_text()
assert old in s, old; p.write_text(s.replace(old, new, 1))
PY
  }
  mg() { local g="$GB" l="$LN"; GB="$T/m/ft-merge-gate.sh"; LN="$T/m/ft_merge_lines.py"; "$@"; local r=$?; GB="$g"; LN="$l"; return $r; }
  mut '        if k == 1:' '        if False:'; mg c3; [ $? != 0 ]; ck "M3 h ≠ s 일 때 anc(h, s) 검사 지움 → ③ FAIL(잡힘)" $?
  c3; ck "M3 원본 대조 → ③ 통과" $?
  mut '        if k != 0:' '        if False:'; mg c4; [ $? != 0 ]; ck "M4 K2 판정 불가를 통과로 셈 → ④ FAIL(잡힘)" $?
  c4; ck "M4 원본 대조 → ④ 통과" $?
  mut '.strip() or s   # r2374 K2' '.strip() or "-"   # r2374 K2'; mg c2; [ $? != 0 ]; ck "M5 FT_REPLACE_HEAD 빈 값이면 Fail → ② 글자 FAIL(잡힘)" $?
  c10 "$T/m"; [ $? != 0 ]; ck "M5 → ⑩ FAIL(잡힘)" $?
  c2; ck "M5 원본 대조 → ② 통과" $?
  mut 'r = anc(sha, h)' 'r = anc(sha, s)'; mg c5; [ $? != 0 ]; ck "M6 anc(sha, h) 를 anc(sha, s) 로 되돌림 → ⑤ FAIL(잡힘)" $?
  c5; ck "M6 원본 대조 → ⑤ 통과" $?
  cmp -s "$BIN/ft_merge_lines.py" "$HERE/../kit/fable-team/bin/ft_merge_lines.py"; ck "bin·kit cmp0 ft_merge_lines.py" $?
fi
echo "단계별 초: ②~⑨ $((S2 - S1)) · ⑩ $((S3 - S2)) · 변이 $((SECONDS - S3)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
