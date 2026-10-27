#!/usr/bin/env bash
# r895 landed.sh <리포> <worktrees.tsv | 경로 목록 파일> <출력 tsv> — 착지 보강(읽기 전용 · 삭제 0).
#   measure.sh 의 «조상» 판정은 squash 착지를 «아님» 으로 센다. 그래서 «내용 착지» 를 따로 본다:
#     가지(또는 사본 HEAD)가 merge-base 뒤에 바꾼 파일이 지금 기준(origin/main)과 바이트가 같으면 = 내용착지(squash·대체 착지 포함)
#     바꾼 파일이 0 이면 = 변경없음 · 하나라도 다르면 = 미착지(<다른 파일 수>) · 7초 넘으면 = 못잼
#   입력이 경로만(사본)이면 HEAD 는 그 사본에서 읽는다(사본의 리포 등록이 사라졌으면 «못잼»).
#
# r895 landed.sh --branches <리포> <출력 tsv> [카드 루트] — «끝난 가지 보관 이동 대상» 후보(판정 2354 · 읽기 전용 · 이동 실행 0).
#   조건 3개를 모두 만족해야 보관 이동 대상이다: ①착지(nano 가지가 origin/main 조상) ②어느 워크트리도 안 씀 ③카드가 완성/·완성후/·아카이브/ 에 있음
#   카드 대조 = 파일 이름(카드 이름이 가지 줄기와 같거나, 줄기로 시작 · 나노 작업 폴더가 이름을 43자에서 자르므로 앞자리 대조 · -rN 꼬리 무시).
#   카드 루트 기본값 = <리포>/.worktrees/harness-ops/design (카드 명단의 라이브 정본 · 없으면 <리포>/design) · 카드가 다른 리포에 있으면 4번째 인자로 준다(예: 팩 가지 대조 = BYZ-Agents 카드).
#   칸: branch · head · card(완성카드|진행카드|확인불가) · card_path  — 카드를 못 찾은 가지는 확정하지 않고 «확인불가» 로 남긴다(DA r1 #3).
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0

if [ "${1:-}" = "--branches" ]; then
  REPO="${2:?usage: landed.sh --branches <리포> <출력 tsv> [카드 루트]}"; OUT="${3:?usage}"
  CARD_ROOT="${4:-${R895_CARD_ROOT:-$REPO/.worktrees/harness-ops/design}}"
  [ -d "$CARD_ROOT" ] || CARD_ROOT="$REPO/design"
  g() { timeout 7 nice -n 10 git -c core.quotepath=false -C "$REPO" "$@"; }
  BASE=origin/main; g rev-parse -q --verify "$BASE" >/dev/null || BASE=main
  WT="$(g worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"
  CARDS="$(find "$CARD_ROOT" -maxdepth 4 -path '*/indices/*/*.md' 2>/dev/null |
             awk -F/ '{n=$NF; sub(/\.md$/,"",n); print n"\t"$(NF-1)}')"
  { printf 'branch\thead\tcard\tcard_path\n'
    g for-each-ref --merged="$BASE" --format='%(refname:short)%09%(objectname:short)' refs/heads/nano |
    WT="$WT" CARDS="$CARDS" awk -F'\t' -v OFS='\t' '
      BEGIN {
        nb = split(ENVIRON["CARDS"], L, "\n")
        for (i = 1; i <= nb; i++) { split(L[i], a, "\t"); if (a[1] == "") continue
          nc++; cn[nc] = a[1]; dir[a[1]] = dir[a[1]] " " a[2] }
        nw = split(ENVIRON["WT"], W, "\n")
        for (i = 1; i <= nw; i++) if (W[i] != "") taken[W[i]] = 1
      }
      { if ($1 in taken) next
        s = $1; sub(/^nano\//, "", s); s2 = s; sub(/-r[0-9]+$/, "", s2)
        card = "확인불가"; path = ""
        for (i = 1; i <= nc; i++) {
          k = cn[i]
          hit = (k == s || k == s2 || (length(s) >= 15 && index(k, s) == 1) || (length(s2) >= 15 && index(k, s2) == 1))
          if (!hit) continue
          if (dir[k] ~ /(^| )(완성|완성후|아카이브)( |$)/) { card = "완성카드"; path = k; break }
          if (card == "확인불가") { card = "진행카드"; path = k }
        }
        print $1, $2, card, path
      }' \
    | sort -t"$(printf '\t')" -k3,3 -k1,1 ; } > "$OUT"
  awk -F'\t' -v out="$OUT" 'NR > 1 { n[$3]++ } END { printf "OK branches → %s (착지 nano · 워크트리 없음 %d · 완성카드 %d · 진행카드 %d · 확인불가 %d)\n", out, NR - 1, n["완성카드"], n["진행카드"], n["확인불가"] }' "$OUT"
  exit 0
fi

REPO="${1:?usage}"; IN="${2:?usage}"; OUT="${3:?usage}"
g() { timeout 7 nice -n 10 git -c core.quotepath=false -C "$REPO" "$@"; }
BASE=origin/main; g rev-parse -q --verify "$BASE" >/dev/null || BASE=main
judge() {  # $1 = sha → 칸 1개
  local h="$1" mb n diff
  mb="$(g merge-base "$h" "$BASE" 2>/dev/null)" || { echo 못잼; return; }
  [ "$mb" = "$(g rev-parse "$h" 2>/dev/null)" ] && { echo 조상; return; }
  n="$(g diff --name-only "$mb" "$h" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" = 0 ] && { echo 변경없음; return; }
  diff="$(g diff --name-only "$h" "$BASE" -- $(g diff --name-only "$mb" "$h") 2>/dev/null | wc -l | tr -d ' ')" || { echo 못잼; return; }
  [ "$diff" = 0 ] && echo "내용착지" || echo "미착지($diff/$n)"
}
printf 'path\thead\tland2\n' > "$OUT"
while IFS=$'\t' read -r p b h _; do
  [ "$p" = path ] && continue
  if [ -z "${h:-}" ]; then h="$(timeout 7 git -C "$p" rev-parse HEAD 2>/dev/null | cut -c1-10)"; fi
  [ -n "$h" ] || { printf '%s\t-\t못잼\n' "$p" >> "$OUT"; continue; }
  printf '%s\t%s\t%s\n' "$p" "$h" "$(judge "$h")" >> "$OUT"
done < "$IN"
echo "OK landed → $OUT"
