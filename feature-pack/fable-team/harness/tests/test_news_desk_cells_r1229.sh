#!/usr/bin/env bash
# test_news_desk_cells_r1229.sh — r1229(Issue #5341) desk 뉴스 오빠 손 칸 3 · relay 요약 ≤2KB · 하루 상한 · FT_DESK_STATE 격리.
# 반례 R1~R7(카드 동결) + R2′(arch#190 #211002 · «확인 불가 · » 먼저 · 30분+ 숫자 0) + 변이 1(전문 그대로 relay).
# 전부 mktemp 임시 루트 + 가짜 ft-hil·ft-decision-count·git·card-flow·mbox · 실 STATE·슬랙·desk 0 · 자기 재호출 0 · 고정 sleep 0(느린 스텁만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KITBIN="$HERE/../kit/fable-team/bin"
DESK="$KITBIN/ft_news_desk.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ROOT="$T/root"; fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# ── 픽스처 ────────────────────────────────────────────────────────────────
mkdir -p "$ROOT/.fable-team/state" "$ROOT/design/teams/feature/indices/"{대기,진행,완성} "$T/state" "$T/mut"
echo "$T" > "$ROOT/.fable-team/LIVE_ROOT"
printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| feature | `design/teams/feature/` | byz-feature-master-claude | 현역 |\n' > "$ROOT/design/TEAMS.md"
echo '{"_desk": "byz-planner-desk-claude#9", "byz-planner-desk-claude#9": {"role": "desk"}}' > "$ROOT/.fable-team/seats-planner.json"
python3 - "$T/ledger.md" <<'PY'
import sys
row = "| 축 {i} — 운영 아키텍처 대규모 분산 사용자·세션·방 → 엔드포인트 → GPU 표준 분산 리서치 | 진척 {i}/9 · 팩 착지 · 다시 열림 | r10{i} → press → RESULT → 착지 → 설치 → 실사건 |"
open(sys.argv[1], "w", encoding="utf-8").write("## 메인 골 (픽스처)\n\n| 골 | 지금 상태 | 닫히려면 남은 것 |\n|---|---|---|\n"
    + "\n".join(row.format(i=i) for i in range(1, 41)) + "\n")   # 40행 ≈ 전문 9KB(실사건 9076B 꼴)
