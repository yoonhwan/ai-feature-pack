#!/usr/bin/env python3
"""ctx-share 시험 — 카드 usage-monitor-coord-weekly 의 반례 표(㊽ · ㊾ · ㊿)와 변이 M113~M125·M127·M128.

입력 = 전부 이 시험이 임시 폴더에 만든 pi 세션 jsonl · seat-resume json · 상수 파일 ·
계정 표본 · 주입 시각(--now). 실 HOME 읽기 0 · 실 세션 0 · 네트워크 0 · sleep 0.

실행: python3 feature-pack/ctx-burn/test/test_share.py [이름조각]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, os.pardir, "bin", "ctx-share")
LINT = os.path.join(HERE, os.pardir, os.pardir, "fable-team", "legacy", "1.x",
                    "harness", "bin", "ft-name-lint.sh")
NOW = datetime(2026, 11, 17, 13, 0, 0)

INV = {
    "FT_CAP_CLAUDE_5X": 5,
    "FT_CAP_CLAUDE_ULTRA": 5,
    "FT_CAP_WK_5X": 172,
    "FT_CAP_WK_ULTRA": 686,
    "FT_CAP_TARGET_UTIL": 0.85,
    "FT_CAP_WK_5X_LOW": 124,
    "FT_CAP_WK_ULTRA_LOW": 497,
}
INV_KEYS = ["FT_CAP_CLAUDE_5X", "FT_CAP_CLAUDE_ULTRA", "FT_CAP_WK_5X", "FT_CAP_WK_ULTRA",
            "FT_CAP_TARGET_UTIL", "FT_CAP_WK_5X_LOW", "FT_CAP_WK_ULTRA_LOW"]
CLAUDE = "claude-sonnet-4-5"
CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def ts(hours_before=0.0):
    return (NOW - timedelta(hours=hours_before)).strftime("%Y-%m-%dT%H:%M:%S")


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def wsum(pct, hours=48.0, inv=None):
    """원하는 주간 % 를 만드는 가중 합(가중 = input 1.0 이므로 input 토큰 수와 같다)."""
    inv = inv or INV
    denom = (float(inv["FT_CAP_CLAUDE_5X"]) * float(inv["FT_CAP_WK_5X"])
             + float(inv["FT_CAP_CLAUDE_ULTRA"]) * float(inv["FT_CAP_WK_ULTRA"])) \
        * float(inv["FT_CAP_TARGET_UTIL"]) * 1_000_000.0
    return float(pct) / 100.0 * denom * hours / 168.0


def used(inp=0.0, cr=0.0, cw=0.0, cw1=0.0, out=0.0, model=CLAUDE):
    u = {"input": inp, "cacheRead": cr, "cacheWrite": cw, "output": out}
    if cw1:
        u["cacheWrite1h"] = cw1
    return (model, u)


def has(text, needle):
    assert needle in text, "기대 없음: %r\n--- 실제 ---\n%s" % (needle, text)


def hasnt(text, needle):
    assert needle not in text, "기대 밖 존재: %r\n--- 실제 ---\n%s" % (needle, text)


class Fixture:
    def __init__(self, tool=TOOL, now=NOW):
        self.root = tempfile.mkdtemp(prefix="ctx-share-test-")
        self.tool = tool
        self.now = now
        self.sessions = os.path.join(self.root, "sessions")
        self.resume = os.path.join(self.root, "resume")
        self.out = os.path.join(self.root, "out")
        os.makedirs(self.sessions)
        os.makedirs(self.resume)
        self.inv = os.path.join(self.root, "inv.env")
        self.write_inv()
        self.acct = os.path.join(self.root, "acct.jsonl")
        self.write_acct(10.0)

    # ------------------------------------------------------------ 만들기
    def write_inv(self, **over):
        vals = dict(INV)
        vals.update(over)
        with open(self.inv, "w", encoding="utf-8") as fh:
            for k in INV_KEYS:
                if vals.get(k) is not None:
                    fh.write("%s=%s\n" % (k, vals[k]))

    def write_acct(self, spec, ts_text=None, path=None):
        """spec = w 값 또는 계정 dict 목록. ts_text 기본 = 재는 시각 1분 전."""
        path = path or self.acct
        if isinstance(spec, (int, float)):
            spec = [{"email": "a@example.com", "tier": "max_5x", "w": spec}]
        accounts = [dict(a) for a in spec]
        line = json.dumps({"ts": ts_text or (NOW - timedelta(minutes=1)).strftime(
            "%Y-%m-%dT%H:%M:%S"), "accounts": accounts})
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(line + "\n")
        return path

    def sess(self, folder, fname, name=None, rows=()):
        d = os.path.join(self.sessions, folder)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, fname)
        lines = []
        if name is not None:
            lines.append(json.dumps({"type": "session_info", "name": name}))
        for r in rows:
            if isinstance(r, str):
                lines.append(r)
                continue
            hours_before, (model, usage) = r
            lines.append(json.dumps({"type": "message", "timestamp": ts(hours_before),
                                     "message": {"model": model, "usage": usage}}))
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        return path

    def resume_record(self, path, name):
        rec = {"name": name, "jsonl": path}
        with open(os.path.join(self.resume, name.replace("#", "_") + ".json"), "w",
                  encoding="utf-8") as fh:
            json.dump(rec, fh)

    # ------------------------------------------------------------ 실행·읽기
    def run(self, *extra, rc=None, force=True, acct=True, inv=None, sessions=None, out=None):
        args = [sys.executable, self.tool,
                "--now", iso(self.now),
                "--sessions-dir", sessions or self.sessions,
                "--resume-dir", self.resume,
                "--inv-file", inv or self.inv,
                "--out", out or self.out]
        if acct is True:
            args += ["--acct-file", self.acct]
        elif acct:
            args += ["--acct-file", acct]
        if force:
            args += ["--force"]
        args += list(extra)
        p = subprocess.run(args, capture_output=True, text=True)
        if rc is not None:
            assert p.returncode == rc, "rc=%d (기대 %d)\nout=%s\nerr=%s" % (
                p.returncode, rc, p.stdout, p.stderr)
        return p

    def board(self):
        with open(os.path.join(self.out, "board.md"), encoding="utf-8") as fh:
            return fh.read()

    def raw(self, name):
        with open(os.path.join(self.out, name), "rb") as fh:
            return fh.read()

    def last(self):
        with open(os.path.join(self.out, "last.json"), encoding="utf-8") as fh:
            return json.load(fh)

    def js(self):
        p = self.run("--json")
        return json.loads(p.stdout)

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


# ---------------------------------------------------------------- ㊽ 반례
@case
def x88_ga(c):
    """㊽가 — 이름이 역할을 가른다: master 800 · nano 200."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=800))])
    c.sess("f1", "b.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=200))])
    c.run()
    b = c.board()
    has(b, "② 조율 80% · 구현 20%")
    has(b, "④ 못 가림 0%")


@case
def x88_na(c):
    """㊽나 — 폴더 글자(nano)보다 이름(arch)이 이긴다."""
    c.sess("proj-.worktrees-nano-run", "a.jsonl", "byz-harness-arch-pi#3",
           [(1, used(inp=100))])
    c.run()
    b = c.board()
    has(b, "② 조율 100% · 구현 0%")
    hasnt(b, "구현 100%")


@case
def x88_da(c):
    """㊽다 — session_info 없음 · seat-resume 의 jsonl → name 이 이름을 준다."""
    path = c.sess("f1", "a.jsonl", None, [(1, used(inp=100))])
    c.resume_record(path, "byz-harness-tester-pi#2")
    c.run()
    has(c.board(), "② 조율 0% · 구현 100%")


@case
def x88_ra(c):
    """㊽라 — 이름 없음 150 · 조율 425 · 구현 425 → 못 가림 15% 이면 판정 불가."""
    c.sess("f1", "a.jsonl", None, [(1, used(inp=150))])
    c.sess("f1", "b.jsonl", "byz-harness-master-pi#1", [(1, used(inp=425))])
    c.sess("f1", "d.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=425))])
    c.run(rc=1)
    b = c.board()
    has(b, "① 판정 불가 · 못 가림 15%")
    has(b, "② 조율 50% · 구현 50% (참고")
    has(b, "④ 못 가림 15%")
    has(b, "⑦ 판정 = 판정 불가")


@case
def x88_ma(c):
    """㊽마 — 표에 없는 역할 토큰 = 못 가림."""
    c.sess("f1", "a.jsonl", "byz-harness-wizard-pi#1", [(1, used(inp=100))])
    c.run(rc=1)
    has(c.board(), "④ 못 가림 100%")


@case
def x88_ba(c):
    """㊽바 — 한 폴더에 팀장·arch 두 파일 = 좌석 2개로 따로 센다."""
    c.sess("proj-.worktrees-aifp-ft-roles--", "a.jsonl", "byz-harness-master-pi#1",
           [(1, used(inp=100))])
    c.sess("proj-.worktrees-aifp-ft-roles--", "b.jsonl", "byz-harness-arch-pi#1",
           [(1, used(inp=100))])
    c.run()
    b = c.board()
    has(b, "② 조율 100% · 구현 0%")
    has(b, "⑥ 조율 상위 2:")


@case
def x88_sa(c):
    """㊽사 — 창 밖(49시간) 요청 제외 · 파일 mtime 이 아니라 줄 timestamp 로 가린다."""
    old = c.sess("f1", "old.jsonl", "byz-harness-nano-r1#0", [(49, used(inp=5000))])
    os.utime(old, None)                      # mtime 은 지금 — mtime 으로 가리면 섞인다
    c.sess("f1", "new.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.run("--hours", "48")
    b = c.board()
    has(b, "② 조율 100% · 구현 0%")
    assert c.last()["requests"] == 1, c.last()


@case
def x88_a(c):
    """㊽아 — claude 가 아닌 모델은 분자·비율에서 뺀다."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1",
           [(1, used(inp=100)), (1, used(inp=9_000_000, model="deepseek-v4.1"))])
    c.run()
    assert abs(c.last()["weighted"] - 100.0) < 0.5, c.last()
    has(c.board(), "② 조율 100% · 구현 0%")


@case
def x88_ja(c):
    """㊽자 — 48시간 1041.857M → 주간 100% · 낮은 앵커 138%."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=1041857000.0))])
    c.run()
    b = c.board()
    has(b, "로컬 W 환산 100% (낮은 앵커 138%)")


@case
def x88_cha(c):
    """㊽차 — 상수 하나가 비면 판정 불가 · 주간 % 없음 · 조율 % 는 낸다."""
    c.write_inv(FT_CAP_WK_ULTRA=None)
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.run(rc=1)
    b = c.board()
    has(b, "판정 불가 · 상수 FT_CAP_WK_ULTRA")
    has(b, "② 조율 100%")
    hasnt(b, "로컬 W 환산 100")


@case
def x88_ka(c):
    """㊽카 — 깨진 json 3줄은 건너뛰고 skipped 에 적는다 · 값은 나머지로."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [
        '{"usage": }',
        '{"type":"message","usage": ',
        '{"usage": 1,,}',
        json.dumps({"type": "tool", "content": "no usage here"}),
        (1, used(inp=100)),
    ])
    c.run()
    last = c.last()
    assert last["skipped"] == 3, last
    assert last["requests"] == 1, last
    has(c.board(), "② 조율 100% · 구현 0%")


@case
def x88_ta(c):
    """㊽타 — last.json 이 30분 안이면 재지 않는다(--force 없음 · 보드 그대로)."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.run()
    board, samples, last = c.raw("board.md"), c.raw("samples.tsv"), c.raw("last.json")
    c.sess("f1", "b.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=900))])
    p = c.run(force=False, rc=0)
    has(p.stdout, "재지 않음")
    assert c.raw("board.md") == board, "보드가 바뀜"
    assert c.raw("samples.tsv") == samples, "samples 가 늘어남"
    assert c.raw("last.json") == last, "last.json 이 바뀜"


@case
def x88_pa(c):
    """㊽파 — 세션 폴더가 없으면 앞 보드를 지우지 않는다(rc 1 · 바이트 그대로)."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.run()
    board = c.raw("board.md")
    p = c.run(sessions=os.path.join(c.root, "nope"), rc=1)
    has(p.stdout, "판정 불가 · 세션 폴더")
    assert c.raw("board.md") == board, "보드를 덮었다"


@case
def x88_ha(c):
    """㊽하 — 가중 식: input 10 + cacheWrite 100(1h 40) + cacheRead 1000 + output 20 = 365."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1",
           [(1, used(inp=10, cw=100, cw1=40, cr=1000, out=20))])
    js = c.js()
    assert abs(js["weighted"] - 365.0) < 0.01, js


# ---------------------------------------------------------------- ㊾ 정의 2 검산
@case
def x99_ga(c):
    """㊾가 — 기준 사본 h48.json 의 claude pool 합 1561.59M → 주간 150%."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=1561590000.0))])
    c.run()
    has(c.board(), "로컬 W 환산 150%")


@case
def x99_na(c):
    """㊾나 — 역할 칸은 셋째 토큰: byz-planner-nano-da-fix#0 = 구현."""
    c.sess("f1", "a.jsonl", "byz-planner-nano-da-fix#0", [(1, used(inp=100))])
    c.run()
    has(c.board(), "② 조율 0% · 구현 100%")


# ---------------------------------------------------------------- ㊿ 계정 실측·판정
@case
def x50_ga(c):
    """㊿가 — 표본은 뒤에서 처음 읽히는 줄 · 한도 가중 평균 = 75.0%."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    acct = os.path.join(c.root, "acct3.jsonl")
    def mins(n):
        return (NOW - timedelta(minutes=n)).strftime("%Y-%m-%dT%H:%M:%S")
    lines = [
        json.dumps({"ts": mins(20), "accounts": [
            {"email": "a@x", "tier": "max_5x", "w": 10.0},
            {"email": "b@x", "tier": "max_20x", "w": 10.0}]}),
        json.dumps({"ts": mins(10), "accounts": [
            {"email": "a@x", "tier": "max_5x", "w": 50.0},
            {"email": "b@x", "tier": "max_5x", "w": 0.0},
            {"email": "c@x", "tier": "max_20x", "w": 100.0}]}),
        '{"ts": "%s", "accounts": [{"email": "d@x",' % mins(0),
    ]
    with open(acct, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    c.run(acct=acct)
    has(c.board(), "계정 실측 75%")


@case
def x50_na(c):
    """㊿나 — 표본이 31분 낡으면 판정 불가 · 조율 % 와 로컬 환산은 낸다."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.write_acct(10.0, ts_text=(NOW - timedelta(minutes=31)).strftime("%Y-%m-%dT%H:%M:%S"))
    c.run(rc=1)
    b = c.board()
    has(b, "계정 표본 낡음 31분")
    has(b, "② 조율 100%")
    has(b, "로컬 W 환산 ")
    has(b, "⑦ 판정 = 판정 불가 · 계정 표본 낡음 31분")


@case
def x50_da(c):
    """㊿다 — w 가 null 인 계정은 0 으로 세지 않고 판정 불가."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.write_acct([{"email": "yoonhwan.ko@x", "tier": "max_5x", "w": None},
                  {"email": "b@x", "tier": "max_20x", "w": 10.0}])
    c.run(rc=1)
    has(c.board(), "계정 표본 빈 값 yoo")


@case
def x50_ra(c):
    """㊿라 — 차 표지: +25%p 는 «다른 머신» · 19%p 는 표지 없음 · −25%p 는 «자 차»."""
    total = wsum(60)
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=total * 0.6))])
    c.sess("f1", "b.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=total * 0.4))])
    for w, want in ((85.0, "다른 머신·밖 경로 의심 +25%p"), (79.0, ""), (35.0, "로컬이 더 큼 −25%p · 자 차")):
        acct = c.write_acct(w, path=os.path.join(c.root, "acct_%s.jsonl" % int(w)))
        c.run(acct=acct)
        b = c.board()
        has(b, "로컬 W 환산 60%")
        if want:
            has(b, want)
        if w == 85.0:
            hasnt(b, "자 차")
        if w == 79.0:
            hasnt(b, "의심")
            hasnt(b, "자 차")
        if w == 35.0:
            hasnt(b, "다른 머신")


@case
def x50_ma(c):
    """㊿마 — 조율 40% · 로컬 90% 이어도 계정 실측 105% 면 목표 밖."""
    total = wsum(90)
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=total * 0.4))])
    c.sess("f1", "b.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=total * 0.6))])
    c.write_acct(105.0)
    c.run()
    b = c.board()
    has(b, "로컬 W 환산 90%")
    has(b, "계정 실측 105%")
    has(b, "⑦ 판정 = 목표 밖")
    hasnt(b, "목표 안")


@case
def x50_ba(c):
    """㊿바 — 계정 표본 파일이 없어도 나머지 줄은 쓰고 rc 1."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.run(acct=os.path.join(c.root, "no-such.jsonl"), rc=1)
    b = c.board()
    has(b, "계정 표본 없음")
    has(b, "② 조율 100%")
    has(b, "④ 못 가림 0%")
    has(b, "⑦ 판정 = 판정 불가 · 계정 표본 없음")


@case
def x50_sa(c):
    """㊿사 — 표에 없는 tier 는 판정 불가(0 으로 세지 않는다)."""
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    c.write_acct([{"email": "a@x", "tier": "max_1x", "w": 10.0}])
    c.run(rc=1)
    has(c.board(), "계정 tier max_1x")


@case
def x50_ja(c):
    """㊿자 — 팀 칸이 qa 여도 역할 칸(master)이 이긴다: 조율 80% · ⑦ 목표 밖."""
    total = wsum(90)
    c.sess("f1", "a.jsonl", "byz-qa-master-0-pi#1", [(1, used(inp=total * 0.8))])
    c.sess("f1", "b.jsonl", "byz-harness-nano-r1#0", [(1, used(inp=total * 0.2))])
    c.write_acct(50.0)
    c.run()
    b = c.board()
    has(b, "② 조율 80% · 구현 20%")
    has(b, "④ 못 가림 0%")
    has(b, "⑦ 판정 = 목표 밖")
    hasnt(b, "목표 안")


@case
def x50_cha(c):
    """㊿차 — 예약어 12개 + 팀 칸 함정 2개: 갈래 1개로 풀리고 못 가림 0."""
    roles = subprocess.run(["bash", LINT, "--roles"], capture_output=True,
                           text=True, check=True).stdout.split()
    assert len(roles) == 12, roles
    rows = 1
    for i, role in enumerate(roles):
        name = "byz-harness-nano-r1#0" if role == "nano" else "byz-harness-%s-0-pi#1" % role
        c.sess("f1", "r%02d.jsonl" % i, name, [(rows, used(inp=1.0))])
    c.sess("f1", "hit1.jsonl", "byz-master-qa-web-pi#2", [(rows, used(inp=1.0))])
    c.sess("f1", "hit2.jsonl", "byz-arch-nano-master-fix#0", [(rows, used(inp=1.0))])
    c.run()
    b = c.board()
    has(b, "④ 못 가림 0%")
    has(b, "② 조율 50% · 구현 50%")


@case
def x50_ka(c):
    """㊿카 — 문법 밖 이름 3개는 역할 낱말이 있어도 못 가림."""
    c.sess("f1", "a.jsonl", "master-pi#1", [(1, used(inp=10))])
    c.sess("f1", "b.jsonl", "byz-qa-master-0-pi", [(1, used(inp=10))])
    c.sess("f1", "d.jsonl", "byz--master-pi#1", [(1, used(inp=10))])
    c.run(rc=1)
    b = c.board()
    has(b, "④ 못 가림 100%")
    has(b, "⑦ 판정 = 판정 불가")


# ---------------------------------------------------------------- DA HOLD-IMPL 1/3 반례 (R2~R4)
@case
def xhold_r2_resume_exact(c):
    """R2 — seat-resume jsonl 은 «그 파일» exact match: a.jsonl-backup 은 이름을 못 받는다."""
    a = c.sess("f1", "a.jsonl", None, [(1, used(inp=100))])
    c.sess("f1", "a.jsonl-backup.jsonl", None, [(1, used(inp=900))])
    c.resume_record(a, "byz-harness-nano-r1#0")
    c.run(rc=1)
    b = c.board()
    has(b, "① 판정 불가 · 못 가림 90%")
    has(b, "② 조율 0% · 구현 100% (참고 · 목표 ≤ 50%)")
    has(b, "④ 못 가림 90%")


@case
def xhold_r3_broken_json_no_keyword(c):
    """R3 — usage·session_info 글자가 없는 깨진 JSON 줄도 skipped 에 센다."""
    path = c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=100))])
    with open(path, "a", encoding="utf-8") as fh:
        fh.write('{\n{"type":\n{"type":"message","timestamp":\n')
    c.run()
    last = c.last()
    assert last["skipped"] == 3, last
    assert last["requests"] == 1, last
    has(c.board(), "② 조율 100%")


