#!/usr/bin/env bash
# test_nano_close_research_r888.sh — r888: ft-nano-close.sh --research (리서치 좌석 = 코드 0 · cherry +0 → ⑥ 증거 줄 면제) + 카드를 origin/main 판에서 읽기
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ --research 통과(증거 줄 없음 · cherry +0 · 미커밋 0 · --result 실재) · 인자 없으면 ⑥ REJECT 그대로
#    ⓑ cherry +1 · 미커밋 → REJECT «리서치 아님» ⓒ --result 없음 → ① REJECT ⓤ 다른 ⑥ 면제·우회 인자와 동시 = usage 2
#    ⓓ 로컬 루트 사본 = 대기/ 옛 판 · origin/main = 진행/ 새 판 → origin/main 판을 읽음 · 쓰기는 작업 트리 사본 · origin/main 에 없으면 기존 순서 · fetch 실패면 옛 ref 를 믿지 않음
#    ⓕ 변이(면제 제거 → ⓐ FAIL · origin/main 후보 제거 → ⓓ FAIL) ⓖ 600/300·외부 호출·GIT_* 0 + 키트 짝 cmp0
#    r3(DA⑥ r2 HOLD 3): 기준 = 카드 기준 판(리서치 줄 base= › «## 상태» base_sha) ⓘ기준 판 뒤 구현 커밋 1 → main 착지여도 REJECT ⓙ머리 맞춤 병합만 → OK · 곁가지 병합 → REJECT
#      ⓚbase_sha 없는 카드 → REJECT ⓛ«R … -> .serena/project.yml»·« M docs/.serena/project.yml» → 미커밋 REJECT ⓜ루트 미추적 .serena/project.yml 만 → OK
#        (r978 r2: R 은 원경로·새경로를 «둘 다» 센다 → ⓛ R 꼴의 미커밋 수 = 2)
#      변이: 기준 = origin/main → ⓘ FAIL · 정확 경로 → 접미사 → ⓛ FAIL · 곁가지 대조 제거 → ⓙ FAIL
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

mkdir -p "$T/bin" "$T/fake" "$T/tmp"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$T/bin/"
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
git -C "$REPO" update-ref refs/remotes/origin/main HEAD   # r842: 카드 단계 ref 실재(없으면 단계 판정 실패 = ERROR + REJECT) · ref 에 카드 없음 = ABSENT → 지금 규칙
git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/.fable-team" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-rs#0'; BR='nano/rs'; NW="$REPO/.worktrees/v65-rs"
IDX='design/planner/indices/진행/rs.md'; OLD_REL='design/planner/indices/대기/rs.md'
# 커밋 A = 루트 로컬이 머문 판(대기/ 옛 사본 · 증거 줄·리서치 줄 없음)
mkdir -p "$REPO/design/planner/indices/대기"
printf '# 인덱스: rs\n## 상태\n- 대기\n' > "$REPO/$OLD_REL"
mkdir -p "$REPO/scripts" "$REPO/docs/.serena"; echo 'print(0)' > "$REPO/scripts/x.py"; echo 'a: 1' > "$REPO/docs/.serena/project.yml"   # r4: ⓛ 가 쓰는 추적 파일 = 좌석이 열린 판(A)에 미리
gitc add -A && gitc commit -q -m "A: 카드 대기"
SHA_A="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
# 커밋 B = origin/main 새 판(진행/ · 리서치 줄 + 세트 증거 줄) — origin 에만 올리고 로컬 main 은 A 로 되돌린다(루트가 뒤처진 꼴)
mkdir -p "$REPO/design/planner/indices/진행"
gitc mv "$OLD_REL" "$IDX"
printf '# 인덱스: rs\n## 상태\n- 진행\n- 리서치: %s base=%s 허용=docs/*\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n' "$SEAT" "$SHA_A" "$SHA_A" > "$REPO/$IDX"
gitc add -A && gitc commit -q -m "B: 카드 진행 + 증거"
gitc push -q origin main
SHA_B="$(git -C "$REPO" rev-parse HEAD)"
gitc reset -q --hard "$SHA_A"
git -C "$REPO" rev-parse -q --verify refs/remotes/origin/main >/dev/null && ok "준비: origin/main = B · 로컬 main = A(대기/ 옛 사본)" || bad "준비 실패"

