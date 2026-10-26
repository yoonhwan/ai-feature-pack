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
      "$SRC"/ft-live-install-check.sh "$SRC"/ft_live_install_check.py "$SRC"/ft_plist_env.py "$SRC"/ft_git_capped.py "$BIN/"
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
printf '# 판정문\n## §1 닫힘: kpack\n- 닫힘 — kpack — main(팩) `%s`\n## §2 닫힘: cside\n- 닫힘 — cside — main `%s`\n## §3 닫힘: kbyz2\n- 닫힘 — kbyz2 — main(팩) `%s`\n## §4 닫힘: kbyzh\n- 닫힘 — kbyzh — main(팩) `%s`\n' "$P1" "$CSIDE" "$C0" "$C0" > "$CR/design/harness/DA-row.md"
out="$(bash "$BIN/ft-index-close-landed.sh" "$CR/design/harness/DA-row.md" --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"| §1 | kpack | 진행 | ok |"* ]] && [[ "$out" == *"| §2 | cside | 진행 | no |"*"not-ancestor"* ]] && [[ "$out" == *"| §3 | kbyz2 | 진행 | no |"*"not-found"* ]] \
  && ck "ⓑ close-landed: 팩 행 = 팩 ref(ok) · 카드 행 = 카드 ref(no) · 표식 어긋남 = not-found" 0 || ck "ⓑ close-landed 조상 검사 리포" 1

# ⓒ 표식과 실제 리포가 어긋나면 정본 게이트도 REJECT(표식 오기 숨김 0)
out="$(printf '## §1 닫힘: kbyz2\n- 닫힘 — kbyz2 — main(팩) \`%s\`\n' "$C0" | bash "$BIN/ft-index-move-canon.sh" "$cnno" "$CR" "$C0")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"표식 오기"* ]] && ck "ⓒ 표식 main(팩) ↔ 실제 카드 리포 → REJECT" 0 || ck "ⓒ 표식 어긋남 → REJECT" 1

# ⓓ 카드(BYZ) 착지 + 설치: 없음 = 지금 통과하던 길 회귀 0
out="$(bash "$BIN/ft-index-move-install.sh" "$cnno" --landed "$C0" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"설치: 없음"* ]] && ck "ⓓ 카드 착지 + 설치: 없음 → 통과 rc0(회귀 0)" 0 || ck "ⓓ 카드 착지 + 설치: 없음 → 통과" 1

# ⓔ DA 보류 가드(ft_da_hold_gate.py landed_check)도 같은 리포 판정 — 팩 착지 카드 통과 · 표식 오기 REJECT
GATE="$BIN/ft_da_hold_gate.py"
gate() { local c="$1"; shift; FT_HARNESS_ROOT="$KD" python3 "$GATE" "$c" --root "$CR" --seats-dir "$T/none" --comm "$T/none" "$@" 2>&1; }
out="$(gate "$cpk" --closing --da "$CR/design/harness/DA-row.md#§1" --landed "$P1")"; rc=$?
[ "$rc" = 0 ] && [[ "${out%%$'\n'*}" == "LANDED-CLOSE sha=$P1"* ]] && ck "ⓔ 팩 착지 카드(main(팩) 행) → 보류 가드 LANDED-CLOSE rc0" 0 || ck "ⓔ 팩 착지 카드 → LANDED-CLOSE" 1
printf '# 인덱스: kbyzh\n## 상태\n- DA⑥ r1 HOLD 4\n- DA⑥ r2 HOLD 1\n' > "$IDX/진행/kbyzh.md"
out="$(gate "$IDX/진행/kbyzh.md" --closing --da "$CR/design/harness/DA-row.md#§4" --landed "$C0")"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"LANDED-INVALID marker-mismatch"*"표식 오기"* ]] && ck "ⓔ 표식 main(팩) 인데 sha 가 카드 리포에만 → LANDED-INVALID marker-mismatch rc3" 0 || ck "ⓔ 표식 오기 → marker-mismatch" 1
out="$(gate "$IDX/진행/kbyzh.md" --closing --da "$CR/design/harness/DA-row.md#§4" --landed "$(printf '0%.0s' {1..40})")"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"LANDED-INVALID not-found"* ]] && ck "ⓔ 어느 리포에도 없는 sha → LANDED-INVALID not-found rc3" 0 || ck "ⓔ not-found → rc3" 1

