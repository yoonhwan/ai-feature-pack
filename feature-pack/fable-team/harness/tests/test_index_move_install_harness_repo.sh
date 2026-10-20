#!/usr/bin/env bash
# test_index_move_install_harness_repo.sh — r581: 완성 이동 설치 게이트가 하네스 파일 대조에 넘기는 리포는 «하네스 루트의 리포» 다.
#   사건(arch 112 실측 2026-10-21): ft-index-move-install.sh:26 이 `--repo "$WT"`(카드 워크트리)를 넘겼고, 카드 리포(BYZ)에 팩 객체
#   (refs/pack-landing/harness-main)가 들어온 뒤로는 그 리포에서 `:(glob)**/harness/kit/**` 가 걸려 ft_live_install_check.py 의
#   outside_repo() 가 fail-closed 로 막았다 = 팩 착지 카드 9장이 진행/ 에 묶임. 도구는 맞게 막았고 «문»이 틀린 리포를 넘겼다.
#   임시 리포 2개(하네스 리포 = 팩 꼴 경로 · 카드 리포 = 그 객체를 fetch 해 둔 꼴) + 가짜 검사 도구 주입. 실 라이브·실 원격·쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"   # 정본 = 팩 키트
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; mkdir -p "$HOME"; FTB="$T/ftbin"; mkdir -p "$FTB"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR

# ── 도구 사본 1벌(게이트 + 대조 도구) · 회수 불가 루트 시험용 사본 1벌(ⓓ)
mkbin() { local d="$1"; mkdir -p "$d"; cp -p "$SRC/ft-index-move-install.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_plist_env.py" \
  "$SRC/ft-live-install-check.sh" "$SRC/ft_live_install_check.py" "$d/"; }
BIN="$T/bin"; mkbin "$BIN"
GATE="$BIN/ft-index-move-install.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 하네스 리포(팩 꼴 경로: feature-pack/fable-team/harness/kit/…) — 범위 A..B 가 키트 파일 1개를 고친다
HR="$T/hrepo"; mkdir -p "$HR/feature-pack/fable-team/harness/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"; chmod 755 "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"
printf 'fable-team/bin/*\tbin\t$FT_BIN\tmaster: install.sh --apply\n' > "$HR/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv"
g "$HR" init -q -b main; g "$HR" add -A; g "$HR" commit -qm c0; A="$(g "$HR" rev-parse HEAD)"
printf '#!/bin/bash\necho v2\n' > "$HR/feature-pack/fable-team/harness/kit/fable-team/bin/x.sh"
g "$HR" add -A; g "$HR" commit -qm c1; B="$(g "$HR" rev-parse HEAD)"
g "$HR" update-ref refs/remotes/origin/main "$B"
HRKIT="$HR/feature-pack/fable-team/harness"                     # 하네스 코드 루트(kit/ 실재)
printf '#!/bin/bash\necho v2\n' > "$FTB/x.sh"; chmod 755 "$FTB/x.sh"   # 라이브 = tip

# ── 카드 리포(다른 리포 · 하네스 리포 객체를 fetch 해 둔 꼴 = BYZ 실사건)
CR="$T/cardrepo"; mkdir -p "$CR/design/harness/indices/진행"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
CARDC="$CR/design/harness/indices/진행/t.md"
printf '# 인덱스: t\n- 설치: 있음\n- 실사건: 카드 이동 · 증거 mbox #123416\n## 상태\n- x\n' > "$CARDC"
g "$CR" add -A; g "$CR" commit -qm card
g "$CR" fetch -q "$HR" '+refs/heads/main:refs/remotes/pack/main'
[ "$(g "$CR" rev-parse -q --verify "$A^{commit}")" = "$A" ] && [ "$(g "$CR" rev-parse -q --verify "$B^{commit}")" = "$B" ]

# ── 가짜 검사 도구: 받은 인자를 그대로 기록하고 rc0
FAKE="$T/fake-chk.sh"; ARGS="$T/args.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$ARGS" > "$FAKE"; chmod 755 "$FAKE"
PD="$T/pending"; mkdir -p "$PD"; : > "$PD/$B.txt"

