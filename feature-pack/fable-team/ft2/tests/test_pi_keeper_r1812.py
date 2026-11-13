"""r1812 ft2 keeper — 끝난 좌석 자동 닫기 시험 (카드 반례 ①~⑫ · 변이 M1~M9).
임시 root(runtime·intent·명부·switch 주입) · 임시 git 리포 2쌍(BYZ 대역 main·ops/main-base · 팩 대역 main) · 가짜 tmux(FT_TMUX ·
세션 목록·capture 고정 · 호출 기록) · 가짜 ft-seat-close·쪽지(인자 기록) · 주입 시계 · 실 tmux kill·launchd·명부·runtime 0 · sleep 0.
기준판(keeper 없음 · retire 끝 닫기 없음) = 전부 Red(① ④ ⑤ 포함). 변이는 사본에서만 고치고 변이마다 원본으로 같은 사례를 1회 더 돈다.
M8 = resolver 완성/ 빼기 → ⑪ · M9 = complete 뒤 done 재확인 빼기 → ⑪″ (카드에 이름만 있어 R1·Q1 에서 정함).
"""
import importlib.util
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1812", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, FT2, OLD, T0, TEAM, AB, _git, _lines, _put = (kw.World, kw.FT2, kw.OLD, kw.T0, kw.TEAM, kw.AB,
                                                    kw._git, kw._lines, kw._put)


def c1(w):   # ① 팩 main 조상 + done=false → complete 1 · 두 번째 바퀴 쓰기 0
    w.card("r9001", w.pack_sha()), w.work("r9001", intent=False)
    assert any(x.startswith("COMPLETED harness r9001") for x in w.round()) and w.kinds("complete") == 1
    assert w.round() is not None and w.kinds("complete") == 1
def c2(w):   # ② BYZ ops/main-base 에만 있는 sha → complete 1
    w.card("r9002", w.commit("byz", {"o.txt": "o"}, "ops/main-base"), refs=("main",)), w.work("r9002", intent=False)
    assert any("ref byz:origin/ops/main-base" in x for x in w.round()) and w.kinds("complete") == 1
def c3(w):   # ③ 착지 줄 없음 → 쓰기 0 · 쪽지 0 · ③′ 미도달 → 쓰기 0 · 쪽지 1 · 다음 바퀴 0
    w.card("r9003"), w.work("r9003", intent=False), w.card("r9013", AB), w.work("r9013", intent=False)
    assert any("r9003 착지 줄 없음" in x for x in w.round()) and w.kinds("complete") == 0
    assert len(_lines(str(w.mbox) + ".log")) == 1 and "미도달" in _lines(str(w.mbox) + ".log")[0]
    assert w.round() is not None and len(_lines(str(w.mbox) + ".log")) == 1 and w.kinds("complete") == 0
def c4(w):   # ④·⑫′ done + 조상 + 유휴 → kill 1 → 부재 확인 → close_receipt 1 (순서 = 닫기 → 영수)
    w.enable(), w.card("r9004", w.pack_sha())
    holder = w.work("r9004", done=True, alive=True)
    assert [x.split()[0] for x in w.round() if "r9004" in x] == ["CLOSED-SESSION", "RECEIPT"]
    assert w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]] and w.kinds("close_receipt") == 1
def c4b(w):  # ④′ pane «Working» → kill 0 · HELD
    w.enable(), w.card("r9014", w.pack_sha()), w.work("r9014", done=True, alive=True, pane="⠋ Working...\n")
    assert any(x.startswith("HELD harness r9014") and "Working" in x for x in w.round())
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
def c4c(w):  # ④″ 세션 이미 없음 → kill 0 · close_receipt 1
    w.enable(), w.card("r9024", w.pack_sha()), w.work("r9024", done=True), w.round()
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 1
def c11(w):  # ⑪ planner 카드가 완성/ 에만 + done=false → resolver 1건 · complete 1
    w.card("r9011", w.pack_sha(), stage="완성", folder="design/teams/planner"), w.work("r9011", team="planner", intent=False)
    assert w.round() is not None and w.kinds("complete", "planner") == 1
