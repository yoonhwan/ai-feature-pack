# 💎 Cartier Auto Feature Pack v1.0.0

**까르띠에 공식 몰 리스톡(wishlist) 자동 구매 감시.**

예약 시각부터 지정한 주기로 위시리스트를 감시해, 상품이 구매 가능해지면
쇼핑백 추가 → 구매 → 네이버페이 결제까지 자동 진행한다.

- **사용자 개입 2번만**: 네이버 CAPTCHA + 네이버페이 보안 키패드
- **지원**: macOS + Google Chrome + 한국 까르띠에 사이트 + Naver Pay (v1)
- **안전장치**: 승인 가격 초과 시 결제 차단(`PRICE_BLOCKED`), 장바구니 비었는지 사전 점검, 주문확정 후 중복 결제 금지

## 빠른 시작

```bash
# 1. 설치 (환경 체크 → 대화형 확인 → 설치 → 상태 저장)
bash skill/scripts/install.sh

# 2. 자격증명 등록 (까르띠에/네이버 ID·PW 4종)
bash skill/scripts/setup-credentials.sh

# 3. 상태 확인
bash skill/scripts/run.sh doctor --json
```

자세한 설치·공유·시나리오는 [INSTALL.md](INSTALL.md)와 [SHARING.md](skill/SHARING.md) 참고.

## 명령

| 명령 | 용도 |
|---|---|
| `cartier-auto doctor` | 설치·자격증명 readiness |
| `cartier-auto setup` | 설치 상태 확인 (미설치 시 설치 유도) |
| `cartier-auto wishlist` | 위시리스트 상품 조회 |
| `cartier-auto schedule` | 구매 예약 작업 생성 |
| `cartier-auto launch` | 감시 백그라운드 시작 |
| `cartier-auto status` / `logs` | 감시 상태·로그 |
| `cartier-auto stop` | 감시 중지 (사용자 명시 요청) |

## 상태 머신

`SCHEDULED → PREWARM(오픈 5분 전) → WATCHING → PURCHASE_STARTED → (USER_ACTION_CAPTCHA → USER_ACTION_PAYMENT_PIN) → COMPLETED`

종료: `COMPLETED` / `PRICE_BLOCKED` / `FAILED` / `STOPPED`
