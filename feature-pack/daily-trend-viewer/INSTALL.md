# 설치 가이드 (에이전트용)

## 1. 사전 조건 확인
- `python3 --version` (mac) 또는 `python --version`/`py --version` (win) → 3.8 이상.
- 미설치 시: https://www.python.org/downloads/ 안내 (win은 "Add Python to PATH" 체크 필수).
- 외부 패키지 설치 불요 (표준 라이브러리만 사용), API 키 불요.

## 2. 배치
- 이 디렉토리(`feature-pack/daily-trend-viewer/`)의 `app/` 폴더가 실행 단위 전부다.
- 사용자가 원하는 위치로 `app/`을 통째 복사해도 되고, 이 위치에서 바로 실행해도 된다.
- mac: `chmod +x app/실행-Mac.command` 확인.
- 포트 28088이 사용 중이면 `app/server.py` 상단 `PORT = 28088`을 빈 포트로 변경.

## 3. 실행
- mac: `app/실행-Mac.command` 더블클릭 (게이트키퍼 경고 시 우클릭→열기), 또는
  `cd app && python3 server.py`
- windows: `app\실행-Windows.bat` 더블클릭
- 브라우저에서 http://localhost:28088 접속. 종료는 터미널 창 닫기(Ctrl+C).

## 4. 확인
- `curl -s -o /dev/null -w "%{http_code}" http://localhost:28088/` → `200`
- 상세 검증은 `test/verify.md` 참조.

## 5. 데이터 파일
- 구독 계정 목록(`reels_accounts.json` 등 4종)은 첫 변경 시 `app/`에 자동 생성 — 백업/이동 시 함께 복사.