def c11b(w):  # ⑪′ 진행/·완성/ 에 다른 착지 줄 → 판정 불가 · complete 0
    w.card("r9021", w.pack_sha()), w.card("r9021", w.pack_sha(), stage="완성"), w.work("r9021", intent=False)
    assert any("판정 불가" in x and "충돌" in x for x in w.round()) and w.kinds("complete") == 0
def c11c(w):  # ⑪″ complete 뒤 done 다시 읽기 실패(대역) → B2 0
    w.card("r9031", w.pack_sha()), w.work("r9031", alive=True)
    k, calls = w.keeper(), []
    real = k.project
    k.project = lambda r, t: (calls.append(1), real(r, t) if len(calls) == 1 else {"result": "복구 필요", "works": {}})[1]
    assert any("done 확인 못 함" in x for x in w.round(k)) and w.tmux("kill-session") == []
def c12(w):  # ⑫ 표식 없음 + kill 뒤 absent → 완료 유보 · journal 증가 0 · RECEIPT-HOLD
    w.card("r9012", w.pack_sha()), w.work("r9012", done=True, alive=True)
    before = len(w.journal())
    assert any(x.startswith("RECEIPT-HOLD harness r9012") and "켜기 전" in x for x in w.round())
    assert len(w.journal()) == before and len(w.tmux("kill-session")) == 1
def c12c(w):  # ⑫″ 표식 있음 + 판독기 alive → 접수 거부 · journal 증가 0
    w.enable(), w.card("r9022", w.pack_sha())
    out = w.keeper().receipt(TEAM, "r9022", "a1", w.work("r9022", done=True), 1, probe=lambda seat: "alive")
    assert out.result == "접수 거부" and w.kinds("close_receipt") == 0
def c5(w):   # ⑤ retire RETIRED rc0 → ft-seat-close 1회(<구> --reason) · retire rc≠0 → 호출 0 · bin=kit 같은 바이트
    assert (w.old / "bin" / "ft-seat-retire.sh").read_bytes() == (w.old / "kit" / "fable-team" / "bin" / "ft-seat-retire.sh").read_bytes()
    env = dict(w.env, FT_SEAT_REAP_BIN=str(w.tmp / "bin" / "reap"), FT_SEAT_QUIESCE_BIN=str(w.mbox), ZC_RESUME_DIR=str(w.tmp / "rs"))
    seats = w.tmp / "cwd" / "seats-zz.json"
    _put(seats, {"Z#1": {"role": "nano", "agent": "claude", "model": "m"}, "Q#1": {"role": "nano"},
                 "Q#2": {"role": "stop-ready", "_replaced_by": "Q#9"}}), _put(w.tm, {"alive": ["Z#1", "Q#1"], "pane": {}})

    def run(a, b):
        return subprocess.run(["bash", str(w.old / "bin" / "ft-seat-retire.sh"), a, b, "--seats", str(seats)],
                              cwd=str(w.tmp / "cwd"), env=env, capture_output=True, text=True, timeout=60)
    done = run("Z#1", "Z#2")
    assert done.returncode == 0 and done.stdout.startswith("RETIRED"), done.stdout + done.stderr
    assert _lines(str(w.close) + ".log") == ["Z#1 --reason retire -> Z#2 --seats %s" % seats] and "STUB Z#1" in done.stdout
    assert run("Q#1", "Q#2").returncode == 3 and len(_lines(str(w.close) + ".log")) == 1
