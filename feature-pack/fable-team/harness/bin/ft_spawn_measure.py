#!/usr/bin/env python3
# ft_spawn_measure.py — r1563 기계 스폰 모니터(읽기 전용 · 세션 jsonl 만 · 쓰기 0 · 네트워크 0).
#   usage: ft_spawn_measure.py [--hours N]        rc 0 = 측정 완료 · 2 = 입력 오류
#   계층 판정 = «요청 수» 하나(req<=3 = 기계 스폰 · req>3 = 작업세션) — 디렉터리 이름(*inbox-haiku*)은 표의 라벨일
#     뿐 판정에 안 쓴다(카드 ⓑ). 이 2계층은 claude 파일에만 — pi 는 좌석이라 요청 수와 무관하게 «작업세션 층»(카드 ⓖ).
#     haiku 파일(요청 전부 haiku 모델)은 «작업세션» 에서만 빼고 «haiku» 칸에 따로 세되 기계 스폰 계층엔 그대로 센다.
#   가중식 = input×1 + cache_creation×1.25 + cache_read×0.1 + output×5 (정본 #276 · claude·pi 같은 상수).
#   조용한 0 금지(no_silent_fallback): 깨진 json 행은 «건너뛴줄=N» · 요청 0 파일은 «빈파일=N» · 창 밖 파일은 «창밖=N».
#   claude 는 message.id 로 접는다(응답이 블록마다 행으로 갈라진다) · ft_waste_measure.py 의 load() 는 import 하지 않는다(요청별 model 부재).
import json
import os
import sys
import time

SPAWN_MAX_REQ = 3      # 경계(카드 ⓐ): req <= 3 = 기계 스폰 · req > 3 = 작업세션
HAIKU = "haiku"
W_INPUT, W_CREATE, W_READ, W_OUTPUT = 1.0, 1.25, 0.1, 5.0
TOP_ROWS = 15
ZERO = dict(session=0, spawn=0, haiku=0, req=0, w=0.0, empty=0, skip=0, out=0)
def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def roots():
    h = home()
    return [("claude", os.path.join(h, ".claude", "projects")), ("pi", os.path.join(h, ".pi", "agent", "sessions"))]


def num(v):
    try:
        return float(v or 0)
    except (TypeError, ValueError):
        return 0.0


def usage_of(fmt, msg):
    """행의 usage → (input, creation, read, output). usage 가 없으면 None(0 으로 치환하지 않는다)."""
    u = msg.get("usage")
    if not isinstance(u, dict) or not u:
        return None
    if fmt == "pi":
        return (num(u.get("input")), num(u.get("cacheWrite")), num(u.get("cacheRead")), num(u.get("output")))
    return (num(u.get("input_tokens")), num(u.get("cache_creation_input_tokens")),
            num(u.get("cache_read_input_tokens")), num(u.get("output_tokens")))


def scan_file(fmt, path):
    """jsonl 1개 → (요청 수, 가중, model 목록, 건너뛴 줄). usage 합 0 행은 요청이 아니다(카드 ⓔ)."""
    req, weight, models, skipped, seen = 0, 0.0, [], 0, set()
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return 0, 0.0, [], 1
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                row = None
            if not isinstance(row, dict):
                skipped += 1          # 깨진 json — 조용히 넘기지 않는다
                continue
            msg = row.get("message") if isinstance(row.get("message"), dict) else {}
            if fmt == "pi":
                if row.get("type") != "message" or msg.get("role") != "assistant":
                    continue
            elif row.get("type") != "assistant":
                continue
            key = msg.get("id") or msg.get("responseId")
            if key:
                if key in seen:
                    continue          # 같은 응답의 갈라진 행
                seen.add(key)
            parts = usage_of(fmt, msg)
            if parts is None or sum(parts) == 0:
                continue              # usage 0 = 요청 아님
            req += 1
            weight += parts[0] * W_INPUT + parts[1] * W_CREATE + parts[2] * W_READ + parts[3] * W_OUTPUT
            models.append(str(msg.get("model") or ""))
    return req, weight, models, skipped


