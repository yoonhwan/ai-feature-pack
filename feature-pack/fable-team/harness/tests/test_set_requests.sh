#!/usr/bin/env bash
# test_set_requests.sh — 상태 요청 왕복(설계 §3-b · §8-2)을 가짜 로컬 기록으로 대조. 판정 주체는 ft-sets.sh(읽기 전용 검사기) 하나:
#   ① READ 뒤 반영 전 중단 → 후계 스캔이 `적용 -` 줄을 찾는다(PENDING)   ② 반영·커밋 뒤 회신 전 중단 → 재요청 = 갱신 0 + 같은 ACK(REACK · 전 상태 불일치보다 먼저)
#   ③ 전 상태 불일치 → 적용 0(MISMATCH)   ④ close 일부 실패 → 보류 — close 실패 · 닫힘 아님   임시 git 리포에서만 돈다(원격 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SETS="$HERE/../../harness/kit/sets/ft-sets.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

bash -n "$SETS" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/design/issues" "$R/design/planner/orders" "$R/design/cfo/orders"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false && git config core.hooksPath /dev/null
ORD=design/planner/orders/ORDER-359-cfo.md; REQ=design/cfo/orders/SET-REQUESTS.md; SETSF=design/issues/SETS.md
printf '# ORDER\n## s1\n본문\n' > "$ORD"; git add -A; git commit -qm order; V1="$(git rev-parse HEAD)"; git update-ref refs/orders/359-cfo "$V1"
HEAD_ROW='| 세트 | 팀 | 상태 | 골 축 | 닫는 사건 | Issue | 발주 | 판정 | 적용 id | 갱신 |'
# ledger <상태> <Issue> <적용 id> — 원장 한 장을 쓴다
ledger() { { echo "$HEAD_ROW"; echo '|---|---|---|---|---|---|---|---|---|---|'
  echo "| cfo/s1-close-bundle | cfo | $1 | 골 축 | 닫는 사건 | $2 | byz-agents@${V1:0:10}:$ORD#s1 | 359 | $3 | 10-08 issues#3 |"; } > "$SETSF"; }
req() { echo "- $1 · cfo/s1-close-bundle · $2 → $3 · 증거 abc1234 · 보냄 seq 61300 · 적용 $4"; }
export FT_SETS_FILE="$R/$SETSF" FT_SETS_REPO="$R" FT_SETS_TEAM_ROOT="$R"

ledger 진행 '#11 #12' cfo-s1-01; git add -A; git commit -qm ledger0

# ① 팀이 요청 줄을 먼저 쓰고 보냄 → issues master 가 읽고 반영 전 중단 → 후계 스캔
{ req cfo-s1-01 발주 진행 "$V1"; req cfo-s1-02 진행 닫힘 -; } > "$REQ"; git add -A; git commit -qm req
out="$(bash "$SETS" cfo)"
{ has "$out" "PENDING cfo-s1-02" && ! has "$out" "PENDING cfo-s1-01"; } && ok "① 반영 전 중단 → 후계 스캔이 적용 - 줄을 PENDING 으로 찾음(적용된 01 은 아님)" || bad "① $out"
before="$(git status --porcelain)"; bash "$SETS" cfo >/dev/null; bash "$SETS" --check cfo >/dev/null
[ "$(git status --porcelain)" = "$before" ] && ok "검사기는 읽기 전용(트리 변화 0)" || bad "트리가 바뀜"

# 후계가 정본 절차대로 반영: 원장 닫힘(close 2/2)·적용 id=02 커밋 → 회신 → 팀이 요청 줄에 적용 sha 기입
ledger '닫힘 — 증거 abc1234 · close 2/2' '#11 #12' cfo-s1-02; git add -A; git commit -qm apply02; AP="$(git rev-parse HEAD)"
out="$(bash "$SETS" --check cfo)"; { has "$out" "CHECK OK"; } && ok "④ close 2/2 확인된 닫힘 = --check 통과" || bad "close 2/2 check: $out"

# ② 반영·커밋 뒤 ACK 회신 전 중단 — 요청 줄은 아직 적용 -  (원장은 이미 적용 id=02, 상태 닫힘 ≠ 전 상태 진행)
out="$(bash "$SETS" cfo)"
{ has "$out" "REACK cfo-s1-02" && ! has "$out" "MISMATCH"; } && ok "② 재요청 → REACK(갱신 0 + 같은 ACK) · 전 상태 불일치보다 우선" || bad "② $out"
{ req cfo-s1-01 발주 진행 "$V1"; req cfo-s1-02 진행 닫힘 "$AP"; } > "$REQ"; git add -A; git commit -qm ack02
out="$(bash "$SETS" cfo)"; { ! has "$out" "PENDING" && ! has "$out" "REACK" && ! has "$out" "STALE" && has "$out" "미완료 0"; } && ok "② ACK 뒤 적용 sha 기입 → 미완료 0" || bad "② ACK 뒤: $out"

# ③ 전 상태 불일치 — 새 요청의 전 상태(진행)와 원장 지금(닫힘)이 다름, 적용 id 도 다름 → 적용 0
{ req cfo-s1-02 진행 닫힘 "$AP"; req cfo-s1-03 진행 보류 -; } > "$REQ"
ledger_before="$(cat "$SETSF")"; out="$(bash "$SETS" cfo)"
{ has "$out" "MISMATCH cfo-s1-03" && has "$out" "원장 지금 닫힘 — 증거 abc1234 · close 2/2" && has "$out" "적용 0"; } && ok "③ 전 상태 불일치 → MISMATCH · 적용 0" || bad "③ $out"
[ "$(cat "$SETSF")" = "$ledger_before" ] && ok "③ 원장 파일 무변경" || bad "③ 원장이 바뀜"

# ④ close 일부 실패 — 행은 보류 — close 실패, 닫힘 건수 0 · 닫힘 선언(close 1/2)은 --check 거부
ledger '보류 — close 실패 #12' '#11 #12' cfo-s1-04; git add -A; git commit -qm hold
out="$(bash "$SETS" cfo)"; { has "$out" "세트 진행 0 · 발주 0 · 보류 1 · 닫힘 0"; } && ok "④ close 일부 실패 = 보류 1 · 닫힘 0" || bad "④ 건수: $out"
bash "$SETS" --check >/dev/null && ok "④ 보류 — close 실패 행 --check 통과" || bad "④ 보류 행 check"
ledger '닫힘 — 증거 abc1234 · close 1/2' '#11 #12' cfo-s1-04
out="$(bash "$SETS" --check 2>&1)"; rc=$?; { [ $rc -ne 0 ] && has "$out" "close 2/2 확인 없음"; } && ok "④ 일부만 close 한 채 닫힘 선언 → --check rc≠0" || bad "④ 닫힘 거부 rc=$rc: $out"
git checkout -q -- "$SETSF"

# 승계 재시작(요청 파일은 팀 작업 트리 최신본을 읽음): 요청 줄을 바꾸면 다음 스캔에 바로 반영 + 팀 요청 파일 없으면 명시
rm -rf "$R/design/cfo"; out="$(bash "$SETS" cfo)"; has "$out" "요청 파일 없음" && ok "팀 요청 파일 없음 → 명시(침묵 0)" || bad "요청 파일 없음: $out"

echo "---"; [ $fail -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit $((fail>0))