def c6(w):   # ⑥ 명부 _replaced_by + 생존 → ft-seat-close 1 · HELD 뒤 5분 0 · 11분 1
    _put(w.root / ".fable-team" / "seats-harness.json", {"_master": "M", "O#1": {"role": "stop-ready", "_replaced_by": "O#2"}, "O#2": {}})
    _put(w.tm, {"alive": ["O#1", "O#2"], "pane": {}}), _put(str(w.close) + ".rc", "3")
    calls = [(setattr(w, "t", T0 + dt), w.round(), len(_lines(str(w.close) + ".log")))[2] for dt in (0, 300, 660)]
    assert calls == [1, 1, 2] and _lines(str(w.close) + ".log")[0].startswith("O#1 --reason retire -> O#2 --seats ")
def c7(w):   # ⑦ 끝난 뒤 31분 열린 좌석(HELD 지속) → --report N=1 · 쪽지 1 · 같은 날 다시 → 0
    w.card("r9007", w.pack_sha()), w.work("r9007", done=True, alive=True, pane="Working\n"), w.round()
    w.t = T0 + 31 * 60
    assert w.keeper().report_once().startswith("손 닫기 후보 1") and len(_lines(str(w.mbox) + ".log")) == 1
    assert w.keeper().report_once().startswith("손 닫기 후보 1") and len(_lines(str(w.mbox) + ".log")) == 1
def c8(w):   # ⑧ 잠금 있음 → 바퀴 0 · rc 0 · 로그 1줄 (cli 진입 경유)
    w.card("r9008", w.pack_sha()), w.work("r9008", intent=False), _put(w.state / "ft2-keeper" / "keeper.lock", "")
    done = subprocess.run([sys.executable, str(w.ft2 / "core" / "cli.py"), "keeper", "--root", str(w.root), "--once"],
                          env=w.env, capture_output=True, text=True, timeout=60)
    assert done.returncode == 0 and done.stdout.count("\n") == 1 and "SKIP" in done.stdout, done.stdout + done.stderr
    assert w.kinds("complete") == 0
def c9(w):   # ⑨ git fetch 실패 → B1·B2 판정 불가 1줄 · complete 0 · kill 0 (complete 1 = r9019 준비 줄)
    w.enable(), w.card("r9009", w.pack_sha()), w.work("r9009", intent=False), w.work("r9019", done=True, alive=True)
    _git(w.root, "remote", "set-url", "origin", str(w.tmp / "없음.git"))
    assert sum("fetch" in x and "판정 불가" in x for x in w.round()) == 1
    assert w.kinds("complete") == 1 and w.tmux("kill-session") == []
def c10(w):  # ⑩ plist 틀 → ProgramArguments[0] 절대 경로 · StartInterval 60 · KeepAlive false · plutil -lint rc0
    text = (w.ft2 / "adapters" / "pi" / "launchd" / "com.byz.ft2-keeper.plist.in").read_text(encoding="utf-8")
    for key, value in (("@FT2_HOME@", "/x/ft2"), ("@ROOT@", "/x/root"), ("@PACK_REPO@", "/x/pack"), ("@SEAT_CLOSE@", "/x/c.sh")):
        text = text.replace(key, value)
    assert "@" not in text.split("-->")[-1] and _put(w.tmp / "k.plist", text) is None
    assert subprocess.run(["plutil", "-lint", str(w.tmp / "k.plist")], capture_output=True).returncode == 0
    data = plistlib.loads(text.encode("utf-8"))
    assert data["ProgramArguments"][0].startswith("/") and data["StartInterval"] == 60 and data["KeepAlive"] is False
    assert data["Label"] == "com.byz.ft2-keeper" and data["ProgramArguments"][-3:] == ["--root", "/x/root", "--once"]
