#!/usr/bin/env bash
# test_nano_feat_remote_ref.sh — R22: 나노 닫기 cherry·증거 게이트가 원격 추적 ref(origin/<feat>)를 받는가.
# mktemp 리포(bare 원격 + 클론)만 쓴다 — 실제 리포·네트워크 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
# expect <이름> <기대 rc> <출력에 있어야 할 문구> -- <명령...>
expect() {
  local name="$1" want="$2" pat="$3"; shift 4
  local out rc; out="$("$@" 2>&1)"; rc=$?
  echo "  $out" | head -3
  if [ "$rc" -eq "$want" ] && printf '%s' "$out" | grep -qF -- "$pat"; then ok "$name"; else bad "$name (rc=$rc want=$want pat=$pat)"; fi
}

git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && git checkout -q -b main 2>/dev/null; mkdir -p src design; echo a > src/a.txt; echo d > design/d.md
  git add -A && git commit -qm base && git push -q origin main )
git clone -q "$T/origin.git" "$T/work" 2>/dev/null
W="$T/work"
# 클론에서 로컬 main 을 없앤다 — origin/main 만 남는 상태(리포 루트 로컬 main 이 옛 것인 CFO 실측의 대용)
git -C "$W" checkout -q -b nano/landed && git -C "$W" branch -q -D main
echo code > "$W/src/landed.txt" && git -C "$W" add -A && git -C "$W" commit -qm "[feature] landed"
git -C "$W" push -q origin nano/landed:main && git -C "$W" fetch -q origin
git -C "$W" checkout -q -b nano/unlanded origin/main
echo code2 > "$W/src/unlanded.txt" && git -C "$W" add -A && git -C "$W" commit -qm "[feature] unlanded"
git -C "$W" push -q origin nano/unlanded && git -C "$W" fetch -q origin

G="$BIN/ft-nano-cherry-gate.sh"
expect "cherry origin/main + 랜딩된 나노 → 통과" 0 "OK cherry 게이트" -- bash "$G" origin/main nano/landed --repo "$W"
expect "cherry origin/main + 미랜딩 코드 나노 → REJECT(+)" 1 "unlanded" -- bash "$G" origin/main nano/unlanded --repo "$W"
expect "cherry nope/main → REJECT refs/remotes/" 1 "refs/remotes/" -- bash "$G" nope/main nano/landed --repo "$W"
expect "cherry nano 를 원격 ref 로 → REJECT(heads 만)" 1 "refs/heads/" -- bash "$G" origin/main origin/nano/unlanded --repo "$W"

# 증거 검사 문서 전용 경로 — nano 가 design/ 만 건드림
git -C "$W" checkout -q -b nano/doc origin/main
echo doc > "$W/design/n.md" && git -C "$W" add -A && git -C "$W" commit -qm "[docs] n"
head="$(git -C "$W" rev-parse HEAD)"
printf '## 상태\n세트: %s · 시험: 없음(문서) — 문서만 · 이슈: 0\n' "$head" > "$T/card.md"
expect "evidence 문서 전용 --feat origin/main → 통과" 0 "OK 증거 줄" -- bash "$BIN/ft-nano-evidence-check.sh" "$T/card.md" --repo "$W" --feat origin/main
expect "evidence --feat nope/main → REJECT" 1 "refs/remotes/" -- bash "$BIN/ft-nano-evidence-check.sh" "$T/card.md" --repo "$W" --feat nope/main

# close 의 fetch 블록 — 함수만 떼어 직접 호출
sed -n '/^_fetch_remote_feat() {/,/^}/p' "$BIN/ft-nano-close.sh" > "$T/fn.sh"
[ -s "$T/fn.sh" ] && ok "close 에 _fetch_remote_feat 정의 존재" || bad "close 에 _fetch_remote_feat 없음"
( cd "$T/seed" && git pull -q --ff-only origin main && echo n > src/n.txt && git add -A && git commit -qm "[feature] newer" && git push -q origin main )
new="$(git -C "$T/seed" rev-parse --short HEAD)"
run_fn() { ( source "$T/fn.sh"; ROOT="$W"; bad=(); _fetch_remote_feat "$1"; echo "bad_n=${#bad[@]}"; printf 'bad: %s\n' "${bad[@]:-}" ); }
out="$(run_fn origin/main 2>&1)"; echo "  $out" | head -3
if printf '%s' "$out" | grep -q "INFO feat=origin/main @ $new (fetch 완료)" && printf '%s' "$out" | grep -q 'bad_n=0'; then ok "원격 feat → fetch 후 최신 ref(INFO 1줄)"; else bad "원격 feat fetch"; fi
git -C "$W" branch -q main origin/main~1 2>/dev/null
git -C "$W" remote set-url origin "$T/gone.git"
out="$(run_fn main 2>&1)"; echo "  $out" | head -3
printf '%s' "$out" | grep -q 'bad_n=0' && ! printf '%s' "$out" | grep -q INFO && ok "로컬 브랜치 값 → fetch 0" || bad "로컬 브랜치 값 fetch 발생"
out="$(run_fn origin/main 2>&1)"; echo "  $out" | head -3
printf '%s' "$out" | grep -q 'bad_n=1' && printf '%s' "$out" | grep -q 'fetch 실패: origin/main' && ok "fetch 실패 → bad 1건(REJECT 사유)" || bad "fetch 실패가 REJECT 로 안 이어짐"

echo "RESULT fail=$fail"
[ "$fail" -eq 0 ]
