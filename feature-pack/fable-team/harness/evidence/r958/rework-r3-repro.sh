#!/usr/bin/env bash
# rework-r3-repro.sh — r958 r3 반송(DA⑥ r2 HOLD 2) 반례 2건을 «r2 판(88bbabb3) vs r3 판» 으로 재현한다. mktemp 리포만 쓴다(실 브랜치·원장 쓰기 0).
#   반례 1 = feat 에 없는 파일 `a"b.py` 를 나노가 추가 → base 판 REJECT · r2 판은 따옴표 경로가 안 맞아 통과(누출) · r3 판은 base 와 같은 REJECT.
#   반례 2 = 가짜 git 이 `rev-parse` 에만 sleep 8 → r2 판은 상한 밖이라 조용히 통과 · r3 판은 «rev-parse 7초 초과» REJECT.
#   + 성능 = «+» 커밋 300 · 경로 2000 · git 1회 0.08초 입력에서 base 판(70초 상한) vs r3 판(묶음) 시간·호출 수.
set -uo pipefail
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
G="$HERE/../../bin/ft-nano-cherry-gate.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pull() {  # <ref> <출력> — 그 판의 게이트 사본
  git -C "$HERE" show "$1:feature-pack/fable-team/harness/bin/ft-nano-cherry-gate.sh" > "$2" 2>/dev/null || { echo "게이트 사본을 못 떴다: $1"; exit 1; }
}
pull origin/main "$T/base.sh"; pull 88bbabb3 "$T/r2.sh"
cp "$HERE/../../bin/ft_git_capped.py" "$T/"   # 변이본은 $T 에 살아 도우미를 같은 자리에서 찾는다

echo "================ 반례 1 — 따옴표 경로(a\"b.py) ================"
R="$T/q"; git init -q -b main "$R"
mkdir -p "$R/app" "$R/design"; printf 'a0\n' > "$R/app/a.py"; printf 'c0\n' > "$R/design/card.md"; git -C "$R" add -A; git -C "$R" commit -qm base
git -C "$R" checkout -q -b nano/x; printf 'q\n' > "$R/app/a\"b.py"; git -C "$R" add -A; git -C "$R" commit -qm "nano quoted path"
git -C "$R" checkout -q main; printf 'm\n' > "$R/app/m.py"; git -C "$R" add -A; git -C "$R" commit -qm "feat moved"
echo "--- base(origin/main) 판:"; bash "$T/base.sh" main nano/x --repo "$R" > "$T/o1.txt" 2>&1; echo "rc=$?"
echo "--- r2 판(88bbabb3):";      bash "$T/r2.sh"   main nano/x --repo "$R" > "$T/o2.txt" 2>&1; echo "rc=$?"
echo "--- r3 판(HEAD):";          bash "$G"         main nano/x --repo "$R" > "$T/o3.txt" 2>&1; echo "rc=$?"
diff "$T/o1.txt" "$T/o3.txt" >/dev/null && echo "==> r3 stdout = base stdout (전문 동일)" || { echo "==> r3 stdout 이 base 와 다르다:"; diff "$T/o1.txt" "$T/o3.txt"; }
echo "--- r2 판 출력(누출 재현):"; sed -n '1,3p' "$T/o2.txt"

echo; echo "================ 반례 2 — rev-parse 가 7초 상한 밖 ================"
B="$T/bin"; mkdir -p "$B"
cat > "$B/git" <<'SH'
#!/bin/bash
case "$*" in *rev-parse*) sleep 8;; esac
exec /usr/bin/git "$@"
SH
chmod 755 "$B/git"
R2="$T/cap"; git init -q -b main "$R2"
mkdir -p "$R2/app"; printf 'A0\n' > "$R2/app/a.py"; git -C "$R2" add -A; git -C "$R2" commit -qm base
git -C "$R2" checkout -q -b nano/x; printf 'A1\n' >> "$R2/app/a.py"; git -C "$R2" commit -qam "nano c1"
git -C "$R2" checkout -q main; git -C "$R2" merge -q --ff-only nano/x   # «+» 0 — 상한 밖이면 조용히 통과한다
echo "--- r2 판(88bbabb3):"; s=$SECONDS; PATH="$B:$PATH" bash "$T/r2.sh" main nano/x --repo "$R2"; echo "rc=$? · $((SECONDS - s))초"
echo "--- r3 판(HEAD):";     s=$SECONDS; PATH="$B:$PATH" bash "$G"       main nano/x --repo "$R2"; echo "rc=$? · $((SECONDS - s))초"

echo; echo "================ 성능 — «+» 300 커밋 · 경로 2000 · git 1회 0.08초 ================"
BB="$T/slow"; mkdir -p "$BB"
cat > "$BB/git" <<'SH'
#!/bin/bash
echo "$*" >> "${FT_GIT_LOG:-/dev/null}"
sleep 0.08
exec /usr/bin/git "$@"
SH
chmod 755 "$BB/git"
R3="$T/big"; git init -q -b main "$R3"
for i in $(seq 1 2000); do mkdir -p "$R3/d$((i % 40))/p"; printf 'f%s\n' "$i" > "$R3/d$((i % 40))/p/f$i.txt"; done
mkdir -p "$R3/app" "$R3/design"; printf 'x\n' > "$R3/app/main.py"; printf 'd0\n' > "$R3/design/base.md"
git -C "$R3" add -A; git -C "$R3" commit -qm base
git -C "$R3" checkout -q -b nano/x
for i in $(seq 1 300); do printf 'd%s\n' "$i" > "$R3/design/c$i.md"; git -C "$R3" add -A; git -C "$R3" commit -qm "nano $i"; done
git -C "$R3" checkout -q main; printf 'feat\n' > "$R3/app/main.py"; git -C "$R3" add -A; git -C "$R3" commit -qm "feat touch"
s=$SECONDS; PATH="$BB:$PATH" bash "$T/base.sh" main nano/x --repo "$R3" > "$T/p1.txt" 2>&1; rcb=$?; tb=$((SECONDS - s))
s=$SECONDS; FT_GIT_LOG="$T/calls3" PATH="$BB:$PATH" bash "$G" main nano/x --repo "$R3" > "$T/p3.txt" 2>&1; rc3=$?; t3=$((SECONDS - s))
: > "$T/calls3b"
FT_GIT_LOG="$T/calls3b" PATH="$BB:$PATH" bash "$G" main nano/x --repo "$R3" > /dev/null 2>&1
echo "base 판: rc=$rcb · ${tb}초 · 첫 줄 = $(sed -n 1p "$T/p1.txt")"
echo "r3 판  : rc=$rc3 · ${t3}초 · 외부 호출 $(wc -l < "$T/calls3b" | tr -d ' ')회 · 첫 줄 = $(sed -n 1p "$T/p3.txt")"
