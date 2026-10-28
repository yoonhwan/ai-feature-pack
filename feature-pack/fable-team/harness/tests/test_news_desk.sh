#!/usr/bin/env bash
# test_news_desk.sh — ft_news_desk.py(r1055 · Issue #4004) 시험 ⓐ~ⓓ + 변이 3 · r1061 plist 해석기 칸 ⓔ + 변이 2.
# 전부 mktemp 임시 FT_ROOT(원장·명단·좌석·카드 폴더·보드 스냅샷 픽스처) + 가짜 ft-card-flow·ft-hil·ft-decision-count·mbox 스텁.
# 실 슬랙·실 desk·실 mbox·실 좌석 호출 0 · 자기 재호출 0 · 고정 sleep 0 · 실행 1회 timeout 70(하드 룰 22).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KITBIN="$REPO/harness/kit/fable-team/bin"
DESK="$KITBIN/ft_news_desk.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ROOT="$T/root"; OPS="$T/ops"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# ── 픽스처 ────────────────────────────────────────────────────────────────
mkdir -p "$ROOT/.fable-team/state/board/2026-10-28" "$ROOT/design/teams/feature/indices/대기" \
  "$ROOT/design/teams/feature/indices/진행" "$ROOT/design/teams/feature/indices/완성" \
  "$OPS/design/harness/indices/대기" "$OPS/design/harness/indices/진행" "$OPS/design/harness/indices/완성" \
  "$T/state" "$T/mut"
echo "$T" > "$ROOT/.fable-team/LIVE_ROOT"
cat > "$ROOT/design/TEAMS.md" <<'MD'
| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| harness | `$FT_HARNESS_ROOT/design/harness/` | byz-harness-master-claude | 현역 |
| feature | `design/teams/feature/` | byz-feature-master-claude | 현역 |
| ops | `design/teams/ops/` | byz-ops-master-claude | 현역 |
| kk | `design/teams/kk/` | FB_KK | 휴면 |
MD
mkdir -p "$ROOT/design/teams/ops/indices/완성"
cat > "$ROOT/.fable-team/seats-harness.json" <<'JS'
{"byz-harness-master-claude#7": {"role": "master"}, "byz-harness-arch-claude#3": {"role": "arch"},
 "byz-harness-da-codex#1": {"role": "da"}, "byz-harness-nano-a#0": {"role": "nano"},
 "byz-harness-nano-old#9": {"role": "stop-ready"}}
JS
cat > "$ROOT/.fable-team/seats-planner.json" <<'JS'
{"_desk": "byz-planner-desk-claude#9", "byz-planner-desk-claude#9": {"role": "desk"}}
JS
cat > "$ROOT/.fable-team/seats-feature.json" <<'JS'
{"byz-feature-master-claude#1": {"role": "master"}, "byz-feature-arch-claude#2": {"role": "arch"},
 "byz-feature-nano-x#3": {"role": "nano"}, "byz-feature-nano-old#0": {"role": "nano", "_closed": {"by": "master"}},
 "byz-feature-nano-gone#1": {"role": "nano", "_replaced_by": "byz-feature-nano-x#3"}}
