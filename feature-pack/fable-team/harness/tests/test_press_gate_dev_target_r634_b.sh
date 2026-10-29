#!/usr/bin/env bash
# test_press_gate_dev_target_r634_b.sh — r634 press 게이트 «dev 대상» 갈래 시험의 2/3 — ⓝ r685 서비스별 본문 판별 (r1134: 한 파일 132초 → 3파일 · 하드 룰 22 «시험 1개 단독 70초»).
#   공용 준비(스텁·mkroot·gate·expect) = lib/press_gate_dev_target_r634.sh · 칸 내용은 쪼개기 전 test_press_gate_dev_target_r634.sh 그대로.
#   짝: test_press_gate_dev_target_r634_a.sh(ⓐ~ⓚ) · _b.sh(ⓝ) · _c.sh(ⓞ ⓛ ⓜ 정적) — 셋을 다 돌려야 r634 전부다.
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

r634_finish
