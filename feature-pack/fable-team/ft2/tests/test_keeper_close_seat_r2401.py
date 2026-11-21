"""r2401 ft2 keeper — 사람·팀장이 부르는 닫기 1개(`keeper --close-seat`) · 카드 반례 ①~⑪.
대역 = r1812 keeper_world(실제 core 장부 · 가짜 tmux · 임시 리포) + BYZ 대역 clone 안의 실제 git worktree 1개(intent worktree · 재개 기록 요건) +
planner 판정 원장(origin/main) + 우편 로그 + 자율 모드 스텁(<root>/.fable-team/bin/ft-autonomy.sh). 실 tmux·실 명부·실 원장·sleep 0.
부르는 길 = 실제 `core/cli.py keeper --close-seat …`(①) · 나머지도 같은 갈래(⑩ 만 park 손을 가짜로 바꾼다 · ⑪ 은 잠금 대기를 1초로 줄여 잰다).
"""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import keeper_world_r1812 as kw

TEAM, W = kw.TEAM, "r2401"
S = "byz-harness-nano-r2401-t#0"
OTHER = "byz-harness-nano-r2401-other#1"
DESK, ARCH, MASTER = "byz-planner-desk-pi#7", "byz-harness-arch-pi#5", "byz-harness-master-pi#9"
N, SEQ, UUID = "4500", "12345", "0b9e2c1a-7d4f-4e21-9a3b-5c6d7e8f9012"
REASON = "판정 원장 행 · 유휴 ft2 나노 1석 정리"
IDLE, BUSY_PANE = "✻ Brewed for 3s\n❯ ", "⠋ Working...\n"
ROW = "- **%s** %%s #%s 수동 닫기 나노 1석(r2401 · 자율 ON A18) · 유휴" % (N, SEQ)
MAIL = "[수동 닫기 승인] %s\n%s 1석 정리 · 유휴" % (W, W)


def mc():
    """이 시험 대상 모듈(사본 = 팩 그대로) — ⑩⑪ 은 in-process 로 손을 바꿔 잰다."""
    path = kw.FT2 / "adapters" / "pi" / "keeper_manual_close.py"
    spec = importlib.util.spec_from_file_location("ft2_manual_r2401", str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(cwd, *a):
    return kw._git(cwd, *a)


def tree(w):
    return w.root / ".fable-team" / "teams" / TEAM / "worktrees" / (W + "@a1")


def world(tmp, mp, mode="on", row=ROW, mail=MAIL, mail_from=DESK, dirty=False, pane=IDLE, att=0, files=1,
          latest=S, rows=None, stop=False):
    """일 1개 = submit→assign(S)→deliver · (latest ≠ S 면 S 뒤에 다른 석 배정) · intent(S) · 실제 worktree · pi jsonl files개."""
    w = kw.World(tmp, mp)
    for key, val in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        git(w.root, "config", key, val)
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    git(w.root, "worktree", "add", "-q", "--detach", str(tree(w)), git(w.root, "rev-parse", "HEAD"))
    steps = [["submit", "--command", "c-" + W, "--body", "b", "--work", W], ["assign", "--work", W, "--holder", S, "--evidence", "v1,v2"],
             ["deliver", "--work", W]]
    if latest != S:
        steps += [["assign", "--work", W, "--holder", OTHER, "--evidence", "v1,v2"], ["deliver", "--work", W]]
    for argv in steps:
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    kw._put(w.runtime() / "launch" / ("%s@a1.intent" % W), {"FT2_HOLDER": S, "state": "opened", "worktree": str(tree(w)), "at": "2026-01-01T00:00:00"})
    folder = Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(tree(w)).strip("/").replace("/", "-"))
    for i in range(files):
        log = folder / ("2026-11-01_%s.jsonl" % (UUID if i == 0 else "x%d" % i))
        kw._put(log, '{"type": "session", "id": "%s"}\n' % UUID), os.utime(log, (w.t - 3600, w.t - 3600))
    if dirty:
        kw._put(tree(w) / "wip.txt", "미커밋 1개\n")
    ledger = (row % S) if row else ""
    kw._put(w.root / "design" / "teams" / "planner" / "VERDICTS-planner-24-r2401.md", "# 판정 원장\n" + (rows if rows is not None else ledger + "\n"))
    git(w.root, "add", "-A"), git(w.root, "commit", "-qm", "ledger")
    git(w.root, "update-ref", "refs/remotes/origin/main", "HEAD")
    kw._put(w.root / ".fable-team" / "comm" / "mailbox.log.jsonl", json.dumps({"seq": SEQ, "from": mail_from, "to": S, "body": mail}, ensure_ascii=False) + "\n")
    stub = "%s/.fable-team/bin/ft-autonomy.sh" % w.root
    kw._put(stub, "#!/bin/sh\necho %s\n" % mode), Path(stub).chmod(0o755)
    if stop:
        kw._put(w.state / "ALL_STOP.json", {"reason": "정지"})
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d.update(alive=[S], pane={S: pane}, att={S: att})
    kw._put(w.tm, d)
    w.rs = tmp / "resume"
    w.env["FT2_SEAT_RESUME_DIR"] = str(w.rs)
    return w


