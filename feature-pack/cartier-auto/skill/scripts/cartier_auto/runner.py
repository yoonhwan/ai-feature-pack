#!/usr/bin/env python3
"""실제 구매 감시·결제 실행 모듈.

라이프사이클:
  SCHEDULED → (5분 전) PREWARM → (예약 시각) WATCHING → PURCHASE_STARTED
  → USER_ACTION_CAPTCHA → USER_ACTION_PAYMENT_PIN → COMPLETED
  예외 종료: PRICE_BLOCKED / FAILED / STOPPED (사용자 명시 요청 시)
"""

from __future__ import annotations

import time
from datetime import timedelta

from ._common import load_job, log, now_kst, save_job
from .monitor import (
    COMPLETED, FAILED, PREWARM, PRICE_BLOCKED, PURCHASE_STARTED, SCHEDULED, STOPPED,
    USER_ACTION_CAPTCHA, USER_ACTION_PAYMENT_PIN, WATCHING,
    compute_current_interval, parse_kst,
)

def load_job_for_run(job_id: str) -> dict:
    job = load_job(job_id)
    if not job:
        raise RuntimeError(f"작업을 찾을 수 없습니다: {job_id}")
    return job


def validate_job_ready(job: dict) -> None:
    if job.get("spec") is None:
        raise RuntimeError("작업 spec이 없습니다")
    if not job.get("approved"):
        raise RuntimeError("사용자 승인이 없습니다")
    if job.get("status") not in (SCHEDULED, PREWARM):
        raise RuntimeError(f"작업 상태가 실행 가능하지 않습니다: {job.get('status')}")


def prewarm_if_due(job: dict, lead_sec: int = 300) -> str:
    """예약 시각 -5분 시점에 PREWARM으로 전환."""
    if job.get("status") == SCHEDULED:
        run_at = parse_kst(job["spec"]["run_at"])
        if now_kst() >= run_at - timedelta(seconds=lead_sec):
            job["status"] = PREWARM
            save_job(job)
            log(f"[{job.get('id')}] PREWARM 진입")
    return job.get("status")


def is_rate_limited_text(text: str) -> bool:
    lower = (text or "").lower()
    return "429" in lower or "rate limit" in lower or "too many requests" in lower


class WatchRunner:
    """간격 계산과 백오프를 순수 함수로 캡슐화 (테스트 가능)."""

    def __init__(self, interval: float = 0.5):
        self.interval = interval
        self.failure_attempt = 0

    def next_sleep(self) -> float:
        self.failure_attempt = 0
        return self.interval

    def on_error(self, error) -> float:
        self.failure_attempt += 1
        return compute_current_interval(self.failure_attempt, self.interval)

    def on_success(self) -> None:
        self.failure_attempt = 0


def guard_completed(job: dict, order_id: str | None = None) -> dict:
    """order-confirmation 확인 시 COMPLETED로 종료, 재시도·중복 결제 금지."""
    if order_id:
        if job.get("order_id") and job["order_id"] != order_id:
            log(f"[{job.get('id')}] 주문번호 불일치 — 중복 결제 위험, 중단")
            job["status"] = FAILED
        else:
            job["order_id"] = order_id
    job["status"] = COMPLETED
    job["confirmed_at"] = now_kst().isoformat(timespec="milliseconds")
    save_job(job)
    return job
