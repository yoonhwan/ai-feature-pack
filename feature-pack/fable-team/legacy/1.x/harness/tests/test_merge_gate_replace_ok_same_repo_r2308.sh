#!/usr/bin/env bash
# test_merge_gate_replace_ok_same_repo_r2308.sh — r2308 · 판정문 리포 = 후보 리포(BYZ PR 꼴)여도 «보호 줄기 조상 ∧ 후보 조상 아님» 판정문은 --replace-ok 로 읽는다
#   반례 ①~⑦ (카드 design/harness/indices/*/r2308-merge-replace-ok-same-repo.md) + 변이 M1~M4(사본 · 변이마다 원본 대조 1회)
#   임시 리포: origin(bare) · W(작업 clone) · LIVE(W 의 detached worktree = 승인 루트) · Q(다른 clone = 다른 리포) · 실 gh·실 원격 0 · sleep 0 · 70초 안
#   R2308_BIN = 기준판 대조용 bin 폴더(지정하면 변이·cmp 생략)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R2308_BIN:-$HERE/../bin}"; T0=$SECONDS
. "$HERE/_merge_fixture.sh"
unset FT_ROOT FT_REPLACE_ROOT FT_REPLACE_REMOTE FT_REPLACE_TARGET
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r2308.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
NOTREAD="DENY 판정 불가 replace-ok 판정문 못 읽음"

# W: main 이 a.txt 에 «KIND == (1, 16)» 을 더함(X) → main·ops/main-base 둘 다 X · PR 가지 = M0 에서 자기 파일 → main 병합 → 17 로 교체(S)
mkrepo "$T"; printf '.fable-team/\n' >> "$W/.git/info/exclude"
printf 'l1\nl2\nl3\nKIND == (1, 16)\n' > "$W/a.txt"; cm "$W" "main adds 16"; X="$(sha "$W" HEAD)"
git -C "$W" push -q origin main main:ops/main-base; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b pr "$M0"; echo own > "$W/own.txt"; cm "$W" "pr own"; git -C "$W" merge -q --no-edit origin/main
printf 'l1\nl2\nl3\nKIND == (1, 17)\n' > "$W/a.txt"; cm "$W" "pr 17"; S="$(sha "$W" HEAD)"; git -C "$W" push -q origin pr
LIVE="$T/live"; git -C "$W" worktree add -q --detach "$LIVE" "$X" 2>/dev/null
mkdir -p "$W/.fable-team"; printf '%s\n' "$LIVE" > "$W/.fable-team/LIVE_ROOT"

