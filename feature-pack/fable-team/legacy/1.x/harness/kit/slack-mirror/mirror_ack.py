"""mirror_ack — desk 로 넘긴 오빠 글에 «받았어요» 1줄, desk 가 못 읽으면 경보 (R241 · DESIGN-r241-desk-never-stall §3 · DA⑥ H2).

--ack 가 있는 인스턴스(#byz-desk talk)만. 단계마다 «완료 사건» 을 원장 항목에 따로 남겨, 재시작 때 미완료 단계만 이어간다(전달 끝 ≠ ack 끝 ≠ 경보 끝).
  ack 단계: ack_ts(받았어요 글) | ack_failed(게시 실패 · 재시도 0) | ack_skipped(--ack 를 켜기 전에 끝난 글 · 소급 0) · ack_at(시각)
  읽음: read_seen = 쪽지 토큰이 desk 대기 큐(mailbox.jsonl)에서 사라짐 — 큐를 못 읽으면 «모름» (읽음도 경보도 만들지 않는다)
  경보 단계(순서 고정): mirror_ack_alarm — planner 쪽지(alarm_planner_seq | alarm_planner_unsure) → 슬랙 줄(alarm_slack_ts)
"""
import os
import subprocess
import sys
import time

import mirror_ack_alarm as alarm
import mirror_lib as lib

ACK_KEYS = ("ack_ts", "ack_failed", "ack_skipped")


def add_args(p) -> None:
    p.add_argument("--ack", action="store_true", help="desk 로 넘긴 오빠 글에 «받았어요» + 미읽음 경보(talk 인스턴스 전용)")


def on_delivered(inb, st: dict, ts: str, e: dict) -> None:
    """전달이 끝난 항목의 ack 단계 — 한 글 1회. 게시 실패는 원장에 남기고 stderr ERROR(전달은 이미 끝났다 → 재전달·재시도 0)."""
    if not inb.a.ack or not e.get("finished") or any(e.get(k) for k in ACK_KEYS):
        return
    try:
        e["ack_ts"] = lib.post(inb.a.api_base, inb.token, inb.a.channel, "받았어요 — desk 에 넘겼어요", e.get("thread") or ts)
        e["ack_at"] = float(os.environ.get("FT_ACK_NOW") or time.time())
    except lib.MirrorError as err:
        print(f"ERROR: 오빠 글 {ts} «받았어요» 게시 실패: {err}", file=sys.stderr)
        e["ack_failed"] = True
    inb._save(st)


def start(inb, st: dict) -> None:
    """패스 «시작» (후보 처리·재개 전) — --ack 를 처음 켠 데몬이면 경계를 영속화한다: 그 시점에 이미 끝난(finished) 글은 ack_skipped(소급 0),
    아직 끝나지 않은 글은 이번 모드의 새 글이라 finished 직후 죽어도 재시작 뒤 ACK 대상으로 남는다(DA⑥ r2 H2-a)."""
    if not inb.a.ack or st.get("ack_since"):
        return
    for e in st["ledger"].values():
        if e.get("finished") and not any(e.get(k) for k in ACK_KEYS):
            e["ack_skipped"] = True
    st["ack_since"] = True
    inb._save(st)


def full_notice(inb, e: dict, to: str) -> None:
    """수신자 큐 가득 참으로 미룸 — 슬랙 상태 알림 1번(기존 full_notified) + 그 좌석 팀 master 쪽지 1번(r630 · full_mailed).
    쪽지 판정·문구는 루트 틱 모듈 ft_queue_watch.py mail 하나(틱과 같은 꼴) · 실패는 stderr ERROR(조용한 0 없음 · 재시도 0)."""
    inb._notice(e, "full_notified", f"{to} 의 mbox 큐가 가득 차 오빠 글 전달을 미뤘어요 — 좌석이 읽어야 전달돼요")
    if e.get("full_mailed"):
        return
    e["full_mailed"] = True
    rosters = os.path.dirname(os.path.abspath(inb.a.seats_file))
    qw = os.environ.get("FT_QUEUE_WATCH_BIN") or os.path.join(rosters, "bin", "ft_queue_watch.py")
    try:
        r = subprocess.run([sys.executable, "-I", qw, "mail", "--mbox", inb.a.mbox, "--rosters", rosters, "--seat", to],
                           capture_output=True, text=True, timeout=7)
    except subprocess.TimeoutExpired:
        print(f"ERROR: r630 {to} 가득 참 master 쪽지 7초 초과", file=sys.stderr)
        return
    if r.returncode:
        print(f"ERROR: r630 {to} master 쪽지 도구 rc={r.returncode}: {(r.stderr.strip().splitlines() or ['-'])[-1][:200]}", file=sys.stderr)
    for ln in r.stdout.splitlines():
        if not ln.startswith("SENT "):
            print(f"r630 {ln}", file=sys.stderr)  # 도구의 WARN·ERROR 줄 그대로


def watch(inb, st: dict) -> None:
    """패스 끝 — 전달 끝·ack 직전에 죽은 항목의 ack 를 잇고, 경보 단계를 한 걸음씩."""
    if not inb.a.ack:
        return
    for ts, e in st["ledger"].items():
        on_delivered(inb, st, ts, e)
        alarm.step(inb, st, ts, e)
