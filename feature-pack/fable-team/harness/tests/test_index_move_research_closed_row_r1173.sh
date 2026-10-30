#!/usr/bin/env bash
# test_index_move_research_closed_row_r1173.sh — ft-index-move 진행→완성 리서치 게이트: ft-seat-close 로 닫은 명부 행
#   (role=stop-ready ∧ _closed dict)은 «명부 행 남음» 이 아니다 · 세션·프로세스 검사 그대로 · 거절 줄이 ft-seat-close 를 안내(r1173).
#   임시 HOME·임시 git 리포 + 가짜 tmux·pgrep(PATH 앞) 픽스처만 — 실 명부·실 tmux·프로세스 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
fail=0; t0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-index-move.sh "../kit/fable-team/bin/ft-index-move.sh"; do bash -n "$SRCDIR/$f" && ok "bash -n $f" || bad "bash -n $f"; done
cmp -s "$SRCDIR/ft-index-move.sh" "$SRCDIR/../kit/fable-team/bin/ft-index-move.sh" && ok "bin·kit 같은 내용 cmp0" || bad "bin·kit 다름"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAKE="$T/fake"; mkdir -p "$FAKE"
# 가짜 tmux: has-session -t =<이름> → $T/sessions 에 그 이름이 있으면 0 · 가짜 pgrep: $T/procs 에 그 이름이 있으면 pid 출력 rc0
printf '#!/usr/bin/env bash\n[ "$1" = has-session ] || exit 1\ngrep -qxF -- "${3#=}" "%s/sessions" 2>/dev/null\n' "$T" > "$FAKE/tmux"
printf '#!/usr/bin/env bash\ngrep -qxF -- "${@: -1}" "%s/procs" 2>/dev/null && { echo 4242; exit 0; }\nexit 1\n' "$T" > "$FAKE/pgrep"
chmod +x "$FAKE/tmux" "$FAKE/pgrep"; : > "$T/sessions"; : > "$T/procs"
export PATH="$FAKE:$PATH" HOME="$T/home" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json" FT_MBOX=/bin/true FT_LAND_REF=HEAD
mkdir -p "$HOME/.claude" "$T/state"

# mkbin <폴더> [기준판] — 시험 대상 bin 사본(기준판 = r1173 직전 팩 origin/main 고정 sha 의 ft-index-move.sh)
BASE_SHA=dd8345f84934bb86b796af5f72c872d7c341ede3
mkbin() {
  mkdir -p "$1"
  cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$SRCDIR/ft-evidence-inject-scan.sh" "$SRCDIR/ft-team-lib.sh" "$1/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/ft-index-lint.sh"
  [ "${2:-}" != base ] || git -C "$SRCDIR" show "$BASE_SHA:./ft-index-move.sh" > "$1/ft-index-move.sh" 2>/dev/null
}
BIN="$T/bin"; mkbin "$BIN"; BASE="$T/base"; HAVE_BASE=1
mkbin "$BASE" base || { HAVE_BASE=0; echo "SKIP 기준판 칸(기준판 R1) — base_sha $BASE_SHA 객체 없음(git 사본 아님)"; }

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/.fable-team"
NAMES="r1 r2 r3 r4 r5 b1 m1"
printf '# 판정문\n## §1 닫힘: 카드 이름 %s\n' "$NAMES" > "$REPO/design/harness/DA-x.md"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$REPO/design/TEAMS.md"
echo '{"_version": "t", "byz-other-nano-x#0": {"role": "nano"}}' > "$REPO/.fable-team/seats.json"
echo '{"_name": "lecture"}' > "$REPO/.fable-team/seats-lecture.json"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
DA="$REPO/design/harness/DA-x.md#§1"

