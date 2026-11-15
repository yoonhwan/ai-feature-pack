#!/usr/bin/env bash
# test_local_bin_link_drift_r2017.sh — r2017: 설치 대조(ft-live-install-check)가 ~/.local/bin 의 ft-* 심링크 중
# «LIVE_BIN 아래도, 루트 shim(<루트>/.fable-team/bin 의 SHIMMARK 파일)도 아닌» 대상을 «DRIFT-LINK <이름> -> <대상>» 1줄씩 낸다(고치기 0 · rc = 기존 PENDING 규칙).
# 사건: ft-successor-open 을 PATH 로 부르면 판 번호가 박힌 옛 판(1.1.270)이 돌았다 — 링크를 손으로 만들었고 점검이 없었다.
# T1 링크 → 옛 판 = DRIFT-LINK 1줄 rc1 · T2 링크 → 지금 LIVE_BIN = 0줄 · T3 링크 → 루트 shim = 0줄
# T4 ft-* 아닌 링크·ft-* 일반 파일 = 0줄 · T5 깨진 링크 = DRIFT-LINK(대상 없음) 1줄
# 변이(손 적용 확인): M1 = 판 비교 삭제 → T1 FAIL · M2 = shim 허용 삭제 → T3 FAIL
# 임시 HOME·가짜 live 2판·임시 루트·임시 git 리포만 — 실 ~/.local/bin·실 ~/.claude 0 · 링크 수정 0 확인 · timeout 70.
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
export HOME="$T/home"; mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/bin"; LB="$HOME/.local/bin"
export FT_ROOTS_TSV="$T/none.tsv"
LV="$T/fable-team/live"; OLD="$LV/1.1.270/bin"; NEW="$LV/1.1.292/bin"
for d in "$OLD" "$NEW"; do mkdir -p "$d"; printf '#!/bin/bash\necho x\n' > "$d/ft-budget.sh"; chmod +x "$d/ft-budget.sh"; done

# ── 픽스처: 키트 리포(skip 행만 — 다른 점검 줄 0) · 루트 P(LIVE_BIN = NEW · .fable-team/bin 에 shim 1개) ──
R="$T/repo"; mkdir -p "$R/kit"; G() { git -C "$R" "$@"; }
G init -q -b main .; G config user.name t; G config user.email t@t
printf '*.txt\tskip\t-\t-\nLIVE-MAP.tsv\tskip\t-\t-\n' > "$R/kit/LIVE-MAP.tsv"; echo a > "$R/kit/a.txt"; G add -A; G commit -qm k0
P="$T/rootP"; mkdir -p "$P/.fable-team/bin"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0
echo "$NEW" > "$P/.fable-team/LIVE_BIN"
printf '#!/usr/bin/env bash\n# ft-root-bin-shim: ft-budget.sh\nexec true\n' > "$P/.fable-team/bin/ft-budget.sh"
printf '#!/usr/bin/env bash\necho plain\n' > "$P/.fable-team/bin/ft-plain.sh"   # shim 표식 없는 루트 bin 파일
chk() { out="$(timeout 70 bash "$CHK" --all --ref main --repo "$R" --kit kit --project "$P" 2>&1)"; rc=$?; }
clr() { rm -f "$LB"/*; }

python3 -m py_compile "$PY" && bash -n "$CHK"; ck "py_compile · bash -n" $?
cmp -s "$PY" "$H/kit/fable-team/bin/ft_live_install_check.py"; ck "bin/kit 짝 cmp0 (ft_live_install_check)" $?

# ── T1: 링크 → 옛 판 → DRIFT-LINK 1줄 · rc1 · 링크 수정 0 ─────────────────────────────
clr; ln -s "$OLD/ft-budget.sh" "$LB/ft-budget"; chk
[ "$rc" = 1 ] && has "PENDING n=1" && has "DRIFT-LINK ft-budget -> $OLD/ft-budget.sh" && [ "$(cnt 'DRIFT-LINK')" = 1 ]
ck "T1 링크 → 옛 판 → DRIFT-LINK 1줄 rc1" $?
[ "$(readlink "$LB/ft-budget")" = "$OLD/ft-budget.sh" ] && has "HINT local-bin"; ck "T1 링크 수정 0 · HINT local-bin(고침 = master)" $?

# ── T2: 링크 → 지금 LIVE_BIN → 0줄 rc0 ────────────────────────────────────────────
clr; ln -s "$NEW/ft-budget.sh" "$LB/ft-budget"; chk
[ "$rc" = 0 ] && hasnt "DRIFT-LINK"; ck "T2 링크 → 지금 LIVE_BIN → 0줄 rc0" $?

# ── T3: 링크 → 루트 shim → 0줄 · shim 표식 없는 루트 bin 파일은 DRIFT-LINK ─────────────────
clr; ln -s "$P/.fable-team/bin/ft-budget.sh" "$LB/ft-budget"; chk
[ "$rc" = 0 ] && hasnt "DRIFT-LINK"; ck "T3 링크 → 루트 shim → 0줄 rc0" $?
clr; ln -s "$P/.fable-team/bin/ft-plain.sh" "$LB/ft-plain"; chk
[ "$rc" = 1 ] && has "DRIFT-LINK ft-plain -> $P/.fable-team/bin/ft-plain.sh"; ck "T3b 루트 bin 이어도 shim 표식 0 → DRIFT-LINK" $?

# ── T4: ft-* 아닌 링크 · ft-* 일반 파일 → 0줄 ──────────────────────────────────────
clr; ln -s "$OLD/ft-budget.sh" "$LB/budget"; printf '#!/bin/bash\n' > "$LB/ft-plainfile"; chk
[ "$rc" = 0 ] && hasnt "DRIFT-LINK"; ck "T4 ft-* 아닌 링크·일반 파일 → 0줄 rc0" $?

# ── T5: 깨진 링크 → DRIFT-LINK (대상 없음) 1줄 ─────────────────────────────────────
clr; ln -s "$T/gone/ft-x.sh" "$LB/ft-x"; chk
[ "$rc" = 1 ] && has "DRIFT-LINK ft-x -> $T/gone/ft-x.sh (대상 없음)" && [ "$(cnt 'DRIFT-LINK')" = 1 ]
ck "T5 깨진 링크 → DRIFT-LINK(대상 없음) 1줄 rc1" $?

# ── 범위 밖: 루트 LIVE_BIN 없음 → 이 갈래 줄 0 · ~/.local/bin 없음 → 줄 0 ───────────────────
clr; ln -s "$OLD/ft-budget.sh" "$LB/ft-budget"; mv "$P/.fable-team/LIVE_BIN" "$T/LIVE_BIN.off"; chk
[ "$rc" = 0 ] && hasnt "DRIFT-LINK"; ck "LIVE_BIN 없음 → 줄 0(검사 밖)" $?
mv "$T/LIVE_BIN.off" "$P/.fable-team/LIVE_BIN"; clr; rmdir "$LB"; chk
[ "$rc" = 0 ] && hasnt "DRIFT-LINK"; ck "~/.local/bin 없음 → 줄 0" $?

grep -q "def local_bin_drift(" "$PY"; ck "판정 1함수(local_bin_drift)" $?
[ "$SECONDS" -le 70 ]; ck "시험 시간 상한(70초 · 실측 ${SECONDS}s)" $?
[ "$fail" = 0 ] && echo "ALL PASS (${SECONDS}s)" || { echo "FAILED $fail"; exit 1; }