PY
cat > "$T/card-flow.sh" <<'SH'
#!/usr/bin/env bash
D=""; while [ $# -gt 0 ]; do case "$1" in --dir) D="$2"; shift 2;; *) shift;; esac; done
echo "카드 대기 $(ls "$D/indices/대기" | wc -l | tr -d ' ') · 진행 0"
SH
printf '#!/usr/bin/env bash\nprintf "h1 5\\nh2 3\\nh3 9\\n"\n' > "$T/hil.sh"
printf '#!/usr/bin/env bash\nprintf "h7 4\\n"\n' > "$T/hil1.sh"
printf '#!/usr/bin/env bash\necho "결정 인터뷰 3건 · 스크립트 1건"\n' > "$T/decision.sh"
printf '#!/usr/bin/env bash\nsleep 2\n' > "$T/slow.sh"
cat > "$T/git.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_LOG"
[ -n "${LAND_NONE:-}" ] && exit 0
printf '\036[fix] r1225 같은 이름 현역 둘\037Why: x\n\nPR #5410 (head aaa)\n'
printf '\036[docs] r1225 증거 줄\037PR #5410 (head aaa)\n'
printf '\036[docs] r1223 착지 반송 고침\037PR #5402 (head bbb)\n'
printf '\036[docs] 손 커밋\037본문만\n'
SH
cat > "$T/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
echo "QUEUED seq=1 to=$2"
SH
chmod +x "$T"/*.sh
export FT_ROOT="$ROOT" FT_DESK_LEDGER_FILE="$T/ledger.md" FT_MBOX="$T/mbox.sh" FT_CARD_FLOW="$T/card-flow.sh"
export FT_DESK_HIL="$T/hil.sh" FT_DESK_DECISION="$T/decision.sh" FT_DESK_GIT="$T/git.sh" FT_DESK_LAND_REPO="$T"
export FT_DESK_STATE="$T/state" MBOX_LOG="$T/mbox.log" GIT_LOG="$T/git.log"
render() { timeout 70 python3 "$DESK" render 2>>"$T/err"; }
runs()   { timeout 70 python3 "${1:-$DESK}" run 2>>"$T/err"; }
relays() { grep -c 'relay byz-planner-desk-claude#9 ft-news-desk' "$MBOX_LOG" 2>/dev/null || true; }
lastfile() { tail -1 "$MBOX_LOG" | awk '{print $4}'; }

# ── R1 h 3개 → 번호·개수 ─────────────────────────────────────────────────
OUT="$(FT_DESK_NOW="2026-10-31 12:23" render)"
eq "R1 실행할 스크립트 3개(h1·h2·h3)" "$(printf '%s' "$OUT" | grep -c '^- 실행할 스크립트: 3개(h1·h2·h3) · 가장 오래된 9분$')" "1"
eq "R1 «미실행 h» 겹말 0" "$(printf '%s' "$OUT" | grep -c '미실행 h')" "0"

# ── R3 오늘 착지 2건(PR 중복 1줄 · PR 없는 커밋 제외) · 0건 ──────────────────
eq "R3 오늘 착지 2건" "$(printf '%s' "$OUT" | grep -c '^- 오늘 착지: 2건$')" "1"
eq "R3 PR #5410 · r1225 1줄" "$(printf '%s' "$OUT" | grep -c '^  - PR #5410 · r1225$')" "1"
eq "R3 PR #5402 · r1223 1줄" "$(printf '%s' "$OUT" | grep -c '^  - PR #5402 · r1223$')" "1"
eq "R3 git log 인자 = first-parent · 오늘 0시부터" "$(grep -c -- '--first-parent --since=2026-10-31 00:00' "$GIT_LOG")" "1"
Z="$(LAND_NONE=1 FT_DESK_NOW="2026-10-31 12:23" render)"
eq "R3 0건 → «없음» · 칸 있음" "$(printf '%s' "$Z" | grep -c '^- 오늘 착지: 없음(오늘 main 착지 0건)$')" "1"
eq "R3 ③ 칸 3개 늘 있음" "$(printf '%s' "$OUT" | grep -cE '^- (실행할 스크립트|답 대기 질문|오늘 착지): ')" "3"

# ── R2 · R2′ 질문 세기 7초 초과 + 직전 값 ─────────────────────────────────
FT_DESK_HIL="$T/hil1.sh" FT_DESK_NOW="2026-10-31 12:23" render >/dev/null      # 직전 값 12:23 = 1개(h7)
S="$(FT_DESK_HIL="$T/slow.sh" FT_DESK_DECISION="$T/slow.sh" FT_DESK_TOOL_TIMEOUT=1 FT_DESK_NOW="2026-10-31 12:34" render)"
eq "R2 질문 칸 = 확인 불가 · (12:23 기준 직전 값)" "$(printf '%s' "$S" | grep -c '^- 답 대기 질문: 확인 불가 · (12:23 기준 결정 인터뷰 3건 · 스크립트 1건) · 사유 ')" "1"
eq "R2′ 실사건(12:34 · h 칸 7초 초과) → 숫자보다 «확인 불가 · » 먼저" "$(printf '%s' "$S" | grep -c '^- 실행할 스크립트: 확인 불가 · (12:23 기준 1개(h7) · 가장 오래된 4분) · 사유 ')" "1"
eq "R2′ 숫자로 시작하는 실패 칸 0" "$(printf '%s' "$S" | grep -cE '^- (실행할 스크립트|답 대기 질문): [0-9]')" "0"
O="$(FT_DESK_HIL="$T/slow.sh" FT_DESK_TOOL_TIMEOUT=1 FT_DESK_NOW="2026-10-31 12:54" render)"
eq "R2′ 직전 값 31분 → 숫자 없이 «확인 불가(직전 값 31분 전)»" "$(printf '%s' "$O" | grep -c '^- 실행할 스크립트: 확인 불가(직전 값 31분 전) · 사유 ')" "1"
eq "R2′ 30분+ 칸에 «기준» 0" "$(printf '%s' "$O" | grep '^- 실행할 스크립트:' | grep -c '기준')" "0"

# ── R7 FT_DESK_STATE 사본 → 실 ft-news-desk-last.json 바이트 같음 ─────────────
echo '{"실행할 스크립트": {"value": "실값", "at": "09:00"}}' > "$ROOT/.fable-team/state/ft-news-desk-last.json"
cp "$ROOT/.fable-team/state/ft-news-desk-last.json" "$T/real.bak"
FT_DESK_NOW="2026-10-31 12:40" render >/dev/null
eq "R7 실 직전 값 파일 바이트 같음" "$(cmp -s "$T/real.bak" "$ROOT/.fable-team/state/ft-news-desk-last.json" && echo same || echo changed)" "same"
eq "R7 직전 값은 FT_DESK_STATE 아래에 씀" "$(grep -c '1개(h7)\|3개(h1·h2·h3)' "$T/state/ft-news-desk-last.json")" "1"

# ── R4 전문 9KB · 바뀐 칸 1 → 쪽지 ≤ 2048B + 경로 1줄 ─────────────────────
export FT_DESK_STATE="$T/relay"; : > "$MBOX_LOG"
FT_DESK_NOW="2026-10-31 13:00" runs; eq "R4 첫 틱 rc0" "$?" "0"
B1="$(lastfile)"
eq "R4 첫 틱(전부 바뀜)도 쪽지 ≤ 2048B" "$([ "$(wc -c < "$B1")" -le 2048 ] && echo yes || echo no)" "yes"
FULL="$(ls "$T/relay"/*.md | head -1)"
eq "R4 전문 ≥ 8KB(9KB 꼴)" "$([ "$(wc -c < "$FULL")" -ge 8000 ] && echo yes || echo no)" "yes"
echo "- w1" > "$ROOT/design/teams/feature/indices/대기/w1.md"
FT_DESK_NOW="2026-10-31 13:10" runs
B2="$(lastfile)"
eq "R4 relay 2통" "$(relays)" "2"
eq "R4 바뀐 칸 1 쪽지 ≤ 2048B" "$([ "$(wc -c < "$B2")" -le 2048 ] && echo yes || echo no)" "yes"
eq "R4 바뀐 칸 = 팀 표 feature 행 1줄" "$(grep -c '^\[팀별 작업 상황\] | feature |' "$B2")" "1"
eq "R4 머리 «바뀐 칸 1개»" "$(head -1 "$B2" | grep -c '^뉴스 바뀐 칸 1개 · 13:10$')" "1"
P2="$(tail -1 "$B2" | sed 's/^전문: //')"
eq "R4 끝줄 = 전문 경로(실재)" "$([ -f "$P2" ] && [ "$(wc -c < "$P2")" -ge 8000 ] && echo yes || echo no)" "yes"

# ── R5 바뀐 칸 0 → 쪽지 0 (분만 다름 · digest 지워도 칸 비교로 0) ─────────────
FT_DESK_NOW="2026-10-31 13:19" runs
eq "R5 분만 다른 틱 → relay 0" "$(relays)" "2"
rm -f "$T/relay/digest.sha"
FT_DESK_NOW="2026-10-31 13:21" runs
eq "R5 digest 없어도 바뀐 칸 0 → relay 0" "$(relays)" "2"

# ── R6 오늘 12통 뒤 → 쪽지 0 · 전문 머리 1줄 ─────────────────────────────
eq "R6 날짜 파일 = 보낸 통 수 2" "$(cat "$T/relay/relay-count-20261031.txt")" "2"
echo 12 > "$T/relay/relay-count-20261031.txt"
echo "- w2" > "$ROOT/design/teams/feature/indices/대기/w2.md"
FT_DESK_NOW="2026-10-31 13:30" runs; eq "R6 상한 틱 rc0" "$?" "0"
eq "R6 relay 0(누적 2)" "$(relays)" "2"
eq "R6 전문 머리 1줄" "$(sed -n 2p "$T/relay/20261031-1330.md" | grep -c '^> 오늘 desk 쪽지 상한 12통 도달')" "1"
FT_DESK_NOW="2026-11-01 00:10" runs
eq "R6 날짜 바뀌면 다시 relay(누적 3)" "$(relays)" "3"

# ── 변이: 전문 그대로 relay → R4 ≤2048B 가 깨진다 ───────────────────────────
cp "$KITBIN/ft_news_desk_blocks.py" "$KITBIN/ft_news_desk_oppa.py" "$T/mut/"
sed 's/relay(root, note, seat/relay(root, out, seat/' "$DESK" > "$T/mut/ft_news_desk.py"
export FT_DESK_STATE="$T/relay-mut"; : > "$MBOX_LOG"
PYTHONPATH="$KITBIN" FT_DESK_NOW="2026-10-31 14:00" runs "$T/mut/ft_news_desk.py"
eq "변이(전문 그대로 relay) → 쪽지 ≤ 2048B 문장이 깨진다" "$([ "$(wc -c < "$(lastfile)")" -le 2048 ] && echo pass || echo broken)" "broken"

echo "RESULT fail=$fail"
[ "$fail" = 0 ]
