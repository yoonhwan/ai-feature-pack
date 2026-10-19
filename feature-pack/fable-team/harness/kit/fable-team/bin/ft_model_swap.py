#!/usr/bin/env python3
"""ft_model_swap.py — 역할 좌석이 모델 한도로 멈추면 같은 역할 후계를 대체 모델로 연다 (r497).

대상 = seats*.json 전부의 역할 칸(`_master`·`_arch`·`_desk`·`_da`… · `_hil_route` 제외) 현역 행 ∧ agent=claude ∧ tmux 생존 · 판정 = R146 analyze.
줄 = WAIT(정지 < 3분 · 해제 예상 ±3분) · RECOVERED(같은 바탕 모델 정상) · NOOP(이미 교대 · 계보 30분) · SKIP · PLAN swap · HIL(같은 uuid 1통).
교대 = ft-successor-open.sh 분리 실행(1회 1건 · 본문 첫 3줄 = 계보 도달 파일 seq 의 골 3줄) · 옛 좌석 kill 0 · 원래 모델 복귀 0 · 끄기 FT_MODEL_SWAP=0.
"""
import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # 형제 모듈 — python -I 에서도 찾는다
from ft_api_outage import Cut, analyze, back  # noqa: E402
from ft_api_outage_util import base_model, fallback_table, goal_source, hhmm, locked, next_name, read_table, records, seat_jsonl  # noqa: E402

SENDER = "ft-model-swap"
ROUTE_KEYS = {"_hil_route"}
HOLD, WINDOW, NEAR = 30 * 60, 10 * 60, 3 * 60
Row = dict[str, object]


