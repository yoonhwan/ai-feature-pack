#!/usr/bin/env bash
# test_nano_close_pack_card_ledger_r1785.sh — 카드 r1785: 팩 나노 카드 판별 = ft-team-lib.sh ft_pack_card 한 출처
#   표지 ⓐ 첫 5줄 `<!-- ledger: …/GOAL-harness.md -->` · ⓑ 첫 `## ` 앞 머리 `- 정본 영향:` 줄의 «팩 원본»
#   ① planner 원장 + 정본 영향 «팩 원본» → close ⓐ 통과(CLOSED · 하네스 카드와 같은 꼴) · ② 같은 카드 spawn pack_wt_line → 1줄
#   ③ planner 원장 + 정본 영향 «제품 docs» / «하네스 제품 docs» → close ⓐ REJECT(새 문구) · spawn 0줄
#   ④ 하네스 원장 → 지금 그대로 CLOSED · ⑤ «팩 원본» 이 본문 `## 배경` 아래에만 → REJECT · spawn 0줄
#   A1 ft_pack_card rc(카드 4종 + 없는 카드) · bin·kit cmp0(ft-team-lib.sh · ft-nano-close.sh · ft-nano-spawn.sh)
# 바탕(fixture) = test_nano_close_pack_wt.sh 와 같은 꼴 — 임시 리포 2개(BYZ 꼴 R · 팩 꼴 P + bare 원격) + 가짜 tmux + bin 사본
#   실 리포·명부·워크트리·tmux 세션·외부 호출 0 · sleep 0 · 자기 재호출 0(real_state_guard 재실행만).
# 변이 확인: FT_R1785_BIN=<바꾼 bin 사본 폴더> 로 그 폴더의 세 파일을 시험한다(cmp 칸은 건너뜀).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team/bin"
SRC="${FT_R1785_BIN:-$TRACKED}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-landed-check.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$KIT/ft-nano-evidence-check.sh" "$KIT/ft-wt-sweep.sh" "$KIT/ft-hil.sh" "$KIT/ft_teamset.py" "$KIT/ft_team_lib.py" "$T/bin/"
cp "$KIT/ft-sheet-events.sh" "$KIT/ft_sheet_events.py" "$KIT/ft_sheet_confirm.py" "$KIT/ft_sheet_key.py" "$KIT/ft_board_env.py" "$KIT/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) cat "$FAKE_PANE_CWDS";;
      *) cat "$FAKE_PANES";;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin HEAD:main; git -C "$R" fetch -q origin
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
RW="$R/.worktrees/harness-k"
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
GC "$P" worktree add -q "$P/.worktrees/k" -b nano/k origin/main
PW="$P/.worktrees/k"; echo kit > "$PW/kit.sh"; GC "$PW" add kit.sh; GC "$PW" commit -q -m work
SHA="$(git -C "$PW" rev-parse HEAD)"

mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies" "$T/cards"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"
HL='<!-- ledger: design/harness/GOAL-harness.md -->'
PL='<!-- ledger: design/teams/planner/PLAN-oppa-ledger.md (오빠 지시) -->'

