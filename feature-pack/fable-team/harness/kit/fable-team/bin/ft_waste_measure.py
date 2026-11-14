#!/usr/bin/env python3
# ft_waste_measure.py — r1462 «깨우는 턴 1개 = 도구 1회» 측정기(비모델 · 세션 jsonl 만 읽는다 · 쓰기 0).
#   usage: ft_waste_measure.py <jsonl> [--since <ISO>]      rc 0 = 기준 안 넘음 · 1 = 초과/판정 불가 · 2 = usage·입력 오류
#   세는 법(같은 요청 단위): assistant message.id 고유 수 = 요청 — 같은 응답이 content 블록마다 행으로 갈라져 있으므로
#     행 수로 세면 요청이 부풀려진다(master 실측: 행 231 = 요청 140). 그 갈라진 행의 tool_use 는 그 요청에 «합쳐» 센다
#     (첫 행만 쓰면 thinking 행이 먼저 와 도구 수가 0 이 된다 — E3 를 속인다). user 텍스트 행 1개 = 깨우는 턴(tool_result 행은 턴이 아니다).
#     틱 턴 = user 텍스트가 «[desk 틱» 으로 시작하는 턴.
#   E1 = 요청/턴(기준 ≤2) · E2 = Σcache_read_input_tokens/요청(≤60000) · E3 = 틱 턴의 tool_use 수(≤1)
#   ★평균은 초과를 숨긴다(DA 반례①)★: E3 = 틱 턴 «별» 도구의 «최대» · E1 도 평균과 «틱 턴 최대» 둘 다 본다.
#   usage 가 아예 없는 요청은 0 으로 치환하지 않고 «미상» 으로 세어 판정 불가 rc1 (조용한 0 금지).
#   BREAK(prefix 끊김) = 앞 요청과 120초 안 ∧ cache_creation > 20000 ∧ cache_read > 0 — 세션 첫 요청은 제외.
#   새 입력 등급은 cache_creation.ephemeral_5m/1h 로 나눠 찍는다(1h 재작성은 비싸다).
#   기준 초과·판정 불가는 «FAIL <항목> …» 줄로 내고 rc1 — 조용한 0 금지(docs/rules/no_silent_fallback.md).
import datetime
import json
import sys

E1_MAX, E2_MAX, E3_MAX = 2.0, 60000, 1.0
BREAK_WINDOW, BREAK_CREATION = 120.0, 20000
TICK_HEAD = "[desk 틱"


def ts_of(s):
    """ISO(…Z · +00:00 · 초 이하 없음) → tz 붙은 datetime. 못 읽으면 None."""
    if not s:
        return None
    t = str(s).replace("Z", "+00:00")
    try:
        d = datetime.datetime.fromisoformat(t)
    except ValueError:
        try:
            d = datetime.datetime.strptime(str(s)[:19], "%Y-%m-%dT%H:%M:%S")
        except ValueError:
            return None
    return d if d.tzinfo else d.replace(tzinfo=datetime.timezone.utc)


def turn_text(row):
    """user 행이 «사람·도구가 넣은 텍스트 턴» 이면 그 글, tool_result·혼합이면 None."""
    if row.get("type") != "user":
        return None
    content = (row.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list) or not content:
        return None
    if not all(isinstance(b, dict) and b.get("type") == "text" for b in content):
        return None
    text = "\n".join(str(b.get("text") or "") for b in content)
    return text or None


def tool_names(message):
    return [str(b.get("name") or "?") for b in (message.get("content") or [])
            if isinstance(b, dict) and b.get("type") == "tool_use"]


def load(path, since):
    """jsonl → (turns, requests, orphans). requests = message.id 첫 행 1개 + 그 id 의 다른 행 tool_use 를 합친다.

    같은 응답이 content 블록마다 행으로 갈라져 있으므로(thinking 행 · tool_use 행) 첫 행만 쓰면
    도구 수가 0 이 된다 — 그게 E3 를 속인다. usage 는 같은 id 안에서 같다(첫 행 것을 쓴다).
    orphans = 어느 턴에도 안 붙은 요청(첫 user 텍스트 앞) — E1 분모에서 빼고 E2 분자에는 넣는다."""
    turns, requests, index = [], [], {}
    cur = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if not isinstance(row, dict):
                continue
            when = ts_of(row.get("timestamp"))
            if when is not None and since is not None and when < since:
                continue
            text = turn_text(row)
            if text is not None:
                cur = {"ts": when, "text": text, "requests": []}
                turns.append(cur)
                continue
            if row.get("type") != "assistant":
                continue
            message = row.get("message") or {}
            mid = message.get("id")
            if not mid:
                continue
            if mid in index:
                index[mid]["tools"].extend(tool_names(message))
                continue
            req = {"ts": when, "usage": message.get("usage") or {}, "tools": tool_names(message)}
            index[mid] = req
            requests.append(req)
            if cur is not None:
                cur["requests"].append(req)
    orphans = len(requests) - sum(len(t["requests"]) for t in turns)
    return turns, requests, orphans


def usage_sum(requests, key):
    return sum(int((r["usage"].get(key) or 0)) for r in requests)


def breaks_of(requests):
    """BREAK = 앞 요청과 120초 안 ∧ creation > 2만 ∧ read > 0 (첫 요청 제외)."""
    n, write, prev = 0, 0, None
    for r in requests:
        if prev is not None and r["ts"] and prev["ts"] and (r["ts"] - prev["ts"]).total_seconds() <= BREAK_WINDOW:
            creation = int(r["usage"].get("cache_creation_input_tokens") or 0)
            read = int(r["usage"].get("cache_read_input_tokens") or 0)
            if creation > BREAK_CREATION and read > 0:
                n += 1
                write += creation
        prev = r
    return n, write