# ⓕ~ⓘ DA⑥ r1 반송(r2 · 7초 상한 · bash 3.2) — git 조회 상한·조회 실패 구분·bash 3.2 문법
#   느린 git 대역: merge-base 만 8초 자고 실패(상한 7초 × 재시도 1 = 14초 안에 REJECT)
FG="$T/fakegit"; mkdir -p "$FG"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = merge-base ] && { sleep 8; exit 1; }; done\nexec %s "$@"\n' "$(command -v git)" > "$FG/git"
chmod 755 "$FG/git"
t0="$(date +%s)"
out="$(printf '## §1 닫힘: kpack\n- 닫힘 — kpack — main(팩) \`%s\`\n' "$P1" | PATH="$FG:$PATH" bash "$BIN/ft-index-move-canon.sh" "$cpk" "$CR" "$P1")"; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"조회 실패"* ]] && [ "$el" -le 16 ] && ck "ⓕ 정본 게이트: merge-base 8초 지연 → 조회 실패 REJECT · 소요 ${el}초 ≤ 16" 0 || ck "ⓕ 정본 게이트 시간 초과 → REJECT(소요 ${el}초)" 1
t0="$(date +%s)"
out="$(PATH="$FG:$PATH" FT_HARNESS_ROOT="$KD" python3 "$GATE" "$cpk" --root "$CR" --seats-dir "$T/none" --comm "$T/none" --closing --da "$CR/design/harness/DA-row.md#§1" --landed "$P1" 2>&1)"; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [[ "$out" == *"LANDED-INVALID lookup-failed"* ]] && [ "$el" -le 16 ] && ck "ⓕ 보류 가드: merge-base 8초 지연 → LANDED-INVALID lookup-failed · 소요 ${el}초 ≤ 16" 0 || ck "ⓕ 보류 가드 시간 초과(소요 ${el}초) :: $out" 1
t0="$(date +%s)"
out="$(PATH="$FG:$PATH" FT_HARNESS_ROOT="$KD" bash "$BIN/ft-index-close-landed.sh" "$CR/design/harness/DA-row.md" --dry-run 2>&1)"; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [[ "$out" == *"| §1 | kpack | 진행 | no |"*"lookup-failed"* ]] && [ "$el" -le 34 ] && ck "ⓕ close-landed: merge-base 8초 지연 → lookup-failed · 느린 행 2개(행당 ≤ 16초) 소요 ${el}초 ≤ 34" 0 || ck "ⓕ close-landed 시간 초과(소요 ${el}초) :: $out" 1

# ⓖ~ⓛ DA⑥ r2 반송(r3 · 7초 상한 남은 3곳) — 실행기 ft_git_capped.py: 재시도 실제 수행 · 자식까지 정리 · 루트 조회 포함 · timeout 도구 불요
REALGIT="$(command -v git)"
mkfake() { local d="$1" body="$2"; mkdir -p "$d"; printf '#!/bin/bash\n%s\nexec %s "$@"\n' "$body" "$REALGIT" > "$d/git"; chmod 755 "$d/git"; }
#   느린 걸 병렬로 돌린다(각 ≈15초) — 작업마다 출력·소요를 파일로
bg() { local n="$1"; shift; ( s0=$SECONDS; o="$("$@" 2>&1)"; r=$?; printf '%s' "$o" > "$T/$n.out"; echo "$r $((SECONDS - s0))" > "$T/$n.rc" ) & }
getrc() { read -r rc el < "$T/$1.rc"; out="$(cat "$T/$1.out")"; }
# ⓖ timeout·gtimeout 이 PATH 에 «실제로 없다» — rev-parse --verify 만 8초 지연
NT="$T/nopath"; mkdir -p "$NT"
for t in bash python3 awk sed grep cut head tail tr mktemp cat rm dirname basename date sleep sort wc env uniq xargs ls find mv cp printf pwd ln readlink; do
  tp="$(command -v "$t" 2>/dev/null)"; [ -n "$tp" ] && [ "${tp#/}" != "$tp" ] && ln -sf "$tp" "$NT/$t"; done