def run(w, seat=S, n=N, approve=None, reason=REASON):
    """실제 CLI 갈래 = `core/cli.py keeper --close-seat …` → (줄 목록, rc)."""
    done = subprocess.run([sys.executable, str(w.ft2 / "core" / "cli.py"), "keeper", "--root", str(w.root), "--close-seat", seat,
                           "--verdict", n, "--approve", approve or ("%s #%s" % (DESK, SEQ)), "--reason", reason],
                          capture_output=True, text=True, env=w.env, cwd=str(w.root), timeout=70)
    return [x for x in done.stdout.strip().splitlines() if x], done.returncode


def kills(w):
    return [a[-1] for a in w.tmux("kill-session")]


def rec(w):
    path = w.rs / (S + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def one(lines, head):
    """그 머리로 시작하는 줄 1개(아니면 빈 글)."""
    got = [x for x in lines if x.startswith(head)]
    assert len(got) == 1, lines
    return got[0]


def untouched(w):
    """손 0 = kill 0 · 재개 기록 0 · park 0."""
    assert kills(w) == [] and rec(w) is None, (kills(w), rec(w))


def test_case01_소유있는_ft2나노_닫기(tmp_path, monkeypatch):
    """① 원장 행 ∧ 우편 ∧ 자율 on → 재개 기록 1 · kill 1 · park 1 · CLOSED-MANUAL … park=done rc 0 · project 에 owner 0."""
    w = world(tmp_path, monkeypatch)
    lines, rc = run(w)
    assert rc == 0, lines
    assert one(lines, "CLOSED-MANUAL") == "CLOSED-MANUAL %s %s 판정 %s %s #%s park=done reason=%s" % (TEAM, S, N, DESK, SEQ, REASON), lines
    assert kills(w) == ["=" + S]
    doc = rec(w)
    assert doc["name"] == S and doc["retired_by"] == DESK and doc["binding"]["source"] == "ft2-manual-close", doc
    proj, prc = w.CLI.run(["project", "--root", str(w.root), "--team", TEAM])
    row = (proj.get("holders") or {}).get(S) or {}
    assert prc == 0 and row.get("free") is True and W not in json.dumps(row, ensure_ascii=False), proj.get("holders")   # 그 일 owner 0
    assert (w.root / ".fable-team" / "teams" / TEAM / "runtime").is_dir()   # 장부 리포 살아 있음(지움 0)


def test_case02_대상_판정(tmp_path, monkeypatch):
    """② dispatch 밖 석 = park=none rc 0 / master 석 = REJECT 대상 아님 / intent 없는 나노 꼴 석 = REJECT 대상 아님 intent 없음."""
    w = world(tmp_path, monkeypatch, latest=OTHER)
    lines, rc = run(w)
    assert rc == 0 and "park=none" in one(lines, "CLOSED-MANUAL"), lines
    assert kills(w) == ["=" + S]
    w2 = world(tmp_path / "b", monkeypatch)
    lines, rc = run(w2, seat=MASTER)
    assert rc == 2 and "REJECT 대상 아님" in one(lines, "REJECT 대상 아님"), lines
    untouched(w2)
    lines, rc = run(w2, seat="byz-harness-nano-ghost#0")
    assert rc == 2 and "intent 없음" in one(lines, "REJECT 대상 아님"), lines
    assert kills(w2) == [] and rec(w2) is None


def test_case03_승인_대조_원장과_우편(tmp_path, monkeypatch):
    """③ 원장에 없는 판정 · 행은 있으나 다른 석 · 행에 «무효» · 우편 from ≠ 승인 좌석 → 모두 REJECT 승인 rc 2 · 손 0."""
    w = world(tmp_path, monkeypatch, mode="off")
    lines, rc = run(w)                                  # 자율 off ∧ «오빠 네» 없음 = 승인 아님
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "b", monkeypatch, mode="off", row="- **%s** %%s #%s 수동 닫기 오빠 네 1795000000.000000" % (N, SEQ))
    lines, rc = run(w, approve="%s #99999" % DESK)      # 원장 행에 #seq 없음
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "c", monkeypatch, rows="- **%s** %s #%s 수동 닫기 다른석 (무효)" % (N, OTHER, SEQ))
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "d", monkeypatch, mail_from=ARCH)
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)


