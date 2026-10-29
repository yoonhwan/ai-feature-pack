#!/usr/bin/env bash
# test_nano_detached_base_r1120.sh — 카드 r1120: detached 사본(ft-scratch = --detach linked worktree)에서 spawn 해도 info base 는 40hex,
#   옛 «HEAD» 좌석은 close 가 같은 info 의 base_sha 로 바꿔 읽는다(닫는 리포의 지금 HEAD 로 풀지 않는다).
# 계약↔시험: ⓐ R1·R2 spawn 블록 추출(PLAN·info) + 변이(detached 분기 끔) · ⓑ R3 close + 변이(교체 줄 끔) · ⓒ R4·R5 · ⓓ R6·R7 · ⓔ bin·kit cmp
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 스크립트 사본만 — 실 리포·명부·tmux·gh·원격 0 · 자기 재호출 0 · 고정 sleep 0. 꼴 = test_nano_close_sha_base.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
TRK="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓔ bin·kit 같은 내용"
for f in ft-nano-close.sh ft-nano-spawn.sh; do
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$SRC/$f" "$TRK/$f" && ok "사본 cmp $f" || bad "사본 불일치 $f"
done

# ── 픽스처 리포: main 은 FORK 뒤로 한 칸 더 간다(MAINH) — «닫는 리포의 지금 HEAD» 가 base_sha 와 다르고 랜딩 브랜치의 조상도 아니다
REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
FORK="$(GIT rev-parse HEAD)"
LAND=feat/v6-realtime-live
GIT branch "$LAND" "$FORK"
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
SEAT='byz-planner-nano-det#0'; CARD="$REPO/design/planner/indices/진행/det.md"
NW="$REPO/.worktrees/det"; BR="nano/det"
GIT worktree add -q "$NW" -b "$BR" "$FORK"
echo work > "$NW/work.txt"; git -C "$NW" add work.txt; git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m work
SHA="$(git -C "$NW" rev-parse HEAD)"
echo ".worktree-info.json" >> "$REPO/.git/info/exclude"
GIT worktree add -q "$T/landwt" "$LAND"
git -C "$T/landwt" merge --squash -q "$BR" >/dev/null 2>&1; git -C "$T/landwt" -c user.email=t@t -c user.name=t commit -q -m "squash land"
echo m > "$REPO/m.txt"; GIT add m.txt; GIT commit -q -m "main moves"; MAINH="$(GIT rev-parse HEAD)"
# detached 사본(ft-scratch-repo.sh 와 같은 꼴 — 등록형 worktree --detach) · 사본 커밋 = FORK, 메인 체크아웃 HEAD = MAINH
git -C "$REPO" worktree add -q --detach "$T/scratch" "$FORK"

