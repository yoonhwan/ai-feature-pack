#!/usr/bin/env bash
# test_nano_close_landed_pr_r1011.sh — r1011: ft-nano-close.sh --landed-pr <PR 번호> (착지(squash) 끝 나노 좌석 닫기)
#   ⑤ cherry(가지 «+» 커밋 0)와 ⑥ 증거 줄 세트 대조(«세트 == 지금 HEAD»)를 «PR MERGED ∧ PR head == 카드 «세트:» sha ∧ 카드 «- 착지:» 줄» 로 대체한다.
# 임시 git 리포 + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실제 리포·seats·tmux·gh(네트워크)는 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 통과 = LANDED-PR-OK · CLOSED-ABSENT <좌석> landed-pr=<N> · 원장 행 · 명부 삭제 · 브랜치 보존 · ⑤ INFO 건너뜀
#    ⓑ PR head ≠ 카드 세트 → REJECT ⓒ OPEN · CLOSED(미병합) → REJECT ⓓ 카드 «- 착지:» 줄 없음 → REJECT(gh 호출 0)
#    ⓔ gh rc≠0 → REJECT · gh 8초(상한 7초) → REJECT ⓕ 모드 충돌·빈 번호 → usage 2 · 인자 없으면 불변
#    ⓖ 변이 «head 대조 끔» → ⓑ 가 닫힘(FAIL) ⓗ kit 짝 cmp0 · /bin/bash 3.2 · 600/300·GIT_* 0
#    ⓘ 세트 줄 = «## 상태» 절 «안» 만 (절 밖 세트 줄이 head 와 같아도 REJECT · 상태 절 세트 = head 면 CLOSED · 상태 절에 세트 줄 0 = REJECT)
#    ⓙ 명부 부재 + 원장 닫힘 행 + 대역 세션 + 없는 PR → gh 1회 · kill 0 · 원장 append 0 · REJECT (PR 검증이 조기 재실행보다 «먼저»)
#    ⓚ 변이 2«절 경계 무시»·«재실행 경로 선행» → 각각 ⓘ·ⓙ 가 못 잡게 되는지(변이 FAIL)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== ⓗ 키트 2곳 같은 바이트 + bash -n (/bin/bash 3.2 포함)"
for f in ft-nano-close.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
  /bin/bash -n "$SRC/$f" && ok "/bin/bash 3.2 -n $f" || bad "/bin/bash 3.2 -n $f"
done

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # reap = 같은 bin 스텁(실기계 프로세스 0)
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
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
# 가짜 gh — 네트워크 0 · 응답은 FAKE_GH_JSON · 실패는 FAKE_GH_RC · 늦음은 FAKE_GH_SLEEP. 호출은 FAKE_GH_LOG 에 남긴다.
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
[ "${FAKE_GH_SLEEP:-0}" = 0 ] || sleep "$FAKE_GH_SLEEP"
[ "${FAKE_GH_RC:-0}" = 0 ] || { echo "gh: Not Found (HTTP 404)" >&2; exit "$FAKE_GH_RC"; }
cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-lp#0'; BR='nano/lp'; NW="$REPO/.worktrees/v65-lp"
CARD_REL='design/planner/indices/진행/lp.md'; CARD="$REPO/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/landed.py"
git -C "$NW" add scripts/landed.py && git -C "$NW" commit -q -m "work (squash 로 착지한 세트)"
SHA0="$(git -C "$NW" rev-parse HEAD)"
SHA1="$(git -C "$REPO" -c user.email=t@t -c user.name=t commit-tree HEAD^{tree} -p HEAD -m 'other')"   # PR head 가 아닌 «다른 커밋»
LEDGER="$T/ledger.md"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" \
  FAKE_GH_JSON="${FAKE_GH_JSON:-$T/gh.json}" FAKE_GH_RC="${FAKE_GH_RC:-0}" FAKE_GH_SLEEP="${FAKE_GH_SLEEP:-0}" "$@" 2>&1 ); }
setup() {  # 명부·pane·카드·나노 HEAD 를 «정상(세션 없음 · 미커밋 0 · 착지 끝)» 으로 리셋
  git -C "$NW" reset -q --hard "$SHA0"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"; unset FAKE_GH_RC FAKE_GH_SLEEP   # ⓔ 가 건 값이 다음 축으로 새지 않게
  rm -f "$NW/.worktree-info.json"
  printf '# 인덱스: lp\n## 상태\n- 2026-10-27 진행\n- 세트: %s · 시험: bash t.sh (12 passed) rc=0 · 이슈: 0\n\n## 정본\n- 착지 끝 좌석은 PR 이 증거\n- 착지: PR #363 merged · squash\n' "$SHA0" > "$CARD"
  # gh 응답 기본값 = MERGED ∧ head == 카드 세트
  printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$SHA1" "$SHA0" > "$T/gh.json"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {  # untouched <이름> — REJECT/usage 인데 명부·tmux·원장·gh 밖이 그대로
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
  git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로(삭제 0)" || bad "$1: 브랜치 삭제"
}