class Swap:
    def __init__(self, a: argparse.Namespace):
        self.a, self.now = a, a.now
        self.ft = Path(a.root) / ".fable-team"
        self.sd = self.ft / "state" / "model-swap"
        self.table = fallback_table(Path(a.table))
        self.st = self.load()
        self.tables = [t for f in sorted(self.ft.glob("seats*.json")) if (t := read_table(f)) is not None]
        r = subprocess.run([os.environ.get("FT_TMUX", "tmux"), "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
        self.alive = set(r.stdout.split()) if r.returncode == 0 else set()
        self.cache: dict[str, tuple[str, Cut | None, list[tuple[int, str]]]] = {}

    def load(self) -> dict[str, object]:
        try:
            return json.loads((self.sd / "state.json").read_text(encoding="utf-8"))  # 손상 = raise → ERROR(교대 0 · fail-closed)
        except FileNotFoundError:
            return {"swapped": [], "last": {}, "hil": []}

    def save(self) -> None:
        self.sd.mkdir(parents=True, exist_ok=True)
        _ = (self.sd / "state.json").write_text(json.dumps(self.st, ensure_ascii=False), encoding="utf-8")

    def send(self, to: str, body: str) -> None:
        r = subprocess.run(["bash", self.a.mbox, "send", to, SENDER, body], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            raise RuntimeError(f"mbox send to={to} rc={r.returncode}: {r.stderr.strip()[:120]}")

    def rows(self) -> list[tuple[str, Row, dict[str, object], bool]]:
        """→ (좌석, 행, 명부, 역할 좌석 여부) — 현역 행만 · 같은 좌석은 첫 명부."""
        seen: dict[str, tuple[str, Row, dict[str, object], bool]] = {}
        for d in self.tables:
            roles = {v for k, v in d.items() if k.startswith("_") and k not in ROUTE_KEYS and isinstance(v, str)}
            for k, v in d.items():
                if k.startswith("_") or not isinstance(v, dict) or v.get("_replaced_by") or v.get("role") == "stop-ready" or k in seen:
                    continue
                seen[k] = (k, v, d, k in roles and v.get("agent") == "claude")
        return list(seen.values())

    def scan(self, seat: str, row: Row) -> tuple[str, Cut | None, list[tuple[int, str]]]:
        if seat not in self.cache:
            path = seat_jsonl(os.environ.get("FT_SEAT_STATUS", str(HERE / "ft-seat-status.sh")), seat)
            cut, oks = analyze(path) if path else (None, [])
            if cut is not None and not cut.model:  # 오류 문구에 모델이 없으면 명부 model
                cut = replace(cut, model=base_model(str(row.get("model") or "")))
            self.cache[seat] = (path, cut, oks)
        return self.cache[seat]

    def run(self) -> None:
        rows, cands = self.rows(), []
        for seat, row, d, role in rows:
            if not role:
                print(f"SKIP {seat} 역할 좌석 아님")
            elif seat in self.alive and (cut := self.scan(seat, row)[1]) and cut.stuck and cut.cause == "rate_limit":
                cands.append((seat, row, d, cut))
        if not cands:
            return
        live = [(s, r) for s, r, _, _ in rows if s in self.alive and r.get("agent") == "claude"]
        oks = [o for s, r in live for o in self.scan(s, r)[2]]
        cuts = [c for s, r in live if (c := self.scan(s, r)[1]) and c.stuck and c.cause == "rate_limit"]
        for seat, row, d, cut in cands:
            if self.one(seat, row, d, cut, oks, cuts):
                break  # 1회 1건

    def one(self, seat: str, row: Row, d: dict[str, object], cut: Cut, oks: list[tuple[int, str]], cuts: list[Cut]) -> bool:
        base, age = seat.rsplit("#", 1)[0], self.now - cut.ts
        if cut.uuid in self.st["swapped"]:  # pyright: ignore[reportOperatorIssue]
            print(f"NOOP {seat} 이미 교대")
        elif age < self.a.min_wait * 60:
            print(f"WAIT {seat} 정지 {age // 60}분 < {self.a.min_wait}분")
        elif cut.eta and self.now - NEAR < cut.eta <= self.now + NEAR:
            print(f"WAIT {seat} 해제 예상 {hhmm(cut.eta)}")
        elif back(cut, oks):
            print(f"RECOVERED {seat} {cut.model}")
        elif self.now - int(self.st["last"].get(base, 0)) < HOLD:  # pyright: ignore[reportAttributeAccessIssue,reportUnknownMemberType,reportUnknownArgumentType]
            print(f"NOOP {seat} 같은 계보 30분 안 재교대 0")
        elif not (new := self.pick(cut.model, oks, cuts)):
            self.hil(seat, d, cut, f"대체 모델 없음({cut.model or '미상'} · model-fallback.tsv 끝)")
        elif not (src := goal_source(self.ft, base)):
            self.hil(seat, d, cut, "골 원문 출처 없음(도달 파일·발주 본문 0)")
        elif not (wt := self.cwd(seat, row)):
            self.hil(seat, d, cut, "워크트리 미상(jsonl cwd·명부 0)")
        else:
            return self.swap(seat, d, cut, base, new, wt, src)
        return False

    def pick(self, model: str, oks: list[tuple[int, str]], cuts: list[Cut]) -> str:
        """표 다음 칸 · 그 모델도 최근 10분 같은 한도 정지 ∧ 그 뒤 정상 0 이면 그다음 칸 · 끝 = ''."""
        nxt, seen = self.table.get(model, ""), {model}
        while nxt and base_model(nxt) not in seen and any(c.model == base_model(nxt) and c.ts >= self.now - WINDOW and not back(c, oks) for c in cuts):
            seen.add(base_model(nxt))
            nxt = self.table.get(base_model(nxt), "")
        return "" if base_model(nxt) in seen else nxt

    def cwd(self, seat: str, row: Row) -> str:
        path = self.scan(seat, row)[0]
        got = next((str(r["cwd"]) for r in reversed(records(path)) if isinstance(r.get("cwd"), str)), "") if path else ""
        return got or str(row.get("worktree") or row.get("cwd") or "")

    def swap(self, seat: str, d: dict[str, object], cut: Cut, base: str, new: str, wt: str, src: tuple[list[str], str]) -> bool:
        name = next_name({k for t in self.tables for k in t} | self.alive, base)
        print(f"PLAN swap {seat} -> {name} model {cut.model} -> {new}")
        if self.a.dry_run:
            return True
        self.sd.mkdir(parents=True, exist_ok=True)
        bf = self.sd / f"{name}.body"
        _ = bf.write_text("\n".join([*src[0], f"[승계 자동 · 모델 한도] {seat} -> {name} · {cut.model} 한도({cut.reset or '미상'}) · 대체 {new}",
                                     f"첫 일 = 부팅 보고(retire 줄) → recv(옛 계보 미처리 쪽지 이어받음) · 인계서 = {src[1] or '미상'}"]) + "\n", encoding="utf-8")
        so = os.environ.get("FT_SUCCESSOR_OPEN", str(HERE / "ft-successor-open.sh"))
        with (self.sd / f"{name}.log").open("ab") as log:
            _ = subprocess.Popen(["bash", so, seat, wt, "--name", name, "--agent", "claude", "--model", new, "--ctx", "1m", "--effort", "high",
                                  "--body-file", str(bf)], stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        self.st["swapped"] = [*self.st["swapped"], cut.uuid][-500:]  # pyright: ignore[reportGeneralTypeIssues]
        self.st["last"][base] = self.now  # pyright: ignore[reportIndexIssue]
        self.save()
        for to in dict.fromkeys(v for v in (d.get("_master"), d.get("_hil_route")) if isinstance(v, str) and v and v != seat):
            self.send(to, f"[자동 교대] {seat} -> {name} · {cut.model} -> {new} · 사유 한도")
        return True

    def hil(self, seat: str, d: dict[str, object], cut: Cut, why: str) -> None:
        print(f"HIL {seat} {why}")
        to = d.get("_hil_route") or d.get("_master")
        if cut.uuid in self.st["hil"] or not isinstance(to, str) or self.a.dry_run:  # pyright: ignore[reportOperatorIssue]
            return
        self.send(to, f"[HIL] 자동 교대 불가 {seat} · {why} · 교대 0 — 손 교대 판단")
        self.st["hil"] = [*self.st["hil"], cut.uuid][-500:]  # pyright: ignore[reportGeneralTypeIssues]
        self.save()


def main() -> int:
    ap = argparse.ArgumentParser()
    _ = ap.add_argument("--root", required=True)
    _ = ap.add_argument("--mbox", default="")
    _ = ap.add_argument("--table", default=str(HERE / "model-fallback.tsv"))
    _ = ap.add_argument("--now", type=int, default=int(os.environ.get("FT_NOW") or time.time()))
    _ = ap.add_argument("--min-wait", type=int, default=int(os.environ.get("FT_MODEL_SWAP_MIN") or 3))  # BOOT 18 «정지 3분»
    _ = ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    a.mbox = a.mbox or str(Path(a.root) / ".fable-team" / "comm" / "mbox.sh")
    try:
        sw = Swap(a)
        with locked(sw.sd / "run.lock", 0) as got:
            if not got:
                print("BUSY model_swap: 다른 실행이 잠금 중 — 이번 회 교대 0")
                return 0
            sw.run()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"ERROR model_swap: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
