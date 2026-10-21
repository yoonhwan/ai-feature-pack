#!/usr/bin/env bash
# test_nano_close_sha_base.sh — 카드 r42-nano-close-sha-base: .worktree-info.json 의 base 가 sha 인 좌석도 닫힌다 (닫기 기준 = 랜딩 브랜치)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 스크립트 사본만 쓴다 — 실제 리포·seats·tmux 세션·원격 쓰기 0. cherry 게이트는 «진짜» 를 쓴다(인자만 기록하는 래퍼 경유).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
TRK="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # r448: 닫기의 reap = 같은 bin 스텁(env -i 시험 · 실기계 프로세스 0) · reap 자체는 test_seat_reap_left0.sh
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

for f in ft-nano-close.sh ft-nano-spawn.sh; do
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$SRC/$f" "$TRK/$f" && ok "사본 cmp $f" || bad "사본 불일치 $f"
done

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"   # 사건 원장 훅(PLAN-status-sheet §3-1) 의존 — 설치 폴더 밖 시험이라 FT_SHEET_ROOT 로 임시 루트
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

cp "$SRC/ft-nano-cherry-gate.sh" "$T/bin/ft-nano-cherry-gate.real.sh"
# 래퍼 — 받은 feat/branch 를 기록하고 진짜 게이트에 넘긴다
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

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init
FORK="$(GIT rev-parse HEAD)"                       # 나노가 갈라진 점(sha)
LAND=feat/v6-realtime-live; OTHER=land/other       # 기본 랜딩 브랜치 · 다른 랜딩 브랜치
GIT branch "$LAND" "$FORK"; GIT branch "$OTHER" "$FORK"
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"

SEAT='byz-planner-nano-ovr#0'; CARD="$REPO/design/planner/indices/진행/ovr.md"
NW="$REPO/.worktrees/cfo-ovr"; BR="fix/ovr-sha"
GIT worktree add -q "$NW" -b "$BR" "$FORK"
echo work > "$NW/work.txt"; git -C "$NW" add work.txt; git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"
echo ".worktree-info.json" >> "$REPO/.git/info/exclude"   # 실제 좌석처럼 info 파일은 추적 밖(ⓔ 미커밋 검사에 안 걸린다)
# 랜딩: 나노 산출을 squash 로 기본 랜딩 브랜치에만 넣는다(커밋 sha 는 달라지고 patch-id 도 squash 라 cherry 는 못 본다 → merge-tree 가 본다)
GIT worktree add -q "$T/landwt" "$LAND"
git -C "$T/landwt" merge --squash -q "$BR" >/dev/null 2>&1; git -C "$T/landwt" -c user.email=t@t -c user.name=t commit -q -m "squash land"
# 「조상 아님」 용 sha — 어느 랜딩 브랜치에도 없는 가지의 커밋
GIT checkout -q -b side "$FORK" 2>/dev/null; echo s > "$REPO/side.txt"; GIT add side.txt; GIT commit -q -m side; SIDE="$(GIT rev-parse HEAD)"; GIT checkout -q main

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setinfo() {  # setinfo <base 값> — 좌석 워크트리 .worktree-info.json 의 base
  printf '{"branch":"%s","base":"%s","base_sha":"%s","purpose":"t"}\n' "$BR" "$1" "${FORK:0:10}" > "$NW/.worktree-info.json"
}
setup() {  # 각 케이스 전 «정상» 리셋
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean" "$T/cherry.args"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run "$@" FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR"; }
# run 이 env -i 라 close 앞 인자(FT_NANO_FEAT=…)는 run "$@" 맨 앞에서 env 인자로 간다.