mkfake "$NT" 'case " $* " in *" rev-parse "*--verify*) sleep 8; exit 1;; esac'
NOTO=1; PATH="$NT" command -v timeout >/dev/null 2>&1 && NOTO=0; PATH="$NT" command -v gtimeout >/dev/null 2>&1 && NOTO=0
BASHBIN="$(command -v bash)"
bg g1 bash -c 'printf "## §1 닫힘: kpack\n" | PATH="$1" "$2" "$3/ft-index-move-canon.sh" "$4" "$5" "$6"' x "$NT" "$BASHBIN" "$BIN" "$cpk" "$CR" "$P1"
# ⓗ «팩 객체 조회만» 시간 초과(리포 경로로 구별 · 카드 리포는 정상) → 다른 리포로 넘어가 OK 0 — REJECT «조회 실패»
FH="$T/fakegit-pack"; mkfake "$FH" '[ "$2" = "'"$PR"'" ] && case " $* " in *" rev-parse "*) sleep 8; exit 1;; esac'
bg h1 bash -c 'PATH="$1:$PATH"; . "$2/ft-team-lib.sh"; ft_landed_repo "$3" "$4" "$5" "닫힘 — kpack — main \`$3\`"' x "$FH" "$BIN" "$P1" "$CR" "$PR"
# ⓙ 후보 리포 «루트 조회»(rev-parse --show-toplevel) 만 시간 초과 → 빈 값으로 넘기지 않고 REJECT — 정본 게이트·보류 가드·close-landed·설치 게이트
FJ="$T/fakegit-root"; mkfake "$FJ" 'case "$2" in */feature-pack/fable-team/harness) case " $* " in *" --show-toplevel"*) sleep 8; exit 1;; esac;; esac'
bg j1 bash -c 'printf "## §1 닫힘: kpack\n" | PATH="$1:$PATH" FT_HARNESS_ROOT="$2" bash "$3/ft-index-move-canon.sh" "$4" "$5" "$6"' x "$FJ" "$KD" "$BIN" "$cpk" "$CR" "$P1"
bg j2 bash -c 'PATH="$1:$PATH" FT_HARNESS_ROOT="$2" python3 "$3" "$4" --root "$5" --seats-dir "$6" --comm "$6" --closing --da "$5/design/harness/DA-row.md#§1" --landed "$7"' x "$FJ" "$KD" "$GATE" "$cpk" "$CR" "$T/none" "$P1"
bg j3 bash -c 'PATH="$1:$PATH" FT_HARNESS_ROOT="$2" bash "$3/ft-index-close-landed.sh" "$4/design/harness/DA-row.md" --dry-run' x "$FJ" "$KD" "$BIN" "$CR"
bg j4 bash -c 'PATH="$1:$PATH" FT_HARNESS_ROOT="$2" bash "$3/ft-index-move-install.sh" "$4" --landed "$5"' x "$FJ" "$KD" "$BIN" "$cning" "$C0"
# ⓚ 첫 merge-base 만 8초 지연 · 둘째는 정상 → 재시도로 OK (호출 2회 · 소요 ≤ 16초)
FK="$T/fakegit-once"; mkfake "$FK" 'case " $* " in *" merge-base "*) echo mb >> "'"$T"'/mbcalls"; [ "$(wc -l < "'"$T"'/mbcalls")" -le 1 ] && { sleep 8; exit 1; };; esac'
: > "$T/mbcalls"
bg k1 bash -c 'printf "## §1 닫힘: kpack\n" | PATH="$1:$PATH" bash "$2/ft-index-move-canon.sh" "$3" "$4" "$5"' x "$FK" "$BIN" "$cpk" "$CR" "$P1"
# ⓛ git 대역이 SIGTERM 을 무시하는 자식 sleep 을 띄운다 → 시간 초과(rc124 · 재시도 1회 = 2번 띄움) 뒤 그 자식 생존 0
FL="$T/fakegit-child"; mkfake "$FL" 'case " $* " in *" rev-parse HEAD "*) echo c >> "'"$T"'/childcalls"; trap "" TERM; sleep 60 & echo $! >> "'"$T"'/childpids"; wait;; esac'
: > "$T/childpids"; : > "$T/childcalls"
t0=$SECONDS; out="$(export PATH="$FL:$PATH"; ft_git_capped 3 "$CR" rev-parse HEAD)"; rc=$?; el=$((SECONDS - t0))
alive=0; n=0; while read -r cp; do n=$((n+1)); kill -0 "$cp" 2>/dev/null && alive=$((alive+1)); done < "$T/childpids"
calls="$(wc -l < "$T/childcalls" | tr -d ' ')"
[ "$rc" = 124 ] && [ "$calls" = 2 ] && [ "$n" -ge 1 ] && [ "$alive" = 0 ] && [ "$el" -le 10 ] && ck "ⓛ 시간 초과 rc124 · 재시도 1회 실제 수행(git ${calls}회 기동 · 자식 ${n}개) · 자식 sleep 생존 ${alive} · 소요 ${el}초" 0 || ck "ⓛ 자식 정리 :: rc=$rc calls=$calls n=$n alive=$alive el=$el" 1
wait
getrc g1; [ "$NOTO" = 1 ] && [ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"조회 실패"* ]] && [ "$el" -le 18 ] && ck "ⓖ timeout·gtimeout 실제로 없는 PATH: rev-parse 8초 → REJECT «조회 실패» · 소요 ${el}초 ≤ 18" 0 || ck "ⓖ timeout 없는 PATH (NOTO=$NOTO 소요 ${el}초)" 1
getrc h1; [ "$rc" = 1 ] && [[ "$out" == "REJECT $PR"*"조회 실패"* ]] && ck "ⓗ 팩 객체 조회만 rc124(카드 리포 정상) → REJECT «조회 실패»(다른 리포로 넘어가 OK 0)" 0 || ck "ⓗ 팩 조회만 실패 :: $out" 1
getrc j1; [ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"팩 리포"*"루트 조회 실패"* ]] && [ "$el" -le 18 ] && ck "ⓙ 정본 게이트: 팩 루트 조회(--show-toplevel)만 시간 초과 → REJECT «루트 조회 실패» · 소요 ${el}초" 0 || ck "ⓙ 정본 게이트 루트 조회 :: rc=$rc el=$el $out" 1
getrc j2; [ "$rc" = 0 ] && [[ "$out" == *"LANDED-INVALID lookup-failed"*"루트 조회 실패"* ]] && [ "$el" -le 18 ] && ck "ⓙ 보류 가드: 팩 루트 조회만 시간 초과 → LANDED-INVALID lookup-failed(루트 조회 실패) · 소요 ${el}초" 0 || ck "ⓙ 보류 가드 루트 조회 :: rc=$rc el=$el $out" 1
getrc j3; [ "$rc" = 2 ] && [[ "$out" == *"팩 리포"*"루트 조회 실패"* ]] && ck "ⓙ close-landed: 팩 루트 조회만 시간 초과 → ERROR rc2(루트 조회 실패)" 0 || ck "ⓙ close-landed 루트 조회 :: rc=$rc $out" 1
getrc j4; [ "$rc" = 1 ] && [[ "$out" == "REJECT 팩 리포"*"루트 조회 실패"* ]] && ck "ⓙ 설치 게이트: 팩 루트 조회만 시간 초과 → REJECT «루트 조회 실패»" 0 || ck "ⓙ 설치 게이트 루트 조회 :: rc=$rc $out" 1
getrc k1; mb="$(wc -l < "$T/mbcalls" | tr -d ' ')"
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'* ]] && [ "$mb" = 2 ] && [ "$el" -le 16 ] && ck "ⓚ 첫 merge-base 만 8초 → 재시도로 OK(호출 ${mb}회 · 소요 ${el}초 ≤ 16)" 0 || ck "ⓚ 재시도 :: rc=$rc mb=$mb el=$el $out" 1

