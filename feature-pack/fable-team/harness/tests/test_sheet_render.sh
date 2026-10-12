#!/usr/bin/env bash
# test_sheet_render.sh — ft-board.py render --sheet(트리 렌더러 · 소유자 미확인 · 3영역 · 보정 메모 · rev 둘) + ft-eli5-lint.py 시험. 빨강 먼저.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../fixtures/sheet/sheet_env.sh"
LINT="$BIN/ft-eli5-lint.py"
new_root
TXT="$(sheet_txt)"; eq "render --sheet --text rc" "$?" 0
MD="$(board render --sheet)"; eq "render --sheet(md) rc" "$?" 0
HTML="$(board render --sheet --html)"; eq "render --sheet --html rc" "$?" 0
SLACK="$(board render --sheet --slack)"; eq "render --sheet --slack rc" "$?" 0
# 세 화면이 다른 문장을 갖지 않는다 — md·html·슬랙 텍스트의 «줄 글자»가 같다(꼴 장식만 다름)
norm() { printf '%s' "$1" | sed '/자세히/,$d' | sed -e 's/<[^>]*>//g' -e 's/^[#> *-]* *//' -e 's/\*//g' | grep -E '(오빠가 정할 것|지금 진행 중|완성 전|완성 후|시안 3개|통역 본체)' | sed 's/ *$//' | sort; }
eq "md == html (트리 줄 글자)" "$(norm "$MD")" "$(norm "$HTML")"
eq "md == 슬랙 텍스트 (트리 줄 글자)" "$(norm "$MD")" "$(norm "$SLACK")"

# 트리 4블록 · 영역 4 고정 · 🔄 ≤5줄
for blk in "❓ 오빠가 정할 것" "🔄 지금 진행 중" "⏳ 완성 전" "⏳ 완성 후"; do has "트리 블록: $blk" "$TXT" "$blk"; done
for area in "통역 본체" "지식(Loom·RAG)" "돈·운영툴" "일하는 방식"; do has "영역: $area" "$TXT" "$area"; done
NPROG="$(printf '%s\n' "$TXT" | awk '/^🔄/{f=1;next} /^⏳/{f=0} f&&/^  · /' | wc -l | tr -d ' ')"
[ "$NPROG" -le 5 ] && [ "$NPROG" -ge 1 ] && ok "🔄 줄 수 1~5 ($NPROG)" || bad "🔄 줄 수 $NPROG"
has "🔄 넘치면 외 N건" "$TXT" "외 "
# 칸별 기대 글자 — say 줄 · 상태 절 마지막 사건 치환(sheet_stages.json) · title 폴백 · ★ 표식
has "일 이름 = say 줄" "$TXT" "시안 3개 → 고르기 → 수정"; has "지금 어디(완료·휴식 → 방금 완성)" "$TXT" "✅ 방금 완성 · 오빠 확인 대기"
has "지금 어디(DA HOLD n → 검토 중 · 고칠 것 n)" "$TXT" "검토 중 · 고칠 것 2"
has "say 없으면 제목 폴백" "$TXT" "현황판 트리 렌더러"; has "사용자 최우선 ★" "$TXT" "★"
has "완성 후 건수" "$TXT" "완성 후 (1건)"
# 펼침 밖에는 번호·sha·판정번호 0 (요약 영역 = 「자세히」 앞)
SUMM="$(printf '%s\n' "$MD" | awk '/^## 자세히/{exit} {print}')"
eq "펼침 밖 #번호 0" "$(printf '%s' "$SUMM" | grep -cE '#[0-9]+')" 0
eq "펼침 밖 hex7+ 0" "$(printf '%s' "$SUMM" | grep -cE '[0-9a-f]{7,}')" 0
eq "펼침 밖 판정 N 0" "$(printf '%s' "$SUMM" | grep -cE '판정 [0-9]+')" 0
has "펼침 안에는 카드 경로" "$MD" "design/harness/indices/진행/job-a.md"
has "각주 출처표(소유자 열)" "$MD" "소유자"

# 원장 없는 칸 → 소유자 미확인(…) · 쪽지 본문에만 있는 사실 → 시트 0
has "원장 없는 칸 = 소유자 미확인(누가 · 어느 도구)" "$MD" "소유자 미확인(harness master · [정지 레디]/[완료] 0)"
lacks "쪽지 본문에만 있는 사실은 시트 0" "$MD$HTML$TXT" "ZZ-QQ-9731"

# 이야기(LLM 모델 json) vs 구조 — 이야기가 「끝났다」여도 칸은 진행 · 이야기 절에 상태어 0
STORY="$T/story.json"; echo '{"summary":"오늘 도구가 전부 끝났다 완료 해결"}' > "$STORY"
OUT="$(FT_SHEET_STORY="$STORY" board render --sheet)"
has "이야기 있어도 구조 상태는 진행" "$OUT" "검토 중 · 고칠 것 2"
STORYSEC="$(printf '%s\n' "$OUT" | awk '/^## 오늘 이야기/{f=1;next} /^## /{f=0} f')"
for w in 완료 해결 승인 배포 결정 전부; do lacks "이야기 절에 상태어 0: $w" "$STORYSEC" "$w"; done

