#!/usr/bin/env bash
# test_issue_card_audit.sh — ft-issue-card-audit.sh 반례 R1~R9 + 변이 3 (PLAN-issue-card-audit-20261028 §3·§4)
#   방식: 임시 git 리포 2 ref(origin/main · origin/ops/main-base) + 가짜 gh + 가짜 git(실패·지연) · 고정 sleep 0 · 자기 재호출 0.
#   변이 3 = 번호 경계 끔(R4) · ops/main-base ref 끔(R5) · git 실패를 빈 집합으로(R9) — 셋 다 «FAIL 이어야» 통과.
#   exit 0 = 전부 통과 · 1 = 실패 1건 이상
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft-issue-card-audit.sh"
[ -f "$TOOL" ] || { echo "도구 없음: $TOOL" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
START=$(date +%s)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
has() { case "$2" in *"$1"*) return 0;; *) echo "  FAIL $3 — 없음[$1]"; fail=1; return 1;; esac; }

# ── 픽스처: 카드 리포(2 ref) ──
REPO="$T/repo"; mkdir -p "$REPO"
mkc() { # <경로> <줄…> — 카드 1장
  local p="$REPO/$1"; shift; mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" > "$p";
}

mkc design/harness/indices/진행/r1-card.md \
  '# 인덱스: r1-card' '' '- Issue: #1' '- 상태: 진행' '' '## 구현 범위' 'x'
mkc design/harness/indices/진행/r2-mention.md \
  '# 인덱스: r2-mention' '' '- Issue: #999' '' '## 배경' '#2 를 처리한 카드(본문 언급)' ''
mkc design/harness/indices/완성/r123-card.md \
  '# 인덱스: r123-card' '' '- Issue: #123' '' '## 구현 범위' 'x'
mkc design/feature/indices/대기/f4-card.md \
  '# 인덱스: f4-card' '' '- Issue: #4' '' '## 구현 범위' 'x'
mkc design/teams/harness/indices/대기/t9-card.md \
  '# 인덱스: t9-card' '' '- Issue: #9' '' '## 구현 범위' 'x'   # origin/main 꼴(teams/ 한 단계 더)
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" add -A; git -C "$REPO" commit -qm main-cards
MAIN_SHA="$(git -C "$REPO" rev-parse HEAD)"
mkc design/harness/indices/대기/r5-card.md \
  '# 인덱스: r5-card' '' '- Issue: #5' '' '## 구현 범위' 'x'
git -C "$REPO" add -A; git -C "$REPO" commit -qm ops-only-card
OPS_SHA="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$MAIN_SHA"
git -C "$REPO" update-ref refs/remotes/origin/ops/main-base "$OPS_SHA"

# ── 픽스처: 이슈 JSON (approved 12건 · 비승인 1건) ──
ISS="$T/issues.json"
cat > "$ISS" <<'JSON'
[
 {"number":1,"title":"r1 작업","labels":[{"name":"approved"},{"name":"team:harness-ops"}]},
 {"number":2,"title":"[v65 교정] r2","labels":[{"name":"approved"}]},
 {"number":3,"title":"카드 없는 r3","labels":[{"name":"approved"},{"name":"team:harness-ops"}]},
 {"number":4,"title":"r4","labels":[{"name":"approved"},{"name":"team:feature"}]},
 {"number":5,"title":"r5","labels":[{"name":"approved"},{"name":"team:harness"}]},
 {"number":6,"title":"[v65 뭔가] r6","labels":[{"name":"approved"}]},
 {"number":8,"title":"팀 근거 없음 r8","labels":[{"name":"approved"}]},
 {"number":9,"title":"teams 꼴 카드 r9","labels":[{"name":"approved"},{"name":"team:harness-ops"}]},
 {"number":12,"title":"r12 경계","labels":[{"name":"approved"}]},
 {"number":101,"title":"r101","labels":[{"name":"approved"}]},
 {"number":102,"title":"r102","labels":[{"name":"approved"}]},
 {"number":103,"title":"r103","labels":[{"name":"approved"}]},
 {"number":123,"title":"r123","labels":[{"name":"approved"}]},
 {"number":7,"title":"승인 아님","labels":[]}
]
JSON

run() { "$TOOL" "$@"; }
EXPECT="ISSUE-CARD approved=13 카드없음=7 #103 #102 #101 #12 #8 +2 언급만=1 닫기후보=1"

