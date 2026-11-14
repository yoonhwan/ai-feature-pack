#!/usr/bin/env bash
# test_index_move_real_event_line_r1422.sh — r1422: 설치 게이트의 «실사건» 증거 검사는 들여쓰지 않은 최상위 «- 실사건:» 줄(여럿이면 마지막)만 본다.
#   실사건(master #265800 · 2026-11-06): ft-index-move-install.sh 가 grep -m1 '^[[:space:]]*-…실사건:' 로 들여쓴 근거 줄을 먼저 잡아
#   r1395 완성 이동이 «증거 토큰 없음» 으로 REJECT 됐다(진짜 닫기 줄은 카드 끝).
#   임시 리포 2개(카드 꼴 · 팩 꼴) + 가짜 대조기. 실 리포·실 라이브·실 state 쓰기 0 · sleep 0.
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

# ── 도구 사본 1벌 · 변이 사본은 이 사본에서만 만든다(원본 무변경)
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC/ft-index-move-install.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_plist_env.py" "$SRC/ft_git_capped.py" \
  "$SRC/ft-harness-root.sh" "$SRC/ft-live-install-check.sh" "$SRC/ft_live_install_check.py" "$BIN/"
GATE="$BIN/ft-index-move-install.sh"
NEW="EV=\"\$(grep -E '^-[[:space:]]*실사건:' \"\$CARD\" | tail -n 1)\""
mutate() { local d="$1" repl="$2"; mkdir -p "$d"; cp -p "$BIN"/*.sh "$BIN"/*.py "$d/"
  python3 - "$d/ft-index-move-install.sh" "$NEW" "$repl" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s: raise SystemExit("mutant target missing")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

# ── 카드 리포(design/TEAMS.md) · 팩 리포(착지 sha) — 카드 꼴 4개
CR="$T/cardrepo"; D="$CR/design/harness/indices/진행"; mkdir -p "$D"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
card() { printf '# 인덱스: %s\n- 설치: 있음\n%b## 상태\n- x\n' "$1" "$2" > "$D/$1.md"; }
card m1 '- 근거:\n  - 실사건: 사고 표 경로 기록\n- 실사건: 다음 이동 · 증거 mbox #1\n'
card m2 '- 실사건: 토큰 없는 앞 줄\n- 실사건: 다음 이동 · 증거 mbox #2\n'
card m3 '- 근거:\n  - 실사건: 들여쓴 줄 · 증거 mbox #3\n'
card m4 '- 실사건: 다음 이동 · 증거 mbox #4\n- 근거:\n  - 실사건: 사고 표 경로 기록\n'
g "$CR" add -A; g "$CR" commit -qm cards

PR="$T/packrepo"; PRKIT="$PR/feature-pack/fable-team/harness"; mkdir -p "$PRKIT/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$PRKIT/kit/fable-team/bin/x.sh"
printf 'fable-team/bin/*\tbin\t$FT_BIN\tmaster: install.sh --apply\n' > "$PRKIT/kit/LIVE-MAP.tsv"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0
printf '#!/bin/bash\necho v2\n' > "$PRKIT/kit/fable-team/bin/x.sh"; g "$PR" add -A; g "$PR" commit -qm p1; P0="$(g "$PR" rev-parse HEAD)"
g "$PR" update-ref refs/remotes/origin/main "$P0"
FAKE="$T/fake-chk.sh"; printf '#!/bin/bash\nexit 0\n' > "$FAKE"; chmod 755 "$FAKE"
export FT_INSTALL_CHECK="$FAKE" FT_INSTALL_RESTART_GATE=0 FT_HARNESS_ROOT="$PRKIT" FT_INSTALL_PENDING_DIR="$T/pd"
run() { local name="$1" gate="${2:-$GATE}"; out="$(timeout 70 bash "$gate" "$D/$name.md" --landed "$P0" 2>&1)"; rc=$?; }
ok() { [ "$rc" = 0 ] && [[ "$out" == *"OK 설치 확인"* ]]; }
nol() { [ "$rc" = 1 ] && [[ "$out" == *"REJECT 카드에 「- 실사건: <무엇> · <증거>」 줄 없음"* ]]; }

# ── M1 들여쓴 근거 줄 뒤 최상위 줄 → 통과 (기준판 = «증거 토큰 없음» REJECT)
s0=$SECONDS; run m1; ok && ck "M1 들여쓴 줄 무시 · 최상위 줄 통과 ($((SECONDS-s0))s)" 0 || ck "M1 들여쓴 줄 무시 · 최상위 줄 통과" 1
# ── M2 최상위 2줄(앞 = 토큰 없음) → 마지막 줄로 통과
s0=$SECONDS; run m2; ok && ck "M2 최상위 여럿 = 마지막 줄 ($((SECONDS-s0))s)" 0 || ck "M2 최상위 여럿 = 마지막 줄" 1
# ── M3 들여쓴 줄만(토큰 있어도) → 지금 «줄 없음» 문구로 REJECT
s0=$SECONDS; run m3; nol && ck "M3 들여쓴 줄만 = 줄 없음 REJECT ($((SECONDS-s0))s)" 0 || ck "M3 들여쓴 줄만 = 줄 없음 REJECT" 1
# ── M4 최상위 줄 뒤 들여쓴 근거 줄 → 통과(마지막 «최상위» 줄)
s0=$SECONDS; run m4; ok && ck "M4 뒤 들여쓴 줄 무시 ($((SECONDS-s0))s)" 0 || ck "M4 뒤 들여쓴 줄 무시" 1

# ── 변이: V1 들여쓰기 허용 → M3·M4 FAIL · V2 첫 줄 고르기 → M2 FAIL
mutate "$T/v1" "EV=\"\$(grep -E '^[[:space:]]*-[[:space:]]*실사건:' \"\$CARD\" | tail -n 1)\""
mutate "$T/v2" "EV=\"\$(grep -m1 -E '^-[[:space:]]*실사건:' \"\$CARD\")\""
run m3 "$T/v1/ft-index-move-install.sh"; nol && ck "V1 들여쓰기 허용 M3 적중" 1 || ck "V1 들여쓰기 허용 → M3 FAIL(적중)" 0
run m4 "$T/v1/ft-index-move-install.sh"; ok && ck "V1 들여쓰기 허용 M4 적중" 1 || ck "V1 들여쓰기 허용 → M4 FAIL(적중)" 0
run m2 "$T/v2/ft-index-move-install.sh"; ok && ck "V2 첫 줄 M2 적중" 1 || ck "V2 첫 줄 → M2 FAIL(적중)" 0

[ -f "$D/m1.md" ] && ck "오염 0 · 카드 무변경" 0 || ck "오염 0" 1
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
