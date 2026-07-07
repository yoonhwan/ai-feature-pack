# 검증 시나리오 (daily-trend-viewer)

전제: `feature-pack/daily-trend-viewer/` 루트에서 실행. jq 불요, curl만 사용.

## V1. 로컬 기동
    cd app && python3 server.py > /tmp/dtv-server.log 2>&1 &
    sleep 2
    curl -s -o /dev/null -w "%{http_code}" http://localhost:28088/
기대: `200` (본문은 index.html). 실패 시 /tmp/dtv-server.log 확인.

## V2. CSRF 방어
    # (a) Origin 없음 → 403
    curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:28088/api/reels/accounts \
      -H "Content-Type: text/plain" -d '{"action":"add","username":"csrf_probe"}'
    # (b) 타 Origin → 403
    curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:28088/api/reels/accounts \
      -H "Origin: https://evil.example" -H "Content-Type: text/plain" \
      -d '{"action":"add","username":"csrf_probe"}'
    # (c) 정상 Origin → 200, 응답 accounts에 csrf_probe 포함
    curl -s -X POST http://127.0.0.1:28088/api/reels/accounts \
      -H "Origin: http://localhost:28088" -H "Content-Type: application/json" \
      -d '{"action":"add","username":"csrf_probe"}'
    # (d) 정리: 같은 Origin으로 {"action":"remove","username":"csrf_probe"} POST → 200,
    #     응답 accounts에 csrf_probe 없음
기대: (a) `403` / (b) `403` / (c) `200` + `"csrf_probe"` 포함 / (d) `200` + 미포함.
(a)(b)에서 app/reels_accounts.json이 생성·변경되지 않았는지도 확인.

## V3. SSRF 방어 (/api/img)
    # (a) allowlist 밖 호스트 → 400
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:28088/api/img?u=https://evil.example/x.jpg"
    # (b) userinfo 우회 시도 → 400
    curl -s -o /dev/null -w "%{http_code}" -G "http://127.0.0.1:28088/api/img" \
      --data-urlencode "u=https://i.ytimg.com@evil.example/x.jpg"
    # (c) 유사 도메인(접미 아님) → 400
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:28088/api/img?u=https://evilytimg.com/x.jpg"
    # (d) http(비 https) → 400
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:28088/api/img?u=http://i.ytimg.com/x.jpg"
    # (e) 정상 allowlist 호스트 → 400이 아니어야 함 (200 또는 원격 실패 시 502)
    curl -s -o /dev/null -w "%{http_code}" -G "http://127.0.0.1:28088/api/img" \
      --data-urlencode "u=https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
기대: (a)~(d) `400` / (e) `200` (네트워크 불가 환경이면 `502` 허용 — 400만 아니면 allowlist 통과 판정).

## V4. 정리
    kill %1  # 또는 pkill -f "python3 server.py"
    rm -f app/reels_accounts.json  # V2에서 생성된 경우만 (기본값 복원 목적)