# 보정 메모 lint — id 실재 + 그 행에 그 필드 실재 · 자동 소비 0 · 미적용 절로만
NOTES="$T/notes.md"
printf '%s\n' 'verdict#901.title | 제목이 틀림 | 새 제목' 'verdict#901.없는필드 | 무관 필드 | x' 'verdict#99999.title | 없는 행 | x' > "$NOTES"
LOUT="$(FT_SHEET_NOTES="$NOTES" board sheet-notes "$NOTES" 2>&1)"; rc=$?
eq "메모 lint: 거절 포함 → rc≠0" "$([ $rc -ne 0 ] && echo y)" y
has "메모 lint: 무관 필드 REJECT" "$LOUT" "REJECT verdict#901.없는필드"; has "메모 lint: 없는 행 REJECT" "$LOUT" "REJECT verdict#99999.title"
has "메모 lint: 정상 줄 OK" "$LOUT" "OK verdict#901.title"
NOUT="$(FT_SHEET_NOTES="$NOTES" board render --sheet)"; has "보정 메모(미적용 1) 절" "$NOUT" "보정 메모(미적용 1)"
before="$(printf '%s' "$MD" | grep -c '열린 판정')"; after="$(printf '%s' "$NOUT" | sed -n '/^## 자세히/,$p' | grep -c '새 제목')"
eq "메모는 칸 글자를 안 바꿈(제안 문장은 메모 절에만)" "$after" 1

# rev 둘 — 이야기만 바뀌면 구조 rev 불변 · 발행 rev 변경 · 같은 입력이면 같은 값
# 시계 고정(교정 1): gh 캐시 mtime 을 T 로 박고 갱신을 끈다 — 안 그러면 REFRESH 가 매 호출 mtime 을 실제 시각으로 다시 써서 (고정 now − mtime)이 TTL 경계를 넘나든다(master 재현 1/10)
export FT_BOARD_GH_REFRESH=0; touch -t 202610121100.00 "$FB/state/board/gh-cache.json"
srev() { python3 -c 'import json,sys;print(json.loads(sys.argv[1])["structure"])' "$1"; }
# 구조 rev 는 시계 무관 — now 만 T → T+캐시 TTL+1초 로 바꿔도 같다(캐시 note «(캐시 HH:MM · 미확인)» 가 생겨도 구조는 같다)
RT0="$(FT_BOARD_NOW=2026-10-12T11:00:01 board render --sheet --rev)"; RT1="$(FT_BOARD_NOW=2026-10-12T11:10:02 board render --sheet --rev)"
has "시계 회귀: T+TTL+1초 에는 캐시 미확인 note 가 실제로 생긴다(회귀 전제)" "$(FT_BOARD_NOW=2026-10-12T11:10:02 board render --sheet)" "캐시 11:00 · 미확인"
eq "구조 rev: now 가 T → T+TTL+1초 여도 동일" "$(srev "$RT1")" "$(srev "$RT0")"
REV0="$(board render --sheet --rev)"; REV1="$(board render --sheet --rev)"; eq "같은 입력 → 같은 rev" "$REV1" "$REV0"
REV2="$(FT_SHEET_STORY="$STORY" board render --sheet --rev)"
S0="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["structure"])' "$REV0")"; S2="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["structure"])' "$REV2")"
P0="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["publish"])' "$REV0")"; P2="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["publish"])' "$REV2")"
eq "이야기만 바뀌어도 구조 rev 불변" "$S2" "$S0"; [ "$P2" != "$P0" ] && ok "이야기만 바뀌어도 발행 rev 변경" || bad "발행 rev 불변"
python3 - "$FT_ROOT" <<'PY'
import json, sys
p = sys.argv[1] + "/design/harness/indices/진행/job-b.md"
s = open(p, encoding="utf-8").read().replace("DA HOLD 2", "DA HOLD 3"); open(p, "w", encoding="utf-8").write(s)
PY
REV3="$(board render --sheet --rev)"; [ "$REV3" != "$REV0" ] && ok "상세(상태 절) 변경 → rev 변경" || bad "상세 변경에도 rev 불변"

# 기존 ⓪~④ 출력 바이트 무변경 — --sheet 없는 render 두 종은 모듈이 추가돼도 같다(두 번 렌더 동일 · 시트 줄 없음)
A="$(board render --term)"; B="$(board render --term)"; eq "기존 render --term 결정적" "$A" "$B"; lacks "기존 render 에 시트 트리 줄 0" "$A" "⏳ 완성 전"

