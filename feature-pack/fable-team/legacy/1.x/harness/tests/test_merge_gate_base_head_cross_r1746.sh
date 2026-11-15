#!/usr/bin/env bash
# test_merge_gate_base_head_cross_r1746.sh — r1746 · «다른 리포» 판정 = 원장 루트(rt) 기준 · 게이트 단독 기본 기준 헤드 = fm_land_ctx 4번째 칸 · 승인 루트(LIVE_ROOT) 한 함수
#   반례 ①~⑧ (카드 design/harness/indices/*/r1746-merge-gate-base-head-cross-repo.md) + 변이 M1~M3(사본 · 변이마다 원본 대조 1회)
#   임시 리포: 원장(BYZ 꼴 · LIVE_ROOT → git worktree) · 대상(팩 꼴 · origin = git@github.com:yoonhwan/pack.git · 가짜 ssh 로 전송은 로컬 bare)
#   실 gh·실 원격·실 알림 0(FT_CRITICAL_OFF=1 · gh 스텁) · sleep 0 · 70초 안 · R1746_BIN = 기준판 대조용 bin 폴더
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R1746_BIN:-$HERE/../bin}"; T0=$SECONDS
. "$HERE/_merge_fixture.sh"
unset FT_ROOT FT_AUTONOMY_STATE_DIR FT_ROOTS_TSV FT_NANO_PREFIX FT_SEATS_JSON FT_NANO_LEDGER_WT FT_BIN
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r1746.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/out"
export FT_CRITICAL_OFF=1 FT_AUTONOMY_LEVEL=each FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/stub/noop" FT_HEAD_LAG_EVENT_S=0
cat > "$T/stub/ssh" <<'EOF'
#!/bin/bash
exec bash -c "$(printf '%s' "${!#}" | sed -E "s|'[^']*'|'$PACK_ORIGIN'|")"
EOF
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"; exit 0\n' > "$T/stub/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export GIT_SSH_COMMAND="$T/stub/ssh" PACK_ORIGIN="$T/pack.git"

# 원장 리포(BYZ 꼴): main 커밋 1 · LIVE_ROOT → detached worktree · 자기 base-head = 원장 sha(팩에 없는 객체)
BYZ="$T/byz"; LIVE="$BYZ/.worktrees/live"; mkdir -p "$BYZ"; git init -q -b main "$BYZ"
git -C "$BYZ" config user.name t; git -C "$BYZ" config user.email t@t; git -C "$BYZ" config commit.gpgsign false
printf '.worktrees/\n.fable-team/\n' > "$BYZ/.gitignore"; echo byz > "$BYZ/byz.txt"; cm "$BYZ" "byz base"; BS="$(sha "$BYZ" HEAD)"
git -C "$BYZ" worktree add -q --detach "$LIVE" 2>/dev/null
mkdir -p "$BYZ/.fable-team/state" "$LIVE/.fable-team/state"; printf '%s\n' "$LIVE" > "$BYZ/.fable-team/LIVE_ROOT"
printf '%s\n' "$BS" > "$BYZ/.fable-team/state/base-head"
# 대상 리포(팩 꼴)
git init -q --bare -b main "$PACK_ORIGIN"; PK="$T/pk"; git clone -q "$PACK_ORIGIN" "$PK" 2>/dev/null
git -C "$PK" config user.name t; git -C "$PK" config user.email t@t; git -C "$PK" config commit.gpgsign false
git -C "$PK" symbolic-ref HEAD refs/heads/main; printf 'a1\n' > "$PK/a.txt"; printf '.fable-team/\n' > "$PK/.gitignore"; cm "$PK" "pack base"; printf 'a2\n' > "$PK/a2.txt"; cm "$PK" "pack 2"   # main 2커밋 — mkpr old(main~1) 자리
git -C "$PK" remote set-url origin git@github.com:yoonhwan/pack.git
git -C "$PK" push -q origin main main:ops/main-base; git -C "$PK" fetch -q origin; PM0="$(sha "$PK" HEAD)"
TAIL="$BYZ/.fable-team/state/base-head-yoonhwan-pack"; printf '%s\n' "$PM0" > "$TAIL"
git -C "$PK" checkout -q -b c1; echo c1 > "$PK/c1.txt"; cm "$PK" "cand 1"; S1="$(sha "$PK" HEAD)"; git -C "$PK" push -q origin c1; git -C "$PK" checkout -q main
echo "INFO 픽스처 $((SECONDS - T0))s"

ctx() { out="$(cd "$1" && FT_ROOT="$BYZ" bash -c '. "$0"; fm_land_ctx "$1" origin "$FT_ROOT" main' "${LB:-$BIN}/ft-merge-lib.sh" "$PK" 2>&1)"; rc=$?; }
c1() { ctx "$PK"; [ "$rc" = 0 ] && [ "$out" = "$BYZ|1|yoonhwan/pack|$TAIL|$PK" ]; }
# ① cross = 원장 루트 기준 — cwd 3가지(대상·git 밖·원장) 모두 같은 줄
c1; ck "① cwd=대상(팩) → cross=1 · base-head-yoonhwan-pack(기준판 = cross=0 · base-head = Red)" $?
ctx "$T/out"; [ "$rc" = 0 ] && [ "$out" = "$BYZ|1|yoonhwan/pack|$TAIL|$PK" ]; ck "① cwd=git 밖 → 같은 줄" $?
ctx "$BYZ"; [ "$rc" = 0 ] && [ "$out" = "$BYZ|1|yoonhwan/pack|$TAIL|$PK" ]; ck "① cwd=원장 → 같은 줄" $?

gate() { out="$(cd "$1" && shift && bash "${GB:-$BIN/ft-merge-gate.sh}" "$@" 2>&1)"; rc=$?; }
# ② 게이트 단독(--base-head-file 없음) · FT_ROOT=원장 · cwd=팩 → 팩 꼬리 파일 sha 로 검사 = ALLOW
c2() { FT_ROOT="$BYZ" gate "$PK" "$S1" --repo "$PK"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && ! [[ "$out" == *"객체 없음"* ]]; }
c2; ck "② 게이트 단독 → 팩 꼬리 기준 헤드 · ALLOW(기준판 = DENY 객체 없음 = Red)" $?
# ③ 대상 원격이 github owner/name 아님(cross=1) → DENY 판정 불가 rc1
PK2="$T/pk2"; git clone -q "$PACK_ORIGIN" "$PK2" 2>/dev/null
c3() { FT_ROOT="$BYZ" gate "$PK2" "$S1" --repo "$PK2"; [ "$rc" = 1 ] && [ "$out" = "DENY 기준 헤드 판정 불가 — 대상 리포 owner/name 못 풂" ]; }
c3; ck "③ owner/name 못 풂 → «DENY 기준 헤드 판정 불가 — 대상 리포 owner/name 못 풂» rc1 · 통과 0" $?
# ④ FT_ROOT 없음 · cwd=대상 → 같은 리포 경로 바이트 그대로(main · ops/main-base)
mkdir -p "$PK/.fable-team/state"; echo zz > "$PK/.fable-team/state/base-head"
gate "$PK" "$S1" --repo "$PK"; [ "$rc" = 1 ] && [ "${out%%$'\n'*}" = "DENY 기준 헤드 파일 손상(40hex 아님): $PK/.fable-team/state/base-head" ]; ck "④ 같은 리포 main → <대상>/.fable-team/state/base-head 그대로" $?
echo zz > "$PK/.fable-team/state/base-head@ops-main-base"
gate "$PK" "$S1" --repo "$PK" --target ops/main-base; [ "$rc" = 1 ] && [ "${out%%$'\n'*}" = "DENY 기준 헤드 파일 손상(40hex 아님): $PK/.fable-team/state/base-head@ops-main-base" ]; ck "④ 대상 가지 ops/main-base → base-head@ops-main-base 그대로" $?
printf '%s\n' "$PM0" > "$PK/.fable-team/state/base-head"; gate "$PK" "$S1" --repo "$PK"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]]; ck "④ 같은 리포 정상 기준 헤드 → ALLOW" $?
rm -f "$PK/.fable-team/state/base-head" "$PK/.fable-team/state/base-head@ops-main-base"
echo "INFO 게이트 사례 $((SECONDS - T0))s"
# 변이(사본 · 착지 사례 앞 — 착지가 기준 헤드 꼬리 파일을 갱신한다) — 변이마다 원본으로 같은 사례 1회 더(반대 결과)
if [ -z "${R1746_BIN:-}" ]; then
  mut() { rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 - "$T/m/$1" "$2" "$3" <<'PY' || echo "FAIL 변이 패치 자리 없음 $1"
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]; s = p.read_text()
assert old in s, old; p.write_text(s.replace(old, new, 1))
PY
  }
  mut ft-merge-lib.sh "$(grep -F 'git -C "$rt" rev-parse' "$BIN/ft-merge-lib.sh")"$'\n' ''
  LB="$T/m" c1; [ $? != 0 ]; ck "M1 cross = cwd 판정으로 되돌림 → ① cwd=팩 FAIL(잡힘)" $?
  c1; ck "M1 원본 대조 → ① 통과" $?
  mut ft-merge-gate.sh 'IFS='"'"'|'"'"' read -r _ _ _ BHF _ <<<"$BHF"' 'BHF="${FT_ROOT:-$(dirname "$(G rev-parse --path-format=absolute --git-common-dir)")}/.fable-team/state/base-head"'
  GB="$T/m/ft-merge-gate.sh" c2; [ $? != 0 ]; ck "M2 게이트 기본 BHF = 옛 FT_ROOT 경로 → ② FAIL(잡힘)" $?
  c2; ck "M2 원본 대조 → ② 통과" $?
  mut ft-merge-gate.sh '|| deny "기준 헤드 판정 불가 — 대상 리포 owner/name 못 풂"' '|| BHF=""'
  GB="$T/m/ft-merge-gate.sh" c3; [ $? != 0 ]; ck "M3 fm_land_ctx rc1 → «생략» → ③ FAIL(잡힘)" $?
  c3; ck "M3 원본 대조 → ③ 통과" $?
