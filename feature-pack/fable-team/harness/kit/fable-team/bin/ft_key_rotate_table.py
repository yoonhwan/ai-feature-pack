"""ft_key_rotate_table.py — 키 표(17키 → 파일 · 최소 길이 · 묶음)와 살아 있음 확인 방법 (R195). 값은 curl 설정을 stdin 으로만 넘긴다."""

import hashlib
import hmac
import json
import os
import subprocess
import time

from ft_key_rotate_io import ENV, ZSH

# KEY: (파일들, 최소 길이, 그룹, 묶음) — 고정 표(규칙 1). 표 밖 키 = REJECT. 묶음 = 교체 단위(binance = KEY+SECRET · op-main/op-develop · 나머지 = ENV 1개).
KEYS = {
    "OP_SERVICE_ACCOUNT_TOKEN": ([ZSH], 16, 1, "op-main"),
    "OP_SERVICE_ACCOUNT_TOKEN_DEVELOP": ([ZSH], 16, 1, "op-develop"),
    "GH_TOKEN_ORG": ([ZSH], 16, 1, "gh-token-org"),
    "BINANCE_API_KEY": ([ZSH], 16, 1, "binance"),
    "BINANCE_SECRET": ([ZSH], 16, 1, "binance"),
    "SLACK_WEBHOOK_URL": ([ZSH], 16, 1, "slack-webhook-url"),
    "OPENAI_API_KEY": ([ZSH, ENV], 16, 2, "openai-api-key"),
    "ELEVENLABS_API_KEY": ([ZSH, ENV], 16, 2, "elevenlabs-api-key"),
    "LANGSMITH_API_KEY": ([ZSH, ENV], 16, 2, "langsmith-api-key"),
    "CEREBRAS_API_KEY": ([ZSH], 16, 3, "cerebras-api-key"),
    "HUGGING_FACE_TOKEN": ([ZSH], 16, 3, "hugging-face-token"),
    "OPENROUTER_API_KEY": ([ZSH], 16, 3, "openrouter-api-key"),
    "PERPLEXITY_API_KEY": ([ZSH, ENV], 16, 3, "perplexity-api-key"),
    "RUNPOD_API_KEY": ([ZSH, ENV], 16, 3, "runpod-api-key"),
    "SEARCHAPI_KEY": ([ZSH], 16, 3, "searchapi-key"),
    "BYZ_E2E_LOGIN_PASSWORD": ([ENV], 8, 4, "byz-e2e-login-password"),
    "BYZ_E2E_JWT_SECRET": ([ENV], 16, 4, "byz-e2e-jwt-secret"),
}
BEARER = {  # KEY: (URL, 헤더 이름, 헤더 접두) — GET 200 = 살아 있음
    "GH_TOKEN_ORG": ("https://api.github.com/user", "Authorization", "Bearer "),
    "OPENAI_API_KEY": ("https://api.openai.com/v1/models", "Authorization", "Bearer "),
    "ELEVENLABS_API_KEY": ("https://api.elevenlabs.io/v1/user", "xi-api-key", ""),
    # 끝점·헤더는 공식 문서로 확인(docs.langchain.com Read tracer sessions · searchapi.io/docs/account-api)
    "LANGSMITH_API_KEY": (
        "https://api.smith.langchain.com/api/v1/sessions?limit=1",
        "x-api-key",
        "",
    ),
    "CEREBRAS_API_KEY": ("https://api.cerebras.ai/v1/models", "Authorization", "Bearer "),
    "HUGGING_FACE_TOKEN": ("https://huggingface.co/api/whoami-v2", "Authorization", "Bearer "),
    "OPENROUTER_API_KEY": ("https://openrouter.ai/api/v1/key", "Authorization", "Bearer "),
    "SEARCHAPI_KEY": ("https://www.searchapi.io/api/v1/me", "Authorization", "Bearer "),
}
DEAD_CODES = {401, 403, 404, 410}
UNVERIFIED = {
    "BYZ_E2E_LOGIN_PASSWORD": "도구 안 확인 불가 — Supabase 변경 뒤 ft-op-token.sh --init 1회 후 ft-op-token.sh <시험 계정> OK 로 확인",
    "BYZ_E2E_JWT_SECRET": "영향 조사 선행(FE·서버 서명 짝) — 그 전 교체·확인 0",
}