def test_case04_planner가_아닌_승인_좌석(tmp_path, monkeypatch):
    """④ 원장·우편 맞고(우편 from = 그 좌석) 승인 좌석만 byz-harness-master 석(planner 아님) → REJECT 승인 rc 2 · 손 0."""
    w = world(tmp_path, monkeypatch, mail_from=MASTER)
    lines, rc = run(w, approve="%s #%s" % (MASTER, SEQ))
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)


def test_case05_자율_모드_대조(tmp_path, monkeypatch):
    """⑤ 자율 on ∧ A<N> 없음 / off ∧ «오빠» 만 / off ∧ «오빠 네 <ts>» = 진행 / mode 판독 실패 / ★고정 반례★ / on ∧ «보류» / 우편 머리 «[닫기 문의]»."""
    w = world(tmp_path, monkeypatch, row="- **%s** %%s #%s 수동 닫기 나노 1석(자율 판정)" % (N, SEQ))
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "b", monkeypatch, mode="off", row="- **%s** %%s #%s 수동 닫기 오빠가 승인함" % (N, SEQ))
    lines, rc = run(w)
    assert rc == 2, lines
    untouched(w)
    w = world(tmp_path / "c", monkeypatch, mode="off", row="- **%s** %%s #%s 수동 닫기 오빠 네 1795000000.000000" % (N, SEQ))
    lines, rc = run(w)
    assert rc == 0 and "park=" in one(lines, "CLOSED-MANUAL"), lines   # 자율 off 여도 «오빠 네 <ts>» = 승인
    w = world(tmp_path / "d", monkeypatch, mode="bogus")
    lines, rc = run(w)
    assert rc == 2 and "자율 모드 판독 실패" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "e", monkeypatch, mode="off", row="- **%s** %%s #%s 오빠 아니오 1795000000.000000 닫기 거절" % (N, SEQ),
              mail="%s 닫기 거절" % W)
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines   # ★DA#56 고정 반례★ 기록 0 · kill 0
    untouched(w)
    w = world(tmp_path / "f", monkeypatch, row="- **%s** %%s #%s 수동 닫기 나노 1석(자율 ON A18) · 보류" % (N, SEQ))
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)
    w = world(tmp_path / "g", monkeypatch, mail="[닫기 문의] %s\n닫아도 되나요" % W)
    lines, rc = run(w)
    assert rc == 2 and "REJECT 승인" in one(lines, "REJECT 승인"), lines
    untouched(w)


def test_case06_정지_중(tmp_path, monkeypatch):
    """⑥ ALL_STOP 켜짐 ∧ ①의 승인 그대로 → REJECT 정지 중 rc 2 · kill 0 · 기록 0."""
    w = world(tmp_path, monkeypatch, stop=True)
    lines, rc = run(w)
    assert rc == 2 and one(lines, "REJECT 정지 중"), lines
    assert "kill 0" in one(lines, "REJECT 정지 중")
    untouched(w)


def test_case07_사람_화면과_일하는_중(tmp_path, monkeypatch):
    """⑦ attached 1 → rc 4 · pane Working → rc 4 · 둘 다 손 0."""
    w = world(tmp_path, monkeypatch, att=1)
    lines, rc = run(w)
    assert rc == 4 and "REJECT attached" in one(lines, "REJECT attached"), lines
    untouched(w)
    w = world(tmp_path / "b", monkeypatch, pane=BUSY_PANE)
    lines, rc = run(w)
    assert rc == 4 and "REJECT busy" in one(lines, "REJECT busy"), lines
    untouched(w)


