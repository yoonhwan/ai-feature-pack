#!/usr/bin/env bash
# ft-acct-usage.sh — 계정별 «구독 한도 상태» 읽기 전용 조회 (r1183 · 하드 룰 12 «7초 룰»)
#   ft-acct-usage.sh [--json] [--account <짧은 id>]
# 행 = provider · account(짧은 id · 이메일 전문 0) · limit · used · remaining · spent(직전 조회 대비) · reset_at · unit · result
#      + five_hour · seven_day · reset_5h · reset_7d · credits(응답이 준 것만 · 못 준 칸은 «근거 없음»)
# 어댑터 = provider 1개 : claude(Anthropic /api/oauth/usage) · codex(chatgpt wham/usage) — $FT_ACCT_USAGE_ADAPTER_DIR/*.py 로 추가(본체 수정 0)
# rc: 0 정상 · 2 전 계정 실패(또는 auth 폴더 없음) · 3 일부 실패 · 1 사용법
# 쓰기 0: auth 파일·cliproxy 설정은 읽기만 · 토큰 갱신 0 · 캐시 파일(60초 · 실패 결과 포함)만 쓴다
# 7초 룰: 계정 1개 = 시도 7초 + 재시도 1(부모가 timeout 으로 끊는다) · 배치 = min(고정비 3 + 7×N, 70)초
# 비밀: 출력·캐시·stderr 에 access_token·refresh_token·id_token 글자 0 («[가림]» · 계정 단위로 가린다)
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
SECRET_FIELDS = ("access_token", "refresh_token", "id_token")


def mask(text, secrets):  # 모든 출력 길(표·json·캐시·result 문구)이 이 함수만 통과한다
    s = str(text)
    for t in secrets:
        if t and len(str(t)) >= 6:
            s = s.replace(str(t), "[가림]")
    return s


def secrets_of(auth):
    return [str(auth.get(k) or "") for k in SECRET_FIELDS]


def mask_row(row, secrets):
    out = {}
    for k in KEYS:
        v = row.get(k)
        out[k] = mask(v, secrets) if isinstance(v, str) else v
    return out


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
    """파일 이름 → 짧은 id (uuid8 + 이메일 local 앞 2자 «…» 도메인 앞 1자). 이메일 전문 0(DA 반송 4)."""
    m = re.match(r"^[A-Za-z]+-([0-9a-fA-F]{6,})-?(.*)$", stem)
    head, rest = (m.group(1)[:8].lower(), m.group(2)) if m else ("", stem)
    local, at, dom = rest.partition("@")
    core = f"{local[:2]}…{dom[:1]}" if at else (rest[:4] or hashlib.sha1(stem.encode()).hexdigest()[:8])
    return f"{head}-{core}" if head else core


def now_iso():
    return dt.datetime.fromtimestamp(NOW, dt.timezone.utc).isoformat(timespec="seconds")


def make_http(deadline):
    def once(url, headers, timeout):
        cmd = [CURL, "-s", "-m", str(timeout), "-w", "\n%{http_code}", url]
        for k, v in headers:
            cmd += ["-H", f"{k}: {v}"]
        try:  # 부모가 시간을 강제한다 — -m 을 무시하는 curl 도 7초에 끊긴다(DA 반송 7)
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 0.5)
        except subprocess.TimeoutExpired:
            return None, "", "시간 초과"
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
    """공통 응답 판정 → (json dict | None, result 문자열). result 가 빈 문자열이면 성공."""
    if st == 429:
        return None, "429 · 판정 불가"
    if st in (401, 403):
        return None, "만료 · cliproxy 갱신 대기"
    if st != 200:
        return None, f"판정 불가 HTTP {st}"
    try:
        j = json.loads(body)
    except Exception:
        return None, "판정 불가 응답 꼴"
    return (j, "") if isinstance(j, dict) else (None, "판정 불가 응답 꼴")


