#!/usr/bin/env python3
"""cartier-auto 단위 테스트 (pytest 없이 직접 실행 가능)."""

from __future__ import annotations

import json
import os
import os
import sys
import tempfile
import time
from pathlib import Path

# 테스트 중 홈 상태 경로 오염 방지
_TMP = tempfile.mkdtemp(prefix="cartier-auto-test-")
os.environ["CARTIER_AUTO_STATE"] = _TMP
os.environ["CARTIER_AUTO_CREDENTIALS"] = str(Path(_TMP) / "credentials.env")
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cartier_auto import _common
from cartier_auto import monitor
from cartier_auto.monitor import (
    MIN_INTERVAL, MAX_INTERVAL, DEFAULT_INTERVAL, PRICE_BLOCKED, COMPLETED, FAILED,
    USER_ACTION_CAPTCHA, USER_ACTION_PAYMENT_PIN, USER_INTERVENTION,
    approve_job, backoff_delay, compute_current_interval, is_rate_limited,
    parse_kst, should_price_block, validate_interval, validate_run_at,
)
from cartier_auto.credentials import save_credentials_env, quote
from cartier_auto.monitor import PriceGuard
from cartier_auto.runner import guard_completed, WatchRunner
from cartier_auto.site import SiteClient


class FakeJobStore:
    """테스트용 가짜 저장소: 파일 I/O 대신 메모리."""

    def __init__(self):
        self.jobs: dict[str, dict] = {}

    def load(self, job_id):
        return self.jobs.get(job_id)

    def save(self, job):
        self.jobs[job["id"]] = job


def make_job(pid="PID1", price=None, approved=100000, run_at=None, interval=0.5, status="SCHEDULED"):
    run_at = run_at or (datetime.now(_common.KST) + timedelta(hours=1)).isoformat()
    return {
        "id": "job_test",
        "spec": {
            "pid": pid,
            "name": "테스트 상품",
            "price_krw": price,
            "run_at": run_at,
            "interval": interval,
            "approved_price": approved,
        },
        "status": status,
        "approved": True,
        "transitions": [],
        "created_at": _common.ts(),
    }


def test_credentials_missing_and_partial():
    """네 자격증명 누락·부분 누락·준비 완료"""
    with tempfile.TemporaryDirectory() as td:
        env_path = Path(td) / "credentials.env"
        # 완전 준비
        save_credentials_env({"CARTIER_ID": "a", "CARTIER_PASSWORD": "b", "NAVER_ID": "c", "NAVER_PASSWORD": "d"}, target=env_path)
        assert parse_env_file(env_path)["CARTIER_ID"] == "a"
        # 부분 누락
        save_credentials_env({"CARTIER_ID": "a"}, target=env_path)
        parsed_partial = parse_env_file(env_path)
        assert "CARTIER_PASSWORD" not in parsed_partial
        assert "NAVER_ID" not in parsed_partial
        # 누락
        save_credentials_env({}, target=env_path)
        parsed_empty = parse_env_file(env_path)
        assert parsed_empty.get("CARTIER_ID") is None


def parse_env_file(path):
    return _common.parse_env_file(path)


def test_env_special_chars_and_perms():
    """env 파일 특수문자·권한"""
    with tempfile.TemporaryDirectory() as td:
        target = Path(td) / "credentials.env"
        values = {
            "CARTIER_ID": "user with space",
            "CARTIER_PASSWORD": "p@ss'word#1",
            "NAVER_ID": "naver#$@!",
            "NAVER_PASSWORD": "q'u'ote",
        }
        save_credentials_env(values, target=target)
        parsed = parse_env_file(target)
        for k, v in values.items():
            assert parsed.get(k) == v, f"{k}: {parsed.get(k)!r} != {v!r}"
        # 권한
        assert (target.stat().st_mode & 0o777) == 0o600