def test_case08_미커밋(tmp_path, monkeypatch):
    """⑧ intent worktree 에 미커밋 1 → REJECT dirty rc 8 · 기록 0 · kill 0."""
    w = world(tmp_path, monkeypatch, dirty=True)
    lines, rc = run(w)
    assert rc == 8 and "REJECT dirty — [wip] 커밋 먼저" in one(lines, "REJECT dirty"), lines
    untouched(w)


def test_case09_재개_기록_요건(tmp_path, monkeypatch):
    """⑨ intent worktree 폴더 jsonl 0개·2개 → rc 5 · 기록 0 · kill 0."""
    for name, files in (("a", 0), ("b", 2)):
        w = world(tmp_path / name, monkeypatch, files=files)
        lines, rc = run(w)
        assert rc == 5 and one(lines, "REJECT 재개 기록"), lines
        assert kills(w) == [] and rec(w) is None


def test_case10_park_실패(tmp_path, monkeypatch):
    """⑩ park 를 가짜로 실패 → rc 7 · «PARK-FAILED» 줄에 손으로 부를 park 명령 1줄 · 세션은 이미 닫힘."""
    w = world(tmp_path, monkeypatch)
    module = mc()
    module.cli.run = lambda argv: ({"result": "접수 거부", "reason": "결과 미확정 = 쉼 거절(쓰기 0)"}, 1)
    keeper = w.keeper()
    rc = module.run(keeper, S, N, "%s #%s" % (DESK, SEQ), REASON)
    assert rc == 7, keeper.lines
    line = one(keeper.lines, "PARK-FAILED")
    assert "python3 core/cli.py park --work %s --attempt a1 --reason idle-done --root %s" % (W, w.root) in line, line
    assert "manual-close: 판정 %s" % N in line, line
    assert kills(w) == ["=" + S] and rec(w) is not None      # 세션은 이미 닫힘(재개 기록 먼저)


def test_case11_잠금_BUSY(tmp_path, monkeypatch):
    """⑪ keeper 잠금 잡힌 채 → «BUSY» rc 3 · 손 0(대기는 1초로 줄여 잰다 · 값 = LOCK_S 7.0)."""
    w = world(tmp_path, monkeypatch)
    module = mc()
    assert module.LOCK_S == 7.0
    lock = w.root / ".fable-team" / "state" / "ft2-keeper" / "keeper.lock"
    kw._put(lock, ""), os.utime(lock, None)   # 지금 시각 = 산 잠금(10분 넘으면 keeper.locked 처럼 지운다)
    keeper = w.keeper()
    rc = module.run(keeper, S, N, "%s #%s" % (DESK, SEQ), REASON, wait=1.0)
    assert rc == 3 and keeper.lines and keeper.lines[-1].startswith("BUSY"), keeper.lines
    assert lock.exists() and kills(w) == [] and rec(w) is None     # 남의 잠금을 지우지 않는다


def test_case12_pane_판독_실패(tmp_path, monkeypatch):
    """⑫ DA#56 H1 — capture-pane rc 1 = 일하는지 모른다 → rc 9 · 기록 0 · kill 0 · CLOSED-MANUAL 0(고정 = DA 5f13c297 반례)."""
    w = world(tmp_path, monkeypatch)
    keeper = w.keeper()
    real = keeper.call
    keeper.call = lambda argv, timeout=None, retry=0: ((1, "", "capture failed") if argv[1] == "capture-pane"
                                                       else real(argv, timeout=timeout, retry=retry))
    rc = mc().run(keeper, S, N, "%s #%s" % (DESK, SEQ), REASON)
    assert rc == 9 and "capture-pane rc=1" in one(keeper.lines, "REJECT pane 판독"), keeper.lines
    untouched(w)


def test_case13_장부_판독_실패(tmp_path, monkeypatch):
    """⑬ DA#56 H2 — endings.latest = None(장부 판독 실패) → rc 9 · park=none 성공 0 · kill 0(소유 없음 확정 불가)."""
    w = world(tmp_path, monkeypatch)
    module = mc()
    monkeypatch.setattr(module.endings, "latest", lambda *a: None)
    keeper = w.keeper()
    rc = module.run(keeper, S, N, "%s #%s" % (DESK, SEQ), REASON)
    assert rc == 9 and "장부 판독 실패" in one(keeper.lines, "REJECT 장부"), keeper.lines
    untouched(w)
