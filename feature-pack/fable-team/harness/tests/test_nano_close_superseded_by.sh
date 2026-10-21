#!/usr/bin/env bash
# test_nano_close_superseded_by.sh — R171: ft-nano-close.sh --superseded-by <대체 카드> (다른 카드로 대체돼 세트를 랜딩하지 않은 나노 닫기)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 실제 cherry 게이트(원장은 임시 경로)만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 인자 없으면 불변 ⓑ REJECT 6종 ⓒ --cherry-override 동시 = exit 2 ⓓ cherry 원장 1행 사유 ⓔ 브랜치 삭제 0 · 명부 손 편집 없이 CLOSED ⓕ 키트 2곳 cmp 0 · 변이 2
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # r448: 닫기의 reap = 같은 bin 스텁(env -i 시험 · 실기계 프로세스 0) · reap 자체는 test_seat_reap_left0.sh
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓕ 키트 2곳 같은 바이트 + bash -n"
for f in ft-nano-close.sh ft-nano-superseded-check.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (fable-team-bin == harness-install)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

mkdir -p "$T/bin" "$T/fake" "$T/mut"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
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

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$REPO/design/planner/indices/대기" "$REPO/design/planner/indices/완료" "$REPO/design/planner/indices/폐기" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-sup#0'; BR='nano/sup'; NW="$REPO/.worktrees/v65-sup"
CARD_REL='design/planner/indices/진행/sup.md'; CARD="$REPO/$CARD_REL"
SUP_REL='design/planner/indices/진행/other.md'; SUP="$REPO/$SUP_REL"
GIT worktree add -q "$NW" -b "$BR"
mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/unlanded.py"
git -C "$NW" add scripts/unlanded.py && git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "work (미랜딩 코드)"
SHA="$(git -C "$NW" rev-parse HEAD)"
LEDGER="$T/ledger.md"; CHERRY_LOG="$T/cherry-override.log"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # 명부·pane·카드·가짜 tmux 상태를 «정상(세션 없음)» 으로 리셋 — 각 케이스가 한 칸만 비튼다
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -f "$CHERRY_LOG"; rm -rf "$T/wtclean"
  printf '# 인덱스: other\n## 상태\n- 진행\n' > "$SUP"
  printf '# 인덱스: sup\n## 상태\n- 2026-10-14 진행\n대체됨: %s · 사유: other 카드로 합쳐짐\n' "$SUP_REL" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$CHERRY_LOG" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {  # untouched <이름> — REJECT 인데 명부·tmux·원장·브랜치가 그대로
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: REJECT 인데 tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: REJECT 인데 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: REJECT 인데 원장 행 생김"
}
reject() {  # reject <사유 조각> <이름> <close 인자...>
  local frag="$1" name="$2"; shift 2
  out="$(close "$@")"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "REJECT" "$name → REJECT" || bad "$name — rc=$rc ← ${out:0:400}"
  has "$out" "$frag" "  └ 사유 «${frag}»"
  untouched "$name"
}

echo "== ⓐ 인자 없이 닫으면 지금 동작(⑥ 증거 줄 요구) 그대로"
setup; reject "증거 줄" "ⓐ 인자 없음 + 대체됨 줄만 있고 세트 증거 줄 없음 → 기존 ⑥ REJECT"
setup; printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
out="$(close --cherry-override "시험 사유")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT (" "ⓐ 인자 없음 + 증거 줄 rc=0 → 기존 경로로 CLOSED(superseded-by 표식 없음)" || bad "ⓐ 기존 경로 rc=$rc ← ${out:0:400}"
hasnt "$out" "superseded-by=" "  └ 출력에 superseded-by 표식 없음"
hasnt "$(cat "$LEDGER")" "superseded-by=" "  └ 닫힘 원장 행에 superseded-by 표식 없음"

echo "== usage (exit 2)"
setup; out="$(close --superseded-by)"; rc=$?;                     [ "$rc" -eq 2 ] && ok "ⓒ --superseded-by 값 누락 → exit 2" || bad "값 누락 rc=$rc"
setup; out="$(close --superseded-by "")"; rc=$?;                  [ "$rc" -eq 2 ] && ok "ⓒ --superseded-by 빈 값 → exit 2" || bad "빈 값 rc=$rc"
setup; out="$(close --superseded-by "$SUP_REL" --cherry-override "사유")"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "동시에 못 쓴다" "ⓒ --cherry-override 와 동시 → exit 2" || bad "동시 지정 rc=$rc ← ${out:0:300}"
setup; out="$(close --cherry-override "사유" --superseded-by "$SUP_REL")"; rc=$?; [ "$rc" -eq 2 ] && ok "ⓒ 순서 바꿔도 exit 2" || bad "순서 바꿈 rc=$rc"
untouched "usage"