echo "== 왜: PLAN §2-1·§2-2 / §3 R1~R9 =="
OUT="$(run --tick --from-json "$ISS" --repo "$REPO" 2>&1)"; RC=$?
echo "--- tick: $OUT"
chk "R1·R2·R3·R4·R7+R3(+) — tick 한 줄" "$EXPECT" "$OUT"
chk "tick rc" 0 "$RC"

TABLE="$(run --table --from-json "$ISS" --repo "$REPO" 2>&1)"
has "#1 · r1 작업 · 연결 · 진행 · harness (라벨 team:harness-ops)" "$TABLE" "R1 연결 · R8 라벨 별칭"
has "· 언급만 · 진행 · v65 (제목 머리 [v65])" "$TABLE" "R2 언급 · R8 제목 머리"
has "#3 · 카드 없는 r3 · 없음 · — · harness (라벨 team:harness-ops)" "$TABLE" "R3 카드없음 · 카드 칸 —"
has "#12 · r12 경계 · 없음 · — · planner (없음 — planner 분류)" "$TABLE" "R4 번호 경계(#12 ≠ #123)"
has "#123 · r123 · 연결 · 완성 · planner" "$TABLE" "R7 완성 카드 연결"
has "#6 · [v65 뭔가] r6 · 없음 · — · v65 (제목 머리 [v65])" "$TABLE" "R8 제목 머리 v65"
has "#8 · 팀 근거 없음 r8 · 없음 · — · planner (없음 — planner 분류)" "$TABLE" "R8 둘 다 없음 → planner"
has "#5 · r5 · 연결 · 대기 · harness (라벨 team:harness)" "$TABLE" "R5 ops/main-base 카드도 연결"
has "#9 · teams 꼴 카드 r9 · 연결 · 대기 · harness (라벨 team:harness-ops)" "$TABLE" "teams/<팀>/indices 꼴도 카드"

MAIL="$(run --mail harness --from-json "$ISS" --repo "$REPO" 2>&1)"
has "[카드 등록 요청 · approved 1건] 골좌표:" "$MAIL" "§2-3 쪽지 머리"
has "- #3 «카드 없는 r3» (추천 근거: 라벨 team:harness-ops)" "$MAIL" "§2-3 쪽지 항목"
has "끝나면 회신 1줄:" "$MAIL" "§2-3 회신 줄"
chk "§2-3 팀별 분리(harness 1건)" "1" "$(printf '%s\n' "$MAIL" | grep -c '^- #')"
PM="$(run --mail planner --from-json "$ISS" --repo "$REPO" 2>&1)"
chk "§2-3 planner 몫(팀 근거 없는 5건)" "5" "$(printf '%s\n' "$PM" | grep -c '^- #')"
has "- #8 «팀 근거 없음 r8»" "$PM" "§2-3 planner 가 #8 받는다"
has "- #12 «r12 경계»" "$PM" "§2-3 planner 가 #12 받는다"
chk "§2-3 v65 몫" "1" "$(run --mail v65 --from-json "$ISS" --repo "$REPO" | grep -c '^- #')"

# R5 변이 대조 — ref 하나를 끄면 #5 가 «없음» 으로 떨어진다
chk "R5 대조 — ref-harness 끄면 카드없음 8" \
  "ISSUE-CARD approved=13 카드없음=8 #103 #102 #101 #12 #8 +3 언급만=1 닫기후보=1" \
  "$(run --tick --from-json "$ISS" --repo "$REPO" --ref-harness origin/main 2>&1)"

# R6 gh 실패 → 판정 불가 rc5 · 부분 결과 0
printf '#!/bin/sh\necho "gh boom" >&2\nexit 1\n' > "$T/gh-fail"; chmod +x "$T/gh-fail"
O6="$(FT_ICA_GH="$T/gh-fail" run --tick --repo "$REPO" 2>&1)"; R6=$?
chk "R6 gh 실패 rc5" 5 "$R6"
chk "R6 판정 불가 1줄" 1 "$(printf '%s\n' "$O6" | grep -c .)"
has "ISSUE-CARD 판정 불가 — gh issue list 실패(2회)" "$O6" "R6 원인 = gh"

# R9 git 실패 → 판정 불가 rc5 · 부분 결과 0
printf '#!/bin/sh\nexit 1\n' > "$T/git-fail"; chmod +x "$T/git-fail"
O9="$(FT_ICA_GIT="$T/git-fail" run --tick --from-json "$ISS" --repo "$REPO" 2>&1)"; R9=$?
chk "R9 git 실패 rc5" 5 "$R9"
chk "R9 판정 불가 1줄" 1 "$(printf '%s\n' "$O9" | grep -c .)"
has "ISSUE-CARD 판정 불가 — git ls-tree origin/main 실패(2회)" "$O9" "R9 원인 = git ls-tree"