# ── ⓐ spawn: BASE_BRANCH~r1120 블록 · PLAN 줄 · info printf 줄을 추출해 실행
spawn_blk() {  # spawn_blk <spawn 파일> <WT> → 출력: INFO_BASE · BASE_BRANCH · PLAN 줄 · info 파일
  local sp="$1" blk planl infol
  blk="$(awk '/^BASE_BRANCH="\$\{BASE_REF:-/{p=1} p{print} /^# r1120:/{q=1} p&&q&&/^fi$/{exit}' "$sp")"
  planl="$(grep -m1 '^echo "PLAN seat=' "$sp")"
  infol="$(grep -m1 -F '"purpose":"nano · %s"}' "$sp")"
  rm -rf "$T/outwt"; mkdir -p "$T/outwt"
  ( WT="$2"; ROOT="$REPO"; BASE_REF=""; WTDIR="$T/outwt"; BRANCH=nano/x; NAME=s#0; AGENT=claude; MODEL=""; IDX_REL=design/x.md; _VIA=""; TIER=""; FAST=""; _PLANX=""
    eval "$blk"; echo "INFO_BASE=$INFO_BASE"; echo "BASE_BRANCH=$BASE_BRANCH"; eval "$planl"; eval "$infol"; cat "$WTDIR/.worktree-info.json" ) 2>&1
}
r1_check() {  # r1_check <spawn 파일> → 실패 수
  local out n=0
  out="$(spawn_blk "$1" "$T/scratch")"
  case "$out" in *"INFO_BASE=$FORK"*) ;; *) n=$((n+1)); echo "  R1 INFO_BASE ≠ $FORK ← ${out:0:300}";; esac
  case "$out" in *"BASE_BRANCH=$FORK"*) ;; *) n=$((n+1)); echo "  R1 worktree add 기준 ≠ 사본 커밋(메인 HEAD ${MAINH:0:9} 로 갈 수 있음)";; esac
  case "$out" in *"base=$FORK(detached)"*) ;; *) n=$((n+1)); echo "  R1 PLAN base=<40hex>(detached) 없음";; esac
  case "$out" in *"\"base\":\"$FORK\",\"base_sha\":\"${FORK:0:7}"*) ;; *) n=$((n+1)); echo "  R1 info base·base_sha ≠ 사본 커밋";; esac
  case "$out" in *'"base":"HEAD"'*) n=$((n+1)); echo "  R1 info base 글자 «HEAD»";; esac
  return "$n"
}
echo "== R1 detached 사본 spawn → info base = 그 커밋 40hex · PLAN base=<40hex>(detached)"
r1o="$(r1_check "$SRC/ft-nano-spawn.sh")" && ok "R1 info·PLAN·worktree add 기준 = $FORK" || bad "R1$(printf '\n%s' "$r1o")"
echo "== R2 가지 위 체크아웃 spawn → info base = 가지 이름(지금과 같음)"
out="$(spawn_blk "$SRC/ft-nano-spawn.sh" "$NW")"
has "$out" "\"base\":\"$BR\"" "R2 info base = $BR"
has "$out" "base=$BR index=" "R2 PLAN base=$BR"
hasnt "$out" "(detached)" "R2 detached 표기 없음"
echo "== 변이 1: detached 분기 끔 → R1 FAIL 이어야 한다"
sed 's/\[ "\$BASE_BRANCH" = HEAD \]/false/' "$SRC/ft-nano-spawn.sh" > "$T/mut-spawn.sh"
cmp -s "$T/mut-spawn.sh" "$SRC/ft-nano-spawn.sh" && bad "변이 1 적용 0(패턴 없음)" || {
  r1_check "$T/mut-spawn.sh" >/dev/null && bad "변이 1 이 R1 을 통과 — 시험이 분기를 못 본다" || ok "변이 1 → R1 FAIL(잡힘)"; }

# ── close: test_nano_close_sha_base.sh 와 같은 가짜 tmux·스텁
mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cp "$SRC/ft-nano-cherry-gate.sh" "$T/bin/ft-nano-cherry-gate.real.sh"
printf '#!/usr/bin/env bash\necho "$1 $2" > "%s/cherry.args"\nexec bash "%s/bin/ft-nano-cherry-gate.real.sh" "$@"\n' "$T" "$T" > "$T/bin/ft-nano-cherry-gate.sh"
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
chmod +x "$T/bin/"* "$T/fake/"*
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setinfo() {  # setinfo <base> [base_sha | -(칸 없음)]
  if [ "${2:-}" = - ]; then printf '{"branch":"%s","base":"%s","purpose":"t"}\n' "$BR" "$1" > "$NW/.worktree-info.json"
  else printf '{"branch":"%s","base":"%s","base_sha":"%s","purpose":"t"}\n' "$BR" "$1" "${2:-${FORK:0:10}}" > "$NW/.worktree-info.json"; fi
}
setup() {
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/det.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean" "$T/cherry.args"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { local cl="$1"; shift; run "$@" FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$cl" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR"; }
noside() {  # noside <이름> — REJECT 뒤 부작용 0
  [ -z "$(cat "$T/tlog")" ] && ok "  └ $1 kill·태그 해제 0" || bad "$1 REJECT 인데 tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ $1 명부 그대로" || bad "$1 REJECT 인데 명부 삭제"
}
r3_check() {  # r3_check <close 파일> → 0 = R3 통과
  setinfo HEAD; setup; local out rc; out="$(close "$1")"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  R3 rc=$rc ← ${out:0:600}"; return 1; }
  case "$out" in *"INFO base «HEAD» → base_sha ${FORK:0:10}"*) ;; *) echo "  R3 INFO «HEAD» 줄 없음"; return 1;; esac
  case "$out" in *"INFO base sha ${FORK:0:9} → 랜딩 브랜치 $LAND"*) ;; *) echo "  R3 조상 판정 기준 ≠ base_sha"; return 1;; esac
  [ "$(cat "$T/cherry.args" 2>/dev/null)" = "$LAND $BR" ] || { echo "  R3 게이트 인자: $(cat "$T/cherry.args" 2>/dev/null)"; return 1; }
  return 0
}

