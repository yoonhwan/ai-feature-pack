#!/usr/bin/env bash
# test_sat_git.sh — r1051 ft-sat-git(가벼운 git 스냅샷 · 설계 §3.3 5단 · 계약 보강 11~15) 단위 시험.
# 반례 R1~R6 + 계약↔시험 대응표 ⓐ~ⓓ(로컬 원격 흉내 = 임시 bare + 가짜 ssh · 실 mini 접속 0 · 실 상태 0).
# 변이 3종(비밀검사 제거 · design/ 거부 제거 · archive 를 삭제 뒤로)이 «잡히면» PASS.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -u   # pipefail 안 쓴다 — `cmd | grep -q` 의 SIGPIPE(141) 거짓 FAIL 방지
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../../harness/kit/fable-team/bin/ft-sat-git"
fail=0; out=""; rc=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: rc=$rc out=$(printf '%s' "$out" | tail -4 | tr '\n' '|')"; fail=$((fail + 1)); }
ck()  { [ "$2" = 0 ] && ok "$1" || bad "$1"; }
led() { python3 -c "import json;d=json.load(open('$1'));print(' '.join(str(d.get(k)) for k in $2))"; }
mut() { sed "$2" "$TOOL" > "$TMP/mut_$1.sh"; chmod +x "$TMP/mut_$1.sh"; }   # 변이 = 도구 사본 한 줄 바꾸기

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
RHOME="$TMP/mini"; FAKE="$TMP/fake"
mkdir -p "$RHOME/Project/sat-git" "$RHOME/Project/sat-work" "$FAKE"
BARE="$RHOME/Project/sat-git/byz-agents.git"; WT="$RHOME/Project/sat-work"; LED="$TMP/state"
git init -q --bare "$BARE" || { echo "FAIL bare 준비"; exit 1; }
# 가짜 ssh — «원격» = 임시 HOME. rem 경로(`-- bash -s …`, stdin 스크립트)와 git 날것 명령 둘 다 받는다.
cat > "$FAKE/ssh" <<'EOS'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  case "$1" in
    -G) exit 0;; -o|-p|-i|-l) shift 2;; -*) shift;; *) break;;
  esac
done
host=$1; shift
if [ "${1:-}" = "--" ]; then
  shift; [ "${1:-}" = bash ] && shift; [ "${1:-}" = -s ] && shift
  exec env HOME="$FAKE_RHOME" bash -s "$@"
