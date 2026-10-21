#!/usr/bin/env bash
# test_merge_land_pack_repo.sh — r648: `ft-merge-land.sh <PR> --approve-sha <sha> --repo <다른 리포(팩)>` = «리포 기준» 모드
#   승인 폴더 = 정식 리졸버(ft-autonomy.sh state-dir) 하나 · gh PR 조회 = -R <대상 리포 실제 전송 URL 의 owner/name> · 기준 헤드·게이트 = 대상 리포 · 승인 없으면 실행 0 그대로
#   임시 BYZ 리포 + 임시 팩 리포(origin = git@github.com:fake/pack.git · GIT_SSH_COMMAND 가짜 ssh 로 실제 전송은 로컬 bare) · 가짜 gh · 실 gh·실 원격 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"; AUT="$BIN/ft-autonomy.sh"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"; BASEREF="${FT_R648_BASE:-origin/main}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub"

# ── 픽스처: BYZ 리포(승인 루트 · cwd) · 팩 리포(origin = 깃허브 ssh 꼴 · GIT_SSH_COMMAND 스텁이 로컬 bare 로 전송)
mkrepo "$T/byz"; BYZ="$T/byz/w"; BYZ_ORIGIN="$T/byz/origin.git"
printf 'byz\n' > "$BYZ/byz.txt"; cm "$BYZ" "byz only"; git -C "$BYZ" push -q origin main   # 팩과 커밋 sha 가 겹치지 않게
mkdir -p "$T/byz/.fable-team/state"
mkrepo "$T/pack"; PACK="$T/pack/w"; PACKORIGIN="$T/pack/origin.git"
git -C "$PACK" remote set-url origin git@github.com:fake/pack.git
cat > "$T/stub/ssh" <<'EOF'
#!/bin/bash
exec bash -c "$(printf '%s' "${!#}" | sed -E "s|'[^']*'|'$PACK_ORIGIN'|")"   # git-upload-pack '<원격 경로>' → 로컬 bare
EOF
chmod +x "$T/stub/ssh"; export GIT_SSH_COMMAND="$T/stub/ssh"

# ── 가짜 gh: `-R` 값별 다른 JSON(팩 PR / BYZ PR) · 인자·FT_ISSUE_REPO 기록 (gh-all = -R 무시하고 팩 JSON)
cat > "$T/stub/gh" <<'EOF'
#!/bin/bash
echo "GL $* repo=${FT_ISSUE_REPO:-}" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] || exit 0
for a in "$@"; do [ "${pv:-}" = "-R" ] && R="$a"; pv="$a"; done
[ -n "${R:-}" ] && cat "$PACK_JSON" || cat "$BYZ_JSON"   # -R 이 붙으면 팩 PR · 안 붙으면 BYZ 쪽 같은 번호
EOF
printf '#!/bin/bash\necho "GL $* repo=${FT_ISSUE_REPO:-}" >> "$STUB_LOG"\n[ "$1 $2" = "pr view" ] && cat "$PACK_JSON"\nexit 0\n' > "$T/stub/gh-all"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" STUB_LOG="$T/gh.log" PACK_JSON="$T/pack.json" BYZ_JSON="$T/byz.json" FT_INSTALL_CHECK="$T/stub/noop"

# ── 지금 판(base HEAD) 도구 사본 — ⓐ «실패 시험 먼저» 의 전(前) 판
mkdir -p "$T/base"
for f in ft-merge-land.sh ft-merge-lib.sh ft-evidence-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-autonomy.sh ft-autonomy-level.sh ft-harness-root.sh ft_flag_off.py; do
  git -C "$TOP" show "$BASEREF:${BIN#"$TOP"/}/$f" > "$T/base/$f" || { echo "FAIL base 사본 $f"; fail=$((fail+1)); }
