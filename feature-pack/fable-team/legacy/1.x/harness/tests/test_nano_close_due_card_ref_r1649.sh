#!/usr/bin/env bash
# test_nano_close_due_card_ref_r1649.sh — r1649 ⓔ: ft-nano-close-due.sh 의 카드 읽기가 «카드 ref» 판을 먼저 본다.
#   실측 꼴 = 명부 index 칸은 진행/<카드>.md 인데 카드는 ref(origin/main)에 이미 완성/<카드>.md 뿐이고,
#   카드 워크트리(_cards_wt) 체크아웃은 뒤처져 그 파일이 없다 → 지금은 «카드 파일 없음(근거 0)» 으로 닫을 좌석 0.
#   임시 리포 2개(remote·데이터 루트 clone) + 좌석 clone + 가짜 tmux·ft-seat-status 만 — 실 명부·tmux·좌석 0 · sleep 0.
set -uo pipefail
export LC_ALL=C
ulimit -u 2000 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="$BIN/ft-nano-close-due.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }

echo "== 짝 cmp · bash -n"
for f in ft-nano-close-due.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; done
bash -n "$TOOL" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$TOOL" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"
eq "$(grep -c 'r1649-mut:cardref' "$TOOL")" "1" "변이 표식 r1649-mut:cardref 1개(ref 후보 삭제 지점)"

T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) cat "$FAKE_SESS";;
  display-message) s="${4#=}"; s="${s%:}"; cat "$FAKE_CWD_DIR/$s";;
  *) exit 9;;
esac
EOF
cat > "$FK/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = turn ] && [ -f "$FAKE_SS_DIR/$2" ] && { cat "$FAKE_SS_DIR/$2"; exit 0; }
exit 1
EOF
chmod +x "$FK/tmux" "$FK/ft-seat-status.sh"
export PATH="$FK:$PATH" FT_CLOSE_DUE_SEAT_STATUS="$FK/ft-seat-status.sh"
export FAKE_SESS="$T/sess" FAKE_CWD_DIR="$T/cwd" FAKE_SS_DIR="$T/ss"
mkdir -p "$T/cwd" "$T/ss"; : > "$T/sess"

# ── 픽스처: remote(정본) · 좌석 clone · 데이터 루트 clone(=2번째 리포) ──────────────────────────
SLUG=refcard; SEAT="byz-harness-nano-$SLUG#0"; REM="$T/rem/origin.git"; WT="$T/wt/$SLUG"; ROOT="$T/root"
git init -q --bare -b main "$REM"; git clone -q "$REM" "$WT" 2>/dev/null
git -C "$WT" checkout -q -b main
mkdir -p "$WT/design/teams/harness"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$WT/design/TEAMS.md"
echo a > "$WT/a"; git -C "$WT" add -A; git -C "$WT" commit -qm M0; git -C "$WT" push -q origin main 2>/dev/null
git -C "$WT" checkout -q -b "nano/$SLUG"; echo x > "$WT/x"; git -C "$WT" add x; git -C "$WT" commit -qm work
H="$(git -C "$WT" rev-parse HEAD)"; git -C "$WT" push -q origin "nano/$SLUG:main" 2>/dev/null   # ff 착지 = origin/main 이 H
git clone -q "$REM" "$ROOT"   # 데이터 루트 = 뒤처진 체크아웃(카드 없음 · remote-tracking 도 H)
# 카드는 «ref 에만» 만든다 — 진행/<카드>.md 는 어디에도 없고 ref 에는 완성/<카드>.md
git -C "$WT" branch -q -f main "$H"; git -C "$WT" checkout -q main; mkdir -p "$WT/design/teams/harness/indices/완성"
printf '# 인덱스: card1\n## 구현 범위\n- x\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n' "$H" > "$WT/design/teams/harness/indices/완성/card1.md"
git -C "$WT" add -A; git -C "$WT" commit -qm card; git -C "$WT" push -q origin main 2>/dev/null || bad "픽스처: 카드 push 실패"
git -C "$WT" checkout -q "nano/$SLUG"
mkdir -p "$ROOT/.fable-team/state" "$ROOT/.worktrees/cards-wt"
python3 - "$ROOT" "$SEAT" <<'PY'
import json, sys
root, seat = sys.argv[1], sys.argv[2]
json.dump({"_master": "byz-harness-master-pi#193", "_cards_wt": "cards-wt",
           seat: {"role": "nano", "agent": "pi", "cwd": "/nonexistent/bogus",
                  "index": "design/teams/harness/indices/진행/card1.md"}},
          open(root + "/.fable-team/seats-harness.json", "w"), ensure_ascii=False)
PY
printf '%s\n' "$SEAT" > "$T/sess"; printf '%s\n' "$WT" > "$T/cwd/$SEAT"; printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"

echo "== 사례 — ref 판에서만 카드를 찾는다"
git -C "$ROOT" cat-file -e "origin/main:design/teams/harness/indices/완성/card1.md" 2>/dev/null && bad "사전: ROOT 의 remote-tracking 에 이미 카드가 있다(fetch 가 필요한 상황이 아니다)" || ok "사전: ROOT 의 remote-tracking 에는 카드가 없다(fetch 가 필요하다)"
[ ! -f "$ROOT/design/teams/harness/indices/완성/card1.md" ] && [ ! -f "$ROOT/.worktrees/cards-wt/design/teams/harness/indices/진행/card1.md" ] && ok "사전: 카드 후보(워크트리·루트 체크아웃)에 카드 파일 0(지금은 근거 0 이던 자리)" || bad "사전: 후보에 카드가 있다"
OUT="$(FT_ROOT="$ROOT" bash "$TOOL" --all --why 2>&1)"; RC=$?
eq "$RC" "0" "E1 판정 불가 0(정상 판정)"
has "$OUT" "닫기 차례 $SEAT 팀=harness 가지=nano/$SLUG landed=ff" "E2 ref(완성/card1.md)에서 세트를 읽어 닫기 차례에 넣는다"
hasnt "$OUT" "제외 $SEAT 카드 파일 없음" "E3 «카드 파일 없음(근거 0)» 0"
git -C "$ROOT" cat-file -e "origin/main:design/teams/harness/indices/완성/card1.md" 2>/dev/null && ok "E4 카드 ref 를 fetch 했다(뒤처진 remote-tracking 을 그대로 믿지 않는다)" || bad "E4 fetch 0"

echo "== 결과: FAIL=$fail"
exit $(( fail > 0 ? 1 : 0 ))
