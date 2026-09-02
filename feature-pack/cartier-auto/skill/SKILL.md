---
name: cartier-auto
description: 까르띠에 공식 몰 리스톡(wishlist) 자동 구매 감시 - 구매 예약 감시, 위시리스트 상품 추적, 네이버페이 결제 자동화. 사용자는 CAPTCHA와 네이버페이 보안 키패드 두 단계만 직접 처리한다.
version: 1.0.0
author: yoonhwan
license: MIT
metadata:
  hermes:
    tags: [cartier, wishlist, restock, automation, playwright, naver-pay, shopping]
    related_skills: []
---

# cartier-auto — 까르띄에 리스톡 자동 구매

까르띄에 공식 온라인 몰(`https://www.cartier.com/ko-kr`)의 위시리스트 상품이 재입고되면
예약 시각부터 지정한 주기로 감시하여 쇼핑백 추가 → 구매 → 네이버페이 결제까지 진행하는 자동화 스킬.

- 지원: macOS + Google Chrome + 한국 까르띄에 사이트 + Naver Pay (v1)
- 사용자 개입: **네이버 CAPTCHA** + **네이버페이 보안 키패드** 두 번뿐
- 보안 키패드 숫자 판독·좌표 클릭은 구현하지 않는다.

## 빠른 시작 (설치)

```bash
bash ~/.codex/skills/cartier-auto/scripts/install.sh
bash ~/.codex/skills/cartier-auto/scripts/setup-credentials.sh
```

설치기는 Python 3.11+ venv + Playwright(Chrome)를 준비한다.
자격증명 설정기는 `~/.config/cartier-auto/credentials.env`(0600)에 아토믹하게 저장한다.

`cartier-auto` 명령은 `~/.local/bin/cartier-auto` 심볼릭 링크로 설치된다.
`~/.local/bin`이 PATH에 없으면 아래 두 가지 중 하나를 사용한다:

```bash
# 방법 1: PATH에 추가 (zsh)
export PATH="$HOME/.local/bin:$PATH"

# 방법 2: 런처 직접 실행
bash ~/.codex/skills/cartier-auto/scripts/run.sh doctor --json
```

## 사용 흐름

1. **Readiness 확인**:
   ```bash
   cartier-auto doctor --json
   ```
   네 가지 자격증명·Chrome·Python·런타임이 모두 준비된 경우에만 READY.

2. **위시리스트 조회**:
   ```bash
   cartier-auto wishlist --json
   ```
   로그인 후 상품명·PID·가격·구매 가능 상태를 JSON으로 반환.

3. **상품·예약 정보 수집** (채팅):
   - 위시리스트에서 정확히 1종 선택 (번호)
   - 구매 예정 일시 (KST, 과거 거부)
   - 새로고침 주기 (0.4~30초, 기본 0.5초)

4. **최종 요약 및 승인**:
   - 선택 상품, PID, 현재 가격, 실행 시각, 주기, 실제 결제 가능성 요약
   - 사용자가 명시적으로 승인한 경우에만 아래로 예약 작업 생성
   - 승인 가격보다 현재 가격이 더 높으면 결제 시작 없이 `PRICE_BLOCKED`로 종료

   ```bash
   cartier_auto schedule --pid PID --at 'YYYY-MM-DD HH:MM:SS' --approved-price 146000 --interval 0.5 --confirm
   ```

5. **감시 시작**:
   ```bash
   cartier_auto launch --job <job-id>       # 백그라운드 실행
   cartier_auto status --job <job-id> --json
   cartier_auto logs --job <job-id>
   cartier_auto stop --job <job-id>          # 사용자 명시 요청 시에만
   ```

## 상태 머신

`SCHEDULED → PREWARM(오픈 5분 전) → WATCHING → PURCHASE_STARTED →`
`(USER_ACTION_CAPTCHA → USER_ACTION_PAYMENT_PIN) → COMPLETED`

종료 상태: `COMPLETED` (주문번호 확인), `PRICE_BLOCKED`, `FAILED`, `STOPPED` (사용자 명시 요청).

- 장바구니가 비어 있지 않으면 중복 구매 방지로 즉시 중단 (자동 삭제 없음)
- 429·일시 오류는 최대 30초 지수 백오프, 성공 시 원래 주기 복귀
- `order-confirmation` URL + 주문번호 확인 전까지 재시도 금지 (중복 결제 방지)

## 실행 환경

- 항상 설치 스킬의 venv(`bash scripts/run.sh ...`)로 실행한다.
- 백그라운드: `tmux` 있으면 `cartier-auto-<job-id>` 세션, 없으면 `nohup`+PID 파일