fi
echo "INFO 변이 $((SECONDS - T0))s"

# 착지 사례 공통: PR N = 지금 main 위 커밋 1개 → refs/pull/N/head · gh 스텁 JSON
mkpr() {  # mkpr <N> [old] → PRS · old = main~1 에서 갈라 main 을 병합(F≠M — replace-ok 판정문을 실제로 읽는 길)
  git -C "$PK" fetch -q origin; git -C "$PK" checkout -q -B "pr$1" "origin/main${2:+~1}"; echo "pr$1" > "$PK/pr$1.txt"; cm "$PK" "pr $1"
  [ -z "${2:-}" ] || git -C "$PK" merge -q --no-edit origin/main
  PRS="$(sha "$PK" HEAD)"; git -C "$PK" push -q origin "pr$1:refs/pull/$1/head"; git -C "$PK" checkout -q main
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"t","body":"b","state":"OPEN","baseRefName":"main"}))' "$PRS" "$1" > "$STUB_JSON"
}
land() { out="$(cd "$PK" && bash "$BIN/ft-merge-land.sh" "$@" --repo "$PK" 2>&1)"; rc=$?; }
# ⑤ 착지 도구 · ① 꼴(cwd=팩 · FT_ROOT=원장) → 기준 헤드 = 팩 꼬리 파일(원장 base-head 면 객체 없음 REJECT)
mkpr 5; FT_ROOT="$LIVE" FT_AUTONOMY_STATE_DIR="$T/st5" bash "$BIN/ft-autonomy.sh" approve-merge "$PRS" >/dev/null 2>&1
FT_ROOT="$BYZ" FT_AUTONOMY_STATE_DIR="$T/st5" land 5 --approve-sha "$PRS"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && ! [[ "$out" == *"객체 없음"* ]]; ck "⑤ land cwd=팩 · FT_ROOT=원장 → 팩 꼬리 기준 헤드로 착지" $?
# ⑥ land FT_ROOT 없음 · cwd=팩(LIVE_ROOT → 원장 live) · --replace-ok <원장 판정문> → 판정문 리포 = 승인 루트
mkdir -p "$PK/.fable-team"; printf '%s\n' "$LIVE" > "$PK/.fable-team/LIVE_ROOT"
mkpr 6 old; FT_ROOT="$LIVE" bash "$BIN/ft-autonomy.sh" approve-merge "$PRS" >/dev/null 2>&1
mkdir -p "$BYZ/design"; printf '# DA\n\n## §2 수용\n\n판정: **APPROVE — 시험**\n\n```gate-replace\nhead %s\n```\n' "$PRS" > "$BYZ/design/DA-r1746.md"; cm "$BYZ" "DA r1746"; DA6="$(sha "$BYZ" HEAD)"
sed -i.bak "s/APPROVE — 시험/HOLD — 시험/" "$BYZ/design/DA-r1746.md"; rm -f "$BYZ/design/DA-r1746.md.bak"; cm "$BYZ" "DA r1746 HOLD"; DH6="$(sha "$BYZ" HEAD)"
gate "$PK" "$PRS" --repo "$PK" --replace-ok "design/DA-r1746.md@$DH6#§2"; [ "$rc" = 1 ] && [[ "$out" == *"replace-ok §2 APPROVE 아님"* ]]; ck "⑥ 같은 꼴 HOLD 판정문 → «APPROVE 아님» DENY(판정문을 승인 루트에서 실제로 읽음 · 기준판 = 못 읽음)" $?
land 6 --approve-sha "$PRS" --replace-ok "design/DA-r1746.md@$DA6#§2"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && ! [[ "$out" == *"못 읽음"* ]]; ck "⑥ FT_ROOT 없음 · 팩 cwd · BYZ 판정문 → 승인 루트(LIVE_ROOT)에서 읽어 착지(기준판 = 못 읽음 = Red)" $?
# ⑥b 승인 루트 = 후보 리포 자신(팩 LIVE_ROOT = 팩) → 후보 리포 폴백 0(r1741 X1) = 못 읽음 DENY
mkpr 61 old; S61="$PRS"; printf '%s\n' "$PK" > "$PK/.fable-team/LIVE_ROOT"; git -C "$PK" checkout -q -b side6 main; mkdir -p "$PK/design"
printf '# DA\n\n## §2 수용\n\n판정: **APPROVE — 가짜**\n\n```gate-replace\nhead %s\n```\n' "$S61" > "$PK/design/DA-r1746.md"; cm "$PK" "가짜 판정문"; DX="$(sha "$PK" HEAD)"; git -C "$PK" checkout -q main
gate "$PK" "$S61" --repo "$PK" --replace-ok "design/DA-r1746.md@$DX#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 판정문 못 읽음"* ]]; ck "⑥b 승인 루트 = 후보 리포 → 폴백 0 · DENY 못 읽음" $?
rm -f "$PK/.fable-team/LIVE_ROOT"
# ⑦ FT_ROOT=원장 메인 루트(LIVE_ROOT 포인터) → 승인 폴더 = LIVE_ROOT state · LIVE_ROOT 못 읽음 = 판정 불가 rc≠0
mkpr 7; FT_ROOT="$LIVE" bash "$BIN/ft-autonomy.sh" approve-merge "$PRS" >/dev/null 2>&1
FT_ROOT="$BYZ" land 7 --approve-sha "$PRS"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && ! [[ "$out" == *"승인 파일 없음"* ]]; ck "⑦ FT_ROOT=원장 메인 → 승인 폴더 = LIVE_ROOT state · 착지(기준판 = 승인 파일 없음 = Red)" $?
mkpr 8; printf 'not-abs\n' > "$BYZ/.fable-team/LIVE_ROOT"
FT_ROOT="$BYZ" land 8 --approve-sha "$PRS"; [ "$rc" = 2 ] && [[ "$out" == *"REJECT 자율 상태 폴더 해석 실패"* ]]; ck "⑦ LIVE_ROOT 못 읽음 → REJECT 자율 상태 폴더 해석 실패 rc2(추정 0)" $?
printf '%s\n' "$LIVE" > "$BYZ/.fable-team/LIVE_ROOT"
echo "INFO 착지 사례 $((SECONDS - T0))s"