# eli5 lint — 렌더 산출물(md·html)에 건다: rc=0 / 반례 파일 rc≠0 (기준 4)
echo "$MD" > "$T/sheet.md"; echo "$HTML" > "$T/sheet.html"
python3 "$LINT" "$T/sheet.md" >"$T/l1.out" 2>&1; eq "lint(md) rc=0" "$?" 0; cat "$T/l1.out" | grep FAIL
python3 "$LINT" "$T/sheet.html" >"$T/l2.out" 2>&1; eq "lint(html) rc=0" "$?" 0; cat "$T/l2.out" | grep FAIL
BAD="$T/bad.md"; { echo "# 요약"; echo "팩 정본 재색인 청크 SSE 랜딩 나노 오케 슬롯 sha PR DA HIL BTS 워크트리 브랜치 캐시 턴 틱"; for i in $(seq 1 50); do echo "줄 $i 판정 126 #360 abcdef1234"; done; echo "## 자세히"; } > "$BAD"
python3 "$LINT" "$BAD" >"$T/l3.out" 2>&1; rc=$?; eq "lint 반례 → rc≠0" "$([ $rc -ne 0 ] && echo y)" y
for k in "기준 1" "기준 2" "기준 3" "기준 4"; do has "lint 반례가 $k 를 잡는다" "$(cat "$T/l3.out")" "$k"; done
# ── fix2 F4 — svg 흐름 그림도 상자 수 상한(≤7)을 센다
SVGBASE="$(printf '%s\n' "$HTML" | grep -v 'class="flow"')"
mksvg() { { printf '%s\n<svg>' "$SVGBASE"; for _ in $(seq 1 "$1"); do printf '<g class="node"><rect/></g>'; done; echo '</svg>'; } > "$T/svg$1.html"; }
mksvg 8; mksvg 7
OUT8="$(python3 "$LINT" "$T/svg8.html" 2>&1)"; rc=$?; eq "F4 svg 8상자 → rc≠0" "$([ $rc -ne 0 ] && echo y)" y; has "F4 svg 8상자 → 흐름 상자 8 > 7" "$OUT8" "흐름 상자 8 > 7"
OUT7="$(python3 "$LINT" "$T/svg7.html" 2>&1)"; has "F4 svg 7상자 → 기준 4 PASS" "$OUT7" "PASS 기준 4"
python3 "$LINT" "$T/sheet.md" 2>&1 | grep -q "PASS 기준 4" && ok "F4 기존 흐름 표 그대로 PASS" || bad "F4 흐름 표 회귀"

# ── fix2 F5 — _norm 이 지우는 입력(멈춤 N분 · 사건 ts 의 HH:MM)만 다른 두 입력 → 구조 rev 동일 · 변이 sha(_norm(blob))→sha(blob) → 달라짐(시험이 _norm 을 잡는다)
mkinput() { # mkinput <분> <HH:MM> — job-b 카드 say 줄 + 정지 레디 사건 1행
  python3 - "$FT_ROOT" "$1" "$2" <<'RPY'
import json, re, sys
root, mins, hhmm = sys.argv[1:4]
p = root + "/design/harness/indices/진행/job-b.md"
s = re.sub(r"^- say:.*\n", "", open(p, encoding="utf-8").read(), flags=re.M)
s = s.replace("\n", f"\n- say: 작업 멈춤 {mins}분 대기\n", 1)
open(p, "w", encoding="utf-8").write(s)
row = {"ev": "stop-ready", "team": "harness", "id": "h-master", "seat": "h-master#1", "ref": "seq 1", "key": "stop-ready:h-master#1:aaaa", "ts": f"2026-10-12T{hhmm}:00"}
open(root + "/.fable-team/state/sheet-events.jsonl", "w", encoding="utf-8").write(json.dumps(row, ensure_ascii=False) + "\n")
RPY
}
mkinput 3 10:30; RA="$(board render --sheet --rev)"; mkinput 7 10:45; RB="$(board render --sheet --rev)"
eq "F5 멈춤 N분·HH:MM 만 다른 두 입력 → 구조 rev 동일" "$(srev "$RB")" "$(srev "$RA")"
MUTR="$T/mut-render"; mkdir -p "$MUTR"; cp "$BIN"/* "$MUTR/" 2>/dev/null; /usr/bin/sed -i '' 's/"structure": sha(_norm(blob))/"structure": sha(blob)/' "$MUTR/ft_board_sheet.py"
mkinput 3 10:30; MA="$(python3 "$MUTR/ft-board.py" render --sheet --rev)"; mkinput 7 10:45; MB="$(python3 "$MUTR/ft-board.py" render --sheet --rev)"
[ "$(srev "$MB")" != "$(srev "$MA")" ] && ok "F5 변이(_norm 제거) → 구조 rev 달라짐(시험이 _norm 을 잡는다)" || bad "F5 변이가 살아남음"
exit $((fail>0))
