#!/usr/bin/env bash
# test_wt_clean_plan_self_check.sh — R173: wt-clean 계획 파일이 «실행 맨 앞에서» 스스로 plan-ver 를 라이브 생성기와 대조해 다르면 멈춘다
# 임시 git 리포 + 가짜 tmux/baton(PATH 앞) + 스크립트 사본만 쓴다 — 실제 리포·seats·tmux·.fable-team/state/wt-clean 은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 일치 계획 = 기존 결과 그대로 ⓑ 생성기 1바이트 수정·삭제·hash 실패 = STALE 1줄 exit 3 + 손 0 ⓓ sweep 경로 STALE 불변 ⓔ 다른 cwd·심링크 실행도 같은 결과 ⓕ 키트 2곳 cmp 0 · 변이 2
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }

echo "== ⓕ 키트 2곳 같은 바이트 + bash -n"
cmp -s "$HERE/../../scripts/fable-team-bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp ft-nano-close.sh (fable-team-bin == harness-install)" || bad "cmp ft-nano-close.sh 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/failgit" "$T/lnk"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
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
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/failgit/git"   # hash-object 실패 재현(PATH 앞)
mkdir -p "$T/exitgit"   # hash-object 는 맞는 sha 를 찍고 exit 42, 그 밖은 진짜 git (H1 — 종료 코드 무시 검출)
REALGIT="$(command -v git)"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = hash-object ]; then "%s" "$@"; exit 42; fi\nexec "%s" "$@"\n' "$REALGIT" "$REALGIT" > "$T/exitgit/git"
chmod +x "$T/bin/"* "$T/fake/"* "$T/failgit/"* "$T/exitgit/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-slf#0'; CARD="$REPO/design/planner/indices/진행/slf.md"
NW="$REPO/.worktrees/cfo-slf"; BR="fix/slf-verdict"
GIT worktree add -q "$NW" -b "$BR"
git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"
printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"

BIN="$T/bin"
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
gen() {  # gen — 워크트리·명부·카드를 정상으로 되돌리고 close 로 계획(.sh.hil) 생성 → PLAN
  [ -d "$NW" ] || { GIT worktree prune; GIT worktree add -q "$NW" "$BR"; }
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/slf.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
  out="$(run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
    FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$BIN/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR")"; grc=$?
  PLAN="$T/wtclean/$SEAT.sh.hil"
  [ "$grc" -eq 0 ] && [ -f "$PLAN" ] || { bad "계획 생성 실패 rc=$grc ← ${out:0:300}"; return 1; }
  : > "$T/tlog"   # 계획 실행 전 기준선 — 원장 행은 남긴다(계획의 wt= 표식이 그 행을 고친다)
}
snap() { printf '%s\n--\n%s\n--\n%s\n--\n%s\n--\n%s\n--\n%s' "$(cat "$T/ledger.md")" "$(cat "$T/tlog")" "$(GIT worktree list)" "$(GIT rev-parse "$BR")" "$(git -C "$NW" status --porcelain 2>&1)" "$(ls "$T/wtclean" 2>&1)"; }
runplan() { ( cd "${PLAN_CWD:-$REPO}" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="${PLAN_PATH:-$T/fake:$PATH}" BATON_BIN="$T/fake/baton" /bin/bash "${PLAN_RUN:-$PLAN}" 2>&1 ); }

# stale_case <이름> — 계획 생성 → 생성기 변경(GEN_HOW) → 실행. STALE 1줄·exit 3·손 0 이면 0 반환(변이에서는 1 이 나와야 한다).
stale_case() {
  local name="$1" how="$2" before after o rc lines
  gen || return 2
  case "$how" in
    byte) printf '\n# 1바이트 변경\n' >> "$BIN/ft-nano-close.sh";;
    delete) rm -f "$BIN/ft-nano-close.sh";;
    hashfail) PLAN_PATH="$T/failgit:$T/fake:$PATH";;
    hashexit42) PLAN_PATH="$T/exitgit:$T/fake:$PATH";;
  esac
  before="$(snap)"; o="$(runplan)"; rc=$?; after="$(snap)"; unset PLAN_PATH
  lines="$(printf '%s\n' "$o" | grep -c .)"
  [ "$rc" -eq 3 ] && case "$o" in "STALE $SEAT — 옛 생성기 계획 실행 거부("*) [ "$lines" -eq 1 ];; *) false;; esac && [ "$before" = "$after" ] && [ -d "$NW" ] && return 0
  echo "  └ $name: rc=$rc lines=$lines ← ${o:0:200}"; return 1
}
restore_gen() { cp "$SRC/ft-nano-close.sh" "$BIN/ft-nano-close.sh"; chmod +x "$BIN/ft-nano-close.sh"; }

echo "== ⓐ 일치 계획 = 기존 결과 그대로"
gen && { has "$(cat "$PLAN")" "GEN=$BIN/ft-nano-close.sh" "  └ 계획에 생성기 절대경로가 구워짐(ⓔ)"
  has "$(sed -n '2,6p' "$PLAN" | grep -c '^# plan-ver: ' | tr -d ' ')" "1" "  └ plan-ver 표식 1줄 그대로"
  planout="$(runplan)"; prc=$?
  [ "$prc" -eq 0 ] && has "$(printf '%s' "$planout" | tail -1)" "cleaned" "ⓐ 일치 계획 실행 → cleaned(rc=0)" || bad "ⓐ rc=$prc ← ${planout:0:300}"
  case "$planout" in *STALE*) bad "ⓐ 일치인데 STALE";; *) ok "  └ STALE 없음";; esac
  [ ! -d "$NW" ] && ok "  └ 워크트리 정리됨" || bad "워크트리 남음"
  GIT rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "브랜치 삭제됨"
  has "$(cat "$T/ledger.md")" "wt=cleaned" "  └ 원장 표식 wt=cleaned"; }

