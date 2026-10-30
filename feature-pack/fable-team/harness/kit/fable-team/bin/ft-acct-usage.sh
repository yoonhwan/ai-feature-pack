#!/usr/bin/env bash
# ft-acct-usage.sh — 계정별 «구독 한도 상태» 읽기 전용 조회 (r1183 · 하드 룰 12 «7초 룰»)
#   ft-acct-usage.sh [--json] [--account <짧은 id>]
# 행 = provider · account(짧은 id · 이메일 전문 0) · limit · used · remaining · spent(직전 조회 대비) · reset_at · unit · result
#      + five_hour · seven_day · reset_5h · reset_7d · credits(응답이 준 것만 · 못 준 칸은 «근거 없음»)
# 어댑터 = provider 1개 : claude(Anthropic /api/oauth/usage) · codex(chatgpt wham/usage) — $FT_ACCT_USAGE_ADAPTER_DIR/*.py 로 추가(본체 수정 0)
# rc: 0 정상 · 2 전 계정 실패(또는 auth 폴더 없음) · 3 일부 실패 · 1 사용법
# 쓰기 0: auth 파일·cliproxy 설정은 읽기만 · 토큰 갱신 0 · 캐시 파일(60초)만 쓴다
# 7초 룰: 계정 1개 = 시도 7초 + 재시도 1 · 배치 = min(고정비 3 + 7×N, 70)초
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "판정 불가 python3 없음" >&2; exit 2; }
FT_ACCT_USAGE_BIN="$HERE" exec python3 - "$@" <<'PY'
import datetime as dt
import glob
import importlib.util
import hashlib
import json
import os
import re
import subprocess
import sys
import time

NA = "근거 없음"
KEYS = ["provider", "account", "limit", "used", "remaining", "spent", "reset_at", "unit", "result",
        "five_hour", "seven_day", "reset_5h", "reset_7d", "credits"]
AUTH_DIR = os.environ.get("FT_ACCT_USAGE_AUTH_DIR") or os.path.expanduser("~/.cli-proxy-api")
STATE = os.environ.get("FT_ACCT_USAGE_STATE") or "/tmp/ft-acct-usage"
CURL = os.environ.get("FT_ACCT_USAGE_CURL") or "curl"
TTL = int(os.environ.get("FT_ACCT_USAGE_TTL") or "60")
NOW = float(os.environ.get("FT_ACCT_USAGE_NOW") or 0) or time.time()
ADAPTER_DIR = os.environ.get("FT_ACCT_USAGE_ADAPTER_DIR") or os.path.join(
    os.environ.get("FT_ACCT_USAGE_BIN", "."), "ft-acct-usage.adapters.d")


def iso(v):  # 응답의 리셋 값(ISO 문자열 또는 epoch 초) → ISO 문자열 · 근거 없으면 ""
    if v is None or v == "":
        return ""
    if isinstance(v, (int, float)):
        return dt.datetime.fromtimestamp(float(v), dt.timezone.utc).isoformat(timespec="seconds")
    return str(v)


def hhmm(v):  # 표 표시용 — 파싱 불가면 원문
    try:
        return dt.datetime.fromisoformat(str(v)).astimezone().strftime("%m-%d %H:%M")
    except Exception:
        return str(v)


def expired(auth):
    v = auth.get("expired")
    if not v:
        return False
    try:
        return dt.datetime.fromisoformat(str(v)).timestamp() <= NOW
    except Exception:
        return False


def short_id(stem):
    """파일 이름 → 짧은 id (uuid8 + 이메일 local 앞 3자 + 도메인 + plan 꼬리). 이메일 전문 0."""
    m = re.match(r"^[A-Za-z]+-([0-9a-fA-F]{6,})-?(.*)$", stem)
    head, rest = (m.group(1)[:8].lower(), m.group(2)) if m else (hashlib.sha1(stem.encode()).hexdigest()[:8], stem)
    local, at, dom = rest.partition("@")
    return f"{head}-{local[:3]}@{dom}" if at else f"{head}-{rest[:4]}"


def now_iso():
    return dt.datetime.fromtimestamp(NOW, dt.timezone.utc).isoformat(timespec="seconds")


