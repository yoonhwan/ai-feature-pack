#!/usr/bin/env bash
# test_pack_nano_worktree_place.sh — 카드 r519: 하네스 «팩 나노» 의 팩 작업 폴더 자리 = <팩>/.worktrees/<키>
#   ⓐ 하네스 카드(- 설치: 있음) spawn 발주문에 «팩 작업 폴더» 1줄 ⓑ 제품 카드(- 설치: 없음) 0줄
#   ⓒ nano-close --wt <팩 등록 · 표준 자리 밖> → REJECT 그대로 + «git -C <팩> worktree move … 뒤 같은 명령» 덧말
#   ⓓ worktree move 로 옮긴 뒤 같은 명령 → 지금 팩 모드 그대로 CLOSED
# 임시 리포 2개(BYZ 꼴 R · 팩 꼴 P + bare 원격) + 가짜 tmux · spawn 은 함수 본문만 추출 — 실제 리포·seats·tmux·외부 호출 0 · GIT_* env 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

echo "== ⓐⓑ spawn 발주문 «팩 작업 폴더» 줄 (함수 추출 · 스크립트 전체 실행 0)"
FN="$(awk '/^pack_wt_line\(\) \{/,/^\}/' "$SRC/ft-nano-spawn.sh")"
if [ -n "$FN" ]; then ok "pack_wt_line 함수 추출"; eval "$FN"; else bad "pack_wt_line 함수 없음"; pack_wt_line() { :; }; fi
grep -q '^BODY=.*\$_PKX' "$SRC/ft-nano-spawn.sh" && ok "BODY 가 \$_PKX 를 붙인다" || bad "BODY 에 \$_PKX 없음"
grep -q '^_PKX="\$(pack_wt_line "\$IDX" "\$SLUG" "\$BRANCH")"' "$SRC/ft-nano-spawn.sh" && ok "_PKX = pack_wt_line IDX SLUG BRANCH" || bad "_PKX 정의 줄 없음"
printf '# 인덱스: k\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n' > "$T/hcard.md"
printf '# 인덱스: k\n- 설치: 없음\n\n## 상태\n' > "$T/pcard.md"
o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/hcard.md" kslug nano/kslug)"
has "$o" "팩 작업 폴더 = /x/pack/.worktrees/kslug" "ⓐ 하네스 카드 → 팩 작업 폴더 줄"
has "$o" "git -C /x/pack worktree add /x/pack/.worktrees/kslug -b nano/kslug origin/main" "  └ 만드는 명령 1줄"
has "$o" "세션 스크래치 0" "  └ 스크래치 금지"
has "$o" "nano-close --wt /x/pack/.worktrees/kslug --branch nano/kslug" "  └ 닫기 경로"
o="$(env -u FT_PACK_ROOT HOME=/h bash -c "$FN"'; pack_wt_line "$1" k nano/k' _ "$T/hcard.md")"
has "$o" "팩 작업 폴더 = /h/Project/ai-feature-pack/.worktrees/k" "ⓐ FT_PACK_ROOT 없음 → 기본 \$HOME/Project/ai-feature-pack"
o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/pcard.md" kslug nano/kslug)"
[ -z "$o" ] && ok "ⓑ 제품 카드 → 줄 0" || bad "ⓑ 제품 카드인데 줄이 나옴: $o"

echo "== ⓒⓓ nano-close 팩 모드 · 표준 자리 밖 → 덧말 · move 뒤 CLOSED"
mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
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
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
RW="$R/.worktrees/harness-k"
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
OUT="$T/scratch/afp"; mkdir -p "$T/scratch"   # 세션 스크래치 꼴(실사건 r517) — 팩 등록 · 표준 자리 밖
GC "$P" worktree add -q "$OUT" -b nano/k origin/main
echo kit > "$OUT/kit.sh"; GC "$OUT" add kit.sh; GC "$OUT" commit -q -m work
SHA="$(git -C "$OUT" rev-parse HEAD)"
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"
run() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$R/.fable-team/seats-harness.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$RW" > "$T/pane-cwds"; printf '%s' "$RW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  printf '# 인덱스: k\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_PACK_ROOT="$P" \
  FT_SEATS_JSON="$R/.fable-team/seats-harness.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }

setup; out="$(close --wt "$OUT" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓒ 표준 자리 밖 → REJECT 그대로" || bad "ⓒ rc=$rc ← ${out:0:600}"
has "$out" "ⓐ--wt($OUT)가 이 리포($R)에 등록된 .worktrees/ 아래 워크트리가 아니다" "  └ 지금 ⓐ 문구 그대로"
has "$out" "표준 자리 밖 — mkdir -p $P/.worktrees && git -C $P worktree move $OUT $P/.worktrees/k 뒤 같은 명령(--wt $P/.worktrees/k)" "  └ 덧말 «worktree move … 뒤 같은 명령»"
MV="$(grep -o 'mkdir -p [^ ]* && git -C [^ ]* worktree move [^ ]* [^ ]*' <<<"$out" | head -1)"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill 0" || bad "  └ REJECT 인데 tmux 변경"
[ -d "$OUT" ] && ok "  └ 워크트리 그대로(이동 0 · 닫기는 옮기지 않는다)" || bad "  └ 워크트리가 움직임"
# 대조 — BYZ 리포에도 팩에도 미등록인 폴더는 덧말 0(옮길 대상이 아님)
mkdir -p "$T/scratch/plain"; setup; out="$(close --wt "$T/scratch/plain" --branch nano/k)"
hasnt "$out" "worktree move" "ⓒ 대조: 팩 미등록 폴더 → 덧말 0"

# ⓓ 덧말 명령을 «그대로» 실행(팩 .worktrees/ 가 아직 없는 꼴 — mkdir 없이는 move 가 실패한다)
if [ -n "$MV" ] && eval "$MV"; then ok "ⓓ 덧말 명령 그대로 실행 rc=0"
else bad "ⓓ 덧말 명령 실행 실패: «${MV}»"; mkdir -p "$P/.worktrees"; git -C "$P" worktree move "$OUT" "$P/.worktrees/k"; fi   # 덧말이 없어도 아래 CLOSED(팩 모드 그대로)는 따로 본다
setup; out="$(close --wt "$P/.worktrees/k" --branch nano/k)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓓ move 뒤 같은 명령 → CLOSED(rc=0)" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$(cat "$T/ledger.md")" "mode=pack-wt wt=$P/.worktrees/k branch=nano/k" "  └ 원장 행 mode=pack-wt"
git -C "$P" rev-parse --verify -q refs/heads/nano/k >/dev/null && ok "  └ 팩 브랜치 그대로" || bad "  └ 팩 브랜치 삭제됨"

[ "$(git config --get core.bare 2>/dev/null || echo false)" = "false" ] && ok "core.bare=false" || bad "core.bare 가 false 아님"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