dac() {  # dac <가지> <시작> <파일> <head> → 판정문 커밋 sha (가지 = 새로 만듦)
  git -C "$W" checkout -q -b "$1" "$2"; mkdir -p "$W/design"
  printf '# DA r2308\n\n## §2 수용\n\n판정: **APPROVE — 시험**\n\n```gate-replace\nhead %s\na.txt\tKIND == (1, 16)\t1\n```\n' "$4" > "$W/design/$3"
  cm "$W" "DA $3"; sha "$W" HEAD; git -C "$W" checkout -q pr
}
GB="$BIN/ft-merge-gate.sh"
gate() { out="$(cd "$W" && bash "$GB" "$@" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?; }

D1="$(dac da1 "$X" DA1.md "$S")"; git -C "$W" push -q origin da1:ops/main-base   # 보호 줄기(ops/main-base) 위 · S 조상 아님
D3="$(dac pr3 "$S" DA3.md "$S")"                                                  # 후보 가지에만(S3 = D3 의 조상 = 자기)
D4="$(dac docs/x "$X" DA4.md "$S")"; git -C "$W" push -q origin docs/x             # docs/* 가지에만(PR 9703 꼴)
git -C "$W" checkout -q -b pr5 "$S"; git -C "$W" merge -q --no-edit origin/ops/main-base 2>/dev/null || git -C "$W" merge -q --no-edit da1; S5="$(sha "$W" HEAD)"; git -C "$W" checkout -q pr
D6="$(dac side6 "$X" DA6.md "$S")"                                                 # W 로컬 가지에만(보호 줄기 아님)
git -C "$W" fetch -q origin

c1() { gate "$S" --replace-ok "design/DA1.md@$D1#§2"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; }
c3() { gate "$D3" --replace-ok "design/DA3.md@$D3#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"* ]] && [[ "$out" == *"— 후보 조상"* ]]; }
c4() { gate "$S" --replace-ok "design/DA4.md@$D4#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"* ]] && [[ "$out" == *"— 보호 줄기 조상 아님"* ]]; }
c5() { gate "$S5" --replace-ok "design/DA1.md@$D1#§2"; [ "$rc" = 1 ] && [[ "$out" == "$NOTREAD"* ]] && [[ "$out" == *"— 후보 조상"* ]]; }
# ⑥ 다른 리포: Q(다른 clone · 승인 루트 = W 의 LIVE) · 판정문 = W 로컬 가지(보호 줄기 아님) → 지금처럼 읽힘
Q="$T/q"; git clone -q "$ORIGIN" "$Q" 2>/dev/null; printf '.fable-team/\n' >> "$Q/.git/info/exclude"; mkdir -p "$Q/.fable-team"; printf '%s\n' "$LIVE" > "$Q/.fable-team/LIVE_ROOT"
c6() { out="$(cd "$Q" && bash "$GB" "$S" --repo "$Q" --base-head-file "$T/none" --replace-ok "design/DA6.md@$D6#§2" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; }
# ⑦ FT_ROOT 채움(= 후보 리포 자신) → 지금처럼 그 리포에서 읽음 · 조상 검사 0(보호 줄기 아닌 판정문도 읽힘)
c7() { out="$(cd "$W" && FT_ROOT="$W" bash "$GB" "$S" --repo "$W" --base-head-file "$T/none" --replace-ok "design/DA6.md@$D6#§2" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; }

gate "$S"; [ "$rc" = 1 ] && [[ "$out" == *"DENY main 이 더한 줄을 지움"* ]]; ck "전제: --replace-ok 없이 DENY(소실 1줄)" $?
c1; ck "① 같은 리포 · 판정문 = origin/ops/main-base 조상 · S 조상 아님 → ALLOW REPLACE-OK(기준판 = 못 읽음 = Red)" $?
c3; ck "③ 판정문이 후보 가지에만(S 조상) → 못 읽음 — 후보 조상(X1 회귀)" $?
gate "$D3" --replace-ok "design/DA3.md@$D3#§2"; [[ "$out" == *"판정문을 후보 밖 보호 줄기 새 커밋으로 다시 올림"* ]]; ck "③ 꼬리 뒤 «다시 올림» 1구" $?
c4; ck "④ 판정문이 docs/* 가지에만 → 못 읽음 — 보호 줄기 조상 아님" $?
[[ "$out" == *"fetch 뒤 다시"* ]]; ck "④ 꼬리 뒤 «fetch 뒤 다시» 1구" $?
c5; ck "⑤ 보호 줄기 조상이면서 S 조상 → 못 읽음 — 후보 조상(막는 쪽)" $?
c6; ck "⑥ 다른 리포 · 아무 가지 판정문 → 지금처럼 읽힘(회귀)" $?
c7; ck "⑦ FT_ROOT 채움 → 그 리포에서 읽음 · 조상 검사 0(회귀)" $?
echo "INFO 게이트 사례 $((SECONDS - T0))s"

if [ -z "${R2308_BIN:-}" ]; then   # 변이(사본) — 변이마다 원본으로 같은 사례 1회 더(반대 결과)
  mut() { rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 - "$T/m/ft_merge_lines.py" "$1" "$2" <<'PY' || echo "FAIL 변이 패치 자리 없음"
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]; s = p.read_text()
assert old in s, old; p.write_text(s.replace(old, new, 1))
PY
  }
  SAME='        if cd[0] and cd[0] == cd[1]:   # r2308 A1'$'\n''            root = same_repo_root(alt, sha, s, why)'
  mut "$SAME"$'\n' ''; GB="$T/m/ft-merge-gate.sh" c1; [ $? != 0 ]; ck "M1 같은 리포 허용 줄 지움 → ① FAIL(잡힘)" $?
  c1; ck "M1 원본 대조 → ① 통과" $?
  mut 'if r == 0:' 'if False:'; GB="$T/m/ft-merge-gate.sh" c3; [ $? != 0 ]; ck "M2 «S 조상 아님» 검사 지움 → ③ FAIL(잡힘)" $?
  c3; ck "M2 원본 대조 → ③ 통과" $?
  mut '"refs/remotes/%s/%s" % (rem, b)) == 0 for b in ("main", "ops/main-base")' 'b) == 0 for b in subprocess.run(["git", "-C", root, "for-each-ref", "--format=%(refname)"], capture_output=True, text=True).stdout.split()'; GB="$T/m/ft-merge-gate.sh" c4; [ $? != 0 ]; ck "M3 보호 줄기 = 아무 ref(docs/* 포함) → ④ FAIL(잡힘)" $?
  c4; ck "M3 원본 대조 → ④ 통과" $?
  mut 'root = alt if cd[0] and cd[0] != cd[1] else ""' 'root = same_repo_root(alt, sha, s, why) if cd[0] and cd[0] != cd[1] else ""'; GB="$T/m/ft-merge-gate.sh" c6; [ $? != 0 ]; ck "M4 common-dir 다를 때도 조상 검사 → ⑥ FAIL(잡힘)" $?
  c6; ck "M4 원본 대조 → ⑥ 통과" $?
  echo "INFO 변이 $((SECONDS - T0))s"
  cmp -s "$BIN/ft_merge_lines.py" "$HERE/../kit/fable-team/bin/ft_merge_lines.py"; ck "bin·kit cmp0 ft_merge_lines.py" $?
fi
# ② 마지막(main 을 움직인다): 대상 = ops/main-base(= S5 가 품은 D1) · 판정문 = origin/main 위 새 커밋(S5 조상 아님) → ALLOW
D2="$(dac da2 "$X" DA2.md "$S5")"; git -C "$W" push -q origin da2:main; git -C "$W" fetch -q origin
gate "$S5" --target ops/main-base --replace-ok "design/DA2.md@$D2#§2"; [ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 1줄"* ]]; ck "② 같은 리포 · 판정문 = origin/main 조상 → ALLOW(기준판 = 못 읽음 = Red)" $?
echo "단계별 초: 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
