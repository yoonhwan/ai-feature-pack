#!/usr/bin/env python3
# pyright: basic
"""ft_trigger_watch.py status|tick — r1285 기억·트리거 원장 감시기 (판정 3045 · 카드 r1285 r3 · 사전 DA③ APPROVE).
status = 항목·인덱스 읽고 머리 1줄(조회 0). tick = 열린 항목마다 prod-dev Cloud Logging(entries:list 페이지 토큰)에서 «조건» 로그를 찾고,
새 insertId 가 있으면 담당 팀 master + planner 에 [긴급] 1통(사건×수신자 1회 · 하루 항목당 사건 6건 상한). 판정·발송·저장은 공용 잠금 안.
머리 «trigger_watch: 열린 항목 N · 발화 M · 판정 불가 K · 판본 <stamp>» · rc 0 = 발화 0·불가 0 · 1 = 발화 · 3 = 판정 불가(조회 실패·꼴 못 읽음 — «발화 0» 으로 숨기지 않는다).
진행 기준 = 수집 시각(receiveTimestamp) 최댓값(끝까지 읽은 조회만) · 예산 = FT_TICK_DEADLINE − 3초 · 남은 < 8초면 커서(state/trigger-watch/cursor)에 적고 다음 바퀴가 잇는다.
env FT_ROOT · FT_MBOX_SH · FT_TRIGGER_LOG_CMD(스텁 · 기본 ft_trigger_fetch.py) · FT_TRIGGER_CALL_SEC(7) · FT_TRIGGER_MAILLOG · FT_TRIGGER_FROM · FT_TRIGGER_CLOCK_FILE · FT_NOW."""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ft_trigger_items as T  # noqa: E402
from ft_directive_watch import team_master  # noqa: E402
from ft_penalty import root  # noqa: E402

MIN_LEFT, CAP, OVERLAP, SEEN_S, PAGE = 8, 6, 120, 86400, 50