# ⓞ 바깥 상한(astra r1) — 보류 가드 바깥 timeout 이 안쪽 재시도 합보다 짧아 먼저 끊던 결함. 세 조회(팩 루트·카드·팩)의 «첫 호출» 이 전부 SIGTERM 무시 자식 + 8초 지연,
#    재시도는 정상 → 바깥(47초)이 먼저 끊지 않고 LANDED-CLOSE · 20초를 넘겨 걸려도 통과 · 반환 순간 자식 생존 0 · 소요 ≤ 70초
FO="$T/fakegit-first"; mkfake "$FO" 'case " $* " in *" rev-parse "*) k="$(printf %s "$*" | cksum | cut -d" " -f1)"; if [ ! -e "'"$T"'/seen.$k" ]; then : > "'"$T"'/seen.$k"; trap "" TERM; sleep 60 & echo $! >> "'"$T"'/firstpids"; wait; fi;; esac'
: > "$T/firstpids"
t0=$SECONDS
out="$(PATH="$FO:$PATH" FT_HARNESS_ROOT="$KD" python3 "$GATE" "$cpk" --root "$CR" --seats-dir "$T/none" --comm "$T/none" --closing --da "$CR/design/harness/DA-row.md#§1" --landed "$P1" 2>&1)"; rc=$?
el=$((SECONDS - t0))
alive=0; n=0; while read -r cp; do n=$((n+1)); kill -0 "$cp" 2>/dev/null && alive=$((alive+1)); done < "$T/firstpids"
[ "$rc" = 0 ] && [[ "${out%%$'\n'*}" == "LANDED-CLOSE sha=$P1"* ]] && [ "$n" -ge 3 ] && [ "$el" -gt 20 ] && [ "$el" -le 70 ] && [ "$alive" = 0 ] \
  && ck "ⓞ 보류 가드: 세 조회 첫 호출 모두 지연(자식 ${n}개) → 바깥이 먼저 끊지 않고 LANDED-CLOSE · 소요 ${el}초(20 초과 ≤ 70) · 자식 생존 ${alive}" 0 || ck "ⓞ 바깥 상한 :: rc=$rc n=$n el=$el alive=$alive out=${out:0:200}" 1