# card <이름> <좌석> — 닫힘 줄 없는 리서치 카드
card() {
  local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "- 리서치: $2 base=abc 허용=design/x"
    echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"
  echo "$f"
}
mv_() { bash "$1/ft-index-move.sh" "$2" 완성 --da "$DA" --seat s 2>&1; }
moved() { [ -f "$IDX/완성/$1.md" ] && echo "$2" | grep -q '^MOVED'; }
held()  { [ -f "$IDX/진행/$1.md" ] && echo "$2" | grep -q "^REJECT 리서치 좌석 열림.*$3"; }
S=byz-lecture-nano-l89-on-seal-keeps-live-rows-research#0
ROW_CLOSED="{\"_name\": \"lecture\", \"$S\": {\"role\": \"stop-ready\", \"agent\": \"pi\", \"worktree\": null, \"_closed\": {\"by\": \"byz-lecture-master-claude#31\", \"at\": \"2026-10-30T15:02:33\", \"verdict\": 2844}}}"
ROW_OPEN="{\"_name\": \"lecture\", \"$S\": {\"role\": \"nano\"}}"
seats() { echo "$1" > "$REPO/.fable-team/seats-lecture.json"; }

# R1 L89 꼴 — 세션 0 · 명부 _closed 표기 · 프로세스 0 → INFO(_closed 표기) + 이동
seats "$ROW_CLOSED"; out="$(mv_ "$BIN" "$(card r1 "$S")")"
moved r1 "$out" && echo "$out" | grep -qF "INFO 리서치 좌석 잔재 0 — $S(세션 0 · 명부 _closed 표기 · 프로세스 0)" && ok "ⓐ R1 _closed 표기 → INFO · 이동" || bad "ⓐ R1: $out"
# 기준판 대조 — 지금 판은 같은 꼴을 «명부 행 남음» 으로 REJECT
if [ "$HAVE_BASE" = 1 ]; then out="$(mv_ "$BASE" "$(card b1 "$S")")"
  held b1 "$out" "명부 행 남음 seats-lecture.json" && ok "기준판 R1 = REJECT 명부 행 남음(지금 값)" || bad "기준판 R1: $out"; fi
# R2 표기 없는 행(role=nano) → REJECT 명부 행 남음 · R5 거절 줄에 ft-seat-close 안내
seats "$ROW_OPEN"; out="$(mv_ "$BIN" "$(card r2 "$S")")"
held r2 "$out" "명부 행 남음 seats-lecture.json" && ok "ⓑ R2 표기 없는 행 → REJECT 명부 행 남음" || bad "ⓑ R2: $out"
echo "$out" | grep '^REJECT 리서치 좌석 열림' | grep -qF "ft-seat-close $S --reason" && ok "ⓔ R5 거절 줄에 ft-seat-close 안내" || bad "ⓔ R5: $out"
# R3 _closed 표기 · 프로세스 있음 → REJECT 프로세스 남음
seats "$ROW_CLOSED"; echo "$S" > "$T/procs"; out="$(mv_ "$BIN" "$(card r3 "$S")")"; : > "$T/procs"
held r3 "$out" "프로세스 남음" && ok "ⓒ R3 _closed · 프로세스 남음 → REJECT" || bad "ⓒ R3: $out"
# R4 _closed 표기 · 세션 있음 → REJECT 세션 남음
echo "$S" > "$T/sessions"; out="$(mv_ "$BIN" "$(card r4 "$S")")"; : > "$T/sessions"
held r4 "$out" "세션 남음" && ok "ⓓ R4 _closed · 세션 남음 → REJECT" || bad "ⓓ R4: $out"
# 변이 1 — _closed 조건 삭제(행이 있으면 항상 남음) → R1 이 REJECT 되면 시험이 잡는다
M1="$T/m1"; mkbin "$M1"; sed -i.bak 's/v.get("role") == "stop-ready": closed = True; continue/v.get("role") == "never": closed = True; continue/' "$M1/ft-index-move.sh"
cmp -s "$M1/ft-index-move.sh" "$BIN/ft-index-move.sh" && bad "변이1 적용 0(sed 불일치)"
out="$(mv_ "$M1" "$(card m1 "$S")")"
if moved m1 "$out"; then bad "변이1(_closed 조건 삭제) 살아남음: $out"; else ok "변이1(_closed 조건 삭제) → R1 판정 FAIL(잡힘)"; fi
seats '{"_name": "lecture"}'

echo "초: 전체 $((SECONDS-t0))"
echo "fail=$fail"; [ "$fail" = 0 ]
