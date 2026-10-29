#!/usr/bin/env bash
# test_index_move_research_gone_r1125.sh — ft-index-move 진행→완성 R387 리서치 게이트: «리서치 닫힘» 줄이 없어도
#   좌석이 «세션 0 ∧ 명부 행 0(모든 seats*.json) ∧ 프로세스 0» 이면 INFO 1줄로 통과 · 하나라도 남거나 못 재면 REJECT(r1125).
#   임시 HOME·임시 git 리포 + 가짜 tmux·pgrep(PATH 앞) 픽스처만 — 실 tmux·프로세스·indices 쓰기 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
fail=0; t0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-index-move.sh "../kit/fable-team/bin/ft-index-move.sh"; do bash -n "$SRCDIR/$f" && ok "bash -n $f" || bad "bash -n $f"; done
cmp -s "$SRCDIR/ft-index-move.sh" "$SRCDIR/../kit/fable-team/bin/ft-index-move.sh" && ok "ⓔ bin·kit 같은 내용 cmp0" || bad "ⓔ bin·kit 다름"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAKE="$T/fake"; mkdir -p "$FAKE"
# 가짜 tmux: has-session -t =<이름> → $T/sessions 에 그 이름이 있으면 0 · 가짜 pgrep: $T/procs 에 그 이름이 있으면 pid 출력 rc0
printf '#!/usr/bin/env bash\n[ "$1" = has-session ] || exit 1\ngrep -qxF -- "${3#=}" "%s/sessions" 2>/dev/null\n' "$T" > "$FAKE/tmux"
printf '#!/usr/bin/env bash\ngrep -qxF -- "${@: -1}" "%s/procs" 2>/dev/null && { echo 4242; exit 0; }\nexit 1\n' "$T" > "$FAKE/pgrep"
chmod +x "$FAKE/tmux" "$FAKE/pgrep"; : > "$T/sessions"; : > "$T/procs"
export PATH="$FAKE:$PATH" HOME="$T/home" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json" FT_MBOX=/bin/true FT_LAND_REF=HEAD
mkdir -p "$HOME/.claude" "$T/state"

# mkbin <폴더> [기준판] — 시험 대상 bin 사본(기준판 = 팩 HEAD 의 ft-index-move.sh)
mkbin() {
  mkdir -p "$1"
  cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$SRCDIR/ft-evidence-inject-scan.sh" "$SRCDIR/ft-team-lib.sh" "$1/"
  [ "${2:-}" != base ] || git -C "$SRCDIR" show HEAD:./ft-index-move.sh > "$1/ft-index-move.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/ft-index-lint.sh"
}
BIN="$T/bin"; mkbin "$BIN"; BASE="$T/base"; mkbin "$BASE" base

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/.fable-team"
NAMES="r1 r2 r3 r4 r5 r6 b1 b5 m1 m2"
printf '# 판정문\n## §1 닫힘: 카드 이름 %s\n' "$NAMES" > "$REPO/design/harness/DA-x.md"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$REPO/design/TEAMS.md"
echo '{"_version": "t", "byz-other-nano-x#0": {"role": "nano"}}' > "$REPO/.fable-team/seats.json"
echo '{"_name": "lecture"}' > "$REPO/.fable-team/seats-lecture.json"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
DA="$REPO/design/harness/DA-x.md#§1"

# card <이름> <좌석> [닫힘 줄]
card() {
  local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "- 리서치: $2 base=abc 허용=design/x"; [ -z "${3:-}" ] || echo "$3"
    echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"
  echo "$f"
}
mv_() { bash "$1/ft-index-move.sh" "$2" 완성 --da "$DA" --seat s 2>&1; }
moved() { [ -f "$IDX/완성/$1.md" ] && echo "$2" | grep -q '^MOVED'; }
held()  { [ -f "$IDX/진행/$1.md" ] && echo "$2" | grep -q "^REJECT 리서치 좌석 열림.*$3"; }
S=byz-lecture-nano-l74-x-research#0

