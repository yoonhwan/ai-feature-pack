"""ft2 코어 journal — segment 회전 · 총량 cap · 회수 (r1584 · PR② 넷째 장).

계약 18줄 줄 18: 미처리는 지우지 않고, 넘치면 «용량 부족» 으로 새 접수를 거절한다. 활성 =
runtime/journal.jsonl(이름 그대로 · 이관 0) · 닫힌 것 = journal.<N>.jsonl. 회전 = append 뒤 활성
크기가 segment cap 에 닿으면 닫고 새 활성(순서 판독 = records). 회수 = base checkpoint → 본문 →
segment(오래된 순) · 잠금 1회 · 멱등. base = state.journal_base {upto,count,proj,receipts} 이고
recover_state 가 base 뒤 suffix 만 접는다. 총량 = runtime 파일 st_size 합 · 한계 = 총 cap −
예약(새 접수) / 총 cap − 1(내부 writer) 이므로 peak ≤ 한계 < 총 cap.
"""

import fcntl
import importlib.util
import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
ACTIVE = "journal.jsonl"
SUBMIT_OPS = ("body_tmp_write", "body_file_fsync", "body_rename", "body_dir_fsync",
              "journal_write", "journal_fsync", "state_write", "receipt")   # 접수 1건의 ops 줄
WRITER_OPS = ("journal_write", "journal_fsync", "state_write")               # 내부 writer 1줄
PROJ_FIELDS = ("generations", "owners", "reservations", "deliveries", "done",
               "reassess_done", "released", "owners_recovered", "uncertain")


