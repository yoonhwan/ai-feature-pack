#!/usr/bin/env bash
# test_index_move_landed_repo.sh — r937: 착지 sha 의 «진짜 리포» 판정 1곳(ft_landed_repo · ft-team-lib.sh) 을 설치·정본·close-landed 세 게이트가 같이 쓴다.
#   사건(카드 r937 · master#114 #169127): 하네스 카드는 BYZ 리포에 있지만 코드는 대개 팩 리포에 착지한다.
#     설치 게이트는 sha 를 팩에서(«git rev-parse --verify 실패»), 정본 게이트는 BYZ origin/main 에서(«랜딩 안 됨») 찾아
#     어느 쪽에 착지한 카드든 한 게이트가 막았다 → 착지가 끝난 카드 120여 장을 닫을 수 없다.
#   임시 리포 2개(BYZ 꼴 · 팩 꼴 · 각 origin/main) + 카드·판정문 픽스처만 — 실 라이브·실 원격·실 indices 쓰기 0.
#   SRC=<bin 폴더> 로 옛 판(전 빨강)·변이(리포 판정 끔 · 표식 대조 끔)를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"
mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_LAND_REF
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-team-lib.sh "$SRC"/ft-harness-root.sh "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-install.sh \
      "$SRC"/ft-index-move-canon.sh "$SRC"/ft-index-close-landed.sh "$SRC"/ft_da_hold_gate.py \
      "$SRC"/ft-live-install-check.sh "$SRC"/ft_live_install_check.py "$SRC"/ft_plist_env.py "$BIN/"
. "$BIN/ft-team-lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 팩 리포(하네스 키트 꼴) — 키트 파일 1개 + LIVE-MAP · origin/main = tip
PR="$T/pack"; KD="$PR/feature-pack/fable-team/harness"
mkdir -p "$KD/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$KD/kit/fable-team/bin/x.sh"; chmod 755 "$KD/kit/fable-team/bin/x.sh"
{ printf 'LIVE-MAP.tsv\tskip\t-\t지도 자신\n'; printf 'fable-team/bin/*\tbin\t$FT_BIN\tmaster: install.sh --apply\n'; } > "$KD/kit/LIVE-MAP.tsv"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0; P0="$(g "$PR" rev-parse HEAD)"
printf '#!/bin/bash\necho v2\n' > "$KD/kit/fable-team/bin/x.sh"; g "$PR" add -A; g "$PR" commit -qm p1; P1="$(g "$PR" rev-parse HEAD)"
g "$PR" update-ref refs/remotes/origin/main "$P1"
FTB="$T/live"; mkdir -p "$FTB"; printf '#!/bin/bash\necho v2\n' > "$FTB/x.sh"; chmod 755 "$FTB/x.sh"   # 라이브 = tip

# ── 카드 리포(BYZ 꼴) — 카드·정본·origin/main(자기 main 만)
CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$CR/docs/architect"
g "$CR" init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
printf '## 절A 제목\nv1\n' > "$CR/docs/architect/X.md"
card() { local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: ${2:-없음}"
    [ "${2:-없음}" = 있음 ] && echo "- 실사건: 라이브 대조 1회 · 증거 mbox #169127"; } > "$f"; echo "$f"; }
cning="$(card kbyz 있음)"; cnno="$(card kbyz2 없음)"; cpk="$(card kpack 없음)"
g "$CR" add -A; g "$CR" commit -qm c0; C0="$(g "$CR" rev-parse HEAD)"
echo x >> "$CR/docs/architect/X.md"; g "$CR" commit -qam c1; C1="$(g "$CR" rev-parse HEAD)"
g "$CR" update-ref refs/remotes/origin/main "$C1"
# 판정문 — 카드별 착지 행(표식 = main = 카드 리포 · main(팩) = 팩 리포)
verdict() { local f="$CR/design/harness/DA-r937.md" sec="$1" stem="$2" line="$3"
  printf '# 판정문\n## %s 닫힘: %s\n- %s\n' "$sec" "$stem" "$line" > "$f"; echo "$f"; }
