#!/usr/bin/env bash
# test_index_move_da_path_r1731.sh — r1731: 카드 이동 줄의 DA 칸이 «리포 상대 경로@HEAD10#§N» 으로 적힌다.
#   끝(카드): 판정문이 카드와 «같은 리포» 의 워크트리에 HEAD 와 같은 바이트로 커밋돼 있으면 상대 경로@HEAD10#§N ·
#     리포 밖·미커밋·HEAD 와 다름 = 지금처럼 받은 글자 그대로 · git 조회 실패 = 그대로 + INFO 1줄 · 판정 검사는 원래 경로.
#   사건(r1723 완성 줄 «DA /Users/…/feature-arch3-r1723-close/design/harness/DA-…md#§1»): 임시 워크트리가 정리되면 근거를 못 따라간다.
#   임시 리포 1 + 그 워크트리 3 + /tmp 판정문 + git 스텁만 — 실 indices·실 라이브·실 원격 쓰기 0 · sleep 0.
#   SRC=<bin 폴더> 로 옛 판(①이 Red = 기준판)·변이(M1~M3)를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R 755 "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" LC_ALL=C
mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_LAND_REF FT_TEAMS_MD FT_TRACK FT_SEATS_JSON FT_MBOX FT_MBOX_DIR FT_MBOX_SH
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-team-lib.sh "$SRC"/ft-harness-root.sh "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-canon.sh \
      "$SRC"/ft-index-move-install.sh "$SRC"/ft-index-close-landed.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py \
      "$SRC"/ft-live-install-check.sh "$SRC"/ft_live_install_check.py "$SRC"/ft_plist_env.py "$BIN/"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 하네스 루트(키트 꼴) + mbox 스텁 — 설치: 없음 카드라 라이브 대조는 안 탄다
