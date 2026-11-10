#!/usr/bin/env bash
# test_ft_land.sh — C9-기계 시험: ft-land.sh 후보 생성 3 시나리오 (①ff ②main 이동→merge-tree ③S10 재현→abort)
# mktemp 저장소(bare origin + clone)만 쓴다 — 실제 리포·origin 은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LAND="$HERE/../../harness/bin/ft-land.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
. "$HERE/lib/fake_resource_env.sh"; fake_comm_root "$T/root" || { echo "FAIL fake_comm_root"; exit 1; }   # r537: ft-land → ft-sheet-events 가 공용 루트를 푼다(묶음 ③ · 임시 루트)
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# mk <이름> — origin(bare) + work clone, main 에 base.txt·keep.txt 1커밋
mk() {
  git init -q --bare -b main "$T/$1.origin"
  git clone -q "$T/$1.origin" "$T/$1" 2>/dev/null
  git -C "$T/$1" checkout -q -b main
  echo base > "$T/$1/base.txt"; echo keep > "$T/$1/keep.txt"
  git -C "$T/$1" add -A; git -C "$T/$1" commit -qm base; git -C "$T/$1" push -q origin main
}
heads() { git -C "$1" for-each-ref refs/heads; }

bash -n "$LAND" && ok "bash -n" || bad "bash -n"
grep -nE 'git[^#]*\bpush\b' "$LAND" | grep -vE '^[0-9]+:\s*#' >/dev/null && bad "ft-land.sh 에 push 호출이 있음" || ok "push 호출 0 (주석 제외)"
bash "$LAND" --push >/dev/null 2>&1; [ $? -eq 2 ] && ok "--push usage 거부(rc=2)" || bad "--push 거부 안 됨"

# ① ff 가능 — main 불변, feat 가 앞섬
mk s1; R="$T/s1"
git -C "$R" checkout -q -b feat/x; echo f > "$R/f.txt"; git -C "$R" add -A; git -C "$R" commit -qm feat
before="$(heads "$R")"
out="$(bash "$LAND" --repo "$R" --feat feat/x 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "① rc=0" || bad "① rc=$rc: $out"
echo "$out" | grep -q 'mode=ff' && ok "① mode=ff" || bad "① mode: $out"
cand="$(echo "$out" | sed -n 's/.*CANDIDATE=\([0-9a-f]*\).*/\1/p')"
[ "$cand" = "$(git -C "$R" rev-parse feat/x)" ] && ok "① 후보 = feat tip" || bad "① 후보 sha 불일치"
[ "$before" = "$(heads "$R")" ] && ok "① refs/heads 변경 0" || bad "① 브랜치가 변경됨"

# ② main 이 움직임 — origin main 에 m.txt 추가, feat 는 f.txt 추가 → merge 후보에 둘 다 있어야 함
mk s2; R="$T/s2"
git -C "$R" checkout -q -b feat/y; echo f > "$R/f.txt"; git -C "$R" add -A; git -C "$R" commit -qm feat
git -C "$R" checkout -q main; echo m > "$R/m.txt"; git -C "$R" add -A; git -C "$R" commit -qm main-moved; git -C "$R" push -q origin main
git -C "$R" reset -q --hard HEAD~1   # 로컬 main 은 뒤처진 채 — 대상은 fetch 한 origin/main 이어야 한다
before="$(heads "$R")"
out="$(bash "$LAND" --repo "$R" --feat feat/y 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "② rc=0" || bad "② rc=$rc: $out"
echo "$out" | grep -q 'mode=merge' && ok "② mode=merge" || bad "② mode: $out"
cand="$(echo "$out" | sed -n 's/.*CANDIDATE=\([0-9a-f]*\).*/\1/p')"; oid="$(echo "$out" | sed -n 's/.*OID=\([0-9a-f]*\).*/\1/p')"
[ "$(git -C "$R" rev-parse "$cand^{tree}")" = "$oid" ] && ok "② 후보 tree == OID" || bad "② tree != OID"
files="$(git -C "$R" ls-tree -r --name-only "$cand" | tr '\n' ' ')"
[ "$files" = "base.txt f.txt keep.txt m.txt " ] && ok "② main 의 m.txt 와 feat 의 f.txt 모두 보존" || bad "② 후보 파일: $files"
[ "$(git -C "$R" rev-list --parents -n1 "$cand" | wc -w | tr -d ' ')" = 3 ] && ok "② 후보 = 부모 2(T·feat)" || bad "② 부모 수"
[ "$before" = "$(heads "$R")" ] && ok "② refs/heads 변경 0" || bad "② 브랜치가 변경됨"

# ③ S10 재현 — 후보를 feat 트리로 만들면 main 의 새 파일(m.txt)이 사라진다 → abort 해야 한다
out="$(FT_LAND_INJECT_S10=1 bash "$LAND" --repo "$R" --feat feat/y 2>&1)"; rc=$?
[ $rc -eq 1 ] && ok "③ S10 주입 → rc=1" || bad "③ rc=$rc (abort 해야 함): $out"
echo "$out" | grep -q 'ABORT 후보 tree != 검사 tree OID' && ok "③ ABORT 사유 = 후보 tree != OID" || bad "③ 사유: $out"
echo "$out" | grep -q 'LAND-CANDIDATE' && bad "③ abort 인데 후보가 출력됨" || ok "③ 후보 출력 0"

# 추가 가드: 충돌이면 abort
mk s4; R="$T/s4"
git -C "$R" checkout -q -b feat/z; echo A > "$R/base.txt"; git -C "$R" commit -qam feat
git -C "$R" checkout -q main; echo B > "$R/base.txt"; git -C "$R" commit -qam main-moved; git -C "$R" push -q origin main
out="$(bash "$LAND" --repo "$R" --feat feat/z 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'ABORT merge-tree 충돌' && ok "충돌 → abort(rc=1)" || bad "충돌 처리 rc=$rc: $out"

echo "---"; [ $fail -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit $((fail>0))
