#!/usr/bin/env bash
# test_nano_close_local_main_base_r1402.sh — 카드 r1402: 좌석 info base 가 정확히 «main» 이고 refs/remotes/origin/main 이 있으면
#   ft-nano-close 가 origin/main 으로 바꿔 읽는다(R22 fetch → ⑥·⑤·freshness 원격 기준) · 원격 ref 없음·다른 가지 이름은 지금 그대로.
# 계약↔시험: base main → origin/main = C1·C2·C3 + M1 · 원격 없음·다른 이름 그대로 = C4·C6·C6b + M2·M3 · fetch 실패 그 자리 REJECT = C5
# 임시 git 리포 + 가짜 원격 bare(url.insteadOf) + 가짜 tmux·gh(PATH 앞) — 실 리포·명부·tmux·gh·네트워크 0 · sleep 0. 꼴 = test_nano_close_base_sha_main_r1122.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
TRK="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

echo "== bin·kit 같은 내용"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
cmp -s "$SRC/ft-nano-close.sh" "$TRK/ft-nano-close.sh" && ok "사본 cmp" || bad "사본 불일치"

# ── 픽스처: 로컬 main = S0 · 원격 main = S0→O1→O2→O3(다른 팀 파일)→LAND(가지 squash) · 나노는 O3 에서
URL='https://github.com/lptest/byz.git'
REPO="$T/repo"; BARE="$T/remote.git"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init
echo s0 > "$REPO/s0.txt"; GIT add s0.txt; GIT commit -q -m s0; S0="$(GIT rev-parse HEAD)"
GIT checkout -q --detach   # main 을 체크아웃에서 떼어 update-ref 로 자유롭게 옮긴다
git init -q --bare "$BARE"
GIT remote add origin "$URL"; GIT config "url.$BARE.insteadOf" "$URL"
GIT push -q origin main
GIT worktree add -q --detach "$T/other" "$S0"
for i in 1 2 3; do echo "o$i" > "$T/other/other$i.txt"; git -C "$T/other" add "other$i.txt"; git -C "$T/other" -c user.email=t@t -c user.name=t commit -q -m "other team $i"; done
O3="$(git -C "$T/other" rev-parse HEAD)"
mkdir -p "$REPO/.fable-team" "$REPO/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
echo ".worktree-info.json" >> "$REPO/.git/info/exclude"
SEAT='byz-ops-nano-lm#0'; CARD="$REPO/design/ops/indices/진행/lm.md"
NW="$REPO/.worktrees/lm"; BR="nano/lm"
GIT worktree add -q "$NW" -b "$BR" "$O3"
echo work > "$NW/work.txt"; git -C "$NW" add work.txt; git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m work
SHA="$(git -C "$NW" rev-parse HEAD)"
git -C "$T/other" merge --squash -q "$BR" >/dev/null 2>&1; git -C "$T/other" -c user.email=t@t -c user.name=t commit -q -m "squash land"
LANDSHA="$(git -C "$T/other" rev-parse HEAD)"; GIT update-ref refs/land "$LANDSHA"
git -C "$BARE" fetch -q "$REPO" refs/land:refs/heads/main
[ "$(git -C "$BARE" rev-parse main)" = "$LANDSHA" ] || { echo "FAIL 픽스처: 원격 main ≠ 착지"; exit 1; }
# C6·C6b: 다른 가지 이름(feat/x · main-x) — 로컬·원격 둘 다 S0
for b in feat/x main-x; do GIT branch "$b" "$S0"; GIT push -q origin "$b"; done

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh \
         ft-wt-sweep.sh ft-team-lib.sh ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py \
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