echo "== R3 close: base «HEAD» + base_sha(닫는 리포 HEAD ${MAINH:0:9} 와 다름) → base_sha 로 판정 · 닫힘"
r3o="$(r3_check "$T/bin/ft-nano-close.sh")" && ok "R3 INFO «HEAD» → base_sha · 기준 = ${FORK:0:9} · CLOSED" || bad "R3$(printf '\n%s' "$r3o")"
echo "== 변이 2: «HEAD» 교체 끔 → R3 FAIL 이어야 한다(기준이 닫는 리포 HEAD)"
sed 's/^if \[ "\$_INFO_FEAT" = HEAD \]; then$/if false; then/' "$T/bin/ft-nano-close.sh" > "$T/bin/mut-close.sh"
cmp -s "$T/bin/mut-close.sh" "$T/bin/ft-nano-close.sh" && bad "변이 2 적용 0(패턴 없음)" || {
  r3_check "$T/bin/mut-close.sh" >/dev/null && bad "변이 2 가 R3 을 통과 — 시험이 교체를 못 본다" || ok "변이 2 → R3 FAIL(잡힘)"; }

echo "== R4 close: base 가지 이름 → 지금 동작(INFO «HEAD»·sha 줄 없음 · 그 가지가 기준)"
setinfo "$LAND"; setup; out="$(close "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "R4 CLOSED" || bad "R4 rc=$rc ← ${out:0:600}"
hasnt "$out" "INFO base «HEAD»" "  └ R4 «HEAD» 줄 없음"; hasnt "$out" "INFO base sha" "  └ R4 sha 줄 없음"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "$LAND $BR" ] && ok "  └ R4 게이트 기준 = $LAND" || bad "R4 게이트 인자: $(cat "$T/cherry.args" 2>/dev/null)"

echo "== R5 close: base 40hex(R42) → 지금 동작(sha 줄 · «HEAD» 줄 없음)"
setinfo "$FORK"; setup; out="$(close "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "INFO base sha ${FORK:0:9} → 랜딩 브랜치 $LAND" "R5 CLOSED · R42 줄" || bad "R5 rc=$rc ← ${out:0:600}"
hasnt "$out" "INFO base «HEAD»" "  └ R5 «HEAD» 줄 없음"

echo "== R6 close: base «HEAD» + base_sha 없음 → 판정 불가 REJECT · 닫기 0"
setinfo HEAD -; setup; out="$(close "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "base_sha(없음)를 $REPO 에서 못 푼다 — 판정 불가" "R6 REJECT 판정 불가" || bad "R6 rc=$rc ← ${out:0:600}"
hasnt "$out" "CLOSED $SEAT" "  └ R6 CLOSED 없음"; noside R6

echo "== R7 close: base «HEAD» + base_sha 가 닫는 리포에 없음 → 판정 불가 REJECT · 닫기 0"
setinfo HEAD deadbeef01; setup; out="$(close "$T/bin/ft-nano-close.sh")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "base_sha(deadbeef01)를 $REPO 에서 못 푼다 — 판정 불가" "R7 REJECT 판정 불가" || bad "R7 rc=$rc ← ${out:0:600}"
hasnt "$out" "CLOSED $SEAT" "  └ R7 CLOSED 없음"; noside R7

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