KD="$T/pack/feature-pack/fable-team/harness"; mkdir -p "$KD/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$KD/kit/fable-team/bin/x.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub-mbox.sh"; export FT_MBOX="$T/stub-mbox.sh" FT_MBOX_SH="$T/stub-mbox.sh"
# ── 카드 리포 + 워크트리 3(판정문 자리)
CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$CR/.fable-team/state" "$CR/.fable-team/comm"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
card() { { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"
  echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$IDX/진행/$1.md"; }
verdict() { printf '# 판정문\n## %s %s — 닫힘 (CLOSE)\n닫힘 — %s — main\n' "$2" "$3" "$3" > "$1"; }
for n in 1 2 3 4 5 6 7 8; do card "k$n"; done
g "$CR" add -A; g "$CR" commit -qm c0
WT2="$T/wt2"; g "$CR" worktree add -q "$WT2" -b wt2
WT3="$T/wt#198"; g "$CR" worktree add -q "$WT3" -b wt198
WT6="$T/wt6"; g "$CR" worktree add -q "$WT6" -b wt6
mkdir -p "$WT2/design/harness" "$WT3/design/harness" "$WT6/design/harness" "$T/outside"
verdict "$WT2/design/harness/DA-1.md" "§1" k1          # ① 커밋본
verdict "$WT2/design/harness/DA-4.md" "§4" k4          # ④ 미커밋
verdict "$WT2/design/harness/DA-5.md" "§5" k5          # ⑤ 커밋 뒤 작업 트리에서 고침
verdict "$WT3/design/harness/DA-2.md" "§2" k2          # ② 경로에 # 이 든 워크트리
verdict "$WT6/design/harness/DA-6.md" "§6" k6          # ⑥ git 조회 실패
verdict "$T/outside/DA-3.md" "§3" k3                   # ③ 리포 밖
OR="$T/other"; mkdir -p "$OR/design/harness"; g "$OR" init -q -b main   # ③b «다른 리포» 안 판정문(같은 리포 아님)
verdict "$OR/design/harness/DA-3b.md" "§3b" k8; g "$OR" add -A; g "$OR" commit -qm o0
printf '# 판정문\n## §9 k7 — 닫힘 (CLOSE)\n닫힘 — k7 — main\n' > "$WT2/design/harness/DA-7.md"   # ⑦ §1 없음
g "$WT2" add design/harness/DA-1.md design/harness/DA-5.md design/harness/DA-7.md; g "$WT2" commit -qm d1
g "$WT3" add -A; g "$WT3" commit -qm d2
g "$WT6" add -A; g "$WT6" commit -qm d6
S1="$(g "$WT2" rev-parse HEAD)"; S2="$(g "$WT3" rev-parse HEAD)"; S6="$(g "$WT6" rev-parse HEAD)"
S1="${S1:0:10}"; S2="${S2:0:10}"; S6="${S6:0:10}"
printf -- '- 커밋 뒤 고친 줄\n' >> "$WT2/design/harness/DA-5.md"                            # ⑤ HEAD 와 바이트 다름

export FT_HARNESS_ROOT="$KD"
mv_() { out="$(bash "$BIN/ft-index-move.sh" "$@" 2>&1)"; rc=$?; }
rec() { grep -F ' — 진행→완성' "$IDX/완성/$1.md" 2>/dev/null | tail -1; }
DAV='· DA '

# ① 같은 리포 다른 워크트리 커밋본 → 상대 경로@HEAD10  (기준판 = 절대경로 = Red)
mv_ "$IDX/진행/k1.md" 완성 --da "$WT2/design/harness/DA-1.md#§1" --seat s
r1="$(rec k1)"; ck "① 같은 리포 워크트리 커밋본 → «design/harness/DA-1.md@$S1#§1» (rc=$rc) :: $r1" \
  "$([ "$rc" = 0 ] && [[ "$r1" == *"${DAV}design/harness/DA-1.md@$S1#§1" ]] && echo 0 || echo 1)"
# ② 경로에 # 이 든 워크트리 → 상대 경로 · 절 = «마지막 #» 뒤
mv_ "$IDX/진행/k2.md" 완성 --da "$WT3/design/harness/DA-2.md#§2" --seat s
r2="$(rec k2)"; ck "② 경로에 # 이 든 워크트리 → «design/harness/DA-2.md@$S2#§2» (rc=$rc) :: $r2" \
  "$([ "$rc" = 0 ] && [[ "$r2" == *"${DAV}design/harness/DA-2.md@$S2#§2" ]] && echo 0 || echo 1)"
# ③ 리포 밖 → 절대경로 그대로
mv_ "$IDX/진행/k3.md" 완성 --da "$T/outside/DA-3.md#§3" --seat s
r3="$(rec k3)"; ck "③ 리포 밖 → 받은 글자 그대로 (rc=$rc) :: $r3" \
  "$([ "$rc" = 0 ] && [[ "$r3" == *"${DAV}$T/outside/DA-3.md#§3" ]] && echo 0 || echo 1)"
# ③b 다른 리포(같은 리포 아님) 안 판정문 → 그대로            (M2 = 리포 대조 지우면 여기서 빨강)
mv_ "$IDX/진행/k8.md" 완성 --da "$OR/design/harness/DA-3b.md#§3b" --seat s
r3b="$(rec k8)"; ck "③b 다른 리포 안 → 받은 글자 그대로 (rc=$rc) :: $r3b" \
  "$([ "$rc" = 0 ] && [[ "$r3b" == *"${DAV}$OR/design/harness/DA-3b.md#§3b" ]] && echo 0 || echo 1)"
# ④ 같은 리포 워크트리지만 미커밋 → 그대로
mv_ "$IDX/진행/k4.md" 완성 --da "$WT2/design/harness/DA-4.md#§4" --seat s
r4="$(rec k4)"; ck "④ 미커밋 판정문 → 받은 글자 그대로 (rc=$rc) :: $r4" \
  "$([ "$rc" = 0 ] && [[ "$r4" == *"${DAV}$WT2/design/harness/DA-4.md#§4" ]] && echo 0 || echo 1)"
# ⑤ 커밋 뒤 작업 트리에서 고침(HEAD 와 다름) → 그대로          (M1 = 바이트 대조 지우면 여기서 빨강)
mv_ "$IDX/진행/k5.md" 완성 --da "$WT2/design/harness/DA-5.md#§5" --seat s
r5="$(rec k5)"; ck "⑤ HEAD 와 바이트 다름 → 받은 글자 그대로 (rc=$rc) :: $r5" \
  "$([ "$rc" = 0 ] && [[ "$r5" == *"${DAV}$WT2/design/harness/DA-5.md#§5" ]] && echo 0 || echo 1)"
# ⑥ 판정문 워크트리 조회만 rc 128 스텁 → 그대로 + INFO 1줄 + 이동 rc0
SG="$T/stubgit"; mkdir -p "$SG"
printf '#!/bin/bash\np=""; for a in "$@"; do [ "$p" = "-C" ] && [ "$a" = "$STUB_FAIL_DIR" ] && { echo "fatal: not a git repository" >&2; exit 128; }; p="$a"; done\nexec %s "$@"\n' "$(command -v git)" > "$SG/git"
export STUB_FAIL_DIR="$(cd "$WT6" && pwd -P)"
chmod 755 "$SG/git"
out="$(PATH="$SG:$PATH" bash "$BIN/ft-index-move.sh" "$IDX/진행/k6.md" 완성 --da "$WT6/design/harness/DA-6.md#§6" --seat s 2>&1)"; rc=$?
r6="$(rec k6)"
ck "⑥ git 조회 실패 → 그대로 + «INFO DA 경로 정규화 불가 — 원문 그대로» + 이동 rc0 (rc=$rc) :: $r6" \
  "$([ "$rc" = 0 ] && [[ "$r6" == *"${DAV}$WT6/design/harness/DA-6.md#§6" ]] && [[ "$out" == *"INFO DA 경로 정규화 불가 — 원문 그대로"* ]] && [[ "$r6" != *"@$S6"* ]] && echo 0 || echo 1)"
# ⑦ §1 없음 → 지금과 같은 REJECT(정규화 전에 검사)
mv_ "$IDX/진행/k7.md" 완성 --da "$WT2/design/harness/DA-7.md#§1" --seat s
ck "⑦ §1 없는 판정문 → REJECT «에 절 «§1» 없음» · 카드 진행 그대로 (rc=$rc) :: $out" \
  "$([ "$rc" = 1 ] && [[ "$out" == *"에 절 «§1» 없음"* ]] && [ -f "$IDX/진행/k7.md" ] && echo 0 || echo 1)"
# ⑧ 회귀 0 — 판정 검사는 «원래 경로»(A4): 판정문이 상대 경로로 적혀도 §검사·닫힘 검사는 받은 절대경로로 했다(①②가 이미 통과) · DA 원장 값도 원래 글자
ck "⑧ 이동 줄만 바뀐다 — 카드 안 «DA <상대경로>» 1줄 · 판정 검사는 원래 경로(r1 · r2 rc0 이 그 증거)" \
  "$([ "$(grep -c "design/harness/DA-1.md@$S1#§1" "$IDX/완성/k1.md")" = 1 ] && echo 0 || echo 1)"
# ⑨ 오염 0 — 카드 리포 변경은 indices/ 폴더와 원장(state/) 밖으로 새지 않는다
ods="$(g "$CR" status --porcelain -z | tr '\0' '\n' | sed 's/^.. //' | grep -vE '^(design/harness/indices/|\.fable-team/)' | grep -v '^$' | head -3)"
ck "⑨ 카드 리포 오염 0 — 변경은 indices/ · .fable-team/ 안뿐 :: $ods" "$([ -z "$ods" ] && echo 0 || echo 1)"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