def is_haiku(models):
    return bool(models) and all(HAIKU in (m or "").lower() for m in models)


def iter_files(root):
    for label in (sorted(os.listdir(root)) if os.path.isdir(root) else []):
        sub = os.path.join(root, label)
        if os.path.isdir(sub):
            yield from [(label, os.path.join(sub, n)) for n in sorted(os.listdir(sub)) if n.endswith(".jsonl")]


def measure(hours):
    """→ (원천별 행 dict, 계층별 합계 dict)."""
    now = time.time()
    rows, totals = {}, {}
    for fmt, root in roots():
        t = totals.setdefault(fmt, dict(ZERO))
        for label, path in iter_files(root):
            try:
                age_h = (now - os.path.getmtime(path)) / 3600.0
            except OSError:
                t["skip"] += 1
                continue
            if age_h > hours:   # 창 --hours: mtime 이 창 밖이면 제외(카드 ⓓ)
                t["out"] += 1
                continue
            req, w, models, skipped = scan_file(fmt, path)
            t["skip"] += skipped
            if req == 0:
                t["empty"] += 1
                continue
            layer = "session" if fmt == "pi" else ("spawn" if req <= SPAWN_MAX_REQ else "session")  # pi = 좌석
            a = rows.setdefault(fmt + "/" + label, dict(session=0, spawn=0, haiku=0, req=0, w=0.0))
            for d in (a, t):
                d["req"] += req
                d["w"] += w
            if is_haiku(models):
                a["haiku"] += 1
                t["haiku"] += 1
                layer = None if layer == "session" else layer   # haiku 는 «작업세션 지표» 에서만 뺀다
            if layer:
                a[layer] += 1
                t[layer] += 1
    return rows, totals


def layer_line(name, t):
    return ("%-6s 작업세션=%d 기계스폰=%d haiku=%d req=%d 가중=%.1fM 빈파일=%d 창밖=%d 건너뛴줄=%d"
            % (name, t["session"], t["spawn"], t["haiku"], t["req"], t["w"] / 1e6, t["empty"], t["out"], t["skip"]))


def parse_hours(argv):
    if not argv:
        return 24.0
    if len(argv) != 2 or argv[0] != "--hours":
        return None
    try:
        hours = float(argv[1])
    except ValueError:
        return None
    return hours if hours >= 0 else None


def main(argv):
    hours = parse_hours(argv)
    if hours is None:
        sys.stderr.write("usage: ft_spawn_measure.py [--hours N]\n")
        return 2

    rows, totals = measure(hours)
    cl, pi = totals.get("claude", ZERO), totals.get("pi", ZERO)
    print("SPAWN r1563 hours=%g home=%s" % (hours, home()))
    print(layer_line("CLAUDE", cl))
    print(layer_line("PI", pi))
    print("합계 작업세션=%d (claude %d + pi %d) 기계스폰=%d haiku=%d req=%d 가중=%.1fM 빈파일=%d 창밖=%d 건너뛴줄=%d"
          % (cl["session"] + pi["session"], cl["session"], pi["session"], cl["spawn"] + pi["spawn"],
             cl["haiku"] + pi["haiku"], cl["req"] + pi["req"], (cl["w"] + pi["w"]) / 1e6,
             cl["empty"] + pi["empty"], cl["out"] + pi["out"], cl["skip"] + pi["skip"]))
    print("가중식 input×1 + cache_creation×1.25 + cache_read×0.1 + output×5 (claude·pi 같은 상수)")
    print("%-52s %4s %4s %5s %6s %6s" % ("원천(cwd)", "작업", "스폰", "haiku", "req", "M"))
    ordered = sorted(rows.items(), key=lambda kv: (-kv[1]["w"], kv[0]))
    for name, a in ordered[:TOP_ROWS]:
        print("%-52s %4d %4d %5d %6d %6.1f" % (name[-52:], a["session"], a["spawn"], a["haiku"], a["req"], a["w"] / 1e6))
    if len(ordered) > TOP_ROWS:
        print("… 외 %d 원천 (합계에 포함)" % (len(ordered) - TOP_ROWS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
