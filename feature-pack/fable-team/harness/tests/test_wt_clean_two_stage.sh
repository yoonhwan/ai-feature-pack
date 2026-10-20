#!/usr/bin/env bash
# test_wt_clean_two_stage.sh — 카드 r166: 닫힌 나노 정리 2단(이름 바꾸고 상한 밖에서 정리) · 껍데기 인식 · 계획 버전 표식 · 껍데기 경보.
#   ⓐ상한 초과가 정리 단계에서 나도 원래 경로 껍데기 0(이름 바뀐 .deleting-<ts> 만) ⓑ.deleting-* 는 다음 sweep 이 이어서 정리(+연속 실패 HIL)
#   ⓒ작업 트리에서만 지워진 줄만 남은 껍데기 = 가드 5번 건너뛰고 정리만 · 진짜 미커밋 = 기존 그대로 HIL ⓓ계획 머리 plan-ver ≠ 라이브 생성기 = 실행 거부
#   ⓔ껍데기 경보는 바뀐 때만 ⓕ브랜치 삭제 0 · 변이 2: move 단계 제거 → ⓐ 실패 · plan-ver 대조 제거 → ⓓ 실패.
# 임시 git 리포 + 임시 워크트리(파일 천 개대 픽스처) + 가짜 tmux·baton(지연·실패 주입) 만 쓴다 — 실 리포·워크트리·baton·tmux·mbox 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 옛 도구로 돌려 시험이 결함을 잡는지 볼 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && bash -n "$SRC/ft-wt-sweep.sh" && ok "bash -n 2종" || bad "bash -n"

mkdir -p "$T/bin" "$T/fake" "$T/hil"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-hil.sh" "$T/bin/"
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
  ls) echo "no server running on /tmp/fake"; exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
