#!/usr/bin/env bash
# _landed_ref_wt_r1737_fixture.sh — r1737 시험 공용 픽스처(사례 아님 · source 전용).
#   임시 git 리포(ROOT + bare REMOTE 두 가지) + 좌석 워크트리 2(가지 이름 ≠ 키 · 중간 -r숫자- 키) + 임시 명부·카드 + PATH 스텁(tmux·gh).
#   실 리포·실 명부·실 좌석·실 tmux·gh(네트워크) 0 · sleep 0 · press 0 · 고정을 쓰지 않는다(호출자가 fail/ok/has 를 먼저 정의).

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }


mkdir -p "$T/bin" "$T/fake" "$T/basebin" "$T/hil"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/"{ft-nano-close,ft-nano-evidence-check,ft-nano-cherry-gate,ft-wt-sweep,ft-team-lib,ft-card-target-lib,ft-sheet-events}.sh \
   "$SRC/"{ft_teamset,ft_team_lib,ft_sheet_events,ft_sheet_confirm,ft_sheet_key,ft_board_env,ft_board_mail}.py "$T/bin/"
cp "$T/bin/"* "$T/basebin/"
BASE_SHA=445533f6   # r1737 기준판 = 이 카드의 팩 base(고치기 전 ft-nano-close.sh · origin/main 은 랜딩 뒤 움직인다)
git -C "$HERE" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh" || git -C "$HERE" show "origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  ls) if [ -s "$FAKE_SESSIONS" ]; then cat "$FAKE_SESSIONS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

BYZ_URL='https://github.com/lptest/byz.git'
ROOT="$T/repo"; mkdir -p "$ROOT"
git -C "$ROOT" init -q -b main && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" remote add origin "$BYZ_URL"
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
push_ref() { git -C "$ROOT" push -q --force "$REMOTE" "$1:refs/heads/$2"; }
push_ref "$(git -C "$ROOT" rev-parse main)" main; push_ref "$(git -C "$ROOT" rev-parse main)" ops/main-base
set_origin() {  # set_origin <리포 경로> — insteadOf 규칙 하나만(둘이 같은 url 이면 git 이 모호로 실패)
  while read -r _k _v; do git -C "$ROOT" config --unset-all "$_k" 2>/dev/null; done < <(git -C "$ROOT" config --get-regexp '^url\..*\.insteadof$' 2>/dev/null)
  git -C "$ROOT" config "url.$1.insteadOf" "$BYZ_URL"; }
set_origin "$REMOTE"
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-ops-nano-refwt#0'; BR='nano/refwt-cfg'; NW="$ROOT/.worktrees/v65-refwt-cfg"   # ★가지 이름(→cfg) ≠ 좌석 키(refwt)
CARD_REL='design/ops/indices/진행/refwt.md'; CARD="$ROOT/$CARD_REL"; LEDGER="$T/ledger.md"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/web" && echo 'x' > "$NW/web/a.txt"
git -C "$NW" add web/a.txt && git -C "$NW" commit -q -m "work (착지한 세트)"
SET="$(git -C "$NW" rev-parse HEAD)"; BASE_MAIN="$(git -C "$ROOT" rev-parse main)"
NW2="$ROOT/.worktrees/v65-refwt-r2-cfg"; git -C "$ROOT" worktree add -q -b nano/refwt-r2-cfg "$NW2" "$SET"   # ★중간 -r숫자- 키(DA R1 꼴)
squash_on() {  # squash_on <원격 가지> <끝줄> — 그 가지 위에 «끝줄 = 인자» 커밋 1개(ft-merge-land 꼴)
  local base tree c
  base="$(git -C "$ROOT" rev-parse "refs/remotes/origin/$1")"
  tree="$(git -C "$ROOT" rev-parse "$base^{tree}")"
  c="$(git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$base" -m "$2")"
  push_ref "$c" "$1"; git -C "$ROOT" fetch -q origin "$1"
}
setup() {  # setup — 명부·카드·gh·원장·스텁을 «정상(착지 0)» 으로 리셋 · 워크트리 HEAD = 세트 · 최근 mtime 0(유휴 검사)
  git -C "$NW" reset -q --hard "$SET"; git -C "$NW" clean -qfd; find "$NW" "$NW2" -type f -not -path '*/.git/*' -exec touch -t 202001010101 {} + 2>/dev/null
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; : > "$T/sessions"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  printf '# 인덱스: refwt\n## 상태\n- 2026-11-12 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n' "$SET" > "$CARD"
  printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$SET" > "$T/gh.json"
  set_origin "$REMOTE"; push_ref "$BASE_MAIN" main; push_ref "$BASE_MAIN" ops/main-base; git -C "$ROOT" fetch -q origin
}
SQ="squash 착지"$'\n\n'"PR #363 (head $SET)"   # ft-merge-land 꼴(끝줄 = «PR #363 (head <세트>)»)
land_main() { squash_on main "$SQ"; }   # origin/main 에 이 PR 의 squash 를 올린다
alive() { printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; }   # 좌석 세션 살아 있음 · pane cwd = 그 워크트리
alive2() { printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$NW2" > "$T/cwd"; }   # pane cwd = 중간 -r숫자- 키 워크트리
close() { ( cd "$ROOT" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_SESSIONS="$T/sessions" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_JSON="$T/gh.json" \
  FT_LAND_REF="${FT_LAND_REF:-}" FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {  # untouched <이름> — REJECT 인데 닫기 흔적 0
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"; git -C "$ROOT" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "$1: 브랜치 삭제"
}
closed_ok() { jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "$1: 명부에 남음"; }
mutant() {  # mutant <old> <new> … → $T/mutbin/ft-nano-close.sh(자리마다 정확 1곳)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; pairs = sys.argv[2:]
s = open(p, encoding='utf-8').read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
    s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
}