echo "== ⓐ MERGED ∧ head==세트 ∧ «- 착지:» 줄 → CLOSED-ABSENT landed-pr=363 · 원장 · 명부 삭제 · 브랜치 보존"
setup; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:800}"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 자리 = LANDED-PR-OK"
has "$out" "merged=${SHA1:0:9} state=MERGED head=${SHA0:0:9} == 카드 세트" "  └ 값 3개(mergeCommit·state·head==세트)를 화면에"
has "$out" "INFO ⑤ cherry 건너뜀 — 착지 끝 좌석(PR #363)" "  └ ⑤ cherry = 가지 비교 0(INFO)"
hasnt "$out" "OK 증거 줄" "  └ ⑥ 증거 줄 검사 면제"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "  └ CLOSED-ABSENT <좌석> landed-pr=<N>"
has "$(cat "$LEDGER")" "landed-pr=363" "  └ 원장 닫힘 행에 landed-pr=<N>"
has "$(cat "$LEDGER")" "닫힘(ft-nano-close)" "  └ 기존 원장 행 꼴 그대로"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 CLOSED(기존 경로)" || bad "명부에 좌석 남음"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 실재(삭제 0)" || bad "브랜치 삭제됨"
[ "$(cat "$T/ghlog")" = "pr view 363 --json state,mergeCommit,headRefOid" ] && ok "  └ gh 호출 1회 · 인자 그대로" || bad "gh 호출: $(cat "$T/ghlog")"
[ -d "$NW" ] && ok "  └ 좌석 워크트리 그대로(정리 계획만)" || bad "좌석 워크트리 사라짐"

echo "== ⓑ PR head ≠ 카드 세트 → REJECT · 닫기 0"
setup; printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$SHA1" "$SHA1" > "$T/gh.json"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓑ head 다름 → REJECT" || bad "ⓑ rc=$rc ← ${out:0:600}"
has "$out" "≠ 카드 세트" "  └ 사유 = head ≠ 카드 세트"
untouched "ⓑ"

echo "== ⓒ PR 이 MERGED 가 아님(OPEN · CLOSED 미병합) → REJECT · 닫기 0"
for st in OPEN CLOSED; do
  setup; printf '{"state":"%s","mergeCommit":null,"headRefOid":"%s"}\n' "$st" "$SHA0" > "$T/gh.json"
  out="$(close --landed-pr 363)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "state=$st — MERGED 만 닫는다" "ⓒ state=$st → REJECT" || bad "ⓒ $st rc=$rc ← ${out:0:600}"
  untouched "ⓒ $st"
done

echo "== ⓓ 카드에 «- 착지:» 줄 없음 → REJECT · gh 호출 0"
setup; printf '# 인덱스: lp\n## 상태\n- 세트: %s · 시험: bash t.sh (12 passed) rc=0 · 이슈: 0\n' "$SHA0" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«- 착지:» 줄이 없다" "ⓓ 착지 줄 없음 → REJECT" || bad "ⓓ rc=$rc ← ${out:0:600}"
[ ! -s "$T/ghlog" ] || [ "$(grep -c . <<< "$(cat "$T/ghlog")")" = 1 ] && ok "  └ PR 조회는 카드 대조보다 먼저 1회(순서 = PR 먼저)" || bad "  └ PR 조회 $(grep -c . <<< "$(cat "$T/ghlog")")회"
untouched "ⓓ"
setup; printf '# 인덱스: lp\n## 상태\n- 2026-10-27 진행\n- 착지: PR #363\n' > "$CARD"   # 세트 줄 없음
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«## 상태» 절에 «세트:» 40-hex 줄이 없다" "ⓓ 세트 줄 없음 → REJECT" || bad "ⓓ 세트 rc=$rc ← ${out:0:600}"
untouched "ⓓ 세트"

echo "== ⓔ gh 실패(rc≠0) → REJECT · gh 8초(상한 7초) → REJECT"
setup; FAKE_GH_RC=1 out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "gh pr view 363 실패(rc=1" "ⓔ gh rc≠0 → REJECT" || bad "ⓔ rc=$rc ← ${out:0:600}"
untouched "ⓔ rc≠0"
setup; _t0="$(date +%s)"; FAKE_GH_SLEEP=8 out="$(close --landed-pr 363)"; rc=$?; _el=$(( $(date +%s) - _t0 ))
[ "$rc" -eq 1 ] && has "$out" "gh 시간 초과(7초 상한" "ⓔ gh 8초 → REJECT(상한 7초)" || bad "ⓔ 느린 gh rc=$rc ← ${out:0:600}"
[ "$_el" -le 30 ] && ok "  └ 상한이 실제로 끊었다(경과 ${_el}s)" || bad "  └ 경과 ${_el}s — 상한이 안 걸렸다"
untouched "ⓔ 8초"

