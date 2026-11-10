#!/usr/bin/env bash
# rework-r2-repro.sh — r958 r2 반송(DA⑥ r1 HOLD 2) 반례 2건의 재현 + 고침 + 변이. mktemp 리포만 쓴다(실 브랜치·원장 쓰기 0).
#   반례 1 = feat 의 app/a.py 를 나노에서 내용 그대로 app/b.py 로 옮긴 커밋 → base 판 REJECT / 고침 전 HEAD 통과(누출).
#   반례 2 = 가짜 git 이 `cherry` 호출에만 sleep 8 → 고침 전 HEAD rc0 「OK(+ 0)」(조용한 통과) / 고침 후 «cherry 7초 초과» REJECT.
set -uo pipefail
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
G="$HERE/../../bin/ft-nano-cherry-gate.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OLD="$T/old-gate.sh"
git -C "$HERE" show origin/main:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh > "$OLD" 2>/dev/null \
  || { echo "옛 게이트 사본을 못 떴다(origin/main)"; exit 1; }
cp "$HERE/../../bin/ft_git_capped.py" "$T/" 2>/dev/null   # 변이본은 $T 에 살아 도우미를 같이 둔다(변이 1개만 다르게)

echo "================ 반례 1 — rename 무변경 이동 ================"
R="$T/ren"; git init -q -b main "$R"
mkdir -p "$R/app"; printf 'A0\n' > "$R/app/a.py"; git -C "$R" add -A; git -C "$R" commit -qm base
git -C "$R" checkout -q -b nano/x; git -C "$R" mv app/a.py app/b.py; git -C "$R" commit -qm "rename no content"
git -C "$R" checkout -q main; printf 'x\n' > "$R/app/m.py"; git -C "$R" add -A; git -C "$R" commit -qm "feat moved"
echo "--- base(origin/main) 판:"; bash "$OLD" main nano/x --repo "$R"; echo "rc=$?"
echo "--- 고침 판(HEAD):"; bash "$G" main nano/x --repo "$R"; echo "rc=$?"
sed 's/--root --no-renames --format/--root --format/' "$G" > "$T/gate-renameon.sh"
echo "--- 변이(rename 검출 켬 = 고침 전 자리):"; bash "$T/gate-renameon.sh" main nano/x --repo "$R"; echo "rc=$?"

echo; echo "================ 반례 2 — git cherry 가 7초 상한 밖 ================"
B="$T/bin"; mkdir -p "$B"
cat > "$B/git" <<'SH'
#!/bin/bash
case "$*" in *cherry*) sleep 8;; esac
exec /usr/bin/git "$@"
SH
chmod 755 "$B/git"
R2="$T/cap"; git init -q -b main "$R2"
mkdir -p "$R2/app"; printf 'A0\n' > "$R2/app/a.py"; git -C "$R2" add -A; git -C "$R2" commit -qm base
# DA⑥ r1 입력 그대로 = «feat 와 나노가 같은 커밋» — «+» 0 이라 상한 밖이면 9초 뒤 rc0 OK(+ 0) 로 조용히 통과한다.
git -C "$R2" checkout -q -b nano/x; printf 'A1\n' >> "$R2/app/a.py"; git -C "$R2" commit -qam "nano c1"
git -C "$R2" checkout -q main; git -C "$R2" merge -q --ff-only nano/x
sed 's/cg_git "\$CG_LIM" cherry/git -C "\$REPO" cherry/' "$G" > "$T/gate-nocherrycap.sh"
echo "--- 변이(cherry 도우미 밖 = 고침 전 자리):"; s=$SECONDS
PATH="$B:$PATH" bash "$T/gate-nocherrycap.sh" main nano/x --repo "$R2"; echo "rc=$? · $((SECONDS - s))초"
echo "--- 고침 판(HEAD):"; s=$SECONDS
PATH="$B:$PATH" bash "$G" main nano/x --repo "$R2"; echo "rc=$? · $((SECONDS - s))초"