echo "== ① info.base=sha(랜딩 브랜치 조상) + 산출이 기본 랜딩 브랜치에 squash 랜딩 → 통과"
setinfo "$FORK"; setup; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "CLOSED(rc=0)" || bad "① rc=$rc ← ${out:0:700}"
has "$out" "INFO base sha ${FORK:0:9} → 랜딩 브랜치 $LAND" "  └ INFO 줄(sha → 랜딩 브랜치)"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "$LAND $BR" ] && ok "  └ 게이트 기준 = 랜딩 브랜치(sha 아님)" || bad "게이트 인자: $(cat "$T/cherry.args" 2>/dev/null)"

echo "== ② info.base=sha 인데 랜딩 브랜치의 조상이 아님 → REJECT(추측 0)"
setinfo "$SIDE"; setup; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "base 가 sha ${SIDE:0:9} 이고 $LAND 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시" "REJECT 문구" || bad "② rc=$rc ← ${out:0:500}"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "REJECT 인데 tmux 변경: $(cat "$T/tlog")"
jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "REJECT 인데 명부 삭제"

echo "== ③ info.base=브랜치 → 지금과 같은 결과(INFO 없음 · 그 브랜치가 기준)"
setinfo "$LAND"; setup; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "CLOSED(rc=0)" || bad "③ rc=$rc ← ${out:0:700}"
hasnt "$out" "INFO base sha" "  └ sha 분기 INFO 없음"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "$LAND $BR" ] && ok "  └ 게이트 기준 = info.base 브랜치" || bad "게이트 인자: $(cat "$T/cherry.args" 2>/dev/null)"

echo "== ④ FT_NANO_FEAT 명시 → 그 값 우선(sha base 여도 sha 분기 안 탐)"
setinfo "$FORK"; setup; out="$(close FT_NANO_FEAT="$OTHER")"; rc=$?
hasnt "$out" "INFO base sha" "  └ sha 분기 INFO 없음"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "$OTHER $BR" ] && ok "  └ 게이트 기준 = FT_NANO_FEAT 값" || bad "게이트 인자: $(cat "$T/cherry.args" 2>/dev/null) (rc=$rc ← ${out:0:300})"

echo "== ⑤ spawn: --base <sha> 면 info base=랜딩 브랜치(지금 브랜치/FT_NANO_FEAT) · 브랜치 이름 base 는 무변경"
SNIP="$(awk '/^# R42: --base/{p=1} p{print} p&&/^fi$/{exit}' "$SRC/ft-nano-spawn.sh")"
[ -n "$SNIP" ] && ok "spawn 에 R42 블록 있음" || bad "spawn 에 R42 블록 없음"
infobase() {  # infobase <BASE_REF> [FT_NANO_FEAT] → INFO_BASE
  ( ROOT="$REPO"; WT="$NW"; BASE_REF="$1"; BASE_BRANCH="${1:-$(git -C "$WT" rev-parse --abbrev-ref HEAD)}"; INFO_BASE="$BASE_BRANCH"
    [ -z "${2:-}" ] || export FT_NANO_FEAT="$2"
    eval "$SNIP"; printf '%s' "$INFO_BASE" )
}
[ "$(infobase "$FORK")" = "$BR" ] && ok "sha → 지금 브랜치($BR)" || bad "sha → $(infobase "$FORK")"
[ "$(infobase "$FORK" "$LAND")" = "$LAND" ] && ok "sha + FT_NANO_FEAT → 그 값" || bad "sha+FEAT → $(infobase "$FORK" "$LAND")"
[ "$(infobase "$LAND")" = "$LAND" ] && ok "브랜치 이름 → 무변경" || bad "브랜치 → $(infobase "$LAND")"
[ "$(infobase "")" = "$BR" ] && ok "--base 없음 → 무변경(지금 브랜치)" || bad "없음 → $(infobase "")"
grep -q '"\$BRANCH" "\$INFO_BASE" "\$(git -C "\$ROOT" rev-parse --short "\$BASE_BRANCH")"' "$SRC/ft-nano-spawn.sh" \
  && ok ".worktree-info.json 기록이 \"base\"=\$INFO_BASE · \"base_sha\"=BASE_BRANCH 의 짧은 sha" || bad "info printf 인자 불일치"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
