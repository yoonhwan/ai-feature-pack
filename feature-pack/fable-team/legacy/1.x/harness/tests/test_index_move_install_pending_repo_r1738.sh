#!/usr/bin/env bash
# test_index_move_install_pending_repo_r1738.sh — r1738: 설치 게이트의 install-pending 대기 파일 지우기는 «착지 리포» 에서 센다.
#   실사건(arch-pi#313 · 2026-11-12): ft-index-move-install.sh:59 가 대기 파일 sha 목록을 `$WT`(카드 리포)에서 rev-list 했다.
#   팩 착지 카드는 그 sha 가 카드 리포에 없어 셈 = 0 → 대기 파일이 남고, 실패도 말하지 않았다(하드 룰 20).
#   임시 리포 2개(카드 꼴 · 팩 꼴) + 가짜 대조기 + 임시 대기 폴더. 실 리포·실 라이브·실 state 쓰기 0 · sleep 0.
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; mkdir -p "$HOME/Library/LaunchAgents"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_ROOT
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 도구 사본 1벌(게이트 + 라이브러리) · 변이 사본은 이 사본에서만 만든다(원본 무변경)
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC/ft-index-move-install.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_plist_env.py" "$SRC/ft_git_capped.py" \
  "$SRC/ft-harness-root.sh" "$SRC/ft-live-install-check.sh" "$SRC/ft_live_install_check.py" "$BIN/"