done
chmod +x "$T/base"/*.sh; printf '#!/bin/bash\nexit 0\n' > "$T/base/ft-head-lag.sh"; chmod +x "$T/base/ft-head-lag.sh"

omain() { sha "$1" refs/heads/main; }   # omain <bare>
json() { python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: "+sys.argv[2],"body":"본문","state":sys.argv[3],"baseRefName":"main"}))' "$1" "$2" "$3"; }
mkpr() {  # mkpr <clone> <bare> <번호> <JSON파일> [noapprove] — 그 리포 origin/main 에서 PR head + 승인
  local c="$1" b="$2" n="$3" j="$4"
  PACK_ORIGIN="$b" git -C "$c" fetch -q origin; git -C "$c" checkout -q -B "pr$n" origin/main; echo "pr$n" > "$c/pr$n.txt"; cm "$c" "pr $n work"
  PACK_ORIGIN="$b" git -C "$c" push -q origin "pr$n:refs/pull/$n/head"; PRSHA="$(sha "$c" HEAD)"; PRNUM="$n"
  json "$PRSHA" "PR $n" OPEN > "$j"; PRJSON="$j"   # 가짜 gh 가 이 리포의 PR JSON 을 낸다
  [ "${5:-}" = noapprove ] || bash "$AUT" approve-merge "$PRSHA" >/dev/null 2>&1
}
land() {  # land <land.sh> [KEY=VAL…] — cwd = BYZ 리포(부른 리포) · PACK_ORIGIN 은 ssh 스텁이 쓴다
  local l="$1"; shift; : > "$STUB_LOG"
  out="$(cd "$BYZ" && env "$@" PACK_ORIGIN="${REPO_ORIGIN:-$PACKORIGIN}" PACK_JSON="${PRJSON:-$T/pack.json}" bash "$l" "$PRNUM" --approve-sha "${AP_SHA:-$PRSHA}" --repo "${REPO_ARG:-$PACK}" 2>&1)"; rc=$?
}
mled() { tail -n1 "$BSTATE/merge-gate.log" | sed -E 's/^[0-9T:+-]+ //; s/[0-9a-f]{40}/<sha>/g; s/pr=[0-9]+/pr=<n>/; s/approve-file=[0-9]+/approve-file=<epoch>/'; }   # 원장 줄 — 시각·sha·PR번호·승인 epoch 만 가린다

# ══ ⓐ 재현(전판) → 고침(후판): 같은 입력 · 같은 픽스처
json "$(sha "$BYZ" HEAD)" "byz PR" CLOSED > "$BYZ_JSON"
BSTATE="$T/byz/.fable-team/state"; export FT_ROOT="$T/byz" FT_AUTONOMY_STATE_DIR="$BSTATE"
M0="$(omain "$PACKORIGIN")"; mkpr "$PACK" "$PACKORIGIN" 5 "$PACK_JSON"; P5="$PRSHA"
land "$T/base/ft-merge-land.sh" -u FT_ROOT FT_AUTONOMY_STATE_DIR=
[ "$rc" != 0 ] && [[ "$out" == *"자율 상태 폴더 해석 실패"* ]]; ck "ⓐ1 전판 · FT_ROOT 없음 → REJECT «자율 상태 폴더 해석 실패»" $?
land "$T/base/ft-merge-land.sh"
[ "$rc" != 0 ] && [[ "$out" == *"OPEN 아님"* ]] && grep -q "pr view 5 " "$STUB_LOG" && ! grep -q -- ' -R ' "$STUB_LOG"; ck "ⓐ2 전판 · gh -R 없음 → BYZ 쪽 PR #5 로 조회(OPEN 아님)" $?
printf '%s\n' "$(sha "$BYZ" HEAD)" > "$BSTATE/base-head"
land "$T/base/ft-merge-land.sh" FT_GH="$T/stub/gh-all"
[ "$rc" != 0 ] && [[ "$out" == *"기준 헤드"*"객체 없음"* ]]; ck "ⓐ3 전판 · BYZ 기준 헤드를 팩 리포 객체로 찾음 → REJECT «객체 없음»" $?
[ "$(omain "$PACKORIGIN")" = "$M0" ]; ck "ⓐ4 전판 3꼴 전부 착지 0(팩 main 불변)" $?

land "$LAND"; Q="${out#*sha=}"; Q="${Q%% *}"; [ "$rc" = 0 ] || Q=""
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ -n "$Q" ] && [ "$(omain "$PACKORIGIN")" = "$Q" ]; ck "ⓐ5 고친 판 · 같은 입력 → LANDED · 팩 origin main = 착지 sha" $?
[ -n "$Q" ] && [ "$(git -C "$PACKORIGIN" rev-parse "$Q^{tree}")" = "$(sha "$PACK" "$P5^{tree}")" ]; ck "ⓐ6 착지 트리 == 검사한 팩 PR head 트리" $?

# ══ ⓑ 대상 리포 기준 gh 조회 · 닫기
grep -q "pr view 5 -R fake/pack --json" "$STUB_LOG" && ! grep -q "pr view 5 --json" "$STUB_LOG"; ck "ⓑ gh pr view -R fake/pack(실제 전송 URL 에서 풂 · BYZ 번호 조회 0)" $?
grep -q "pr-close 5 .* repo=fake/pack" "$STUB_LOG"; ck "ⓑ2 PR 코멘트·닫기 wrapper 도 FT_ISSUE_REPO=fake/pack" $?

# ══ ⓒ 승인 값 = 부른 리포(BYZ) 자율 상태 폴더 그대로 · 팩 쪽 상태 폴더 0
[ -f "$BSTATE/autonomy-merge-approved/$P5" ] && grep -qxF "$(head -n1 "$BSTATE/autonomy-merge-approved/$P5")" "$BSTATE/autonomy.log"; ck "ⓒ 승인 파일·로그 = BYZ 자율 상태 폴더 그대로" $?
[ ! -e "$T/pack/.fable-team" ] && [ ! -e "$PACK/.fable-team" ]; ck "ⓒ2 팩 리포에 상태 폴더 생성 0" $?

# ══ ⓓ 기준 헤드·게이트 = 대상 리포(팩) · 리포별 기준 헤드
[ -n "$Q" ] && [ "$(git -C "$PACKORIGIN" rev-parse "$Q^")" = "$M0" ] && [[ "$out" == *"main_before=$M0"* ]]; ck "ⓓ 게이트·착지 = 팩 origin/main 위(부모 = 착지 전 팩 main)" $?
[ -n "$Q" ] && [ "$(head -n1 "$BSTATE/base-head-fake-pack" 2>/dev/null)" = "$Q" ] && [ "$(head -n1 "$BSTATE/base-head")" = "$(sha "$BYZ" HEAD)" ]; ck "ⓓ2 기준 헤드 리포별(base-head-fake-pack ← Q · BYZ base-head 그대로)" $?

# ══ ⓔ 성공 원장 = 승인 쪽 한 곳 · 줄에 repo=<대상 리포>
grep -q "repo=pack main=$M0 head=$P5 method=ft-merge-land .*landed=$Q pr=5 " "$BSTATE/merge-gate.log" && [ ! -e "$PACK/.fable-team/state" ]; ck "ⓔ 원장 = BYZ 한 곳 · 줄에 repo=pack" $?

# ══ ⓖ 실제 전송 URL 끼리 어긋남(insteadOf: raw = 깃허브, 실제 = 로컬) → REJECT · 착지 0 · gh 조회 0
mkrepo "$T/pack2"; P2="$T/pack2/w"; P2ORIGIN="$T/pack2/origin.git"
git -C "$P2" config url."$P2ORIGIN".insteadOf "https://github.com/fake/pack2.git"; git -C "$P2" remote set-url origin https://github.com/fake/pack2.git
mkpr "$P2" "$P2ORIGIN" 9 "$T/pack2.json"; P9="$PRSHA"; M9="$(omain "$P2ORIGIN")"; REPO_ARG="$P2"; REPO_ORIGIN="$P2ORIGIN"
land "$LAND"; REPO_ARG=""; REPO_ORIGIN=""
[ "$rc" = 1 ] && [[ "$out" == *"remote URL 해석 실패"* ]] && [ "$(omain "$P2ORIGIN")" = "$M9" ] && [ ! -s "$STUB_LOG" ]; ck "ⓖ raw URL ≠ 실제 전송 URL(insteadOf) → REJECT 1줄 · 착지 0 · gh 조회 0" $?

# ══ ⓖ4 push 목적지가 둘 이상(첫 = 팩 · 두 번째 = 다른 리포) → REJECT(land 는 등록된 모든 URL 로 보낸다)
mkrepo "$T/pack4"; P4="$T/pack4/w"; P4ORIGIN="$T/pack4/origin.git"
git -C "$P4" remote set-url origin git@github.com:fake/pack.git
git -C "$P4" remote set-url --add --push origin git@github.com:fake/pack.git
git -C "$P4" remote set-url --add --push origin git@github.com:fake/other.git
mkpr "$P4" "$P4ORIGIN" 31 "$T/pack4.json"; P31="$PRSHA"; M31="$(omain "$P4ORIGIN")"; REPO_ARG="$P4"; REPO_ORIGIN="$P4ORIGIN"
land "$LAND"; REPO_ARG=""; REPO_ORIGIN=""
[ "$rc" = 1 ] && [[ "$out" == *"remote URL 해석 실패"* ]] && [ "$(omain "$P4ORIGIN")" = "$M31" ] && [ ! -s "$STUB_LOG" ]; ck "ⓖ4 push 목적지 2개(팩 + 다른 리포) → REJECT · 착지 0 · gh 조회 0" $?

# ══ ⓖ2 승인 없음 = 실행 0 유지 · ⓖ3 교차 리포 «다른 sha 승인» → REJECT
mkpr "$PACK" "$PACKORIGIN" 11 "$PACK_JSON" noapprove; M11="$(omain "$PACKORIGIN")"
land "$LAND"
[ "$rc" = 2 ] && [[ "$out" == *"approve-merge"* ]] && [ "$(omain "$PACKORIGIN")" = "$M11" ]; ck "ⓖ2 승인 없음 → rc2 · 착지 0" $?
mkpr "$PACK" "$PACKORIGIN" 12 "$PACK_JSON"; M12="$(omain "$PACKORIGIN")"
FT_AUTONOMY_STATE_DIR="$BSTATE" bash "$AUT" approve-merge "$M12" >/dev/null 2>&1   # PR head 가 아닌 sha 로 승인
AP_SHA="$M12" land "$LAND"; AP_SHA=""
[ "$rc" = 1 ] && [[ "$out" == *"승인 sha"* ]] && [ "$(omain "$PACKORIGIN")" = "$M12" ]; ck "ⓖ3 교차 리포 · 다른 sha 승인 → REJECT · 착지 0" $?

# ══ ⓕ --repo 없음(부른 리포 자신 · origin 은 로컬 경로) = 지금 그대로 · 원장 줄 바이트 동일(base 대조)
mkpr "$BYZ" "$BYZ_ORIGIN" 7 "$BYZ_JSON"; B7="$PRSHA"; MB="$(omain "$BYZ_ORIGIN")"
: > "$STUB_LOG"; out="$(cd "$BYZ" && bash "$LAND" 7 --approve-sha "$B7" 2>&1)"; rc=$?
L_NEW="$(mled)"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain "$BYZ_ORIGIN")" != "$MB" ] && ! grep -q -- ' -R ' "$STUB_LOG"; ck "ⓕ --repo 없음 = 지금 그대로 LANDED · gh -R 0" $?
[ "$(head -n1 "$BSTATE/base-head")" = "$(omain "$BYZ_ORIGIN")" ]; ck "ⓕ2 같은 리포는 기준 헤드도 지금 그대로(base-head)" $?
mkpr "$BYZ" "$BYZ_ORIGIN" 8 "$BYZ_JSON"; B8="$PRSHA"; MB8="$(omain "$BYZ_ORIGIN")"
LN0="$(grep -c . "$BSTATE/merge-gate.log" 2>/dev/null | tr -d ' ')"
out="$(cd "$BYZ" && bash "$T/base/ft-merge-land.sh" 8 --approve-sha "$B8" 2>&1)"; rc=$?
LN1="$(grep -c . "$BSTATE/merge-gate.log" 2>/dev/null | tr -d ' ')"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain "$BYZ_ORIGIN")" != "$MB8" ] && [ "${LN1:-0}" -gt "${LN0:-0}" ]; ck "ⓕ3a 전판이 «실제로» 착지했다(rc0·LANDED·main 전진·원장 +1 — 아니면 아래 비교는 무효)" $?
[ -n "$L_NEW" ] && [ "$(mled)" = "$L_NEW" ]; ck "ⓕ3 CROSS=0 원장 줄 = 전판과 바이트 동일(repo= 칸 포함 · 시각·sha·PR번호만 가림)" $?

# ══ ⓐ7/ⓐ8 승인 폴더 = 정식 리졸버(LIVE_ROOT) — 공용 루트에만 승인이 있으면 착지 0
mkrepo "$T/byz2"; B2="$T/byz2/w"; mkdir -p "$T/live2/.fable-team/state" "$B2/.fable-team/state" "$B2/.fable-team"
printf '%s\n' "$T/live2" > "$B2/.fable-team/LIVE_ROOT"
mkrepo "$T/pack3"; P3="$T/pack3/w"; P3ORIGIN="$T/pack3/origin.git"
git -C "$P3" remote set-url origin git@github.com:fake/pack3.git
mkpr "$P3" "$P3ORIGIN" 21 "$T/pack3.json"; P21="$PRSHA"; M21="$(omain "$P3ORIGIN")"
FT_AUTONOMY_STATE_DIR="$B2/.fable-team/state" bash "$AUT" approve-merge "$P21" >/dev/null 2>&1   # 승인은 «공용 루트» 에만
: > "$STUB_LOG"; out="$(cd "$B2" && env -u FT_ROOT -u FT_AUTONOMY_STATE_DIR PACK_ORIGIN="$P3ORIGIN" PACK_JSON="$T/pack3.json" bash "$LAND" 21 --approve-sha "$P21" --repo "$P3" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"승인 파일 없음"* ]] && [ "$(omain "$P3ORIGIN")" = "$M21" ] && [ ! -s "$STUB_LOG" ]; ck "ⓐ7 env 없음 · 승인이 공용 루트에만 → REJECT(공용 루트를 승인 폴더로 쓰지 않는다)" $?
FT_AUTONOMY_STATE_DIR="$T/live2/.fable-team/state" bash "$AUT" approve-merge "$P21" >/dev/null 2>&1   # 정식 상태 폴더에도 승인
out="$(cd "$B2" && env -u FT_ROOT -u FT_AUTONOMY_STATE_DIR PACK_ORIGIN="$P3ORIGIN" PACK_JSON="$T/pack3.json" bash "$LAND" 21 --approve-sha "$P21" --repo "$P3" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain "$P3ORIGIN")" != "$M21" ]; ck "ⓐ8 대조 · 정식 상태 폴더(LIVE_ROOT)에 승인 → LANDED(리졸버 하나만 쓴다)" $?

# ══ 키트 사본·줄 수
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 2 cmp0" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
bash -n "$BIN/ft-merge-lib.sh"; ck "bash -n ft-merge-lib.sh" $?

# ══ ⓗ 기존 merge-land·merge-gate·approval-equiv 시험 전부 PASS(base 대조 원문은 evidence 03)
for t in test_merge_land test_merge_land_state_dir test_merge_land_off_approval test_merge_land_equiv test_merge_land_push_reason test_merge_head_gate; do
  bash "$HERE/$t.sh" > "$T/$t.out" 2>&1; r=$?
  [ "$r" = 0 ]; ck "ⓗ $t rc=0 ($(grep -c '^PASS' "$T/$t.out" | tr -d ' ') PASS)" $?
done

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