def test_validate_interval_bounds():
    """0.4/30초 경계"""
    assert validate_interval(0.4) == 0.4
    assert validate_interval(30.0) == 30.0
    assert validate_interval(0.5) == 0.5
    for bad in (0.39, 30.1, -1, 0):
        try:
            validate_interval(bad)
            raise AssertionError(f"{bad} 통과됨")
        except ValueError:
            pass


def test_validate_run_at_past():
    """과거 시각 거부"""
    past = (datetime.now(_common.KST) - timedelta(minutes=5)).isoformat()
    try:
        validate_run_at(past)
        raise AssertionError("과거 시각 통과됨")
    except ValueError:
        pass
    future = (datetime.now(_common.KST) + timedelta(minutes=5)).isoformat()
    assert validate_run_at(future)


def test_kst_conversion():
    """KST 변환"""
    dt = parse_kst("2026-08-24T20:00:00+09:00")
    assert dt.utcoffset().total_seconds() == 9 * 3600
    assert dt.tzinfo == _common.KST


def test_wishlist_pid_selection():
    """위시리스트 다중 상품에서 정확한 PID 선택"""
    content = """
    <button data-pid="CRB7215700" class="wishlist-item">다이아몬드</button>
    <button data-pid="CR66050019" class="wishlist-item">데클라라시옹</button>
    <button data-pid="CRB1234000" class="wishlist-item">러브</button>
    """
    from cartier_auto.site import SiteClient
    items = SiteClient(None).parse_wishlist(content)
    pids = [i["pid"] for i in items]
    assert pids == ["CRB7215700", "CR66050019", "CRB1234000"]


def test_price_block_guard():
    """승인 가격 초과 차단"""
    assert should_price_block(1100, 1000) is True
    assert should_price_block(1000, 1000) is False
    assert should_price_block(500, 1000) is False
    assert should_price_block(None, 1000) is False
    job = make_job(price=1100, approved=1000)
    result = PriceGuard().check(job, 1100)
    assert result == PRICE_BLOCKED


def test_backoff_recovery():
    """429 백오프와 원래 주기 복귀"""
    assert compute_current_interval(0, 0.5) == 0.5
    b1 = compute_current_interval(1, 0.5)
    b2 = compute_current_interval(2, 0.5)
    assert b1 >= 1.0
    assert b2 >= b1
    # 성공 시 원래 주기 복귀
    assert compute_current_interval(0, 0.5) == 0.5
    # 429 감지
    assert is_rate_limited(RuntimeError("HTTP 429 Too Many Requests")) is True


def test_user_intervention_states_and_duplicate_prevention():
    """사용자 개입 두 상태와 주문확정 이후 중복 방지"""
    assert USER_ACTION_CAPTCHA in USER_INTERVENTION
    assert USER_ACTION_PAYMENT_PIN in USER_INTERVENTION
    job = make_job(price=100, approved=100)
    done = guard_completed(job, order_id="KR-12345")
    assert done["status"] == COMPLETED
    assert done.get("order_id") == "KR-12345"
    # 중복 완료 방지
    again = guard_completed(job, order_id="KR-12345")
    assert again["status"] == COMPLETED
    assert again["order_id"] == "KR-12345"



def test_runner_watch_cycle():
    """감시 루프 상태 전이 (순수)"""
    r = WatchRunner(interval=DEFAULT_INTERVAL)
    assert r.next_sleep() == DEFAULT_INTERVAL
    assert r.on_error(Exception("429")) > DEFAULT_INTERVAL
    r.on_success()
    assert r.failure_attempt == 0


def main():
    if os.environ.get("CARTIER_AUTO_TEST_TARGET") == "quick":
        # 빠른 검증: 위시리스트 파싱과 상태 머신만
        test_wishlist_pid_selection()
        test_price_block_guard()
        print("quick tests OK")
        return 0
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {test.__name__}: {exc}")
            import traceback
            traceback.print_exc()
    print(f"\n{len(tests) - failed}/{len(tests)} tests passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
