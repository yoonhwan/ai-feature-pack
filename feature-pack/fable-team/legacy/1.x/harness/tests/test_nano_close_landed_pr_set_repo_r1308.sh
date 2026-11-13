#!/usr/bin/env bash
# test_nano_close_landed_pr_set_repo_r1308.sh — r1308: ft-nano-close.sh --landed-pr 의 리포 고르기(_lp_repo_pick)가
#   카드 «대상:» 줄에 절대경로가 0개일 때, 카드 «## 상태» 의 마지막 «세트:» sha 객체가 «ROOT·팩 중 팩에만» 있으면 그 리포(팩)로 정한다
#   (팩 PR 은 팩 리포에서 읽고 판정한다 · 둘 다 = REJECT · ROOT 에만·둘 다 없음·팩 미설치 = 지금 r1053 갈래 그대로).
# 임시 git 리포 2개(ROOT + PACK · 각각 bare 원격) + 가짜 tmux·gh(-R 별 다른 응답)·git(호출 기록) 만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 고정 sleep 0 · GIT_* env 0 · 자기 재호출 0.
# ⓐ R1 팩 카드(대상 상대경로 «팩 feature-pack/…» · 절대경로 0) · 세트·PR head(세트 + main 병합 1)는 팩에만 · ROOT 에 같은 번호 PR 다른 head
#    → gh -R <팩 slug> 1회 · CLOSED · 꼬리 «landed-pr=363 equiv=1 repo=lptest/pack» · cherry-override 0 · INFO «세트 객체 근거 → 팩»
#    ⓕ R6 같은 입력에서 ⑥ 판정기(ft-approval-equiv.sh)가 «실제로 --repo <팩>» 으로 불림(인자 기록) · EQUIV mode=merge merges=1
# ⓑ R2 BYZ 카드(절대경로 0 · 카드가 ROOT 에 삶) · 세트가 ROOT 에만 → 새 갈래 건너뜀 → r1053 그대로 ROOT · 출력이 «갈래 제거 판» 과 바이트 같음
# ⓒ R2b 팩 미설치(FT_PACK_ROOT 없는 경로) · 절대경로 0 · 세트 ROOT 에만 · cwd = 좌석 워크트리(≠ROOT) → 갈래 건너뜀(cat-file ^{commit} 호출 0) → CLOSED
# ⓓ R2c 카드가 ROOT 밖 리포 · 절대경로 0 · 세트 ROOT 에만 → r1053 그대로 REJECT · gh 0
# ⓔ R3 세트 객체가 ROOT·팩 둘 다 → REJECT «객체가 ROOT·팩 둘 다» · gh 0 · 닫기 0
# ⓖ R4 세트가 어디에도 없음 · «세트:» 줄 0 → r1053 그대로(«갈래 제거 판» 과 바이트 같음)
# ⓗ R5 대상 절대경로가 팩 아래 1개 이상 → 지금 r1023 갈래 그대로(팩) · 새 INFO 줄 0
# 변이 5: «갈래 제거» → R1 FAIL · «둘 다를 팩 우선» → R3 FAIL · «갈래를 r1053 뒤로» → R1 FAIL · «빈 팩 경로 건너뜀 제거» → R2b FAIL · «ROOT 에만 → ROOT 갈래 추가» → R2c FAIL
# 짝: bin == kit cmp0 · /bin/bash 3.2 -n · 회귀 8(r1053·r1011·r1074·r1112·r1058·r1083·r1084·r1169)은 이 파일 밖(카드 완료 조건에서 함께 rc0 확인)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

mkdir -p "$T/bin" "$T/fake" "$T/real"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
# r1308: ft_team_lib.py = ft_teamset.py(나노 이름 규칙)의 import 짝 — 없으면 8 회귀처럼 «이름 규칙 조회 실패» 로 조기 종료한다
cp "$SRC/ft-nano-close.sh" "$SRC/ft-landed-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-card-target-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
   "$SRC/ft_team_lib.py" \
   "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" \
   "$T/bin/"