# 카드 5종 — mk <파일> <원장 줄> <정본 영향 줄(빈 값 = 없음)> <본문 배경 줄(빈 값 = 없음)>
mk() { { printf '# 인덱스: k\n%s\n' "$2"; [ -z "$3" ] || printf '%s\n' "$3"
  printf -- '- 설치: 있음 — 팩 키트 1\n\n## 배경\n%s\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "${4:-한 단락}" "$SHA"; } > "$1"; }
mk "$T/cards/harness.md" "$HL" "" ""
mk "$T/cards/planner-pack.md" "$PL" '- 정본 영향: 하네스 1.x 라이브 bin `x.sh` + 팩 원본 · 제품 docs 0' ""
mk "$T/cards/planner-prod.md" "$PL" '- 정본 영향: 제품 docs' ""
mk "$T/cards/planner-hprod.md" "$PL" '- 정본 영향: 하네스 제품 docs' ""
mk "$T/cards/planner-body.md" "$PL" '- 정본 영향: 제품 docs' '- 정본 영향: 하네스 bin + 팩 원본'

run() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" bash -c 'while [ $# -gt 0 ]; do case "$1" in [A-Z_]*=*) export "$1"; shift;; *) break;; esac; done; exec "$@"' _ "$@" 2>&1 ); }   # env 뒤 첫 낱말 = 글자 명령(범위 분류기) · 인자 앞 VAR=값 은 안쪽에서 export
setup() {  # setup <카드 종류>
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$R/.fable-team/seats-harness.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$RW" > "$T/pane-cwds"; printf '%s' "$RW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  cp "$T/cards/$1.md" "$CARD"
}
close() { run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_PACK_ROOT="$P" \
  FT_SEATS_JSON="$R/.fable-team/seats-harness.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$PW" --branch nano/k; }
NEWMSG='팩 경로는 팩 카드(원장 GOAL-harness 또는 정본 영향 «팩 원본»)만'
OLDA="ⓐ--wt($PW)가 이 리포($R)에 등록된 .worktrees/ 아래 워크트리가 아니다"
closed() {  # closed <라벨> — ⓐ 통과 + 뒤 검사 = 하네스 카드와 같은 꼴(CLOSED · mode=pack-wt)
  local out rc; out="$(close)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "$1 → CLOSED(rc=0)" || bad "$1 rc=$rc ← ${out:0:900}"
  hasnt "$out" "$OLDA" "  └ ⓐ 거절 줄 0"
  has "$out" "OK 증거 줄" "  └ ⑥ 증거 줄 = 팩 HEAD 대조 통과"
  has "$(cat "$T/ledger.md")" "mode=pack-wt wt=$PW branch=nano/k" "  └ 원장 행 mode=pack-wt"
}
rejected() {  # rejected <라벨> — ⓐ REJECT(새 문구) · kill·명부 변경 0
  local out rc; out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "$1 → REJECT(rc=1)" || bad "$1 rc=$rc ← ${out:0:600}"
  has "$out" "$OLDA" "  └ ⓐ 거절 줄"
  has "$out" "$NEWMSG" "  └ 새 문구(A3)"
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "  └ REJECT 인데 tmux 변경: $(cat "$T/tlog")"
}

echo "== A1 ft_pack_card rc"
( . "$T/bin/ft-team-lib.sh"
  declare -F ft_pack_card >/dev/null || { echo "FAIL A1 ft_pack_card 함수 없음"; exit 1; }
  r=0; for c in harness:0 planner-pack:0 planner-prod:1 planner-hprod:1 planner-body:1; do
    ft_pack_card "$T/cards/${c%%:*}.md"; g=$?
    [ "$g" = "${c##*:}" ] && echo "PASS A1 ${c%%:*} rc=$g" || { echo "FAIL A1 ${c%%:*} rc=$g (기대 ${c##*:})"; r=1; }
  done
  ft_pack_card "$T/cards/없음.md"; g=$?; [ "$g" = 1 ] && echo "PASS A1 카드 없음 rc=1" || { echo "FAIL A1 카드 없음 rc=$g"; r=1; }
  ft_pack_card ""; g=$?; [ "$g" = 1 ] && echo "PASS A1 빈 인자 rc=1" || { echo "FAIL A1 빈 인자 rc=$g"; r=1; }
  exit "$r" ) || fail=$((fail+1))

echo "== ① planner 원장 + 정본 영향 «팩 원본» + 팩 등록 --wt → ⓐ 통과"
setup planner-pack; closed "①"
echo "== ③ planner 원장 + 정본 영향 «제품 docs» → ⓐ REJECT"
setup planner-prod; rejected "③ 제품 docs"
echo "== ③' planner 원장 + 정본 영향 «하네스 제품 docs»(팩 원본 없음) → ⓐ REJECT"
setup planner-hprod; rejected "③' 하네스 제품 docs"
echo "== ④ 하네스 원장 카드 → 지금 그대로 CLOSED"
setup harness; closed "④"
echo "== ⑤ «팩 원본» 이 본문 ## 배경 아래에만 → ⓐ REJECT"
setup planner-body; rejected "⑤ 본문만"

echo "== ② spawn pack_wt_line (추적 lib source + 추적 spawn 의 함수 본문)"
( . "$T/bin/ft-team-lib.sh"
  fn="$(awk '/^pack_wt_line\(\) \{/,/^\}/' "$SRC/ft-nano-spawn.sh")"; [ -n "$fn" ] || { echo "FAIL ② pack_wt_line 함수 없음"; exit 1; }
  eval "$fn"; r=0
  for c in harness:1 planner-pack:1 planner-prod:0 planner-hprod:0 planner-body:0; do
    o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/cards/${c%%:*}.md" s1 nano/s1)"
    case "$o" in *"팩 작업 폴더 = /x/pack/.worktrees/s1"*) n=1;; '') n=0;; *) n=x;; esac
    [ "$n" = "${c##*:}" ] && echo "PASS ② ${c%%:*} 줄 $n" || { echo "FAIL ② ${c%%:*} 줄 $n (기대 ${c##*:}) «${o}»"; r=1; }
  done; exit "$r" ) || fail=$((fail+1))

if [ -z "${FT_R1785_BIN:-}" ]; then
  for f in ft-team-lib.sh ft-nano-close.sh ft-nano-spawn.sh; do
    cmp -s "$TRACKED/$f" "$KIT/$f" && ok "bin·kit cmp0 $f" || bad "bin·kit 내용 다름 $f"
  done
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
