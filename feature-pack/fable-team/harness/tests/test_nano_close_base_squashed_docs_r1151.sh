#!/usr/bin/env bash
# test_nano_close_base_squashed_docs_r1151.sh — 카드 r1151: base_sha 가 팀 가지·origin/main 어느 쪽 조상도 아니어도
#   merge-base(base_sha, origin/main)..base_sha 가 *.md 만 바꿨으면 «squash 된 문서 가지» — 랜딩 브랜치 origin/main · 코드 섞이면 REJECT 그대로.
# 계약↔시험: ⓐ R1(팀 가지·origin/main 두 꼴 + --landed-pr) INFO · REJECT 0 + 변이 1(갈래 삭제 → R1 FAIL) · ⓑ R2·R4 REJECT 그대로
#   · ⓒ R3 r1122 INFO 그대로 · ⓓ bin·kit cmp
# 임시 git 리포 + 가짜 원격 bare(url.insteadOf) + 가짜 tmux·gh(PATH 앞) — 실 리포·명부·tmux·gh·네트워크 0 · 자기 재호출 0 · 고정 sleep 0. 꼴 = test_nano_close_base_sha_main_r1122.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
TRK="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓓ bin·kit 같은 내용"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"
cmp -s "$SRC/ft-nano-close.sh" "$TRK/ft-nano-close.sh" && ok "사본 cmp" || bad "사본 불일치"

# ── 픽스처: M0 → 문서 가지 D(카드 .md · 한글 경로) → main 에 squash S · 나노 base = D · 나노 작업은 원격 main 에 squash 착지
#    D2 = 카드 .md + 코드 .sh(R2) · ORPH = 공통 조상 없는 커밋(R4) · TEAM = 뒤처진 팀 가지(M0)
URL='https://github.com/lptest/byz.git'
REPO="$T/repo"; BARE="$T/remote.git"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init; M0="$(GIT rev-parse HEAD)"
TEAM=feat/t-main; GIT branch "${TEAM}" "$M0"
CARDDOC="design/v65/indices/대기/m5-card.md"
GIT checkout -q -b docs; mkdir -p "$REPO/design/v65/indices/대기"; echo card > "$REPO/$CARDDOC"; GIT add "$CARDDOC"; GIT commit -q -m "card docs"; D="$(GIT rev-parse HEAD)"
GIT checkout -q -b docs2 "$M0"; mkdir -p "$REPO/design/v65/indices/대기"; echo card2 > "$REPO/$CARDDOC"; echo 'echo x' > "$REPO/tool.sh"
GIT add "$CARDDOC" tool.sh; GIT commit -q -m "card+code"; D2="$(GIT rev-parse HEAD)"
GIT checkout -q main
GIT merge --squash -q docs >/dev/null 2>&1; GIT commit -q -m "squash docs"; S="$(GIT rev-parse HEAD)"
ORPH="$(GIT commit-tree "$(git -C "$REPO" mktree </dev/null)" -m orphan)"
git init -q --bare "$BARE"
GIT remote add origin "$URL"; GIT config "url.$BARE.insteadOf" "$URL"
GIT push -q origin main
mkdir -p "$REPO/.fable-team" "$REPO/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
echo ".worktree-info.json" >> "$REPO/.git/info/exclude"
SEAT='byz-ops-nano-bs#0'; CARD="$REPO/design/ops/indices/진행/bs.md"
NW="$REPO/.worktrees/bs"; BR="nano/bs"
GIT worktree add -q "$NW" -b "$BR" "$D"
echo work > "$NW/work.txt"; git -C "$NW" add work.txt; git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m work
SHA="$(git -C "$NW" rev-parse HEAD)"
GIT worktree add -q --detach "$T/land" "$S"
git -C "$T/land" merge --squash -q "$BR" >/dev/null 2>&1; git -C "$T/land" -c user.email=t@t -c user.name=t commit -q -m "squash land"
LANDSHA="$(git -C "$T/land" rev-parse HEAD)"; GIT update-ref refs/land "$LANDSHA"
git -C "$BARE" fetch -q "$REPO" refs/land:refs/heads/main
[ "$(git -C "$BARE" rev-parse main)" = "$LANDSHA" ] || { echo "FAIL 픽스처: 원격 main ≠ 착지"; exit 1; }
git -C "$REPO" merge-base --is-ancestor "$D" "$LANDSHA" && { echo "FAIL 픽스처: D 가 main 조상"; exit 1; }

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh \
         ft-wt-sweep.sh ft-team-lib.sh ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py \
         ft_sheet_key.py ft_board_env.py ft_board_mail.py ft-approval-equiv.sh ft_approval_equiv.py ft-nano-freshness.sh; do
  [ ! -e "$SRC/$f" ] || cp "$SRC/$f" "$T/bin/"
done
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*
printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$LANDSHA" "$SHA" > "$T/gh.json"
# 변이 1 = r1151 갈래 삭제(=기준판)
python3 - "$T/bin/ft-nano-close.sh" "$T/bin/mut1-close.sh" <<'PY' || bad "변이 1 사본 실패"
import sys
src, out = sys.argv[1:3]; s = open(src, encoding='utf-8').read()
a = 'elif [ "$_FEAT_FETCH_FAIL" = 0 ] && _docs_only_base "$_BASE_SHA"; then'
assert s.count(a) == 1, f"변이 자리 {s.count(a)}곳"
open(out, 'w', encoding='utf-8').write(s.replace(a, 'elif false; then'))
PY