def main(argv):
    path, since_s = None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--since":
            if i + 1 >= len(argv):
                sys.stderr.write("usage: ft_waste_measure.py <jsonl> [--since <ISO>]\n")
                return 2
            since_s = argv[i + 1]
            i += 2
            continue
        if a in ("-h", "--help") or a.startswith("-"):
            sys.stderr.write("usage: ft_waste_measure.py <jsonl> [--since <ISO>]\n")
            return 2
        if path is not None:
            sys.stderr.write("usage: ft_waste_measure.py <jsonl> [--since <ISO>]\n")
            return 2
        path, i = a, i + 1
    if not path:
        sys.stderr.write("usage: ft_waste_measure.py <jsonl> [--since <ISO>]\n")
        return 2
    since = None
    if since_s is not None:
        since = ts_of(since_s)
        if since is None:
            sys.stderr.write("REJECT --since 시각을 못 읽었다: %s\n" % since_s)
            return 2
    try:
        turns, requests, orphans = load(path, since)
    except OSError as e:
        sys.stderr.write("REJECT jsonl 을 읽지 못했다: %s\n" % e)
        return 2

    fails = []
    total = len(requests)
    measured = [r for r in requests if isinstance(r["usage"], dict) and r["usage"]]
    unknown = total - len(measured)          # usage 가 아예 없는 요청 = «미상» — 0 으로 치환하지 않는다
    read_sum = sum(int(r["usage"].get("cache_read_input_tokens") or 0) for r in measured)
    e2 = (read_sum / len(measured)) if measured else None
    e1 = (total / len(turns)) if turns else None
    tick = [t for t in turns if t["text"].lstrip().startswith(TICK_HEAD)]
    other = [t for t in turns if not t["text"].lstrip().startswith(TICK_HEAD)]
    tick_tools = [sum(len(r["tools"]) for r in t["requests"]) for t in tick]   # 틱 턴 «별» 도구 수
    tick_req = sum(len(t["requests"]) for t in tick)
    tick_max = max((len(t["requests"]) for t in tick), default=0)              # 틱 턴 «별» 요청 최대
    e3 = max(tick_tools) if tick_tools else None                              # 평균이 아니라 최대(평균은 초과를 숨김)
    nbreak, write = breaks_of(measured)
    e5 = sum(int((r["usage"].get("cache_creation") or {}).get("ephemeral_5m_input_tokens") or 0) for r in measured)
    e1h = sum(int((r["usage"].get("cache_creation") or {}).get("ephemeral_1h_input_tokens") or 0) for r in measured)
    out_tok = usage_sum(measured, "output_tokens")
    tools = sum(len(r["tools"]) for r in requests)

    print("WASTE r1462 file=%s since=%s" % (path.rsplit("/", 1)[-1], since_s or "-"))
    print("TURNS turns=%d requests=%d orphans=%d" % (len(turns), total, orphans))
    if e1 is None:
        print("E1 value=NA 기준=%g UNKNOWN turns=0" % E1_MAX)
        fails.append("E1 판정 불가 턴 0")
    else:
        others_avg = (sum(len(t["requests"]) for t in other) / len(other)) if other else 0.0
        tick_avg = (tick_req / len(tick)) if tick else 0.0
        ok = e1 <= E1_MAX and tick_max <= E1_MAX
        print("E1 value=%.2f 기준=%g %s ticks=%d tick_avg=%.2f others_avg=%.2f tick_max=%d"
              % (e1, E1_MAX, "PASS" if ok else "FAIL", len(tick), tick_avg, others_avg, tick_max))
        if e1 > E1_MAX:
            fails.append("E1 value=%.2f > 기준=%g" % (e1, E1_MAX))
        if tick_max > E1_MAX:
            fails.append("E1 tick_max=%d > 기준=%g" % (tick_max, E1_MAX))
    if e2 is None:
        print("E2 value=NA 기준=%d UNKNOWN 미상=%d" % (E2_MAX, unknown))
        fails.append("E2 판정 불가 usage 없는 요청 %d건" % unknown)
    else:
        ok = e2 <= E2_MAX and unknown == 0
        print("E2 value=%d 기준=%d %s 미상=%d" % (e2, E2_MAX, "PASS" if ok else "FAIL", unknown))
        if e2 > E2_MAX:
            fails.append("E2 value=%d > 기준=%d" % (e2, E2_MAX))
        if unknown:
            fails.append("E2 판정 불가 usage 없는 요청 %d건" % unknown)
    if e3 is None:
        print("E3 value=NA 기준=%g UNKNOWN ticks=0" % E3_MAX)
        fails.append("E3 판정 불가 틱턴 0")
    else:
        ok = e3 <= E3_MAX
        shown = ",".join(str(x) for x in tick_tools[:10]) + ("…" if len(tick_tools) > 10 else "")
        print("E3 value=%.2f 기준=%g %s ticks=%d tick_tools=%s"
              % (e3, E3_MAX, "PASS" if ok else "FAIL", len(tick), shown))
        if not ok:
            fails.append("E3 value=%.2f > 기준=%g" % (e3, E3_MAX))
    print("BREAK count=%d write=%d" % (nbreak, write))
    print("CACHE 새입력5m=%d 1h=%d 출력=%d 도구=%d" % (e5, e1h, out_tok, tools))
    for f in fails:
        print("FAIL %s" % f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
