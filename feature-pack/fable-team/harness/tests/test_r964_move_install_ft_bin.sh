#!/usr/bin/env bash
# test_r964_move_install_ft_bin.sh — r964: 완성 이동 설치 게이트가 대조기를 부를 때 FT_BIN 을 «비면 게이트가 있는 라이브 폴더» 로 넘기고,
#   대조기 rc=3(대조 못 함)은 «라이브 설치 어긋남» 이 아니라 «설치 대조 불가» 로 따로 거절한다.
#   사건(arch 149 실측 2026-10-26): `env -u FT_BIN bash <라이브>/ft-live-install-check.sh --all --project <루트>` → ERROR FT_BIN 없음 rc=3 ·
#   같은 명령에 FT_BIN=<라이브 bin> → OK n=462 · 게이트 45~46행이 rc≠0 을 모두 «설치 어긋남» 으로 적어, 설치가 맞는데 없는 설치 문제를 찾게 했다.
#   임시 리포 2개(하네스 리포 = 팩 꼴 경로 · 카드 리포) + 가짜 대조기 주입. 실 라이브·실 원격·쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"   # 정본 = 팩 키트
PAIR="$(cd -- "$HERE/../bin" && pwd -P)/ft-index-move-install.sh"   # 짝 사본
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=${rc:-?} out=${out:0:500} log=${got:-}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; mkdir -p "$HOME"
unset FT_BIN FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 도구 사본 1벌(게이트 + 부속) · 변이용으로 게이트만 갈아 끼운다
mkbin() { local d="$1"; mkdir -p "$d"; cp -p "$SRC/ft-index-move-install.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_plist_env.py" "$SRC/ft_git_capped.py" \
  "$SRC/ft-harness-root.sh" "$d/"; }
BIN="$T/bin"; mkbin "$BIN"
BIN_P="$(cd "$BIN" && pwd -P)"
FTB="$T/ftbin"; mkdir -p "$FTB"
LOG="$T/got.log"; : > "$LOG"

# ── 하네스 리포(팩 꼴 경로) — 범위 A..B 가 키트 파일 1개를 고친다
HR="$T/hrepo"; mkdir -p "$HR/feature-pack/fable-team/harness/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"; chmod 755 "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"
printf 'fable-team/bin/*\tbin\t$FT_BIN\tmaster: install.sh --apply\n' > "$HR/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
g "$HR" init -q -b main; g "$HR" add -A; g "$HR" commit -qm c0; A="$(g "$HR" rev-parse HEAD)"
printf '#!/bin/bash\necho v2\n' > "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"
g "$HR" add -A; g "$HR" commit -qm c1; B="$(g "$HR" rev-parse HEAD)"
g "$HR" update-ref refs/remotes/origin/main "$B"
HRKIT="$HR/feature-pack/fable-team/harness"
printf '#!/bin/bash\necho v2\n' > "$FTB/x.sh"; chmod 755 "$FTB/x.sh"

# ── 카드 리포(설치 있음 · 실사건 증거 토큰 있음)
CR="$T/cardrepo"; mkdir -p "$CR/design/harness/indices/진행"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
CARD="$CR/design/harness/indices/진행/t.md"
printf '# 인덱스: t\n- 설치: 있음\n- 실사건: 카드 이동 · 증거 mbox #123416\n## 상태\n- x\n' > "$CARD"
g "$CR" add -A; g "$CR" commit -qm card

# ── 가짜 대조기: 받은 FT_BIN 을 기록하고 FAKE_RC 대로 끝난다(기본 0)
FAKE="$T/fake-chk.sh"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FT_BIN-__UNSET__}" > "${FAKE_LOG:?}"
case "${FAKE_RC:-0}" in
  0) echo "OK n=1 skip=0"; exit 0 ;;
  3) echo "ERROR 지도 못 풂(가짜 · FT_BIN=${FT_BIN-__UNSET__})"; exit 3 ;;
  *) echo "DIFF x.sh"; exit "${FAKE_RC}" ;;
esac
EOF
chmod 755 "$FAKE"
PD="$T/pending"; mkdir -p "$PD"

# run_case <게이트> <rc> [FT_BIN 값] — 게이트 1회 실행 → rc·out·got(대조기가 받은 FT_BIN)
run_case() {
  local gate="$1" frc="$2" fb="${3-}" E=(env -u FT_BIN)
  case "$fb" in ''|__UNSET__) ;; *) E+=("FT_BIN=$fb");; esac   # 3.2: 빈 배열 전개는 set -u 에서 터진다 — 최소 1개는 항상 들어 있다
  : > "$LOG"
  out="$("${E[@]}" FT_INSTALL_CHECK="$FAKE" FAKE_LOG="$LOG" FAKE_RC="$frc" \
        FT_INSTALL_PENDING_DIR="$PD" FT_HARNESS_ROOT="$HRKIT" bash "$gate" "$CARD" --landed "$A..$B" 2>&1)"; rc=$?
  got="$(head -1 "$LOG" 2>/dev/null)"
}

