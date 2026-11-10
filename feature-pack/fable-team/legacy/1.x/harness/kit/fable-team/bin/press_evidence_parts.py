"""press_evidence_parts.py — r1268 큰 poller_dom.jsonl 의 gzip 조각 만들기(pack)·읽기(verify).
  poller 가 45 MB(FT_PRESS_POLLER_PART_MB · 시험 전용)를 넘으면: 한 gzip 스트림을 조각 파일(poller_dom.jsonl.gz.001 …) ≤ 한도로 나눈다.
  meta.txt 에 poller_sha256·poller_bytes·poller_parts 3줄 · 읽을 때는 조각을 차례로 풀어 이으며 줄 단위로 검사하고 sha256·바이트 수를 meta 와 대조한다.
  메모리 = 조각 1개 + 버퍼(통째 읽기 0) · 판정 규칙·거절 문구는 press_evidence_verify.py 의 check_poller 하나.
"""
import gzip
import hashlib
import os
import re
import subprocess
import zlib

MAX_PARTS = 999
NAME = re.compile(r"^poller_dom\.jsonl\.gz\.(\d{3})$")


def limit_bytes():
    return int(float(os.environ.get("FT_PRESS_POLLER_PART_MB") or 45) * 1024 * 1024)


class Spill:   # gzip 이 쓰는 파일꼴 — 한도마다 다음 조각 파일로 넘어간다
    def __init__(self, outdir, size, reject):
        self.dir, self.size, self.reject, self.paths, self.cur, self.n = outdir, size, reject, [], None, 0

    def write(self, data):
        view = memoryview(data)
        while len(view):
            if self.cur is None or self.n >= self.size:
                self.close()
                if len(self.paths) >= MAX_PARTS:
                    raise self.reject("poller 조각 %d 초과" % MAX_PARTS)
                self.paths.append(os.path.join(self.dir, "poller_dom.jsonl.gz.%03d" % (len(self.paths) + 1)))
                self.cur, self.n = open(self.paths[-1], "wb"), 0
            part = view[:self.size - self.n]
            self.cur.write(part)
            self.n += len(part)
            view = view[len(part):]
        return len(data)

    def flush(self):
        pass

    def close(self):
        self.cur and self.cur.close()
        self.cur = None


def split(path, size, outdir, check, reject):   # → (sha256, 바이트 수, 조각 경로들) · check(줄 반복자)가 거절하면 그대로 올린다
    h, total, sp = hashlib.sha256(), [0], Spill(outdir, size, reject)

    def lines(f, gz):
        for raw in f:
            h.update(raw)
            total[0] += len(raw)
            gz.write(raw)
            yield raw.decode("utf-8", "replace")
    try:
        with open(path, "rb") as f, gzip.GzipFile(fileobj=sp, mode="wb", mtime=0) as gz:
            check(lines(f, gz))
    finally:
        sp.close()
    return h.hexdigest(), total[0], sp.paths


def names_of(repo, commit):
    p = subprocess.run(["git", "-C", repo, "ls-tree", "--name-only", commit], capture_output=True, text=True)
    return sorted(n for n in p.stdout.split() if NAME.match(n)) if p.returncode == 0 else []


def rows(repo, commit, meta, reject):   # 조각을 풀어 이은 줄 반복자 · 끝에서 sha256·바이트 수를 meta 와 대조(틀리면 거절)
    try:
        want = (meta["poller_sha256"], int(meta["poller_bytes"]), int(meta["poller_parts"]))
    except (KeyError, ValueError):
        raise reject("poller 조각 meta 3줄(poller_sha256·poller_bytes·poller_parts) 없음")
    names = names_of(repo, commit)
    if len(names) != want[2] or [NAME.match(n).group(1) for n in names] != ["%03d" % i for i in range(1, want[2] + 1)]:
        raise reject("poller 조각 수 ≠ meta(조각 %d · meta %d)" % (len(names), want[2]))
    return stream(repo, commit, names, want, reject)


def stream(repo, commit, names, want, reject):
    d, h, n, buf = zlib.decompressobj(16 + zlib.MAX_WBITS), hashlib.sha256(), 0, b""
    for name in names:
        p = subprocess.Popen(["git", "-C", repo, "cat-file", "blob", "%s:%s" % (commit, name)], stdout=subprocess.PIPE)
        for chunk in iter(lambda: p.stdout.read(1 << 20), b""):
            try:
                out = d.decompress(chunk)
            except zlib.error as x:
                p.kill()
                raise reject("poller 조각 풀기 실패(%s): %s" % (name, x))
            h.update(out)
            n += len(out)
            *done, buf = (buf + out).split(b"\n")
            yield from (r.decode("utf-8", "replace") for r in done)
        if p.wait():
            raise reject("판정 불가: git cat-file rc=%d" % p.returncode)
    if not d.eof or d.unused_data:
        raise reject("poller 조각 풀기 실패(스트림 끝 모자람·남음)")
    if buf:
        yield buf.decode("utf-8", "replace")
    if (h.hexdigest(), n) != want[:2]:
        raise reject("poller 조각 sha256 ≠ meta")