fi
exec env HOME="$FAKE_RHOME" bash -c "$*"
EOS
chmod +x "$FAKE/ssh"
export FAKE_RHOME="$RHOME" FT_SAT_GIT_SSH="$FAKE/ssh" FT_SAT_GIT_HOST=mini
export FT_SAT_GIT_STATE="$LED" FT_SAT_GIT_TIMEOUT=70
newrepo() { local r="$TMP/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p pkg design && echo one > pkg/a.txt && echo card > design/card.md && echo hi > README.md \
  && git add -A && git commit -qm init ); echo "$r"; }
REPO="$(newrepo repo)"
sat() { out="$(cd "$REPO" && bash "$TOOL" "$@" 2>&1)"; rc=$?; }
# ── ⓐ R1 push: 원격 스냅샷 가지 + worktree + 훅 + 원장 세대 1 · 생성 ≤20초 · 전송 ≤15초 ────────
t0=$SECONDS; sat push r1 --base HEAD
w1="$WT/r1-g1"; ref1="$(git -C "$BARE" rev-parse --verify refs/heads/snap/r1-g1 2>/dev/null)"
cr=$(printf '%s' "$out" | sed -n 's/.* create=\([0-9]*\)s.*/\1/p'); tr_=$(printf '%s' "$out" | sed -n 's/.* transfer=\([0-9]*\)s.*/\1/p')
[ "$rc" = 0 ] && [ -n "$ref1" ] && [ -d "$w1" ] && [ -x "$(git -C "$w1" rev-parse --absolute-git-dir)/hooks/pre-commit" ] \
  && [ "$(led "$LED/r1.json" "['gen']")" = 1 ] && [ "${cr:-99}" -le 20 ] && [ "${tr_:-99}" -le 15 ] \
  && ck "R1 push = snap 가지+worktree+훅+원장 gen1 · create=${cr}s≤20 · transfer=${tr_}s≤15 · 왕복 $((SECONDS - t0))s" 0 \
  || ck "R1 push = snap 가지+worktree+훅+원장 gen1 · create=${cr}s≤20 · transfer=${tr_}s≤15 · 왕복 $((SECONDS - t0))s" 1
# ── R2a 사용 중 slug 재push 거부(계약 보강 12 동시 재사용) ──────────────────────────────────
sat push r1 --base HEAD
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q '사용 중' && ck "R2a 사용 중 slug 재push 거부" 0 || ck "R2a 사용 중 slug 재push 거부" 1
# ── ⓒ R4 원격 작업 커밋 → fetch cherry-pick 성공 · ≤30초 ──────────────────────────────────
git -C "$w1" config user.email t@t; git -C "$w1" config user.name t
printf 'two\n' > "$w1/pkg/a.txt"; git -C "$w1" commit -qam 'nano change'
t0=$SECONDS; sat fetch r1; el=$((SECONDS - t0))
[ "$rc" = 0 ] && [ "$(cd "$REPO" && git log -1 --format=%s)" = "nano change" ] && [ "$(cd "$REPO" && git rev-parse --abbrev-ref HEAD)" = "nano/r1-g1" ] \
  && grep -q two "$REPO/pkg/a.txt" && [ "$el" -le 30 ] \
  && ck "R4 fetch = 원격 커밋 cherry-pick(제목 보존) · ${el}s≤30 · branch nano/r1-g1" 0 \
  || ck "R4 fetch = 원격 커밋 cherry-pick(제목 보존) · ${el}s≤30 · branch nano/r1-g1" 1
# ── ⑤ R5 sweep: archive ref 실패 → worktree remove·branch -D 0 ────────────────────────────
: > "$BARE/refs/archive"   # refs/archive 를 파일로 막아 update-ref 실패를 만든다
t0=$SECONDS; sat sweep r1; save="$out"; savrc=$rc; el=$((SECONDS - t0)); rm -f "$BARE/refs/archive"
[ "$savrc" != 0 ] && [ -d "$w1" ] && git -C "$BARE" rev-parse --verify refs/heads/snap/r1-g1 >/dev/null 2>&1 \
  && ! printf '%s' "$save" | grep -q 'WORKTREE-REMOVED' \
  && ck "R5 archive 실패 → 삭제 0 (worktree·가지 보존 · ${el}s≤30)" 0 \
  || ck "R5 archive 실패 → 삭제 0 (worktree·가지 보존 · ${el}s≤30)" 1
# ── ④⑥ R6 sweep 순서 = archive → remove → branch -D · 원장 in_use 0(gen 보존) ───────────────
t0=$SECONDS; sat sweep r1; el=$((SECONDS - t0))
order=$(printf '%s' "$out" | grep -o 'ARCHIVE\|WORKTREE-REMOVED\|BRANCH-DELETED' | tr '\n' ' ')
atip="$(git -C "$BARE" rev-parse --verify refs/archive/sat-git/r1-g1 2>/dev/null)"
[ "$rc" = 0 ] && [ "$order" = "ARCHIVE WORKTREE-REMOVED BRANCH-DELETED " ] && [ ! -d "$w1" ] \
  && ! git -C "$BARE" rev-parse --verify refs/heads/snap/r1-g1 >/dev/null 2>&1 && [ -n "$atip" ] \
  && [ "$(led "$LED/r1.json" "['gen','in_use']")" = "1 False" ] \
  && ck "R6 sweep 순서 ARCHIVE→REMOVE→BRANCH-DELETED · archive ref 보존 · 원장 gen1 유지 · ${el}s≤30" 0 \
  || ck "R6 sweep 순서 ARCHIVE→REMOVE→BRANCH-DELETED · archive ref 보존 · 원장 gen1 유지 · ${el}s≤30" 1
# ── R2 같은 slug 두 번째 push → g2(새 이름공간) · archive 된 g1 tip 불변 ────────────────────
sat push r1 --base HEAD; w2="$WT/r1-g2"; g2tip="$(git -C "$BARE" rev-parse --verify refs/heads/snap/r1-g2 2>/dev/null)"
[ "$rc" = 0 ] && [ -n "$g2tip" ] && [ "$(git -C "$BARE" rev-parse refs/archive/sat-git/r1-g1)" = "$atip" ] \
  && [ "$(led "$LED/r1.json" "['gen']")" = 2 ] \
  && ck "R2 재push = g2 새 이름공간 · g1 archive tip 불변 · 원장 gen2" 0 || ck "R2 재push = g2 새 이름공간 · g1 archive tip 불변 · 원장 gen2" 1
# ── ⓒ R4 네거티브: design/ 변경 커밋 거부(+변이③) · 병합 커밋 거부 ─────────────────────────
git -C "$w2" config user.email t@t; git -C "$w2" config user.name t
mkdir -p "$w2/design"; echo new > "$w2/design/foo.md"; git -C "$w2" add -A; git -C "$w2" commit -qm 'design change'
sat fetch r1; dref=$rc; dout=$out
[ "$dref" != 0 ] && printf '%s' "$dout" | grep -q 'design/ 변경 커밋 거부' && ck "R4n design/ 변경 커밋 거부" 0 || ck "R4n design/ 변경 커밋 거부" 1
mut des "s/grep -Eq '^design\\/' \&\& die/grep -Eq \"__nomatch__\" \&\& die/"   # 변이③ = design/ 거부 한 줄 제거
out="$(cd "$REPO" && bash "$TMP/mut_des.sh" fetch r1 2>&1)"; rc=$?
[ "$rc" = 0 ] && ck "변이③ design/ 거부 제거 → R4n 칸 무의미(변이 검출)" 0 || ck "변이③ design/ 거부 제거 → 변이 검출 실패" 1
git -C "$w2" reset -q --hard "$g2tip"; rm -rf "$w2/design"
git -C "$w2" checkout -q -b side; printf 's\n' > "$w2/pkg/s.txt"; git -C "$w2" add -A; git -C "$w2" commit -qm side
git -C "$w2" checkout -q -; printf 'm\n' > "$w2/pkg/m.txt"; git -C "$w2" add -A; git -C "$w2" commit -qm main2
git -C "$w2" merge -q --no-ff side -m merge >/dev/null 2>&1
sat fetch r1; mref=$rc; mout=$out; git -C "$w2" reset -q --hard "$g2tip"
[ "$mref" != 0 ] && printf '%s' "$mout" | grep -q '병합 커밋 거부' && ck "R4n 병합 커밋 거부" 0 || ck "R4n 병합 커밋 거부" 1
# ── ② R3 비밀파일 검출 → push 0 · 원장 사용중 해제 ────────────────────────────────────────
R2="$(newrepo repo2)"; printf 'SECRET=1\n' > "$R2/.env"; ( cd "$R2" && git add -A && git commit -qm dotenv )
out="$(cd "$R2" && FT_SAT_GIT_STATE="$TMP/state2" bash "$TOOL" push sec1 --base HEAD 2>&1)"; rc=$?
[ "$rc" != 0 ] && ! git -C "$BARE" rev-parse --verify refs/heads/snap/sec1-g1 >/dev/null 2>&1 \
  && [ "$(led "$TMP/state2/sec1.json" "['in_use']")" = "False" ] \
  && ck "R3 비밀 파일 검출 → push 0 · 원장 사용중 해제" 0 || ck "R3 비밀 파일 검출 → push 0 · 원장 사용중 해제" 1
# ── 변이 2종 더(② · ④) — 그 «검사» 를 없애면 그 시험 칸이 무의미해진다(변이 검출 = PASS) ──────
mut sec 's/grep -Eq "\$SECRET"; then/grep -Eq "__nomatch__"; then/'
out="$(cd "$R2" && FT_SAT_GIT_STATE="$TMP/state3" bash "$TMP/mut_sec.sh" push sec1 --base HEAD 2>&1)"; rc=$?
[ "$rc" = 0 ] && ck "변이② 비밀검사 제거 → R3 칸 무의미해짐(변이 검출)" 0 || ck "변이② 비밀검사 제거 → 변이 검출 실패" 1
mut arc 's|^git -C "\$bare" update-ref "\$ar"|: skip update-ref|'   # 변이④ = archive 를 삭제 뒤로
sat push r1 --base HEAD; sat fetch r1; chmod 500 "$BARE/refs/archive/sat-git"
out="$(cd "$REPO" && bash "$TMP/mut_arc.sh" sweep r1 2>&1)"; rc=$?
chmod 700 "$BARE/refs/archive/sat-git" 2>/dev/null
[ "$rc" = 0 ] && [ ! -d "$WT/r1-g3" ] && ck "변이④ archive 를 삭제 뒤로 → R5 칸 무의미(변이 검출)" 0 || ck "변이④ archive 를 삭제 뒤로 → 변이 검출 실패" 1
[ "$fail" = 0 ] && { echo "OK test_sat_git ($((SECONDS))s · 실패 0)"; exit 0; }
echo "FAIL test_sat_git — 실패 $fail 칸"; exit 1