def make_http(deadline):
    def once(url, headers, timeout):
        cmd = [CURL, "-s", "-m", str(timeout), "-w", "\n%{http_code}", url]
        for k, v in headers:
            cmd += ["-H", f"{k}: {v}"]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except OSError:
            return None, "", f"{CURL} 실행 실패"
        if r.returncode != 0:
            return None, "", "시간 초과" if r.returncode == 28 else f"curl rc{r.returncode}"
        body, _, code = r.stdout.rpartition("\n")
        return (int(code) if code.isdigit() else 0), body, ""

    def http(url, headers):
        err = "시간 초과"
        for _ in (0, 1):  # 재시도 1회 — «응답이 온» 실패는 재시도하지 않는다
            left = deadline - time.time()
            if left < 1:
                return None, "", "시간 초과"
            st, body, err = once(url, headers, max(1, min(7, int(left))))
            if not err:
                return st, body, ""
        return None, "", err

    return http


def http_result(st, body):
    """공통 응답 판정 → (json | None, result 문자열). result 가 빈 문자열이면 성공."""
    if st == 429:
        return None, "429 · 판정 불가"
    if st in (401, 403):
        return None, "만료 · cliproxy 갱신 대기"
    if st != 200:
        return None, f"판정 불가 HTTP {st}"
    try:
        return json.loads(body), ""
    except Exception:
        return None, "판정 불가 응답 형식"


def claude_fetch(auth, http):  # 어댑터 = provider 1개
    st, body, err = http("https://api.anthropic.com/api/oauth/usage", [
        ("Authorization", "Bearer " + str(auth.get("access_token") or "")),
        ("anthropic-version", "2023-06-01"), ("anthropic-beta", "oauth-2025-04-20")])
    if err:
        return {"result": "판정 불가 " + err}
    j, res = http_result(st, body)
    if res:
        return {"result": res}
    lim = {x.get("kind"): x for x in (j.get("limits") or []) if isinstance(x, dict)}
    fh, sd = (j.get("five_hour") or {}), (j.get("seven_day") or {})
    sess, week = (lim.get("session") or {}), (lim.get("weekly") or lim.get("weekly_scoped") or {})
    five = fh.get("utilization") if isinstance(fh.get("utilization"), (int, float)) else sess.get("percent")
    seven = sd.get("utilization") if isinstance(sd.get("utilization"), (int, float)) else week.get("percent")
    row = {"five_hour": five if five is not None else NA, "seven_day": seven if seven is not None else NA,
           "reset_5h": iso(fh.get("resets_at") or sess.get("resets_at")),
           "reset_7d": iso(sd.get("resets_at") or week.get("resets_at")), "unit": "%",
           "limit": 100, "used": five, "remaining": None if five is None else 100 - five,
           "reset_at": iso(fh.get("resets_at") or sess.get("resets_at"))}
    return row


def codex_fetch(auth, http):
    st, body, err = http("https://chatgpt.com/backend-api/wham/usage", [
        ("Authorization", "Bearer " + str(auth.get("access_token") or "")),
        ("chatgpt-account-id", str(auth.get("account_id") or "")), ("User-Agent", "codex_cli_rs")])
    if err:
        return {"result": "판정 불가 " + err}
    j, res = http_result(st, body)
    if res:
        return {"result": res}
    rl = j.get("rate_limit") or {}
    pw, sw = (rl.get("primary_window") or {}), (rl.get("secondary_window") or {})
    win = (int(pw.get("limit_window_seconds") or 0), pw.get("used_percent"))
    five, seven = ((NA, win[1]) if win[0] >= 86400 else (win[1], NA))
    cr = j.get("credits") or {}
    return {"five_hour": five if five is not None else NA, "seven_day": seven if seven is not None else NA,
            "reset_5h": "", "reset_7d": iso(pw.get("reset_at")) or (now_iso() if pw.get("reset_after_seconds") else ""),
            "unit": "%", "limit": 100, "used": pw.get("used_percent"),
            "remaining": None if pw.get("used_percent") is None else 100 - pw["used_percent"],
            "reset_at": iso(pw.get("reset_at")),
            "credits": cr.get("balance") if cr.get("has_credits") and not cr.get("unlimited") else NA}


ADAPTERS = {"claude": claude_fetch, "codex": codex_fetch}


def load_adapters():
    if not os.path.isdir(ADAPTER_DIR):
        return ADAPTERS
    for p in sorted(glob.glob(os.path.join(ADAPTER_DIR, "*.py"))):
        try:
            spec = importlib.util.spec_from_file_location("fau_" + os.path.basename(p)[:-3], p)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            if callable(getattr(mod, "fetch", None)) and getattr(mod, "PROVIDER", None):
                ADAPTERS[str(mod.PROVIDER)] = mod.fetch
        except Exception as e:  # 어댑터 적재 실패도 조용히 넘기지 않는다
            print(f"판정 불가 어댑터 적재 {os.path.basename(p)} {type(e).__name__}", file=sys.stderr)
    return ADAPTERS


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def fill(row):
    for k in KEYS:
        v = row.get(k)
        row[k] = NA if v is None or v == "" else v
    return {k: row.get(k) for k in KEYS}


