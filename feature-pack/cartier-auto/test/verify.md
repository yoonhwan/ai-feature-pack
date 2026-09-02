# cartier-auto 검증 절차

설치/업데이트 후 아래 순서로 정상 동작을 확인한다.

## 1. 정적 검증 (설치 무관)

```bash
cd <feature-pack>/cartier-auto
python3 skill/scripts/quick_validate.py
# 기대: "OK cartier-auto 구조·frontmatter 검증 통과"

python3 skill/scripts/tests/test_cartier_auto.py
# 기대: 10/10 tests passed
```

## 2. 설치 상태

```bash
bash skill/scripts/run.sh setup --json
# 기대: installed: true, codex/claude/bin: true

bash skill/scripts/run.sh doctor --json
# 기대: ready: true (설치 + python + chrome + runtime + credentials)
```

## 3. 브라우저 검증 (실제 자격증명 필요)

```bash
bash skill/scripts/run.sh wishlist --json
# 기대: 위시리스트 상품 목록(이름/PID/가격) JSON 출력
#       0개여도 오류 없이 "items": [] (정상 조회 성공)
# 재캡처/로그인 폼이 뜨면 브라우저 창에서 직접 인증 → 대기 후 결과
```

## 4. 상태 전이 검증 (감시 루프)

```bash
# 예약 생성 → 시작 → 상태 확인 → 중지
bash skill/scripts/run.sh schedule --pid CRB7215800 --at '<미래 시각>' --interval 5 --approved-price 2340000 --confirm
bash skill/scripts/run.sh launch --job <JOBID>
bash skill/scripts/run.sh status --job <JOBID> --json
#   기대: SCHEDULED → PREWARM → WATCHING 전이 발생
bash skill/scripts/run.sh stop --job <JOBID>
#   기대: STOPPED + 프로세스·tmux 종료 (stopped: true)
```

## 5. 보안 체크

- `credentials.env` 권한 0600, 값이 로그/JSON/스크린샷에 노출되지 않아야 함
- `installed.json`에 자격증명 값 없음
- 공유 시 `credentials.env`/`session-state.json`/`installed.json`/`logs` 제외
