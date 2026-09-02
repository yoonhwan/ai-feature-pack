#!/usr/bin/env python3
"""Playwright 기반 실제 구매 감시·결제 플로우.

결제 단계 사용자 개입은 두 번뿐:
  1) 네이버 CAPTCHA (사용자가 직접 입력, purchaser가 ID/PW 재입력)
  2) 네이버페이 보안 키패드 비밀번호 (저장 카드 자동 선택, 키패드는 사용자 입력)

보안 키패드 숫자 판독·좌표 클릭은 구현하지 않는다.
"""

from __future__ import annotations

import re
import time

from ._common import log
from .monitor import (
    FAILED, PRICE_BLOCKED, PURCHASE_STARTED, USER_ACTION_CAPTCHA,
    USER_ACTION_PAYMENT_PIN, WATCHING, compute_current_interval,
)
from .site import SiteClient

NAVER_CAPTCHA_WAIT_SEC = 300
NAVER_PIN_WAIT_SEC = 300


def consecutive_interval(failure_attempt: int, base: float) -> float:
    return compute_current_interval(failure_attempt, base)


class BrowserFlow:
    def __init__(self, config: dict, creds: dict, job: dict):
        self.config = config
        self.creds = creds
        self.job = job
        self.spec = job["spec"]
        self.job_id = job.get("id")
        self.state_path = job.get("state_path")
        self.client = SiteClient(config=config)

    # ---- 예열 ----

    def warm(self, context) -> None:
        prewarm_page = context.new_page()
        prewarm_page.goto(self.config["base_url"] + "/ko-kr/home", wait_until="domcontentloaded")
        SiteClient.dismiss_banners(prewarm_page)
        if not self.client.is_logged_in(prewarm_page):
            if not self.client.login(prewarm_page, self.creds):
                raise RuntimeError("까르띠에 로그인 실패")
            context.storage_state(path=self.state_path)
        if self._cart_nonempty(context):
            raise RuntimeError("장바구니가 비어 있지 않습니다 — 중복 구매 방지를 위해 중단")
        prewarm_page.close()

    def _cart_nonempty(self, context) -> bool:
        page = context.new_page()
        try:
            page.goto(self.config["base_url"] + self.config["cart_path"], wait_until="domcontentloaded", timeout=20000)
            qty = page.locator('[data-minicart-component="qty"]').first
            if qty.count():
                text = qty.inner_text().strip()
                if text.isdigit() and int(text) > 0:
                    return True
            return page.locator(".cart__line-item").count() > 0
        finally:
            page.close()

    # ---- 감시 루프 ----

    def watch(self, context):
        page = context.new_page()
        pid = self.spec["pid"]
        interval = float(self.spec.get("interval", 0.5))
        approved = self.spec.get("approved_price")
        watch_deadline = time.time() + int(self.config["watch"].get("watch_seconds", 604800))
        failure_attempt = 0
        self.transition(WATCHING)
        while time.time() < watch_deadline:
            try:
                self._read_wishlist(page, pid)
                price = self._read_price(page, pid)
                if approved is not None and price is not None and price > approved:
                    self.transition(PRICE_BLOCKED, f"현재 가격 {price}원 > 승인 가격 {approved}원")
                    return None
                if not self._can_buy(page, pid):
                    failure_attempt = 0
                    self._sleep(interval)
                    continue
                self.transition(PURCHASE_STARTED)
                return self._purchase_ready(page)
            except Exception as exc:
                failure_attempt += 1
                wait = consecutive_interval(failure_attempt, interval)
                log(f"[{self.job_id}] 감시 오류 연속 {failure_attempt}회: {exc} → {wait:.1f}초 대기")
                if failure_attempt >= 10:
                    self.transition(FAILED, f"감시 오류 한도 초과: {exc}")
                    return None
                self._sleep(wait)
        self.transition(FAILED, "감시 시간 초과")
        return None

    def _read_wishlist(self, page, pid: str) -> None:
        page.goto(self.config["base_url"] + self.config["wishlist_path"], wait_until="domcontentloaded", timeout=15000)
        SiteClient.dismiss_banners(page)

    def _read_price(self, page, pid: str) -> int | None:
        try:
            bag = page.locator(f'button[data-pid="{pid}"]').first
            if bag.count() == 0:
                return None
            container = bag.locator("xpath=ancestor::*[contains(@class,'product') or contains(@class,'tile') or contains(@class,'wishlist')][1]")
            if container.count():
                text = container.inner_text(timeout=3000)
                import re
                m = re.search(r"([0-9][0-9,.]*)\\s*(?:원|KRW|₩)", text)
                if m:
                    return int(re.sub(r"[^0-9]", "", m.group(1)))
            return None
        except Exception:
            return None

    def _can_buy(self, page, pid: str) -> bool:
        bag = page.locator(f'button[data-pid="{pid}"]').first
        return bag.count() > 0 and bag.is_enabled()

    def _sleep(self, sec: float) -> None:
        if sec > 0:
            time.sleep(sec)

    def transition(self, status: str, note: str = "") -> None:
        from .monitor import TransitionRecorder
        TransitionRecorder(self.job_id).transition(status, note)

    # ---- 결제 플로우 ----

    def _purchase_ready(self, page):
        """선택한 data-pid 버튼만 추적해 활성화 즉시 쇼핑백 추가 → 구매하기 → 결제."""
        pid = self.spec["pid"]
        bag_button = page.locator(f'button[data-pid="{pid}"]').first
        bag_button.click(timeout=5000)
        page.wait_for_timeout(1200)
        # 미니카트에서 결제 진행
        self._open_minicart(page)
        checkout = page.locator('[data-cart-component="checkout-action"], .minicart__checkout-action').first
        if checkout.count() and checkout.is_visible():
            checkout.click(timeout=10000)
            try:
                page.wait_for_url("**/cart**", timeout=20000)
            except Exception:
                pass
        else:
            page.goto(self.config["base_url"] + self.config["cart_path"], wait_until="domcontentloaded")
        return self._checkout(context=page.context, page=page)

    def _checkout(self, context, page) -> str | None:
        # 구매하기 → 배송정보 → 필수동의 → NAVER PAY → 주문하기
        buy_button = page.locator("a, button").filter(
            has_text="구매하기").first
        buy_button.click(timeout=15000)
        page.wait_for_url("**/checkout**", timeout=20000)
        guest_email = self.creds.get("CARTIER_ID")
        if guest_email and page.locator("input[type=email]").count():
            page.locator("input[type=email]").first.fill(guest_email)
            self.client.visible_text_button(page, self.config["selectors"]["guest_checkout_text"]).click()
            page.wait_for_timeout(2000)

        # 배송단계 진입 시 주소 채움
        if "shipping" in page.url:
            self._fill_address(page)
            submit = page.locator("button.submit-shipping").first
            if submit.count():
                submit.click(timeout=15000)
                try:
                    page.wait_for_url("**stage=payment**", timeout=20000)
                except Exception:
                    pass
        # 필수 동의 + NAVER PAY 선택
        self._select_naver_pay(page)
        return self._launch_and_complete_naver(context, page)

    def _fill_address(self, page) -> None:
        # 프로필에 주소가 없으면 스킬 실행기가 요청하므로, 있으면 채운다.
        profile = self.job.get("profile", {})
        mapping = {
            "family_name_ko": ["성(국문)", "last name"],
            "given_name_ko": ["이름(국문)", "first name"],
            "phone": ["핸드폰 번호"],
            "postal_code": ["우편번호"],
            "city": ["도시"],
            "district": ["시/구/군"],
            "street": ["도로명주소"],
            "detail": ["상세 주소"],
        }
        filled = 0
        for key, labels in mapping.items():
            value = profile.get(key)
            if not value:
                continue
            for label in labels:
                locator = self.client.field_by_label(page, label)
                if locator.count():
                    locator.fill(value, timeout=5000)
                    filled += 1
                    break
        if filled == 0:
            raise RuntimeError("배송정보 필드가 비어 있습니다 — 주소를 설정해 주세요")

    def _select_naver_pay(self, page) -> None:
        required_consents = [
            "주문자 본인의 핸드폰 번호와 동일합니다",
            "까르띠에의 판매약관 및 개인정보 보호정책을 읽었으며 이에 동의함",
        ]
        for consent_text in required_consents:
            checkbox = page.get_by_text(consent_text, exact=False).first.locator(
                "xpath=ancestor-or-self::label[1]//input[@type='checkbox'] | "
                "ancestor::*[self::label or self::div][1]//input[@type='checkbox']"
            ).first
            if not checkbox.count():
                checkbox = page.get_by_role("checkbox", name=consent_text, exact=False).first
            if not checkbox.count():
                raise RuntimeError(f"필수 결제 동의 체크박스를 찾지 못했습니다: {consent_text}")
            if not checkbox.is_checked():
                label = page.locator("label").filter(has_text=consent_text).first
                if not label.count():
                    raise RuntimeError(f"필수 결제 동의 라벨을 찾지 못했습니다: {consent_text}")
                label.click(timeout=5000)
                if not checkbox.is_checked():
                    raise RuntimeError(f"필수 결제 동의 체크에 실패했습니다: {consent_text}")
        naver = page.get_by_text("NAVER PAY", exact=True).first
        if not naver.count():
            naver = page.locator("text=NAVER PAY").filter(has_not_text="POINT").first
        if not naver.count():
            raise RuntimeError("결제수단을 찾지 못했습니다: NAVER PAY")
        control = naver.locator(
            "xpath=ancestor::*[self::label or self::button or @role='radio' or "
            "contains(@class,'payment-method') or contains(@class,'payment-option')][1]"
        ).first
        if not control.count():
            control = naver.locator("xpath=ancestor::div[1]")
        control.click(timeout=5000)
        log(f"[{self.job_id}] NAVER PAY 결제수단 선택 완료")

    def _launch_and_complete_naver(self, context, page) -> str | None:
        """주문하기 클릭 → 네이버페이 팝업 → CAPTCHA/PIN 대기 → order-confirmation."""
        order_button = page.locator("button:visible, a:visible").filter(has_text="주문하기").last
        order_button.wait_for(state="visible", timeout=20000)
        existing_pages = set(context.pages)
        with context.expect_page(timeout=15000) as popup_info:
            order_button.click(timeout=15000)
        payment_page = popup_info.value
        payment_page.wait_for_load_state("domcontentloaded", timeout=15000)
        return self._complete_naver(context, payment_page, checkout_page=page)

    def _complete_naver(self, context, payment_page, checkout_page):
        username = self.creds.get("NAVER_ID", "")
        password = self.creds.get("NAVER_PASSWORD", "")
        if not username or not password:
            raise RuntimeError("NAVER_ID 또는 NAVER_PASSWORD가 없습니다")
        if "nid.naver.com" in payment_page.url:
            payment_page.wait_for_load_state("domcontentloaded", timeout=20000)
            payment_page.locator("#id, input[name='id']").first.wait_for(state="visible", timeout=20000)
            payment_page.locator("#id, input[name='id']").first.fill(username)
            payment_page.locator("#pw, input[name='pw']").first.fill(password)
            login_button = payment_page.locator(
                "button[type='submit']:visible, button.btn_login:visible, "
                "input[type='submit']:visible, a.btn_login:visible, #log\\.login"
            ).first
            if not login_button.count():
                login_button = payment_page.get_by_text("로그인", exact=True).last
            login_button.click(timeout=10000)
            login_submitted_at = time.time()
            login_deadline = time.time() + NAVER_CAPTCHA_WAIT_SEC
            captcha_seen = False
            credentials_reentered = False
            while time.time() < login_deadline:
                current_url = payment_page.url
                if "pay.naver.com/" in current_url:
                    break
                if "nidlogin.rcaptcha" in current_url:
                    if not captcha_seen:
                        captcha_seen = True
                        self.transition(USER_ACTION_CAPTCHA,
                                        "사용자 개입 1/2: 네이버 CAPTCHA를 직접 입력하고 확인해 주세요. 최대 5분 대기")
                    payment_page.wait_for_timeout(500)
                    continue
                if not credentials_reentered and "nidlogin.login" in current_url and time.time() - login_submitted_at >= 2:
                    pw_input = payment_page.locator("#pw, input[name='pw']").first
                    pw_empty = pw_input.count() and pw_input.is_visible() and not pw_input.input_value()
                    if pw_empty:
                        payment_page.locator("#id, input[name='id']").first.fill(username)
                        pw_input.fill(password)
                        retry = payment_page.locator(
                            "button[type='submit']:visible, button.btn_login:visible, "
                            "input[type='submit']:visible, a.btn_login:visible, #log\\.login"
                        ).first
                        if not retry.count():
                            retry = payment_page.get_by_text("로그인", exact=True).last
                        retry.click(timeout=10000)
                        credentials_reentered = True
                        log(f"[{self.job_id}] 네이버 로그인 화면 복귀 — 정보 재입력 완료")
                payment_page.wait_for_timeout(500)
            else:
                error_text = payment_page.locator("body").inner_text(timeout=10000)
                visible = " ".join(line.strip() for line in error_text.splitlines() if line.strip())[:500]
                raise RuntimeError(f"네이버 로그인 실패: {visible}")
        pay_button = payment_page.get_by_role("button", name="결제하기", exact=False).last
        if not pay_button.count():
            pay_button = payment_page.locator("button:visible, a:visible").filter(has_text="결제").last
        pay_button.wait_for(state="visible", timeout=20000)
        body = payment_page.locator("body").inner_text(timeout=10000)
        if any(token in body for token in ["보안문자", "추가 인증", "2단계 인증"]):
            self.transition(USER_ACTION_CAPTCHA, "네이버 추가 인증(보안문자)을 직접 처리해 주세요")
        card_option = payment_page.locator("input[type='radio']:visible").first
        if card_option.count() and not card_option.is_checked():
            card_option.check(force=True)
        self.transition(USER_ACTION_PAYMENT_PIN, "저장 카드 선택 완료 — 네이버페이 보안 키패드 비밀번호를 직접 입력해 주세요")
        pay_button.click(timeout=15000)
        payment_page.get_by_text("비밀번호", exact=False).first.wait_for(state="visible", timeout=15000)
        pin_deadline = time.time() + NAVER_PIN_WAIT_SEC
        while time.time() < pin_deadline:
            try:
                checkout_page.wait_for_url("**order-confirmation**", timeout=5000)
                break
            except Exception:
                payment_page.wait_for_timeout(1000)
        else:
            raise RuntimeError(f"네이버페이 결제 완료를 확인하지 못했습니다: {checkout_page.url}")
        order_id = ""
        try:
            body_text = checkout_page.locator("body").inner_text(timeout=10000)
            import re as _re
            m = _re.search(r"(?:주문번호|order\\s*number)[^0-9]{0,12}([A-Z0-9-]{6,40})", body_text, _re.I)
            if m:
                order_id = m.group(1)
        except Exception:
            pass
        return order_id

    def _open_minicart(self, page) -> None:
        overlay = page.locator('[data-minicart-component="overlay"]').first
        if overlay.count() and overlay.is_visible():
            return
        trigger = page.locator('[data-minicart-component="trigger"]').first
        if trigger.count():
            trigger.click(timeout=5000)
            page.wait_for_timeout(1200)