cp "$SRC/ft-approval-equiv.sh" "$SRC/ft_approval_equiv.py" "$T/real/"
# R6: 판정기는 «진짜» 를 부르되 인자를 기록한다(래퍼 = 기록 + exec · 판정 규칙 바꾸지 않음)
cat > "$T/bin/ft-approval-equiv.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_EQ_LOG:-/dev/null}"
exec "$FAKE_EQ_REAL" "$@"
EOF
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
case "$*" in *"-R lptest/pack"*) cat "$FAKE_GH_JSON_PACK";; *) cat "$FAKE_GH_JSON";; esac
EOF
cat > "$T/fake/git" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_GIT_LOG:-}" ] && echo "$*" >> "$FAKE_GIT_LOG"
exec /usr/bin/git "$@"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

BYZ_URL='https://github.com/lptest/byz.git'; PACK_URL='git@github.com:lptest/pack.git'
ROOT="$T/repo"; mkdir -p "$ROOT"
git -C "$ROOT" init -q -b main && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" remote add origin "$BYZ_URL"
git -C "$ROOT" config "url.$T/remote.git.insteadOf" "$BYZ_URL"   # 식별자 = 설정값(github 꼴) · 전송 = 로컬 bare(네트워크 0)
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git -C "$ROOT" push -q origin main
INIT="$(git -C "$ROOT" rev-parse main)"
PACK="$T/pack"; mkdir -p "$PACK"
git -C "$PACK" init -q -b main && git -C "$PACK" -c user.email=t@t -c user.name=t commit -q --allow-empty -m pack-init
git -C "$PACK" remote add origin "$PACK_URL"
git -C "$PACK" config "url.$T/pack-remote.git.insteadOf" "$PACK_URL"
PREM="$T/pack-remote.git"; git init -q --bare "$PREM"; git -C "$PREM" symbolic-ref HEAD refs/heads/main
git -C "$PREM" config uploadpack.allowAnySHA1InWant true
git -C "$PACK" push -q origin main
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/완성" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-ops-nano-lp#0'; BR='nano/lp'; NW="$ROOT/.worktrees/v65-lp"
CARD_REL='design/ops/indices/완성/lp.md'; CARD="$ROOT/$CARD_REL"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/web" && echo 'x' > "$NW/web/a.txt"
git -C "$NW" add web/a.txt && git -C "$NW" commit -q -m "BYZ 좌석 작업"
SHA0="$(git -C "$NW" rev-parse HEAD)"
git -C "$ROOT" update-ref refs/remotes/origin/main "$(git -C "$ROOT" rev-parse main)"
# 팩 좌석 = 세트 S 를 만드는 곳 · 팩 main 은 한 칸 앞서 간다(M1) · PR head X = 세트 + main 병합 1(ft-merge-land 꼴)
NWP="$PACK/.worktrees/v65-lp"
git -C "$PACK" worktree add -q "$NWP" -b nano/lp
git -C "$NWP" config user.email t@t; git -C "$NWP" config user.name t
mkdir -p "$NWP/feature-pack/fable-team/harness/bin" && echo 'pack work' > "$NWP/feature-pack/fable-team/harness/bin/pack-work.txt"
git -C "$NWP" add feature-pack/fable-team/harness/bin/pack-work.txt && git -C "$NWP" commit -q -m "팩 세트 작업"
S="$(git -C "$NWP" rev-parse HEAD)"
_blob="$(printf 'g1\n' | git -C "$PACK" hash-object -w --stdin)"
GIT_INDEX_FILE="$T/pidx" git -C "$PACK" read-tree "$(git -C "$PACK" rev-parse main)"
GIT_INDEX_FILE="$T/pidx" git -C "$PACK" update-index --add --cacheinfo "100644,$_blob,g1.txt"
_ptree="$(GIT_INDEX_FILE="$T/pidx" git -C "$PACK" write-tree)"; rm -f "$T/pidx"
M1="$(git -C "$PACK" -c user.email=t@t -c user.name=t commit-tree "$_ptree" -p "$(git -C "$PACK" rev-parse main)" -m other1)"
git -C "$PACK" push -q --force "$PREM" "$M1:refs/heads/main" && git -C "$PACK" fetch -q origin main
git -C "$NWP" fetch -q origin main && git -C "$NWP" merge -q --no-ff -m "merge main 1" origin/main
X="$(git -C "$NWP" rev-parse HEAD)"
git -C "$PACK" push -q "$PREM" "$X:refs/heads/pr363"   # PR head 객체를 «팩 origin» 에 둔다(⑥ 판정기 fetch 대상)
LEDGER="$T/ledger.markdown"; OTHER="$T/other"; mkdir -p "$OTHER"; git -C "$OTHER" init -q -b main

