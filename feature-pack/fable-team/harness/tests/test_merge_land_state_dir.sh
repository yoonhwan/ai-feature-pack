#!/usr/bin/env bash
# test_merge_land_state_dir.sh — R253: 자율 상태 폴더 해석 = ft-autonomy.sh state-dir 한 곳 (설치 폴더 ≠ repo 픽스처 · FT_ROOT·FT_AUTONOMY_STATE_DIR unset · gh 는 스텁 · 실 원격 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset FT_ROOT FT_AUTONOMY_STATE_DIR FT_PLANNER_DIR FT_NOW
mkrepo "$T"
export FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"

mkinst() {  # mkinst <설치 루트> — <루트>/.fable-team/bin 에 병합 도구 묶음 복사(repo·원격은 설치 폴더 밖) · 시작 장부·뒤처짐 알림은 무동작 스텁
  local b="$1/.fable-team/bin"; mkdir -p "$b"
  for f in ft-merge-land.sh ft-merge-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-autonomy.sh; do cp "$BIN/$f" "$b/$f"; done
  for f in ft-autonomy-start.sh ft-head-lag.sh; do printf '#!/bin/bash\nexit 0\n' > "$b/$f"; done
  chmod +x "$b"/*.sh
}
mkpr() {  # mkpr <번호> <브랜치> <시작점>
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
omain() { sha "$ORIGIN" refs/heads/main; }
X="$T/inst"; mkinst "$X"; XB="$X/.fable-team/bin"
land() { out="$(bash "$XB/ft-merge-land.sh" "$@" --repo "$W" 2>&1)"; rc=$?; }

out="$(bash "$XB/ft-autonomy.sh" state-dir 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$X/.fable-team/state" ]; ck "ⓐ state-dir = 설치 폴더 기준 state (repo 아님)" $?
out="$(FT_AUTONOMY_STATE_DIR=/d bash "$XB/ft-autonomy.sh" state-dir 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "/d" ]; ck "ⓑ FT_AUTONOMY_STATE_DIR 지정이면 그 값" $?

bash "$XB/ft-autonomy.sh" on >/dev/null 2>&1; git -C "$W" fetch -q origin
mkpr 21 pr21 origin/main; P21="$PRSHA"; M1="$(omain)"
bash "$XB/ft-autonomy.sh" approve-merge "$P21" >/dev/null 2>&1
land 21 --approve-sha "$P21"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain)" != "$M1" ]; ck "ⓒ 자율 ON · approve-merge 뒤 env 없이 착지(LANDED)" $?

git -C "$W" fetch -q origin; mkpr 22 pr22 origin/main; P22="$PRSHA"; M2="$(omain)"
land 22 --approve-sha "$P22"
[ "$rc" = 2 ] && [[ "$out" == *"approve-merge"* ]] && [ "$(omain)" = "$M2" ]; ck "ⓓ 자율 ON · 승인 없음 → 같은 REJECT rc2 · main 불변" $?

X2="$T/inst-bad"; mkinst "$X2"; XB2="$X2/.fable-team/bin"
printf '#!/bin/bash\ncase "$1" in mode) echo on;; state-dir) exit 1;; esac\n' > "$XB2/ft-autonomy.sh"
out="$(bash "$XB2/ft-merge-land.sh" 22 --approve-sha "$P22" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"자율 상태 폴더 해석 실패"* ]] && [ "$(omain)" = "$M2" ]; ck "ⓔ state-dir 실패 → REJECT 자율 상태 폴더 해석 실패 · 착지 0" $?

LOGF="$W/.fable-team/state/merge-gate.log"
[ "$(grep -c 'method=ft-merge-land' "$LOGF" 2>/dev/null)" = 1 ] && grep -q "head=$P21 method=ft-merge-land .*pr=21" "$LOGF"; ck "ⓕ merge-gate.log = <git 공용 루트>/.fable-team/state 에 1줄" $?
[ ! -e "$X/.fable-team/state/merge-gate.log" ]; ck "ⓕ 설치 폴더 state 에는 merge-gate.log 0" $?
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
