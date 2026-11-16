"""r2072 ft2 keeper — 10분 넘게 이어진 줄(판정 불가 · HELD… · NEXT-HOLD · FILL-WAIT)을 바퀴 끝에 막힘 장부(block.sh)에 올린다.

after(k, body) = keeper.run_once 의 바퀴 본문을 감싼다(잠금 안 · 잠금에 걸린 바퀴와 --report 는 여기를 안 지남).
  · 장부 도구 = env FT_BLOCK_BIN › <root>/.fable-team/state/ft20-r1483-watch/block.sh · 없음·FT_CRITICAL_OFF=1 = 모든 동작 0
  · 바퀴 동안 k.log 가 받은 (종류, 팀, 글)을 곁에 적는다(로그 줄·순서 그대로) · 바퀴 끝에 기억(blockseen.json)·전문(blocks-latest.txt)·raise
  · keeper.call 을 거치지 않음(호출 셈·SLOW-CALL·ALL_STOP 밖) · 상한 7초 · 출력 버림 · 예외 0(A5 keeper 판정·로그·rc 불변)
"""
import json
import os
import re
import signal
import subprocess
import tempfile

LIMIT_S, MAX_CALLS, CAUSE_N = 7, 20, 160
LONG_S = 600   # A2 오래 이어진 줄 = 마지막 − 처음 ≥ 10분
ALIVE_S, SEAT_ALIVE_S, PERIOD = 300, 1260, 150   # A2 산 줄 = 300초(HELD-SEAT = 닫기 재시도 600 × 2 + 바퀴 60)
KINDS = ("판정 불가", "NEXT-HOLD", "FILL-WAIT")
FULL = ".fable-team/state/ft2-keeper/blocks-latest.txt"


class Ledger:
    """A1 올리는 한 길 — 한 바퀴 1개(상한을 한 번 넘기면 남은 호출 0 · 20회 안)."""

    def __init__(self, root, env):
        self.root, self.env, self.stopped, self.n = root, dict(env), False, 0
        tool = self.env.get("FT_BLOCK_BIN") or os.path.join(root, ".fable-team", "state", "ft20-r1483-watch", "block.sh")
        self.tool = tool if self.env.get("FT_CRITICAL_OFF") != "1" and os.path.isfile(tool) else None

    def raise_(self, *args):
        try:
            if not self.tool or self.stopped or self.n >= MAX_CALLS:
                return
            self.n += 1
            a = [str(x) for x in args]
            for i in range(len(a) - 1):
                if a[i] == "--cause":
                    a[i + 1] = (a[i + 1].splitlines() or [""])[0][:CAUSE_N]
            p = subprocess.Popen(["bash", self.tool, "raise"] + a, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 env=dict(self.env, FT20_SCAN_ROOT=self.root), start_new_session=True)
            try:
                p.wait(timeout=LIMIT_S)
            except subprocess.TimeoutExpired:
                self.stopped = True
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
                try:
                    p.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
        except Exception:   # 장부는 곁가지 — keeper 판정·출력·rc 를 바꾸지 않는다(A5)
            return


def watched(kind):
    """A2 대상 종류."""
    return kind.startswith("HELD") or kind in KINDS


def same(kind, team, text):
    """A2 같은 줄 열쇠 = (종류 · 팀 칸 · 숫자 덩어리 → N)."""
    return json.dumps([kind, team, re.sub(r"\d+", "N", text)], ensure_ascii=False)


def write(path, body):
    """일반 파일 · 임시 파일 → 바꿔치기."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(body)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {key: row for key, row in data.items() if isinstance(row, dict) and {"first", "last", "text"} <= set(row)}
    except (OSError, ValueError, AttributeError):
        return {}   # 깨진 기억 = 빈 기억


def remember(seen, rows, now):
    """A2 — 죽은 줄을 먼저 지우고(마지막 시각 기준) 이 바퀴 줄로 마지막 시각을 갱신(처음 시각 유지)."""
    for key in list(seen):
        if now - seen[key]["last"] > (SEAT_ALIVE_S if json.loads(key)[0] == "HELD-SEAT" else ALIVE_S):
            del seen[key]
    for kind, team, text in rows:
        if watched(kind):
            row = seen.setdefault(same(kind, team, text), {"first": now})
            row.update(last=now, text=text)
    return seen


def fills(k):
    """A3 — 바퀴 끝 state.fill_wait 에 남은 팀 = FILL-WAIT 줄이 이 바퀴에 찍힌 것으로 센다(로그 줄 0)."""
    wait = k.state.get("fill_wait") or {}
    cap = getattr(k.fa, "INTAKE_CAP", 8)
    return [("FILL-WAIT", team, "남은 일 %s/%s — fill 0 · 다음 바퀴" % (n, cap)) for team, n in sorted(wait.items())] if isinstance(wait, dict) else []


def settle(k, ledger, rows):
    """A2·A4 — 기억 갱신 → 오래 이어진 줄 → 전문 파일 → (팀 칸 · 종류) 묶음마다 raise 1회(처음 시각이 이른 순 20)."""
    now = int(k.now())
    os.makedirs(k.dir, exist_ok=True)
    path = os.path.join(k.dir, "blockseen.json")
    seen = remember(load(path), rows + fills(k), now)
    write(path, json.dumps(seen, ensure_ascii=False, sort_keys=True))
    long = sorted(((row["first"], key, row) for key, row in seen.items() if row["last"] - row["first"] >= LONG_S), key=lambda x: (x[0], x[1]))
    lines = []
    groups = {}
    for first, key, row in long:
        kind, team, _ = json.loads(key)
        label = team or "keeper"
        lines.append("%d분째\t%s\t%s\t%s\n" % ((now - first) // 60, kind, label, " ".join(row["text"].split())))
        groups.setdefault((label, kind), []).append(row)
    write(os.path.join(k.dir, "blocks-latest.txt"), "".join(lines))
    for (label, kind), got in groups.items():   # long 이 처음 시각 순 = 묶음도 처음 시각 순
        ledger.raise_("ft2-keeper:" + kind.replace(" ", "-"), "team", label,
                      "--cause", "%s %d줄 10분 넘게 · %s" % (kind, len(got), got[0]["text"]),
                      "--fix", "판정 필요 %s keeper %s — 전문 %s" % (label, kind, FULL), "--period", str(PERIOD))


def after(k, body):
    """keeper 바퀴 본문 1회 + 끝에 올림 · 장부 없음 = 본문만."""
    ledger = Ledger(k.root, k.env)
    if not ledger.tool:
        return body()
    rows, real = [], k.log
    def tap(kind, team="", text=""):
        out = real(kind, team, text)
        rows.append((kind, team or "", text or ""))
        return out
    k.log = tap
    try:
        out = body()
    finally:
        del k.log
    try:
        settle(k, ledger, rows)
    except Exception:   # A5 — 기억·전문·장부 실패는 바퀴 결과를 바꾸지 않는다
        pass
    return out