mutate() {  # mutate <out> <old> <new>
  python3 - "$T/bin/ft-nano-close.sh" "$@" <<'PY'
import sys
src, out, a, b = sys.argv[1:5]; s = open(src, encoding='utf-8').read()
assert s.count(a) == 1, f"변이 자리 {s.count(a)}곳: {a}"
open(out, 'w', encoding='utf-8').write(s.replace(a, b))
PY
}
COND='if [ "$_INFO_FEAT" = main ] && git -C "$SEAT_REPO" rev-parse --verify -q refs/remotes/origin/main >/dev/null; then'
mutate "$T/bin/base-close.sh" "$COND" 'if false; then' || bad "기준판(M1) 사본 실패"
mutate "$T/bin/m2-close.sh" "$COND" 'if case "$_INFO_FEAT" in main*) true;; *) false;; esac && git -C "$SEAT_REPO" rev-parse --verify -q refs/remotes/origin/main >/dev/null; then' || bad "M2 사본 실패"
mutate "$T/bin/m3-close.sh" "$COND" 'if [ "$_INFO_FEAT" = main ]; then' || bad "M3 사본 실패"

ENVFEAT=""
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" ${ENVFEAT:+FT_NANO_FEAT="$ENVFEAT"} FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-ops.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$@" 2>&1 ); }   # env 뒤 명령 = 글자 bash(비밀 분류기)
# setup <info base> <로컬 main> <origin/main 추적 ref | -(없음)> [원격 url 막음 1]
setup() {
  printf '{"branch":"%s","base":"%s","purpose":"t"}\n' "$BR" "$1" > "$NW/.worktree-info.json"
  printf '{"%s":{"role":"nano","index":"design/ops/indices/진행/lm.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-ops.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ghlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  git -C "$REPO" update-ref refs/heads/main "$2"
  if [ "$3" = - ]; then git -C "$REPO" update-ref -d refs/remotes/origin/main 2>/dev/null; else git -C "$REPO" update-ref refs/remotes/origin/main "$3"; fi
  if [ "${4:-0}" = 1 ]; then git -C "$REPO" config "url.$T/missing.git.insteadOf" "$URL"; git -C "$REPO" config --unset "url.$BARE.insteadOf"
  else git -C "$REPO" config --unset "url.$T/missing.git.insteadOf" 2>/dev/null; git -C "$REPO" config "url.$BARE.insteadOf" "$URL"; fi
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { local cl="$1"; shift; run "$cl" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR" "$@"; }
INFO='INFO base main → origin/main'
WARNIG='무시(둘 다 있고 다름)'
cnt() { printf '%s\n' "$1" | grep -cF -- "$2"; }
pass_check() {  # pass_check <close> → 0 = rc0 · INFO 1줄 · WARN 무시 0 · CLOSED
  local out rc; out="$(close "$1")"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  rc=$rc ← ${out:0:900}"; return 1; }
  [ "$(cnt "$out" "$INFO")" = 1 ] || { echo "  INFO 줄 $(cnt "$out" "$INFO")개"; return 1; }
  case "$out" in *"$WARNIG"*) echo "  WARN 무시 줄 있음"; return 1;; esac
  case "$out" in *"CLOSED $SEAT"*) ;; *) echo "  CLOSED 없음"; return 1;; esac
  return 0
}
norm() { printf '%s\n' "$1" | sed -E 's/^(STEP .*) \+[0-9]+s$/\1 +Ns/'; }
same_check() {  # same_check <close 새판> <setup 인자…> → 0 = 기준판과 출력·rc 같음 · INFO 0줄
  local cl="$1"; shift; local o1 o2 r1 r2
  setup "$@"; o1="$(close "$cl")"; r1=$?
  setup "$@"; o2="$(close "$T/bin/base-close.sh")"; r2=$?
  [ "$r1" = "$r2" ] && [ "$(norm "$o1")" = "$(norm "$o2")" ] || { echo "  기준판과 다름 rc $r1/$r2"; diff <(norm "$o2") <(norm "$o1") | head -8; return 1; }
  case "$o1" in *"$INFO"*) echo "  INFO 줄 있음"; return 1;; esac
  return 0
}
NEW="$T/bin/ft-nano-close.sh"