printf '.worktree-info.json\n' > "$REPO/.gitignore"
git -C "$REPO" add .gitignore && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies" "$T/wtclean"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-del#0'; CARD="$REPO/design/planner/indices/진행/del.md"
NW="$REPO/.worktrees/v65-del"; BR="nano/del"
PLAN="$T/wtclean/$SEAT.sh"; PTR="$PLAN.deleting"
baton_ok()   { printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"; }
baton_slow() { printf '#!/usr/bin/env bash\nsleep 8\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"; }
baton_fail() { printf '#!/usr/bin/env bash\nexit 1\n' > "$T/fake/baton"; chmod +x "$T/fake/baton"; }
baton_ok

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
# sweep — 리포 밖 cwd · 격리 계획 디렉터리. 추가 env 는 인자로.
swp() { ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" BATON_BIN="$T/fake/baton" FT_WT_CLEAN_DIR="${DIRX:-$T/wtclean}" FT_WT_PLAN_TIMEOUT="${TMOX:-20}" FT_WT_RESUME_GRACE="${GRACEX:-0}" \
  HIL_DIR="$T/hil" HIL_CLIP=0 FT_SHEET_ROOT="$FT_SHEET_ROOT" "$@" bash "${SWEEPX:-$T/bin/ft-wt-sweep.sh}" 2>&1 ); }
gone() { local i; for i in $(seq 1 80); do [ ! -e "$1" ] && return 0; sleep 0.5; done; return 1; }
deleting_dirs() { ls -d "$NW".deleting-* 2>/dev/null; }

# fresh — 파일 천 개대 워크트리(최상위 dir 15 + file 4) 커밋 → close(FT_WT_AUTOCLEAN=0)로 계획 생성. GEN=생성기 경로(변이용).
fresh() {
  local d f GENX="${GEN:-$T/bin/ft-nano-close.sh}"
  rm -rf "$NW" "$NW".deleting-* "$T"/wtclean/* 2>/dev/null; GIT worktree prune; GIT branch -D "$BR" >/dev/null 2>&1
  GIT worktree add -q "$NW" -b "$BR"
  for d in $(seq 0 14); do mkdir -p "$NW/d$d"; for f in $(seq 1 80); do echo "$d-$f" > "$NW/d$d/f$f.txt"; done; done
  for f in f1 f2 f3 f4; do echo "$f" > "$NW/$f"; done
  printf '{"branch":"%s"}\n' "$BR" > "$NW/.worktree-info.json"
  git -C "$NW" add -A && git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "work"
  SHA="$(git -C "$NW" rev-parse HEAD)"
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/del.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
  gen_out="$(run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" FT_WT_AUTOCLEAN=0 \
    FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$GENX" "$SEAT" --result "$T/result.md" --recv 1)"
  [ -f "$PLAN" ] || { bad "계획 생성 실패 ← ${gen_out:0:400}"; return 1; }
}
tip_unmoved() { [ "$(git -C "$REPO" rev-parse "refs/heads/$BR" 2>/dev/null)" = "$SHA" ]; }

# ⓐ 축 검사 함수 — 변이 시험이 같은 검사를 재사용한다. 0 = 충족.
#   baton 이 8초 걸리고 계획 상한이 4초: 옛 방식이면 baton 도중 TERM → 원래 경로 껍데기. 새 방식은 계획이 상한 안에 끝나고 원래 경로는 비어 있다.
axis_a() {
  baton_slow; a_out="$(TMOX=4 swp FT_WT_SWEEP_MAX=1)"
  case "$a_out" in *"OK   $SEAT wt=cleaned"*) ;; *) a_why="계획이 cleaned 로 안 끝남 ← ${a_out:0:300}"; return 1;; esac
  [ ! -e "$NW" ] || { a_why="원래 경로 $NW 가 남음(껍데기)"; return 1; }
  [ -n "$(deleting_dirs)" ] || [ -f "$PTR" ] || { a_why=".deleting-<ts> 도 포인터도 없음"; return 1; }
  return 0
}

echo "== ⓐ 상한 초과(baton 8s > 계획 상한 4s)에도 원래 경로 껍데기 0 · 이름 바뀐 .deleting-<ts> 만"
fresh && {
  grep -qE '^# plan-ver: [0-9a-f]{40}$' "$PLAN" && ok "  └ 계획 머리 # plan-ver: <40hex>" || bad "계획 머리에 plan-ver 없음"
  if axis_a; then ok "ⓐ 원래 경로 비어 있음 · .deleting-<ts> 로 이름 바뀜 · 계획 cleaned"; else bad "ⓐ $a_why"; fi
  has "$(cat "$T/ledger.md")" "이름 바꿈 →" "  └ 원장 표식에 이름 바꿈 기록"
  tip_unmoved && ok "  └ 브랜치 tip 그대로" || bad "브랜치 tip 이 움직임"
  # ⓑ 분리 정리가 상한 밖에서 끝까지 돈다(sweep 이 끝난 뒤에도)
  if gone "$PTR" && [ -z "$(deleting_dirs)" ]; then ok "ⓑ 분리 정리가 상한 밖에서 끝남(.deleting-<ts> · 포인터 사라짐)"; else bad "ⓑ 분리 정리가 안 끝남: $(deleting_dirs) $(ls "$T"/wtclean)"; fi
  [ -z "$(GIT worktree list --porcelain | grep deleting)" ] && ok "  └ worktree 목록에 deleting 0(prune)" || bad "worktree 목록에 deleting 남음"
  tip_unmoved && ok "ⓕ 브랜치 tip 그대로(삭제 0)" || bad "ⓕ 브랜치 tip 이 움직임"
  GIT rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "ⓕ 브랜치 $BR 실재" || bad "ⓕ 브랜치가 사라짐"
}

echo "== ⓑ 이어정리 — 분리 정리가 실패/중단된 .deleting-<ts> 를 다음 sweep 이 이어서 지운다"
fresh && {
  baton_fail; b1="$(GRACEX=60 swp)"   # 방금 만든 포인터는 이어정리 대상 아님(유예 60s) — 계획이 건 분리 정리와 겹쳐 실패 횟수가 2 가 되는 것을 막는다
  has "$b1" "OK   $SEAT wt=cleaned" "ⓑ 계획 cleaned(이름 바꿈까지)"
  for i in $(seq 1 40); do [ -f "$PTR.fail" ] && break; sleep 0.25; done
  [ -n "$(deleting_dirs)" ] && ok "  └ baton 실패 → .deleting-<ts> 남김(삭제 보류)" || bad "baton 실패인데 .deleting 이 사라짐"
  [ "$(cat "$PTR.fail" 2>/dev/null)" = 1 ] && ok "  └ 실패 횟수 1 기록" || bad "실패 횟수 기록 이상: $(cat "$PTR.fail" 2>/dev/null)"
  # 반쯤 지워진 상태 시늉(상한 TERM 이 삭제 도중 걸린 모양): 큰 폴더 몇 개 + info 삭제
  D1="$(deleting_dirs | head -1)"; rm -rf "$D1"/d0 "$D1"/d1 "$D1"/d2 "$D1/.worktree-info.json"
  baton_ok; b2="$(swp)"
  has "$b2" "RESUME $SEAT" "ⓑ 다음 sweep 이 RESUME(이어정리)"
  if gone "$PTR" && [ -z "$(deleting_dirs)" ]; then ok "ⓑ 반쯤 지워진 .deleting-<ts> 를 이어서 끝까지 정리"; else bad "ⓑ 이어정리 안 끝남: $(deleting_dirs)"; fi
  [ -z "$(GIT worktree list --porcelain | grep deleting)" ] && ok "  └ worktree 목록에 deleting 0" || bad "worktree 목록에 deleting 남음"
  # 연속 실패 FT_WT_FINISH_MAX(3) → HIL, 포인터 .hil
  printf '%s\n%s\n' "$NW.deleting-1" "$REPO" > "$PTR"; echo 3 > "$PTR.fail"; mkdir -p "$NW.deleting-1"
  b3="$(swp)"
  has "$b3" "[HIL] seat=$SEAT 이름 바뀐 워크트리 정리 3회 연속 실패" "ⓑ 연속 실패 3 → [HIL] seat="
  [ -f "$PTR.hil" ] && [ ! -f "$PTR" ] && ok "  └ 포인터 .hil 로 이동(다음 sweep 재시도 0)" || bad "포인터 이동 이상"
  rm -rf "$NW.deleting-1"
  # 이름 안전장치 — .deleting-<ts> 가 아닌 경로는 지우지 않는다
  mkdir -p "$T/keep"; echo x > "$T/keep/x"; printf '%s\n%s\n' "$T/keep" "$REPO" > "$T/p.deleting"
  bash "$T/bin/ft-wt-sweep.sh" --finish "$T/p.deleting" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && [ -f "$T/keep/x" ] && ok "  └ 이름 안전장치: .deleting-<ts> 아닌 경로 삭제 거부(rc=1)" || bad "이름 안전장치 실패 rc=$rc"
}

echo "== ⓒ 껍데기 인식 — ' D' 만 남은(info 도 사라진) 워크트리는 가드 5번 건너뛰고 정리만 · 진짜 미커밋은 기존 그대로 HIL"
fresh && { rm -rf "$NW"/d0 "$NW"/d1 "$NW"/d2 "$NW/.worktree-info.json"
  has "$(git -C "$NW" status --porcelain | head -1)" " D " "  └ 전제: 작업 트리에서만 지워진 줄(' D')"
  c1="$(swp)"; has "$c1" "OK   $SEAT wt=cleaned" "ⓒ 껍데기(' D' 만 · info 없음) → cleaned"
  [ ! -e "$NW" ] && ok "  └ 원래 경로 비어 있음" || bad "껍데기가 원래 경로에 남음"
  gone "$PTR"; tip_unmoved && ok "  └ 브랜치 tip 그대로([wip]·삭제 커밋 0)" || bad "브랜치 tip 이 움직임"; }
fresh && { rm -rf "$NW"/d0 "$NW"/d1 "$NW/.worktree-info.json"; echo changed >> "$NW/f1"
  c2="$(swp)"; has "$c2" "[HIL] seat=$SEAT" "ⓒ ' D' + 수정(' M') + info 없음 → 기존 그대로 HIL"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }
fresh && { rm -rf "$NW"/d0 "$NW"/d1; echo changed >> "$NW/f1"
  c3="$(swp)"; has "$c3" "[HIL] seat=$SEAT 실작업물 미커밋 1파일" "ⓒ ' D' + 수정 1(info 있음) → 실작업물 미커밋 1파일 HIL"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }
fresh && { rm -rf "$NW"/d0 "$NW"/d1 "$NW/.worktree-info.json"; echo new > "$NW/untracked.txt"
  c4="$(swp)"; has "$c4" "[HIL] seat=$SEAT" "ⓒ ' D' + 새 파일('??') + info 없음 → HIL"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }

# ⓓ 축 검사 함수 — 생성기가 계획 생성 뒤 달라졌으면 옛 계획은 실행 거부(r535: 같은 좌석·WT 로 재생성 → 새 계획만 실행 · 옛 계획 .replanned). 0 = 충족.
axis_d() {
  printf '\n# drift\n' >> "$T/bin/ft-nano-close.sh"
  local lv; lv="$(git hash-object "$T/bin/ft-nano-close.sh")"
  printf 'echo "OLD BODY RAN"\n' >> "$PLAN"
  d_out="$(swp)"
  case "$d_out" in *"REPLAN $SEAT"*) ;; *) cp "$SRC/ft-nano-close.sh" "$T/bin/ft-nano-close.sh"; d_why="REPLAN 줄 없음 ← ${d_out:0:300}"; return 1;; esac
  cp "$SRC/ft-nano-close.sh" "$T/bin/ft-nano-close.sh"
  [ -f "$PLAN.replanned" ] && grep -q 'OLD BODY RAN' "$PLAN.replanned" || { d_why="옛 계획이 .replanned 로 안 옮겨짐"; return 1; }
  grep -q 'OLD BODY RAN' "$PLAN.log" 2>/dev/null && { d_why="옛 몸통이 실행됨"; return 1; }
  grep -qx "# plan-ver: $lv" "$PLAN.done" 2>/dev/null || { d_why="새 계획(plan-ver=라이브)이 실행되지 않음"; return 1; }
  return 0
}
echo "== ⓓ 계획 plan-ver ≠ 라이브 생성기 = 옛 계획 실행 거부 → 재생성(r535)"
fresh && {
  if axis_d; then ok "ⓓ 생성기가 달라진 뒤 sweep → REPLAN 1줄 · 옛 계획 .replanned · 새 계획만 실행"; else bad "ⓓ $d_why"; fi
  has "$d_out" "replanned 1" "  └ 요약 줄에 replanned 1"
  gone "$PTR"
}
fresh && { grep -v '^# plan-ver: ' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  e1="$(swp)"; has "$e1" "REPLAN $SEAT" "ⓓ plan-ver 표식 없는 옛 생성기 계획도 옛 판 → 재생성"; gone "$PTR"; }
fresh && { printf '{"branch":"feat/x"}\n' > "$NW/.worktree-info.json"; printf '\n# drift\n' >> "$T/bin/ft-nano-close.sh"
  e0="$(swp)"; cp "$SRC/ft-nano-close.sh" "$T/bin/ft-nano-close.sh"
  has "$e0" "STALE $SEAT" "ⓓ 재생성 불가(가지 nano/* 아님) → 지금처럼 STALE"; has "$e0" "stale 1" "  └ 요약 줄에 stale 1"
  [ -f "$PLAN.stale" ] && [ ! -f "$PLAN" ] && ok "  └ 계획 .stale" || bad "계획이 .stale 로 안 옮겨짐"; [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }
fresh && { e2="$(swp)"; has "$e2" "OK   $SEAT wt=cleaned" "ⓓ 생성기 그대로면 정상 실행"; gone "$PTR"; hasnt "$e2" "STALE" "  └ STALE 0"; }
mkdir -p "$T/stub"; printf 'echo cleaned\n' > "$T/stub/x#0.sh"
e3="$(DIRX="$T/stub" swp)"; has "$e3" "OK   x#0 wt=cleaned" "ⓓ 생성기 계획이 아닌 스텁 계획은 plan-ver 대상 아님(기존 시험 호환)"

echo "== ⓔ 껍데기 경보 — 바뀐 때만 1줄"
rm -rf "$NW" "$NW".deleting-* "$T"/wtclean/* 2>/dev/null; GIT worktree prune
mkdir -p "$T/scan"
mkshell() { GIT worktree add -q "$REPO/.worktrees/$1" -b "shell-$1"; local d; for d in 0 1 2 3 4 5; do mkdir -p "$REPO/.worktrees/$1/d$d"; echo x > "$REPO/.worktrees/$1/d$d/x"; done; git -C "$REPO/.worktrees/$1" add -A; git -C "$REPO/.worktrees/$1" -c user.email=t@t -c user.name=t commit -q -m w; }
mkshell sa; mkshell ok1
rm -rf "$REPO/.worktrees/sa"/d0 "$REPO/.worktrees/sa"/d1
scan() { DIRX="$T/scan" swp FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=0; }
s1="$(scan)"; has "$s1" "[HIL] seat=byz-harness-wt-shell 반쯤 지워진 워크트리 껍데기 1곳(전체 1곳): sa" "ⓔ 껍데기 1곳 → [HIL] 1줄(sa · 팀 미상 = harness · r444)"; hasnt "$s1" "ok1" "  └ 멀쩡한 워크트리(ok1)는 안 셈"
s2="$(scan)"; hasnt "$s2" "[HIL] 반쯤" "ⓔ 그대로면 두 번째 sweep 은 경보 0"
mkshell sb; rm -rf "$REPO/.worktrees/sb"/d2 "$REPO/.worktrees/sb"/d3
s3="$(scan)"; has "$s3" "껍데기 2곳(전체 2곳): sa sb" "ⓔ 목록이 바뀌면(2곳) 다시 1줄"
s4="$(scan)"; hasnt "$s4" "[HIL] 반쯤" "  └ 바뀐 뒤 그대로면 다시 0"
s5="$(DIRX="$T/scan" swp FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=3600)"; hasnt "$s5" "[HIL] 반쯤" "  └ 스캔 간격 안(3600s)에선 훑지도 않음"
[ -d "$REPO/.worktrees/sa" ] && [ -d "$REPO/.worktrees/sb" ] && ok "  └ 경보는 읽기만 — 껍데기 손 0" || bad "경보가 껍데기를 건드림"

echo "== ⓕ 브랜치 삭제 코드 0"
grep -nE 'branch +-[dD]|update-ref +-d' "$SRC/ft-wt-sweep.sh" >/dev/null && bad "sweep 에 브랜치 삭제 코드" || ok "ⓕ sweep 에 브랜치 삭제 코드 0"
sed -n '/^# ★r166 2단 정리★/,/^mark "\$res"/p' "$SRC/ft-nano-close.sh" | grep -qE 'branch +-[dD]|update-ref +-d' && bad "계획 2단 블록에 브랜치 삭제 코드" || ok "ⓕ 계획 2단 블록에 브랜치 삭제 코드 0"

# ⓖ 보관 tar 없는 삭제 0 (DA⑥ H1) — 가짜 baton 은 성공 때 tar·INDEX 행을 «실제로 만든다»(baton archive 와 같은 꼴: <루트>/.baton/archive/INDEX.jsonl · <id>.tar.gz)
baton_tar() { printf '#!/usr/bin/env bash\nA="%s/.baton/archive"; mkdir -p "$A"; echo hello > "$A/.seed"; id="arch_$$"; tar czf "$A/$id.tar.gz" -C "$A" .seed\nprintf '"'"'{"id":"%%s","worktree":"%%s"}\\n'"'"' "$id" "$2" >> "$A/INDEX.jsonl"\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"; }
waitfail() { local i; for i in $(seq 1 60); do [ "$(cat "$PTR.fail" 2>/dev/null)" = "$1" ] && [ ! -f "$PTR.pid" ] && return 0; sleep 0.25; done; return 1; }
# 계획이 이름을 바꾼 직후 baton 실패로 .deleting 이 남은 상태를 만든다 → marker(info) 와 큰 폴더 일부를 지운 «흔적 없는 반쯤 지운 껍데기»(보관 tar 없음)
mk_shell_no_tar() {
  rm -rf "$REPO/.baton"; baton_fail; GRACEX=60 swp >/dev/null; waitfail 1 || return 1
  G1="$(deleting_dirs | head -1)"; [ -n "$G1" ] || return 1
  rm -rf "$G1"/d0 "$G1"/d1 "$G1/.worktree-info.json"
}
# ①②축 검사 — marker 없음·tar 없음에서 보관이 안 되는 동안: 삭제 0 · 원래 경로 없음 · .deleting·포인터·파일 유지 · 다음 sweep 재시도(실패 횟수 증가). 0 = 충족.
axis_g() {
  mk_shell_no_tar || { g_why="준비 실패(.deleting 없음)"; return 1; }
  g_out="$(swp)"; waitfail 2 || { g_why="다음 sweep 이 재시도하지 않음(fail=$(cat "$PTR.fail" 2>/dev/null))"; return 1; }
  [ ! -e "$NW" ] || { g_why="원래 경로가 되살아남"; return 1; }
  [ -d "$G1" ] && [ -f "$G1/d5/f1.txt" ] && [ -f "$PTR" ] || { g_why="보관 tar 없이 지워짐(.deleting/파일/포인터 소실)"; return 1; }
  return 0
}
echo "== ⓖ 보관 tar 없는 삭제 0 — 잔여 삭제는 검증된 tar 가 있을 때만(marker 무관)"
fresh && {
  if axis_g; then ok "ⓖ①② marker 없음·tar 없음 + 보관 실패 → 삭제 0 · 원래 경로 없음 · .deleting·포인터·파일 유지 · 다음 sweep 재시도"; else bad "ⓖ①② $g_why"; fi
  has "$g_out" "RESUME $SEAT" "  └ 재시도 경로(RESUME) 작동"
  # ③ 검증된 tar 있음 → baton 없이 이어서 정리
  printf '%s\n' "{\"id\":\"pre\",\"worktree\":\"$G1\"}" >> "$REPO/.baton/archive/INDEX.jsonl" 2>/dev/null || { mkdir -p "$REPO/.baton/archive"; printf '%s\n' "{\"id\":\"pre\",\"worktree\":\"$G1\"}" >> "$REPO/.baton/archive/INDEX.jsonl"; }
  echo hi > "$T/seed"; tar czf "$REPO/.baton/archive/pre.tar.gz" -C "$T" seed
  g3="$(swp)"; has "$g3" "RESUME $SEAT" "ⓖ③ 검증된 tar 있음 → 이어정리(RESUME)"
  if gone "$PTR" && [ ! -e "$G1" ]; then ok "ⓖ③ 검증된 tar 가 있으면 baton 실패와 무관하게 잔여 정리"; else bad "ⓖ③ tar 있는데 정리 안 됨"; fi
  # 깨진 tar(0바이트)는 증거가 아니다
  fresh; rm -rf "$REPO/.baton"; baton_fail; GRACEX=60 swp >/dev/null; waitfail 1
  G1="$(deleting_dirs | head -1)"; mkdir -p "$REPO/.baton/archive"; : > "$REPO/.baton/archive/bad.tar.gz"; printf '%s\n' "{\"id\":\"bad\",\"worktree\":\"$G1\"}" > "$REPO/.baton/archive/INDEX.jsonl"
  swp >/dev/null; waitfail 2; [ -d "$G1" ] && ok "ⓖ 0바이트 tar 는 증거 아님 → 삭제 0" || bad "ⓖ 0바이트 tar 로 삭제됨"
  # ④ 가짜 baton 이 성공 때 tar 를 실제로 만든다 → 시험이 tar 실재 단언
  fresh; rm -rf "$REPO/.baton"; baton_tar; swp >/dev/null
  gone "$PTR"; [ -z "$(deleting_dirs)" ] && ok "ⓖ④ 보관 성공 뒤 정리 끝" || bad "ⓖ④ 정리 안 끝남"
  [ "$(ls "$REPO"/.baton/archive/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && ok "ⓖ④ tar 실재(.baton/archive/*.tar.gz)" || bad "ⓖ④ tar 가 없음"
  has "$(cat "$REPO/.baton/archive/INDEX.jsonl" 2>/dev/null)" ".deleting-" "ⓖ④ INDEX 행이 이름 바뀐 경로를 가리킴"
  baton_ok
}

echo "== 변이 시험 — 검사가 정말 결함을 잡는가"
# 변이 1: move 단계 제거 → ⓐ 실패해야 한다
sed '/worktree move "\$WT" "\$DEL"/d' "$SRC/ft-nano-close.sh" > "$T/mut-close.sh"; chmod +x "$T/mut-close.sh"; cp "$T/mut-close.sh" "$T/bin/ft-nano-close-mut.sh"
cmp -s "$T/mut-close.sh" "$SRC/ft-nano-close.sh" && bad "변이 1 이 생성기를 안 바꿈" || ok "변이 1 적용(move 줄 제거)"
GEN="$T/bin/ft-nano-close-mut.sh" fresh && { if axis_a; then bad "변이 1(move 제거) 인데 ⓐ 가 통과 — 검사가 못 잡음"; else ok "변이 1(move 제거) → ⓐ 실패 검출: $a_why"; fi; }
sleep 9; rm -rf "$NW" "$NW".deleting-*; GIT worktree prune
# 변이 2: plan-ver 대조 제거 → ⓓ 실패해야 한다
sed 's/^plan_ver_check() {$/plan_ver_check() { return 0;/' "$SRC/ft-wt-sweep.sh" > "$T/bin/ft-wt-sweep-mut.sh"
cmp -s "$T/bin/ft-wt-sweep-mut.sh" "$SRC/ft-wt-sweep.sh" && bad "변이 2 가 sweep 을 안 바꿈" || ok "변이 2 적용(plan-ver 대조 무력화)"
fresh && { SWEEPX="$T/bin/ft-wt-sweep-mut.sh"; if axis_d; then bad "변이 2(plan-ver 대조 제거) 인데 ⓓ 가 통과 — 검사가 못 잡음"; else ok "변이 2(plan-ver 대조 제거) → ⓓ 실패 검출: $d_why"; fi; unset SWEEPX; }

# 변이 3: tar 실재 검사 제거 → ⓖ①② 실패해야 한다(마커 없는 껍데기를 tar 없이 지워 버린다)
sed 's/^has_tar() {$/has_tar() { return 0;/' "$SRC/ft-wt-sweep.sh" > "$T/bin/ft-wt-sweep-mut3.sh"
cmp -s "$T/bin/ft-wt-sweep-mut3.sh" "$SRC/ft-wt-sweep.sh" && bad "변이 3 이 sweep 을 안 바꿈" || ok "변이 3 적용(tar 실재 검사 무력화)"
fresh && { SWEEPX="$T/bin/ft-wt-sweep-mut3.sh"; if axis_g; then bad "변이 3(tar 검사 제거) 인데 ⓖ 가 통과 — 검사가 못 잡음"; else ok "변이 3(tar 검사 제거) → ⓖ 실패 검출: $g_why"; fi; unset SWEEPX; }

echo "== 위생 — 공용 .git 설정 불변"
[ "$(git -C "$HERE/../.." config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare 이상"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