def c13(w):  # 보정1 B2 Pi 턴 끝 근거 없음(파일 0 · toolUse) + capture rc0·빈 pane → 판정 불가 · kill 0 · 영수 0
    w.enable(), w.card("r9041", w.pack_sha()), w.card("r9051", w.pack_sha())
    w.work("r9041", done=True, alive=True, pane="", turn=None), w.work("r9051", done=True, alive=True, pane="", turn="toolUse")
    lines = w.round()
    assert [x.split()[0] for x in lines if "r9041" in x or "r9051" in x] == ["HELD", "HELD"], lines
    assert all("판정 불가" in x for x in lines if "r9041" in x or "r9051" in x)
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
def c14(w):  # 보정1 B5 보호 역할(master holder) · intent holder ≠ 최신 dispatch holder → 닫기 0 · 영수 0
    w.enable(), w.card("r9061", w.pack_sha()), w.card("r9071", w.pack_sha())
    w.work("r9061", done=True, alive=True, holder="byz-harness-master-pi#999")
    w.work("r9071", done=True, alive=True, seat="byz-harness-nano-other-t#0")
    lines = w.round()
    assert any(x.startswith("HELD harness r9061") and "보호 역할" in x for x in lines), lines
    assert any(x.startswith("HELD harness r9071") and "holder 불일치" in x for x in lines), lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "④′": c4b, "④″": c4c, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10,
         "⑪": c11, "⑪′": c11b, "⑪″": c11c, "⑫": c12, "⑫′": c4, "⑫″": c12c,
         "B2-pi": c13, "B5-role": c14}
KP, KL, KC = "adapters/pi/keeper.py", "adapters/pi/keeper_land.py", "adapters/pi/keeper_close.py"
MUTANTS = {"M1": ("ft2", KL, '"--is-ancestor", sha, ref)[0] == 0', '"--is-ancestor", sha, ref)[0] in (0, 1, 128)', c3),
           "M2": ("ft2", KL, '(self.pack, "origin/main"), (self.root, REFS[0]), (self.root, REFS[1])', '(self.pack, "origin/main"),', c2),
           "M3": ("ft2", KC, "if BUSY.search(pane", "if False and BUSY.search(pane", c4b),
           "M4": ("ft2", KC, 'self.call([self.tmux, "kill-session"', 'self.receipt(team, work, attempt, holder, gen); self.call([self.tmux, "kill-session"', c4),
           "M5": ("old", "bin/ft-seat-retire.sh", '[ "$prc" -eq 0 ] && [ "$RECONLY" = 0 ] || exit "$prc"', '[ "$RECONLY" = 0 ] || exit "$prc"', c5),
           "M6": ("ft2", KC, "< RETRY_S:", "< 0:", c6),
           "M7": ("ft2", KP, "os.O_CREAT | os.O_EXCL | os.O_WRONLY", "os.O_CREAT | os.O_WRONLY", c8),
           "M8": ("ft2", KL, 'STAGES = ("진행", "대기", "완성")', 'STAGES = ("진행", "대기")', c11),
           "M9": ("ft2", KL, "if not self.done(team, work):", "if False:", c11c),
           "M10": ("ft2", KC, "if not self.turn_ended(", "if False and not self.turn_ended(", c13),
           "M11": ("ft2", KC, "if not self.protected_ok(", "if False and not self.protected_ok(", c14)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    where, rel, old, new, case = MUTANTS[name]
    trees = {"ft2": tmp_path / "m" / "ft2", "old": tmp_path / "m" / "old"}
    shutil.copytree(FT2, trees["ft2"], ignore=shutil.ignore_patterns("tests", "__pycache__"))
    for sub in (("bin",), ("kit", "fable-team", "bin")):
        shutil.copytree(OLD.joinpath(*sub), trees["old"].joinpath(*sub))
    text = (trees[where] / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    for path in [trees[where] / rel] + ([trees["old"] / "kit" / "fable-team" / rel] if where == "old" else []):
        path.write_text(text.replace(old, new), encoding="utf-8")   # retire 변이는 kit 사본도 같이(bin=kit 검사가 먼저 잡지 않게)
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w1", monkeypatch, trees["ft2"], trees["old"]))
    case(World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