# ⓞ2 바깥이 끊을 때: 실행기에 SIGTERM → 안쪽 git 그룹(SIGTERM 무시 자식 포함)까지 정리 — 반환 순간 자식 생존 0
FO2="$T/fakegit-hang"; mkfake "$FO2" 'case " $* " in *" rev-parse "*) trap "" TERM; sleep 60 & echo $! >> "'"$T"'/hangpids"; wait;; esac'
: > "$T/hangpids"
out="$(PATH="$FO2:$PATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1])
from ft_git_capped import run_cmd
rc, _ = run_cmd(["python3", sys.argv[1] + "/ft_git_capped.py", "30", sys.argv[2], "rev-parse", "HEAD"], 2)
print(rc)' "$BIN" "$CR" 2>&1)"
alive=0; n=0; while read -r cp; do n=$((n+1)); kill -0 "$cp" 2>/dev/null && alive=$((alive+1)); done < "$T/hangpids"
[ "$out" = 124 ] && [ "$n" -ge 1 ] && [ "$alive" = 0 ] && ck "ⓞ2 바깥 상한이 끊으면 rc124 · 안쪽 실행기가 git 그룹까지 정리(자식 ${n}개 중 생존 ${alive})" 0 || ck "ⓞ2 바깥 끊김 정리 :: out=$out n=$n alive=$alive" 1

