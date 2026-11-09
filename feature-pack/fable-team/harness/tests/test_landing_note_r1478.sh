#!/usr/bin/env bash
# test_landing_note_r1478.sh — r1478: 비모델 도구가 끝낸 «착지(LANDED)·이동(MOVED)» 사건을 카드 팀 master 에 1줄 쪽지로 남긴다.
#   계약: 착지 1건 = 1통 · 묶음(한 LANDED 에 카드 여러 장) = 1통 · 수신 = 카드 팀 명부 `_master`(카드 0 = 부른 좌석 FT_SEAT 둘째 토막)
#         「팀 못 정함」 = INFO 1줄(아무 팀장에게나 보내기 0) · arch 쪽지는 기존대로 완성 이동 때만(수신 _arch · 순서 = 이동 쪽지 먼저)
#         발신 실패·시간 초과 = WARN 1줄 + 부른 쪽 rc 불변 · 재시도 0 · 발신 상한 7초
#   격리: 임시 bare origin + clone · 가짜 gh·가짜 mbox(호출 기록) — 실 gh·실 원격·실 쪽지·실 명부 쓰기 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$SRC/../kit/fable-team/bin"; LAND="$SRC/ft-merge-land.sh"; MOVE="$SRC/ft-index-move.sh"; BIN="$SRC"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team" "$T/bin"
export FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
export FT_ROOT="$W" MBOX_LOG="$T/mbox.log" FT_MBOX="$T/mbox.sh"
unset FT_SEAT MBOX_FAIL MBOX_SLEEP   # 좌석이 준 env 로 시험이 흔들리지 않게(발신자 칸은 아래에서 명시)
printf '# 시험 목록(빈)\n' > "$T/deny.txt"; : > "$MBOX_LOG"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
[ -z "${MBOX_SLEEP:-}" ] || sleep "$MBOX_SLEEP"
[ -z "${MBOX_FAIL:-}" ] || { echo "QUEUE_FULL" >&2; exit "$MBOX_FAIL"; }
echo "QUEUED fake"
EOF
chmod +x "$T/mbox.sh"
put() { mkdir -p "$(dirname "$W/$1")"; printf '%b\n' "$2" > "$W/$1"; }
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <PR번호> <가지> <제목> <본문> <경로=내용>...
  local n="$1" b="$2" ttl="$3" bdy="$4"; shift 4
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"
  git -C "$W" push -q -f origin "$b:refs/pull/$n/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":sys.argv[4],"state":"OPEN","baseRefName":"main"},ensure_ascii=False))' \
    "$PRSHA" "$b" "$ttl" "$bdy" > "$STUB_JSON"
}
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; : > "$MBOX_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
mbox_n() { if [ -f "$MBOX_LOG" ]; then grep -c . "$MBOX_LOG" || true; else echo 0; fi; }

# ── 사전: 문법 · 줄 수 · 짝 사본 · 명단·카드·명부 픽스처(임시 리포) ──
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
bash -n "$MOVE"; ck "bash -n ft-index-move.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 200 ]; ck "ft-merge-land.sh ≤ 200줄" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "짝 사본 bin·kit cmp0(ft-merge-land)" $?
cmp -s "$MOVE" "$KIT/ft-index-move.sh"; ck "짝 사본 bin·kit cmp0(ft-index-move)" $?
cmp -s "$SRC/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"; ck "짝 사본 bin·kit cmp0(ft-merge-lib)" $?
put "design/TEAMS.md" '| 팀 | 폴더 | x | y |
|---|---|---|---|
| harness | `design/harness/` | h | 현역 |
| v65 | `design/v65/` | v | 현역 |'
IDX="design/harness/indices"
for c in r1478-card-one r2001-card-a r2002-card-b; do put "$IDX/진행/$c.md" "# 인덱스: $c"; done
put "design/v65/indices/진행/r2003-card-v65.md" "# 인덱스: r2003-card-v65"   # F1(DA HOLD): 다른 팀 카드가 섞인 묶음
put "docs/architect/X.md" "## 절A 제목"
cm "$W" "base cards"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
printf '.fable-team/\n' >> "$W/.git/info/exclude"   # 하네스 상태(base-head 등)가 시험 커밋에 섞이지 않게
mkdir -p "$W/.fable-team"
printf '{"_master":"team-harness-master#9","_arch":"team-harness-arch#3"}\n' > "$W/.fable-team/seats-harness.json"
printf '{"_master":"team-v65-master#1"}\n' > "$W/.fable-team/seats.json"   # v65 팀 명부(팀 없음 → seats.json)
printf '{"_master":"team-move-master#4","_arch":"team-move-arch#2"}\n' > "$T/seats-move.json"

