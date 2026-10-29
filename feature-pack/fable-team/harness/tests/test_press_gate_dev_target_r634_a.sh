#!/usr/bin/env bash
# test_press_gate_dev_target_r634_a.sh — r634 press 게이트 «dev 대상» 갈래 시험의 1/3 — ⓐ~ⓚ (r1134: 한 파일 132초 → 3파일 · 하드 룰 22 «시험 1개 단독 70초»).
#   공용 준비(스텁·mkroot·gate·expect) = lib/press_gate_dev_target_r634.sh · 칸 내용은 쪼개기 전 test_press_gate_dev_target_r634.sh 그대로.
#   짝: test_press_gate_dev_target_r634_a.sh(ⓐ~ⓚ) · _b.sh(ⓝ) · _c.sh(ⓞ ⓛ ⓜ 정적) — 셋을 다 돌려야 r634 전부다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/press_gate_dev_target_r634.sh"

# ══ ⓐ dev 선언 + 로컬 리스너 0 + web·gateway 200 + 세 이미지 ⊇ WANT → 통과
mkroot a; dev_env
n=$((n+1)); gate "${DEV[@]}"; got=$?
[ "$got" -eq 0 ] && printf '%s' "$OUT" | grep -q 'dev 대상 — 로컬 칸 ②~⑤ 대신' \
  && printf '%s' "$OUT" | grep -q 'dev 러너 대상 일치' \
  && printf '%s' "$OUT" | grep -q 'dev web health 200' && printf '%s' "$OUT" | grep -q 'dev gateway health 200' \
  && printf '%s' "$OUT" | grep -q 'dev 이미지 worker ⊇' && ! printf '%s' "$OUT" | grep -q '리스너 없음' \
  && printf '%s' "$OUT" | grep -q 'PRESS-GATE PASS' \
  && ok "$n. ⓐ dev 선언 + 로컬 리스너 0 + web·gateway 200 + 세 이미지 ⊇ WANT → 통과 (exit $got)" \
  || { bad "$n. ⓐ dev 통과 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
n=$((n+1)); pf="$CASE/permits/byz-v65-tester-claude#0.json"
[ -f "$pf" ] && [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["target"])' "$pf" 2>/dev/null)" = dev ] \
  && [ "$(awk -F'\t' 'END{print NF"="$NF}' "$CASE/permits/permits.log")" = "6=dev" ] \
  && printf '%s' "$OUT" | grep -q '⑥ 기준선' && printf '%s' "$OUT" | grep -q '⑦ 역할 tester' \
  && ok "$n. ⓐ 허가 파일 target=dev(json) · permits.log 끝칸 dev · ⑥⑦⑧ 그대로 판정" \
  || { bad "$n. ⓐ 허가 target 칸"; cat "$pf" 2>/dev/null; cat "$CASE/permits/permits.log" 2>/dev/null; }

# ══ ⓑ~ⓗ 부정 칸
mkroot b; dev_env
expect 1 'dev gateway health=503' "ⓑ dev gateway 503 → 막힘" "${DEV[@]}" FAKE_CURL_GW=503
mkroot c; dev_env
expect 1 "byz-agents-worker-dev 이미지 ${SIDE:0:10} 에 ${SHA:0:10} 없음" "ⓒ worker 이미지에 WANT 없음 → 막힘" "${DEV[@]}" FAKE_IMG_WORKER="$SIDE"
mkroot d1; dev_env
expect 1 'dev worker 이미지 sha 못 읽음' "ⓓ1 이미지 못 읽음(빈 값) → 막힘" "${DEV[@]}" FAKE_IMG_WORKER=""
mkroot d2; dev_env
expect 1 'dev gateway 이미지 sha 못 읽음' "ⓓ2 이미지 형식 불명(:latest) → 막힘" "${DEV[@]}" FAKE_IMG_GATEWAY='r/gateway:latest'
mkroot d3; dev_env
expect 1 'dev web 이미지 sha 못 읽음' "ⓓ3 이미지 태그 39자(축약 sha) → 막힘" "${DEV[@]}" FAKE_IMG_WEB="${SHA:1}"
mkroot e
expect 1 '원하는 커밋 미지정' "ⓔ FT_PRESS_DEV_WANT 없음 → 막힘" FT_PRESS_TARGET=dev BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" \
  FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot f
expect 1 'FT_PRESS_TARGET=prod — 대상은 local(기본)·dev 만' "ⓕ 대상=prod → 막힘" FT_PRESS_TARGET=prod
mkroot g
expect 1 '리스너 없음(:8081)' "ⓖ 선언 없음 → 로컬 칸 그대로(막힘)" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
expectnot 1 'dev 대상 — 로컬 칸' "ⓖ 선언 없음 → dev 갈래 출력 0" FAKE_CURL_WEB=200

# ══ ⓗ dev 선언이어도 ⑥⑦⑧ 은 그대로 막는다
mkroot h1; dev_env
n=$((n+1)); OUT="$(env -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_DEV_WANT \
  FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$SHA" BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" \
  FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA" \
  FT_PRESS_WT="$R" FT_PRESS_ROOT="$CASE/root" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" \
  TMUX_PANE=%1 FAKE_TMUX_SESSION='byz-v65-tester-claude#0' \
  SVC_WEB="$SVC_WEB" SVC_GW="$SVC_GW" SVC_WK="$SVC_WK" EXP_WEB="$EXP_WEB" EXP_GATEWAY="$EXP_GW" \
  PATH="$CASE/fakebin:$PATH" bash "$SUT" 2>&1)"; got=$?
[ "$got" -eq 1 ] && printf '%s' "$OUT" | grep -q '⑥ 카드 미지정' && printf '%s' "$OUT" | grep -q 'dev web health 200' \
  && ok "$n. ⓗ1 dev 선언 + ⑥ 카드 미지정 → 막힘(dev 칸 통과했는데 ⑥ 이 막는다) (exit $got)" \
  || { bad "$n. ⓗ1 ⑥ 카드 미지정 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
mkroot h2; dev_env
expect 1 '⑦ 역할 nano — press 는 tester·checker 만' "ⓗ2 dev 선언이어도 ⑦ 역할 nano → 막힘" "${DEV[@]}" FAKE_TMUX_SESSION='byz-harness-nano-x#0'
mkroot h3; dev_env
mkdir -p "$CASE/prev3"
printf '| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 |  |  |\n| 코드 |  |  |\n| 로그 |  |  |\n| 화면 |  |  |\n' > "$CASE/prev3/BTS.md"
printf '{"seat":"byz-v65-tester-claude#0","role":"tester","evid":"%s"}\n' "$CASE/prev3" > "$CASE/permits/byz-v65-tester-claude#0.json"
expect 1 '⑧ 직전 회차 BTS 표 미완' "ⓗ3 dev 선언이어도 ⑧ 직전 BTS 빈칸 → 막힘" "${DEV[@]}" FT_PRESS_EVID="$CASE/ev-h3"
mkroot h4; dev_env
mkdir -p "$CASE/prev" && printf '| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | a | 1 |\n| 코드 | b | 2 |\n| 로그 | c | 3 |\n| 화면 |  |  |\n' > "$CASE/prev/BTS.md"
printf '{"seat":"byz-v65-tester-claude#0","role":"tester","evid":"%s"}\n' "$CASE/prev" > "$CASE/permits/byz-v65-tester-claude#0.json"   # 옛 꼴(target 칸 없음)
expect 1 '모자란 칸: 화면' "ⓗ4 옛 허가(target 칸 없음)도 ⑧ 이 읽는다(하위 호환)" "${DEV[@]}"

# ══ ⓘ H1 러너 대상 ↔ 게이트 대상 결합(dev 선언만 하고 러너는 localhost 로 쏘는 길)
mkroot i1; dev_env
expect 1 'BYZ_WEB_BASE 이 비었다' "ⓘ1 러너 env BYZ_WEB_BASE 없음 → 막힘" "${DEV[@]}" BYZ_WEB_BASE=
mkroot i2; dev_env
expect 1 'BYZ_GATEWAY_BASE=http://localhost:8080 ≠' "ⓘ2 러너가 localhost 로 쏘면 → 막힘" "${DEV[@]}" BYZ_GATEWAY_BASE=http://localhost:8080

# ══ ⓙ H2 sha 판정(종료코드·40자·WANT 출처)
mkroot j1; dev_env
expect 1 'dev web 이미지 sha 못 읽음' "ⓙ1 gcloud rc≠0 + 유효 태그 출력 → 막힘(종료코드 유실 금지)" "${DEV[@]}" FAKE_GCLOUD_RC=1
mkroot j2
expect 1 'FT_PRESS_DEV_WANT=main — 40자 hex' "ⓙ2 WANT=가지 이름 → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT=main \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot j3
expect 1 'FT_PRESS_DEV_WANT=HEAD~1 — 40자 hex' "ⓙ3 WANT=HEAD~1 → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT=HEAD~1 \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot j4; dev_env
expect 1 '≠ press 워크트리 HEAD' "ⓙ4 WANT=오래된 조상(≠HEAD) → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$SHA_PREV" \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA_PREV" FAKE_IMG_GATEWAY="$SHA_PREV" FAKE_IMG_WORKER="$SHA_PREV"

# ══ ⓚ H3 세 서비스 필수 · health 본문
mkroot k1; dev_env
expect 1 'FT_PRESS_DEV_SVCS 에 worker 가 없다' "ⓚ1 SVCS 에 web·gateway 만 → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=web="$SVC_WEB",gateway="$SVC_GW"
mkroot k2; dev_env
expect 1 'FT_PRESS_DEV_SVCS 에 web 가 없다' "ⓚ2 SVCS 빈 값(루프 0회 통과 0) → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=' '
mkroot k3; dev_env
expect 1 'FT_PRESS_DEV_SVCS 중복: web' "ⓚ3 SVCS 중복 → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=web="$SVC_WEB",web="$SVC_WEB",gateway="$SVC_GW",worker="$SVC_WK"
mkroot k4; dev_env
expect 1 'dev gateway health 200 이지만 본문이 status=ok JSON 객체가 아니다' "ⓚ4 gateway 200 이지만 HTML 오류 페이지 → 막힘(r685: JSON 판별)" "${DEV[@]}" FAKE_BODY_GW='<!DOCTYPE html><html><body>error</body></html>'

r634_finish
