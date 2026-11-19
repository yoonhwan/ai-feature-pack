#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_budget.py — r2175 notify 실행 예산 · 단계 표식 · stall-scan «멎은 곳».
N1 지난 초 = 실행 시작(이 모듈을 읽은 때 · Ctx·due 포함)부터 단조 시계 · 예산 B = env FT_LAND_RECORD_BUDGET_S(기본 12 · 숫자 아님·0 이하 = 12).
  줄의 첫 외부 호출(발신 · drift) 직전에 지난 초 ≥ B 면 그 줄을 미룬다(쪽지·보낸 기록·drift·ring 0) · 끝에 «미룸 <n>줄 …» 1줄 · rc 불변.
N4 env FT_LAND_RECORD_CLOCK=<파일> 이면 지난 초 = 그 파일의 숫자(없거나 못 읽으면 0).
N5 표식 = <루트>/.fable-team/state/land-record-notify-step.txt 1줄(임시→mv · 일반 파일) «<epoch> <단계> <대상|-> 경과=<초> 보냄=<n> 남음=<n>» · 못 쓰면 출력 0.
N6 stop_trace(루트, 시작 epoch) = 표식 epoch ≥ 시작이면 epoch 를 뺀 120자 · 아니면 «표식 없음» (둘 다 epoch() 꼴 = 소수 6자리).
r2316 R3 — 표식 칸에 «단계=d1:<초>,f:<초>,d2:<초>»(지난 단계 누적 · due-1·fetch·due-2 끝 시각) + «느린=<이름>:<초>,…»(이 실행 호출 중 초 큰 3개 · 누적) — 기존 칸(경과·보냄·남음) 뒤 · stop_trace 120자 안에 «단계=» 칸 전부와 «느린=» 첫 칸."""
from __future__ import annotations

import os
import time
from pathlib import Path

from ft_nano_record import run
from ft_nano_record_call import CALLS, clock, slow
from ft_nano_record_wake import doorbell

T0 = time.monotonic()
STEP = Path(".fable-team") / "state" / "land-record-notify-step.txt"
NOTIFY_KINDS = ("차례", "주인없음", "카드없음", "밀림")
STAGES = (("due-1", "d1"), ("fetch", "f"), ("due-2", "d2"))   # r2316 R3 — 단계 이름 → 표식 칸 이름
AT_MARK = ("due-1", "due-2")   # r2316 R3 — 표식이 곧 단계 끝인 둘 · «fetch» 표식은 fetch 들어가기 직전(fetch_all 도 URL 마다 쓴다) = 끝 시각은 due_rows 가 stage() 로 센다


def epoch():   # 표식·stall-scan 이 함께 쓰는 시각 꼴(소수 6자리 · 정수초 절삭 0)
    return f"{time.time():.6f}"


def num(x):
    return f"{round(x, 3):g}"


def budget_s():
    try:
        b = float(os.environ.get("FT_LAND_RECORD_BUDGET_S") or "")
    except ValueError:
        return 12.0
    return b if b > 0 else 12.0


class Budget:
    def __init__(self, root):
        self.path, self.b, self.sent, self.left, self.deferred = Path(root) / STEP, budget_s(), 0, None, 0
        self.clock = os.environ.get("FT_LAND_RECORD_CLOCK")
        self.stages = {}   # r2316 R3 — 단계 이름 → 그 단계가 끝난 때의 지난 초
        self.mark("due")

    def elapsed(self):
        return clock() if self.clock else clock() - T0   # r2316 R3 — run() 과 같은 시계(FT_LAND_RECORD_CLOCK 주입 가능)

    def stage(self, name):   # r2316 R3 — 단계가 끝난 시각(표식 없이 셈만 · 다음 표식의 «단계=» 칸에 실린다)
        if name in dict(STAGES):
            self.stages[name] = self.elapsed()

    def over(self):   # N1 — 넘었으면 미룸 1 을 센다
        if self.elapsed() < self.b:
            return False
        self.deferred += 1
        return True

    def mark(self, step, target="-"):   # N5 · r2316 R3: 단계 칸·느린 호출 칸을 기존 칸 뒤에 붙인다(120자 안에 단계 칸 전부)
        if step in AT_MARK:
            self.stage(step)
        left = "-" if self.left is None else self.left
        cells = ",".join(f"{tag}:{num(self.stages[name])}" for name, tag in STAGES if name in self.stages) or "-"
        tmp = self.path.with_name(f"{self.path.name}.tmp-{os.getpid()}")
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp.write_text(f"{epoch()} {step} {target or '-'} 경과={num(self.elapsed())} 보냄={self.sent} 남음={left} "
                           f"단계={cells} 느린={slow()}\n", encoding="utf-8")
            os.replace(tmp, self.path)
        except OSError:
            pass

    def walk(self, out, row, fmt):   # notify 의 줄 돌기 → rc(미룸으로 안 바뀜 · N3)
        for i, r in enumerate(out):
            self.left = len(out) - i - 1
            if r["k"] in NOTIFY_KINDS:
                row(r)
            elif r["k"] == "판정불가":
                print(fmt(r))
        self.left = 0
        self.mark("끝")
        if self.deferred:
            print(f"미룸 {self.deferred}줄 — 실행 예산 {num(self.b)}초 · 다음 실행이 이어 보냄")
        return 3 if any(r["k"] == "판정불가" for r in out) else 0


def step(ctx, name):   # r2202 F2 — due 안 단계 표식(due-1 · fetch · due-2) · Budget 은 notify 안에서만 있다 = due 손 실행은 표식 0
    bud = getattr(ctx, "bud", None)
    if bud:
        bud.mark(name)


def stage(ctx, name):   # r2316 R3 — 단계가 끝난 시각(표식 없이 셈만) · «fetch» 표식은 fetch 들어가기 직전이라 끝나는 곳에서 한 번 더 센다
    bud = getattr(ctx, "bud", None)
    if bud:
        bud.stage(name)


def over(ctx):   # notify 밖(landed·done)에서 부르면 늘 False
    bud = getattr(ctx, "bud", None)
    return bool(bud and bud.over())


def close_over(ctx, r):   # 밀림 줄 — 같은 실행의 drift 캐시가 DRIFT 이고 [설치 먼저] 기록이 있거나 판정 불가면 이번에 외부 호출 0 = 예산 밖(N2)
    d = getattr(ctx, "_drift", None)
    if d is not None and d[0] != 0 and (d[0] != 1 or ctx.store()["install"].get(f"{r['stem']}|{r['q']}")):
        return False
    return over(ctx)


def traced(ctx, step, target, cmd):   # 표식 → run(7초) · send 성공 = 보냄 +1
    bud = getattr(ctx, "bud", None)
    if bud:
        bud.mark(step, target)
    rc, out, err = run(cmd, env=dict(os.environ))
    if bud and step == "send" and rc == 0:
        bud.sent += 1
    return rc, out, err


def ring_mark(ctx, r):   # wake 가 ring 을 부를 조건(차례 줄 · doorbell ≠ sent)과 같을 때 ring 직전 표식
    bud = getattr(ctx, "bud", None)
    if bud and r["k"] == "차례" and doorbell(getattr(ctx, "send_out", "")) != "sent":
        bud.mark("ring", r["seat"])


def stop_trace(root, start):   # N6
    try:
        ep, rest = (Path(root) / STEP).read_text(encoding="utf-8").strip().split(" ", 1)
        if float(ep) >= float(start):
            return rest[:120]
    except (OSError, ValueError, UnicodeDecodeError):
        pass
    return "표식 없음"