# 팩 객체를 카드 리포로 fetch 해 둔 꼴(실사건 · r581) — P1 은 두 리포에 다 있다
g "$CR" fetch -q "$PR" '+refs/heads/main:refs/remotes/pack/main'
# fetch «뒤» 에 생긴 팩 커밋 = 카드 리포에 없는 팩 sha(표식 오기 시험용)
printf 'note\n' > "$PR/README.md"; g "$PR" add -A; g "$PR" commit -qm p2; P2="$(g "$PR" rev-parse HEAD)"; g "$PR" update-ref refs/remotes/origin/main "$P2"

# ⓐ 리포 판정 — 한 곳에만 / 둘 다(표식·기본) / 둘 다 없음 / 표식 어긋남
out="$(ft_landed_repo "$C0" "$CR" "$PR" "")"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$CR" ] && [ "${out##*$'\t'}" = "$C0" ] && ck "ⓐ 카드 리포에만 → 카드 리포" 0 || ck "ⓐ 카드 리포에만 → 카드 리포" 1
out="$(ft_landed_repo "$P0" "$CR" "$PR" "")"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$PR" ] && ck "ⓐ 팩 리포에만 → 팩 리포(카드 리포가 fetch 해 둬도)" 0 || ck "ⓐ 팩 리포에만 → 팩 리포" 1
out="$(ft_landed_repo "$P1" "$CR" "$PR" "닫힘 — kpack — main \`$P1\`")"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$CR" ] && ck "ⓐ 둘 다 + 표식 main → 카드 리포" 0 || ck "ⓐ 둘 다 + 표식 main → 카드 리포" 1
out="$(ft_landed_repo "$P1" "$CR" "$PR" "닫힘 — kpack — main(팩) \`$P1\`")"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$PR" ] && ck "ⓐ 둘 다 + 표식 main(팩) → 팩 리포" 0 || ck "ⓐ 둘 다 + 표식 main(팩) → 팩 리포" 1
out="$(ft_landed_repo "$P1" "$CR" "$PR" "")"; rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$PR" ] && ck "ⓐ 둘 다 + 표식 없음 → 팩(카드 리포 fetch 관례 · r581)" 0 || ck "ⓐ 둘 다 + 표식 없음 → 팩" 1
out="$(ft_landed_repo "$(printf '0%.0s' {1..40})" "$CR" "$PR" "")"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == "REJECT"*"어느 리포에서도 못 찾음"* ]] && ck "ⓐ 둘 다 없음 → REJECT «어느 리포에서도 못 찾음»" 0 || ck "ⓐ 둘 다 없음 → REJECT" 1
out="$(ft_landed_repo "$C0" "$CR" "$PR" "닫힘 — kbyz — main(팩) \`$C0\`")"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"표식 오기"* ]] && ck "ⓐ 표식 main(팩) 인데 팩에 없음 → REJECT(표식 오기 숨김 0)" 0 || ck "ⓐ 표식 오기(팩) → REJECT" 1
out="$(ft_landed_repo "$P2" "$CR" "$PR" "닫힘 — kpack — main \`$P2\`")"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"표식 오기"* ]] && ck "ⓐ 표식 main 인데 카드 리포에 없음 → REJECT(표식 오기 숨김 0)" 0 || ck "ⓐ 표식 오기(카드) → REJECT" 1

# ⓑ 세 게이트가 ⓐ 의 같은 리포·같은 ref 를 쓴다
export FT_HARNESS_ROOT="$KD"
# ⓑ1 카드(BYZ) 착지 + 설치: 있음 = 통과 — 설치 대조는 라이브 전수(--all) · sha 를 팩에서 찾지 않는다
export FT_BIN="$FTB" FT_INSTALL_CHECK="$BIN/ft-live-install-check.sh"
out="$(bash "$BIN/ft-index-move-install.sh" "$cning" --landed "$C0" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"INFO 착지 리포 = 카드 리포"* ]] && [[ "$out" == *"OK 설치 확인"*"OK n=1"* ]] && ck "ⓑ 카드 착지 + 설치: 있음 → 라이브 전수 대조 통과 rc0" 0 || ck "ⓑ 카드 착지 + 설치: 있음 → 통과" 1
# ⓑ2 팩 착지 + 정본 영향 없음 = 통과 · 카드 리포 origin/main 에는 그 sha 가 «없다» — 카드 리포로 검사하면 빨강이어야 한다
dv="$(verdict §1 kpack "닫힘 — kpack — main(팩) \`$P1\`")"
out="$(printf '## §1 닫힘: kpack\n- 닫힘 — kpack — main(팩) \`%s\`\n' "$P1" | bash "$BIN/ft-index-move-canon.sh" "$cpk" "$CR" "$P1")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'"정본 영향 없음:"* ]] && ck "ⓑ 팩 착지 + 정본 영향 없음 → 정본 게이트 OK(팩 origin/main 조상)" 0 || ck "ⓑ 팩 착지 + 정본 영향 없음 → OK" 1
out="$(printf '## §1 닫힘: kpack\n- 닫힘 — kpack — main \`%s\`\n' "$P1" | bash "$BIN/ft-index-move-canon.sh" "$cpk" "$CR" "$P1")"; rc=$?
[[ "$out" == "REJECT"$'\t'"랜딩 안 됨"* ]] && ck "ⓑ 표식 main + 두 리포에 있는 sha → 카드 리포로 풀려 «랜딩 안 됨»(표식이 리포를 가른다)" 0 || ck "ⓑ 표식 main → 랜딩 안 됨" 1
# ⓑ3 close-landed 조상 검사도 같은 리포 — 팩 행(main(팩)) 은 팩 origin/main 으로 · 카드 행(main) 은 카드 origin/main 으로
cp "$cnno" "$IDX/진행/cside.md"
echo y >> "$CR/docs/architect/X.md"; g "$CR" commit -qam c-side; CSIDE="$(g "$CR" rev-parse HEAD)"; g "$CR" reset -q --hard HEAD~1   # 가지에만 있는 커밋 = origin/main 조상 아님
printf '# 판정문\n## §1 닫힘: kpack\n- 닫힘 — kpack — main(팩) `%s`\n## §2 닫힘: cside\n- 닫힘 — cside — main `%s`\n## §3 닫힘: kbyz2\n- 닫힘 — kbyz2 — main(팩) `%s`\n' "$P1" "$CSIDE" "$C0" > "$CR/design/harness/DA-row.md"
out="$(bash "$BIN/ft-index-close-landed.sh" "$CR/design/harness/DA-row.md" --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"| §1 | kpack | 진행 | ok |"* ]] && [[ "$out" == *"| §2 | cside | 진행 | no |"*"not-ancestor"* ]] && [[ "$out" == *"| §3 | kbyz2 | 진행 | no |"*"not-found"* ]] \
  && ck "ⓑ close-landed: 팩 행 = 팩 ref(ok) · 카드 행 = 카드 ref(no) · 표식 어긋남 = not-found" 0 || ck "ⓑ close-landed 조상 검사 리포" 1

# ⓒ 표식과 실제 리포가 어긋나면 정본 게이트도 REJECT(표식 오기 숨김 0)
out="$(printf '## §1 닫힘: kbyz2\n- 닫힘 — kbyz2 — main(팩) \`%s\`\n' "$C0" | bash "$BIN/ft-index-move-canon.sh" "$cnno" "$CR" "$C0")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"표식 오기"* ]] && ck "ⓒ 표식 main(팩) ↔ 실제 카드 리포 → REJECT" 0 || ck "ⓒ 표식 어긋남 → REJECT" 1

# ⓓ 카드(BYZ) 착지 + 설치: 없음 = 지금 통과하던 길 회귀 0
out="$(bash "$BIN/ft-index-move-install.sh" "$cnno" --landed "$C0" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"설치: 없음"* ]] && ck "ⓓ 카드 착지 + 설치: 없음 → 통과 rc0(회귀 0)" 0 || ck "ⓓ 카드 착지 + 설치: 없음 → 통과" 1

# ⓔ 오염 0 — 두 리포 변경 없음
[ -z "$(g "$CR" status --porcelain | grep -v 'design/harness/')" ] && [ -z "$(g "$PR" status --porcelain)" ] && ck "ⓔ 리포 오염 0(design/harness 픽스처 밖 변경 0 · 팩 무변경)" 0 || ck "ⓔ 리포 오염 0 :: $(g "$CR" status --porcelain | grep -v 'design/harness/' | head -3)" 1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
