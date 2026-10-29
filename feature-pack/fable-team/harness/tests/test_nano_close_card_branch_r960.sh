#!/usr/bin/env bash
# test_nano_close_card_branch_r960.sh — r960 ⓐⓑ: ft-nano-close.sh ⑥ 카드 찾기가 «좌석 가지»까지 본다(카드가 아직 origin/main 에 없을 때)
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞) 만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 카드가 나노 가지에만(origin/main·팀 루트에 없음) → 지금 판은 «⑥카드 못 찾음» REJECT · 고친 판은 그 가지에서 읽어 --suspended 닫기 진행(카드 원문 경로 «<가지>:<경로>» 1줄)
#    ⓐ2 같은 상태에서 --superseded-by 닫기 → 카드를 가지에서 읽어 대조(CLOSED · 지금 판은 ⑥카드 못 찾음 REJECT)
#    ⓑ 카드가 가지에도 origin/main 에도 없음 → 지금처럼 ⑥카드 못 찾음 REJECT(조용한 통과 0 · 명부·카드·세션 불변)
#    ⓕ 변이: 가지 카드 찾기 끔(ⓐ FAIL) ⓖ 키트 짝 cmp0 · bash -n · 600/300·외부 호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓖ 키트 2곳 같은 바이트 + bash -n"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp ft-nano-close.sh (bin == kit)" || bad "cmp ft-nano-close.sh 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$T/bin/"   # r842 픽스처: 실 설치 꼴 — 단계 판정 lib + 캡 git
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
chmod +x "$T/bin/"* "$T/fake/"*

ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
REPO="$T/repo"; mkdir -p "$REPO"
gitc() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" init -q -b main && gitc commit -q --allow-empty -m init
git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/.fable-team" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
gitc push -q origin main   # origin/main = 카드 없는 판

SEAT='byz-planner-nano-bc#0'; BR='nano/bc'; NW="$REPO/.worktrees/v65-bc"
CARD_REL='design/planner/indices/진행/bc.md'; CARD="$NW/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/unlanded.py"
git -C "$NW" add scripts/unlanded.py && git -C "$NW" commit -q -m "work (미랜딩 코드)"
SHA0="$(git -C "$NW" rev-parse HEAD)"
mkdir -p "$(dirname "$CARD")"
printf '# 인덱스: bc\n## 상태\n- 2026-10-26 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n\n## 정본\n- 뒤 절\n' "$SHA0" > "$CARD"
git -C "$NW" add -A && git -C "$NW" commit -q -m "card: 가지에만 카드(증거 줄)"
SHA1="$(git -C "$NW" rev-parse HEAD)"
printf '# 인덱스: bc\n## 상태\n- 2026-10-26 진행\n대체됨: design/planner/indices/대기/other.md · 사유: r960 시험\n' > "$CARD"
git -C "$NW" add -A && git -C "$NW" commit -q -m "card: 대체됨 줄"
SHA2="$(git -C "$NW" rev-parse HEAD)"
mkdir -p "$REPO/design/planner/indices/대기"; printf '# 인덱스: other\n## 상태\n- 대기\n' > "$REPO/design/planner/indices/대기/other.md"   # 대체 카드(판정 근거 원문)
[ -f "$REPO/$CARD_REL" ] && bad "준비: 카드가 팀 루트에 있으면 안 됨" || ok "준비: 카드는 나노 가지에만($BR) · origin/main·팀 루트엔 없음"

LEDGER="$T/ledger.md"; CHERRY_LOG="$T/cherry-override.log"
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup [기준 sha] — 명부·pane·HEAD 를 «세션 없음 · 미커밋 0» 으로 리셋(카드 = 가지 커밋 그대로 · 기본 = 증거 줄 판)
  git -C "$NW" reset -q --hard "${1:-$SHA1}"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","agent":"claude","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -f "$CHERRY_LOG"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$CHERRY_LOG" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_AUTOCLEAN=0 bash "$T/bin/${CLOSE_BIN:-ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }

echo "== ⓐ 카드가 나노 가지에만 → --suspended 로 닫기 진행 · 카드 원문 경로 «<가지>:<경로>» 1줄"
setup; out="$(close --suspended "r960 가지 카드 시험")"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0 (지금 판은 ⑥카드 못 찾음 REJECT)" || bad "ⓐ rc=$rc ← ${out:0:500}"
has "$out" "CLOSED-ABSENT $SEAT suspended=1" "  └ CLOSED-ABSENT <좌석> suspended=1 (세션 없음)"
has "$out" "$BR:$CARD_REL" "  └ 카드 원문 경로 = «<가지>:<경로>» 1줄"
has "$out" "SUSPENDED-OK" "  └ ⑥ 중단 검사 통과"
has "$(cat "$CARD")" "중단:" "  └ 카드 «## 상태» 에 중단 줄(가지 체크아웃 사본 · 읽기·쓰기)"

echo "== ⓐ2 --superseded-by — ⑥ 이 가지 카드를 읽어 대체됨 줄을 대조 → CLOSED"
setup "$SHA2"; out="$(close --superseded-by design/planner/indices/대기/other.md)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ2 rc=0" || bad "ⓐ2 rc=$rc ← ${out:0:600}"
has "$out" "CLOSED-ABSENT $SEAT superseded-by=" "  └ CLOSED-ABSENT <좌석> superseded-by=<카드>(세션 없음)"
hasnt "$out" "카드 못 찾음" "  └ «카드 못 찾음» 0"

echo "== ⓑ 카드가 가지에도 origin/main 에도 없음 → ⑥카드 못 찾음 REJECT · 닫힘 0"
setup; git -C "$NW" rm -q "$CARD_REL"; git -C "$NW" commit -q -m "card 없음"
out="$(close --suspended "r960 카드 없음 시험")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓑ REJECT rc=1" || bad "ⓑ rc=$rc ← ${out:0:400}"
has "$out" "카드 못 찾음" "  └ 사유 = 카드 못 찾음(가지에도 없음)"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "  └ tmux 변경"
jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "  └ 명부 삭제"
[ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "  └ 원장 행 생김"

echo "== ⓕ 변이 — 가지 카드 찾기를 끄면 ⓐ 가 무너지는가"
mutate() {  # mutate <표지> <바꿀 글> — 표지 줄을 바꾼 사본으로 그 섹션을 돌려 FAIL 이 나는지
  local mark="$1" repl="$2"
  python3 - "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close.mut.sh" "$mark" "$repl" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().splitlines()
out, hit = [], 0
for ln in lines:
    if mark in ln: out.append(repl); hit += 1
    else: out.append(ln)
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(hit)
PY
}
n="$(mutate "# r960-mut:branchcard" ':')"
[ "$n" -ge 1 ] && ok "변이 표지 r960-mut:branchcard 1줄" || bad "변이 표지 r960-mut:branchcard 못 찾음"
CLOSE_BIN=ft-nano-close.mut.sh; setup; out="$(close --suspended "변이")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "카드 못 찾음" "ⓕ 가지 카드 찾기 끔 → ⓐ FAIL(REJECT 카드 못 찾음)" || bad "ⓕ rc=$rc ← ${out:0:400}"
CLOSE_BIN=ft-nano-close.sh

echo "== ⓖ 600/300 s · 외부 호출 · GIT_* env 0 (r960 새 줄)"
NEWL="$(grep 'r960\|_cb_\|_CB_' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