# ── T1: 카드 1장 착지 → LANDED 뒤 가짜 mbox 1통 · 수신 = 그 팀 _master · 머리·카드 토큰·설치 칸 · rc 0 ──
mkpr 1 doc1 "docs: r1478 카드 하나" "본문 r1478" "design/x/t1.md=T1"
A1="$PRSHA"
land "$LAND" 1 --approve-sha "$A1"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=1 "* ]] && [ "$(mbox_n)" = 1 ] \
  && grep -qE '^send team-harness-master#9 [^ ]+ \[착지\] pr=1 sha=[0-9a-f]{10} 카드 r1478 · 설치 (OK|PENDING|SKIP)$' "$MBOX_LOG"
ck "T1 카드 1장 → 쪽지 1통(_master·[착지]·pr·sha·카드 r…·설치) · rc 0" $?
grep -q '^send team-harness-master#9 ft-merge-land ' "$MBOX_LOG"; ck "T1b 카드 0 아님이라 발신자 = ft-merge-land(FT_SEAT 없음)" $?

# ── T2: 카드 2장 한 PR = 묶음 → 쪽지 1통(본문에 두 토큰) · 2통 아님 ──
mkpr 2 doc2 "docs: r2001 r2002 묶음" "카드 r2001 · r2002" "design/x/t2.md=T2"
land "$LAND" 2 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [ "$(mbox_n)" = 1 ] && grep -q 'r2001' "$MBOX_LOG" && grep -q 'r2002' "$MBOX_LOG"
ck "T2 묶음 착지 → 쪽지 1통(본문에 r2001·r2002 둘 다)" $?
# ── T2b (DA F1): 서로 다른 팀 카드 묶음 = 합집합 → 팀마다 1통 · FT_SEAT 없음이어도 발신자 팀으로 새지 않는다 ──
mkpr 7 doc7 "docs: r2001 r2003 두 팀" "harness r2001 · v65 r2003" "design/x/t7.md=T7"
land "$LAND" 7 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=7 "* ]] && [ "$(mbox_n)" = 2 ] \
  && grep -q '^send team-harness-master#9 ' "$MBOX_LOG" && grep -q '^send team-v65-master#1 ' "$MBOX_LOG"
ck "T2b 두 팀 묶음 → 팀마다 1통(합집합 2통 · 한 팀으로 몰리지 않음)" $?

# ── T3: 카드 0장(팩 코드 PR) — FT_SEAT 둘째 토막으로 팀 · FT_SEAT 없으면 INFO 1줄·발신 0·rc 불변 ──
mkpr 3 doc3 "chore: 코드만" "카드 토큰 없음" "bin/q3.sh=echo q3"
A3="$PRSHA"
export FT_SEAT=byz-harness-nano-r1478#0; land "$LAND" 3 --approve-sha "$A3"; unset FT_SEAT
[ "$rc" = 0 ] && [ "$(mbox_n)" = 1 ] && grep -qE '^send team-harness-master#9 byz-harness-nano-r1478#0 \[착지\] pr=3 ' "$MBOX_LOG"
ck "T3a 카드 0 + FT_SEAT=byz-harness-… → harness _master 로 1통" $?
mkpr 4 doc4 "chore: 코드만 둘" "카드 토큰 없음" "bin/q4.sh=echo q4"
land "$LAND" 4 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [ "$(mbox_n)" = 0 ] && echo "$out" | grep -q '^INFO 착지 쪽지 생략 — 팀 못 정함$'
ck "T3b FT_SEAT 없음 → 착지 rc0 · INFO 1줄 · 발신 0" $?
# ── T3c (DA F2): 받은 root 를 fm_land_notify 에 넘기나 — FT_REPO_ROOT 에 «다른 리포» 를 끼워도 쪽지는 카드 리포 팀장에게 간다 ──
mkdir -p "$T/decoy/.fable-team"; git -C "$T/decoy" init -q 2>/dev/null || mkdir -p "$T/decoy"
printf '{"_master":"team-decoy#7"}\n' > "$T/decoy/.fable-team/seats-harness.json"
mkpr 8 doc8 "chore: 코드만 셋" "카드 토큰 없음" "bin/q8.sh=echo q8"
A8="$PRSHA"; apv --approve-sha "$A8"; : > "$MBOX_LOG"
out="$(FT_REPO_ROOT="$T/decoy" FT_SEAT=byz-harness-nano-r1478#0 bash "$LAND" 8 --approve-sha "$A8" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=8 "* ]] && [ "$(mbox_n)" = 1 ] \
  && grep -qE '^send team-harness-master#9 byz-harness-nano-r1478#0 \[착지\] pr=8 ' "$MBOX_LOG" \
  && ! grep -q 'team-decoy#7' "$MBOX_LOG"
