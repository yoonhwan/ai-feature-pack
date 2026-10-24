#!/usr/bin/env python3
"""ft_model_swap.py — 역할 좌석이 모델 한도로 멈추면 같은 역할 후계를 대체 모델로 연다 (r497).

대상 = seats*.json 전부의 역할 칸(`_master`·`_arch`·`_desk`·`_da`… · `_hil_route` 제외) 현역 행 ∧ agent=claude ∧ tmux 생존 · 판정 = R146 analyze.
줄 = WAIT(정지 < 3분 · 해제 예상 ±3분) · RECOVERED(같은 바탕 모델 정상) · NOOP(이미 교대 · 계보 30분) · SKIP · PLAN swap · HIL(계보·이유 1통) · HOLD(계정 한도 · r838).
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
from ft_api_outage_util import base_model, fallback_table, find_jsonls, goal_source, hhmm, jsonl_cwd, locked, next_name, read_table  # noqa: E402
from ft_model_swap_account import CLOSE, WINDOW, Account, shut, write_atomic  # noqa: E402  r838 계정 한도 판정 · r863 키 값 읽기(200줄 상한으로 분리)

SENDER = "ft-model-swap"
ROUTE_KEYS = {"_hil_route"}
HOLD, NEAR, DAY = 30 * 60, 3 * 60, 24 * 3600
Row = dict[str, object]


class Swap(Account):
    def __init__(self, a: argparse.Namespace):
        self.a, self.now, self.tmux = a, a.now, os.environ.get("FT_TMUX", "tmux")
        self.ft = Path(a.root) / ".fable-team"
        self.sd = self.ft / "state" / "model-swap"
        self.table = fallback_table(Path(a.table))
        self.st = self.load()
        self.tables = [t for f in sorted(self.ft.glob("seats*.json")) if (t := read_table(f)) is not None]
        r = subprocess.run([self.tmux, "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
        self.alive = set(r.stdout.split()) if r.returncode == 0 else set()
        self.cache: dict[str, tuple[str, Cut | None, list[tuple[int, str]]]] = {}
        self.jp: dict[str, str] = {}

    def paths(self, seats: list[str]) -> None:  # 좌석 → jsonl 한 번에(최근 2일 파일 머리만 · 좌석별 seat-status 조회는 부하 때 1회 10초 실측)
        self.jp.update(find_jsonls([s for s in seats if s not in self.jp], self.tmux, Path(os.environ.get("FT_CLAUDE_PROJECTS") or Path.home() / ".claude" / "projects")))

    def load(self) -> dict[str, object]:
        try:
            return json.loads((self.sd / "state.json").read_text(encoding="utf-8"))  # 손상 = raise → ERROR(교대 0 · fail-closed)
        except FileNotFoundError:
            return {"swapped": [], "last": {}, "hil": []}

    def save(self) -> None:
        write_atomic(self.sd / "state.json", self.st)  # r863 r2 — 자르고 쓰기 0(쓰기 실패 = 상태 파일 그대로)

    def send(self, to: str, body: str) -> None:
        r = subprocess.run(["bash", self.a.mbox, "send", to, SENDER, body], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            raise RuntimeError(f"mbox send to={to} rc={r.returncode}: {r.stderr.strip()[:120]}")

    def rows(self) -> list[tuple[str, Row, dict[str, object], bool]]:  # → (좌석, 행, 명부, 역할 좌석 여부) — 현역 행만 · 같은 좌석은 첫 명부
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
            path = self.jp.get(seat, "")
            cut, oks = analyze(path) if path else (None, [])
            if cut is not None and not cut.model:  # 오류 문구에 모델이 없으면 명부 model
                cut = replace(cut, model=base_model(str(row.get("model") or "")))
            self.cache[seat] = (path, cut, oks)
        return self.cache[seat]

    def run(self) -> None:
        rows, cands, self.bad = self.rows(), [], set()  # bad = 이번 실행 ERROR 낸 손상 키 이름(r863 · Account.read_key)
        self.paths([s for s, _, _, role in rows if role and s in self.alive])
        for seat, row, d, role in rows:
            if not role:
                print(f"SKIP {seat} 역할 좌석 아님")
            elif seat in self.alive and (cut := self.scan(seat, row)[1]) and cut.stuck and cut.cause == "rate_limit":
                cands.append((seat, row, d, cut))
        if not cands and shut(self.st.get("outage_open", 0)) and not self.st.get("blocked"):
            return
        live = [(s, r) for s, r, _, _ in rows if s in self.alive and r.get("agent") == "claude"]
        self.paths([s for s, _ in live])  # 복구·대체 모델·키 닫기 근거 = 살아 있는 claude 좌석 전부(후보 또는 열린 알림 키가 있을 때만)
        self.close_keys(live, {s.rsplit("#", 1)[0] for s, _, _, _ in cands})
        if not cands:
            return
        oks =[o for s, r in live for o in self.scan(s, r)[2]]
        cuts = [c for s, r in live if (c := self.scan(s, r)[1]) and c.stuck and c.cause == "rate_limit"]
        if self.account(cands, oks):
            return
        for seat, row, d, cut in cands:
            if self.one(seat, row, d, cut, oks, cuts):
                break  # 1회 1건

    def close_keys(self, live: list[tuple[str, Row]], stuck: set[str]) -> None:
        """r838 알림 키(outage_open·blocked)를 지우는 곳은 여기 하나 — 값 {at 알린 시각, seen 마지막 정지 본 시각 · 지금 정지면 now} · 닫힘 = at 뒤 정상 턴(is_normal) 또는 now−seen ≥ 24시간(살아 있는 계보 0 이어도 · r4)."""
        oks: dict[str, list[int]] = {}
        for s, r in live:
            oks.setdefault(s.rsplit("#", 1)[0], []).extend(t for t, _ in self.scan(s, r)[2])
        def keep(name: str, b: str, v: object) -> object:  # b = 계보('' = 장애 키 · 살아 있는 claude 좌석 아무나) → 남길 값 · CLOSE = 닫힘
            if (kv := self.read_key(name, v)) is None:
                return v  # r863 손상 = ERROR 1줄 + 원래 값 그대로(None 도 · 지우기·덮어쓰기 0)
            kv["seen"] = self.now if (b in stuck if b else stuck) else kv["seen"]
            return CLOSE if any(t > kv["at"] for k, ts in oks.items() if not b or k == b for t in ts) or self.now - kv["seen"] >= DAY else kv
        if not shut(self.st.get("outage_open", 0)):
            self.st["outage_open"] = 0 if (v := keep("outage_open", "", self.st["outage_open"])) is CLOSE else v
        self.st["blocked"] = {k: v for k, v0 in dict(self.st.get("blocked") or {}).items() if (v := keep(k, k.split("|", 1)[0], v0)) is not CLOSE}  # pyright: ignore[reportCallIssue,reportArgumentType,reportUnknownArgumentType,reportUnknownMemberType,reportUnknownVariableType]

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
        elif not (wt := jsonl_cwd(self.scan(seat, row)[0]) or str(row.get("worktree") or row.get("cwd") or "")):
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

    def swap(self, seat: str, d: dict[str, object], cut: Cut, base: str, new: str, wt: str, src: tuple[list[str], str]) -> bool:
        name = next_name({k for t in self.tables for k in t} | self.alive, base)
        print(f"PLAN swap {seat} -> {name} model {cut.model} -> {new}")
        if self.a.dry_run:
            return True
        self.st["swapped"] = [*self.st["swapped"], cut.uuid][-500:]  # pyright: ignore[reportGeneralTypeIssues]
        self.st["last"][base] = self.now  # pyright: ignore[reportIndexIssue]
        self.save()  # 기록 먼저 — 열기·쪽지가 실패해도 같은 uuid 재교대 0(중복 후계 0)
        bf = self.sd / f"{name}.body"
        _ = bf.write_text("\n".join([*src[0], f"[승계 자동 · 모델 한도] {seat} -> {name} · {cut.model} 한도({cut.reset or '미상'}) · 대체 {new}",
                                     f"첫 일 = 부팅 보고(retire 줄) → recv(옛 계보 미처리 쪽지 이어받음) · 인계서 = {src[1] or '미상'}"]) + "\n", encoding="utf-8")
        so = os.environ.get("FT_SUCCESSOR_OPEN", str(HERE / "ft-successor-open.sh"))
        with (self.sd / f"{name}.log").open("ab") as log:
            _ = subprocess.Popen(["bash", so, seat, wt, "--name", name, "--agent", "claude", "--model", new, "--ctx", "1m", "--effort", "high",
                                  "--body-file", str(bf)], stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        for to in dict.fromkeys(v for v in (d.get("_master"), d.get("_hil_route")) if isinstance(v, str) and v and v != seat):
            self.send(to, f"[자동 교대] {seat} -> {name} · {cut.model} -> {new} · 사유 한도")
        return True

    def hil(self, seat: str, d: dict[str, object], cut: Cut, why: str) -> None:
        print(f"HIL {seat} {why}")
        to, key = d.get("_hil_route") or d.get("_master"), f"{seat.rsplit('#', 1)[0]}|{why}"  # r838 ⓖ: 키 = (계보 · 이유) — 정지 uuid 는 회차마다 바뀐다
        if key in self.st["blocked"] or self.mute(key) or not isinstance(to, str) or self.a.dry_run:  # pyright: ignore[reportOperatorIssue] · 닫힘 = close_keys 하나(r838 r3 ②) · r863 손상 계보 알림 0
            return
        self.send(to, f"[자동 교대 불가] {seat} · {why} · 교대 0 — 필요한 결정: 손 교대 여부(planner 인터뷰)")  # ⓗ 머리 [HIL] 0(슬랙 질문 적체)
        self.st["blocked"][key] = {"at": self.now, "seen": self.now}  # pyright: ignore[reportIndexIssue] · r4 값 {at, seen} · 저장 = main 끝


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
            if not a.dry_run:
                sw.save()  # HIL uuid
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"ERROR model_swap: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