LEDGER="$T/ledger.md"; CHERRY_LOG="$T/cherry-override.log"
run() { ( cd "$REPO" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
local_card() {  # local_card <상대경로> [기준 판 sha | none] — 로컬 작업 트리에 리서치 시험용 카드(증거 줄 없음 · r3: «## 상태» base_sha 줄 = 좌석이 열린 판 · 기본 A)
  mkdir -p "$(dirname "$REPO/$1")"
  if [ "${2:-}" = none ]; then printf '# 인덱스: rs\n## 상태\n- 진행(로컬)\n' > "$REPO/$1"
  else printf '# 인덱스: rs\n## 상태\n- base_sha: %s (spawn)\n- 진행(로컬)\n' "${2:-$SHA_A}" > "$REPO/$1"; fi; }
setup() {  # 명부·pane·나노 HEAD 를 «세션 없음 · 미커밋 0 · 커밋 0(cherry +0)» 으로 리셋 · 카드 = 로컬 대기/ 옛 사본만
  git -C "$NW" reset -q --hard "$SHA_A"; git -C "$NW" clean -qfd
  gitc reset -q --hard "$SHA_A"; gitc clean -qfd -- design
  git -C "$REPO" remote set-url origin "$ORIGIN"
  git -C "$ORIGIN" update-ref refs/heads/main "$SHA_B"; gitc update-ref refs/remotes/origin/main "$SHA_B"   # r3: ⓘ 가 옮긴 origin main 을 B 로(임시 bare 리포)
  for _r in rsbase rsside; do gitc update-ref -d "refs/heads/$_r" 2>/dev/null; done; git -C "$ORIGIN" update-ref -d refs/heads/landed 2>/dev/null; rm -rf "$NW/.serena"   # r4: ⓘ 재실행(변이) 때 landed 비-ff 거절 방지
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$IDX" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -f "$CHERRY_LOG"; rm -rf "$T/wtclean"; rm -rf "$T/tmp"/*
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT="${FEAT:-main}" \
  FT_CHERRY_OVERRIDE_LEDGER="$CHERRY_LOG" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$CLOSE_BIN" "$SEAT" "$@"; }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
}
usage2() { local name="$1"; shift; setup; out="$(close --result "$T/result.md" --recv 1 "$@")"; rc=$?
  [ "$rc" -eq 2 ] && ok "$name → usage rc=2" || bad "$name — rc=$rc ← ${out:0:300}"; untouched "$name"; }

# ⓐ·ⓑ·ⓒ 는 «카드 origin/main» 과 떼어 보려고 origin/main 에 없는 카드 경로(로컬 진행/ 사본)를 쓴다
RS_IDX='design/planner/indices/진행/rs-local.md'
rs_setup() { setup; local_card "$RS_IDX" "${1:-}"; printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$RS_IDX" > "$REPO/.fable-team/seats-planner.json"; }
section_a() {
  echo "== ⓐ --research: 증거 줄 없음 · cherry +0 · 미커밋 0 · --result 실재 → CLOSED rc0"
  rs_setup; out="$(close --result "$T/result.md" --recv 1)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "증거 줄 없음" "ⓐ 인자 없음 = 지금 판 ⑥증거 줄 없음 REJECT" || bad "ⓐ 기준 rc=$rc ← ${out:0:400}"
  rs_setup; out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT research=1" "ⓐ --research → rc0 · CLOSED-ABSENT <좌석> research=1" || bad "ⓐ --research rc=$rc ← ${out:0:600}"
  has "$out" "RESEARCH-OK" "  └ ⑥ 자리 = 리서치 검사 통과 줄"
  hasnt "$out" "증거 줄 없음" "  └ ⑥ 증거 줄 검사 면제"
  has "$(cat "$LEDGER")" "research=1" "  └ 닫힘 원장 행에 research=1"
  git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 보존" || bad "  └ 브랜치 삭제됨"
}
section_a

echo "== ⓑ --research 인데 코드 커밋(cherry +1) · 미커밋 → REJECT «리서치 아님» (면제 0)"
rs_setup; mkdir -p "$NW/scripts"; echo 'print(1)' > "$NW/scripts/x.py"; git -C "$NW" add -A; git -C "$NW" commit -q -m "코드"
out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓑ cherry +1 → REJECT «리서치 아님»" || bad "ⓑ cherry rc=$rc ← ${out:0:500}"
has "$out" "구현 닫기 경로" "  └ 다음 수 = 구현 닫기 경로"
untouched "ⓑ cherry"
rs_setup; mkdir -p "$NW/scripts"; echo 'print(2)' > "$NW/scripts/y.py"
out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓑ 미커밋 코드 → REJECT «리서치 아님»" || bad "ⓑ 미커밋 rc=$rc ← ${out:0:500}"
untouched "ⓑ 미커밋"

echo "== ⓒ --research 인데 --result 없음 → REJECT ①"
rs_setup; out="$(close --result "$T/none.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "①결과 경로 없음" "ⓒ --result 없음 → ① REJECT" || bad "ⓒ rc=$rc ← ${out:0:400}"
untouched "ⓒ"

section_g() {
  echo "== ⓖ(r2) FT_NANO_FEAT=좌석 브랜치 + 구현 커밋 1 + --research → REJECT (r3 기준 = 카드 기준 판 뒤 구현 커밋)"
  rs_setup; mkdir -p "$NW/scripts"; echo 'print(3)' > "$NW/scripts/z.py"; git -C "$NW" add scripts/z.py; git -C "$NW" commit -q -m "구현"
  out="$(FEAT="$BR" close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "구현 커밋 1" "ⓖ 좌석 브랜치 기준 + 커밋 1 → REJECT «구현 커밋 1»(r3: 기준 판 뒤 · 단언 문구만 갱신)" || bad "ⓖ rc=$rc ← ${out:0:600}"
  has "$out" "기준 브랜치가 좌석 자신" "  └ 사유에 «기준 브랜치가 좌석 자신»"
  untouched "ⓖ"
}
section_g

echo "== ⓗ(r2) 0바이트 --result + --research → REJECT ①"
rs_setup; : > "$T/empty.md"; out="$(close --result "$T/empty.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "①결과 파일이 비어 있음" "ⓗ 빈 결과 파일 → ① REJECT" || bad "ⓗ rc=$rc ← ${out:0:400}"
untouched "ⓗ"

echo "== ⓤ 다른 ⑥ 면제·우회 인자와 동시 → usage 2"
usage2 "ⓤ --research + --suspended" --research --suspended "정지"
usage2 "ⓤ --research + --superseded-by" --research --superseded-by design/planner/indices/진행/other.md
usage2 "ⓤ --research + --never-started" --research --never-started "산출 0"
usage2 "ⓤ --research + --shared-wt" --research --shared-wt
usage2 "ⓤ --research + --cherry-override" --research --cherry-override "사람 사유"

section_i() {
  echo "== ⓘ(r3) 기준 판(reflog A) 뒤 구현 커밋 1 · 이미 origin/main 에 착지(HEAD ⊂ origin/main) → REJECT"
  rs_setup; mkdir -p "$NW/scripts"; echo 'print(4)' > "$NW/scripts/l.py"; git -C "$NW" add scripts/l.py; git -C "$NW" commit -q -m "구현(착지)"
  git -C "$NW" push -q origin "HEAD:refs/heads/landed"; git -C "$ORIGIN" update-ref refs/heads/main "$(git -C "$NW" rev-parse HEAD)"; gitc update-ref refs/remotes/origin/main "$(git -C "$NW" rev-parse HEAD)"   # r4: 기준 판 = reflog(A) — 착지 = origin main 을 그 커밋으로(임시 bare)
  out="$(FEAT=origin/main close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "구현 커밋 1" "ⓘ 착지한 구현 좌석 → REJECT «구현 커밋 1»" || bad "ⓘ rc=$rc ← ${out:0:600}"
  hasnt "$out" "RESEARCH-OK" "  └ RESEARCH-OK 0"
  untouched "ⓘ"
}
section_i

section_j() {
  echo "== ⓙ(r3)=ⓥ(r4) 기준 판 A 뒤 머리 맞춤 병합(origin/main 끌어옴)만 · 커밋 0 → RESEARCH-OK"
  rs_setup; git -C "$NW" merge -q --no-ff -m "머리 맞춤" origin/main
  out="$(FEAT=origin/main close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓙ 머리 맞춤 병합만 → rc0 RESEARCH-OK" || bad "ⓙ rc=$rc ← ${out:0:600}"
  echo "== ⓙ(r3) 곁가지(구현 커밋 · origin/main 밖) 병합 → REJECT «곁가지 병합 1»"
  rs_setup; gitc branch -q rsside "$SHA_A"; git -C "$NW" checkout -q rsside; mkdir -p "$NW/scripts"; echo 'print(5)' > "$NW/scripts/s.py"; git -C "$NW" add scripts/s.py; git -C "$NW" commit -q -m "곁가지 구현"
  git -C "$NW" checkout -q "$BR"; git -C "$NW" merge -q --no-ff -m "곁가지 병합" rsside
  out="$(FEAT=origin/main close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "곁가지 병합 1" "ⓙ 곁가지 구현 병합 → REJECT «곁가지 병합 1»" || bad "ⓙ 곁가지 rc=$rc ← ${out:0:600}"
  untouched "ⓙ 곁가지"
}
section_j

echo "== ⓚ(r3→r4) base_sha 줄 없는 카드 + --research → 판정 무영향(r4: 기준 판 = reflog · 카드 줄 안 읽음 → 단언 갱신)"
rs_setup none; out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK 기준 판 ${SHA_A:0:9}(reflog)" "ⓚ 카드 base_sha 없음 → reflog 기준 RESEARCH-OK" || bad "ⓚ rc=$rc ← ${out:0:500}"

section_s() {
  echo "== ⓢ(r4) 좌석이 카드 «- 리서치: <좌석> base=» 를 HEAD 로 고침 + 구현 커밋 1 → REJECT"
  rs_setup; mkdir -p "$NW/scripts"; echo 'print(7)' > "$NW/scripts/h.py"; git -C "$NW" add scripts/h.py; git -C "$NW" commit -q -m "구현 숨김"
  _hd="$(git -C "$NW" rev-parse HEAD)"; printf '# 인덱스: rs\n## 상태\n- base_sha: %s\n- 리서치: %s base=%s 허용=docs/*\n' "$_hd" "$SEAT" "$_hd" > "$REPO/$RS_IDX"
  out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "구현 커밋 1" "ⓢ 카드 줄 HEAD 로 고쳐도 reflog 기준 → REJECT «구현 커밋 1»" || bad "ⓢ rc=$rc ← ${out:0:600}"
  untouched "ⓢ"
}
section_s

echo "== ⓣ(r4) 카드 리서치 줄 중복·앞에 추가(엉뚱한 base) · 커밋 0 → 판정 무영향(RESEARCH-OK · 기준 = reflog A)"
rs_setup; printf '# 인덱스: rs\n## 상태\n- 리서치: %s base=%s 허용=docs/*\n- 리서치: %s base=%s 허용=*\n- base_sha: %s\n' "$SEAT" "$SHA_B" "$SEAT" "$SHA_B" "$SHA_B" > "$REPO/$RS_IDX"
out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "기준 판 ${SHA_A:0:9}(reflog)" "ⓣ 카드 줄 중복·앞 추가 → 무영향(reflog A)" || bad "ⓣ rc=$rc ← ${out:0:600}"

echo "== ⓤ(r4) 좌석 브랜치 reflog 없음(대역: reflog 비움) → REJECT «리서치 기준 판 없음(reflog)»"
RLF="$REPO/.git/logs/refs/heads/$BR"; rs_setup; cp "$RLF" "$T/reflog.bak"; : > "$RLF"
out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 기준 판 없음(reflog)" "ⓤ reflog 없음 → REJECT" || bad "ⓤ rc=$rc ← ${out:0:500}"
untouched "ⓤ"
echo "== ⓤ(r4) reflog 맨 처음 줄이 «branch: Created from» 아님 → REJECT"
sed -n '2,$p' "$T/reflog.bak" > "$RLF"
out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 기준 판 없음(reflog)" "ⓤ 첫 줄 Created from 아님 → REJECT" || bad "ⓤ 첫 줄 rc=$rc ← ${out:0:500}"
cp "$T/reflog.bak" "$RLF"

section_l() {
  echo "== ⓛ(r3) «R scripts/x.py -> .serena/project.yml» · « M docs/.serena/project.yml» → 미커밋 REJECT(정확 경로 · r4: 추적 파일은 열린 판 A 에)"
  rs_setup; mkdir -p "$NW/.serena"; git -C "$NW" mv scripts/x.py .serena/project.yml
  out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "미커밋 2건" "ⓛ R → .serena/project.yml → 미커밋 2건 REJECT(이름 변경 = 원경로+새경로 둘 다 센다 · r978 r2)" || bad "ⓛ R rc=$rc ← ${out:0:600}"
  untouched "ⓛ R"
  git -C "$NW" reset -q --hard "$SHA_A"; rm -rf "$NW/.serena"; echo 'a: 2' > "$NW/docs/.serena/project.yml"
  out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "미커밋 1건" "ⓛ « M docs/.serena/project.yml» → 미커밋 1건 REJECT" || bad "ⓛ M rc=$rc ← ${out:0:600}"
  untouched "ⓛ M"
}
section_l

section_m() {
  echo "== ⓜ(r3) 루트 미추적 .serena/project.yml 만 → RESEARCH-OK"
  rs_setup; mkdir -p "$NW/.serena"; echo 'p: 1' > "$NW/.serena/project.yml"
  out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓜ 루트 .serena/project.yml 미추적만 → rc0" || bad "ⓜ rc=$rc ← ${out:0:600}"
}
section_m

section_d() {
  echo "== ⓓ 로컬 루트 = 대기/ 옛 판 · origin/main = 진행/ 새 판 → r842: 단계(진행/) 디스크 사본 없음 REJECT(낡은 대기/ 로 쓰지 않는다)"
  setup; out="$(close --result "$T/result.md" --recv 1)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "디스크 사본 없음" "ⓓ r842 — 옛 단계 사본뿐 → REJECT «디스크 사본 없음»" || bad "ⓓ rc=$rc ← ${out:0:600}"
  hasnt "$out" "CLOSED" "  └ 닫힘 0(낡은 사본으로 안 감)"
  [ -f "$REPO/$OLD_REL" ] && ok "  └ 대기/ 옛 사본은 그대로(쓰기 0)" || bad "  └ 대기/ 사본 사라짐"
}
section_d

section_d2() {
  echo "== ⓓ2 로컬 루트에 진행/ 사본도 있음 → origin/main 판을 읽고 쓰기는 그 진행/ 사본(r888 판독 보존)"
  setup; mkdir -p "$REPO/design/planner/indices/진행"; cp "$REPO/$OLD_REL" "$REPO/$IDX"; printf '%s\n' "$(cat "$REPO/$OLD_REL")" > "$REPO/$IDX"
  out="$(close --result "$T/result.md" --recv 1)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT" "ⓓ2 증거 줄(origin/main 판에만 있음) → rc0" || bad "ⓓ2 rc=$rc ← ${out:0:600}"
  has "$out" "카드 위치 ← origin/main:$IDX" "  └ INFO 카드 위치 ← origin/main:<경로>"
  has "$(cat "$REPO/$IDX")" "- 리서치 닫힘: $SEAT" "  └ 리서치 줄(origin/main 판)을 읽고 · 쓰기는 작업 트리 진행/ 사본"
  [ -z "$(ls -A "$T/tmp")" ] && ok "  └ 꺼낸 임시 카드 파일 정리(TMPDIR 비어 있음)" || bad "  └ 임시 파일 남음: $(ls -A "$T/tmp")"
}
section_d2

echo "== ⓓ origin/main 에 카드 없음 → 기존 후보 순서 그대로"
rs_setup; out="$(close --result "$T/result.md" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && hasnt "$out" "origin/main:" "ⓓ origin/main 에 없는 카드 → 작업 트리 후보(origin/main 표기 0)" || bad "ⓓ 없음 rc=$rc ← ${out:0:400}"

echo "== ⓓ origin fetch 실패 → 옛 origin/main ref 를 최신으로 믿지 않는다(기존 순서 · 증거 줄 없음 REJECT)"
setup; mkdir -p "$REPO/design/planner/indices/진행"; cp "$REPO/$OLD_REL" "$REPO/$IDX"; git -C "$REPO" remote set-url origin "$T/no-such.git"   # r842: 단계(진행/) 디스크 사본을 둬 ⑥ 증거 줄 자리까지 간다
out="$(close --result "$T/result.md" --recv 1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "fetch 실패" "ⓓ fetch 실패 → WARN 1줄 + origin/main 판 안 읽음" || bad "ⓓ fetch 실패 rc=$rc ← ${out:0:500}"
hasnt "$out" "카드 위치 ← origin/main:" "  └ 옛 ref 카드 사용 0"
has "$out" "증거 줄 없음" "  └ 작업 트리 옛 사본으로 판정(REJECT)"
git -C "$REPO" remote set-url origin "$ORIGIN"

echo "== ⓕ 변이 — 면제 제거 → ⓐ FAIL · origin/main 후보 제거 → ⓓ FAIL"
mutate() {  # mutate <표지> <바꿀 글> — 표지 줄을 바꾼 사본으로 섹션을 돌려 FAIL 이 나는지
  local mark="$1" repl="$2"
  python3 - "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close.mut.sh" "$mark" "$repl" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}
mutate "# r888-mut:research" 'elif false; then'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_a)"
case "$sub" in *FAIL*) ok "ⓕ 면제 제거 → ⓐ FAIL";; *) bad "ⓕ 면제 제거해도 ⓐ 통과(시험이 면제를 못 잡음)";; esac
mutate "# r888-mut:cardref" ':'
sub="$(section_d2)"   # r842: ⓓ 는 이제 단계 판정에서 먼저 막는다 — 판독 경로는 ⓓ2 가 잰다
case "$sub" in *FAIL*) ok "ⓕ origin/main 후보 제거 → ⓓ2 FAIL";; *) bad "ⓕ origin/main 후보 제거해도 ⓓ2 통과";; esac
mutate "# r888-mut:uniq" '    _rs_n=0; _rs_nrc=0'
sub="$(section_g)"
case "$sub" in *FAIL*) ok "ⓕ 고유 커밋 검사 제거 → ⓖ FAIL";; *) bad "ⓕ 고유 커밋 검사 제거해도 ⓖ 통과";; esac
mutate "# r888-mut:uniq" '      _rs_n="$(git -C "$SEAT_WT" rev-list --count --no-merges origin/main..HEAD 2>&1)"; _rs_nrc=$?'
sub="$(section_i)"
case "$sub" in *FAIL*) ok "ⓕ(r3) 기준 = origin/main 으로 되돌림 → ⓘ FAIL";; *) bad "ⓕ(r3) origin/main 기준이어도 ⓘ 통과";; esac
mutate "# r888-mut:exact" '        case "$_e" in *.serena/project.yml) ;; *) _rs_dirty=$((_rs_dirty+1));; esac'
sub="$(section_l)"
case "$sub" in *FAIL*) ok "ⓕ(r3) 정확 경로 → 접미사 → ⓛ FAIL";; *) bad "ⓕ(r3) 접미사 비교여도 ⓛ 통과";; esac
mutate "# r888-mut:side" '        :'
sub="$(section_j)"
case "$sub" in *FAIL*) ok "ⓕ(r3) 곁가지 대조 제거 → ⓙ FAIL";; *) bad "ⓕ(r3) 곁가지 대조 없어도 ⓙ 통과";; esac
mutate "# r888-mut:base" '    _rs_base="$(grep -F -- "- 리서치: $SEAT base=" "${CARD_READ:-$CARD}" | head -1 | sed -nE "s/.* base=([0-9a-f]{40}).*/\1/p")"'
sub="$(section_s)"
case "$sub" in *FAIL*) ok "ⓕ(r4) 기준을 카드 줄로 되돌림 → ⓢ FAIL";; *) bad "ⓕ(r4) 카드 줄 기준이어도 ⓢ 통과";; esac
CLOSE_BIN="$T/bin/ft-nano-close.sh"

echo "== ⓖ 600/300 s · 외부 호출 · GIT_* env 0 (r888 줄)"
NEWL="$(grep 'r888\|RESEARCH\|CARD_READ\|_card_ref' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"
hasnt "$NEWL" "GIT_WORK_TREE=" "ⓖ GIT_WORK_TREE env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