# ⓐ 게이트가 검사 도구에 넘기는 리포 = 하네스 루트의 리포(카드 워크트리 아님)
out="$(FT_INSTALL_CHECK="$FAKE" FT_INSTALL_PENDING_DIR="$PD" FT_HARNESS_ROOT="$HRKIT" bash "$GATE" "$CARDC" --landed "$A..$B" 2>&1)"; rc=$?
got="$(cat "$ARGS" 2>/dev/null)"
if [ "$rc" = 0 ] && ! [[ "$got" == *"--repo"* ]]; then ck "ⓐ 검사 도구에 --repo 를 넘기지 않는다(도구 기본값 = 하네스 루트 리포) — got «${got}»" 0; else ck "ⓐ …got «${got}»" 1; fi
if [ ! -e "$PD/$B.txt" ]; then ck "ⓐ 통과 시 install-pending 파일 제거 그대로" 0; else ck "ⓐ 통과 시 install-pending 파일 제거 그대로" 1; fi

# ⓑ 실제 대조 도구로 같은 꼴 — 카드 리포를 넘기면 ERROR(옛 판 재현) · 기본값이면 OK
: > "$ARGS"
out="$(FT_BIN="$FTB" FT_INSTALL_CHECK="$BIN/ft-live-install-check.sh" FT_INSTALL_PENDING_DIR="$PD" FT_HARNESS_ROOT="$HRKIT" bash "$GATE" "$CARDC" --landed "$A..$B" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [[ "$out" == *"OK 설치 확인"* ]] && [[ "$out" == *"OK n=1"* ]]; then ck "ⓑ 하네스 루트 리포로 대조 → OK n=1 rc0" 0; else ck "ⓑ 하네스 루트 리포로 대조 → OK n=1 rc0" 1; fi
out="$(cd "$HR" && FT_BIN="$FTB" FT_HARNESS_ROOT="$HRKIT" bash "$BIN/ft-live-install-check.sh" --range "$A..$B" --repo "$CR" 2>&1)"; rc=$?
if [ "$rc" = 3 ] && [[ "$out" == *"--repo("*"밖"* ]] && [[ "$out" == *"harness/kit/"* ]]; then ck "ⓑ 변이: 카드 리포를 --repo 로 넘기면 ERROR rc3(옛 판 재현 · fail-closed 그대로)" 0; else ck "ⓑ 변이: 카드 리포를 --repo 로 넘기면 ERROR rc3" 1; fi

# ⓒ 설치: 없음 카드 = 대조 호출 0 · 그대로 통과
: > "$ARGS"
printf '# 인덱스: n\n- 설치: 없음\n## 상태\n- x\n' > "$CR/design/harness/indices/진행/n.md"
out="$(FT_INSTALL_CHECK="$FAKE" FT_INSTALL_PENDING_DIR="$PD" FT_HARNESS_ROOT="$HRKIT" bash "$GATE" "$CR/design/harness/indices/진행/n.md" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [[ "$out" == *"설치: 없음"* ]] && [ ! -s "$ARGS" ]; then ck "ⓒ 설치: 없음 → 대조 호출 0 · 통과 rc0" 0; else ck "ⓒ 설치: 없음 → 대조 호출 0 · 통과 rc0" 1; fi

# ⓓ 하네스 루트를 못 풀면 REJECT 그대로(통과로 후퇴 0)
BIN2="$T/bin2"; mkbin "$BIN2"
g "$HR" update-ref refs/remotes/origin/main "$B"
out="$(cd "$T" && env -u FT_HARNESS_ROOT FT_INSTALL_PENDING_DIR="$PD" bash "$BIN2/ft-index-move-install.sh" "$CARDC" --landed "$A..$B" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && [[ "$out" == *"REJECT"* ]] && [[ "$out" == *"하네스 루트를 못 풂"* ]]; then ck "ⓓ 하네스 루트 못 풂 → REJECT rc1(후퇴 0)" 0; else ck "ⓓ 하네스 루트 못 풂 → REJECT rc1(후퇴 0)" 1; fi

# ⓔ 오염 0
if [ "$(g "$CR" config --get core.bare)" != true ] && [ -d "$CR/design/harness" ]; then ck "core.bare 오염 0 · 카드 리포 무변경" 0; else ck "core.bare 오염 0 · 카드 리포 무변경" 1; fi
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