# ⑧ 팩 나노 worktree(pane cwd) · FT_ROOT 없음 → 팀 env 자리 = 좌석 명부 루트(원장) (r1759 roots.tsv)
SEAT="byz-harness-nano-r1746x#0"; mkdir -p "$BYZ/.fable-team/bin-harness"
python3 -c 'import json,sys;json.dump({"_master":"m",sys.argv[2]:{"role":"nano","agent":"pi"}},open(sys.argv[1],"w"))' "$BYZ/.fable-team/seats-harness.json" "$SEAT"
printf '#!/usr/bin/env bash\nprintf "ROOT-PICK %%s\\n" "$ROOT"\nexit 0\n' > "$BYZ/.fable-team/bin-harness/harness-env.sh"
printf '# 시험 명부\nr1\t%s\t현역\torigin/main\t.\t/tmp/x1\nr2\t%s\t현역\torigin/main\t.\t/tmp/x2\n' "$PK" "$BYZ" > "$T/roots.tsv"
git -C "$PK" worktree add -q -b nano/x "$T/pkwt" main 2>/dev/null
out="$(cd "$T/pkwt" && FT_ROOTS_TSV="$T/roots.tsv" bash "$BIN/ft-nano-close.sh" "$SEAT" --result "$T/x.md" --recv 7 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"ROOT-PICK $BYZ"* ]] && ! [[ "$out" == *"팀 env 없음: $PK"* ]]; ck "⑧ 팩 나노 worktree → 팀 루트 = 명부 루트(원장) · «팀 env 없음: <팩>» 0" $?
echo "INFO 나노 닫기 $((SECONDS - T0))s"

if [ -z "${R1746_BIN:-}" ]; then
  for f in ft-merge-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-merge-land.sh ft-nano-close.sh; do cmp -s "$BIN/$f" "$HERE/../kit/fable-team/bin/$f"; ck "bin·kit cmp0 $f" $?; done
fi
echo "단계별 초: 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
