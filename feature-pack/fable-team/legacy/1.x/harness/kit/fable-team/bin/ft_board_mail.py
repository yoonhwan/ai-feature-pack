"""ft-board 우편 기록 — 로그 + 회전본 + 현재 큐를 seq 로 합쳐 collect 1회에 읽는다 (판정 511·514 · 설계 §4-r2 Q2-r2 · §4-r3). 읽기만 · 쓰기 0.

좌석 이름 비교는 계보(`#N` 앞) — 승계 회신도 인정한다. «기다리는 것» 은 기록 안의 사실 + `추정:` 표기만 쓰고 결론 문구는 내지 않는다.
완료 선언 = 그 좌석의 마지막 발신 머리가 `[완료·휴식]`(또는 원 쪽지가 기록에 있는 `[완료·휴식 유지 #seq]`)이고,
받는 좌석이 그 뒤 이 좌석에게 발신하지 않았을 때. 증거 있음 = 원 쪽지에 증거 줄 + 그 sha 가 리포에 실재(`git cat-file -e`, sha 당 1회).
"""
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

LOGS = ("mailbox.log.jsonl.1", "mailbox.log.jsonl", "mailbox.jsonl")
PREFIX = re.compile(r"^\[[^\]\n]*->[^\]\n]*\]\s*")  # mbox 가 붙이는 `[from->to] ` 접두
DONE = "[완료·휴식]"
KEEP = re.compile(r"^\[완료·휴식 유지 #(\d+)\]")
EVIDENCE = re.compile(r"세트: ([0-9a-f]{40}) · 시험: (?:.+ rc=[0-9]+|없음\(문서\)) · 이슈: \S+")


def lineage(name: str) -> str:
    return re.sub(r"#\d+$", "", name)


def hhmm(ts: str) -> str:
    return datetime.fromisoformat(ts).strftime("%H:%M")


def body_of(rec: dict) -> str:
    return PREFIX.sub("", rec["body"], count=1)


class Mail:
    def __init__(self, root: Path):
        self.root, self.err, self.recs, self._sha = root, None, [], {}
        by_seq: dict = {}
        found = False
        for fn in LOGS:
            p = root / ".fable-team" / "comm" / fn
            if not p.exists():
                continue
            found = True
            for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
                if line.strip() and not self._take(line, by_seq):
                    self.err = f"{fn} {n}행 해석 실패"
                    return
        self.recs = [by_seq[k] for k in sorted(by_seq)]
        if not found:
            self.err = "우편 기록 파일 없음"
        elif not self.recs:
            self.err = "우편 기록 비어 있음"

    @staticmethod
    def _take(line: str, by_seq: dict) -> bool:
        try:
            r = json.loads(line)
            datetime.fromisoformat(r["ts"])
            by_seq.setdefault(int(r["seq"]), {"seq": int(r["seq"]), "ts": r["ts"], "to": str(r["to"]),
                                              "from": str(r["from"]), "body": str(r["body"])})
        except (ValueError, KeyError, TypeError):
            return False
        return True

    def last_sent(self, seat: str) -> dict | None:
        mine = [r for r in self.recs if lineage(r["from"]) == lineage(seat)]
        return mine[-1] if mine else None

    def first_after(self, seq: int, frm: str, to: str) -> dict | None:
        return next((r for r in self.recs if r["seq"] > seq and lineage(r["from"]) == lineage(frm)
                     and lineage(r["to"]) == lineage(to)), None)

    def _sha_exists(self, sha: str) -> bool:
        if sha not in self._sha:
            r = subprocess.run(["git", "-C", str(self.root), "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True)
            self._sha[sha] = r.returncode == 0
        return self._sha[sha]

    def _origin(self, seat: str, last: dict) -> dict | None:
        body = body_of(last)
        if body.startswith(DONE):
            return last
        m = KEEP.match(body)
        o = self._by_seq(int(m.group(1))) if m else None
        return o if o and lineage(o["from"]) == lineage(seat) and body_of(o).startswith(DONE) else None

    def _by_seq(self, seq: int) -> dict | None:
        return next((r for r in self.recs if r["seq"] == seq), None)

    def declaration(self, seat: str) -> dict | None:
        """완료 선언 꼬리 재료 {seq, to, ts, hhmm, evidence} — 조건이 안 맞거나 기록을 못 읽으면 None."""
        last = None if self.err else self.last_sent(seat)
        orig = self._origin(seat, last) if last else None
        if not orig or self.first_after(orig["seq"], orig["to"], seat):
            return None
        m = EVIDENCE.search(body_of(orig))
        return {"seq": orig["seq"], "to": orig["to"], "ts": orig["ts"], "hhmm": hhmm(orig["ts"]),
                "evidence": bool(m) and self._sha_exists(m.group(1))}

    def wait(self, seat: str, decl: dict | None) -> str:
        """기다리는 것 한 줄 — 전부 `추정:` 표기 · 읽을 수 없으면 `기다림 확인 불가(사유)`. 결론(발주 필요 등)은 쓰지 않는다."""
        if self.err:
            return f"기다림 확인 불가({self.err})"
        start = hhmm(self.recs[0]["ts"])
        if decl:
            return (f"추정: {decl['to']} 에 완료 선언 #{decl['seq']}({decl['hhmm']}) · "
                    f"기록({start} 이후)상 이후 {decl['to']} → 이 좌석 발신 없음")
        last = self.last_sent(seat)
        if last is None:
            return f"추정: 기록({start} 이후)상 발신 없음"
        if body_of(last).startswith("[HIL]"):
            return f"추정: HIL 대기 #{last['seq']}({last['to']})"
        head = f"추정: {last['to']} 에 마지막 발신 #{last['seq']}({hhmm(last['ts'])}) · "
        back = self.first_after(last["seq"], last["to"], seat)
        return head + (f"기록상 회신 있음 #{back['seq']}" if back else f"기록상 이후 {last['to']} 회신 없음")