echo "== ⓑ 생성기가 달라지면 STALE 1줄 · exit 3 · 파일/워크트리/원장/브랜치 손 0"
stale_case "생성기 1바이트 수정" byte && ok "ⓑ 생성기 1바이트 수정 → STALE 1줄 exit 3 · 손 0" || bad "ⓑ 생성기 1바이트 수정"
restore_gen
stale_case "생성기 삭제" delete && ok "ⓑ 생성기 파일 없음 → 같은 결과" || bad "ⓑ 생성기 삭제"
restore_gen
stale_case "git hash-object 실패" hashfail && ok "ⓑ git hash-object 실패 → 같은 결과(통과로 간주 0)" || bad "ⓑ hash 실패"

stale_case "hash-object 맞는 sha + exit 42" hashexit42 && ok "ⓑ hash-object 가 맞는 sha 를 찍고 exit 42 → STALE 1줄 exit 3 · 동작 0(H1)" || bad "ⓑ hash exit 42"

echo "== ⓔ 다른 cwd · 심링크 /tmp/h<N> 형태로 실행해도 같은 결과"
gen && { ln -sf "$PLAN" "$T/lnk/h1"; PLAN_CWD=/ PLAN_RUN="$T/lnk/h1"; planout="$(runplan)"; prc=$?
  [ "$prc" -eq 0 ] && has "$(printf '%s' "$planout" | tail -1)" "cleaned" "ⓔ 심링크·cwd=/ 일치 계획 → cleaned" || bad "ⓔ 일치 rc=$prc ← ${planout:0:300}"
  unset PLAN_CWD PLAN_RUN; }
gen && { ln -sf "$PLAN" "$T/lnk/h1"; printf '\n# x\n' >> "$BIN/ft-nano-close.sh"; before="$(snap)"; PLAN_CWD=/ PLAN_RUN="$T/lnk/h1"; o="$(runplan)"; rc=$?; unset PLAN_CWD PLAN_RUN
  [ "$rc" -eq 3 ] && has "$o" "STALE $SEAT" "ⓔ 심링크·cwd=/ 생성기 변경 → STALE exit 3" || bad "ⓔ 변경 rc=$rc ← ${o:0:200}"
  [ "$before" = "$(snap)" ] && ok "  └ 손 0" || bad "ⓔ 손 있음"; }
restore_gen

echo "== ⓓ sweep 경로 — 기존 plan_ver_check 가 먼저 막는다(.stale 이동 · STALE 문구 불변 · 계획 미실행)"
gen && { mkdir -p "$T/sw"; cp "$PLAN" "$T/sw/$SEAT.sh"; printf '\n# y\n' >> "$BIN/ft-nano-close.sh"
  swo="$(cd "$REPO" && FT_WT_CLEAN_DIR="$T/sw" bash "$BIN/ft-wt-sweep.sh" 2>&1)"
  has "$swo" "STALE $SEAT — 옛 생성기 계획 실행 거부(plan-ver=" "ⓓ sweep STALE 문구 불변"
  [ -f "$T/sw/$SEAT.sh.stale" ] && [ ! -e "$T/sw/$SEAT.sh" ] && ok "  └ .stale 로 이동" || bad "ⓓ .stale 이동 안 됨"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로(계획 미실행)" || bad "ⓓ 워크트리 사라짐"; }
restore_gen

echo "== 변이 2 — 자기검사를 망가뜨리면 위 ⓑ 시험이 실패해야 한다"
mutate() {  # mutate <이름> <perl -pi 식> <how> — 변이 생성기로 만든 계획이 STALE 로 «안» 멈추면(= 시험이 실패를 검출) 통과
  local name="$1" expr="$2" how="$3" saved="$BIN"
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin";
  perl -0pi -e "$expr" "$T/mutbin/ft-nano-close.sh"
  cmp -s "$T/mutbin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && { bad "변이 $name — 변이가 적용되지 않음"; return; }
  BIN="$T/mutbin"; stale_case "$name" "$how" >/dev/null && bad "변이 $name — 시험이 못 잡음(STALE 로 멈췄다)" || ok "변이 $name — ⓑ 시험이 실패를 검출"
  BIN="$saved"
}
mutate "자기검사 블록 제거(1바이트 수정 경우)" 's/\n_lv="\$\(git hash-object[^\n]*\n\[ -n "\$_lv" \][^\n]*\n/\n/' byte
mutate "비교를 «비었으면 통과» 로(생성기 삭제 경우)" 's/\[ -n "\$_lv" \] && \[ "\$_lv" = "\$PLANVER" \]/[ -z "\$_lv" ] || [ "\$_lv" = "\$PLANVER" ]/' delete
mutate "종료 코드 무시(|| _lv=\"\" 제거)" 's/ \|\| _lv=""//' hashexit42

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