def _load_record():
    spec = importlib.util.spec_from_file_location("ft2_core_record", os.path.join(_HERE, "record.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def line_bytes(rec):
    """journal 1줄 byte(개행 포함) — 필요량 산정과 실제 쓰기가 같은 함수를 쓴다."""
    return len(json.dumps(rec, ensure_ascii=False, sort_keys=True).encode("utf-8")) + 1


def ops_bytes(names):
    return sum(len(json.dumps({"op": name}, ensure_ascii=False).encode("utf-8")) + 1 for name in names)


def try_lock(path):
    """writer.lock 비차단 시도 — 잡으면 핸들, 점유 중이면 None(기다리지 않는다)."""
    handle = open(path, "a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def unlock(handle):
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    handle.close()


def _fsync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


class Journal:
    """팀 runtime 1곳 — 회전·판독·총량 판정·회수·복구를 이 한 곳에서 한다."""

    def __init__(self, runtime, segment_cap=65536, total_cap=8388608, reserve=532480,
                 state_slack=4096, line_max=512, ops=None, on_step=None, rec=None):
        self.runtime, self.segment_cap, self.total_cap = os.path.abspath(runtime), segment_cap, total_cap
        self.reserve_bytes, self.state_slack = max(1, reserve), state_slack
        self.line_max = line_max
        self.ops, self.on_step = ops or (lambda op: None), on_step or (lambda step: None)
        self.rec = rec or _load_record()
        self.active_path = os.path.join(self.runtime, ACTIVE)
        self.state_path = os.path.join(self.runtime, "state.json")
        self.tmp_path = os.path.join(self.runtime, "tmp")
        self.lock_path = os.path.join(self.runtime, "writer.lock")
        self.envelope, self.cached_state = None, {}

    def _size(self, path):
        return os.path.getsize(path) if os.path.exists(path) else 0

    def _limit(self, internal=False):
        return self.total_cap - (1 if internal else self.reserve_bytes)

    def envelope_for(self, state):
        return len(json.dumps(state, ensure_ascii=False, sort_keys=True).encode("utf-8"))

    def reserve(self, k=1):
        """내부 writer 1호출의 append 상한 k 합산 예약(DA R2-①) — 넘으면 쓰기 전에 «용량 부족»."""
        state = self._size(self.state_path)
        needed = k * (self.line_max + state + k * (self.line_max + self.state_slack)
                      + ops_bytes(WRITER_OPS))
        limit = self._limit(True)
        if self.usage() + needed > limit:
            raise self.rec.WriterRefused("용량 부족", "예약 k=%d 필요 %d > 한계 %d" % (k, needed, limit))

    def closed(self):
        """닫힌 segment [(N, path)] N 오름차순."""
        out = []
        for name in os.listdir(self.runtime):
            stem = name[8:-6] if name.startswith("journal.") and name.endswith(".jsonl") else ""
            if stem.isdigit():
                out.append((int(stem), os.path.join(self.runtime, name)))
        return sorted(out)

    def _records_of(self, path):
        out = []
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                    self.rec.check(rec)
                except (ValueError, self.rec.RecordError) as exc:
                    raise self.rec.CorruptStateError("journal 판독 불가: %s" % exc)
                out.append(rec)
        return out

    def records(self):
        """닫힌 segment(N 오름차순) + 활성 파일 한 줄 순서 — seq 감소·중복 = CorruptStateError."""
        out = []
        for path in [p for _n, p in self.closed()] + [self.active_path]:
            if not os.path.exists(path):
                continue
            for rec in self._records_of(path):
                if out and rec["seq"] <= out[-1]["seq"]:
                    raise self.rec.CorruptStateError("journal seq 역행·중복: %r <= %r"
                                                     % (rec["seq"], out[-1]["seq"]))
                out.append(rec)
        return out

    def usage(self):
        """runtime 폴더 총량 = 모든 파일 st_size 합(state·segment·ops·bodies·tmp)."""
        return sum(self._size(os.path.join(root, name))
                   for root, _dirs, files in os.walk(self.runtime) for name in files)

    def state(self):
        """state 판독 — tmp/state.json.tmp 가 남아 있으면 «복구 필요»(Journal.recover 로만 푼다)."""
        if os.path.exists(os.path.join(self.tmp_path, "state.json.tmp")):
            raise self.rec.CorruptStateError("state.json.tmp 잔여 = 복구 필요(Journal.recover)")
        self.cached_state = self.rec.read_state_guarded(self.state_path)
        return self.cached_state

    def admits_submit(self, body, rec, envelope):
        """새 접수 필요량 = 본문 + journal 줄 + 새 state + ops 8줄 — 본문 tmp «전» 판정(DA R2)."""
        needed = len(body.encode("utf-8")) + line_bytes(rec) + envelope + ops_bytes(SUBMIT_OPS)
        return self.usage() + needed <= self._limit()

    def _reserve_line(self, rec, envelope):
        """내부 writer 1줄의 필요량 판정 = 줄 + state 몫 + ops 3줄 — 넘으면 쓰기 0(«용량 부족»)."""
        total, limit = self.usage(), self._limit(True)
        needed = line_bytes(rec) + envelope + ops_bytes(WRITER_OPS)
        if total + needed > limit:
            raise self.rec.WriterRefused("용량 부족", "총량 %d + 필요 %d > 한계 %d" % (total, needed, limit))

    def _write_line(self, rec):
        with open(self.active_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            self.ops("journal_write")
            os.fsync(handle.fileno())
        self.ops("journal_fsync")
        _fsync_dir(self.runtime)

    def append(self, rec, envelope=None):
        """내부 writer 1줄 — 총량 판정 → append → 회전. 넘으면 쓰기 0 · WriterRefused(«용량 부족»)."""
        self.rec.check(rec)
        envelope = (envelope if envelope is not None
                    else self._size(self.state_path) + line_bytes(rec) + self.state_slack)
        self._reserve_line(rec, envelope)
        self.envelope = envelope
        self._write_line(rec)
        if self._size(self.active_path) >= self.segment_cap:
            closed = self.closed()
            os.replace(self.active_path, os.path.join(self.runtime,
                                                      "journal.%d.jsonl" % ((closed[-1][0] if closed else 0) + 1)))
            _fsync_dir(self.runtime)
            self.on_step("after_rotate")

    def write_state(self, state):
        """state checkpoint — 예약한 state 몫을 넘으면 tmp 쓰기 «전» 에 «완료 유보»(journal 이 정본)."""
        payload = json.dumps(state, ensure_ascii=False, sort_keys=True)
        size = len(payload.encode("utf-8"))
        if self.envelope is not None and size > self.envelope:
            raise self.rec.WriterRefused("완료 유보", "state 실측 %d > 예약 %d" % (size, self.envelope),
                                         written=True)
        tmp = os.path.join(self.tmp_path, "state.json.tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        self.on_step("state_tmp_written")
        os.replace(tmp, self.state_path)
        _fsync_dir(self.runtime)
        self.ops("state_write")
        self.envelope = None

    def _keep_last(self, top, last):
        """마지막 seq 를 담은 segment 는 회수하지 않는다 — seq 되감김 0(R1 ⑤)."""
        return top >= last

    def _drop(self, path):
        """segment 1개 삭제 — 없는 파일은 건너뛴다(재실행 멱등 · M3)."""
        if not os.path.exists(path):
            return False
        os.unlink(path)
        self.ops("seg_unlink")
        return True

    def _unlink(self, rel, op):
        full = os.path.join(self.runtime, rel)
        if os.path.exists(full):
            os.unlink(full)
            self.ops(op)

    def reclaim(self, state=None):
        """끝난 segment 만 회수 — base checkpoint → 본문 → segment. 잠금 1회 · 재실행 멱등."""
        lock = try_lock(self.lock_path)
        if lock is None:
            return {"result": "BUSY", "reclaimed": [], "bodies": 0, "reason": "writer.lock 점유"}
        try:
            return self._reclaim(state)
        except self.rec.CorruptStateError as exc:
            return {"result": getattr(exc, "word", "복구 필요"), "reclaimed": [], "bodies": 0,
                    "reason": str(exc)}
        finally:
            unlock(lock)

    def _reclaim(self, state=None):
        records = self.records()
        state = self.rec.recover_state(state or self.state(), records)
        base = dict(state.get("journal_base") or {})
        upto, last = base.get("upto") or 0, (records[-1]["seq"] if records else 0)
        targets, bodies, new_upto = [], [], upto
        for _n, path in self.closed():
            seg = self._records_of(path)
            top = max([rec["seq"] for rec in seg] or [0])
            if not top or (top > upto and (self._keep_last(top, last)
                                           or not self._segment_closed(seg, records, state))):
                break                                      # 마지막 seq segment · 열린 work = 보존
            targets.append(path)                           # top ≤ upto = 재실행(멱등) / 닫힌 segment
            new_upto = max(new_upto, top)
            bodies += [rec["body"] for rec in seg if rec["kind"] == "accept" and rec.get("body")]
        if new_upto > upto:
            folded = [rec for rec in records if rec["seq"] <= new_upto]
            proj = self.rec.recover_state(state, folded)
            receipts = dict(base.get("receipts") or {})
            receipts.update({rec["command"]: rec["attempt"] for rec in folded if rec["kind"] == "accept"})
            new_state = dict(state, journal_base={
                "upto": new_upto, "count": (base.get("count") or 0) + len(folded), "receipts": receipts,
                "proj": {name: proj.get(name) or {} for name in PROJ_FIELDS}})
            size, limit = self.envelope_for(new_state), self._limit(True)
            # DA #280106 ②: 이 transaction 이 state tmp 경계 «전» 에 쓰는 ops 줄까지 예약에 센다.
            if self.usage() + size + ops_bytes(("reclaim_checkpoint", "state_write")) > limit:
                raise self.rec.WriterRefused("용량 부족", "회수 checkpoint 가 내부 한계를 넘는다")
            self.ops("reclaim_checkpoint")
            self.envelope = size
            self.write_state(new_state)
            self.on_step("reclaim_after_checkpoint")
        for name in bodies:                                # K1 = 본문 삭제 뒤 · segment 삭제 전
            self._unlink(name, "body_unlink")
        self.on_step("reclaim_after_bodies")
        removed = [os.path.basename(path) for path in targets]
        for idx, path in enumerate(targets):
            if self._drop(path) and idx == 0:
                self.on_step("reclaim_after_seg")          # K2 = 첫 segment 삭제 직후
        _fsync_dir(self.runtime)
        return {"result": "회수 결과", "reclaimed": removed, "bodies": len(bodies), "upto": new_upto}

    def _segment_closed(self, seg, records, state):
        """그 segment 의 모든 줄이 «닫힌 work» — work 없는 줄(accept work=None)은 늘 열림(보존)."""
        return all(work is not None and self._work_closed(work, records, state)
                   for work in {rec.get("work") for rec in seg})

    def _work_closed(self, work, records, state):
        """done + (required 면 reassess_done) + owners·uncertain 없음 + 마지막 result 뒤 start·effect 없음
        + dispatch 의도가 deliver 로 닫힘 (DA R1 ④)."""
        rows = [rec for rec in records if rec.get("work") == work]
        done = (state.get("done") or {}).get(work)
        if done is None or work in (state.get("owners") or {}) or work in (state.get("uncertain") or {}):
            return False
        if (done or {}).get("marker") == "required" and work not in (state.get("reassess_done") or {}):
            return False
        last = max([rec["seq"] for rec in rows if rec["kind"] == "result"] or [0])
        sent = {(rec.get("work"), rec.get("attempt")) for rec in rows if rec["kind"] == "deliver"}
        return (not [rec for rec in rows if rec["kind"] in ("start", "effect") and rec["seq"] > last]
                and all((work, rec.get("attempt")) in sent for rec in rows if rec["kind"] == "dispatch"))

    def recover(self):
        """state.json.tmp 잔여(크래시) 복구 — 잠금 안에서 tmp 삭제 → recover_state checkpoint.
        복구 쓰기 합 ≤ 예약 · 내부 한계 안. 아니면 쓰기 0 · «용량 부족»(복구 필요 유지)."""
        lock = try_lock(self.lock_path)
        if lock is None:
            return {"result": "BUSY", "written": False, "reason": "writer.lock 점유"}
        try:
            state = self.rec.recover_state(self.rec.read_state_guarded(self.state_path), self.records())
            size = self.envelope_for(state)
            if size + ops_bytes(WRITER_OPS) > self.reserve_bytes or self.usage() + size > self._limit(True):
                return {"result": "용량 부족", "written": False, "revision": state["revision"]}
            self._unlink(os.path.join("tmp", "state.json.tmp"), "recover_unlink")
            self.envelope = None
            self.write_state(state)
            return {"result": "접수 성공", "written": True, "revision": state["revision"]}
        except self.rec.CorruptStateError as exc:
            return {"result": getattr(exc, "word", "복구 필요"), "written": False, "reason": str(exc)}
        finally:
            unlock(lock)
