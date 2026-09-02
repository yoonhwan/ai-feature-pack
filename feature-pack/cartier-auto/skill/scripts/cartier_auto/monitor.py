#!/usr/bin/env python3
"""감시·결제 상태 머신과 순수 로직 (브라우저 의존 없음, 테스트 가능)."""

from __future__ import annotations

import random
import time
from datetime import datetime

from ._common import KST, load_job, log, now_kst, save_job, ts

# 상태
SCHEDULED = "SCHEDULED"
PREWARM = "PREWARM"
WATCHING = "WATCHING"
PURCHASE_STARTED = "PURCHASE_STARTED"
USER_ACTION_CAPTCHA = "USER_ACTION_CAPTCHA"
USER_ACTION_PAYMENT_PIN = "USER_ACTION_PAYMENT_PIN"
COMPLETED = "COMPLETED"
PRICE_BLOCKED = "PRICE_BLOCKED"
FAILED = "FAILED"
STOPPED = "STOPPED"

TERMINAL = {COMPLETED, PRICE_BLOCKED, FAILED, STOPPED}
USER_INTERVENTION = {USER_ACTION_CAPTCHA, USER_ACTION_PAYMENT_PIN}

MIN_INTERVAL = 0.4
MAX_INTERVAL = 30.0
DEFAULT_INTERVAL = 0.5

BACKOFF_BASE = 1.0
BACKOFF_CAP = 30.0


def now() -> str:
    return now_kst().isoformat(timespec="milliseconds")


def parse_kst(text: str) -> datetime:
    return datetime.fromisoformat(text).astimezone(KST)


def validate_interval(value: float) -> float:
    value = float(value)
    if not (MIN_INTERVAL <= value <= MAX_INTERVAL):
        raise ValueError(f"새로고침 주기는 {MIN_INTERVAL}~{MAX_INTERVAL}초여야 합니다 (입력: {value})")
    return round(value, 3)


def validate_run_at(text: str) -> datetime:
    dt = parse_kst(text)
    if dt <= now_kst():
        raise ValueError(f"예약 시각은 현재보다 미래여야 합니다 (입력: {text})")
    return dt


def approve_job(spec: dict, interval: float) -> dict:
    """승인 전 검증: 과거 시각 거부, 주기 경계."""
    validate_run_at(spec["run_at"])
    spec = dict(spec)
    spec["interval"] = validate_interval(interval)
    spec["status"] = SCHEDULED
    return spec


def is_rate_limited(error) -> bool:
    text = str(error).lower()
    return "429" in text or "rate limit" in text or "too many requests" in text


def backoff_delay(attempt: int) -> float:
    delay = min(BACKOFF_BASE * (2 ** min(attempt - 1, 6)), BACKOFF_CAP)
    return round(delay + random.uniform(0, 0.25), 3)


def should_price_block(current_price: int | None, approved_price: int) -> bool:
    return current_price is not None and current_price > approved_price


def compute_current_interval(failure_attempt: int, base_interval: float) -> float:
    if failure_attempt == 0:
        return base_interval
    return backoff_delay(failure_attempt)


class TransitionRecorder:
    """상태 전이 + 시간 기록. 사용자 개입 두 상태는 USER_INTERVENTION 값만 사용."""

    def __init__(self, job_id: str):
        self.job_id = job_id

    def transition(self, status: str, note: str = "") -> None:
        job = load_job(self.job_id) or {}
        trans = job.get("transitions", [])
        trans.append({"status": status, "at": now(), "note": note})
        job["status"] = status
        job["transitions"] = trans[-50:]
        save_job(job)
        log(f"[{self.job_id}] {status} {note}".strip(), job_id=self.job_id)


class PriceGuard:
    def check(self, job: dict, current_price: int | None) -> str | None:
        approved = job.get("spec", {}).get("approved_price") if job.get("spec") else job.get("approved_price")
        if approved is None:
            return None
        if current_price is not None and current_price > approved:
            return PRICE_BLOCKED
        return None


class PurchaseOnceGuard:
    def already(self, job: dict) -> bool:
        return job.get("status") == COMPLETED or bool(job.get("order_id") or job.get("confirmed_at"))

    def record_completed(self, job: dict, order_id: str | None = None) -> dict:
        job = dict(job)
        job["status"] = COMPLETED
        job["confirmed_at"] = now()
        if order_id:
            job["order_id"] = order_id
        save_job(job)
        return job


def parse_job_schedule(spec: dict) -> tuple[datetime, float]:
    return parse_kst(spec["run_at"]), float(spec.get("interval", DEFAULT_INTERVAL))