# ⓟ git 자신의 종료 코드 124(시간 초과 아님)는 재시도 없이 그대로 · 출력 보존 / 첫 호출 rc124+출력 → 그대로 rc124(둘째 호출 0)
FP="$T/fakegit-rc124"; mkfake "$FP" 'case " $* " in *" rev-parse "*) echo c >> "'"$T"'/rc124calls"; echo SENTINEL; exit 124;; esac'
: > "$T/rc124calls"
out="$(export PATH="$FP:$PATH"; ft_git_capped 7 "$CR" rev-parse HEAD)"; rc=$?
calls="$(wc -l < "$T/rc124calls" | tr -d ' ')"
[ "$rc" = 124 ] && [ "$out" = SENTINEL ] && [ "$calls" = 1 ] && ck "ⓟ git 자신의 rc124(지연 0): 호출 ${calls}회 · rc124 · 출력 SENTINEL 보존(재시도·출력 버림 0)" 0 || ck "ⓟ git rc124 :: rc=$rc calls=$calls out=$out" 1
FP2="$T/fakegit-rc124-then0"; mkfake "$FP2" 'case " $* " in *" rev-parse "*) echo c >> "'"$T"'/rc124calls2"; if [ "$(wc -l < "'"$T"'/rc124calls2")" -le 1 ]; then echo FIRST; exit 124; fi;; esac'
: > "$T/rc124calls2"
out="$(export PATH="$FP2:$PATH"; ft_git_capped 7 "$CR" rev-parse HEAD 2>/dev/null | head -1)"
calls="$(wc -l < "$T/rc124calls2" | tr -d ' ')"
[ "$out" = FIRST ] && [ "$calls" = 1 ] && ck "ⓟ 첫 호출 rc124+출력 FIRST → 둘째 호출로 성공 출력을 만들지 않는다(호출 ${calls}회)" 0 || ck "ⓟ 첫 호출 rc124 :: out=$out calls=$calls" 1

# ⓘ bash 3.2(/bin/bash) 문법 — 이 카드가 고친 파일 전부 + 이 시험을 /bin/bash 로 1회
b32=0
for f in ft-team-lib.sh ft-index-move.sh ft-index-move-install.sh ft-index-move-canon.sh ft-index-close-landed.sh; do /bin/bash -n "$BIN/$f" 2>/dev/null || b32=1; done
out="$(/bin/bash -c '. "$1" && ft_landed_repo "$2" "$3" "$4" ""' x "$BIN/ft-team-lib.sh" "$C0" "$CR" "$PR" 2>&1)"; rc=$?
[ "$b32" = 0 ] && [ "$rc" = 0 ] && [ "${out%%$'\t'*}" = "$CR" ] && ck "ⓘ bash 3.2(/bin/bash): 고친 파일 -n rc0 · ft_landed_repo 실행 ok" 0 || ck "ⓘ bash 3.2 :: b32=$b32 rc=$rc out=$out" 1
# ⓘ2 /bin/bash 3.2 로 ft_git_capped 실행기 경로(timeout 도구 불요) 실제 호출
out="$(/bin/bash -c '. "$1" && ft_git_capped 7 "$2" rev-parse --verify -q "$3^{commit}"' x "$BIN/ft-team-lib.sh" "$CR" "$C0" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$C0" ] && ck "ⓘ /bin/bash 3.2: ft_git_capped(python 실행기) rc·stdout git 그대로" 0 || ck "ⓘ /bin/bash 3.2 실행기 :: rc=$rc out=$out" 1

# ⓝ 이 카드가 고친 게이트 파일에서 git 을 ft_git_capped 밖에서 부르는 줄 = 0 (실행기 ft_git_capped.py 만 예외)
raw=0
for f in ft-index-move-install.sh ft-index-move-canon.sh ft-index-close-landed.sh ft_da_hold_gate.py; do
  n="$(grep -nE 'git -C|\["git"|(^|[^A-Za-z_./-])git (rev-parse|merge-base|diff|show|rev-list|ls-files|log|cat-file)' "$BIN/$f" | grep -vE '^[0-9]+:[[:space:]]*#|ft_git_capped|_run_capped|git_capped\(|gq ' | wc -l | tr -d ' ')"
  [ "$n" = 0 ] || { raw=$((raw+n)); echo "  raw git: $f ×$n"; }; done
[ "$raw" = 0 ] && ck "ⓝ 게이트 4파일에서 ft_git_capped 밖 git 호출 줄 0" 0 || ck "ⓝ 캡 밖 git 호출 줄 ${raw}" 1

# ⓜ 오염 0 — 두 리포 변경 없음
[ -z "$(g "$CR" status --porcelain | grep -v 'design/harness/')" ] && [ -z "$(g "$PR" status --porcelain)" ] && ck "ⓜ 리포 오염 0(design/harness 픽스처 밖 변경 0 · 팩 무변경)" 0 || ck "ⓜ 리포 오염 0 :: $(g "$CR" status --porcelain | grep -v 'design/harness/' | head -3)" 1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
