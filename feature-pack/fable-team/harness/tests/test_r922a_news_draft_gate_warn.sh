#!/usr/bin/env bash
# test_r922a_news_draft_gate_warn.sh — r922a: 옛 뉴스 잡(FT_NEWS_MODE=draft)의 골 표 묶음 검증 실패는 planner [긴급] 이 아니라 WARN 1줄 · 발행 0·rc 는 지금 그대로.
# 축 = ⓐ draft+무장(통지 0 · WARN 1) ⓐ' 게이트 본체 없음(draft) ⓑ html 모드(긴급 1 = 회귀 0) ⓑ' 본체 없음(html) ⓒ draft+정상 묶음(WARN 0) ⓓ env 오타(drafts → draft 아님) ⓔ draft+비무장(지금 그대로)
# 픽스처 = mktemp 격리 루트(armed 표식 · seats-planner.json · 대역 mbox.sh · 대역 발행 도구) + 골 표 정본·원장 파일 — 실 루트·실 큐·실 슬랙 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in FT_NEWS_MODE FT_NEWS_PUBLISH FT_NEWS_NOW FT_MBOX FT_ROOT FT_GOAL_A6_MD FT_GOAL_A6_LEDGER; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

# ── 골 표 정본·원장 픽스처(정상 묶음용) — 실 정본 파일을 읽지 않는다
CANON="$T/CANON.md"; LEDGER="$T/LEDGER.md"
cat > "$CANON" <<'EOF'
# 자율 골 A6 (시험 픽스처)

## 골 → 팀 → 닫는 증거

| 골(원문) | 담당 팀 | 닫는 증거 |
|---|---|---|
| v65 마이크 넘기기 완성 | v65 | sha |
| m.room 멀티 사용자 | room | sha |
| m.lecture 멀티 사용자 | lecture | sha |
| 하네스팀 랜딩부터 | harness | sha |
| 전팀 지침과 재기동 | harness · planner | 0 |
| 메모리 세션 제한 | harness | 0 |
EOF
python3 - "$LEDGER" > "$LEDGER" <<'PY'
import datetime, sys
print("# 오빠 원장\n\n> 마지막 갱신: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M") + "\n\n## 메인 골 6줄\n\n| 골(오빠 원문) | 지금 상태 | 닫히려면 남은 것 |\n|---|---|---|")
for i in range(1, 7):
    print(f"| 원장 글자 {i} | 상태{i} 진행 | 남은{i} |")
PY
mk_sandbox() { mkdir -p "$T/sb/.fable-team/state"; : > "$T/sb/.fable-team/LIVE_BIN"; printf '%s\n' "$T/sb" > "$T/sb/.fable-team/LIVE_ROOT"; }
mk_sandbox
GOAL_ENV=(FT_ROOT="$T/sb" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_LEDGER="$LEDGER")
BLOCK="$T/block.txt"
env "${GOAL_ENV[@]}" bash "$BIN/ft-goal-table.sh" > "$BLOCK" 2>"$T/render.err"; RC=$?
[ "$RC" = 0 ] && head -1 "$BLOCK" | grep -q '^★골 표 A6 (' && ok "픽스처: 정상 골 표 블록 렌더 rc0" || bad "픽스처 렌더 rc=$RC :: $(head -2 "$BLOCK") :: $(cat "$T/render.err")"
printf '%s\n' "$(cat "$BLOCK")" > "$T/part-ok.txt"
printf '# 뉴스 판 (골 표 블록 없음 — 검증한 판과 본문이 다르다)\n\n*바뀐 것*\n- 한 줄\n' > "$T/part-bad.txt"

# ── 격리 루트: armed 표식 · planner 명부 · 대역 mbox(송신 기록) · 대역 발행 도구(호출 기록)
mk_root() {  # <이름> [armed=1] → ROOT
  ROOT="$T/$1"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm" "$ROOT/design/planner/news"
  echo '{"_master":"byz-planner-master-claude#9","_desk":"byz-planner-desk-claude#3"}' > "$ROOT/.fable-team/seats-planner.json"
  printf '#!/bin/sh\nprintf "CALL %%s\\n" "$1" >> "%s/mbox.log"\nprintf "%%s\\n" "$*" >> "%s/mbox-body.log"\nexit 0\n' "$ROOT" "$ROOT" > "$ROOT/.fable-team/comm/mbox.sh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/publish.log"\necho "ft-news-publish: 발행 완료 ts=1.0 channel=SLACK permalink=-"\nexit 0\n' "$ROOT" > "$ROOT/publish.sh"
  chmod +x "$ROOT/.fable-team/comm/mbox.sh" "$ROOT/publish.sh"
  [ "${2:-1}" = 1 ] && : > "$ROOT/.fable-team/state/goal-gate.armed"
  return 0
}
sends() { [ -f "$ROOT/mbox.log" ] && wc -l < "$ROOT/mbox.log" | tr -d ' ' || echo 0; }
pubs()  { [ -f "$ROOT/publish.log" ] && wc -l < "$ROOT/publish.log" | tr -d ' ' || echo 0; }

