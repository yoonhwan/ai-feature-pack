#!/usr/bin/env bash
# ft-acct-forecast.sh — 계정·창·풀마다 «소진 예상 시각 · 풀림 시각» 을 근거 있는 값으로만 낸다 (r1213)
#   ft-acct-forecast.sh [--json] [--model <scope 모델 이름>] [--pool <provider>]
# 입력 = ft-acct-usage.sh --json(같은 폴더) + <상태 폴더>/samples.tsv · 쓰기 0(표본은 조회 도구가 남긴다)
# 속도 = 같은 리셋 창 표본 중 «마지막 감소 뒤» 유효 표본 ≥2 · 간격 ≥60초 → 시간당 %
# 소진 예상 = 관측 시각 + (임계 − 지금 %)/속도 · 결과가 resets_at 뒤면 «리셋 전 소진 없음»
# 임계 = FT_ACCT_FULL(기본 98) 하나로 통일 · 시각 = FT_ACCT_USAGE_NOW(조회 도구와 같은 변수 · 0 유효)
# 풀 전체 소진 예상은 내지 않는다(계정 배정 순서·전환 뒤 속도를 모른다) — 가장 이른 계정 소진만 낸다
# rc: 0 정상 · 1 사용법 · 2 전 계정 판정 불가(조회 도구 rc2 전파) · 3 일부 판정 불가
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "판정 불가 python3 없음" >&2; exit 2; }
FT_ACCT_FORECAST_BIN="$HERE" exec python3 - "$@" <<'PY'
import datetime as dt
import json
import os
import subprocess
import sys
import time

NA = "근거 없음"
BIN = os.environ.get("FT_ACCT_FORECAST_BIN") or "."
USAGE = os.path.join(BIN, "ft-acct-usage.sh")
CALL_TIMEOUT = 80  # 조회 도구 배치 상한 70초 + 여유
FULL = float(os.environ.get("FT_ACCT_FULL") or "98")
SAMPLE_FIELDS = 7


def now_val():  # 시각 주입은 0 도 유효 — 없을 때만 실제 시각(조회 도구와 같은 규칙)
    v = os.environ.get("FT_ACCT_USAGE_NOW")
    if v is None or v == "":
        return time.time()
    try:
        return float(v)
    except ValueError:
        return time.time()


NOW = now_val()


def common_root():  # 조회 도구와 같은 방식 — 상태 폴더는 <리포 루트>/.fable-team/state/acct-usage
    try:
        g = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=7)
    except (subprocess.SubprocessError, OSError):
        return ""
    root = (g.stdout or "").strip()
    if g.returncode != 0 or not root:
        return ""
    root = root[:-5] if root.endswith("/.git") else root
    return root if os.path.isdir(os.path.join(root, ".fable-team")) else ""


def state_dir():
    v = os.environ.get("FT_ACCT_USAGE_STATE")
    if v:
        return v
    root = common_root()
    if root:
        return os.path.join(root, ".fable-team", "state", "acct-usage")
    return os.path.expanduser("~/.fable-team/state/acct-usage")


STATE = state_dir()