echo "== ⓑ REJECT 6종 — 대체 카드 없음·자기 자신·대기/진행/완료 밖·사유 빈칸·대체됨 줄 없음·경로 불일치"
setup; rm -f "$SUP"
reject "대체 카드 파일이 없다" "ⓑ 대체 카드 파일 없음" --superseded-by "$SUP_REL"
setup; printf '# 인덱스: sup\n## 상태\n대체됨: %s · 사유: 자기 자신\n' "$CARD_REL" > "$CARD"
reject "자신이다" "ⓑ 대체 카드 = 자기 자신" --superseded-by "$CARD_REL"
setup; printf '## 상태\n대체됨: design/planner/indices/폐기/other.md · 사유: 폐기 폴더\n' > "$CARD"; printf 'x\n' > "$REPO/design/planner/indices/폐기/other.md"
reject "{대기,진행,완성,완료}" "ⓑ 대체 카드가 대기/진행/완성/완료 밖(폐기/)" --superseded-by design/planner/indices/폐기/other.md
setup; printf '## 상태\n대체됨: design/planner/../x/indices/진행/other.md · 사유: 상위 경로\n' > "$CARD"
reject "«..»" "ⓑ 대체 카드 경로에 .." --superseded-by design/planner/../x/indices/진행/other.md
setup; printf '## 상태\n대체됨: %s · 사유:   \n' "$SUP_REL" > "$CARD"
reject "사유가 비어" "ⓑ 사유 빈칸" --superseded-by "$SUP_REL"
setup; printf '## 상태\n- 2026-10-14 진행\n' > "$CARD"
reject "대체됨:» 줄이 아니다" "ⓑ «대체됨:» 줄 없음" --superseded-by "$SUP_REL"
setup; printf '## 상태\n대체됨: %s · 사유: 맞음\n- 뒤에 다른 줄\n' "$SUP_REL" > "$CARD"
reject "대체됨:» 줄이 아니다" "ⓑ 대체됨 줄이 «맨 끝»이 아님" --superseded-by "$SUP_REL"
setup; reject "다르다" "ⓑ 줄의 경로 ≠ --superseded-by 값" --superseded-by design/planner/indices/대기/other.md

echo "== 전부 맞음 → CLOSED (세션 없음)"
setup; out="$(close --superseded-by "$SUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT superseded-by=$SUP_REL" "ⓔ 통과 → CLOSED superseded-by=<카드> (rc=0)" || bad "통과 rc=$rc ← ${out:0:600}"
has "$out" "OK 대체됨" "  └ ⑥ 대체됨 검사 통과 줄"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제 — 손 편집 없이 도구가 갱신" || bad "명부에 좌석 남음"
has "$(cat "$LEDGER")" "superseded-by=$SUP_REL" "  └ 닫힘 원장 행에 superseded-by=<카드>"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 삭제 0" || bad "브랜치 삭제됨"
[ "$(git -C "$NW" rev-parse HEAD)" = "$SHA" ] && ok "  └ 나노 HEAD 그대로" || bad "HEAD 가 움직임"

echo "== ⓓ ⑤ cherry — 미랜딩 코드는 REJECT 일 상황 → override 사유 = superseded-by <카드>, 원장 1행"
[ "$(wc -l < "$CHERRY_LOG" | tr -d ' ')" = "1" ] && ok "ⓓ cherry-gate-override 원장 1행" || bad "cherry 원장 행수: $(wc -l < "$CHERRY_LOG" 2>&1)"
has "$(cat "$CHERRY_LOG")" "reason=superseded-by $SUP_REL" "  └ 사유 = superseded-by <카드>"
has "$(cat "$CHERRY_LOG")" "seat=$SEAT" "  └ seat 칸 = 좌석명"
setup; out="$(close --cherry-override "사람 사유")"; has "$(cat "$CHERRY_LOG" 2>/dev/null)" "reason=사람 사유" "기존 --cherry-override 사유는 그대로(⑥ 은 별개 REJECT: 증거 줄 없음)" || true
setup; out="$(close)"; hasnt "$(cat "$CHERRY_LOG" 2>/dev/null)" "superseded-by" "인자 없이는 cherry 원장에 superseded-by 행 0"

