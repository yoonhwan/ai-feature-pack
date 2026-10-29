#!/usr/bin/env bash
# test_press_gate_dev_target_r634_b.sh — r634 press 게이트 «dev 대상» 갈래 시험의 2/3 — ⓝ r685 서비스별 본문 판별 · ⓞ1~ⓞ7 (r1134: 한 파일 132초 → 3파일 · 하드 룰 22 «시험 1개 단독 70초»).
#   공용 준비(스텁·mkroot·gate·expect) = lib/press_gate_dev_target_r634.sh · 칸 내용은 쪼개기 전 test_press_gate_dev_target_r634.sh 그대로.
#   짝: test_press_gate_dev_target_r634_a.sh(ⓐ~ⓚ) · _b.sh(ⓝ · ⓞ1~ⓞ7) · _c.sh(ⓞ8 ⓛ ⓜ 정적) — 셋을 다 돌려야 r634 전부다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/press_gate_dev_target_r634.sh"

# ══ ⓝ r685 서비스별 본문 판별 — web = 앱 표지 ∧ 오류 표지 없음 · gateway = status ok JSON 객체
mkroot n1; dev_env
expect 0 'dev web health 200 —' "ⓝ1 web 200 + 정상 앱 HTML(<title>하우투 톡 · /_next/static/ · </html>) → 통과" "${DEV[@]}" FAKE_BODY_WEB="$APP_HTML"
for em in 'Service Unavailable' 'Application failed to start' '502 Bad Gateway' '503 Service Temporarily Unavailable' 'Error: Server Error' 'That’s an error.' 'Internal Server Error' 'Application error: a client-side exception has occurred'; do
  mkroot n2; dev_env
  expect 1 "dev web health 200 이지만 본문에 오류 표지" "ⓝ2 web 200 + 앱 표지 있는 오류 HTML «${em}» → 막힘" "${DEV[@]}" FAKE_BODY_WEB="$(err_page "$em")"
done
mkroot n3; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓝ3 web 200 + 앱 표지 없는 HTML(다른 서비스·빈 페이지) → 막힘" "${DEV[@]}" FAKE_BODY_WEB='<!DOCTYPE html><html><body>hello</body></html>'
mkroot n4; dev_env
expect 1 'dev web health 200 이지만 본문이 비었다' "ⓝ4 web 200 + 빈 본문 → 막힘" "${DEV[@]}" FAKE_BODY_WEB=
mkroot n5; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓝ5 web 200 + JSON 본문(옛 픽스처 기본값) → 막힘" "${DEV[@]}" FAKE_BODY_WEB='{"ok":true}'
mkroot n6; dev_env
expect 0 'dev web health 200 —' "ⓝ6 FT_PRESS_DEV_WEB_MARK 로 앱 표지만 바꾼다(표지 있으면 통과)" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='data-app="byz"' \
  FAKE_BODY_WEB='<html><head><script src="/_next/static/a.js"></script></head><body data-app="byz"><main>다른 이름으로 배포한 우리 앱 화면입니다 — 표지만 다르다</main></body></html>'
mkroot n7; dev_env
expect 1 '앱 표지 «data-app="byz"» 없음' "ⓝ7 표지를 바꾸면 기본 표지(<title>하우투 톡)만으론 막힘" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='data-app="byz"' FAKE_BODY_WEB="$APP_HTML"
mkroot n8; dev_env
expect 1 'dev web health=302' "ⓝ8 web 302(리다이렉트 뒤 다른 서비스) → 막힘(따라가지 않는다)" "${DEV[@]}" FAKE_CURL_WEB=302
mkroot n9; dev_env
expect 1 'dev web health=200 rc=7' "ⓝ9 curl 실패(rc≠0) → 막힘" "${DEV[@]}" FAKE_CURL_RC=7
for gb in '' 'ok' '{"error":"boom"}' '{"status":"degraded"}' '[{"status":"ok"}]' '{"status":"ok"'; do
  mkroot n10; dev_env; gw_why='본문이 status=ok JSON 객체가 아니다'; [ -z "$gb" ] && gw_why='본문이 비었다'
  expect 1 "dev gateway health 200 이지만 ${gw_why}" "ⓝ10 gateway 200 + 본문 «${gb:-빈 본문}» → 막힘" "${DEV[@]}" FAKE_BODY_GW="$gb"
