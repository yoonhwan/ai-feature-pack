#!/usr/bin/env python3
"""까르띠에 사이트 설정 (하드코딩 상품·테스트 상품·1Password 없음)."""

from __future__ import annotations

import json
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = Path(__file__).resolve().parent.parent / "config" / "cartier-site.json"


def default_config() -> dict:
    return {
        "base_url": "https://www.cartier.com",
        "locale": "ko-kr",
        "wishlist_path": "/ko-kr/wishlist",
        "cart_path": "/ko-kr/cart",
        "checkout_path": "/ko-kr/checkout",
        "selectors": {
            "cookie_allow_text": "모두 허용",
            "add_to_wishlist_text": "위시리스트에 추가",
            "add_to_cart_text": "쇼핑백에 추가하기",
            "login_email_selector": "#login-form-email",
            "login_password_selector": "#login-form-password, input[name='loginPassword']",
            "login_submit_text": "로그인",
            "guest_checkout_text": "비회원 결제 진행",
            "naver_pay": "NAVER PAY",
            "order_confirm_text": "주문하기",
        },
        "watch": {
            "lead_time_sec": 300,
            "normal_poll_sec": 5.0,
            "user_wait_sec": 300,
            "watch_seconds": 604800,
        },
        "headless": False,
    }


def load_site_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return default_config()


def write_default_config() -> Path:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        CONFIG_FILE.write_text(json.dumps(default_config(), ensure_ascii=False, indent=2), encoding="utf-8")
    return CONFIG_FILE