def scope_str(scope):  # 표본 칸과 «같은» 직렬화여야 창과 표본이 만난다
    if scope is None:
        return ""
    try:
        s = json.dumps(scope, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    except (TypeError, ValueError):
        s = str(scope)
    return s.replace("\t", " ").replace("\n", " ").replace("\r", " ")


def epoch(v):
    if isinstance(v, bool) or v is None or v == "" or v == NA:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return dt.datetime.fromisoformat(str(v)).timestamp()
    except ValueError:
        return None


def hhmm(v):
    t = epoch(v)
    return dt.datetime.fromtimestamp(t).strftime("%H:%M") if t is not None else NA


def iso_at(t):
    return dt.datetime.fromtimestamp(float(t), dt.timezone.utc).isoformat(timespec="seconds")


def load_samples():
    out = []
    try:
        with open(os.path.join(STATE, "samples.tsv"), encoding="utf-8") as f:
            for line in f:
                f7 = line.rstrip("\n").split("\t")
                if len(f7) != SAMPLE_FIELDS:
                    continue
                try:
                    at, pct = float(f7[0]), float(f7[5])
                except ValueError:
                    continue
                out.append({"at": at, "key": f7[2], "kind": f7[3], "scope": f7[4],
                            "resets_at": f7[6], "percent": pct})
    except OSError:
        pass
    return out


def speed(samples, key, kind, scope, resets_at):
    """같은 리셋 창의 표본에서 «마지막 감소 뒤» 유효 표본 ≥2 · 간격 ≥60초 → 시간당 %"""
    seq = [s for s in samples if s["key"] == key and s["kind"] == kind
           and s["scope"] == scope and s["resets_at"] == resets_at and s["at"] <= NOW]
    seq.sort(key=lambda s: s["at"])
    if len(seq) < 2:
        return None, "표본"
    start = 0
    for i in range(1, len(seq)):
        if seq[i]["percent"] < seq[i - 1]["percent"]:
            start = i  # 감소 직전 표본은 다른 구간이다 — 그 뒤만 센다
    tail = seq[start:]
    if len(tail) < 2:
        return None, "감소"
    span = tail[-1]["at"] - tail[0]["at"]
    if span < 60:
        return None, "간격"
    rate = (tail[-1]["percent"] - tail[0]["percent"]) / (span / 3600.0)
    if rate <= 0:
        return None, "속도"
    return rate, ""


def model_of(scope):
    if not isinstance(scope, dict):
        return None
    m = scope.get("model")
    if isinstance(m, dict):
        name = m.get("id") or m.get("display_name")
        return str(name) if name else None
    if isinstance(m, str) and m:
        return m
    return None


def is_scoped(win):
    kind = str(win.get("kind") or "")
    return "scoped" in kind or win.get("scope") is not None


def judge(win, row, key, samples):
    """창 1개 판정 — state ∈ 소진 · 소진 예상 · 리셋 전 소진 없음 · 재조회 필요 · 근거 없음"""
    kind = str(win.get("kind") or "")
    scope = scope_str(win.get("scope"))
    pct = win.get("percent")
    rsv = win.get("resets_at")
    rs_clean = "" if rsv in (None, "") or rsv == NA else str(rsv)
    obs = epoch(row.get("observed_at"))
    rse = epoch(rs_clean)
    out = {"kind": kind, "scope": scope, "percent": pct, "resets_at": rs_clean,
           "observed_at": row.get("observed_at"), "state": "", "eta": None, "why": ""}
    if not isinstance(pct, (int, float)):
        out.update(state=NA, why="값")
        return out
    if rse is not None and rse < NOW:  # 캐시 유효 중 리셋이 지났다 = 재조회 없이 확정 0
        out.update(state="재조회 필요", why="리셋 지남")
        return out
    if pct >= FULL:
        out.update(state="소진")
        return out
    rate, why = speed(samples, key, kind, scope, rs_clean)
    if rate is None:
        out.update(state=NA, why=why)
        return out
    eta = (obs if obs is not None else NOW) + (FULL - pct) / rate * 3600.0  # 지금이 아니라 관측 시각 기준
    if rse is not None and eta > rse:
        out.update(state="리셋 전 소진 없음")
        return out
    out.update(state="소진 예상", eta=eta, why=f"시간당 {rate:.1f}%")
    return out


def account_verdict(winlist, judged, want_model):
    """모델 판정 = 공통 창 전부 AND 그 모델 scope 창 · scope 미상은 «근거 없음(scope)»(all 로 바꾸지 않음)"""
    exhausted, blocked, unknown = [], [], False
    for w, j in zip(winlist, judged):
        scoped = is_scoped(w)
        name = model_of(w.get("scope")) if scoped else None
        tag = "모델 창" if scoped else "공통 창"
        if scoped and name is None:
            unknown = True
            continue
        if scoped and want_model and name.lower() != want_model.lower():
            continue  # 다른 모델 창은 이 모델 판정에 걸리지 않는다
        if j["state"] == "소진":
            exhausted.append((tag, j))
        elif j["state"] == "재조회 필요" or (j["state"] == NA and j["why"] == "값"):
            blocked.append(tag)
    if unknown:
        return False, f"{NA}(scope)", None
    if exhausted:
        rs = [epoch(j["resets_at"]) for _t, j in exhausted]
        rs = [t for t in rs if t is not None]
        return False, f"소진({exhausted[0][0]})", (max(rs) if rs else None)  # 계정 풀림 = 소진 창 중 가장 늦은
    if blocked:
        return False, blocked[0], None
    return True, "가용", None


def parse_rows(out, rc):
    try:
        rows = json.loads(out)
    except ValueError:
        return None
    return rows if isinstance(rows, list) else None


def build_pool(prov, rows, samples, want_model):
    accounts, windows_out, earliest, bad_any = [], [], None, False
    free_times = []
    for row in rows:
        if str(row.get("provider") or "") != prov:
            continue
        acc = str(row.get("account") or "")
        wins = row.get("windows")
        if str(row.get("result") or "OK") != "OK":
            bad_any = True
            accounts.append({"account": acc, "judge": "판정 불가", "free": None})
            windows_out.append({"account": acc, "judge": "판정 불가", "windows": []})
            continue
        if not isinstance(wins, list):
            why = wins if isinstance(wins, str) and wins.startswith(NA) else f"{NA}(창)"
            accounts.append({"account": acc, "judge": why, "free": None})
            windows_out.append({"account": acc, "judge": why, "windows": []})
            continue
        key = row.get("account_key") or ""
        judged = [judge(w, row, key, samples) for w in wins]
        ok, why, free = account_verdict(wins, judged, want_model)
        if free is not None:
            free_times.append(free)
        accounts.append({"account": acc, "judge": why, "free": (iso_at(free) if free else None)})
        windows_out.append({"account": acc, "judge": why, "windows": judged})
        for j in judged:
            if j["state"] == "소진 예상" and j["eta"] is not None:
                if earliest is None or j["eta"] < earliest["at"]:
                    earliest = {"account": acc, "at": j["eta"], "kind": j["kind"]}
    available = sum(1 for a in accounts if a["judge"] == "가용")
    pool = {"pool": prov, "model": want_model or None, "available": available,
            "accounts": len(accounts),
            "earliest": ({"account": earliest["account"], "at": iso_at(earliest["at"]),
                          "kind": earliest["kind"]} if earliest else None),
            "pool_reset": (iso_at(min(free_times)) if free_times else None),  # 풀 풀림 = 계정별 풀림 중 가장 이른 값
            "pool_exhaust": f"{NA}(배정 순서)",
            "rows": accounts, "windows": windows_out}
    return pool, bad_any


def table(head, rows):
    if not rows:
        return
    data = [head] + [[str(c) for c in r] for r in rows]
    w = [max(len(r[i]) for r in data) for i in range(len(head))]
    for r in data:
        print("  ".join(r[i].ljust(w[i]) for i in range(len(head))).rstrip())


def main(argv):
    want_model = ""
    want_pool = ""
    if "--model" in argv:
        i = argv.index("--model")
        if i + 1 >= len(argv):
            print("사용법: ft-acct-forecast.sh [--json] [--model <모델>] [--pool <provider>]", file=sys.stderr)
            return 1
        want_model = argv[i + 1]
    if "--pool" in argv:
        i = argv.index("--pool")
        if i + 1 >= len(argv):
            print("사용법: ft-acct-forecast.sh [--json] [--model <모델>] [--pool <provider>]", file=sys.stderr)
            return 1
        want_pool = argv[i + 1]
    try:  # 조회 도구가 시간을 강제한다(7초 룰은 그쪽 몫 · 여기 상한은 사고 방지)
        r = subprocess.run(["bash", USAGE, "--json"], capture_output=True, text=True,
                           timeout=CALL_TIMEOUT, env=os.environ)
    except subprocess.TimeoutExpired:
        print("판정 불가 조회 시간 초과")
        return 2
    except OSError as e:
        print(f"판정 불가 조회 실행 실패 {type(e).__name__}")
        return 2
    rows = parse_rows(r.stdout, r.returncode)
    if rows is None:  # 단문 1줄(폴더 없음 등) → 그 1줄 그대로 rc2
        line = [x for x in (r.stdout or "").strip().splitlines() if x]
        print(line[0] if line else "판정 불가 조회 결과 없음")
        return 2 if r.returncode in (0, 2) else r.returncode
    bad = [x for x in rows if str(x.get("result") or "OK") != "OK"]
    if rows and len(bad) == len(rows):  # 전 계정 429 등 = 한 줄로 접는다
        print(f"판정 불가 전 계정 {bad[0].get('result')}")
        return 2
    samples = load_samples()
    provs = []
    for x in rows:
        p = str(x.get("provider") or "")
        if (not want_pool or p == want_pool) and p not in provs:
            provs.append(p)
    pools, bad_any = [], False
    for p in provs:
        pool, bad = build_pool(p, rows, samples, want_model)
        bad_any = bad_any or bad
        pools.append(pool)
    if "--json" in argv:
        print(json.dumps(pools, ensure_ascii=False, indent=1))
    else:
        for pool in pools:
            label = pool["pool"] + (f"/{pool['model']}" if pool["model"] else "")
            early = (f"{pool['earliest']['account']} {hhmm(pool['earliest']['at'])}"
                     if pool["earliest"] else f"{NA}(표본)")
            print(f"풀 {label}: 가용 {pool['available']}/{pool['accounts']} · 가장 이른 소진 {early}"
                  f" · 풀 풀림 {hhmm(pool['pool_reset']) if pool['pool_reset'] else '—'}")
            table(["account", "판정", "풀림"],
                  [[a["account"], a["judge"], hhmm(a["free"]) if a["free"] else "—"] for a in pool["rows"]])
            wrows = []
            for acc in pool["windows"]:
                for j in acc["windows"]:
                    wrows.append([acc["account"], j["kind"], j["scope"] or "-", j["percent"],
                                  hhmm(j["observed_at"]),
                                  (hhmm(j["eta"]) if j["eta"] is not None else "—"),
                                  hhmm(j["resets_at"]) if j["state"] == "소진" else "—",
                                  j["state"] + (f"({j['why']})" if j["why"] and j["state"] == NA else "")])
            table(["account", "창", "scope", "지금%", "관측", "소진 예상", "풀림", "판정"], wrows)
    return 3 if bad_any else 0


sys.exit(main(sys.argv[1:]))
PY