ck "T3c 받은 root 가 이긴다(FT_REPO_ROOT 유혹 0 · F2)" $?
unset A3

# ── T5: 가짜 mbox rc≠0 → WARN 1줄 · LANDED 그대로 · rc 불변 · 재시도 0(호출 1회) ──
mkpr 5 doc5 "docs: r1478 실패" "본문" "design/x/t5.md=T5"
export MBOX_FAIL=3; land "$LAND" 5 --approve-sha "$PRSHA"; unset MBOX_FAIL; export -n MBOX_FAIL 2>/dev/null || true
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=5 "* ]] && echo "$out" | grep -q '^WARN 착지 쪽지 발신 실패 → team-harness-master#9(3)' && [ "$(mbox_n)" = 1 ]
ck "T5 발신 실패 → WARN 1줄 · LANDED 유지 · rc 0 · 재시도 0" $?

# ── T6: 가짜 mbox sleep 20 → 7초에 끊고 WARN(시간 초과) · 전체 소요에 7초 넘게 안 더한다 ──
mkpr 6 doc6 "docs: r1478 느림" "본문" "design/x/t6.md=T6"
export MBOX_SLEEP=20; s0=$SECONDS; land "$LAND" 6 --approve-sha "$PRSHA"; el=$((SECONDS - s0)); unset MBOX_SLEEP
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=6 "* ]] && echo "$out" | grep -q '시간 초과' && [ "$(mbox_n)" = 1 ] && [ "$el" -le 15 ]
ck "T6 발신 7초 상한 → WARN(시간 초과) · 소요 ${el}s ≤ 15s(sleep 20 이면 끊겼다는 증거) · rc 0" $?

# ── T4: 이동(ft-index-move) — 대기→진행 1통 · 완성 = 이동 쪽지 먼저 + arch 정본 쪽지 · 영향 없음 카드 = arch 생략 ──
cp "$MOVE" "$SRC/ft-index-move-canon.sh" "$SRC/ft-index-move-install.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-merge-lib.sh" "$SRC/ft_da_hold_gate.py" "$SRC/ft_git_capped.py" "$T/bin/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-index-lint.sh"
mv_() { out="$(FT_SEATS_JSON="$T/seats-move.json" FT_LAND_REF=main FT_INDEX_STATE_DIR="$T/state" bash "$T/bin/ft-index-move.sh" "$@" 2>&1)"; rc=$?; }
mv_wt() { out="$(env -u FT_SEATS_JSON -u FT_MBOX -u FM_NOTIFY_REPO -u FT_ROOT -u FT_REPO_ROOT FT_LAND_REF=main FT_INDEX_STATE_DIR="$T/state" bash "$T/bin/ft-index-move.sh" "$@" 2>&1)"; rc=$?; }   # 명부·mbox = 기본 경로(공용 루트) 를 실제로 태운다
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main
put "$IDX/대기/r3001-move-wait.md" "# 인덱스: r3001-move-wait"; cm "$W" "card 대기"; : > "$MBOX_LOG"
mv_ "$W/$IDX/대기/r3001-move-wait.md" 진행 --seat s
[ "$rc" = 0 ] && [ "$(mbox_n)" = 1 ] && grep -qE '^send team-move-master#4 [^ ]+ \[카드 이동\] r3001 대기→진행$' "$MBOX_LOG"
ck "T4a 대기→진행 → [카드 이동] 1통(_master) · arch 쪽지 0" $?
put "$IDX/진행/r3002-move-done.md" "# 인덱스: r3002-move-done
- 정본 갱신: docs/architect/X.md §절A
- 규칙: 없음 — 시험 fixture 카드(규칙 무관)
- 설치: 없음"
cm "$W" "card 진행"; : > "$MBOX_LOG"
git -C "$W" checkout -q -b c9; printf 'v2\n' >> "$W/docs/architect/X.md"; cm "$W" "x v2"; C9="$(sha "$W" HEAD)"
git -C "$W" checkout -q main; git -C "$W" merge -q --squash c9 >/dev/null; git -C "$W" commit -qm "squash c9"; S9="$(sha "$W" HEAD)"
printf '# 판정문\n## §1 닫힘: r3002-move-done\n정본 diff 확인: docs/architect/X.md §절A @%s — v2\n' "$C9" > "$W/design/harness/DA-note.md"
mv_ "$W/$IDX/진행/r3002-move-done.md" 완성 --da "$W/design/harness/DA-note.md#§1" --seat s --landed "$S9"
[ "$rc" = 0 ] && [ "$(mbox_n)" = 2 ] \
  && [ "$(sed -n 1p "$MBOX_LOG" | grep -cE '^send team-move-master#4 [^ ]+ \[카드 이동\] r3002 진행→완성')" = 1 ] \
  && grep -q '^send team-move-arch#2 ' "$MBOX_LOG" && grep -q '\[정본 갱신 요청\]' "$MBOX_LOG"
