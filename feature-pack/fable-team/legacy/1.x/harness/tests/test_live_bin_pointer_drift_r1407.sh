#!/usr/bin/env bash
# test_live_bin_pointer_drift_r1407.sh — r1407: 설치 대조(ft-live-install-check)가 루트 명부(roots.tsv)의 루트와 그 .worktrees/*/ 의
# .fable-team/LIVE_BIN 포인터를 읽어, 머신 설치 판(--project 루트 LIVE_BIN 의 판)과 다르면 «DRIFT live-bin <경로> pinned=<판> want=<판>» 1줄.
# 사건: airag 워크트리(rag-transplant) LIVE_BIN 이 1.1.14 에 멈춰 좌석 열기가 모델 상태줄을 못 읽고 닫혔다 — 설치 대조는 워크트리 포인터를 안 봤다.
# D1 워크트리 포인터 옛 판 → DRIFT 1줄 rc1 · D2 워크트리 = 설치 판 → 줄 0 rc0 · D3 워크트리 LIVE_BIN 없음 → 줄 0 rc0
# D4 포인터가 절대경로 폴더 아님 → ERROR rc3 · D5 루트 2개 중 한 루트 포인터만 옛 판 → 그 루트 1줄(기준 = 설치 판 하나)
# 임시 HOME·임시 roots.tsv(FT_ROOTS_TSV)·임시 루트 2개·가짜 live 폴더 3판·임시 git 리포만 — 실 ~/.claude 0 · 포인터 수정 0 확인 · timeout 70.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/.." && pwd -P)"
CHK="$H/bin/ft-live-install-check.sh"; PY="$H/bin/ft_live_install_check.py"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:900}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
hasnt() { [[ "$out" != *"$1"* ]]; }
cnt() { printf '%s\n' "$out" | grep -c "$1"; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; mkdir -p "$HOME/Library/LaunchAgents"
export FT_ROOTS_TSV="$T/roots.tsv"
LV="$T/fable-team/live"; for v in 1.1.14 1.1.255 1.1.262; do mkdir -p "$LV/$v/bin"; done
NEW="$LV/1.1.262/bin"; OLD="$LV/1.1.14/bin"; MID="$LV/1.1.255/bin"

# ── 픽스처: 키트 리포(skip 행 1개 — 다른 점검 줄 0) · 루트 P(설치 기준) · 루트 Q(+ .worktrees/w1) ─────
R="$T/repo"; mkdir -p "$R/kit"; G() { git -C "$R" "$@"; }
G init -q -b main .; G config user.name t; G config user.email t@t
printf '*.txt\tskip\t-\t-\nLIVE-MAP.tsv\tskip\t-\t-\n' > "$R/kit/LIVE-MAP.tsv"; echo a > "$R/kit/a.txt"; G add -A; G commit -qm k0
P="$T/rootP"; Q="$T/rootQ"; W="$Q/.worktrees/w1"
mkdir -p "$P/.fable-team" "$Q/.fable-team" "$W/.fable-team"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0
echo "$NEW" > "$P/.fable-team/LIVE_BIN"; echo "$NEW" > "$Q/.fable-team/LIVE_BIN"
printf '# 이름 경로 상태 기준ref 우편함 접두\np\t%s\t현역\torigin/main\t.\t기본\nq\t%s\t현역\torigin/main\t.\t-\nghost\t%s\t현역\torigin/main\t.\t-\n' "$P" "$Q" "$T/no-such-root" > "$FT_ROOTS_TSV"
chk() { out="$(timeout 70 bash "$CHK" --all --ref main --repo "$R" --kit kit --project "$P" 2>&1)"; rc=$?; }

python3 -m py_compile "$PY" && bash -n "$CHK"; ck "py_compile · bash -n" $?
cmp -s "$PY" "$H/kit/fable-team/bin/ft_live_install_check.py"; ck "bin/kit 짝 cmp0 (ft_live_install_check)" $?

# ── D1: 워크트리 포인터 옛 판 → DRIFT live-bin 1줄 · rc1 · 포인터 수정 0 ─────────────────────
echo "$OLD" > "$W/.fable-team/LIVE_BIN"; before="$(shasum "$W/.fable-team/LIVE_BIN")"
chk
[ "$rc" = 1 ] && has "PENDING n=1" && has "DRIFT live-bin $W/.fable-team/LIVE_BIN pinned=1.1.14 want=1.1.262" && [ "$(cnt 'DRIFT live-bin')" = 1 ]
ck "D1 워크트리 포인터 옛 판 → DRIFT live-bin 1줄 rc1" $?
[ "$before" = "$(shasum "$W/.fable-team/LIVE_BIN")" ] && has "HINT live-bin"; ck "D1 포인터 파일 수정 0 · HINT live-bin(고침은 사람)" $?

# ── D2: 워크트리 포인터 = 설치 판 → 줄 0 · rc0 ─────────────────────────────────────────
echo "$NEW" > "$W/.fable-team/LIVE_BIN"; chk
[ "$rc" = 0 ] && has "OK n=0 skip=2" && hasnt "DRIFT"; ck "D2 워크트리 = 설치 판 → 줄 0 rc0" $?

# ── D3: 워크트리에 LIVE_BIN 없음 → 줄 0(루트를 따른다) ────────────────────────────────────
rm -f "$W/.fable-team/LIVE_BIN"; chk
[ "$rc" = 0 ] && hasnt "DRIFT"; ck "D3 워크트리 LIVE_BIN 없음 → 줄 0 rc0" $?

# ── D4: 포인터가 절대경로 폴더 아님 → ERROR rc3 ───────────────────────────────────────
echo "live/1.1.14/bin" > "$W/.fable-team/LIVE_BIN"; chk
[ "$rc" = 3 ] && has "ERROR LIVE_BIN 이 절대경로 폴더가 아님" && has "$W/.fable-team/LIVE_BIN"; ck "D4 상대경로 포인터 → ERROR rc3" $?
echo "$LV/9.9.9/bin" > "$W/.fable-team/LIVE_BIN"; chk
[ "$rc" = 3 ] && has "ERROR LIVE_BIN 이 절대경로 폴더가 아님"; ck "D4b 없는 폴더 포인터 → ERROR rc3" $?
rm -f "$W/.fable-team/LIVE_BIN"

# ── D5: 루트 2개 · Q 루트 포인터만 다른 판 → Q 1줄(기준 = 설치 판 하나 · 루트 자기 판 아님) ─────
echo "$MID" > "$Q/.fable-team/LIVE_BIN"; chk
[ "$rc" = 1 ] && has "DRIFT live-bin $Q/.fable-team/LIVE_BIN pinned=1.1.255 want=1.1.262" && [ "$(cnt 'DRIFT live-bin')" = 1 ] && hasnt "$P/.fable-team/LIVE_BIN pinned"
ck "D5 한 루트 포인터만 다른 판 → 그 루트 1줄 rc1" $?
echo "$MID" > "$W/.fable-team/LIVE_BIN"; chk
[ "$rc" = 1 ] && [ "$(cnt 'DRIFT live-bin')" = 2 ] && has "DRIFT live-bin $W/.fable-team/LIVE_BIN pinned=1.1.255 want=1.1.262"
ck "D5b 워크트리 = 자기 루트 판(1.1.255)이어도 설치 판과 다르면 DRIFT" $?

# ── 범위 밖·기존 동작: 명부 없음 → 줄 0 ─────────────────────────────────────────────
echo "$OLD" > "$W/.fable-team/LIVE_BIN"; FT_ROOTS_TSV="$T/none.tsv" chk
[ "$rc" = 0 ] && hasnt "DRIFT"; ck "명부 없음 → 이 갈래 줄 0(기존 동작)" $?

grep -q "def live_bin_drift(" "$PY"; ck "판정 1함수(live_bin_drift)" $?
[ "$SECONDS" -le 70 ]; ck "시험 시간 상한(70초 · 실측 ${SECONDS}s)" $?
[ "$fail" = 0 ] && echo "ALL PASS (${SECONDS}s)" || { echo "FAILED $fail"; exit 1; }
