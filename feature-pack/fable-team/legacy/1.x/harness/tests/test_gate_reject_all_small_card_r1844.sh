#!/usr/bin/env bash
# test_gate_reject_all_small_card_r1844.sh — r1844: 완성 관문 게이트는 거절 사유를 모아 «  - <사유>» 줄로 전부 낸다 ·
#   20줄 이하 작은 카드(8절 꼴 아님)는 머리 10키 + 끝 «## 상태» 절 1개만 본다. 임시 리포·사본만 · 실 리포 쓰기 0 · sleep 0.
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; KIT="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"
fail=0; ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc ${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; export HOME="$T/home"; mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_LANDED_MARKER FT_ROOT FT_TEAM FT_GOAL_LINES_FILE
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
BIN="$T/bin"; cp -Rp "$KIT" "$BIN"; rc=0; out=""
mutate() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if old not in s: raise SystemExit("mutant target missing: " + old)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# ── 카드 리포 + 팩 리포(착지 sha) + 가짜 대조기
R="$T/repo"; IDX="$R/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$R/src"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$R/design/TEAMS.md"
echo '원장: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$R/design/LEDGER.md"; echo x > "$R/src/target.sh"
printf '# 판정문\n## §1 닫힘: r1844a\n' > "$R/design/harness/DA-x.md"
printf '# 인덱스: r1844a\n- 설치: 있음\n- 남은 범위: 없음\n## 상태\n- x\n' > "$IDX/진행/r1844a.md"
g "$R" init -q -b main; g "$R" add -A; g "$R" commit -qm base
PK="$T/pack/feature-pack/fable-team/harness"; mkdir -p "$PK/kit/fable-team/bin"; echo v1 > "$PK/kit/fable-team/bin/x.sh"
g "$T/pack" init -q -b main; g "$T/pack" add -A; g "$T/pack" commit -qm p0; echo v2 > "$PK/kit/fable-team/bin/x.sh"
g "$T/pack" add -A; g "$T/pack" commit -qm p1; P0="$(g "$T/pack" rev-parse HEAD)"; g "$T/pack" update-ref refs/remotes/origin/main "$P0"
printf '#!/bin/bash\nexit 0\n' > "$T/chk0"; printf '#!/bin/bash\necho MISMATCH x.sh\nexit 1\n' > "$T/chk1"; chmod 755 "$T/chk0" "$T/chk1"
export FT_INSTALL_RESTART_GATE=0 FT_HARNESS_ROOT="$PK" FT_INSTALL_PENDING_DIR="$T/pd" FT_SEATS_JSON="$T/none.json" FT_MBOX=/bin/true FT_INDEX_STATE_DIR="$T/st"
mkdir -p "$T/st"
# ── ① 완성 이동: 정본 줄·규칙 줄·실사건 줄 없음 → 사유 3줄 모두 · rc 1 · 이동 0 (기준판 = 첫 사유 1줄)
s0=$SECONDS; out="$(FT_INSTALL_CHECK="$T/chk0" timeout 70 bash "$BIN/ft-index-move.sh" "$IDX/진행/r1844a.md" 완성 --da "$R/design/harness/DA-x.md#§1" --seat s --landed "$P0" 2>&1)"; rc=$?
n="$(printf '%s\n' "$out" | grep -cE '^  - (정본 게이트|카드에 「- 규칙:」 줄 없음|카드에 「- 실사건:)')"
{ [ "$rc" = 1 ] && [ "$n" = 3 ] && [ -f "$IDX/진행/r1844a.md" ] && printf '%s\n' "$out" | grep -q '^REJECT 정본 게이트'; }; ck "① 완성 관문 사유 3줄 · rc1 · 이동 0 ($((SECONDS-s0))s)" $?
# ── ①b 설치 게이트 단독: 라이브 어긋남 + 실사건 줄 없음 → 사유 2줄 (M1 표적)
inst() { out="$(FT_INSTALL_CHECK="$T/chk1" timeout 70 bash "$1" "$IDX/진행/r1844a.md" --landed "$P0" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -cE '^  - (라이브 설치 어긋남|카드에 「- 실사건:)')" = 2 ]; }
s0=$SECONDS; inst "$BIN/ft-index-move-install.sh"; ck "①b 설치 게이트 사유 2줄 ($((SECONDS-s0))s)" $?
# ── ②③ lint 작은 카드
L="$IDX/대기"
small() { local f="$L/$1.md" k; { echo "# 인덱스: $1 — 끝: 시험"; echo '<!-- ledger: design/LEDGER.md -->'
  for k in '지시 #: t#1' '골좌표: 4 · 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '원인 1줄: 시험' '대상(쓰기 = 나노): src/target.sh' \
    '계약: x' '반례: ① x' '변이: M1 x' '회귀: x' '크기: x' '범위 밖: x' '설치: 없음' '상태: 대기'; do [ "$k" = "${2:-}" ] || echo "- $k"; done
  [ "${4:-}" = nost ] || { echo; echo '## 상태'; }; for k in $(seq "$3"); do echo "- s$k"; done; } > "$f"; echo "$f"; }
lint() { out="$(cd "$R" && timeout 70 bash "${2:-$BIN/ft-index-lint.sh}" "$1" 2>&1)"; rc=$?; }
s0=$SECONDS; f="$(small s20 '' 4)"; [ "$(wc -l < "$f" | tr -d ' ')" = 20 ]; ck "② 카드 20줄" $?
lint "$f"; [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^OK '; ck "② 20줄 + 10키 → OK ($((SECONDS-s0))s)" $?
f="$(small s20n '' 6 nost)"; lint "$f"; [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^  - 작은 카드: 끝 «## 상태» 절'; ck "② «## 상태» 절 없음 → REJECT(r1846)" $?
f="$(small s19 '반례: ① x' 4)"; lint "$f"; [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^  - ')" = 1 ] && printf '%s\n' "$out" | grep -q '^  - 작은 카드: 머리 키 없음: 반례$'
ck "③ 20줄 이하 반례 뺌 → 그 키 1줄" $?
f21="$(small s21 '반례: ① x' 6)"; [ "$(wc -l < "$f21" | tr -d ' ')" = 21 ]; ck "③ 카드 21줄" $?
lint21() { lint "$f21" "${1:-}"; [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^  - 절 없음: 골 원문' && ! printf '%s\n' "$out" | grep -q '작은 카드'; }
s0=$SECONDS; lint21; ck "③ 21줄 = 지금처럼 절 검사 ($((SECONDS-s0))s)" $?
# ── 변이 M1 install rej 즉시 exit → ①b FAIL · M2 20줄 문턱 제거 → ③ 21줄 FAIL
cp -Rp "$BIN" "$T/m1"; mutate "$T/m1/ft-index-move-install.sh" 'rej() { R+=("$*"); }' 'rej() { echo "REJECT $* (이동 0)"; exit 1; }'
inst "$T/m1/ft-index-move-install.sh"; [ $? != 0 ]; ck "M1 install rej 즉시 exit → ①b FAIL(적중)" $?
cp -Rp "$BIN" "$T/m2"; mutate "$T/m2/ft-index-lint.sh" '-le 20 ]' '-le 99999 ]'
lint21 "$T/m2/ft-index-lint.sh"; [ $? != 0 ]; ck "M2 20줄 문턱 제거 → ③ 21줄 FAIL(적중)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