JS
python3 - "$ROOT/.fable-team/state/board/2026-10-28/165000-abcd1234.json" <<'PY'
import json, sys
teams = [
 {"key": "harness", "label": "harness", "error": None, "queue": [],
  "progress": {"c1": {"title": "r1055-news-desk — 뉴스 전문 생성기"}}},
 {"key": "feature", "label": "feature", "error": None,
  "queue": [{"title": "F-brain-files — 파일 일반화 카드"}],
  "progress": {"c2": {"title": "wire-3 — 챗 도구 루프 켜기"}}},
]
json.dump({"date": "2026-10-28", "teams": teams}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
# 원장 픽스처: 골 7행 · 골 칸은 80자 넘는 긴 원문(R1 «줄임 0» 을 실제로 잡는다) · 뒤에 «골 아님» 표를 붙인다
python3 - "$T/ledger.md" <<'PY'
import sys
titles = ["하네스팀 랜딩부터", "말풍선 정상화 — 강의 문장 확정 말풍선 + v65 상하단 긴 발화", "구독 크레딧",
          "리랭커·캐시 → 브레인·챗봇 정본 → 챗 첫 배선 → v65·방·강의 챗 에이전트", "세션 생명주기",
          "이슈 관리 — 일은 깃 이슈로 시작해 정본 등록까지가 완성 · 매일 00시 이슈 정리·중복 묶기",
          "운영 아키텍처 — 대규모 분산(사용자·세션·방 → 엔드포인트 → GPU) · GCP 표준 분산 리서치 · 메인 아키텍처 (#3077)"]
rows = [f"| {t} | 0{i}:0x: 다시 열림 · 진척 {i}/9 · 팩 착지 | r10{i} → press → RESULT |" for i, t in enumerate(titles, 1)]
open(sys.argv[1], "w", encoding="utf-8").write(
    "## 메인 골 7줄 — 지금 상태 (픽스처)\n\n| 골(오빠 원문) | 지금 상태 | 닫히려면 남은 것 |\n|---|---|---|\n"
    + "\n".join(rows) + "\n\n## 다른 절\n\n| x | y |\n|---|---|\n| 골 표 아님 | z |\n")
PY
for i in 1 2 3; do echo "- c$i" > "$ROOT/design/teams/feature/indices/완성/c$i.md"; done
for i in 1 2; do echo "- w$i" > "$ROOT/design/teams/feature/indices/대기/w$i.md"; done
echo "- p1" > "$ROOT/design/teams/feature/indices/진행/p1.md"
for i in 1 2 3 4 5; do echo "- h$i" > "$OPS/design/harness/indices/대기/h$i.md"; done
for i in 1 2; do echo "- hq$i" > "$OPS/design/harness/indices/진행/hq$i.md"; done
echo "- hd1" > "$OPS/design/harness/indices/완성/hd1.md"

# 스텁: ft-card-flow(카드 폴더 실제 개수) · ft-hil · ft-decision-count · mbox(relay 기록만)
cat > "$T/card-flow.sh" <<'SH'
#!/usr/bin/env bash
D=""
while [ $# -gt 0 ]; do case "$1" in --dir) D="$2"; shift 2;; --team|--root) shift 2;; *) shift;; esac; done
w=$(ls "$D/indices/대기"/*.md 2>/dev/null | wc -l | tr -d ' ')
p=$(ls "$D/indices/진행"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "카드 대기 $w · 진행 $p(좌석 1) · 착지됐는데 진행 0"
SH
cat > "$T/hil.sh" <<'SH'
#!/usr/bin/env bash
if [ "${2:-}" = "--each" ]; then printf 'h12 149\nh9 161\n'; else echo "미실행 h 2개 · 가장 오래된 161분"; fi
SH
echo '#!/usr/bin/env bash
echo "결정 인터뷰 27건 · 스크립트 3건 · 팀 대기 26건(가장 오래 byz-knowledge-master-claude#62 174분)"' > "$T/decision.sh"
cat > "$T/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
echo "QUEUED seq=1 to=$2"
SH
chmod +x "$T/card-flow.sh" "$T/hil.sh" "$T/decision.sh" "$T/mbox.sh"
export FT_ROOT="$ROOT" FT_HARNESS_ROOT="$OPS" FT_DESK_LEDGER_FILE="$T/ledger.md" FT_MBOX="$T/mbox.sh"
export FT_CARD_FLOW="$T/card-flow.sh" FT_DESK_HIL="$T/hil.sh" FT_DESK_DECISION="$T/decision.sh"
export FT_DESK_STATE="$T/state" MBOX_LOG="$T/mbox.log"
render() { timeout 70 python3 "${1:-$DESK}" render 2>>"$T/err"; }
runs()   { timeout 70 python3 "${1:-$DESK}" run 2>>"$T/err"; }
mutant() {  # <파일 이름> <sed 식> → 변이판 진입점 경로 (짝 모듈은 그대로 사본 · import 는 PYTHONPATH 로)
  cp "$KITBIN/ft_news_desk.py" "$KITBIN/ft_news_desk_blocks.py" "$T/mut/"
  sed "$2" "$KITBIN/$1" > "$T/mut/$1"; printf '%s' "$T/mut/ft_news_desk.py"
}
mrender() { PYTHONPATH="$KITBIN" timeout 70 python3 "$T/mut/ft_news_desk.py" render 2>>"$T/err"; }
mruns()   { PYTHONPATH="$KITBIN" timeout 70 python3 "$T/mut/ft_news_desk.py" run 2>>"$T/err"; }
relays()  { grep -c 'relay byz-planner-desk-claude#9 ft-news-desk' "$T/mbox.log" 2>/dev/null || true; }

# ── ⓐ 원장 골 표 (R1·R2) ────────────────────────────────────────────────
OUT="$(render)"
eq "ⓐ 골 표 7행" "$(printf '%s' "$OUT" | grep -c '^| [0-9]* | ')" "7"
eq "ⓐ 골 칸 글자 그대로(80자 자르기 0)" "$(printf '%s' "$OUT" | grep -cF '| 7 | 운영 아키텍처 — 대규모 분산(사용자·세션·방 → 엔드포인트 → GPU) · GCP 표준 분산 리서치 · 메인 아키텍처 (#3077) |')" "1"
eq "ⓐ 다른 절 표 안 섞임" "$(printf '%s' "$OUT" | grep -c '골 표 아님')" "0"
eq "ⓐ 머리 = 블록 순서 ①골 ②팀 ③오빠 손" "$(printf '%s' "$OUT" | grep -n '^## ' | cut -d: -f2 | tr '\n' ' ')" "## 골 7줄 지금 상태 ## 팀별 작업 상황 ## 오빠 손 "
mutant ft_news_desk_blocks.py 's/{c\[0\]} | {c\[1\]}/{c[0][:30]} | {c[1]}/' >/dev/null
eq "ⓐ 변이(골 칸 30자 자르기) → 이 시험 문장이 깨진다" "$(mrender | grep -cF '| 7 | 운영 아키텍처 — 대규모 분산(사용자·세션·방 → 엔드포인트 → GPU) · GCP 표준 분산 리서치 · 메인 아키텍처 (#3077) |')" "0"
printf '#!/bin/sh\nsleep 3\nexit 1\n' > "$T/git-slow.sh"; chmod +x "$T/git-slow.sh"
SLOW="$(FT_DESK_LEDGER_FILE='' FT_LEDGER_REPO="$ROOT" FT_DESK_GIT="$T/git-slow.sh" FT_DESK_LEDGER_TIMEOUT=1 render)"
eq "ⓐ-2 느린 원장 → 골 블록 «확인 불가» 1줄" "$(printf '%s' "$SLOW" | grep -c '^확인 불가 — 원장 골 표를 못 읽었다')" "1"
eq "ⓐ-2 느린 원장이어도 팀 표는 나감" "$(printf '%s' "$SLOW" | grep -c '^## 팀별 작업 상황')" "1"
eq "ⓐ-2 빈 골 표 금지" "$(printf '%s' "$SLOW" | grep -c '^| # | 골 |')" "0"

# ── ⓑ 팀별 표 (R3) ──────────────────────────────────────────────────────
eq "ⓑ harness = ops 폴더 숫자(대기 5·진행 2·완성 1)" "$(printf '%s' "$OUT" | grep -c '^| harness | .* | 5 | 2 | 1 | ')" "1"
eq "ⓑ feature 대기 2 · 진행 1 · 완성 3" "$(printf '%s' "$OUT" | grep -c '^| feature | .* | 2 | 1 | 3 | ')" "1"
eq "ⓑ 열린 좌석 = 닫힘·대체 뺀 수(3)" "$(printf '%s' "$OUT" | grep '^| feature |' | awk -F'|' '{gsub(/ /,"",$7); print $7}')" "3"
eq "ⓑ 휴면 팀(kk) 줄 없음" "$(printf '%s' "$OUT" | grep -c '^| kk |')" "0"
eq "ⓑ 지금 하는 일 = 보드 스냅샷 팀 줄" "$(printf '%s' "$OUT" | grep -cF '| feature | 진행: 챗 도구 루프 켜기 / 다음 대기: 파일 일반화 카드 |')" "1"
eq "ⓑ harness 열린 좌석 4(은퇴 행 제외)" "$(printf '%s' "$OUT" | grep '^| harness |' | awk -F'|' '{gsub(/ /,"",$7); print $7}')" "4"
eq "ⓑ 명부 없는 팀은 «확인 불가»(0 으로 내지 않음)" "$(printf '%s' "$OUT" | grep '^| ops |' | grep -c '확인 불가')" "1"
mutant ft_news_desk_blocks.py 's/team_root(team, root)/root \/ "design" \/ "teams" \/ team/' >/dev/null
eq "ⓑ 변이(main 만 셈) → harness 숫자가 틀려 이 시험 문장이 깨진다" "$(mrender | grep -c '^| harness | .* | 5 | 2 | 1 | ')" "0"

# ── ⓒ 바뀐 틱만 relay (R4) · desk 좌석 (R5) ─────────────────────────────
: > "$T/mbox.log"
FT_DESK_NOW="2026-10-28 16:50" runs; eq "ⓒ 첫 틱 rc 0" "$?" "0"
FT_DESK_NOW="2026-10-28 16:59" runs
eq "ⓒ 분만 다른 틱 → relay 0(누적 1통)" "$(relays)" "1"
eq "ⓒ 첫 전문 파일 UTF-8 로 남음" "$(ls "$T/state"/*.md 2>/dev/null | wc -l | tr -d ' ')" "1"
echo "- w3" > "$ROOT/design/teams/feature/indices/대기/w3.md"
FT_DESK_NOW="2026-10-28 17:05" runs
eq "ⓒ 내용이 바뀐 틱 → relay 1통 더(누적 2통)" "$(relays)" "2"
mutant ft_news_desk.py 's/CLOCK.sub("HH:MM", text)/"고정"/' >/dev/null
: > "$T/mbox.log"
export FT_DESK_STATE="$T/state4"
FT_DESK_NOW="2026-10-28 17:11" mruns
echo "- w4" > "$ROOT/design/teams/feature/indices/대기/w4.md"
FT_DESK_NOW="2026-10-28 17:12" mruns
eq "ⓒ 변이(digest 무시) → 두 번째 틱 relay 0(정상은 2통) = 이 시험 문장이 깨진다" "$(relays)" "1"
export FT_DESK_STATE="$T/state"
n_before=$(relays)
echo '{"_desk": "byz-planner-desk-claude#9", "byz-planner-desk-claude#9": {"role": "desk", "_closed": {"by": "x"}}}' > "$T/seats-closed.json"
echo "- w5" > "$ROOT/design/teams/feature/indices/대기/w5.md"
: > "$T/err"
FT_DESK_SEATS="$T/seats-closed.json" FT_DESK_NOW="2026-10-28 17:15" runs; r5=$?
eq "R5 명부 desk 닫힘 → rc≠0" "$([ "$r5" -ne 0 ] && echo yes || echo no)" "yes"
eq "R5 «판정 불가» 1줄" "$(grep -c '판정 불가 desk 좌석' "$T/err")" "1"
eq "R5 relay 0" "$(relays)" "$n_before"

# ── ⓓ 슬랙 한도 회귀(이 카드 밖 칸) ─────────────────────────────────────
eq "ⓓ 뉴스 글 한도 3500B 대조" "$(python3 - "$KITBIN" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_news_publish as p, ft_news_ledger_text as t
print(p.MAX_BYTES, t.MAX_BYTES, p.MAX_BYTES == t.MAX_BYTES == 3500)
PY
)" "3500 3500 True"

# ── ⓔ plist 해석기 = 3.10+ (r1061 · Issue #4064) ────────────────────────────
# 실사건: launchd 가 맥 기본 python(3.9.6)으로 ft_news_desk.py 를 불러 ft_board_env.py 의 «Path | None»(3.10 문법)에서 TypeError.
ENV_PY="$KITBIN/ft_plist_env.py"
TPL="$REPO/harness/kit/fable-team/com.byz.ft-news-desk.plist.template"
G="$T/gitroot"; mkdir -p "$G/.git"   # render_bin 은 <루트>/.git 폴더 유무만 본다(임시 루트 · 실 git 0)
rbin() { timeout 70 python3 "$ENV_PY" render-bin "$1" "$G" 2>&1; }
TPL_OLD='<string>/usr/bin/python3</string>'; TPL_NEW='<string>/opt/homebrew/bin/python3</string>'
rbin "$TPL" > "$T/news.plist"; rc_e=$?
eq "ⓔ R1 렌더 성공" "$rc_e" "0"
eq "ⓔ R1 렌더본 해석기 = /opt/homebrew/bin/python3" "$(plutil -extract ProgramArguments.0 raw "$T/news.plist" 2>/dev/null)" "/opt/homebrew/bin/python3"
eq "ⓔ R2 렌더본에 /usr/bin/python3 0" "$(grep -c '/usr/bin/python3' "$T/news.plist" || true)" "0"
eq "ⓔ R3 템플릿에 __PY__ 0" "$(grep -c '__PY__' "$TPL" || true)" "0"
eq "ⓔ R1 렌더본 자리표시 잔재 0" "$(grep -c '__[A-Z_]\{1,\}__' "$T/news.plist" || true)" "0"
# 변이① 8행을 __PY__ 로 → render_bin 이 채우지 않는 자리표시라 «자리표시 잔재» RenderError
sed "s#$TPL_NEW#<string>__PY__</string>#" "$TPL" > "$T/py.template"
rbin "$T/py.template" > "$T/py.out"; rc_m1=$?
eq "ⓔ 변이(__PY__) → 렌더 실패" "$([ "$rc_m1" -ne 0 ] && echo fail || echo pass)" "fail"
eq "ⓔ 변이(__PY__) → «자리표시 잔재» 1줄" "$(grep -c '자리표시 잔재' "$T/py.out" || true)" "1"
# 변이② 해석기를 /usr/bin/python3 로 되돌림 → 렌더는 되지만 위 R2 칸이 깨진다
sed "s#$TPL_NEW#$TPL_OLD#" "$TPL" > "$T/old.template"
rbin "$T/old.template" > "$T/old.plist"; rc_m2=$?
eq "ⓔ 변이(/usr/bin/python3) → R2 칸이 깨진다" "$([ "$rc_m2" = 0 ] && [ "$(plutil -extract ProgramArguments.0 raw "$T/old.plist" 2>/dev/null)" != "/opt/homebrew/bin/python3" ] && echo broken || echo same)" "broken"

# ── ⓕ 정본 폴더 = env FT_HARNESS_ROOT · 지도 폴백 아님 (r1064 · R1) ─────────
OPS2="$T/ops2"; mkdir -p "$OPS2/design/harness/indices/대기" "$OPS2/design/harness/indices/진행" "$OPS2/design/harness/indices/완성"
for i in 1 2 3 4; do echo "- q$i" > "$OPS2/design/harness/indices/진행/q$i.md"; done
F="$(FT_HARNESS_ROOT="$OPS2" render)"
eq "ⓕ env 폴더 숫자(대기 0·진행 4·완성 0)" "$(printf '%s' "$F" | grep -c '^| harness | .* | 0 | 4 | 0 | ')" "1"
eq "ⓕ 처음 픽스처 숫자(5·2·1) 아님" "$(printf '%s' "$F" | grep -c '^| harness | .* | 5 | 2 | 1 | ')" "0"
mutant ft_news_desk_blocks.py 's|team_root(team, root)|Path(str(root)) / "design" / "harness"|' >/dev/null
eq "ⓕ 변이(env 폴더 무시) → 이 시험 문장이 깨진다" "$(FT_HARNESS_ROOT="$OPS2" mrender | grep -c '^| harness | .* | 0 | 4 | 0 | ')" "0"

# ── ⓖ env 없음 → 지도 폴백 0 · «확인 불가» (R2) ─────────────────────────────
G2="$(FT_HARNESS_ROOT='' render)"
NOENV='| 확인 불가(FT_HARNESS_ROOT 없음) | 확인 불가(FT_HARNESS_ROOT 없음) | 확인 불가(FT_HARNESS_ROOT 없음) | '
eq "ⓖ harness 카드 세 칸 = 확인 불가(FT_HARNESS_ROOT 없음)" "$(printf '%s' "$G2" | grep -c "^| harness | .*${NOENV}")" "1"
eq "ⓖ 다른 팀(feature) 행은 그대로(«확인 불가» 아님)" "$(printf '%s' "$G2" | grep '^| feature |' | grep -c 'FT_HARNESS_ROOT 없음')" "0"
eq "ⓖ feature 행 숫자 칸 실재" "$(printf '%s' "$G2" | grep -c '^| feature | .* | [0-9]\{1,\} | [0-9]\{1,\} | [0-9]\{1,\} | ')" "1"
: > "$T/mbox.log"; : > "$T/err"
FT_HARNESS_ROOT='' FT_DESK_STATE="$T/state-noenv" FT_DESK_NOW="2026-10-28 18:02" runs; rc_g=$?
eq "ⓖ env 없어도 relay 는 나감 rc0" "$rc_g" "0"
eq "ⓖ relay 1통" "$(relays)" "1"
eq "ⓖ ERROR 로그 1줄" "$(grep -c 'harness 카드 숫자 확인 불가: env FT_HARNESS_ROOT 없음' "$T/err")" "1"
mutant ft_news_desk_blocks.py 's/if _needs_env(team, root):/if False:/' >/dev/null
eq "ⓖ 변이(지도 폴백 복원) → 이 시험 문장이 깨진다" "$(FT_HARNESS_ROOT='' mrender | grep -c '확인 불가(FT_HARNESS_ROOT 없음)')" "0"

# ── ⓗ 도구 7초 상한 + 재시도 1 (R3) ────────────────────────────────────────
H1="$T/hil1.mark"; rm -f "$H1"; export H1
cat > "$T/hil-slow1.sh" <<'SH'
#!/usr/bin/env bash
if [ -f "$H1" ]; then printf 'h1 12\n'; else : > "$H1"; sleep 2; printf 'h1 12\n'; fi
SH
chmod +x "$T/hil-slow1.sh"
H3="$(FT_DESK_HIL="$T/hil-slow1.sh" FT_DESK_TOOL_TIMEOUT=1 render)"
eq "ⓗ 첫 호출 상한 초과 → 재시도 성공 값" "$(printf '%s' "$H3" | grep -c '^- 실행할 스크립트: 1개 (미실행 h 1개 · 가장 오래된 12분)')" "1"
eq "ⓗ 성공했으니 «직전 값» 0" "$(printf '%s' "$H3" | grep -c '직전 값')" "0"

# ── ⓘ 둘 다 실패 → 직전 값(HH:MM) · 없으면 확인 불가 (R4·R5) ─────────────────
cat > "$T/hil-fail.sh" <<'SH'
#!/usr/bin/env bash
sleep 2
SH
chmod +x "$T/hil-fail.sh"
FT_DESK_NOW="2026-10-28 16:50" render >/dev/null   # 성공 1회 = 상태 파일에 16:50 이 박힌다
I4="$(FT_DESK_HIL="$T/hil-fail.sh" FT_DESK_TOOL_TIMEOUT=1 render)"
eq "ⓘ R4 직전 값(HH:MM) 줄" "$(printf '%s' "$I4" | grep -c '^- 실행할 스크립트: 직전 값(16:50) · 지금 확인 불가: ')" "1"
eq "ⓘ R4 질문 칸은 성공값(직전 값 아님)" "$(printf '%s' "$I4" | grep -cF -- '- 답 대기 질문: 결정 인터뷰 27건')" "1"
: > "$T/err"
FT_DESK_HIL="$T/hil-fail.sh" FT_DESK_TOOL_TIMEOUT=1 render >/dev/null
eq "ⓘ R4 ERROR 로그 1줄(칸당)" "$(grep -c '오빠 손 실행할 스크립트 칸 확인 불가' "$T/err")" "1"
mv "$ROOT/.fable-team/state/ft-news-desk-last.json" "$T/sticky.bak"
I5="$(FT_DESK_HIL="$T/hil-fail.sh" FT_DESK_TOOL_TIMEOUT=1 render)"
eq "ⓘ R5 상태 파일 없음 → 확인 불가 1줄" "$(printf '%s' "$I5" | grep -c '^- 확인 불가(')" "1"
eq "ⓘ R5 «직전 값» 0" "$(printf '%s' "$I5" | grep -c '직전 값')" "0"
mv "$T/sticky.bak" "$ROOT/.fable-team/state/ft-news-desk-last.json"
mutant ft_news_desk.py 's/if prev.get("at")/if False/' >/dev/null
eq "ⓘ 변이(직전 값 표시 끔) → 이 시험 문장이 깨진다" "$(FT_DESK_HIL="$T/hil-fail.sh" FT_DESK_TOOL_TIMEOUT=1 mrender | grep -c '직전 값(16:50)')" "0"

# ── ⓙ ft-hil 호출 = 틱당 1 (R6) ────────────────────────────────────────────
cat > "$T/hil-count.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HCALL"
printf 'h1 9\nh2 4\n'
SH
chmod +x "$T/hil-count.sh"
HCALL="$T/hil-calls.log"; : > "$HCALL"; export HCALL
FT_DESK_HIL="$T/hil-count.sh" render >/dev/null
eq "ⓙ ft-hil 호출 횟수 1" "$(wc -l < "$HCALL" | tr -d ' ')" "1"
eq "ⓙ 인자 = --pending --each" "$(cat "$HCALL")" "--pending --each"
eq "ⓙ 두 번째 --pending 호출 0" "$(grep -c -- '--pending$' "$HCALL" || true)" "0"

# ── ⓚ plist 템플릿 FT_HARNESS_ROOT (R7) ────────────────────────────────────
rbin "$TPL" > "$T/news2.plist"
eq "ⓚ FT_HARNESS_ROOT 키 1개" "$(grep -c '<key>FT_HARNESS_ROOT</key>' "$T/news2.plist")" "1"
eq "ⓚ 값 = <루트>/.worktrees/harness-ops" "$(plutil -extract EnvironmentVariables.FT_HARNESS_ROOT raw "$T/news2.plist" 2>/dev/null)" "$G/.worktrees/harness-ops"
eq "ⓚ 렌더본 자리표시 잔재 0" "$(grep -c '__[A-Z_]\{1,\}__' "$T/news2.plist" || true)" "0"

echo "RESULT fail=$fail"
[ "$fail" = 0 ]