ck "T4b 완성 이동 → 이동 쪽지 먼저(_master) + arch 정본 쪽지 1통(순서·수신 유지)" $?
put "$IDX/진행/r3003-move-none.md" "# 인덱스: r3003-move-none
- 정본 영향 없음: 하네스 도구만 변경
- 규칙: 없음 — 시험 fixture 카드(규칙 무관)
- 설치: 없음"
cm "$W" "card none"; : > "$MBOX_LOG"
printf '# 판정문\n## §1 닫힘: r3003-move-none\n' > "$W/design/harness/DA-none.md"
mv_ "$W/$IDX/진행/r3003-move-none.md" 완성 --da "$W/design/harness/DA-none.md#§1" --seat s --landed "$S9"
[ "$rc" = 0 ] && [ "$(mbox_n)" = 1 ] && grep -q '\[카드 이동\] r3003 진행→완성' "$MBOX_LOG" \
  && echo "$out" | grep -q '^INFO 정본 쪽지 생략 — 정본 영향 없음 카드$'
ck "T4c 영향 없음 카드 완성 → 이동 쪽지 1통 + arch 쪽지 0(기존 INFO 그대로)" $?

# ── T7 (보정 r2): 카드가 «연결 worktree» 안에 있어도 명부·comm 은 공용 루트(common-dir)에서 찾는다 ──
mkdir -p "$W/.fable-team/comm"; cp "$T/mbox.sh" "$W/.fable-team/comm/mbox.sh"
git -C "$W" worktree add -q "$T/wt" -b wt7 main
WIDX="$T/wt/design/harness/indices"; mkdir -p "$WIDX/대기"
printf '# 인덱스: r3010-wt-card\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n' > "$WIDX/대기/r3010-wt-card.md"; : > "$MBOX_LOG"
mv_wt "$WIDX/대기/r3010-wt-card.md" 진행 --seat s
[ "$rc" = 0 ] && [ "$(mbox_n)" = 1 ] && grep -qE '^send team-harness-master#9 [^ ]+ \[카드 이동\] r3010 대기→진행$' "$MBOX_LOG"
ck "T7 연결 worktree 안 카드 이동 → 공용 루트 명부(_master)로 1통" $?
# ── T7b: 공용 루트에 명부가 없으면 INFO 에 «찾은 경로» 1줄 · 발신 0 · rc 불변 ──
mv "$W/.fable-team/seats-harness.json" "$T/seats-harness.json.bak"
WREAL="$(cd "$W" && pwd -P)"   # /var ↔ /private/var (git 은 실제 경로로 푼다)
printf '# 인덱스: r3011-wt-card\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n' > "$WIDX/대기/r3011-wt-card.md"; : > "$MBOX_LOG"
mv_wt "$WIDX/대기/r3011-wt-card.md" 진행 --seat s
[ "$rc" = 0 ] && [ "$(mbox_n)" = 0 ] && echo "$out" | grep -qF "INFO 이동 쪽지 생략 — 팀 명부 없음(harness · $WREAL/.fable-team/seats-harness.json)"
ck "T7b 명부 없음 → INFO 에 찾은 경로 1줄 · 발신 0 · rc 0" $?
mv "$T/seats-harness.json.bak" "$W/.fable-team/seats-harness.json"

# ── 격리 ──
{ [ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; }; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh·실 쪽지 0)" $?
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