# R9 시간 초과 → rc5 (상한 env 로 줄인다 · 고정 sleep 0)
printf '#!/bin/sh\nsleep 3\nexit 0\n' > "$T/git-slow"; chmod +x "$T/git-slow"
S=$(date +%s)
O9T="$(FT_ICA_GIT="$T/git-slow" FT_ICA_TIMEOUT_S=1 run --tick --from-json "$ISS" --repo "$REPO" 2>&1)"; R9T=$?
chk "R9 시간 초과 rc5" 5 "$R9T"
has "1초 초과" "$O9T" "R9 초과 사유"
chk "R9 초과 상한(≤10초)" 1 "$([ $(( $(date +%s) - S )) -le 10 ] && echo 1)"

# ── 변이 3 (각각 FAIL 이어야 통과) ──
mutate() { # <이름> <치환 전 한 줄> <치환 후 한 줄> [<ENV=값>]
  local name="$1" from="$2" to="$3" penv="${4:-}" dir="$T/mut-$1"
  mkdir -p "$dir"
  cp "$BIN/ft-issue-card-audit.sh" "$BIN/_issue_card_audit.py" "$BIN/_issue_card_audit_out.py" "$BIN/team_aliases.json" "$dir/"
  python3 - "$dir/_issue_card_audit.py" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
if old not in text:
    print("PATCH-MISS", old, file=sys.stderr); sys.exit(1)
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
  [ $? -eq 0 ] || { echo "  FAIL 변이 $name — 치환 실패"; fail=1; return 0; }
  local out rc
  if [ -n "$penv" ]; then out="$(env "$penv" "$dir/ft-issue-card-audit.sh" --tick --from-json "$ISS" --repo "$REPO" 2>&1)"; rc=$?
  else out="$("$dir/ft-issue-card-audit.sh" --tick --from-json "$ISS" --repo "$REPO" 2>&1)"; rc=$?; fi
  if [ "$out" = "$EXPECT" ] && [ "$rc" = 0 ]; then
    echo "  FAIL 변이 $name — 변이인데 같은 값이 나왔다(시험이 안 잡는다)"; fail=1
  else echo "  OK   변이 $name — 잡힘 (rc=$rc · ${out:0:60})"; fi
}

echo "== 변이 4 =="
# M1 번호 경계 끔: #123 이 #12 에도 걸린다 → R4(#12 = 없음) 무너져 카드없음/언급만이 달라진다
mutate num-boundary \
  '    return {int(n) for n in REF_RE.findall(text or "")}' \
  '    return {int(n) for n in REF_RE.findall(text or "")} | {int(str(n)[:i]) for n in REF_RE.findall(text or "") for i in range(1, len(str(n)))}' \
  ""
# M2 ops/main-base ref 끔 → R5(#5 = ops/main-base 카드만) 무너진다
mutate ref-off \
  'ap.add_argument("--ref-harness", default="origin/ops/main-base")' \
  'ap.add_argument("--ref-harness", default="origin/main")' \
  "카드없음=7"
# M4 카드 경로 정규식을 옛 «한 단계» 꼴로 되돌림 → teams/<팀>/indices 카드가 사라져 R5·teams 칸이 무너진다
mutate teams-path \
  'CARD_PATH_RE = re.compile(r"^design/(?:teams/)?[^/]+/indices/(?P<bucket>[^/.][^/]*)/.+\.md$")' \
  'CARD_PATH_RE = re.compile(r"^design/[^/]+/indices/(?P<bucket>[^/.][^/]*)/.+\.md$")' \
  ""
# M3 git 실패를 빈 집합으로 → R9(rc5 · 부분 결과 0) 무너진다
mutate git-empty \
  '    raise Unjudgeable(f"{what} 실패(2회) — {last}")' \
  '    return b""' \
  "FT_ICA_GIT=$T/git-fail"

echo "== 요약 =="
echo "  elapsed=$(($(date +%s) - START))s"
if [ "$fail" -eq 0 ]; then echo "PASS issue-card-audit R1~R9 + 변이 4"; exit 0; fi
echo "FAIL issue-card-audit — 위 FAIL 줄"; exit 1