@case
def xhold_r4_missing_const_json(c):
    """R4 — 상수 누락이면 --json 의 주간 환산 칸은 null(기본값으로 낸 값 노출 0)."""
    c.write_inv(FT_CAP_WK_ULTRA=None)
    c.sess("f1", "a.jsonl", "byz-harness-master-pi#1", [(1, used(inp=wsum(80)))])
    p = c.run("--json", rc=1)
    js = json.loads(p.stdout)
    assert js["weekly_pct"] is None, js
    assert js["weekly_low_pct"] is None, js
    has(js["verdict"], "판정 불가 · 상수 FT_CAP_WK_ULTRA")


# ---------------------------------------------------------------- 변이 (지정 반례가 FAIL 해야 한다)
MUTATIONS = [
    ("M113", "x88_na",
     'def class_of_session(name, folder):\n    """정의 1 — 이름이 이긴다. 폴더 글자는 읽지 않는다(기준값 사)."""\n    return class_of(name)',
     'def class_of_session(name, folder):\n    """정의 1 — 이름이 이긴다. 폴더 글자는 읽지 않는다(기준값 사)."""\n    if any(k in folder for k in ("nano", "tester", "qa", "scratch", "@a1")):\n        return "work"\n    return class_of(name)'),
    ("M114", "x88_ra", '    return "unknown"\n', '    return "coord"\n'),
    ("M115", "x88_sa", '                    t = parse_ts(d.get("timestamp"))',
     '                    t = os.path.getmtime(path)'),
    ("M116", "x88_ja", ' * inv["FT_CAP_TARGET_UTIL"]', ''),
    ("M117", "x88_cha", '    missing = [k for k in INV_KEYS if not raw.get(k)]',
     '    missing = []'),
    ("M118", "x88_pa", '        print("판정 불가 · 세션 폴더")\n        return 1',
     '        pass'),
    ("M119", "x99_na", '    return toks[2]\n',
     '    for tok in reversed(toks):\n        if tok in IMPL_ROLES or tok in COORD_ROLES:\n            return tok\n    return toks[2]\n'),
    ("M120", "x50_ga", '    for line in reversed(lines):', '    for line in lines:'),
    ("M121", "x50_ga", '            den += limit', '            den += 1.0'),
    ("M122", "x50_da", '            if w is None:\n                return None, ts_text, "계정 표본 빈 값 %s" % (email[:3] or "?")',
     '            if w is None:\n                w = 0.0'),
    ("M123", "x50_na", '        if age_min > STALE_MIN:\n            return None, ts_text, "계정 표본 낡음 %d분" % int(round(age_min))',
     '        if False:\n            return None, ts_text, ""'),
    ("M124", "x50_ma", '            and acct_pct is not None and acct_pct <= 100.0:',
     '            and True:'),
    ("M125", "x50_ra", '    if diff <= -DIFF_FLAG:\n        return "로컬이 더 큼 %s%%p · 자 차" % signed(diff)',
     '    if abs(diff) >= DIFF_FLAG:\n        return "다른 머신·밖 경로 의심 +%s%%p" % p1(abs(diff))'),
    ("M127", "x50_ja", '    return toks[2]\n',
     '    for tok in toks:\n        if tok in IMPL_ROLES or tok in COORD_ROLES:\n            return tok\n    return toks[2]\n'),
    ("M128", "x50_ka", '    toks = head.split("-")\n    if len(toks) < 3 or any(t == "" for t in toks):\n        return None',
     '    toks = [t for t in head.split("-") if t]\n    if len(toks) < 3:\n        for tok in toks:\n            if tok in IMPL_ROLES or tok in COORD_ROLES:\n                return tok\n        return None'),
]