echo "== ⓕ 모드 충돌 · 빈 번호 → usage 2 · 인자 없으면 불변"
usage2() { local name="$1"; shift; setup; out="$(close "$@")"; rc=$?
  [ "$rc" -eq 2 ] && ok "$name → usage rc=2" || bad "$name — rc=$rc ← ${out:0:300}"; untouched "$name"; }
usage2 "ⓕ --landed-pr + --suspended" --landed-pr 363 --suspended "팀 정지"
usage2 "ⓕ --landed-pr + --shared-wt" --landed-pr 363 --shared-wt
usage2 "ⓕ --landed-pr + --cherry-override" --landed-pr 363 --cherry-override "사람 사유"
usage2 "ⓕ --landed-pr + --never-started" --landed-pr 363 --never-started "발주 0"
usage2 "ⓕ --landed-pr + --research" --landed-pr 363 --research
usage2 "ⓕ --landed-pr \"\"" --landed-pr ""
usage2 "ⓕ --landed-pr 값 누락" --landed-pr
setup; out="$(close)"; rc=$?   # 인자 없음 = 기존 경로(⑥ 증거 줄이 «세트 != HEAD» 로 막힌다)
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓕ 인자 없음 → 기존 경로 그대로(rc=1)" || bad "ⓕ 인자 없음 rc=$rc ← ${out:0:600}"
hasnt "$out" "landed-pr" "  └ landed-pr 표식 없음"
untouched "ⓕ 인자 없음"

echo "== ⓖ 변이 «head 대조 끔» → ⓑ 가 닫힌다(가드가 실제로 잡는가)"
rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
python3 - "$T/mutbin/ft-nano-close.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'elif [ "$_lp_head" != "$_lp_set" ]; then'
assert old in s, "변이 자리 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, 'elif false; then', 1))
PY
setup; printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$SHA1" "$SHA1" > "$T/gh.json"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓖ 변이(대조 끔) → head 가 달라도 닫힘 = ⓑ 가 잡는다(변이 FAIL)" || bad "ⓖ 변이 rc=$rc — 변이가 안 먹었다(ⓑ 가 다른 이유로 막힘): $(printf '%s' "$out" | head -3)"

echo "== ⓘ 세트 줄은 «## 상태» 절 안의 마지막 줄만 (DA⑥ r2 HOLD ①)"
setup; printf '# 인덱스: lp\n## 상태\n- 세트: %s · 시험: bash t.sh (12 passed) rc=0 · 이슈: 0\n\n## 참고\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n- 착지: PR #363\n' "$SHA1" "$SHA0" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "≠ 카드 세트" "ⓘ 상태 절 세트(≠head) · 절 밖 세트(=head) → REJECT" || bad "ⓘ rc=$rc ← ${out:0:600}"
untouched "ⓘ 절 밖 세트 무시"
setup; printf '# 인덱스: lp\n## 상태\n- 세트: %s · 시험: bash t.sh (12 passed) rc=0 · 이슈: 0\n\n## 참고\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n- 착지: PR #363\n' "$SHA0" "$SHA1" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "ⓘ 상태 절 세트 = head(뒤 절은 다른 sha) → CLOSED" || bad "ⓘ rc=$rc ← ${out:0:600}"
setup; printf '# 인덱스: lp\n## 상태\n- 2026-10-27 진행\n- 착지: PR #363\n\n## 참고\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA0" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«## 상태» 절에 «세트:» 40-hex 줄이 없다" "ⓘ 상태 절에 세트 줄 0(절 밖에만) → REJECT" || bad "ⓘ 세트 rc=$rc ← ${out:0:600}"
untouched "ⓘ 상태 절 세트 0"

