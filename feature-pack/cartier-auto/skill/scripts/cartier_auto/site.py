#!/usr/bin/env python3
"""까르띠에 사이트 상호작용: 로그인, 위시리스트, 가격, 장바구니, 결제 플로우.

실제 결제는 실행기(runner)가 Playwright로 수행한다. 이 모듈은 조회·파싱·검증을 담당한다.
"""

from __future__ import annotations

import re
import time

from ._common import with_retry
from .config import load_site_config


class SiteClient:
    def __init__(self, page=None, config: dict | None = None):
        self.page = page
        self.config = config or load_site_config()
        self._price_cache: dict[str, int] = {}

    def set_page(self, page) -> None:
        self.page = page

    @property
    def base_url(self) -> str:
        return self.config["base_url"]

    @property
    def wishlist_path(self) -> str:
        return self.config["wishlist_path"]

    # ---- 위시리스트 ----

    @staticmethod
    def _price_int(text: str) -> int | None:
        cleaned = re.sub(r"[^0-9]", "", text)
        return int(cleaned) if cleaned else None


    def parse_wishlist(self, content: str) -> list[dict]:
        """텍스트 폴백 파서 — data-pid 목록을 순서대로 추출 (실제 DOM은 fetch_wishlist 사용)."""
        out: list[dict] = []
        seen: set[str] = set()
        for m in re.finditer(r'data-pid=["\']([^"\']+)["\']', content):
            pid = m.group(1)
            if pid in seen:
                continue
            seen.add(pid)
            out.append({"pid": pid, "name": pid, "price_krw": None})
        return out


    def fetch_wishlist(self, require_login: bool = False, captcha_wait_sec: int = 300) -> list[dict]:
        """Playwright DOM에서 위시리스트 상품을 직접 순회해 [{pid, name, price_krw}] 반환.

        상품 데이터 로드 중 사이트 reCAPTCHCA(봇 보호)가 감지되면,
        사용자가 브라우저 창에서 직접 인증을 완료할 때까지 최대 captcha_wait_sec초
        폴링하며 대기한다. 완료 후 데이터 로드를 재시도해 상품을 추출한다.
        """
        if self.page is None:
            raise RuntimeError("Playwright 페이지가 연결되지 않았습니다")
        def _load():
            self.page.goto(self.base_url + self.wishlist_path, wait_until="domcontentloaded", timeout=20000)
            # 로그인 폼으로 리다이렉트되면 로그인 후 다시 위시리스트로
            if self.is_logged_in(self.page) is False or not self._url_ok(self.page):
                from ._common import load_creds
                creds = load_creds()
                if creds.get("CARTIER_ID") and creds.get("CARTIER_PASSWORD"):
                    self.login(self.page, creds)
                    self.page.goto(self.base_url + self.wishlist_path, wait_until="domcontentloaded", timeout=20000)
            return self.page
        with_retry(_load, "위시리스트 조회")
        items: list[dict] = []
        deadline = time.monotonic() + 30
        captcha_notified = False
        while time.monotonic() < deadline:
            # 재캡처가 감지되거나 상품이 로드되면 루프에서 처리
            if self._recaptcha_present():
                if not captcha_notified:
                    print(f"[위시리스트] 재캡처(봇 보호) 감지 — 브라우저 창에서 직접 인증해 주세요. 최대 {captcha_wait_sec}초 대기", flush=True)
                    captcha_notified = True
                deadline = time.monotonic() + captcha_wait_sec
            items = self._extract_wishlist_items()
            if items:
                return items
            # 재캡처가 감지된 동안에는 빈 목록으로 간주하지 않고 대기를 계속한다
            recaptcha_on = self._recaptcha_present()
            if not recaptcha_on:
                # 빈 위시리스트 문구가 명시적으로 뜨면 빈 목록 반환
                body_text = self.page.locator("body").inner_text()
                if "위시리스트가 비어 있습니다" in body_text or "wishlist is empty" in body_text.lower():
                    return []
            self.page.wait_for_timeout(2500 if not recaptcha_on else 1500)
        # 시간 초과 시 상태를 명확히 구분해 보고
        content = self.page.content()
        if self._recaptcha_present() or "recaptcha" in content.lower() or "g-recaptcha" in content.lower():
            raise RuntimeError(
                "위시리스트 상품 로드가 reCAPTCHA(봇 보호)에 의해 지속 차단됩니다. "
                "브라우저 창에서 직접 인증을 완료한 뒤 다시 실행해 주세요."
            )
        return []

    @staticmethod
    def _url_ok(page) -> bool:
        """현재 URL이 위시리스트(상품 조회 가능)인지."""
        u = (page.url or "").lower()
        return "login" not in u and "login_challenge" not in u and "account" not in u

    def _recaptcha_present(self) -> bool:
        """페이지 안에 보이는 reCAPTCHA 위젯/프레임이 있는지."""
        try:
            if self.page is None:
                return False
            # reCAPTCHA iframe (사용자에게 보이는 체크박스/챌린지)
            frames = self.page.frames
            for f in frames:
                u = (f.url or "").lower()
                if "recaptcha" in u or "google.com/recaptcha" in u:
                    return True
            # g-recaptcha 위젯 요소
            if self.page.locator('.g-recaptcha, iframe[src*="recaptcha"]').count():
                return True
        except Exception:
            return False
        return False

    def _extract_wishlist_items(self) -> list[dict]:
        """현재 DOM에서 data-pid 상품 카드를 추출한다.

        실제 마크업은 div.wishlist__product-line-item[data-pid] 형태이며
        카드 텍스트에 상품명·가격(₩)이 함께 포함되어 있다.
        """
        items: list[dict] = []
        seen: set[str] = set()
        cards = self.page.locator('[data-pid]')
        count = cards.count()
        for i in range(count):
            card = cards.nth(i)
            pid = card.get_attribute("data-pid") or ""
            if not pid or pid in seen:
                continue
            seen.add(pid)
            name = ""
            price = None
            try:
                card_text = card.inner_text(timeout=3000)
            except Exception:
                card_text = ""
            lines = [ln.strip() for ln in card_text.splitlines() if ln.strip()]
            # 이름: 첫 줄 (쇼핑백/크기/가격 단서가 아닌 줄)
            for ln in lines:
                if ln and not any(tok in ln for tok in ("쇼핑백", "크기", "₩", "KRW", "원", "위시리스트", "아이템")):
                    name = ln
                    break
            # 가격: ₩ / KRW / 원 표기 숫자
            m = re.search(r"₩\s*([0-9][0-9,]*)", card_text)
            if not m:
                m = re.search(r"([0-9][0-9,]*)\s*(?:원|KRW)", card_text)
            if m:
                price = self._price_int(m.group(1))
            items.append({"pid": pid, "name": name or pid, "price_krw": price})
        return items
        # 2) 명시적으로 빈 위시리스트
        if ("위시리스트가 비어 있습니다" in body_text or "wishlist is empty" in body_text.lower()):
            return []
        # 3) reCAPTCHA/보호로 로드 차단？
        if "recaptcha" in content.lower() or "g-recaptcha" in content.lower():
            raise RuntimeError(
                "위시리스트 상품이 로드되지 않았습니다 — 사이트 reCAPTCHA(봇 보호)가 데이터 로드를 차단 중입니다. "
                "브라우저를 직접 열어 재캡처를 통과시킨 뒤 재시도하세요."
            )
        # 4) 그 외: 빈 결과로 간주 (재로드 1회 더)
        if "아이템" not in body_text:
            return []
        return []

    def wishlist_items_text(self, items: list[dict]) -> list[str]:
        out = []
        for idx, item in enumerate(items, 1):
            price = f"{item.get('price_krw'):,}원" if item.get("price_krw") else "가격 미확인"
            out.append(f"{idx}. {item.get('name') or item.get('pid')} (PID {item.get('pid')}) — {price}")
        return out

    # ---- 가격 / 구매 가능 / 로그인 ----

    def current_price(self, page=None, pid: str | None = None) -> int | None:
        return self._price_cache.get(pid) if pid else None

    def can_buy(self, page=None, pid: str | None = None) -> bool:
        # 구매 가능 여부는 실행기의 실제 위시리스트 DOM 검사로 판단한다.
        return False

    @staticmethod
    def is_logged_in(page) -> bool:
        """URL·로그인 폼·계정 링크를 종합해 실제 로그인 여부를 판정한다."""
        url = (page.url or "").lower()
        # 명시적 로그인 URL이면 미로그인
        if any(tok in url for tok in ("/login", "login_challenge", "connection", "logon", "signin",
                                      "oauth2/auth", "oauth")):
            return False
        # 로그인 폼 단서 (이메일+비밀번호 입력이 함께 보이면 미로그인)
        try:
            body = page.locator("body").inner_text().lower()
        except Exception:
            body = ""
        if "비밀번호" in body and ("이메일" in body or "아이디" in body or "로그인" in body):
            # 로그인 폼 직접 노출 여부: type=password input 존재
            try:
                if page.locator("input[type='password']").count():
                    return False
            except Exception:
                pass
        # 헤더 '나의 까르띠에' 링크의 href로 판정 (가장 신뢰)
        try:
            my = page.locator("header a, nav a").filter(has_text="나의 까르띠에").first
            if my.count():
                href = (my.get_attribute("href") or "").lower()
                if "oauth2" in href or "login" in href or "auth" in href:
                    return False
                if "account" in href or "my-account" in href or "wishlist" in href:
                    return True
        except Exception:
            pass
        # 폴백: 본문에 로그인 폼 단서가 없고 계정 영역이 있으면 로그인
        if any(tok in body for tok in ("비밀번호 입력", "로그인 정보", "이메일 주소")):
            return False
        return "나의 까르띠에" in body

    def login(self, page, creds: dict) -> bool:
        cfg = self.config
        email = creds.get("CARTIER_ID", "")
        password = creds.get("CARTIER_PASSWORD", "")
        if not email or not password:
            raise RuntimeError("CARTIER_ID 또는 CARTIER_PASSWORD가 없습니다")
        page.goto(self.base_url + "/ko-kr/login", wait_until="domcontentloaded")
        self.dismiss_banners(page)
        page.locator(cfg["selectors"]["login_email_selector"]).first.fill(email, timeout=5000)
        page.locator(cfg["selectors"]["login_password_selector"]).first.fill(password, timeout=5000)
        # 제출 버튼: type=submit 우선, 없으면 '로그인' 텍스트 버튼
        submit = page.locator("#login-form button[type='submit'], form:has(input[id='login-form-email']) button[type='submit']").first
        if not submit.count():
            submit = page.locator("button").filter(has_text=cfg["selectors"]["login_submit_text"]).first
        submit.click(timeout=10000)
        # 로그인 완료/실패 대기 (재캡처 챌린지가 뜨면 여기서 기다림)
        try:
            page.wait_for_url("**/my-account**", timeout=25000)
        except Exception:
            pass
        page.wait_for_load_state("domcontentloaded", timeout=10000)
        return self.is_logged_in(page)

    @staticmethod
    def field_by_label(page, label: str):
        return page.locator(f'label:text-is("{label}")').locator("xpath=following-sibling::*[self::input or self::select]").first

    @staticmethod
    def visible_text_button(page, text: str):
        return page.locator("button").filter(has_text=text).first

    @staticmethod
    def dismiss_banners(page) -> None:
        try:
            button = page.locator("button").filter(has_text="모두 허용").first
            button.click(timeout=2500)
            page.wait_for_timeout(800)
        except Exception:
            pass