def find_case(name):
    for fn in CASES:
        if fn.__name__ == name:
            return fn
    raise KeyError(name)


def run_case(fn, tool=TOOL):
    c = Fixture(tool=tool)
    try:
        fn(c)
    finally:
        c.cleanup()


def mutate(mid, old, new, root):
    with open(TOOL, encoding="utf-8") as fh:
        src = fh.read()
    if src.count(old) != 1:
        raise AssertionError("%s: 바꿀 자리 %d개(1개여야 한다)" % (mid, src.count(old)))
    path = os.path.join(root, "mutant_%s.py" % mid)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src.replace(old, new))
    return path


def main(argv):
    pat = argv[1] if len(argv) > 1 else ""
    failed, ran = 0, 0
    t0 = time.time()
    for fn in CASES:
        if pat and pat not in fn.__name__:
            continue
        ran += 1
        s = time.time()
        try:
            run_case(fn)
            print("PASS %-10s %5.2fs  %s" % (fn.__name__, time.time() - s,
                                             (fn.__doc__ or "").split("—")[0].strip()))
        except AssertionError as e:
            failed += 1
            print("FAIL %-10s        %s" % (fn.__name__, e))
        except Exception:
            failed += 1
            print("FAIL %-10s        (예외)\n%s" % (fn.__name__, traceback.format_exc()))
    for mid, case_name, old, new in MUTATIONS:
        if pat and pat not in mid and pat.lower() not in mid.lower():
            continue
        ran += 1
        s = time.time()
        root = tempfile.mkdtemp(prefix="ctx-share-mut-")
        try:
            tool = mutate(mid, old, new, root)
            try:
                run_case(find_case(case_name), tool=tool)
            except AssertionError as e:
                print("PASS %-10s %5.2fs  변이 → %s FAIL (%s)" % (
                    mid, time.time() - s, case_name, str(e).splitlines()[0][:60]))
            else:
                failed += 1
                print("FAIL %-10s        변이인데 %s 가 통과함" % (mid, case_name))
        except (AssertionError, OSError) as e:
            failed += 1
            print("FAIL %-10s        %s" % (mid, e))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    print("\n%d 사례 · 실패 %d · %.1f초" % (ran, failed, time.time() - t0))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