echo "== 세션이 살아 있는 좌석 → CLOSED + 태그 해제 + kill (브랜치 보존)"
setup; printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close --superseded-by "$SUP_REL")"
# FT_WT_AUTOCLEAN=0 이면 기존 스크립트 마지막 줄 &&-체인이 1 을 돌려준다(R171 이전부터) — 종료코드가 아니라 출력·상태로 본다
has "$out" "CLOSED $SEAT superseded-by=$SUP_REL (명부 삭제 · 원장 append)" "살아 있는 좌석 → CLOSED <좌석> superseded-by=<카드> 1줄"
has "$out" "KILLED $SEAT" "  └ 세션 kill(표준승인 경로)"
has "$(cat "$T/tlog")" "kill-session" "  └ 가짜 tmux kill-session 호출"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 삭제 0" || bad "브랜치 삭제됨"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제" || bad "명부에 좌석 남음"

mutate() {  # mutate <이름> <python 치환 스크립트> — 도우미 사본에 변이를 넣어 $T/bin 에 덮어쓴다
  python3 - "$SRC/ft-nano-superseded-check.sh" "$T/bin/ft-nano-superseded-check.sh" <<PY
import sys
src = open(sys.argv[1], encoding="utf-8").read().split("\n")
$2
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(src))
PY
  chmod +x "$T/bin/ft-nano-superseded-check.sh"
}
echo "== ⓑ 심링크 우회 차단 (DA⑥ r171 H1) — 이름만 허용 꼴인 심링크의 실제 위치(canonical)가 base 의 indices/{대기,진행,완료} 밖이면 REJECT"
printf 'outside\n' > "$T/outside.md"; mkdir -p "$T/outdir" "$REPO/design/evil/indices"; printf 'x\n' > "$T/outdir/x.md"; printf 'readme\n' > "$REPO/README.md"
symcard() { printf '## 상태\n대체됨: %s · 사유: 심링크 시험\n' "$1" > "$CARD"; }
LINK_REL='design/planner/indices/진행/link.md'
setup; ln -s "$T/outside.md" "$REPO/$LINK_REL"; symcard "$LINK_REL"
reject "실제 위치가 허용 범위 밖" "ⓑ① 허용 이름 심링크 → base 밖 파일" --superseded-by "$LINK_REL"
has "$out" "→ $T/outside.md" "  └ 사유에 canonical 경로"
rm -f "$REPO/$LINK_REL"
setup; ln -s "$T/outdir" "$REPO/design/evil/indices/진행"; symcard "design/evil/indices/진행/x.md"
reject "실제 위치가 허용 범위 밖" "ⓑ② indices/진행 폴더 자체가 base 밖 폴더 심링크" --superseded-by design/evil/indices/진행/x.md
rm -f "$REPO/design/evil/indices/진행"
setup; ln -s "$REPO/README.md" "$REPO/$LINK_REL"; symcard "$LINK_REL"
reject "실제 위치가 허용 범위 밖" "ⓑ③ 허용 이름 심링크 → base 안 비-indices 파일(README.md)" --superseded-by "$LINK_REL"
rm -f "$REPO/$LINK_REL"
setup; ln -s "$SUP" "$REPO/$LINK_REL"; symcard "$LINK_REL"
out="$(close --superseded-by "$LINK_REL")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT superseded-by=$LINK_REL" "ⓑ④ base 안 다른 허용 카드로의 심링크 → 정상 통과" || bad "ⓑ④ rc=$rc ← ${out:0:400}"
rm -f "$REPO/$LINK_REL"

echo "== 변이 3 — canonical 범위 검사를 지우면 ①② 가 통과해 버린다(= 이 시험이 변이를 검출)"
mutate C '
a = next(i for i, l in enumerate(src) if l.startswith("for b in \"${BASES[@]}\"; do"))
b = next(i for i in range(a + 1, len(src)) if src[i] == "done")
src[a:b+1] = ["for b in \"${BASES[@]}\"; do [ -f \"$b/$SUP\" ] && { found=\"$b/$SUP\"; break; }; done"]
'
setup; ln -s "$T/outside.md" "$REPO/$LINK_REL"; symcard "$LINK_REL"
out="$(close --superseded-by "$LINK_REL")"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 C: ① base 밖 파일 심링크가 통과 → 시험 ①이 변이를 검출" || bad "변이 C ① 미검출 rc=$rc ← ${out:0:300}"
rm -f "$REPO/$LINK_REL"
setup; ln -s "$T/outdir" "$REPO/design/evil/indices/진행"; symcard "design/evil/indices/진행/x.md"
out="$(close --superseded-by design/evil/indices/진행/x.md)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 C: ② base 밖 폴더 심링크가 통과 → 시험 ②가 변이를 검출" || bad "변이 C ② 미검출 rc=$rc ← ${out:0:300}"
rm -f "$REPO/design/evil/indices/진행"
cp "$SRC/ft-nano-superseded-check.sh" "$T/bin/ft-nano-superseded-check.sh"

