#!/usr/bin/env bash
# test_nano_close_superseded_hint_r1733.sh — r1733: ft-nano-close.sh ⑥ REJECT(⑥카드 못 찾음 4곳 · ⑥--landed-pr NOT-EQUIV) 사유 줄 «뒤» 에 «다음:» 1줄
#   = 같은 번호 카드가 indices/{진행,완성,아카이브}/r<번호>-*.md 에 정확히 1개면 --superseded-by 꼴 · 0·2개 이상 = 개수만 · 번호 못 뽑음 = 판정 불가.
#   판정·첫 줄·사유 줄·rc 1·명부·원장·kill 은 기준판 그대로(A4) — 안내 줄만 늘어난다. 그 밖 REJECT 갈래 = 안내 0. 반례 ①~⑦(카드 동결) + 변이 M1~M3(각각 원본 대조).
#   임시 git 리포 + gh·tmux 스텁만 — 실 리포·좌석·tmux·gh(네트워크)·sleep 0 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }
echo "== 짝 cmp(bin == kit) · bash -n · /bin/bash 3.2 -n"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"
mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-wt-sweep.sh ft-team-lib.sh \
         ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py \
         ft_board_mail.py ft-approval-equiv.sh ft_approval_equiv.py; do cp "$SRC/$f" "$T/bin/"; done
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
printf '#!/usr/bin/env bash\necho "$*" >> "$FAKE_GH_LOG"\ncat "$FAKE_GH_JSON"\n' > "$T/fake/gh"
chmod +x "$T/bin/"* "$T/fake/"*
REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
BYZ_URL='https://github.com/lptest/byz.git'
git -C "$REPO" remote add origin "$BYZ_URL"; git -C "$REPO" config "url.$REPO.insteadOf" "$BYZ_URL"
IDXDIR="$REPO/design/harness/indices"; mkdir -p "$REPO/.fable-team" "$IDXDIR/진행" "$IDXDIR/완성" "$IDXDIR/아카이브" "$T/comm/bodies"
echo m1 > "$REPO/main.txt"; git -C "$REPO" add main.txt; git -C "$REPO" commit -q -m 'main 1'; M1="$(git -C "$REPO" rev-parse HEAD)"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
mk() {  # mk <부모> <메시지> <경로=내용>… → 새 커밋 sha(작업 트리 0 · 임시 index)
  local parent="$1" msg="$2" kv p blob idx="$T/idx.$$"; shift 2; rm -f "$idx"; GIT_INDEX_FILE="$idx" git -C "$REPO" read-tree "$parent"
  for kv in "$@"; do p="${kv%%=*}"; blob="$(printf '%s\n' "${kv#*=}" | git -C "$REPO" hash-object -w --stdin)"
    GIT_INDEX_FILE="$idx" git -C "$REPO" update-index --add --cacheinfo "100644,$blob,$p"; done
  git -C "$REPO" commit-tree "$(GIT_INDEX_FILE="$idx" git -C "$REPO" write-tree)" -p "$parent" -m "$msg"; }
DOC="$(mk "$M1" docs 'design/teams/x/a.md=a')"
S2="$(mk "$DOC" set2 'design/teams/x/c.md=c')"                 # ② 세트 = 팀 문서만(코드 0) → cherry 길 아님 · 판정기 사유 그대로
H2="$(mk "$M1" pr902 'design/teams/x/z.md=z')"                 # ② PR head ≠ 세트
Q="$(git -C "$REPO" commit-tree "$M1^{tree}" -p "$M1" -m 'squash 902' -m "PR #902 (head $H2)")"   # 착지 게이트 = 끝줄 «PR #N (head <H>)»
git -C "$REPO" update-ref refs/heads/main "$Q"; git -C "$REPO" reset -q --hard "$Q"; git -C "$REPO" update-ref refs/remotes/origin/main "$Q"
SEAT='byz-harness-nano-h#0'; NW="$REPO/.worktrees/harness-h"; git -C "$REPO" worktree add -q "$NW" -b nano/h "$S2"; LEDGER="$T/ledger.md"
card() {  # card <rel> [<세트 sha>] — 카드 1장(②는 착지 대조용 «세트:»·«- 착지:» 줄 필요)
  printf '# 인덱스: h\n## 상태\n- 2026-11-12 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 대상: %s/main.txt\n- 착지: PR #902 squash\n' "${2:-$M1}" "$REPO" > "$REPO/$1"; }
setup() {  # setup <명부 index 상대경로> — 명부·pane·gh·원장·카드 폴더를 리셋(카드 파일은 각 사례가 만든다)
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$1" > "$REPO/.fable-team/seats-harness.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  find "$IDXDIR" -name 'r9*.md' -delete; rm -f "$NW/dirty.txt"
  printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$H2" > "$T/gh.json"; }
close() {  # close [인자…] — CLOSE_BIN 으로 원본/변이를 바꿔 끼운다
  ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
    FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" \
    FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=main FT_SEATS_JSON="$REPO/.fable-team/seats-harness.json" \
    FT_NANO_LEDGER="$LEDGER" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
    bash "${CLOSE_BIN:-$T/bin}/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh (문자열 1곳 치환)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, "변이 자리 %d곳: %s" % (s.count(old), old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
dline() { printf '%s\n' "$1" | grep -F '다음:' | head -1; }
echo "== ① 명부 index = 진행/r9001-old.md(없음) · 완성/r9001-new.md 1개 → ⑥카드 못 찾음 + --superseded-by 안내(rc=1)"
setup 'design/harness/indices/진행/r9001-old.md'; echo x > "$IDXDIR/완성/r9001-new.md"
cp "$REPO/.fable-team/seats-harness.json" "$T/seats.pre"; cp "$LEDGER" "$T/ledger.pre"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && ok "① rc=1" || bad "① rc=$rc ← ${out:0:700}"
has "$out" "⑥카드 못 찾음:" "  └ ⑥카드 못 찾음 사유 줄 그대로"
has "$(dline "$out")" "다음: 같은 번호 카드 design/harness/indices/완성/r9001-new.md — 대체됐으면 bash ft-nano-close.sh $SEAT --superseded-by design/harness/indices/완성/r9001-new.md" "  └ 다음: 같은 번호 카드 1개 + --superseded-by 꼴"
[ "$(printf '%s\n' "$out" | tail -1)" = "$(dline "$out")" ] && ok "  └ «다음:» = 마지막 줄(사유 줄 뒤)" || bad "  └ «다음:» 위치: $(printf '%s\n' "$out" | tail -1)"
cmp -s "$REPO/.fable-team/seats-harness.json" "$T/seats.pre" && ok "  └ ⑦ 명부 그대로(cmp0)" || bad "  └ ⑦ 명부 변경"
cmp -s "$LEDGER" "$T/ledger.pre" && ok "  └ ⑦ 원장 그대로(cmp0)" || bad "  └ ⑦ 원장 변경"
echo "== ② --landed-pr NOT-EQUIV(gh 스텁 head ≠ 세트) + 완성/r9002-new.md 1개 → 안내 1줄(사유 갈래는 그대로)"
setup 'design/harness/indices/진행/r9002-own.md'; card 'design/harness/indices/진행/r9002-own.md' "$S2"; echo x > "$IDXDIR/완성/r9002-new.md"
out="$(close --landed-pr 902)"; rc=$?
[ "$rc" -eq 1 ] && ok "② rc=1" || bad "② rc=$rc ← ${out:0:700}"
has "$out" "«세트 + main 병합뿐» 도 아님(판정기 rc=" "  └ ⑥--landed-pr NOT-EQUIV 사유 그대로"
has "$(dline "$out")" "다음: 같은 번호 카드 design/harness/indices/완성/r9002-new.md" "  └ 다음: 옛 index 자신(진행/r9002-own.md)은 빼고 1개"
echo "== ③ 같은 번호 카드 0개 → «0개»"
setup 'design/harness/indices/진행/r9003-old.md'
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "다음: 같은 번호 카드 0개 — 명부 index 를 확인해라(추측 0)" "③ 0개 안내" || bad "③ rc=$rc ← ${out:0:700}"
echo "== ④ 같은 번호 2개(완성·아카이브) → «2개» · 경로 추측 0"
setup 'design/harness/indices/진행/r9004-old.md'; echo x > "$IDXDIR/완성/r9004-a.md"; echo x > "$IDXDIR/아카이브/r9004-b.md"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "다음: 같은 번호 카드 2개 — 명부 index 를 확인해라(추측 0)" "④ 2개 안내" || bad "④ rc=$rc ← ${out:0:700}"
hasnt "$(dline "$out")" "--superseded-by" "  └ 2개일 때 경로 추측 0"
echo "== ⑤ index 이름에 r 번호 없음 → «판정 불가»"
setup 'design/harness/indices/진행/oldcard.md'
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "다음: 판정 불가 — 명부 index 파일 이름에 r<번호> 가 없다" "⑤ 판정 불가 안내" || bad "⑤ rc=$rc ← ${out:0:700}"
echo "== ⑥ 다른 REJECT 갈래(ⓔ --wt 미커밋) → 안내 0 · 안내 끈 기준판과 바이트 같음"
setup 'design/harness/indices/진행/r9006-own.md'; card 'design/harness/indices/진행/r9006-own.md'; echo x > "$NW/dirty.txt"
out="$(close --wt "$NW" --branch nano/h)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ⓔ--wt 미커밋" "  ⑥ 다른 갈래 rc=1" || bad "⑥ rc=$rc ← ${out:0:700}"
hasnt "$out" "다음:" "  └ 안내 0"
mutant '"${bad[@]}"; nf_superseded_next_hint; exit 1' '"${bad[@]}"; exit 1'   # r1733-mut:hint
mout="$(CLOSE_BIN="$T/mutbin" close --wt "$NW" --branch nano/h)"
out2="$(printf '%s\n' "$out" | grep -v '^STEP ')"; mout2="$(printf '%s\n' "$mout" | grep -v '^STEP ' | sed "s|$T/mutbin|$T/bin|g")"   # 변이 사본 경로만 다른 INFO 줄=같은 말 · STEP 초는 계측 줄
[ "$out2" = "$mout2" ] && ok "  ⑥ 기준판(안내 끔)과 바이트 같음" || bad "  ⑥ 기준판과 다름 ← $(printf '%s' "$out2" | diff - <(printf '%s' "$mout2") | head -5)"
echo "== 변이 M1 «1개를 첫 번째로»(cnt=1) → ④ 가 «2개» 를 못 찍는다(원본 대조 = 2개)"
mutant '_hit="$_hit|$_rel"; _cnt=$((_cnt+1)); _one="$_rel"' '_hit="$_hit|$_rel"; _cnt=1; _one="$_rel"'
setup 'design/harness/indices/진행/r9004-old.md'; echo x > "$IDXDIR/완성/r9004-a.md"; echo x > "$IDXDIR/아카이브/r9004-b.md"
hasnt "$(dline "$(CLOSE_BIN="$T/mutbin" close)")" "같은 번호 카드 2개" "  └ M1 변이 FAIL(2개 → 1개로 오판)"
has "$(dline "$(close)")" "같은 번호 카드 2개" "  └ 원본 대조 = 2개(반대 결과)"
echo "== 변이 M2 «모든 REJECT 에 안내» → ⑥ 다른 갈래에 안내가 찍힌다(원본 대조 = 안내 0)"
mutant '  [ "$_h" -eq 1 ] || return 0' '  [ "$_h" -ge 0 ] || return 0'
setup 'design/harness/indices/진행/r9006-own.md'; card 'design/harness/indices/진행/r9006-own.md'; echo x > "$NW/dirty.txt"
case "$(CLOSE_BIN="$T/mutbin" close --wt "$NW" --branch nano/h)" in *"다음:"*) ok "  └ M2 변이 FAIL(다른 갈래에도 안내)";; *) bad "  └ M2 변이 생존 — 안내 0";; esac
hasnt "$(close --wt "$NW" --branch nano/h)" "다음:" "  └ 원본 대조 = ⑥ 다른 갈래 안내 0"
echo "== 변이 M3 «안내 뒤 rc 0» → ① rc 가 0(원본 대조 = rc1)"
mutant 'nf_superseded_next_hint; exit 1; fi' 'nf_superseded_next_hint; exit 0; fi'
setup 'design/harness/indices/진행/r9001-old.md'; echo x > "$IDXDIR/완성/r9001-new.md"
CLOSE_BIN="$T/mutbin" close >/dev/null; mrc=$?
[ "$mrc" -ne 1 ] && ok "  └ M3 변이 FAIL(rc=$mrc ≠ 1)" || bad "  └ M3 변이 생존 — rc=1"
close >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok "  └ 원본 대조 = rc1" || bad "  └ 원본 rc=$rc"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