done
mkroot n11; dev_env
expect 0 'dev gateway health 200 —' "ⓝ11 gateway 200 + {\"status\":\"ok\",…} JSON → 통과" "${DEV[@]}" FAKE_BODY_GW='{"status":"ok","service":"gateway"}'
n=$((n+1)); grep -c '^DEV_ERR_MARKS=' "$GATE" | grep -qx 1 && grep -q '^DEV_WEB_MARK="\${FT_PRESS_DEV_WEB_MARK:-' "$GATE" \
  && ok "$n. ⓝ12 오류 표지 목록·앱 표지 기본값 = 파일 맨 위 1곳" || bad "$n. ⓝ12 표지 정의 위치"

# ══ ⓞ r685 DA⑥ r1 반례(H1 앱 표지 고유성 · H2 본문 판별 마감 · H3) — 오류 문구는 구현 목록과 «다른» 철자·대소문자로도
for em in 'Application error: a server-side exception has occurred (see the server logs for more information).' 'Failed to compile' 'service unavailable' '404 — 페이지를 찾을 수 없습니다' '404: This page could not be found.'; do
  mkroot o1; dev_env
  expect 1 "dev web health 200 이지만 본문에 오류 표지" "ⓞ1 앱 표지 다 갖춘 Next 오류 화면 «${em}» → 막힘" "${DEV[@]}" FAKE_BODY_WEB="$(err_page "$em")"
done
mkroot o2; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓞ2 200 로그인 화면(Sign in · /_next/static/ 있음 · 우리 제목 없음) → 막힘" "${DEV[@]}" \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><title>Sign in - Google Accounts</title><script src="/_next/static/s.js"></script></head><body><h1>Sign in</h1><p>to continue to Cloud Run — use your Google Account</p></body></html>'
mkroot o3; dev_env
expect 1 'dev web health 200 이지만 본문 <body> 의 보이는 글자' "ⓞ3 빈 body + 앱 표지만(정적 껍데기) → 막힘" "${DEV[@]}" \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><title>하우투 톡</title><script src="/_next/static/a.js"></script></head><body><div id="root"></div><script>self.__next_f.push([1,"하우투 톡 실시간 AI 통역 화면 데이터 조각"])</script></body></html>'
mkroot o4; dev_env
expect 1 'dev web health 200 이지만 본문에 «</html>» 없음' "ⓞ4 앱 표지만 있는 잘린 본문(</html> 없음) → 막힘" "${DEV[@]}" FAKE_BODY_WEB="${APP_HTML%</body></html>}"
mkroot o5; dev_env
expect 0 'dev web health 200 —' "ⓞ5 정상 화면의 스크립트(RSC 데이터) 안 «This page could not be found» 는 통과(실측 dev 루트 2회 · 보이는 글자만 대조)" "${DEV[@]}" \
  FAKE_BODY_WEB="${APP_HTML%</body></html>}<script>self.__next_f.push([1,\"404: This page could not be found.\"])</script></body></html>"
mkroot o6; dev_env
expect 1 'FT_PRESS_DEV_WEB_MARK=«<» 1글자 — 6글자 미만' "ⓞ6 약한 env 표지 «<» → 경고 + 기본값으로 판별(제목 없는 화면 막힘)" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='<' \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><script src="/_next/static/x.js"></script></head><body><main>아무 Next 앱 화면 — 우리 제목은 없다 아무 글자</main></body></html>'
printf '%s' "$OUT" | grep -q '본문에 앱 표지 «<title>하우투 톡» 없음' && ok "  ⓞ6b 기본값 «<title>하우투 톡» 으로 막았다" || bad "  ⓞ6b 기본값 판별 아님"
mkroot o7; dev_env
expect 1 'dev web health 200 이지만 본문 판별 실패' "ⓞ7 본문 판별 python 실패(rc=1·출력 0) → 막힘(fail-closed)" "${DEV[@]}" FAKE_PY=fail

r634_finish
