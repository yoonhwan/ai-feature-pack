---
name: cartier-auto
description: 까르띠에 공식 몰 리스톡 자동 구매 - 위시리스트 감시, 예약 구매, 네이버페이 결제 자동화. CAPTCHA·보안 키패드는 사용자가 직접.
---

# /cartier-auto — 까르띄에 리스톡 자동 구매

까르띄에 위시리스트 상품이 재입고되면 예약 시각부터 지정 주기로 감시하고 쇼핑백 추가 → 구매 → 네이버페이 결제를 진행한다.

## 실행 순서

1. **Readiness**: `cartier-auto doctor --json`
   - 준비 안 됐으면: `bash ~/.codex/skills/cartier-auto/scripts/setup-credentials.sh` 안내 후 완료 보고를 기다린다.
2. **위시리스트 조회**: `cartier-auto wishlist --json` — 상품명·PID·가격 JSON 반환
3. **상품 선택**: 번호로 정확히 1종
4. **예약 정보 수집** (대화):
   - 구매 예정 일시 (`YYYY-MM-DD HH:MM:SS`, KST, 과거 거부)
   - 새로고침 주기 (0.4~30초, 기본 0.5)
5. **최종 요약 + 승인** — 사용자가 명시 승인해야만 아래 실행
   ```bash
   cartier-auto schedule --pid PID --name '상품명' --price 146000 \
     --at '2026-08-25 20:00:00' --interval 0.5 --approved-price 146000 --confirm
   ```
6. **감시 시작**: `cartier-auto launch --job JOBID`
   - 상태: `cartier-auto status --job JOBID --json` / 로그: `cartier-auto logs --job JOBID`
   - 중지: `cartier-auto stop --job JOBID`

## 제약
- 실제 결제 전 사용자 개입은 **네이버 CAPTCHA**와 **네이버페이 보안 키패드** 두 번뿐
- 결제 테스트는 반복하지 않는다. 조회·예약·상태 전이까지 검증
- 주문확정(`order-confirmation`+주문번호) 전까지 재시도·중복 결제 금지
- 승인 가격보다 현재 가격이 높으면 `PRICE_BLOCKED`로 종료