def cfg(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def curl(lines):
    """curl 설정을 stdin 으로 → (코드, 본문). 연결 실패만 1회 재시도(7초 룰). 값은 argv 에 안 간다."""
    for attempt in (0, 1):
        r = subprocess.run(
            ["curl", "-sS", "--max-time", "7", "-w", "\n%{http_code}", "-K", "-"],
            input="\n".join(lines),
            capture_output=True,
            text=True,
        )
        if r.returncode == 0:
            body, _, code = r.stdout.rpartition("\n")
            return int(code or 0), body
    return 0, ""


def check(key, getter, paid=False):
    """-> (상태, 라벨). 상태: ALIVE / DEAD / SKIP-CHECK / UNVERIFIED / CHECK-FAILED."""
    if key in UNVERIFIED:
        return "UNVERIFIED", UNVERIFIED[key]
    val = getter(key)
    if val is None:
        return "CHECK-FAILED", "값 없음"
    if key.startswith("OP_SERVICE_ACCOUNT_TOKEN"):
        env = dict(os.environ, OP_SERVICE_ACCOUNT_TOKEN=val)
        for _ in (0, 1):
            try:
                rc = subprocess.run(
                    ["op", "whoami"], env=env, capture_output=True, timeout=7
                ).returncode
                return ("ALIVE" if rc == 0 else "DEAD"), "rc=%d" % rc
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass
        return "CHECK-FAILED", "op 응답 없음"
    if key == "PERPLEXITY_API_KEY" and not paid:
        return "SKIP-CHECK", "유료 호출 0 (--paid-check 로만)"
    if key == "BINANCE_API_KEY":
        return "SKIP-CHECK", "BINANCE_SECRET 교체 뒤 1회 확인"
    body_extra = False
    if key in BEARER:
        url, h, pre = BEARER[key]
        lines = ["url = %s" % cfg(url), "header = %s" % cfg(h + ": " + pre + val)]
    elif key == "PERPLEXITY_API_KEY":
        lines = [
            'url = "https://api.perplexity.ai/chat/completions"',
            "header = %s" % cfg("Authorization: Bearer " + val),
            'header = "Content-Type: application/json"',
            "data = %s"
            % cfg(
                json.dumps(
                    {
                        "model": "sonar",
                        "max_tokens": 1,
                        "messages": [{"role": "user", "content": "hi"}],
                    }
                )
            ),
        ]
    elif key == "RUNPOD_API_KEY":
        body_extra = True
        lines = [
            'url = "https://api.runpod.io/graphql"',
            "header = %s" % cfg("Authorization: Bearer " + val),
            'header = "Content-Type: application/json"',
            "data = %s" % cfg('{"query":"query{myself{id}}"}'),
        ]
    elif key == "SLACK_WEBHOOK_URL":
        lines = [
            "url = %s" % cfg(val),
            'header = "Content-Type: application/json"',
            'data = ""',
        ]  # 빈 본문 POST — 게시 0
    elif key == "BINANCE_SECRET":
        ak = getter("BINANCE_API_KEY")
        q = "timestamp=%d&recvWindow=5000" % (time.time() * 1000)
        sig = hmac.new(val.encode(), q.encode(), hashlib.sha256).hexdigest()
        lines = [
            "url = %s"
            % cfg(
                "https://api.binance.com/sapi/v1/account/apiRestrictions?%s&signature=%s" % (q, sig)
            ),
            "header = %s" % cfg("X-MBX-APIKEY: " + (ak or "")),
        ]
    else:
        return "UNVERIFIED", "확인 방법 미정의"
    code, body = curl(lines)
    if code == 0:
        return "CHECK-FAILED", "http=000 (네트워크)"
    label = "http=%d" % code
    if key == "SLACK_WEBHOOK_URL":
        return (
            "ALIVE" if code in (200, 400) else "DEAD" if code in DEAD_CODES else "CHECK-FAILED"
        ), label
    if body_extra and code == 200 and '"errors"' in body:
        return "DEAD", label + " errors"
    return ("ALIVE" if code == 200 else "DEAD" if code in DEAD_CODES else "CHECK-FAILED"), label
