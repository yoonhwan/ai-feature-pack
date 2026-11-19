#!/usr/bin/env bash
# test_issue_card_audit_status_approved_r2312.sh — 판정기 승인 거름이 «approved»·«status:approved» 둘 다 센다 (r2312)
#   반례 ①~⑦(계약 A1~A3) + 변이 M1·M2(사본에서만 · 변이마다 원본 같은 사례 1회 대조).
#   방식: test_issue_card_audit.sh 꼴 — 가짜 Issue JSON(--from-json) + 임시 git 리포 2 ref · 네트워크 0 · sleep 0.
#   기준판 = 고정 sha 714b220f(git show · 실패면 «판정 불가» rc 2) · ICA_BIN=<dir> 로 다른 판 시험.
#   exit 0 = 전부 통과 · 1 = 실패 · 2 = 판정 불가
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${ICA_BIN:-$(cd "$HERE/../bin" && pwd)}"
KIT="$HERE/../kit/fable-team/bin"
REL="feature-pack/fable-team/legacy/1.x/harness/bin"
BASE_SHA="714b220fd3"
[ -f "$BIN/_issue_card_audit.py" ] || { echo "도구 없음: $BIN/_issue_card_audit.py" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
START=$(date +%s)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }

# ── 판 사본: base(기준판) · m1 · m2 ──
mkbin() { # <폴더> <_issue_card_audit.py 원본> — 판 1벌
  mkdir -p "$1"; cp "$BIN/ft-issue-card-audit.sh" "$BIN/_issue_card_audit_out.py" "$BIN/team_aliases.json" "$1/"
  cp "$2" "$1/_issue_card_audit.py"
}
git -C "$HERE" show "$BASE_SHA:$REL/_issue_card_audit.py" > "$T/base.py" 2>/dev/null \
  || { echo "판정 불가: 기준판 git show 실패($BASE_SHA)"; exit 2; }
mkbin "$T/base" "$T/base.py"
sed 's/^LABEL_APPROVED_ALL = .*/LABEL_APPROVED_ALL = ("approved",)/' "$BIN/_issue_card_audit.py" > "$T/m1.py"
sed 's/if any(lab in LABEL_APPROVED_ALL for lab in i\["labels"\])/if any("approved" in lab for lab in i["labels"])/' \
  "$BIN/_issue_card_audit.py" > "$T/m2.py"
mkbin "$T/m1" "$T/m1.py"; mkbin "$T/m2" "$T/m2.py"

# ── 픽스처: 카드 리포(2 ref) · #2 카드만 완성/ ──
REPO="$T/repo"; mkdir -p "$REPO/design/harness/indices/완성"
printf '%s\n' '# 인덱스: r2-done' '' '- Issue: #2' '' '## 구현 범위' 'x' > "$REPO/design/harness/indices/완성/r2-done.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" add -A; git -C "$REPO" commit -qm cards
SHA="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$SHA"
git -C "$REPO" update-ref refs/remotes/origin/ops/main-base "$SHA"

cat > "$T/four.json" <<'JSON'
[
 {"number":1,"title":"옛 이름","labels":[{"name":"approved"}]},
 {"number":2,"title":"새 이름","labels":[{"name":"status:approved"}]},
 {"number":3,"title":"둘 다","labels":[{"name":"approved"},{"name":"status:approved"}]},
 {"number":4,"title":"hil","labels":[{"name":"hil:approved"}]}
]
JSON
cat > "$T/hil.json" <<'JSON'
[{"number":4,"title":"hil","labels":[{"name":"hil:approved"}]}]
JSON
cat > "$T/str.json" <<'JSON'
[{"number":7,"title":"문자열 라벨","labels":["status:approved"]}]
JSON

run() { local b="$1"; shift; "$b/ft-issue-card-audit.sh" "$@" --repo "$REPO" 2>&1; }
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

echo "== 반례 ①~⑦ (판 = $BIN) =="
TICK="$(run "$BIN" --tick --from-json "$T/four.json")"; RC=$?
chk "① 4건 → approved=3 (A1 · 둘 다 = 1건)" 3 "$(field "$TICK" approved)"
chk "① rc" 0 "$RC"
chk "② #2 완성 카드 → 닫기후보=1" 1 "$(field "$TICK" 닫기후보)"
TABLE="$(run "$BIN" --table --from-json "$T/four.json")"
case "$TABLE" in *"#2"*) echo "  OK   ② --table 에 #2";; *) echo "  FAIL ② --table 에 #2 없음"; fail=1;; esac
chk "③ hil:approved 만 → approved=0 (A2)" 0 "$(field "$(run "$BIN" --tick --from-json "$T/hil.json")" approved)"
chk "④ --all-open = 기준판 같은 줄 (A3)" \
  "$(run "$T/base" --tick --all-open --from-json "$T/four.json")" \
  "$(run "$BIN" --tick --all-open --from-json "$T/four.json")"
BTICK="$(run "$T/base" --tick --from-json "$T/four.json")"
echo "  ⑥ 고친 판: $TICK"
echo "  ⑥ 기준판: $BTICK"
# ⑥ 차이 = approved 칸 + (② 의 #2 완성 카드 몫) 닫기후보 칸 · 카드없음·언급만은 같음
chk "⑥ 카드없음·언급만 칸 = 기준판" \
  "$(printf '%s' "$BTICK" | sed 's/.*카드없음=/카드없음=/; s/ 닫기후보=.*//')" \
  "$(printf '%s' "$TICK" | sed 's/.*카드없음=/카드없음=/; s/ 닫기후보=.*//')"
chk "⑥ approved 기준판→고친 판" "2→3" "$(field "$BTICK" approved)→$(field "$TICK" approved)"
chk "⑦ 문자열 배열 라벨 → approved=1" 1 "$(field "$(run "$BIN" --tick --from-json "$T/str.json")" approved)"
if [ -z "${ICA_BIN:-}" ]; then
  cmp -s "$BIN/_issue_card_audit.py" "$KIT/_issue_card_audit.py"; chk "⑤ bin·kit cmp0" 0 "$?"
fi

echo "== 변이 (사본 · 원본 대조) =="
chk "M1 옛 1개 → ① approved≠3 (원본=3)" "M1=2 원본=3" \
  "M1=$(field "$(run "$T/m1" --tick --from-json "$T/four.json")" approved) 원본=$(field "$TICK" approved)"
chk "M2 낱말 포함 → ③ approved≠0 (원본=0)" "M2=1 원본=0" \
  "M2=$(field "$(run "$T/m2" --tick --from-json "$T/hil.json")" approved) 원본=$(field "$(run "$BIN" --tick --from-json "$T/hil.json")" approved)"

echo "-- 걸린 초: $(( $(date +%s) - START ))"
[ "$fail" = 0 ] && { echo "ALL OK"; exit 0; } || { echo "FAILED"; exit 1; }
