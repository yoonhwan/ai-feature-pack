#!/usr/bin/env bash
# test_r559_scope_team_folder_docs.sh — r559: 자율 범위 분류기가 «팀 폴더 첫 문서 착지» 를 docs 로 읽는다(카드 이동 짝 · 팀 폴더 비실행 파일) + 속도
# 외부 호출 0(임시 git 리포 · 로컬 origin bare) · 실 원장·슬랙·Redis 0 · GIT_* 환경 변수 안 건다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLS="${R559_CLS:-$HERE/../../harness/kit/fable-team/bin/autonomy_scope_classify.py}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"; mkdir -p "$T/state/autonomy-scope"
git init -q --bare "$T/o.git"; git clone -q "$T/o.git" "$T/w" 2>/dev/null; W="$T/w"
cm() { git -C "$W" -c user.email=t@t -c user.name=t commit -q -m "${1:-c}"; }
sha() { git -C "$W" rev-parse HEAD; }
git -C "$W" checkout -q -b main; mkdir -p "$W/design/teams/x/indices/대기" "$W/design/teams/x/indices/진행" "$W/design/teams/cfo" "$W/docs" "$W/design/foo"
printf 'card line\n' > "$W/design/teams/x/indices/대기/C-a.md"; echo d > "$W/docs/a.md"; echo f > "$W/design/foo/a.txt"
git -C "$W" add -A; cm base; git -C "$W" push -q origin main; BASE="$(sha)"
echo m1 > "$W/m1.txt"; git -C "$W" add -A; cm m1; git -C "$W" push -q origin main   # main = BASE 한 칸 위 — 가지들은 main 조상이 아님(docs 판정 대상)
git -C "$W" checkout -q -B side "$BASE"
mk() { local br="$1" from="$2"; shift 2; git -C "$W" reset -q --hard && git -C "$W" clean -qfd; git -C "$W" checkout -q -B "$br" "$from"; ( cd "$W" && eval "$*" ); git -C "$W" add -A; cm "$br"; SHA="$(sha)"; }
cls() { out="$(python3 "$CLS" classify "$@" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }   # want <이름> <rc> <출력 머리>

python3 -I -m py_compile "$CLS"; ck "py_compile" $?
[ "$(wc -l < "$CLS" | tr -d ' ')" -le 200 ]; ck "classify ≤ 200줄" $?

# ⓐ 카드 이동 + 상태 줄 1줄 수정(git R0xx) → docs move(옛 판 = forbid move-changed)
mk a1 "$BASE" 'mkdir -p design/teams/x/indices/진행 && git mv design/teams/x/indices/대기/C-a.md design/teams/x/indices/진행/C-a.md && printf "card line\n상태: 진행\n" > design/teams/x/indices/진행/C-a.md'
cls "$SHA"; want "ⓐ 카드 대기→진행 + 상태 줄 수정 → CLASS docs" 0 "CLASS docs"
# ⓑ 같은 이동이 D+A 로 잡힘(유사도 낮음) → docs move · 짝 = 같은 팀 indices 사이 · 같은 이름 · 양쪽 docs
mk b1 "$BASE" 'mkdir -p design/teams/x/indices/진행 && git mv design/teams/x/indices/대기/C-a.md design/teams/x/indices/진행/C-a.md && python3 -c "open(\"design/teams/x/indices/진행/C-a.md\",\"w\").write(\"완전히 다른 내용\n\"*50)"'
n="$(git -C "$W" diff --name-status -M "$BASE" "$SHA" | tr '\n' ' ')"; echo "  ⓑ 세트 모양: $n"
cls "$SHA"; want "ⓑ D+A 로 잡힌 같은 카드 이동 → CLASS docs" 0 "CLASS docs"
# ⓐ2 R080 꼴(같은 이름 · 내용 20% 바뀜 · ops 실사건 d1df8c06cf) → docs move
mk a2 "$BASE" 'mkdir -p design/teams/x/indices/진행 && git mv design/teams/x/indices/대기/C-a.md design/teams/x/indices/진행/C-a.md && python3 -c "p=\"design/teams/x/indices/진행/C-a.md\"; t=open(p).read(); open(p,\"w\").write(t+\"증거 줄: 시험 rc=0\n\"*8)"'
st="$(git -C "$W" diff --name-status -M "$BASE" "$SHA" | head -1 | cut -f1)"; echo "  ⓐ2 세트 모양: $st"
cls "$SHA"; want "ⓐ2 카드 이동 + 내용 일부 변경(R0xx) → CLASS docs" 0 "CLASS docs"
# ⓒ 짝 없는 D(팀 폴더 문서 삭제) → forbid delete 그대로
mk c1 "$BASE" 'git rm -q design/teams/x/indices/대기/C-a.md'; cls "$SHA"; want "ⓒ 짝 없는 D → FORBID delete" 3 "FORBID kind=delete"
# ⓓ 다른 팀 폴더로의 이동 · indices 밖 이동 → forbid
mk d1 "$BASE" 'mkdir -p design/teams/cfo/indices/진행 && git mv design/teams/x/indices/대기/C-a.md design/teams/cfo/indices/진행/C-a.md && echo "상태: 진행" >> design/teams/cfo/indices/진행/C-a.md'
cls "$SHA"; want "ⓓ 다른 팀 폴더로 이동(내용 바뀜) → FORBID(delete·move-changed 중 하나 · 짝 아님)" 3 "FORBID kind="
mk d2 "$BASE" 'git mv design/teams/x/indices/대기/C-a.md design/teams/x/C-a.md && echo "상태: 진행" >> design/teams/x/C-a.md'; cls "$SHA"; want "ⓓ indices 밖으로 이동(내용 바뀜) → FORBID" 3 "FORBID kind="
mk d3 "$BASE" 'mkdir -p design/teams/cfo/indices/진행 && git mv design/teams/x/indices/대기/C-a.md design/teams/cfo/indices/진행/C-a.md'
cls "$SHA"; want "ⓓ 다른 팀 폴더로 이동(같은 이름·같은 내용) → 지금과 같이 CLASS docs(R100)" 0 "CLASS docs"
# ⓔ 팀 폴더 증거 파일(.txt·.json·.raw·확장자 없음·.png) → docs
mk e1 "$BASE" 'mkdir -p design/teams/x/evidence-t1 && echo t > design/teams/x/evidence-t1/a.txt && echo "{}" > design/teams/x/evidence-t1/b.json && echo r > design/teams/x/evidence-t1/c.raw && echo s > design/teams/x/evidence-t1/sampdone && echo p > design/teams/x/evidence-t1/d.png'
cls "$SHA"; want "ⓔ 팀 증거 비실행 파일 → CLASS docs" 0 "CLASS docs"
# ⓕ 증거 폴더의 run.py·run.sh → docs · pytest 가 모으는 test_*.py·a_test.py·conftest.py → code · 100755 → forbid mode
mk f1 "$BASE" 'mkdir -p design/teams/x/evidence-t1 && echo "print(1)" > design/teams/x/evidence-t1/run.py && echo "echo 1" > design/teams/x/evidence-t1/run.sh'
cls "$SHA"; want "ⓕ evidence run.py·run.sh → CLASS docs" 0 "CLASS docs"
mk f2 "$BASE" 'mkdir -p design/teams/x/evidence-t1 && echo "def test_a(): pass" > design/teams/x/evidence-t1/test_a.py'; cls "$SHA"; want "ⓕ test_a.py → CLASS code" 0 "CLASS code"
mk f3 "$BASE" 'mkdir -p design/teams/x && echo "def test_a(): pass" > design/teams/x/a_test.py'; cls "$SHA"; want "ⓕ a_test.py → CLASS code" 0 "CLASS code"
mk f4 "$BASE" 'mkdir -p design/teams/x && echo "" > design/teams/x/conftest.py'; cls "$SHA"; want "ⓕ conftest.py → CLASS code" 0 "CLASS code"
mk f5 "$BASE" 'mkdir -p design/teams/x/evidence-t1 && echo 1 > design/teams/x/evidence-t1/run.sh && chmod +x design/teams/x/evidence-t1/run.sh'
cls "$SHA"; want "ⓕ 100755 실행 비트 → FORBID mode 그대로" 3 "FORBID kind=mode"
# ⓖ 팀 폴더 밖 design/ → 지금과 같음(code) · 팀 폴더 안 evidence 밖 .py → code
mk g1 "$BASE" 'echo n > design/foo/b.txt'; cls "$SHA"; want "ⓖ 팀 폴더 밖 design/foo/b.txt → CLASS code" 0 "CLASS code"
mk g2 "$BASE" 'mkdir -p design/teams/x && echo n > design/teams/x/a.py'; cls "$SHA"; want "ⓖ evidence 밖 팀 폴더 .py → CLASS code" 0 "CLASS code"
# ⓗ 금지 낱말은 그대로 — 결제 낱말 경로 · 학습 키를 주면 docs
mk h1 "$BASE" 'mkdir -p design/teams/cfo && echo n > design/teams/cfo/toss-payments.html'; H1="$SHA"; cls "$SHA"; want "ⓗ toss-payments.html → FORBID billing 그대로" 3 "FORBID kind=billing"
mk h2 "$BASE" 'mkdir -p design/teams/cfo && echo n > design/teams/cfo/toss-payments.md'; cls "$SHA"; want "ⓗ toss-payments.md → CLASS docs(.md 는 낱말 금지 줄 위 · r514 그대로)" 0 "CLASS docs"
out="$(python3 "$CLS" classify "$H1" --repo "$W" --scope S1 --learned billing 2>&1)"; rc=$?
want "ⓗ 학습 키 billing 주면 CLASS docs kind=billing learned" 0 "CLASS docs kind=billing learned"
# ⓘ 속도 — 1,000파일 · 6,676파일(v65 실사건 크기) 두 세트 · 파일당 git 호출 0
speed() {  # speed <파일 수> → "초" (분류 1회)
  local n="$1" d="$T/sp$1"; mkdir -p "$d"; git init -q "$d/o.git" --bare; git clone -q "$d/o.git" "$d/w" 2>/dev/null
  git -C "$d/w" checkout -q -b main; echo base > "$d/w/base.md"; git -C "$d/w" add -A
  git -C "$d/w" -c user.email=t@t -c user.name=t commit -q -m base; git -C "$d/w" push -q origin main
  git -C "$d/w" checkout -q -b side
  python3 - "$d/w" "$n" <<'PY'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
os.makedirs(os.path.join(root, "design/teams/x/docs"), exist_ok=True)
for i in range(n):
    with open(os.path.join(root, "design/teams/x/docs/f%05d.md" % i), "w", encoding="utf-8") as f:
        f.write("# 문서 %d\n\n내용 줄 %d\n\n- 항목\n" % (i, i))
PY
  git -C "$d/w" add -A; git -C "$d/w" -c user.email=t@t -c user.name=t commit -q -m side; local s; s="$(git -C "$d/w" rev-parse HEAD)"
  local base; base="$(git -C "$d/w" rev-parse main)"
  python3 - "$CLS" "$d/w" "$s" <<'PY'
import subprocess, sys, time
cls, repo, sha = sys.argv[1:4]
t = time.time(); p = subprocess.run([sys.executable, cls, "classify", sha, "--repo", repo, "--scope", "S1"], capture_output=True, text=True)
print("%.2f %d %s" % (time.time() - t, p.returncode, p.stdout.strip()[:60]))
PY
  echo "  ⓘ ${n}파일 세트: $(git -C "$d/w" diff --name-only "$base" "$s" | wc -l | tr -d ' ')개 변경"
}
read -r t1 rc1 o1 <<<"$(speed 1000)"; echo "  ⓘ 1000파일 시간=${t1}s rc=$rc1 out=$o1"
read -r t2 rc2 o2 <<<"$(speed 6676)"; echo "  ⓘ 6676파일 시간=${t2}s rc=$rc2 out=$o2"
out="1000=${t1}s 6676=${t2}s $o1 / $o2"; rc=0
python3 -c "import sys; sys.exit(0 if float('$t1')<=7 and float('$t2')<=7 else 1)"; ck "ⓘ 1000·6676 파일 세트 각 7초 안" $?
# ⓙ 기존 분류기 시험 무변경 + rc0 (base 대조)
if git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$HERE" diff --quiet origin/main -- test_autonomy_scope_classify.sh; ck "ⓙ 기존 시험 파일 base 대조 diff 0" $?
fi
bash "$HERE/test_autonomy_scope_classify.sh" >"$T/existing.log" 2>&1; ck "ⓙ 기존 분류기 시험 rc0(ALL PASS)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