def window_bucket(window):  # 창 종류는 limit_window_seconds 값으로 고른다(순서 가정 0 · DA 반송 3)
    secs = int(window.get("limit_window_seconds") or 0)  # 꼴이 틀리면 계정 단위 격리로 간다(조용한 빈 값 0)
    used = window.get("used_percent")
    if not isinstance(used, (int, float)) or secs <= 0:
        return None
    return "five_hour" if secs <= 21600 else "seven_day"


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
    return {"five_hour": five, "seven_day": seven,
            "reset_5h": iso(fh.get("resets_at") or sess.get("resets_at")),
            "reset_7d": iso(sd.get("resets_at") or week.get("resets_at")), "unit": "%",
            "limit": 100, "used": five, "remaining": None if five is None else 100 - five,
            "reset_at": iso(fh.get("resets_at") or sess.get("resets_at")),
            "credits": (j.get("iguana_necktie") or {}).get("remaining_dollars")}


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
    row = {"unit": "%", "limit": 100}
    for w in (rl.get("primary_window") or {}, rl.get("secondary_window") or {}):
        bucket = window_bucket(w)
        if not bucket:
            continue
        used = w.get("used_percent")
        row[bucket] = used
        row["reset_" + ("5h" if bucket == "five_hour" else "7d")] = (
            iso(w.get("reset_at")) or (now_iso() if w.get("reset_after_seconds") else ""))
        row["used"] = used
        row["remaining"] = 100 - used
        row["reset_at"] = row.get("reset_at") or iso(w.get("reset_at"))
    cr = j.get("credits") or {}
    row["credits"] = cr.get("balance") if cr.get("has_credits") and not cr.get("unlimited") else NA
    return row


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
        except Exception as exc:  # 어댑터 적재 실패도 조용히 넘기지 않는다
            print(f"판정 불가 어댑터 적재 {os.path.basename(p)} {type(exc).__name__}", file=sys.stderr)
    return ADAPTERS


def fetch_guarded(prov, auth, http, secrets):  # 계정 단위 격리 — 한 계정의 응답 꼴이 틀려도 나머지는 계속(DA 반송 2·5)
    try:
        return ADAPTERS[prov](auth, http)
    except Exception as e:
        return {"result": "판정 불가 응답 꼴 " + mask(f"{type(e).__name__}: {e}", secrets)}


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
    rows, targets, seen = [], [], {}
    for p in files:
        stem = os.path.basename(p)[:-5]
        prov = stem.split("-")[0]
        acc = short_id(stem)
        seen[acc] = seen.get(acc, 0) + 1
        acc = acc if seen[acc] == 1 else f"{acc}-{seen[acc]}"  # 짧은 id 충돌은 번호로 가른다
        row = {"provider": prov, "account": acc}
        if want and not acc.startswith(want):
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
        secrets = secrets_of(auth)
        hit = cache.get(row["account"]) or {}
        if hit.get("row") and isinstance(hit.get("at"), (int, float)) and NOW - hit["at"] < TTL:
            row.update({k: v for k, v in hit["row"].items() if k in KEYS})  # 실패 결과도 캐시(DA 반송 6)
            continue
        got = fetch_guarded(row["provider"], auth, http, secrets)
        row.update({k: v for k, v in got.items() if k in KEYS})
        if not row.get("result"):
            row["result"] = "OK"
        used = row.get("used")
        prev = last.get(row["account"], {})
        if isinstance(used, (int, float)) and isinstance(prev.get("used"), (int, float)):
            row["spent"] = round(used - prev["used"], 2)
        cache[row["account"]] = {"at": NOW, "row": mask_row(row, secrets)}
        if row["result"] == "OK" and isinstance(used, (int, float)):
            last[row["account"]] = {"used": used, "at": NOW}
    for name, blob in (("cache.json", cache), ("last.json", last)):
        try:
            with open(os.path.join(STATE, name), "w", encoding="utf-8") as f:
                json.dump(blob, f, ensure_ascii=False)
        except OSError as e:
            print(f"경고 캐시 쓰기 실패 {name}: {type(e).__name__}", file=sys.stderr)
    out = [fill(mask_row(r, secrets_of(a) if isinstance(a, dict) else [])) for _p, r, a in rows]
    if as_json:
        print(json.dumps(out, ensure_ascii=False, indent=1))
    else:
        head = ["provider", "account", "5h", "7d", "reset(5h)", "reset(7d)", "result"]
        body = [[hhmm(r["reset_5h"]) if r["reset_5h"] != NA else NA,
                 hhmm(r["reset_7d"]) if r["reset_7d"] != NA else NA] for r in out]
        table = [head] + [[str(r[c]) for c in ("provider", "account", "five_hour", "seven_day")] + b + [r["result"]]
                          for r, b in zip(out, body)]
        w = [max(len(str(row[i])) for row in table) for i in range(len(head))]
        for row in table:
            print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(row)).rstrip())
    bad = [r for r in out if any(k in str(r["result"]) for k in ("판정 불가", "429", "만료"))]
    if not bad:
        return 0
    return 2 if len(bad) == len(out) else 3


sys.exit(main(sys.argv[1:]))
PY