FEATENV="$TEAM"
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" \
  FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FT_NANO_FEAT="$FEATENV" "$@" 2>&1 ); }
setinfo() { printf '{"branch":"%s","base":"%s","base_sha":"%s","purpose":"t"}\n' "$BR" "$1" "$1" > "$NW/.worktree-info.json"; }
setup() {
  printf '{"%s":{"role":"nano","index":"design/ops/indices/진행/bs.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-ops.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ghlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  git -C "$REPO" update-ref refs/remotes/origin/main "$S"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { local cl="$1"; shift; run FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-ops.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$cl" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" "$@"; }
closeb() { local cl="$1"; shift; close "$cl" --branch "$BR" "$@"; }
noside() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ $1 kill·태그 해제 0" || bad "$1 REJECT 인데 tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-ops.json" >/dev/null && ok "  └ $1 명부 그대로" || bad "$1 REJECT 인데 명부 삭제"
}
NEWL="INFO base sha ${D:0:9} = squash 된 문서 가지(문서 1개) → 랜딩 브랜치 origin/main"
OLDREJ="의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시"
r1_check() {  # r1_check <close 파일> → 0 = 통과(새 INFO · REJECT 0 · CLOSED)
  setinfo "$D"; setup; local out rc; out="$(closeb "$1")"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  rc=$rc ← ${out:0:900}"; return 1; }
  case "$out" in *"$NEWL"*) ;; *) echo "  INFO 줄 없음"; return 1;; esac
  case "$out" in *"$OLDREJ"*|*REJECT*) echo "  REJECT 있음"; return 1;; esac
  case "$out" in *"CLOSED $SEAT"*) ;; *) echo "  CLOSED 없음"; return 1;; esac
  return 0
}

echo "== R1 문서 가지 D(카드 .md 1개 · squash S) 에서 연 나노 · 팀 가지 env → 랜딩 브랜치 origin/main · 닫힘"
o="$(r1_check "$T/bin/ft-nano-close.sh")" && ok "R1 INFO · REJECT 0 · CLOSED" || bad "R1$(printf '\n%s' "$o")"
echo "== R1b 같은 꼴 · FT_NANO_FEAT=origin/main(r1122 갈래 건너뜀) → 같은 INFO · 닫힘"
FEATENV=origin/main
o="$(r1_check "$T/bin/ft-nano-close.sh")" && ok "R1b INFO · REJECT 0 · CLOSED" || bad "R1b$(printf '\n%s' "$o")"
FEATENV="$TEAM"
echo "== R1c --landed-pr 로 닫는 R1 꼴(실사건 꼴) → LANDED-PR-OK + 새 INFO"
setinfo "$D"; setup; printf -- '- 착지: %s\n' "$LANDSHA" >> "$CARD"; out="$(close "$T/bin/ft-nano-close.sh" --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "R1c rc=0" || bad "R1c rc=$rc ← ${out:0:900}"
has "$out" "LANDED-PR-OK #363" "  └ R1c LANDED-PR-OK"
has "$out" "$NEWL" "  └ R1c 새 INFO"
hasnt "$out" "$OLDREJ" "  └ R1c 옛 REJECT 없음"
echo "== 변이 1: 갈래 삭제 → R1 FAIL 이어야 한다"
r1_check "$T/bin/mut1-close.sh" >/dev/null && bad "변이 1 이 R1 을 통과 — 시험이 갈래를 못 본다" || ok "변이 1 → R1 FAIL(잡힘)"

echo "== R2 문서 가지가 코드(.sh)도 바꿈 → REJECT «조상이 아니다» 그대로"
setinfo "$D2"; setup; out="$(closeb "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 1 ] && ok "R2 rc=1" || bad "R2 rc=$rc"
has "$out" "base 가 sha ${D2:0:9} 이고 ${TEAM} $OLDREJ" "  └ R2 REJECT 문구 그대로"
hasnt "$out" "squash 된 문서 가지" "  └ R2 새 INFO 없음"
noside R2

echo "== R3 base_sha 가 origin/main 조상(S) → r1122 INFO 그대로 · 새 갈래 안 탐"
setinfo "$S"; setup; out="$(closeb "$T/bin/ft-nano-close.sh")"
has "$out" "INFO base sha ${S:0:9} → 랜딩 브랜치 origin/main(팀 가지 ${TEAM} 뒤처짐" "  └ R3 r1122 INFO 그대로"
hasnt "$out" "squash 된 문서 가지" "  └ R3 새 INFO 없음"

echo "== R4 base_sha 와 origin/main 공통 조상 없음 → REJECT 그대로"
setinfo "$ORPH"; setup; out="$(closeb "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 1 ] && ok "R4 rc=1" || bad "R4 rc=$rc"
has "$out" "base 가 sha ${ORPH:0:9} 이고 ${TEAM} $OLDREJ" "  └ R4 REJECT 문구 그대로"
hasnt "$out" "squash 된 문서 가지" "  └ R4 새 INFO 없음"
hasnt "$out" "판정 불가" "  └ R4 판정 불가 아님(공통 조상 없음 = rc1)"
noside R4

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