# ⓐ FT_BIN 이 없는 env + 설치가 맞는 카드 → 통과 · 대조기가 받은 FT_BIN = 게이트 폴더
run_case "$BIN/ft-index-move-install.sh" 0
if [ "$rc" = 0 ] && [ "$(cd "$got" 2>/dev/null && pwd -P)" = "$BIN_P" ]; then ck "ⓐ FT_BIN 없음 → 통과 rc0 · 대조기가 받은 FT_BIN = 게이트 폴더($BIN_P)" 0; else ck "ⓐ FT_BIN 없음 → 통과 · FT_BIN = 게이트 폴더" 1; fi

# ⓑ 부른 쪽이 FT_BIN 을 넣으면 그 값 그대로(게이트가 덮지 않음)
run_case "$BIN/ft-index-move-install.sh" 0 "$FTB"
if [ "$rc" = 0 ] && [ "$got" = "$FTB" ]; then ck "ⓑ FT_BIN 지정 → 그 값으로 대조($FTB)" 0; else ck "ⓑ FT_BIN 지정 → 그 값으로 대조" 1; fi

# ⓒ 대조기 rc=3 → «설치 대조 불가» 거절 · «라이브 설치 어긋남» 글자 0
run_case "$BIN/ft-index-move-install.sh" 3
if [ "$rc" = 1 ] && [[ "$out" == *"설치 대조 불가"* ]] && [[ "$out" == *"지도 못 풂(가짜"* ]] && [[ "$out" != *"라이브 설치 어긋남"* ]]; then
  ck "ⓒ rc=3 → «설치 대조 불가» + 대조기 첫 ERROR 줄 · «라이브 설치 어긋남» 0" 0
else ck "ⓒ rc=3 → «설치 대조 불가» + 대조기 첫 ERROR 줄 · «라이브 설치 어긋남» 0" 1; fi

# ⓓ 실제 어긋남(rc=1) → 지금처럼 «라이브 설치 어긋남» 거절
run_case "$BIN/ft-index-move-install.sh" 1
if [ "$rc" = 1 ] && [[ "$out" == *"라이브 설치 어긋남"* ]] && [[ "$out" != *"설치 대조 불가"* ]]; then ck "ⓓ rc=1(DIFF) → «라이브 설치 어긋남» 거절" 0; else ck "ⓓ rc=1(DIFF) → «라이브 설치 어긋남» 거절" 1; fi

# ⓔ kit 짝 사본 cmp0 · /bin/bash 3.2 문법 통과
if cmp -s "$SRC/ft-index-move-install.sh" "$PAIR"; then ck "ⓔ kit ↔ 하네스 bin 짝 사본 cmp0" 0; else ck "ⓔ kit ↔ 하네스 bin 짝 사본 cmp0" 1; fi
if /bin/bash -n "$SRC/ft-index-move-install.sh" 2>/dev/null; then ck "ⓔ /bin/bash 3.2 문법 통과" 0; else ck "ⓔ /bin/bash 3.2 문법 통과" 1; fi

# ── 변이 3종: 각각 «해당 체크가 FAIL» 이어야 시험이 산다
mut() { local d="$T/mut-$1"; mkbin "$d"; python3 - "$BIN/ft-index-move-install.sh" "$d/ft-index-move-install.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
echo "$d/ft-index-move-install.sh"; }
M1="$(mut m1 'FT_BIN="${FT_BIN:-$HERE}" bash "$CHK"' 'bash "$CHK"')"
run_case "$M1" 0
if [ "$(cd "$got" 2>/dev/null && pwd -P)" = "$BIN_P" ]; then ck "변이 «FT_BIN 기본값 빼기» → ⓐ FAIL" 1; else ck "변이 «FT_BIN 기본값 빼기» → ⓐ FAIL(got=${got:-빈값})" 0; fi
M2="$(mut m2 'FT_BIN="${FT_BIN:-$HERE}" bash "$CHK"' 'FT_BIN="$HERE" bash "$CHK"')"
run_case "$M2" 0 "$FTB"
if [ "$got" = "$FTB" ]; then ck "변이 «기본값이 부른 쪽 값을 덮음» → ⓑ FAIL" 1; else ck "변이 «기본값이 부른 쪽 값을 덮음» → ⓑ FAIL(got=${got:-빈값})" 0; fi
M3="$(mut m3 'rej "설치 대조 불가(rc=3)' 'rej "라이브 설치 어긋남(rc=3)')"
run_case "$M3" 3
if [[ "$out" == *"라이브 설치 어긋남"* ]]; then ck "변이 «rc 갈래 하나로» → ⓒ FAIL" 0; else ck "변이 «rc 갈래 하나로» → ⓒ FAIL" 1; fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
