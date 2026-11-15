"""r1933 — keeper 가 연 2.0 나노(opened intent · FT2_HOLDER == 받는이 전체 이름 · 그 이름 tmux 세션)에 send → QUEUED.
반례 ①~⑨(⑩ = ft2/tests/test_pi_launch_recv_r1933.py) · 변이 M1~M3 + R1(M4 role_key 비교 + M5 has-session 을 intent 쪽 이름으로 · 함께).
세계 = 임시 루트 2개 + roots.tsv · 가짜 tmux(FT_FAKE_SESSIONS 만 산다) · 실 우편함·실 tmux·실 명부 0 · sleep 0.
"""
import json, os, shutil, subprocess  # noqa: E401
from pathlib import Path
import pytest
from real_state_guard import guard_begin_module  # noqa: F401  r541 실 상태 지문(모듈 autouse)
COMM = Path(__file__).resolve().parents[2] / "comm"
N, OLD, OTHER = "byz-harness-nano-pi#999", "byz-harness-nano-old#0", "o-seat#0"
TMUX = """#!/bin/sh
printf '%s\\n' "$*" >> "$FT_FAKE_TMUX_LOG"
case "$1" in
  has-session) for s in $FT_FAKE_SESSIONS; do [ "=$s" = "$3" ] && exit 0; done; exit 1;;
  list-panes) [ "$2" = "-a" ] && for s in $FT_FAKE_SESSIONS; do printf '%s|%%9\\n' "$s"; done; exit 0;;
esac
exit 0
"""
def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path
class World:
    def __init__(self, tmp, comm=COMM):
        self.tmp, self.r, self.o = tmp, tmp / "byz", tmp / "other"
        for root in (self.r, self.o):
            (root / ".fable-team/comm").mkdir(parents=True)
            for f in comm.iterdir():
                if f.is_file() and f.suffix in (".py", ".sh"):
                    shutil.copyfile(f, root / ".fable-team/comm" / f.name)
        self.roster = put(self.r / ".fable-team/seats-harness.json", json.dumps({"_master": "m#1", "m#1": {"role": "master"}, OLD: {"role": "nano"}}))
        put(self.o / ".fable-team/seats.json", json.dumps({"_master": OTHER, OTHER: {"role": "master"}}))
        put(tmp / "roots.tsv", f"byz\t{self.r}\t현역\torigin/main\t.\t기본\nother\t{self.o}\t현역\torigin/main\t.\t기본\n")
        put(tmp / "stub/tmux", TMUX).chmod(0o755)
        (tmp / "home").mkdir(); (tmp / "tmpx").mkdir()  # noqa: E702
    def intent(self, holder, state="opened", raw=None):
        put(self.r / ".fable-team/teams/harness/runtime/launch/w@a1.intent", raw or json.dumps({"FT2_HOLDER": holder, "state": state}))
    def send(self, to, sessions=""):
        env = {**{k: v for k, v in os.environ.items() if k != "FT_MBOX_BRIDGED"}, "FT_ROOTS_TSV": str(self.tmp / "roots.tsv"), "HOME": str(self.tmp / "home"), "TMPDIR": str(self.tmp / "tmpx"),
               "FT_FAKE_TMUX_LOG": str(self.tmp / "tmux.log"), "FT_FAKE_SESSIONS": sessions, "FT_MBOX_DOORBELL_MIN": "0",
               "PATH": f"{self.tmp / 'stub'}{os.pathsep}{os.environ['PATH']}", "FT_ROOT": str(self.r), "FT_REPO_ROOT": str(self.r),
               "FT_MBOX_DIR": str(self.r / ".fable-team/comm")}
        return subprocess.run(["bash", str(self.r / ".fable-team/comm/mbox.sh"), "send", to, "m#1", "r1933 시험 본문"],
                              env=env, capture_output=True, text=True, timeout=60)
    def queue(self, root=None):
        p = (root or self.r) / ".fable-team/comm/mailbox.jsonl"
        return [json.loads(x)["to"] for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.is_file() else []
    def rings(self):
        log = self.tmp / "tmux.log"
        return [x for x in log.read_text(encoding="utf-8").splitlines() if x.startswith("send-keys") and "recv" in x] if log.is_file() else []
def refused(w, got):
    assert got.returncode == 2 and got.stderr.count("받는이 판정 불가") == 1 and "QUEUED" not in got.stdout, got.stdout + got.stderr
    assert w.queue() == [], w.queue()
def c1(w):   # ① opened + 세션 있음 → QUEUED 1 · pane 도착 1 · ⑦ 명부 바이트 변화 0
    before = w.roster.read_bytes()
    w.intent(N)
    got = w.send(N, N)
    assert got.returncode == 0 and "QUEUED" in got.stdout, got.stdout + got.stderr
    assert w.queue() == [N] and len(w.rings()) == 1 and w.roster.read_bytes() == before, (w.queue(), w.rings())
def c2(w):   # ② intent opening → 판정 불가
    w.intent(N, "opening")
    refused(w, w.send(N, N))
def c3(w):   # ③ opened + 세션 없음 → 판정 불가
    w.intent(N)
    refused(w, w.send(N, ""))
def c4(w):   # ④ intent JSON 깨짐 → 판정 불가 1줄 · 큐 0
    w.intent(N, raw="{깨짐")
    refused(w, w.send(N, N))
def c5(w):   # ⑤ 1.x 명부 나노 → 지금 그대로(intent 없음)
    got = w.send(OLD, "")
    assert got.returncode == 0 and "QUEUED" in got.stdout and w.queue() == [OLD], got.stdout + got.stderr
def c6(w):   # ⑥ 다른 루트 받는이 → 다리 그대로
    got = w.send(OTHER, "")
    assert got.returncode == 0 and "BRIDGED" in got.stdout and w.queue() == [] and w.queue(w.o) == [OTHER], got.stdout + got.stderr
def c8(w):   # ⑧ DA R1 입력: 받는이 #998 · opened intent = #999 · tmux 에 #999 만 → 판정 불가
    w.intent(N)
    refused(w, w.send("byz-harness-nano-pi#998", N))
def c9(w):   # ⑨ FT2_HOLDER=#998 opened · tmux 에 #999 만 → 판정 불가
    w.intent("byz-harness-nano-pi#998")
    refused(w, w.send("byz-harness-nano-pi#998", N))
@pytest.mark.parametrize("case", [c1, c2, c3, c4, c5, c6, c8, c9])
def test_case(tmp_path, case):
    case(World(tmp_path))
MUTANTS = {"M1": (c1, [("    if ft2_seat(me, to):\n        return None", "")]),
           "M2": (c3, [('return subprocess.run(["tmux", "has-session", "-t", "=" + to], capture_output=True, timeout=7).returncode == 0', "return True")]),
           "M3": (c2, [('doc.get("state") == "opened" and ', "")]),
           "R1": (c8, [('doc.get("FT2_HOLDER") == to', 'role_key(str(doc.get("FT2_HOLDER"))) == role_key(to)'), ('"=" + to]', '"=" + doc["FT2_HOLDER"]]')])}
@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant(tmp_path, name):   # 사본 comm 의 mbox_roots.py 만 바꿈 → 그 사례 FAIL · 원본으로 1회 더 PASS
    case, swaps = MUTANTS[name]
    comm = tmp_path / "comm"
    shutil.copytree(COMM, comm, ignore=shutil.ignore_patterns("__pycache__"))
    text = (comm / "mbox_roots.py").read_text(encoding="utf-8")
    for old, new in swaps:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    (comm / "mbox_roots.py").write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(World(tmp_path / "m", comm))
    case(World(tmp_path / "o"))