echo "== C1 base main · 로컬 main 3커밋+ 뒤 · 가지는 origin/main 에 squash → 통과 · INFO 1줄"
setup main "$S0" "$S0"; o="$(pass_check "$NEW")" && ok C1 || bad "C1$(printf '\n%s' "$o")"
echo "== C2 C1 꼴 + FT_NANO_FEAT=origin/main → 통과 · WARN 무시 0줄"
ENVFEAT=origin/main; setup main "$S0" "$S0"; o="$(pass_check "$NEW")" && ok C2 || bad "C2$(printf '\n%s' "$o")"; ENVFEAT=""
echo "== C3 base main · 로컬 main == origin/main(착지 포함) → 통과 · INFO 1줄 · 판정은 기준판과 같음(rc)"
setup main "$LANDSHA" "$LANDSHA"; o="$(pass_check "$NEW")" && ok C3 || bad "C3$(printf '\n%s' "$o")"
setup main "$LANDSHA" "$LANDSHA"; close "$T/bin/base-close.sh" >/dev/null; r=$?; [ "$r" -eq 0 ] && ok "  └ C3 기준판도 rc0" || bad "C3 기준판 rc=$r"
echo "== C4 base main · refs/remotes/origin/main 없음 → 로컬 main 그대로(기준판과 같음) · INFO 0줄"
o="$(same_check "$NEW" main "$S0" -)" && ok C4 || bad "C4$(printf '\n%s' "$o")"
echo "== C5 base main · origin main fetch 실패 → REJECT «⑤ origin/main fetch 실패» · cherry·freshness 0"
setup main "$S0" "$S0" 1; out="$(close "$NEW")"; rc=$?
[ "$rc" -eq 1 ] && ok "C5 rc=1" || bad "C5 rc=$rc ← ${out:0:600}"
case "$out" in *"⑤ origin/main fetch 실패(origin/main)"*) ok "  └ C5 fetch 실패 REJECT";; *) bad "C5 문구 없음 ← ${out:0:600}";; esac
case "$out" in *"CLOSED $SEAT"*) bad "C5 닫힘";; *) ok "  └ C5 닫기 0";; esac
[ -z "$(cat "$T/tlog")" ] && ok "  └ C5 tmux 변경 0" || bad "C5 tmux 변경: $(cat "$T/tlog")"
echo "== C6 base feat/x(로컬 · origin/feat/x 있음) → 바꾸지 않음(기준판과 같음)"
o="$(same_check "$NEW" feat/x "$S0" "$S0")" && ok C6 || bad "C6$(printf '\n%s' "$o")"
echo "== C6b base main-x(접두만 같음) → 바꾸지 않음(기준판과 같음)"
o="$(same_check "$NEW" main-x "$S0" "$S0")" && ok C6b || bad "C6b$(printf '\n%s' "$o")"

echo "== M1 바꿔 읽기 삭제(=기준판) → C1·C2 FAIL 이어야 한다"
setup main "$S0" "$S0"; pass_check "$T/bin/base-close.sh" >/dev/null && bad "M1 이 C1 통과" || ok "M1 → C1 FAIL(잡힘)"
ENVFEAT=origin/main; setup main "$S0" "$S0"; pass_check "$T/bin/base-close.sh" >/dev/null && bad "M1 이 C2 통과" || ok "M1 → C2 FAIL(잡힘)"; ENVFEAT=""
echo "== M2 «main» 비교를 접두(main*)로 넓힘 → C6b FAIL 이어야 한다"
same_check "$T/bin/m2-close.sh" main-x "$S0" "$S0" >/dev/null && bad "M2 가 C6b 통과" || ok "M2 → C6b FAIL(잡힘)"
echo "== M3 원격 ref 있음 검사 삭제 → C4 FAIL 이어야 한다"
same_check "$T/bin/m3-close.sh" main "$S0" - >/dev/null && bad "M3 가 C4 통과" || ok "M3 → C4 FAIL(잡힘)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