# R1 L74 꼴 — 닫힘 줄 없음 · 세션 0 · 명부 행 0 · 프로세스 0 → INFO + 이동
out="$(mv_ "$BIN" "$(card r1 "$S")")"
moved r1 "$out" && echo "$out" | grep -qF "INFO 리서치 좌석 잔재 0 — $S(세션 0 · 명부 행 0 · 프로세스 0)" && ok "ⓐ R1 잔재 0 → INFO · 이동" || bad "ⓐ R1: $out"
# 기준판 대조 — 지금(HEAD) 판은 같은 꼴을 REJECT
out="$(mv_ "$BASE" "$(card b1 "$S")")"
held b1 "$out" "줄 없음" && ok "기준판 R1 = REJECT(지금 값)" || bad "기준판 R1: $out"
# R2 세션 있음
echo "$S" > "$T/sessions"; out="$(mv_ "$BIN" "$(card r2 "$S")")"; : > "$T/sessions"
held r2 "$out" "세션 남음" && ok "ⓑ R2 세션 남음 → REJECT" || bad "ⓑ R2: $out"
# R3 명부 행 있음(seats-<팀>.json)
echo "{\"_name\": \"lecture\", \"$S\": {\"role\": \"research\"}}" > "$REPO/.fable-team/seats-lecture.json"
out="$(mv_ "$BIN" "$(card r3 "$S")")"
echo '{"_name": "lecture"}' > "$REPO/.fable-team/seats-lecture.json"
held r3 "$out" "명부 행 남음 seats-lecture.json" && ok "ⓑ R3 명부 행 남음 → REJECT" || bad "ⓑ R3: $out"
# R4 프로세스 있음
echo "$S" > "$T/procs"; out="$(mv_ "$BIN" "$(card r4 "$S")")"
held r4 "$out" "프로세스 남음" && ok "ⓑ R4 프로세스 남음 → REJECT" || bad "ⓑ R4: $out"
# 변이 2 — pgrep 검사 생략 → R4 가 통과하면 시험이 잡는다(= FAIL 이어야 함)
M2="$T/m2"; mkbin "$M2"; sed -i.bak 's/_p="$(pgrep -f -- "$1")"; _rc=$?/_p=""; _rc=1/' "$M2/ft-index-move.sh"
cmp -s "$M2/ft-index-move.sh" "$BIN/ft-index-move.sh" && bad "변이2 적용 0(sed 불일치)"
out="$(mv_ "$M2" "$(card m2 "$S")")"; : > "$T/procs"
if held m2 "$out" "프로세스 남음"; then bad "변이2(pgrep 생략) 살아남음: $out"; else ok "변이2(pgrep 생략) → R4 판정 FAIL(잡힘)"; fi
# R5 닫힘 줄 있음 → 출력이 기준판과 같다
L="- 리서치 닫힘: $S 2026-10-29T22:00 left=0"
o5="$(mv_ "$BIN" "$(card r5 "$S" "$L")")"; ob="$(mv_ "$BASE" "$(card b5 "$S" "$L")")"
moved r5 "$o5" && [ "${o5//r5/X}" = "${ob//b5/X}" ] && ok "ⓒ R5 닫힘 줄 길 출력 동일" || bad "ⓒ R5: [$o5] vs [$ob]"
# R6 명부 읽기 실패 → 판정 불가 REJECT
echo '{broken' > "$REPO/.fable-team/seats-lecture.json"; out="$(mv_ "$BIN" "$(card r6 "$S")")"
echo '{"_name": "lecture"}' > "$REPO/.fable-team/seats-lecture.json"
held r6 "$out" "판정 불가 — 명부 읽기 실패 seats-lecture.json" && ok "ⓓ R6 명부 읽기 실패 → 판정 불가 REJECT" || bad "ⓓ R6: $out"
# 변이 1 — 대안 끔(닫힘 줄 없으면 항상 남음) → R1 이 REJECT 되면 시험이 잡는다
M1="$T/m1"; mkbin "$M1"; sed -i.bak 's/_left="$(research_left "$_rseat")"/_left="끔"/' "$M1/ft-index-move.sh"
cmp -s "$M1/ft-index-move.sh" "$BIN/ft-index-move.sh" && bad "변이1 적용 0(sed 불일치)"
out="$(mv_ "$M1" "$(card m1 "$S")")"
if moved m1 "$out"; then bad "변이1(대안 끔) 살아남음: $out"; else ok "변이1(대안 끔) → R1 판정 FAIL(잡힘)"; fi

echo "초: 전체 $((SECONDS-t0))"
echo "fail=$fail"; [ "$fail" = 0 ]