class Run:
    def __init__(self, R: Path, repo: str, ref: str, end: float) -> None:
        self.R, self.repo, self.ref, self.end, self.sd = R, repo, ref, end, T.sdir(R)
        self.lines: list[str] = []
        self.fired = self.undecided = 0

    def left(self) -> float:
        return self.end - T.now()

    def call(self, req: dict) -> dict:
        cmd, sec = os.environ.get("FT_TRIGGER_LOG_CMD") or f"{sys.executable} {HERE}/ft_trigger_fetch.py", float(os.environ.get("FT_TRIGGER_CALL_SEC") or 7)
        for _ in range(2):  # 호출 1회 min(7, 남은 예산) + 재시도 1(시간 초과만)
            left = self.left()
            if left <= 0:
                break
            try:
                p = subprocess.run(shlex.split(cmd), input=json.dumps(req), capture_output=True, text=True, timeout=min(sec, left))
            except subprocess.TimeoutExpired:
                continue
            if p.returncode != 0:
                raise T.Undecided(f"조회 rc={p.returncode} {p.stderr.strip()[:80]}")
            try:
                d = json.loads(p.stdout)
            except ValueError:
                raise T.Undecided("조회 결과 JSON 아님")
            if not isinstance(d, dict) or not isinstance(d.get("entries", []), list) or any(not isinstance(e, dict) or not e.get("insertId") or not e.get("receiveTimestamp") for e in d.get("entries", [])):
                raise T.Undecided("조회 결과 꼴 아님(entries 배열·insertId·receiveTimestamp)")
            return d
        raise T.Undecided("조회 시간 초과")

    def in_maillog(self, to: str, token: str) -> bool:
        f = Path(os.environ.get("FT_TRIGGER_MAILLOG") or self.R / ".fable-team/comm/mailbox.log.jsonl")
        try:
            with open(f, encoding="utf-8") as fh:
                tail = deque(fh, 20000)
        except OSError as e:
            raise T.Undecided(f"우편함 기록 못 읽음 {e.__class__.__name__}")
        for ln in tail:
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            if d.get("to") == to and token in str(d.get("body", "")):
                return True
        return False

    def send(self, to: str, text: str) -> bool:
        mbox, me = os.environ.get("FT_MBOX_SH") or str(self.R / ".fable-team/comm/mbox.sh"), os.environ.get("FT_TRIGGER_FROM", "ft-trigger-watch")
        try:
            p = subprocess.run(["bash", mbox, "send", to, me, text], capture_output=True, text=True, timeout=7)
        except subprocess.TimeoutExpired:
            return False
        return "QUEUED" in p.stdout + p.stderr

    def dispatch(self, it: dict, new: list[dict]) -> bool:
        """새 사건 묶음 1통 — 수신자마다 ①의도 표식 ②쪽지 끝 토큰 ③QUEUED ④.sent · True = 전부 끝(seen 에 넣어도 됨)."""
        n, now = it["num"], T.now()
        dayf, today = self.sd / f"{n}.day", time.strftime("%Y-%m-%d", time.localtime(now))
        day = T.rjson(dayf, {})
        count = day.get("count", 0) if day.get("day") == today else 0
        lead = new[0]["insertId"]
        if count >= CAP:
            self.lines.append(f"하루 상한 {CAP} — {n}")
            return True
        to_all = list(dict.fromkeys(x for x in (team_master(self.R, it["담당"]), team_master(self.R, "planner")) if x))
        if not to_all:
            raise T.Undecided(f"{n} 받는이 없음(명부 _master 못 읽음)")
        token = f"trigger:{n}:{lead}"
        text = f"[긴급] 트리거 {n} 발화 — {it['할 일'][:160]} · 로그 {new[0].get('timestamp', '?')} {lead} · 새 로그 {len(new)}건 · 항목 {it['path']} · 담당이 항목 «## 발화» 줄 추가 · {token}"
        mk, sent_now = self.sd / n, 0
        mk.mkdir(parents=True, exist_ok=True)
        for to in to_all:
            key = re.sub(r"[^\w.#-]", "_", to)
            sent, intent = mk / f"{lead}.{key}.sent", mk / f"{lead}.{key}.intent"
            if sent.exists():
                continue
            if intent.exists() and self.in_maillog(to, token):  # 앞 바퀴가 보내다 끊김 — 이미 쪽지가 갔으면 재발송 0
                sent.write_text("maillog\n", encoding="utf-8")
                continue
            intent.write_text(f"{now:.0f}\n", encoding="utf-8")
            if not self.send(to, text):
                raise T.Undecided(f"{n} 발송 실패 → {to} (다음 바퀴 이 수신자만 다시)")
            sent.write_text(f"{now:.0f}\n", encoding="utf-8")
            sent_now += 1
        self.fired += 1 if sent_now else 0
        T.wjson(dayf, {"day": today, "count": count + len(new)})
        return True

    def item(self, it: dict) -> None:
        n, sd = it["num"], self.sd
        sincef, curf, seenf = sd / f"{n}.since", sd / f"{n}.cursor", sd / f"{n}.seen"
        seen = {k: v for k, v in T.rjson(seenf, {}).items() if T.now() - v < SEEN_S}
        if not sincef.is_file():
            T.wjson(sincef, T.fmt_ts(T.first_commit_ts(self.repo, self.ref, it["path"])))
        since = T.parse_ts(T.rjson(sincef, ""))
        cur = T.rjson(curf, None)
        if cur:
            flt, tok, mx = cur["filter"], cur["token"], cur["maxrecv"]
        else:
            g = it["조건 글자"].replace("\\", "\\\\").replace('"', '\\"')
            parts = ['resource.type="cloud_run_revision"', f'resource.labels.service_name="{it["조건 서비스"]}"', f'(textPayload:"{g}" OR jsonPayload.message:"{g}")',
                     f'receiveTimestamp>="{T.fmt_ts(since - OVERLAP)}"', f'timestamp>="{T.fmt_ts(since - SEEN_S)}"'] + ([] if it["조건 심각도"] == "ANY" else [f"severity>={it['조건 심각도']}"])
            flt, tok, mx = " AND ".join(parts), None, 0.0
        got, complete = [], False
        while self.left() >= MIN_LEFT:
            d = self.call({"filter": flt, "orderBy": "timestamp asc", "pageSize": PAGE, **({"pageToken": tok} if tok else {})})
            got += d.get("entries", [])
            mx = max([mx] + [T.parse_ts(e["receiveTimestamp"]) for e in d.get("entries", [])])
            tok = d.get("nextPageToken")
            if not tok:
                complete = True
                break
        new = list({e["insertId"]: e for e in got if e["insertId"] not in seen}.values())
        if new:
            self.dispatch(it, new)
            seen.update({e["insertId"]: T.now() for e in new})
        T.wjson(seenf, seen)
        if complete:
            if mx:
                T.wjson(sincef, T.fmt_ts(max(since, mx)))
            curf.unlink(missing_ok=True)
        else:
            T.wjson(curf, {"filter": flt, "token": tok, "maxrecv": mx})


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("status", "tick"):
        print("사용: ft_trigger_watch.py status|tick")
        return 2
    R = root()
    try:
        repo, ref = T.repo_ref(R)
        items, notes = T.load(repo, ref)
    except T.Undecided as e:
        print(f"trigger_watch 판정 불가 — 항목 읽기 {e}")
        return 3
    opn = [i for i in items if not i["closed"]]
    run = Run(R, repo, ref, T.now() + 60)
    run.lines = [f"trigger_watch: {x}" for x in notes]
    if argv[0] == "tick":
        deadline = os.environ.get("FT_TICK_DEADLINE")
        run.end = (float(deadline) if deadline else T.now() + 60) - 3
        with T.single_run(run.sd) as got:
            if not got:
                print("trigger_watch: 앞 실행이 아직 돈다 — 건너뜀")
                return 0
            nextf = run.sd / "cursor"
            start = nextf.read_text(encoding="utf-8").strip() if nextf.is_file() else ""
            order = [i for i in opn if i["num"] >= start] + [i for i in opn if i["num"] < start]
            for it in order:
                if run.left() < MIN_LEFT:
                    nextf.write_text(it["num"] + "\n", encoding="utf-8")
                    run.lines.append(f"trigger_watch: 예산 소진 — 다음 바퀴 {it['num']} 부터")
                    break
                try:
                    run.item(it)
                except T.Undecided as e:
                    run.undecided += 1
                    run.lines.append(f"trigger_watch 판정 불가 — {it['num']} {e}")
            else:
                nextf.unlink(missing_ok=True)
    stamp = f"{int(T.now())}-{hashlib.sha1(json.dumps([[i['num'], i['상태']] for i in items] + notes).encode()).hexdigest()[:8]}"
    print(f"trigger_watch: 열린 항목 {len(opn)} · 발화 {run.fired} · 판정 불가 {run.undecided} · 판본 {stamp}")
    for ln in run.lines:
        print(ln)
    return 3 if run.undecided else 1 if run.fired else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
