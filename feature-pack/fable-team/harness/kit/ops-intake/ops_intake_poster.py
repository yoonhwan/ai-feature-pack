#!/usr/bin/env python3
"""ops_intake_poster — mini 게시기. mini 쪽지함의 [OPS-REPLY] 1통 → 슬랙 같은 스레드 답글 1건 → 쪽지 삭제(ack).

계약(기획 §3 ⑨ · §4 · §6):
  · `thread_ts` 가 없으면 게시 0 (최상위 글 금지) — rc2
  · 게시 «전» 문장 검사: 비밀 + 내부어(경로·좌석 이름·sha·판정 번호) → 걸리면 게시 0 — rc4
  · 같은 쪽지(seq+ts)는 두 번 게시하지 않는다 — state/posted.json 장부
  · 봇 토큰은 mini `~/.hermes/.env` 에서 «읽기만» 한다(새 비밀 0)
  · 슬랙 호출은 하네스 정본 `mirror_lib.post` 재사용 — 7초 상한 + 재시도 1 이 그 안에 있다

사용: python3 ops_intake_poster.py            1회 처리(launchd 60초)  rc 0 정상 · 2 형식 · 4 게시 거부 · 5 쪽지 실패
env: OPS_INTAKE_ROOT · OPS_MBOX_SH/OPS_MBOX_PY · OPS_SLACK_LIB(정본 slack-mirror 폴더) · OPS_HERMES_ENV · OPS_SLACK_BASE · OPS_INTAKE_CHANNEL · OPS_TOOL_SEAT · FT_NOW
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

import ops_intake_common as c

HEADS = "[OPS-REPLY]"
TS_RX = re.compile(r"^\s*thread_ts:\s*(\S+)\s*$", re.M)
CHAN_RX = re.compile(r"^\s*channel:\s*(\S+)\s*$", re.M)
OPS_RX = re.compile(r"\[OPS-REPLY\]\s*(OPS-\d{8}-\d{3})")
SHA_RX = re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")  # 커밋 sha 꼴 — 사람 글에 나갈 이유가 없다
MAX_LINES = 3


def slack_lib():
    """정본 post_guard 규칙표 + mirror_lib.post — 복제 0."""
    here = Path(__file__).resolve().parent
    d = Path(c.env_path("OPS_SLACK_LIB", str(here.parent / "slack-mirror")))
    if not (d / "post_guard.py").is_file() or not (d / "mirror_lib.py").is_file():
        raise c.IntakeError(f"슬랙 정본 모듈 없음: {d} · 게시 0", 2)
    if str(d) not in sys.path:
        sys.path.insert(0, str(d))
    import mirror_lib
    import post_guard
    return mirror_lib, post_guard


def guard(text: str) -> None:
    """게시 전 문장 검사 — 정본 규칙표(post_guard)를 «사람 채널» 기준으로 전부 건다."""
    _ml, pg = slack_lib()
    hits = [f"묶음1:{n}" for n, p in pg.SECRETS.items() if re.search(p, text)]
    hits += [f"묶음2:{n}" for n, p in pg.INTERNAL.items() if re.search(p, text)]
    if SHA_RX.search(text):
        hits.append("묶음2:sha")
    if hits:
        raise c.IntakeError(f"게시 거부(post_guard) — {', '.join(hits)} · 게시 0", 4)


def token(path: Path) -> str:
    """`SLACK_BOT_TOKEN=값` — 값은 어디에도 출력하지 않는다."""
    try:
        for ln in path.read_text(encoding="utf-8").splitlines():
            if ln.startswith("SLACK_BOT_TOKEN=") and ln.split("=", 1)[1].strip():
                return ln.split("=", 1)[1].strip().strip("'\"")
    except OSError as e:
        raise c.IntakeError(f"토큰 파일 읽기 실패: {path} ({type(e).__name__}) · 게시 0", 2) from e
    raise c.IntakeError(f"토큰 파일에 SLACK_BOT_TOKEN 없음: {path} · 게시 0", 2)


def channel_of(body: str, ops_id: str) -> str:
    m = CHAN_RX.search(body) or re.search(r"채널\s+(C[A-Z0-9]{6,})", body)
    if m:
        return m.group(1)
    if c.env_path("OPS_INTAKE_CHANNEL", ""):
        return c.env_path("OPS_INTAKE_CHANNEL", "")
    st = c.read_json(c.sub("status") / f"{ops_id}.json", {})
    if isinstance(st, dict) and st.get("slack_channel"):
        return str(st["slack_channel"])
    raise c.IntakeError("채널 판정 불가 — channel 줄·OPS_INTAKE_CHANNEL·상태 파일 모두 없음 · 게시 0", 2)


def parse(body: str) -> tuple[str, str, str]:
    """(ops_id, thread_ts, 게시 문장). 첫 줄 머리는 문장에서 뺀다."""
    m_o, m_t = OPS_RX.search(body), TS_RX.search(body)
    if not m_o:
        raise c.IntakeError("형식 위반: [OPS-REPLY] ops_id 없음 · 게시 0", 2)
    if not m_t:
        raise c.IntakeError(f"형식 위반: thread_ts 없음({m_o.group(1)}) · 최상위 글 금지 · 게시 0", 2)
    lines = [ln for ln in body.splitlines() if ln.strip() and not TS_RX.match(ln) and not CHAN_RX.match(ln) and not ln.startswith(HEADS)]
    lines = [ln for ln in lines if not ln.strip().startswith("상태 파일")]
    if not lines:
        raise c.IntakeError("형식 위반: 게시 문장 없음 · 게시 0", 2)
    return m_o.group(1), m_t.group(1), "\n".join(lines[:MAX_LINES])


def ledger_key(ops_id: str, ts: str, text: str) -> str:
    """같은 쪽지를 두 번 보내도(new seq) 한 번만 게시 — 본문 지문으로 센다."""
    return hashlib.sha1(f"{ops_id}|{ts}|{text}".encode()).hexdigest()[:16]


def main() -> int:
    seat = c.env_path("OPS_TOOL_SEAT", "byz-opsintake-tool-cmd#0")
    ledger_path = c.sub("state") / "posted.json"
    ledger = c.read_json(ledger_path, [])
    done = set(map(str, ledger))
    rows = [r for r in c.mbox_rows(seat) if str(r.get("body", "")).startswith(HEADS)]
    if not rows:
        print("POST idle n=0")
        return 0
    ml, _pg = slack_lib()
    tok = token(Path(c.env_path("OPS_HERMES_ENV", str(c.home() / ".hermes/.env"))))
    base = c.env_path("OPS_SLACK_BASE", "https://slack.com/api/")
    ok, acked = 0, []
    try:
        for row in rows:
            key = ledger_key(*parse(str(row.get("body", ""))))
            if key in done:
                acked.append(row.get("seq"))
                continue
            ops_id, ts, text = parse(str(row.get("body", "")))
            guard(text)
            ch = channel_of(str(row.get("body", "")), ops_id)
            posted = ml.post(base, tok, ch, text, ts)
            done.add(key)
            ledger.append(key)
            c.write_json(ledger_path, sorted(done))
            acked.append(row.get("seq"))
            ok += 1
            print(f"POST ok {ops_id} ts={ts} posted={posted}")
    except c.IntakeError as e:
        if acked:
            c.mbox_ack(acked)
        print(f"STOP {e}", file=sys.stderr)
        return e.rc
    if acked:
        c.mbox_ack(acked)
    print(f"POST done n={ok}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