card_pack() {  # R1·R3·R4 꼴 — 대상 = «팩 …» 상대경로(절대경로 0)
  printf '# 인덱스: lp\n## 상태\n- 2026-11-02 진행\n  - 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n- 대상: 팩 feature-pack/fable-team/harness/bin/ft-nano-close.sh\n' "$1"
}
card_byz() {  # R2·R2b·R2c 꼴 — 대상 줄 0
  printf '# 인덱스: lp\n## 상태\n- 2026-11-02 진행\n  - 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n' "$1"
}
card_abs() {  # R5 꼴 — 대상 = 팩 «절대경로»(r1023 갈래)
  printf '# 인덱스: lp\n## 상태\n- 2026-11-02 진행\n  - 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n- 대상: %s/feature-pack/fable-team/harness/bin/ft-nano-close.sh\n' "$1" "$PACK"
}
setup() {  # setup <카드 본문 함수> <세트 sha> <ROOT PR head 꼴: ROOT|INIT>
  git -C "$NW" reset -q --hard "$SHA0"; git -C "$NW" clean -qfd
  rm -rf "$OTHER/design"
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; : > "$T/gitlog"; : > "$T/eqlog"
  rm -rf "$T/wtclean"
  "$1" "$2" > "$CARD"
  local h="$SHA0"; [ "${3:-ROOT}" = ROOT ] || h="$INIT"
  printf '{"state":"MERGED","mergeCommit":null,"headRefOid":"%s"}\n' "$h" > "$T/gh.json"        # ROOT(BYZ) 응답
  printf '{"state":"MERGED","mergeCommit":null,"headRefOid":"%s"}\n' "$X" > "$T/gh-pack.json"   # 팩 응답
}
close() {  # close [--cwd <디렉토리>] <ft-nano-close 인자…>
  local cwd="$ROOT"; [ "${1:-}" = "--cwd" ] && { cwd="$2"; shift 2; }
  ( cd "$cwd" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="${PKROOT:-$PACK}" \
    FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FAKE_GH_JSON_PACK="$T/gh-pack.json" \
    FAKE_GIT_LOG="$T/gitlog" FAKE_EQ_LOG="$T/eqlog" FAKE_EQ_REAL="$T/real/ft-approval-equiv.sh" \
    FT_NANO_LEDGER_WT="${LWT:-$ROOT/.worktrees/v6-realtime-live}" \
    FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
    FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
    bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
}
mutant() {  # mutant <old> <new> [<old2> <new2> …] → $T/mutbin/ft-nano-close.sh (정확 치환 · 자리 1곳 강제)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; pairs = sys.argv[2:]
s = open(p, encoding='utf-8').read()
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
    s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
}
CUT_HEAD='      # ★r1308★ 절대경로 0'
CUT_TAIL='      if [ -z "$repo" ]; then'
mutant_cut() {  # 갈래 통째 제거(«갈래 없던 판» = R2·R2b·R4 기준판 · 변이 1)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$CUT_HEAD" "$CUT_TAIL" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding='utf-8').read()
assert s.count(a) == 1, f"시작 앵커 {s.count(a)}곳"
i = s.find(a); j = s.find(b, i)
assert j >= 0, "끝 앵커 없음"
s = s[:i] + s[j:]
open(p, 'w', encoding='utf-8').write(s)
PY
}
same_out() {  # same_out <이름> <real 출력> <기준판 출력> — «출력 바이트 같음»(실행 폴더 bin/mutbin · 단계 초 «+<N>s» 만 맞춘다)
  local a b d
  a="$(printf '%s' "$2" | sed -e "s|$T/mutbin|$T/bin|g" -e 's/+[0-9][0-9]*s/+<N>s/g')"
  b="$(printf '%s' "$3" | sed -e "s|$T/mutbin|$T/bin|g" -e 's/+[0-9][0-9]*s/+<N>s/g')"
  [ "$a" = "$b" ] && { ok "$1"; return 0; }
  printf '%s\n' "$a" > "$T/a.txt"; printf '%s\n' "$b" > "$T/b.txt"
  d="$(diff "$T/a.txt" "$T/b.txt" | head -6 | tr '\n' '|')"
  bad "$1 — 출력이 기준판과 다르다: $d"
}

echo "== ⓐ R1 팩 카드(절대경로 0) · 세트·PR head 는 팩에만 → gh -R 팩 · CLOSED · cherry-override 0"
setup card_pack "$S" ROOT
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "INFO ⑥--landed-pr 세트 객체 근거 → 팩($PACK" "  └ INFO 세트 객체 근거 → 팩"
has "$out" "LANDED-PR-OK #363 merged= state=MERGED head=${X:0:9} repo=lptest/pack" "  └ ⑥ 자리 repo=lptest/pack"
has "$out" "≡ 카드 세트 ${S:0:9} + main 병합 1 equiv=1" "  └ EQUIV(세트 + main 병합 1)"
has "$out" "landed-pr=363 equiv=1 repo=lptest/pack" "  └ 꼬리 landed-pr=363 equiv=1 repo=<팩 slug>"
hasnt "$out" "repo=lptest/byz" "  └ BYZ slug 0"
hasnt "$out" "--cherry-override" "  └ cherry-override 0"
[ "$(cat "$T/ghlog")" = "pr view 363 -R lptest/pack --json state,mergeCommit,headRefOid" ] && ok "  └ gh 1회 -R lptest/pack" || bad "ⓐ gh: $(cat "$T/ghlog")"
jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "ⓐ: 명부에 남음"
has "$(cat "$LEDGER")" "landed-pr=363 equiv=1 repo=lptest/pack" "  └ 원장 행 equiv=1 repo=팩"

echo "== ⓕ R6 같은 입력 — ⑥ 판정기는 «실 판정기» 가 --repo <팩> 으로 불린다"
has "$(cat "$T/eqlog")" "--repo $PACK" "  └ 판정기 인자 --repo <팩>(스텁 아님)"
hasnt "$(cat "$T/eqlog")" "--repo $ROOT" "  └ 판정기 --repo <ROOT> 0"
eqout="$(bash "$T/real/ft-approval-equiv.sh" "$S" "$X" --repo "$PACK" 2>&1)"; eqrc=$?
[ "$eqrc" -eq 0 ] && ok "  └ 실 판정기 직접 호출 rc=0" || bad "ⓕ 실 판정기 rc=$eqrc ← ${eqout:0:300}"
has "$eqout" " merges=1 " "  └ 판정기 merges=1"
has "$eqout" "mode=merge" "  └ 판정기 mode=merge"

echo "== ⓑ R2 BYZ 카드 · 세트 ROOT 에만 → r1053 그대로 ROOT(«갈래 없던 판» 과 바이트 같음)"
setup card_byz "$SHA0" ROOT
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ rc=0" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "INFO ⑥--landed-pr 카드 위치 근거 → ROOT($ROOT" "  └ r1053 INFO 그대로"
has "$out" "repo=lptest/byz" "  └ repo=BYZ"
hasnt "$out" "세트 객체 근거" "  └ 새 INFO 줄 0"
mutant_cut; setup card_byz "$SHA0" ROOT; out2="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc2=$?
same_out "  └ 출력 바이트 = 갈래 없던 판(rc=$rc2)" "$out" "$out2"

echo "== ⓒ R2b 팩 미설치 + cwd = 좌석 워크트리 → 갈래 건너뜀(cat-file ^{commit} 0) · CLOSED"
setup card_byz "$SHA0" ROOT
out="$(PKROOT="$T/nopack" close --cwd "$NW" --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓒ rc=0" || bad "ⓒ rc=$rc ← ${out:0:900}"
has "$out" "INFO ⑥--landed-pr 카드 위치 근거 → ROOT($ROOT" "  └ r1053 갈래 그대로"
[ "$(grep -c 'cat-file -e .*\^{commit}' "$T/gitlog")" = 0 ] && ok "  └ cat-file ^{commit} 호출 0" || bad "ⓒ cat-file ^{commit}: $(grep -c 'cat-file -e .*\^{commit}' "$T/gitlog")회"
mutant_cut; setup card_byz "$SHA0" ROOT; out2="$(PKROOT="$T/nopack" CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --cwd "$NW" --landed-pr 363)"; rc2=$?
same_out "  └ 출력 바이트 = 갈래 없던 판(rc=$rc2)" "$out" "$out2"

echo "== ⓓ R2c 카드가 ROOT 밖 리포 · 세트 ROOT 에만 → r1053 그대로 REJECT · gh 0"
setup card_byz "$SHA0" ROOT; mkdir -p "$OTHER/$(dirname "$CARD_REL")"; mv "$CARD" "$OTHER/$CARD_REL"
out="$(LWT="$OTHER" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "카드가 사는 리포 $OTHER ≠ ROOT" "ⓓ ROOT 밖 카드 → REJECT(추측 0)" || bad "ⓓ rc=$rc ← ${out:0:900}"
[ ! -s "$T/ghlog" ] && ok "  └ gh 호출 0" || bad "ⓓ gh: $(cat "$T/ghlog")"
untouched "ⓓ"
mutant_cut; out2="$(LWT="$OTHER" CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc2=$?
same_out "  └ 출력 바이트 = 갈래 없던 판(rc=$rc2)" "$out" "$out2"

echo "== ⓔ R3 세트 객체가 ROOT·팩 둘 다 → REJECT(조용히 하나 고르지 않는다) · gh 0"
setup card_pack "$S" ROOT
git -C "$ROOT" fetch -q "$PACK" "+$S:refs/r1308/set"   # 같은 세트를 ROOT 에도 둔다
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓔ rc=1" || bad "ⓔ rc=$rc ← ${out:0:900}"
has "$out" "객체가 ROOT·팩 둘 다" "  └ 사유 = 둘 다(추측 0)"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
[ ! -s "$T/ghlog" ] && ok "  └ gh 호출 0" || bad "ⓔ gh: $(cat "$T/ghlog")"
untouched "ⓔ"

echo "== ⓖ R4 세트가 어디에도 없음 · «세트:» 줄 0 → r1053 그대로(«갈래 없던 판» 과 바이트 같음)"
setup card_pack "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ROOT
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓖ(없음) rc=1" || bad "ⓖ(없음) rc=$rc ← ${out:0:600}"
mutant_cut; setup card_pack "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ROOT
out2="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc2=$?
same_out "  └ 출력 바이트 = 갈래 없던 판(rc=$rc2)" "$out" "$out2"
setup card_pack "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ROOT
printf '# 인덱스: lp\n## 상태\n- 2026-11-02 진행\n- 착지: PR #363 squash\n- 대상: 팩 feature-pack/fable-team/harness/bin/ft-nano-close.sh\n' > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«세트:» 40-hex 줄이 없다" "ⓖ(줄 0) → 세트 없음 REJECT" || bad "ⓖ(줄 0) rc=$rc ← ${out:0:600}"
out2="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc2=$?
same_out "  └ 출력 바이트 = 갈래 없던 판(rc=$rc2)" "$out" "$out2"

echo "== ⓗ R5 대상 절대경로가 팩 아래 1개 이상 → 지금 r1023 갈래 그대로(팩) · 새 INFO 줄 0"
setup card_abs "$S" ROOT
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓗ rc=0" || bad "ⓗ rc=$rc ← ${out:0:900}"
hasnt "$out" "세트 객체 근거" "  └ 새 갈래 손대지 않음"
has "$out" "repo=lptest/pack" "  └ repo=팩(r1023 갈래)"
[ "$(cat "$T/ghlog")" = "pr view 363 -R lptest/pack --json state,mergeCommit,headRefOid" ] && ok "  └ gh 1회 -R lptest/pack" || bad "ⓗ gh: $(cat "$T/ghlog")"

echo "== 변이 1 «세트 객체 갈래 제거» → R1 이 잡는다(-R BYZ · REJECT)"
mutant_cut
setup card_pack "$S" ROOT
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
hasnt "$out" "LANDED-PR-OK" "  └ 변이 1 FAIL — R1 이 잡는다(통과 0)"
hasnt "$(cat "$T/ghlog")" "-R lptest/pack" "  └ 변이 1 FAIL — gh 가 팩을 부르지 않는다(BYZ 로 감)"

echo "== 변이 2 «둘 다» 를 팩 우선으로 → R3 이 잡는다"
mutant '          if git -C "$ROOT" cat-file -e "$s^{commit}" 2>/dev/null; then _lp_repo_err=' '          if false; then _lp_repo_err='
setup card_pack "$S" ROOT
git -C "$ROOT" fetch -q "$PACK" "+$S:refs/r1308/set"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "  └ 변이 2 FAIL — R3 이 잡는다(둘 다인데 닫힘 ← 조용히 팩 선택)" || bad "변이 2 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 3 «갈래를 r1053 뒤로» (그 시점 repo 는 이미 정해져 갈래 죽음) → R1 이 잡는다"
mutant '      if [ -n "$pk" ] && [ "${#s}" -eq 40 ]' '      if [ -n "$repo" ] && [ "${#s}" -eq 40 ]'
setup card_pack "$S" ROOT
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && hasnt "$out" "LANDED-PR-OK" "  └ 변이 3 FAIL — R1 이 잡는다(팩 갈래 0 → REJECT)" || bad "변이 3 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 4 «빈 팩 경로 건너뜀 제거» → R2b 가 잡는다"
mutant '      if [ -n "$pk" ] && [ "${#s}" -eq 40 ]' '      if [ "${#s}" -eq 40 ]'
setup card_byz "$SHA0" ROOT
out="$(PKROOT="$T/nopack" CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --cwd "$NW" --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "  └ 변이 4 FAIL — R2b 가 잡는다(빈 팩 경로가 cwd 리포를 봐 «둘 다» 로 거절)" || bad "변이 4 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 5 «ROOT 에만 → ROOT» 갈래 추가 → R2c 가 잡는다"
mutant '          repo="$pk"; echo "INFO ⑥--landed-pr 세트 객체 근거 → 팩($pk · 카드 «대상:» 줄 절대경로 0)"   # r1308-mut:setrepo
        fi' '          repo="$pk"; echo "INFO ⑥--landed-pr 세트 객체 근거 → 팩($pk · 카드 «대상:» 줄 절대경로 0)"   # r1308-mut:setrepo
        elif git -C "$ROOT" cat-file -e "$s^{commit}" 2>/dev/null; then repo="$ROOT"
        fi'
setup card_byz "$SHA0" ROOT; mkdir -p "$OTHER/$(dirname "$CARD_REL")"; mv "$CARD" "$OTHER/$CARD_REL"
out="$(LWT="$OTHER" CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "  └ 변이 5 FAIL — R2c 가 잡는다(ROOT 밖 카드가 닫힘)" || bad "변이 5 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