echo "== 변이 2 — 검사를 지우면 ⓑ 케이스가 통과해 버린다(= 이 시험이 변이를 검출)"
# 변이 A: «대체됨:» 줄 검사(정규식·사유·경로 일치) 제거
mutate A '
a = next(i for i, l in enumerate(src) if l.startswith("re="))
b = next(i for i, l in enumerate(src) if l.startswith("[ \"$line_path\" = \"$SUP\" ]"))
src[a:b+1] = ["line_path=\"$SUP\"; reason=x"]
'
setup; printf '## 상태\n- 2026-10-14 진행\n' > "$CARD"
out="$(close --superseded-by "$SUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 A(대체됨 줄 검사 제거): «대체됨:» 줄 없는 카드가 통과 → ⓑ 케이스가 변이를 검출" || bad "변이 A 미검출 rc=$rc ← ${out:0:300}"
# 변이 B: 대체 카드 실재 검사 제거
cp "$SRC/ft-nano-superseded-check.sh" "$T/bin/ft-nano-superseded-check.sh"
mutate B '
a = next(i for i, l in enumerate(src) if l.startswith("found=\"\""))
b = next(i for i, l in enumerate(src) if l.startswith("[ -n \"$found\" ]"))
src[a:b+1] = ["found=\"/nonexistent/x\""]
'
setup; rm -f "$SUP"
out="$(close --superseded-by "$SUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 B(대체 카드 실재 검사 제거): 없는 대체 카드가 통과 → ⓑ 케이스가 변이를 검출" || bad "변이 B 미검출 rc=$rc ← ${out:0:300}"
cp "$SRC/ft-nano-superseded-check.sh" "$T/bin/ft-nano-superseded-check.sh"
setup; rm -f "$SUP"; out="$(close --superseded-by "$SUP_REL")"; rc=$?
[ "$rc" -eq 1 ] && ok "원본 복구 뒤 같은 입력은 다시 REJECT" || bad "원본 복구 뒤 rc=$rc"

