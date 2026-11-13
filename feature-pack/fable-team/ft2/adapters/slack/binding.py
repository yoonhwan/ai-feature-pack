"""ft2 Slack thread binding — thread 1곳에 담당 1명 · 세대(gen) 1개 (r1582 · PR③ 둘째 장).

binding 기록 1건 = (workspace, channel, root ts) → 담당(seat, gen)와 open. 한 thread 의 담당은 하나뿐이라
두 번째 bind 는 덮어쓰지 않고 «거절 행» 을 남긴다(계약 줄 12 · 사례 t2). 담당 교체는 명시 승계(handover)와
재개(reopen) 두 길로만 하고 매번 gen 을 1 올린다 — 답 발행은 «내 세대 = 지금 세대» 만 보고, 다르면 옛 세대
답으로 거절한다(계약 줄 12 · 사례 c7). 채널이 닫히면(close) 담당은 없고(owner None) open=false 다
(계약 줄 14 · 사례 c6·d4). 기록은 append-only jsonl · 쓰기마다 fsync.
"""

import collections
import json
import os
import time

BOUND, REJECTED, CLOSED, REOPENED = "bound", "rejected", "closed", "reopened"

#: thread 키 — 답 (thread 연결, 요청 번호) 중 «thread 연결» 쪽 3값(계약 줄 3).
Key = collections.namedtuple("Key", "workspace channel root")


class Binding(collections.namedtuple("Binding", "workspace channel root seat gen open")):
    """지금 유효한 binding 1건. `owner` = «좌석#세대» 표기(사례 c7·t2 문면)."""
    __slots__ = ()

    @property
    def owner(self):
        return None if self.seat is None else owner_label(self.seat, self.gen)


def thread_key(workspace, channel, root):
    return Key(str(workspace or ""), str(channel or ""), str(root or ""))


def owner_label(seat, gen):
    return "%s#%d" % (seat, gen)


class ThreadBinding:
    """팀 runtime 1곳의 binding 장부. 판정은 `state` 한 낱말로만 말한다."""
    def __init__(self, root, team="harness", clock=None):
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "bindings.jsonl")

    def entries(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def _append(self, entry):
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(dict(entry, schema=1, at=self.clock()), ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        fd = os.open(os.path.dirname(self.path), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        return entry

    def latest(self):
        return {tuple(entry["key"]): entry for entry in self.entries()}

    def settled(self):
        """거절 행을 뺀 «상태를 바꾼» 마지막 기록 — binding 의 유효본은 이것뿐이다."""
        return {tuple(entry["key"]): entry for entry in self.entries() if entry["state"] != REJECTED}

    def get(self, key):
        """지금 유효한 binding. 없으면 None — 답 발행은 이 값 하나로 거절을 정한다."""
        entry = self.settled().get(tuple(key))
        if entry is None:
            return None
        return Binding(key.workspace, key.channel, key.root, entry.get("seat"), entry["gen"], bool(entry["open"]))

    def bind(self, key, seat):
        """첫 bind = gen 1. 이미 있으면 덮어쓰지 않는다(사례 t2)."""
        now = self.get(key)
        if now is None:
            return self._write(key, seat, 1, True, BOUND)
        kind = "second_owner" if now.open else "not_open"
        return self._reject(key, now, kind, want=owner_label(seat, 1), has=now.owner)

    def handover(self, key, seat):
        """명시 승계 — gen+1. 닫힌 binding 은 승계가 아니라 재개(reopen) 대상이다."""
        now = self.get(key)
        if now is None or not now.open:
            return self._reject(key, now, "not_open")
        return self._write(key, seat, now.gen + 1, True, BOUND)

    def handover_seat(self, old, new):
        """좌석 교대(r1827 B1) — 유효본(settled) 중 open·seat==old 마다 handover 1회(gen+1). 넘긴 수."""
        keys = [Key(*k) for k, e in self.settled().items() if e.get("open") and e.get("seat") == old]
        return sum(1 for key in keys if self.handover(key, new)["state"] == BOUND)

    def close(self, key):
        """채널 닫힘 — 담당 없음(owner None) · open=false · gen 은 그대로(사례 c6)."""
        now = self.get(key)
        if now is None:
            return self._reject(key, None, "not_bound")
        return self._write(key, None, now.gen, False, CLOSED)

    def reopen(self, key, seat):
        """재개 — 닫힌 binding 만 · gen+1(사례 d4 «reopen_gen 2»)."""
        now = self.get(key)
        if now is None or now.open:
            return self._reject(key, now, "not_closed")
        return self._write(key, seat, now.gen + 1, True, REOPENED)

    def _write(self, key, seat, gen, open_, state):
        return self._append({"state": state, "key": list(key), "seat": seat, "gen": gen, "open": open_,
                             "owner": None if seat is None else owner_label(seat, gen)})

    def _reject(self, key, now, kind, want=None, has=None):
        return self._append({"state": REJECTED, "k": kind, "key": list(key), "root": key.root,
                             "want": want, "has": has, "seat": None if now is None else now.seat,
                             "owner": None if now is None else now.owner,
                             "gen": None if now is None else now.gen,
                             "open": False if now is None else now.open})


def main(argv):
    """`slack handover-seat --root R --from OLD --to NEW` (r1827 B2) — 장부 있는 팀마다 B1 · 실패 팀 = 판정 불가 rc 1."""
    args = dict(zip(argv[::2], argv[1::2]))
    if len(argv) != 6 or set(args) != {"--root", "--from", "--to"}:
        return print("usage: slack handover-seat --root R --from OLD --to NEW") or 64
    root, moved, rc = os.path.abspath(args["--root"]), [], 0
    teams = os.path.join(root, ".fable-team", "teams")
    for team in sorted(os.listdir(teams) if os.path.isdir(teams) else []):
        if not os.path.isfile(os.path.join(teams, team, "slack", "bindings.jsonl")):
            continue
        try:
            moved.append((team, ThreadBinding(root, team).handover_seat(args["--from"], args["--to"])))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            print("SLACK-BINDING 판정 불가 %s %s" % (team, (str(exc) or type(exc).__name__).replace("\n", " ")))
            rc = 1
    print("SLACK-BINDING moved=%d teams=[%s]" % (sum(n for _, n in moved), " ".join("%s:%d" % m for m in moved)))
    return rc