def main(argv):
    load_adapters()
    as_json = "--json" in argv
    want = ""
    if "--account" in argv:
        i = argv.index("--account")
        if i + 1 >= len(argv):
            print("사용법: ft-acct-usage.sh [--json] [--account <짧은 id>]", file=sys.stderr)
            return 1
        want = argv[i + 1]
    if not os.path.isdir(AUTH_DIR) or not os.access(AUTH_DIR, os.R_OK):
        print(f"판정 불가 auth 폴더 {AUTH_DIR}")
        return 2
    files = sorted(glob.glob(os.path.join(AUTH_DIR, "*.json")))
    if not files:
        print(f"판정 불가 auth 파일 없음 {AUTH_DIR}")
        return 2
    rows, targets = [], []
    for p in files:
        stem = os.path.basename(p)[:-5]
        prov = stem.split("-")[0]
        row = {"provider": prov, "account": short_id(stem)}
        if want and not row["account"].startswith(want):
            continue
        auth = load_json(p, None)
        if not isinstance(auth, dict):
            rows.append((p, dict(row, result="판정 불가 auth 파일 손상"), auth))
        elif auth.get("disabled"):
            rows.append((p, dict(row, result="비활성"), auth))
        elif prov not in ADAPTERS:
            rows.append((p, dict(row, result=f"판정 불가 어댑터 없음 {prov}"), auth))
        elif expired(auth):
            rows.append((p, dict(row, result="만료 · cliproxy 갱신 대기"), auth))
        else:
            rows.append((p, dict(row, result=""), auth))
            targets.append(rows[-1])
    if want and not rows:
        print(f"판정 불가 계정 없음 {want}")
        return 2
    os.makedirs(STATE, exist_ok=True)
    cache = load_json(os.path.join(STATE, "cache.json"), {})
    last = load_json(os.path.join(STATE, "last.json"), {})
    deadline = time.time() + min(3 + 7 * len(targets), 70)
    http = make_http(deadline)
    for path, row, auth in targets:
        hit = cache.get(row["account"]) or {}
        if hit.get("row") and isinstance(hit.get("at"), (int, float)) and NOW - hit["at"] < TTL:
            row.update({k: v for k, v in hit["row"].items() if k in KEYS})
            continue
        got = ADAPTERS[row["provider"]](auth, http)
        row.update({k: v for k, v in got.items() if k in KEYS})
        used = row.get("used")
        prev = last.get(row["account"], {})
        if isinstance(used, (int, float)) and isinstance(prev.get("used"), (int, float)):
            row["spent"] = round(used - prev["used"], 2)
        if not row.get("result"):
            row["result"] = "OK"
            cache[row["account"]] = {"at": NOW, "row": {k: row.get(k) for k in KEYS}}
            last[row["account"]] = {"used": used, "at": NOW}
    for name, blob in (("cache.json", cache), ("last.json", last)):
        try:
            with open(os.path.join(STATE, name), "w", encoding="utf-8") as f:
                json.dump(blob, f, ensure_ascii=False)
        except OSError as e:
            print(f"경고 캐시 쓰기 실패 {name}: {type(e).__name__}", file=sys.stderr)
    out = [fill(r) for _p, r, _a in rows]
    if as_json:
        print(json.dumps(out, ensure_ascii=False, indent=1))
    else:
        cols = ["provider", "account", "five_hour", "seven_day", "reset_5h", "reset_7d", "result"]
        head = ["provider", "account", "5h", "7d", "reset(5h)", "reset(7d)", "result"]
        body = [[hhmm(r["reset_5h"]) if r["reset_5h"] != NA else NA,
                 hhmm(r["reset_7d"]) if r["reset_7d"] != NA else NA] for r in out]
        table = [head] + [[str(r[c]) for c in ("provider", "account", "five_hour", "seven_day")] + b + [r["result"]]
                          for r, b in zip(out, body)]
        w = [max(len(str(row[i])) for row in table) for i in range(len(cols))]
        for row in table:
            print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(row)).rstrip())
    bad = [r for r in out if any(k in str(r["result"]) for k in ("판정 불가", "429", "만료"))]
    if not bad:
        return 0
    return 2 if len(bad) == len(out) else 3


sys.exit(main(sys.argv[1:]))
PY