echo "== R177 다른 팀 대체 카드 — 대체 카드 팀의 원장 워크트리를 검사 base 에만 더한다(임시 루트만 · 실 루트 .fable-team 읽기 0)"
LW="$REPO/.worktrees/loom-main"; LENV="$REPO/.fable-team/bin-loom/loom-env.sh"; XSUP_REL='design/loom/indices/진행/loom-other.md'
loomsetup() {  # 닫는 좌석 = planner 팀, 대체 카드 = loom 원장 WT 안 카드 — 루트·planner 어디에도 없다
  setup; rm -rf "$LW" "$REPO/.fable-team/bin-loom"; mkdir -p "$LW/design/loom/indices/진행" "$REPO/.fable-team/bin-loom"
  printf '# 인덱스: loom-other\n## 상태\n- 진행\n' > "$LW/$XSUP_REL"
  printf '#!/usr/bin/env bash\nexport FT_NANO_LEDGER_WT=%s\n' "$LW" > "$LENV"
  printf '## 상태\n대체됨: %s · 사유: loom 카드로 넘어감\n' "$XSUP_REL" > "$CARD"
}
loomsetup
out="$(run bash "$T/bin/ft-nano-superseded-check.sh" "$CARD" --superseded-by "$XSUP_REL" --base "$NW" --base "$REPO")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "대체 카드 파일이 없다" "ⓕ --team-root 없는 검사 단독 → REJECT rc=1(기존과 같음)" || bad "ⓕ 단독 rc=$rc ← ${out:0:300}"
out="$(run bash "$T/bin/ft-nano-superseded-check.sh" "$CARD" --superseded-by "$XSUP_REL" --base "$NW" --base "$REPO" --team-root "$REPO")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "OK 대체됨" "ⓐ --team-root 를 주면 loom 원장 WT 에서 찾아 OK rc=0" || bad "ⓐ 검사 rc=$rc ← ${out:0:300}"
loomsetup; out="$(close --superseded-by "$XSUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT superseded-by=$XSUP_REL" "ⓐ 다른 팀 카드 → close --superseded-by 통과 + CLOSED" || bad "ⓐ close rc=$rc ← ${out:0:600}"
[ "$(wc -l < "$LEDGER" | tr -d ' ')" = "1" ] && has "$(cat "$LEDGER")" "$SEAT" "ⓓ 닫힘 원장 행 = 닫는 좌석 팀 원장(FT_NANO_LEDGER)에만 1행" || bad "ⓓ 원장 행수: $(wc -l < "$LEDGER" 2>&1)"
[ "$(find "$LW" -type f | wc -l | tr -d ' ')" = "1" ] && ok "  └ 대체 카드 팀 원장 WT 쓰기 0(카드 1개 그대로)" || bad "ⓓ loom 원장 WT 에 파일이 생김: $(find "$LW" -type f | tr '\n' ' ')"
loomsetup; rm -f "$LENV"
reject "대체 카드 파일이 없다" "ⓑ 없는 팀(env 없음) → 추가 0 → 기존 REJECT" --superseded-by "$XSUP_REL"
loomsetup; printf 'export FT_NANO_LEDGER_WT=$OTHER_ROOT/.worktrees/loom-main\n' > "$LENV"
reject "대체 카드 파일이 없다" "ⓒ env 값에 다른 \$VAR → 추가 0 → REJECT" --superseded-by "$XSUP_REL"
loomsetup; printf 'export FT_NANO_LEDGER_WT=$(touch %s/pwned)%s\n' "$T" "$LW" > "$LENV"
reject "대체 카드 파일이 없다" "ⓐ env 값의 명령 치환 → 추가 0 → REJECT" --superseded-by "$XSUP_REL"
[ ! -e "$T/pwned" ] && ok "  └ env 를 source·eval 하지 않음(명령 치환 실행 0)" || bad "ⓐ env 값이 실행됨"
loomsetup; printf 'export FT_NANO_LEDGER_WT=%s\n' "$LW/없는디렉터리" > "$LENV"
reject "대체 카드 파일이 없다" "ⓒ env 값이 디렉터리가 아님 → 추가 0 → REJECT" --superseded-by "$XSUP_REL"
loomsetup; rm -f "$LW/$XSUP_REL"; ln -s "$T/outside.md" "$LW/$XSUP_REL"
reject "실제 위치가 허용 범위 밖" "ⓔ 대체 카드 팀 WT 안 심링크 → base 밖 파일 → REJECT" --superseded-by "$XSUP_REL"
loomsetup; printf 'export FT_NANO_LEDGER_WT="$_GR_ROOT/.worktrees/loom-main"\n' > "$LENV"
out="$(close --superseded-by "$XSUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT superseded-by=$XSUP_REL" "  └ graphics 꼴(\"\$_GR_ROOT/…\")는 루트로 치환해 통과" || bad "_GR_ROOT 꼴 rc=$rc ← ${out:0:400}"
loomsetup; mkdir -p "${REPO}_BAD/.worktrees/loom-main/design/loom/indices/진행"; cp "$LW/$XSUP_REL" "${REPO}_BAD/.worktrees/loom-main/$XSUP_REL"
printf 'export FT_NANO_LEDGER_WT="$_GR_ROOT_BAD/.worktrees/loom-main"\n' > "$LENV"
reject "대체 카드 파일이 없다" "ⓒ DA⑥ H1① \$_GR_ROOT_BAD 접두 치환 → 추가 0 → REJECT" --superseded-by "$XSUP_REL"
loomsetup; printf 'export FT_NANO_LEDGER_WT="%s\n' "$LW" > "$LENV"
reject "대체 카드 파일이 없다" "ⓒ DA⑥ H1② 닫히지 않은 따옴표 → 추가 0 → REJECT" --superseded-by "$XSUP_REL"
loomsetup; printf "export FT_NANO_LEDGER_WT='%s'\n" "$LW" > "$LENV"
out="$(close --superseded-by "$XSUP_REL")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT superseded-by=$XSUP_REL" "  └ 홑따옴표 쌍은 벗겨 통과" || bad "홑따옴표 쌍 rc=$rc ← ${out:0:400}"
rm -rf "$LW" "$REPO/.fable-team/bin-loom" "${REPO}_BAD"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
