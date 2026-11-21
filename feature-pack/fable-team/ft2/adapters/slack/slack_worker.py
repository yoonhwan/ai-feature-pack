"""ft2 Slack 수신 스레드 밖 일꾼 (r2341 · S3) — 깨움·쪽지·보충·Web 호출을 큐 1개로 받아 차례로 한다.

수신 스레드는 큐에 넣기만 한다(막힘 0) — 깨움 subprocess 상한 25초·보충 50초가 수신 루프를 묶지 않는다(ⓧ4).
차례 = 넣은 순서(스레드 1개 · ⑱) · 상한 1000 · 가득 = «일꾼 넘침» 1줄 + 알림 1시간 1통(⑭).
수명 = on_idle 마다 is_alive 1줄(입출력 0) · 죽었으면 다시 띄우고 큐는 그대로 둔다(⑬ · 유실 0).
큐를 비우는 일만 한다 — Slack 읽기·장부 쓰기는 맡은 일감(deliver·notify·보충) 안에서만 일어난다.
"""

import queue
import threading
import time

CAP, OVERFLOW_GAP, POLL_S = 1000, 3600.0, 1.0
OVERFLOW = "일꾼 넘침"  # listen.log 낱말 — 시험이 이 낱말로 찾는다


class Worker:
    """일꾼 1개 = 스레드 1개 · 큐 1개. 넣는 쪽(수신 스레드)은 기다리지 않는다."""

    def __init__(self, *, log=None, notify=None, now=None, mono=None, cap=CAP, gap=OVERFLOW_GAP):
        self.log = log or (lambda line: None)
        self.notify = notify or (lambda row: None)  # 넘침 알림 1통 — 일꾼이 부른다(수신 스레드 아님)
        self.now = now or time.time
        self.mono = mono or time.monotonic  # r2391 — 일감 1개의 초를 재는 시계(수신기와 같은 시계)
        self.cap, self.gap = int(cap), float(gap)
        self.queue = queue.Queue(maxsize=self.cap)
        self.worker, self.stopping = None, threading.Event()
        self.max_queue, self.dropped, self.last_overflow, self.alerting = 0, 0, None, 0
        self.slowest = 0.0  # r2391 K2 — «최장 처리» 칸 = 일꾼이 한 일감에 머문 최장 초(관측만)

    # ── 넣는 쪽 (수신 스레드) — 넣고 바로 돌아간다
    def submit(self, job, *args, **kwargs):
        """큐에 넣기만 한다. 가득 = 버리고 1줄(1시간 1통 알림은 일꾼이 보낸다 · ⑭)."""
        try:
            self.queue.put_nowait((job, args, kwargs))
        except queue.Full:
            self.dropped += 1
            at = self.now()
            if self.last_overflow is None or at - self.last_overflow >= self.gap:  # 1시간 1줄
                self.last_overflow, self.alerting = at, 1
                self.log("%s — 큐 %d 가득 · 버린 일 %d" % (OVERFLOW, self.cap, self.dropped))
            return False
        self.max_queue = max(self.max_queue, self.queue.qsize())
        return True

    def wrap(self, job):
        """이미 있는 함수를 큐로 넘기는 꼴 — 주입(deliver·notify·resend)에 쓴다."""
        if job is None:
            return None

        def queued(*args, **kwargs):
            self.submit(job, *args, **kwargs)
            return None

        return queued

    # ── 수명 (수신 스레드가 부르는 것은 이 3줄뿐 · 입출력 0)
    def start(self):
        self.stopping.clear()
        self.worker = threading.Thread(target=self._loop, name="ft2-slack-worker", daemon=True)
        self.worker.start()
        return self.worker

    def alive(self):
        return bool(self.worker is not None and self.worker.is_alive())

    def on_idle(self):
        """envelope 0 인 1초 — 일꾼 수명만 본다(입출력 0). 죽었으면 다시 띄운다(큐 그대로 = 유실 0 · ⑬)."""
        if self.alive():
            return False
        self.log("일꾼 죽음 — 다시 띄움 · 큐 %d 그대로" % self.queue.qsize())
        self.start()
        return True

    def reset_stats(self):  # S6 — «연결 끝» 칸 = 이 연결의 큐 최대 · 최장 처리 초
        self.max_queue, self.slowest = 0, 0.0

    def stop(self, timeout=70.0):
        """멈춤 = 남은 일감을 다 하고 끝난다(유실 0) — 수신기 종료 1곳."""
        worker, self.worker = self.worker, None
        self.stopping.set()
        if worker is not None and worker is not threading.current_thread() and worker.is_alive():
            try:
                self.queue.put_nowait(None)  # 자고 있는 일꾼을 깨운다(차례는 큐 뒤)
            except queue.Full:
                pass
            worker.join(timeout)
        while True:  # 일꾼이 죽어 있던 경우 — 남은 일감은 여기서 마저 한다
            try:
                item = self.queue.get_nowait()
            except queue.Empty:
                return
            if item is not None:
                self._work(item)

    # ── 일꾼 쪽
    def _loop(self):
        while not self.stopping.is_set():
            self._one()

    def _one(self, wait=POLL_S):
        """큐 1개(차례 지킴) — 없으면 wait 초 자고 다시 본다(폴링 = 큐뿐 · Web 호출 0 · ⑮)."""
        try:
            item = self.queue.get(timeout=wait)
        except queue.Empty:
            item = None
        if item is not None:
            self._work(item)
        self._overflow_note()

    def _work(self, item):
        job, args, kwargs = item
        started = self.mono()
        try:
            job(*args, **kwargs)
        except Exception as exc:  # 일감 실패 = 1줄 · 일꾼은 계속 산다(죽는 곳은 스레드 밖 사고뿐)
            self.log("일꾼 일감 실패 %s" % type(exc).__name__)
        finally:
            self.slowest = max(self.slowest, self.mono() - started)  # r2391 K2 — 일꾼이 머문 초(관측)
            self.queue.task_done()

    def _overflow_note(self):
        if not self.alerting:
            return
        self.alerting = 0
        self.notify({"state": "overflow", "dropped": self.dropped,
                     "reason": "%s — 버린 일 %d" % (OVERFLOW, self.dropped)})