rerun_setup() {  # ⓙ 명부 부재 + 원장 닫힘 행 + 대역 세션 살아 있음
  setup; printf '{}\n' > "$REPO/.fable-team/seats-planner.json"
  printf -- '- **[2026-10-27 10:00 KST] `%s` 닫힘(ft-nano-close)**: ①결과 `x` ②회수 seq 1 ③세션 없음(백필). kill=1 · wt=planned\n' "$SEAT" > "$LEDGER"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; : > "$T/tlog"
}
echo "== ⓙ 명부 부재 · 원장 닫힘 행 · 대역 세션 + 없는 PR → gh 1회 · kill 0 · REJECT (DA⑥ r2 HOLD ②)"
rerun_setup; FAKE_GH_RC=1 out="$(close --landed-pr 999999)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "gh pr view 999999 실패" "ⓙ 없는 PR → REJECT" || bad "ⓙ rc=$rc ← ${out:0:600}"
[ "$(grep -c . <<< "$(cat "$T/ghlog")")" = 1 ] && ok "  └ gh 호출 1회" || bad "  └ gh 호출: $(cat "$T/ghlog")"
[ ! -s "$T/tlog" ] && ok "  └ kill·태그 해제 0(조기 재실행보다 먼저 막힘)" || bad "  └ tmux 변경: $(cat "$T/tlog")"
[ "$(grep -c '닫힘(ft-nano-close)' "$LEDGER")" = 1 ] && ok "  └ 원장 append 0" || bad "  └ 원장 행 $(grep -c '닫힘(ft-nano-close)' "$LEDGER")개"
rerun_setup; out="$(close --landed-pr 363)"; rc=$?   # PR 은 MERGED 인데 명부에 행이 없다
[ "$rc" -eq 1 ] && has "$out" "명부에 좌석 행이 없어 카드 index 를 알 수 없다" "ⓙ MERGED 지만 명부 부재 → REJECT(조용한 통과 0)" || bad "ⓙ MERGED rc=$rc ← ${out:0:600}"
[ ! -s "$T/tlog" ] && ok "  └ kill·태그 해제 0" || bad "  └ tmux 변경: $(cat "$T/tlog")"

mutant() {  # mutant <old> <new> [<old2> <new2> …] → $T/mutbin/ft-nano-close.sh (매번 새 사본 · 여러 자리 한 번에)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; pairs = sys.argv[2:]
s = open(p, encoding="utf-8").read()
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    assert old in s, "변이 자리 없음: " + old[:60]
    s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
PY
}
echo "== ⓚ 변이 «절 경계 무시» → ⓘ(절 밖 세트 무시) 가 닫혀 버린다"
mutant 'inb && /세트:/{l=$0}' '/세트:/{l=$0}'
setup; printf '# 인덱스: lp\n## 상태\n- 세트: %s · 시험: bash t.sh (12 passed) rc=0 · 이슈: 0\n\n## 참고\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n- 착지: PR #363\n' "$SHA1" "$SHA0" > "$CARD"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓚ 변이(절 경계 무시) → 절 밖 세트로 닫힘 = ⓘ 가 잡는다(변이 FAIL)" || bad "ⓚ 변이 rc=$rc — 변이가 안 먹었다: $(printf '%s' "$out" | head -2)"
echo "== ⓚ 변이 «재실행 경로 선행» → ⓙ(PR 검증 먼저) 가 kill 로 넘어간다"
mutant 'if [ -n "$LANDED_PR" ]; then _lp_fetch_pr || { echo "REJECT $SEAT"; echo "  - $_lp_pr_err"; exit 1; }; fi' ':' \
  '[ -z "$LANDED_PR" ] || { echo "REJECT $SEAT"; echo "  - ⑥--landed-pr: 명부에 좌석 행이 없어 카드 index 를 알 수 없다 — «세트»·«- 착지:» 대조 불가(닫기 0 · kill 0 · 원장 append 0) · 명부 행을 복구하거나 카드 경로를 확인해라"; exit 1; }' ':'
rerun_setup; FAKE_GH_RC=1 out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 999999)"; rc=$?
{ [ "$rc" -eq 0 ] || [ -s "$T/tlog" ]; } && ok "ⓚ 변이(검증 선행 제거) → kill 로 넘어감 = ⓙ 가 잡는다(변이 FAIL)" || bad "ⓚ 변이 rc=$rc — 변이가 안 먹었다: $(printf '%s' "$out" | head -2)"

echo "== ⓗ 600/300 s · 외부 호출(네트워크) · GIT_* env 0"
NEWL="$(grep 'LANDED_PR\|_lp_' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓗ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|nc ')" ":" "ⓗ 외부 호출 0 (gh 1회만)"
hasnt "$NEWL" "GIT_DIR=" "ⓗ GIT_DIR env 0"
hasnt "$NEWL" "GIT_WORK_TREE=" "ⓗ GIT_WORK_TREE env 0"
[ "$(printf '%s\n' "$NEWL" | grep -c 'nf_bound "$cap" gh pr view')" = 1 ] && ok "ⓗ PR 조회는 정확히 1곳(상한 걸린 nf_bound)" || bad "ⓗ PR 조회 $(printf '%s\n' "$NEWL" | grep -c 'gh pr view')곳"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