# ── 구동기 — ft_news_post.publish 한 번(실 모듈 · 대역은 mbox·발행 도구뿐)
drive() {  # <bin 디렉터리> <루트> <판 파일> <모드(빈 값=env 없음)> → stdout · stderr=$T/err · RC
  OUT="$(env PATH="$PATH" "${GOAL_ENV[@]}" FT_MBOX= FT_NEWS_PUBLISH="bash $ROOT/publish.sh" \
    ${4:+FT_NEWS_MODE="$4"} python3 - "$1" "$ROOT" "$3" "$T/err" <<'PY' 2>>"$T/err"
import logging, sys
from datetime import datetime
from pathlib import Path
sys.path.insert(0, sys.argv[1])
logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
import ft_news_post as np
root = Path(sys.argv[2])
parts = [Path(sys.argv[3]).read_text(encoding="utf-8")]
rc, posts = np.publish(root / "design/planner/news", root / ".fable-team/state/news-ledger", parts, datetime(2026, 10, 26, 12, 0), "a" * 40)
print(f"RC={rc} posts={len(posts)}")
raise SystemExit(0)
PY
)"; RC=$?
  ERR="$(cat "$T/err" 2>/dev/null)"; return 0
}

# ⓐ 초안 모드 + 무장 + 검증 실패 → planner [긴급] 0 · WARN 1줄 · 발행 0 · rc 지금과 같다(3)
mk_root a; : > "$T/err"; drive "$BIN" "$ROOT" "$T/part-bad.txt" draft
rc_is "$RC" 0 "ⓐ 구동기 정상 종료"
has "$OUT" "RC=3" "ⓐ rc = 지금과 같다(3 · 발행 0)"
[ "$(sends)" = 0 ] && ok "ⓐ mbox 송신 0(planner [긴급] 없음)" || bad "ⓐ mbox 송신 $(sends)건 ← $(cat "$ROOT/mbox.log" 2>/dev/null | head -3)"
[ "$(grep -c '^WARNING WARN draft 묶음 검증 실패(긴급 0 — 발행 0 모드) ' <<<"$ERR")" = 1 ] && ok "ⓐ WARN «draft 묶음 검증 실패(긴급 0 — 발행 0 모드)» 1줄" || bad "ⓐ WARN 줄 :: $ERR"
hasnt "$ERR" "REJECT 골 표 없음" "ⓐ ERROR «REJECT 골 표 없음» 0(초안 모드는 로그 경고 1줄로만)"
hasnt "$ERR" "Traceback" "ⓐ Traceback 0"
[ "$(pubs)" = 0 ] && ok "ⓐ 발행 도구 호출 0" || bad "ⓐ 발행 도구 $(pubs)회"
[ ! -f "$ROOT/.fable-team/state/news-ledger/last.sha" ] && ok "ⓐ 기준선(last.sha) 안 옮김" || bad "ⓐ last.sha 생김"

# ⓐ' 게이트 본체(ft_goal_gate) 설치 누락 + 초안 모드 + 무장 → 최소 통지(_notify_minimal)도 0 · WARN 1줄 · rc 3
SOLO="$T/solo"; mkdir -p "$SOLO"; cp "$BIN/ft_news_post.py" "$SOLO/"
mk_root ap; : > "$T/err"; drive "$SOLO" "$ROOT" "$T/part-bad.txt" draft
has "$OUT" "RC=3" "ⓐ' 본체 없음 + draft rc 3(발행 0 그대로)"
[ "$(sends)" = 0 ] && ok "ⓐ' 본체 없음 + draft → 최소 통지 0" || bad "ⓐ' mbox $(sends)건 ← $(cat "$ROOT/mbox.log" 2>/dev/null | head -3)"
[ "$(grep -c '^WARNING WARN draft 묶음 검증 실패(긴급 0 — 발행 0 모드) ' <<<"$ERR")" = 1 ] && ok "ⓐ' 본체 없음 + draft WARN 1줄" || bad "ⓐ' WARN :: $ERR"
hasnt "$ERR" "Traceback" "ⓐ' Traceback 0"