GATE="$BIN/ft-index-move-install.sh"
mutate() { local d="$1" mode="$2"; mkdir -p "$d"; cp -p "$BIN"/*.sh "$BIN"/*.py "$d/"
  python3 - "$d/ft-index-move-install.sh" "$mode" <<'PY'
import sys
p, mode = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
if mode == "M1":
    if '"$LRREPO" rev-list' not in s: raise SystemExit("M1 target missing")
    s = s.replace('"$LRREPO" rev-list', '"$WT" rev-list', 1)
elif mode == "M2":
    old = "  printf 'INFO 대기 파일 지우기 판정 불가 — %s rev-list %s rc=%s\\n' \"$LRREPO\" \"$RANGE\" \"$prc\"\n"
    if old not in s: raise SystemExit("M2 target missing")
    s = s.replace(old, "    :\n", 1)
else:
    raise SystemExit("unknown mutant " + mode)
open(p, "w", encoding="utf-8").write(s)
PY
}

# ── 카드 리포(design/TEAMS.md 있음) · 팩 리포(feature-pack/fable-team/harness/kit/…) — 서로 다른 리포, 객체 공유 0
CR="$T/cardrepo"; mkdir -p "$CR/design/harness/indices/진행"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
CARDC="$CR/design/harness/indices/진행/t.md"
printf '# 인덱스: t\n- 설치: 있음\n- 실사건: 카드 이동 · 증거 mbox #289099\n## 상태\n- x\n' > "$CARDC"
g "$CR" add -A; g "$CR" commit -qm card
printf '# 인덱스: t2\n- 설치: 있음\n- 실사건: 카드 이동 · 증거 mbox #289099\n## 상태\n- y\n' > "$CR/design/harness/indices/진행/t2.md"
g "$CR" add -A; g "$CR" commit -qm card2; CS="$(g "$CR" rev-parse HEAD)"

PR="$T/packrepo"; PRKIT="$PR/feature-pack/fable-team/harness"
mkdir -p "$PRKIT/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$PRKIT/kit/fable-team/bin/x.sh"
printf 'fable-team/bin/*\tbin\t$FT_BIN\tmaster: install.sh --apply\n' > "$PRKIT/kit/LIVE-MAP.tsv"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0; P0="$(g "$PR" rev-parse HEAD)"
printf '#!/bin/bash\necho v2\n' > "$PRKIT/kit/fable-team/bin/x.sh"; g "$PR" add -A; g "$PR" commit -qm p1; P1="$(g "$PR" rev-parse HEAD)"
printf '#!/bin/bash\necho v3\n' > "$PRKIT/kit/fable-team/bin/x.sh"; g "$PR" add -A; g "$PR" commit -qm p2; P2="$(g "$PR" rev-parse HEAD)"
g "$PR" update-ref refs/remotes/origin/main "$P2"
MISS="0123456789abcdef0123456789abcdef01234567"   # 두 리포 어디에도 없는 sha
FAKE="$T/fake-chk.sh"; printf '#!/bin/bash\nexit 0\n' > "$FAKE"; chmod 755 "$FAKE"
export FT_INSTALL_CHECK="$FAKE" FT_INSTALL_RESTART_GATE=0 FT_HARNESS_ROOT="$PRKIT"
run() { local pd="$1" card="$2" range="$3" gate="${4:-$GATE}"; PD="$pd" out="$(FT_INSTALL_PENDING_DIR="$pd" bash "$gate" "$card" --landed "$range" 2>&1)"; rc=$?; }
mkextra() { local pd="$1"; mkdir -p "$pd"; : > "$pd/$MISS.txt"; }   # 범위 밖 파일 = 남아야 한다

# ── ① 팩 착지 sha(팩에만 있음) → 대기 파일 지워짐 · OK 줄 (기준판 = 파일 남음 = Red)
PD1="$T/pd1"; mkextra "$PD1"; : > "$PD1/$P1.txt"; s0=$SECONDS
run "$PD1" "$CARDC" "$P1^..$P1"
t1=$((SECONDS-s0))
{ [ "$rc" = 0 ] && [[ "$out" == *"OK 설치 확인"* ]] && [ ! -e "$PD1/$P1.txt" ]; } && ck "① 팩 착지 대기 파일 지워짐 rc0 (${t1}s)" 0 || ck "① 팩 착지 대기 파일 지워짐 (${t1}s)" 1

# ── ② 카드 리포 착지 sha(카드에만 있음) → 지금과 같게 지워짐
PD2="$T/pd2"; mkextra "$PD2"; : > "$PD2/$CS.txt"; s0=$SECONDS
run "$PD2" "$CARDC" "$CS"
t2=$((SECONDS-s0))
{ [ "$rc" = 0 ] && [ ! -e "$PD2/$CS.txt" ]; } && ck "② 카드 리포 착지 대기 파일 지워짐 rc0 (${t2}s)" 0 || ck "② 카드 리포 착지 …" 1

# ── ③ 팩 착지 범위 2커밋 → 둘 다 지워짐 · 범위 밖 sha 파일은 남음
PD3="$T/pd3"; mkextra "$PD3"; : > "$PD3/$P0.txt"; : > "$PD3/$P1.txt"; : > "$PD3/$P2.txt"; s0=$SECONDS
run "$PD3" "$CARDC" "$P0..$P2"
t3=$((SECONDS-s0))
if [ "$rc" = 0 ] && [ ! -e "$PD3/$P1.txt" ] && [ ! -e "$PD3/$P2.txt" ] && [ -e "$PD3/$P0.txt" ] && [ -e "$PD3/$MISS.txt" ]; then
  ck "③ 범위 2커밋 지움 · 범위 밖 보존 (${t3}s)" 0; else ck "③ 범위 2커밋 지움 · 범위 밖 보존 (${t3}s)" 1; fi

# ── ④ 착지 리포 rev-list 실패(없는 시작 sha) → INFO 판정 불가 1줄 · 대기 파일 손 0 · rc0 · OK 줄 그대로
PD4="$T/pd4"; mkextra "$PD4"; : > "$PD4/$P1.txt"; s0=$SECONDS
run "$PD4" "$CARDC" "$MISS..$P1"
t4=$((SECONDS-s0))
if [ "$rc" = 0 ] && [ -e "$PD4/$P1.txt" ] && [[ "$out" == *"OK 설치 확인"* ]] \
   && printf '%s\n' "$out" | grep -qE "^INFO 대기 파일 지우기 판정 불가 — .* rev-list .* rc=[1-9]"; then
  ck "④ rev-list 실패 = 판정 불가 1줄 · 손 0 · rc0 (${t4}s)" 0; else ck "④ rev-list 실패 = 판정 불가 1줄 · 손 0 · rc0 (${t4}s)" 1; fi

# ── ⑤ 두 리포 어디에도 없는 sha → :34 REJECT 그대로 · 대기 파일 손 0
PD5="$T/pd5"; mkextra "$PD5"; : > "$PD5/$MISS.txt"; s0=$SECONDS
run "$PD5" "$CARDC" "$MISS"
t5=$((SECONDS-s0))
{ [ "$rc" = 1 ] && [[ "$out" == *"REJECT 착지 sha 를 어느 리포에서도 못 찾음"* ]] && [ -e "$PD5/$MISS.txt" ]; } \
  && ck "⑤ 두 리포에 없음 = REJECT rc1 · 손 0 (${t5}s)" 0 || ck "⑤ 두 리포에 없음 = REJECT rc1 · 손 0 (${t5}s)" 1

# ── 변이 M1(리포 인자 $WT 되돌림) → ① FAIL · 변이 M2(INFO 줄 삭제) → ④ FAIL · 각각 원본 반대 결과 대조
mutate "$T/mut-M1" M1; mutate "$T/mut-M2" M2
PDM="$T/pdm1"; mkextra "$PDM"; : > "$PDM/$P1.txt"; s0=$SECONDS
run "$PDM" "$CARDC" "$P1^..$P1" "$T/mut-M1/ft-index-move-install.sh"; tm1=$((SECONDS-s0))
{ [ "$rc" = 0 ] && [ -e "$PDM/$P1.txt" ]; } && ck "M1 카드 리포에서 셈 = 대기 파일 남음(반례 ① 적중 · ${tm1}s)" 0 || ck "M1 카드 리포에서 셈(반례 ① 적중)" 1
PDO="$T/pdo1"; mkextra "$PDO"; : > "$PDO/$P1.txt"
run "$PDO" "$CARDC" "$P1^..$P1"
{ [ "$rc" = 0 ] && [ ! -e "$PDO/$P1.txt" ]; } && ck "M1 대조: 원본은 같은 사례에서 지운다" 0 || ck "M1 대조: 원본은 같은 사례에서 지운다" 1
PDN="$T/pdm2"; mkextra "$PDN"; : > "$PDN/$P1.txt"; s0=$SECONDS
run "$PDN" "$CARDC" "$MISS..$P1" "$T/mut-M2/ft-index-move-install.sh"; tm2=$((SECONDS-s0))
{ [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'INFO 대기 파일 지우기 판정 불가'; } && ck "M2 INFO 줄 없음(반례 ④ 적중 · ${tm2}s)" 0 || ck "M2 INFO 줄 없음(반례 ④ 적중)" 1
PDQ="$T/pdo2"; mkextra "$PDQ"; : > "$PDQ/$P1.txt"
run "$PDQ" "$CARDC" "$MISS..$P1"
printf '%s\n' "$out" | grep -q 'INFO 대기 파일 지우기 판정 불가' && ck "M2 대조: 원본은 같은 사례에서 INFO 1줄" 0 || ck "M2 대조: 원본은 같은 사례에서 INFO 1줄" 1

# ── 오염 0
if [ "$(g "$CR" config --get core.bare)" != true ] && [ -f "$CARDC" ] && [ -d "$PRKIT" ]; then ck "오염 0 · 두 리포 무변경" 0; else ck "오염 0 · 두 리포 무변경" 1; fi
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