# ⓑ 발행 모드(html) + 무장 + 같은 입력 → [긴급] 1통 · rc 3 (회귀 0)
mk_root b; : > "$T/err"; drive "$BIN" "$ROOT" "$T/part-bad.txt" html
has "$OUT" "RC=3" "ⓑ html rc 3"
[ "$(sends)" = 1 ] && ok "ⓑ html → planner [긴급] 1통" || bad "ⓑ html mbox $(sends)건"
has "$(cat "$ROOT/mbox-body.log" 2>/dev/null)" "[긴급] 뉴스 발행 거절 — 골 표" "ⓑ 쪽지 머리 «[긴급] 뉴스 발행 거절 — 골 표»"
has "$ERR" "ERROR REJECT 골 표 없음" "ⓑ html → ERROR «REJECT 골 표 없음» 1줄(지금 그대로)"
hasnt "$ERR" "WARN draft 묶음 검증 실패" "ⓑ html → draft WARN 0"
[ "$(pubs)" = 0 ] && ok "ⓑ html 검증 실패 = 발행 0" || bad "ⓑ 발행 도구 $(pubs)회"

# ⓑ' 본체 없음 + 발행 모드(html) → 최소 통지 [긴급] 1통 (회귀 0)
mk_root bp; : > "$T/err"; drive "$SOLO" "$ROOT" "$T/part-bad.txt" html
[ "$(sends)" = 1 ] && ok "ⓑ' 본체 없음 + html → 최소 통지 1통" || bad "ⓑ' mbox $(sends)건"
has "$(cat "$ROOT/mbox-body.log" 2>/dev/null)" "[긴급] 뉴스 발행 거절 — 골 표" "ⓑ' 쪽지 머리 «[긴급] …»"

# ⓒ 초안 모드 + 정상 묶음 → 지금과 같은 결과(WARN 0 · 통지 0 · rc 0 · 발행 0)
mk_root c; : > "$T/err"; drive "$BIN" "$ROOT" "$T/part-ok.txt" draft
has "$OUT" "RC=0" "ⓒ draft + 정상 묶음 rc 0"
hasnt "$ERR" "WARN draft 묶음 검증 실패" "ⓒ WARN 0"
hasnt "$ERR" "REJECT" "ⓒ REJECT 0"
[ "$(sends)" = 0 ] && ok "ⓒ 통지 0" || bad "ⓒ mbox $(sends)건"
[ "$(pubs)" = 0 ] && ok "ⓒ 초안 모드 = 발행 도구 0" || bad "ⓒ 발행 도구 $(pubs)회"
[ -f "$ROOT/design/planner/news/NEWS-20261026-1200.md" ] && ok "ⓒ 초안 파일은 남는다" || bad "ⓒ 초안 파일 없음"

# ⓓ env 오타(FT_NEWS_MODE=drafts)·빈 값 → draft 로 «안» 읽힌다(발행 모드와 같이 [긴급] 1통) — 조용한 강등 0
for v in drafts ""; do
  mk_root d; : > "$T/err"; drive "$BIN" "$ROOT" "$T/part-bad.txt" "$v"
  [ "$(sends)" = 1 ] && ok "ⓓ FT_NEWS_MODE='$v' → draft 아님([긴급] 1통)" || bad "ⓓ '$v' mbox $(sends)건"
  hasnt "$ERR" "WARN draft 묶음 검증 실패" "ⓓ '$v' → draft WARN 0"
done

# ⓔ 초안 모드 + 비무장(armed 없음) → 지금 그대로: WOULD-REJECT 로그만 · 통지 0 · rc 0
mk_root e 0; : > "$T/err"; drive "$BIN" "$ROOT" "$T/part-bad.txt" draft
has "$OUT" "RC=0" "ⓔ draft + 비무장 rc 0(지금 그대로)"
grep -q 'WOULD-REJECT' "$ROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓔ WOULD-REJECT 로그 남음" || bad "ⓔ WOULD-REJECT 로그 없음"
[ "$(sends)" = 0 ] && ok "ⓔ 비무장 통지 0" || bad "ⓔ mbox $(sends)건"

# ── 짝 사본(설치본) 바이트 동일
cmp -s "$BIN/ft_news_post.py" "$KIT/ft_news_post.py" && ok "짝 사본 kit cmp0" || bad "짝 사본 kit 다름"

echo "== fail=$fail"; [ "$fail" = 0 ]
