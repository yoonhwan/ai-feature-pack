"""r2055a settle 한 길 — 좌석마다 판정 1개(LANDED · PARKED · WORKING · UNKNOWN) (카드 반례 ①②③④⑤⑥⑦⑨⑩⑪⑫⑰⑱⑲⑳ · 변이 M3·M4·M5).
대역 = r1812 keeper_world(임시 root · 두 ref · 가짜 tmux) + 실 임시 nano worktree(clone · push) + 가짜 mbox(peek·send) · ps·pane 표 = keeper 인스턴스 주입.
실 tmux·실 runtime·실 명부·Slack 0 · sleep 0(시계 = 주입 w.t). 기준판(팩 origin/main 91b0b064) = ①②③④⑤⑦⑨⑩⑪⑫⑰(가)⑱⑲ Red · ⑥ ⑰(나)(라)(마)(바) ⑳ 은 지킴·양성 회귀.
"""
import datetime
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_world_r2055", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
FT2, T0, TEAM, IDLE_PANE = kw.FT2, kw.T0, kw.TEAM, "✻ Brewed for 3s\n❯ "
MBOX = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nif [ "$1" = peek ]; then echo "pending=$(cat "$0.pending" 2>/dev/null || echo 0) scanned=1"; exit 0; fi\n' \
       'echo "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n'
LS = 'if a[0] == "list-sessions": print("\\n".join(d["alive"])); sys.exit(0)\n'
CHAIN = [(100, 1, 0.0, "zsh"), (101, 100, 0.0, "npm"), (102, 101, 0.0, "node"), (103, 102, None, "pi"), (200, 1, 2.0, "other")]


def world(tmp, mp, ft2=FT2):
    w = kw.World(tmp, mp, ft2)
    kw._put(w.mbox, MBOX), w.mbox.chmod(0o755)
    kw._put(tmp / "bin" / "gh", "#!/bin/sh\necho '[]'\n"), (tmp / "bin" / "gh").chmod(0o755)
    w.env.update(FT2_GH=str(tmp / "bin" / "gh"), HOME=str(tmp / "home"), FT2_TEAM_NANO_MAX="0", FT2_MAILBOX_DIR=str(tmp / "comm"),
                 FT2_SEAT_RESUME_DIR=str(tmp / "resume"), GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
    w.enable()
    return w


def git(cwd, *a):
    return kw._git(cwd, *a)


def nano(w, work, res="", alive=True, state="opened", turn="stop", age=7200, pane=IDLE_PANE, tree=True, dirty=False, push=True,
         body=None, done=False, branch=None):
    """나노 1석 = 접수(본문) → 배정(자원 res) → 전달 · 실 worktree(clone · 가지 커밋 · push) · intent · Pi jsonl(mtime = 시계 − age)."""
    holder, res = "byz-%s-nano-%s#0" % (TEAM, work), res or "R-" + work
    steps = [["submit", "--command", "c-" + work, "--body", body or "본문-" + work, "--work", work],
             ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2"] + (["--resources", res] if res else []),
             ["deliver", "--work", work]] + ([["complete", "--work", work, "--attempt", "a1"]] if done else [])
    for argv in steps:
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    path, base = w.tmp / "wt" / work, git(w.tmp / "seed-byz", "rev-parse", "main")
    if tree:
        git(w.tmp, "clone", "-q", str(w.tmp / "byz.git"), str(path))
        for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
            git(path, "config", k, v)
        git(path, "checkout", "-q", "-b", branch or "nano/" + work)
        kw._put(path / "x.txt", work), git(path, "add", "-A"), git(path, "commit", "-q", "-m", "x")
        git(path, "push", "-q", "origin", branch or "nano/" + work) if push else None
        kw._put(path / "dirty.txt", "d") if dirty else None
    intent = {"FT2_HOLDER": holder, "state": state, "at": "2026-01-01T00:00:00", "base": "origin/main", "base_sha": base}
    intent.update({"worktree": str(path)} if tree else {})
    kw._put(w.runtime() / "launch" / ("%s@a1.intent" % work), intent)
    jsonl = Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(path).strip("/").replace("/", "-")) / "s.jsonl"
    kw._put(jsonl, '{"type": "session"}\n' + json.dumps({"type": "message", "message": {"role": "assistant", "stopReason": turn}}) + "\n")
    os.utime(jsonl, (w.t - age, w.t - age))
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"], d["pane"][holder] = d["alive"] + ([holder] if alive else []), pane
    kw._put(w.tm, d)
    return holder


def rnd(w, cmd="pi", cpu=0.0, dt=0, clean=None):
    """한 바퀴 — 시계 dt 초 앞으로 · pane 명령·ps 표(사슬 끝 %cpu) 주입 · tmuxc clean 대역 출력(A13 1차 · 기본 = 셸 명령이면 살아 있는 세션 전부) · 반환 = 로그 줄."""
    w.t += dt
    alive = json.loads(w.tm.read_text(encoding="utf-8"))["alive"]
    shells = alive if os.path.basename(cmd) in ("zsh", "bash", "fish") else []
    kw._put(str(w.tm) + ".clean", "".join(x + "\n" for x in shells) if clean is None else clean)
    k = w.keeper()
    k.pane_info = lambda seat: (100, cmd)
    k.ps_rows = lambda: [(p, pp, cpu if c is None else c, n) for p, pp, c, n in CHAIN]
    return w.round(k)


def two(w, **kv):   # CPU idle 판정 = 표본 2개 · 간격 30초
    return rnd(w, **kv) + rnd(w, dt=30, **kv)


def proj(w):
    return w.CLI.run(["project", "--root", str(w.root), "--team", TEAM])[0]


def has(lines, *words):
    return [x for x in lines if all(word in x for word in words)]


def sent(w):
    return [x for x in kw._lines(str(w.mbox) + ".log") if x.startswith("send")]


def c1(w):   # ① 끝난 나노 · 착지 0 · clean · push · 유휴 ≥ 60분 → PARKED · kill 1 · parked 1줄 · 용량 −1 · 의무 그대로
    w.card("r9551", stage="진행")
    nano(w, "r9551")
    before = proj(w)
    lines = two(w)
    assert has(lines, "PARKED harness r9551", "idle-done") and len(w.tmux("kill-session")) == 1, lines
    after = proj(w)
    assert w.kinds("parked") == 1 and (after["capacity"], after["remaining"]) == (before["capacity"] - 1, before["remaining"]), after


def c2(w):   # ② 팀 걸친 카드(짝 표 없음 · 본문 경로) · 착지 줄 조상 → LANDED(COMPLETED + 닫기)
    stem, sha = "v65-conn-9-x", w.pack_sha()
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/teams/v65/indices/완성/%s.md" % stem: "# 인덱스\n- 남은 범위: 없음\n- 착지: %s\n" % sha}, ref)
    nano(w, stem, age=10, body="[발주] %s — 카드 origin/main design/teams/v65/indices/대기/%s.md(팀 폴더 아님) §범위" % (stem, stem))
    lines = two(w)   # A6·S4-1 jsonl 10초 전 증가 = WORKING landed-wait · kill 0 · complete 0 (DA#11 R1)
    assert has(lines, "WORKING harness %s" % stem, "landed-wait") and not w.tmux("kill-session") and w.kinds("complete") == 0, lines
    lines = rnd(w, dt=7200)   # 무활동 ≥ PARK_IDLE → LANDED
    assert has(lines, "COMPLETED harness %s" % stem) and len(w.tmux("kill-session")) == 1, lines


def c2b(w):   # ②′ 본문 경로 실패 사유 꼬리 · 짝 표 먼저(본문 읽기 0) · .. 경로 무시
    k, stem = w.keeper(), "v65-conn-8-y"
    nano(w, stem, alive=False, body="경로 없음")
    assert k.landing(TEAM, stem)[2] == "판정 불가 · 카드 후보 0 · 본문 경로 없음"
    for i, body in enumerate(("design/a/indices/대기/{s}.md · design/b/indices/진행/{s}.md", "design/z/indices/대기/{s}.md",
                              "design/../x/indices/대기/{s}.md")):
        (w.runtime() / "bodies" / ("c-%s.body" % stem)).write_text(body.format(s=stem), encoding="utf-8")
        tail = ("본문 경로 충돌", "본문 카드 없음 design/z", "본문 경로 없음")[i]
        assert tail in w.keeper().landing(TEAM, stem)[2], (i, body)
    w.commit("byz", {"design/teams/chatbot/indices/진행/%s.md" % stem: "# 인덱스\n- 착지: %s\n" % w.pack_sha()}, "main")
    kw._put(w.runtime() / "cards.tsv", "%s\tdesign/teams/chatbot/indices/진행/%s.md\n" % (stem, stem))
    rnd(w)   # fetch
    got = w.keeper().landing(TEAM, stem)
    (w.runtime() / "bodies" / ("c-%s.body" % stem)).unlink()
    assert w.keeper().landing(TEAM, stem) == got and "본문" not in str(got) and got[0], got


def c3(w, failed="closed"):   # ③·⑫ 세션 0 · owner 남음 · intent closed/failed → park(launch-failed) 1회 · 판정 낱말 = UNKNOWN launch-failed(r2058 L3) · owner·예약 해제 · 용량 −1
    nano(w, "r9553", alive=False, state=failed)
    before = proj(w)
    lines = rnd(w)
    st = json.loads((w.runtime() / "state.json").read_text(encoding="utf-8"))
    after = proj(w)
    assert has(lines, "UNKNOWN harness r9553", "launch-failed") and not has(lines, "PARKED harness r9553"), lines   # r2058 — 쉼은 하되 줄은 UNKNOWN
    assert w.kinds("parked") == 1, lines
    assert "r9553" not in st["owners"] and "R-r9553" not in st["reservations"] and after["capacity"] == before["capacity"] - 1
    assert after["remaining"] == before["remaining"]
    out, rc = w.CLI.run(["assign", "--work", "r9553", "--holder", "byz-harness-nano-r9553#0", "--evidence", "v1,v2", "--resources", "R-r9553",
                         "--root", str(w.root), "--team", TEAM])
    assert (rc, out["attempt"]) == (0, "a2"), out   # ⑫ 다시 열기 = 새 attempt(같은 자원 R)


def c4(w):   # ④ ALL_STOP + ① 입력 → kill 0 · park 0 · fill 0 · «예정 PARKED» 1줄
    kw._put(w.state / "ALL_STOP.json", {"since": 1, "reason": "시험"})
    w.card("r9554", stage="진행")
    nano(w, "r9554")
    lines = two(w) + rnd(w, dt=30)
    assert len(has(lines, "예정 PARKED", "r9554")) == 1 and not w.tmux("kill-session") and w.kinds("parked") == 0, lines
    assert not w.tmux("send-keys") and w.kinds("dispatch") == 1


def c4b(w):   # ④′ ALL_STOP 깨짐 = 정지 + 판정 불가 1줄
    kw._put(w.state / "ALL_STOP.json", "{깨짐")
    nano(w, "r9554")
    lines = two(w)
    assert has(lines, "판정 불가", "ALL_STOP") and not w.tmux("kill-session") and w.kinds("parked") == 0, lines


def c5(w):   # ⑤ 새 꼴(intent worktree 칸 없음) → UNKNOWN · [긴급] 1통 · kill 0 · r2065 E3·E5 실패도 그날 지문(재시도 0) → 같은 날 다시 0통
    nano(w, "r9555", tree=False)
    kw._put(str(w.mbox) + ".rc", "1")
    lines = rnd(w)
    assert has(lines, "UNKNOWN harness r9555", "intent-bad") and has(lines, "ROUND", "unknown=2") and not w.tmux("kill-session"), lines   # r2055 R3 정체 본문 도달 0 도 UNKNOWN 줄([긴급]) = 2
    assert len([x for x in sent(w) if "intent-bad" in x]) == 1   # 시도 1(재시도 0) — old 기대 2 = 7초 + 재시도 1
    kw._put(str(w.mbox) + ".rc", "0")
    rnd(w, dt=60), rnd(w, dt=60)
    assert len([x for x in sent(w) if "intent-bad" in x]) == 1 and not [x for x in kw._lines(str(w.close) + ".log")]   # 실패 지문 = 같은 날 다시 보내지 않는다
    assert not has(rnd(w, dt=60), "HELD")


def c6(w):   # ⑥ 스피너 = WORKING · 일하는 pi(API 대기 · %cpu 0.0 ×2 · jsonl 5분 전 · 스피너 없음) = WORKING · 닫힘 0 · park 0
    nano(w, "r9556", pane="⠋ Working (3s)", age=600)   # A13 1차가 서면 사유 = jsonl(pane 글자 안 읽음)
    nano(w, "r9557", age=300)
    lines = two(w)
    assert has(lines, "WORKING harness r9556", "jsonl-active") and has(lines, "WORKING harness r9557"), lines
    assert not w.tmux("kill-session") and w.kinds("parked") == 0, lines


def c7(w):   # ⑦ 유휴 ≥ 60분 · dirty / unpushed → UNKNOWN [긴급] · kill 0
    nano(w, "r9558", dirty=True)
    nano(w, "r9559", push=False)
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9558", "dirty") and has(lines, "UNKNOWN harness r9559", "unpushed"), lines
    assert not w.tmux("kill-session") and w.kinds("parked") == 0 and len(sent(w)) == 2


def c9(w):   # ⑨ 질문 창(toolUse · jsonl 무활동 16분) · %cpu 0.1 ×2(30초) → UNKNOWN waiting-input · [긴급] 팀장 · kill 0
    nano(w, "r9560", turn="toolUse", age=960)
    lines = two(w, cpu=0.1)
    assert has(lines, "UNKNOWN harness r9560", "waiting-input") and not w.tmux("kill-session"), lines
    assert [x for x in sent(w) if "waiting-input" in x and x.startswith("send M-harness")], sent(w)


def c10(w):   # ⑩ 원장 done ∧ 카드 완성 폴더 · PR 0 · 가지 이름 다름 → LANDED(넓힌 근거) · 세션 닫힘
    w.card("r9561", stage="완성")
    nano(w, "r9561", done=True, branch="feature/other", age=60)
    lines = two(w)   # jsonl 1분 전 증가 = WORKING · kill 0 (DA#11 R1 재현 입력)
    assert has(lines, "WORKING harness r9561") and not w.tmux("kill-session"), lines
    lines = rnd(w, dt=7200)
    assert has(lines, "CLOSED-ENDING harness r9561", "done-card-완성") and len(w.tmux("kill-session")) == 1, lines


def c11(w):   # ⑪ accept 만 · PARK_IDLE 넘음 · 같은 work command 2개 → 용량 1 · 의무 2 · UNKNOWN accept-only 1줄
    for c in ("c1", "c2"):
        assert w.CLI.run(["submit", "--command", c, "--body", "b", "--work", "r9562", "--root", str(w.root), "--team", TEAM])[1] == 0
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    w.t = datetime.datetime.strptime(kw.NOW, "%Y-%m-%dT%H:%M:%S").timestamp() + 7200
    lines = rnd(w)
    p = proj(w)
    assert len([x for x in lines if x.startswith("UNKNOWN harness r9562 - accept-only")]) == 1 and (p["capacity"], p["remaining"]) == (1, 2), (lines, p)


DICT_WORK = ({"slack": {"team": "planner"}},   # ㉕ 실제 journal accept 의 work 꼴 2개(Slack 접수 · work 없는 접수)
             {"route": {"channel": "C0C9GRFHJE5", "id": "post:x", "thread": "1794578093.789539", "to": "byz-planner-desk-pi#154"},
              "slack": {"attempts": 2, "channel": "C0C9GRFHJE5", "ts": "1794580640.715179"}})


def c25_journal(w, dict_work=True, str_work=True, dispatch=True):
    """㉕ journal — dict-work accept 2줄(work 칸만 실제 꼴로 바꿈) · str-work accept-only 1건 · 다른 work dispatch 1줄 · 시계 = PARK_IDLE 넘김."""
    steps = [["submit", "--command", "c-d%d" % i, "--body", "b", "--work", "d%d" % i] for i in (1, 2) if dict_work]
    steps += [["submit", "--command", "c-s", "--body", "b", "--work", "r9570"]] if str_work else []
    steps += [["submit", "--command", "c-x", "--body", "b", "--work", "r9572"], ["assign", "--work", "r9572", "--holder", "byz-harness-nano-r9572#0",
              "--evidence", "v1,v2"], ["deliver", "--work", "r9572"]] if dispatch else []
    for argv in steps:
        assert w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])[1] == 0
    path = w.runtime() / "journal.jsonl"
    rows = [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines()]
    for rec in rows:
        if rec["kind"] == "accept" and rec["work"] in ("d1", "d2"):
            rec["work"] = DICT_WORK[int(rec["work"][1]) - 1]
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    w.t = datetime.datetime.strptime(kw.NOW, "%Y-%m-%dT%H:%M:%S").timestamp() + 7200


def c25_only(w):
    k = w.keeper()
    k.unknown = 0
    try:
        k.accept_only(TEAM, w.journal())
    except TypeError as exc:   # 기준판 = dict 를 set 원소로 씀
        raise AssertionError("accept_only 예외 %r" % exc)
    return [x for x in k.lines if x.startswith("UNKNOWN")]


def c25a(w):   # ㉕가 dict-work accept 2 + str-work accept-only 1 + 다른 work dispatch 1 → 예외 0 · UNKNOWN accept-only = str work 1건만
    c25_journal(w)
    got = c25_only(w)
    assert len(got) == 1 and got[0].startswith("UNKNOWN harness r9570 - accept-only"), got


def c25b(w):   # ㉕나 dispatch 0 · dict-work accept 만 → 예외 0 · UNKNOWN 0 · [긴급] 0
    c25_journal(w, str_work=False, dispatch=False)
    assert c25_only(w) == [] and not [x for x in sent(w) if "[긴급]" in x], sent(w)


def c25c(w):   # ㉕다 같은 journal 로 keeper 한 바퀴(team_round 경유) → 끝까지 감 · 다른 판정 줄 = dict-work 줄 없을 때와 같음
    c25_journal(w)
    lines = rnd(w)
    with pytest.MonkeyPatch.context() as mp:   # 대조 세계(dict-work 줄 0 · 나머지 같음)
        base = world(w.tmp / "base", mp)
        c25_journal(base, dict_work=False)
        want = rnd(base)
    pick = lambda xs: [x for x in xs if x.split()[0] in ("UNKNOWN", "WORKING", "PARKED", "LANDED", "COMPLETED", "ROUND") or x.startswith("CLOSED")]   # noqa: E731
    assert pick(lines) == pick(want) and has(lines, "UNKNOWN harness r9570 - accept-only"), (lines, want)


def c12(w):   # ⑫ intent failed · 세션 부재 · owner 있음 → park(launch-failed) · 새 attempt
    c3(w, "failed")


def c17(w, case):   # ⑰ 장기 좌석 끝남 근거 ↔ 닫기 자격(hil.md 보존)
    b = "byz-harness-arch-pi#"
    roster = {"_master": "M-harness"}
    alive, ready, resume, closed = {"가": ([10, 11], [(11, 10)], [], ()), "나": ([10, 11], [(11, 10)], [10], ()),
                                    "다": ([9, 10, 11], [(10, 9), (11, 10)], [], ()), "라": ([5], [], [], (5,)),
                                    "마": ([10, 11], [], [], ()), "바": ([7], [], [], ())}[case]
    for n in alive:
        roster[b + str(n)] = {"role": "stop-ready"}
    (w.tmp / "comm").mkdir(exist_ok=True)
    for new, old in ready:
        roster[b + str(old)]["_replaced_by"] = b + str(new)
        with open(w.tmp / "comm" / "mailbox.log.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"from": b + str(new), "to": b + str(old), "body": "[레디] %s%d <- %s%d · 항목 1" % (b, new, b, old)}, ensure_ascii=False) + "\n")
    if case == "마":
        roster[b + "10"]["_replaced_by"] = b + "11"
    for n in resume:   # r2055 R2 검증된 재개 기록 = 실제 세션 파일 결속
        w.resume(b + str(n))
    kw._put(w.root / ".fable-team" / "seats-harness.json", roster)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"] = [b + str(n) for n in alive]
    kw._put(w.tm, d)
    i = kw.TMUX.replace("__PY__", sys.executable)
    kw._put(w.tmp / "bin" / "tmux", i[:i.index('if a[0] == "kill-session"')] + LS + i[i.index('if a[0] == "kill-session"'):])
    k = w.keeper()
    k.closed_seats = lambda: {b + str(n) for n in closed}
    k.pane_info, k.ps_rows = (lambda seat: (100, "zsh")), (lambda: [(p, pp, c or 0.0, n) for p, pp, c, n in CHAIN])   # 1차 = clean ∧ pane_pid ∧ ps ∧ 세션 파일
    lines = w.round(k)
    shut = [x.split()[0] for x in kw._lines(str(w.close) + ".log")]
    want = {"가": [], "나": [b + "10"], "다": [b + "9"], "라": [], "마": [], "바": []}[case]
    code = {"가": "keep-last-2", "나": None, "다": "keep-last-2", "라": "keep-recent", "마": "ready-wait", "바": "long-seat"}[case]
    assert shut == want, (case, shut, lines)
    assert code is None or has(lines, "WORKING harness", code), (case, lines)


def c18(w):   # ⑱ 명부 밖 byz-* = UNKNOWN roster-outside · 이름 lint 실패 = name-bad · 1차 shell-only·쉼 ∧ kill 직전 pane Working = tmuxc-mismatch · kill 0
    holder = nano(w, "r9563", age=7200, pane="✻ done\n⠋ Working (2s)\n❯ ")
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"] += ["byz-harness-ghost-pi#3", "byz-harness-Bad Name"]
    kw._put(w.tm, d)
    i = kw.TMUX.replace("__PY__", sys.executable)
    kw._put(w.tmp / "bin" / "tmux", i[:i.index('if a[0] == "kill-session"')] + LS + i[i.index('if a[0] == "kill-session"'):])
    lines = rnd(w, cmd="zsh", clean=holder + "\n")   # 판독원 = 기본 실행(tmuxc clean 대역 · 주입 0)
    assert has(lines, "UNKNOWN harness - byz-harness-ghost-pi#3 roster-outside"), lines
    assert has(lines, "UNKNOWN harness - byz-harness-Bad Name name-bad"), lines
    assert has(lines, "UNKNOWN harness r9563", "tmuxc-mismatch") and not w.tmux("kill-session"), lines


def c19(w):   # ⑲ pane 명령 zsh(shell-only) · clean · push → PARKED · 같은 꼴 dirty → UNKNOWN shell-only-unsafe · 둘 다 WORKING 아님
    nano(w, "r9564")
    nano(w, "r9565", dirty=True)
    lines = rnd(w, cmd="zsh")
    assert has(lines, "PARKED harness r9564", "shell-only") and has(lines, "UNKNOWN harness r9565", "shell-only-unsafe"), lines
    assert not has(lines, "WORKING harness r956") and len(w.tmux("kill-session")) == 1


def c20(w):   # ⑳ tmuxc 대조 — 사슬 끝(pane → npm → node → pi) %cpu 0.5 = busy · 0.1 ×2(30초) = idle · 셸 목록·깊이 = tmuxc 규칙
    k = w.keeper()
    k.ps_rows = lambda: [(p, pp, 0.5 if c is None else c, n) for p, pp, c, n in CHAIN]
    assert k.cpu("s", (100, "npm")) == "busy"
    k.ps_rows = lambda: [(p, pp, 0.1 if c is None else c, n) for p, pp, c, n in CHAIN]
    assert k.cpu("s", (100, "npm")) == "pending"
    w.t += 30
    assert k.cpu("s", (100, "npm")) == "idle"
    S = kw._mod(w.ft2 / "adapters" / "pi" / "keeper_settle.py", "settle_r2055_%d" % id(w))
    tool = Path(os.path.expanduser("~/.local/bin/tmuxc"))
    if tool.exists():   # tmuxc 정본(읽기만) — cmd_clean 셸 목록 · pane_descendant_pids 깊이
        text = tool.read_text(encoding="utf-8", errors="replace")
        line = next(x for x in text.splitlines() if '"$command" == "zsh"' in x)
        assert set(S.SHELLS) == {x.split('"')[0] for x in line.split('== "')[1:]} and '"$depth" -lt %d' % S.CPU_DEPTH in text
    table = {"s1": "zsh", "s2": "pi", "s3": "bash", "s4": "fish", "s5": "node"}
    assert {s for s, c in table.items() if os.path.basename(c) in S.SHELLS} == {"s1", "s3", "s4"}


CASES = {"①": c1, "②": c2, "②′": c2b, "③": c3, "④": c4, "④′": c4b, "⑤": c5, "⑥": c6, "⑦": c7, "⑨": c9, "⑩": c10, "⑪": c11,
         "⑫": c12, "⑱": c18, "⑲": c19, "⑳": c20, "㉕가": c25a, "㉕나": c25b, "㉕다": c25c}
CASES.update({"⑰" + c: (lambda c: lambda w: c17(w, c))(c) for c in "가나다라마바"})
KS = "adapters/pi/keeper_settle.py"
MUTANTS = {"M3": ('and age >= WAIT_S and cpu == "idle" and idle_s == PARK_IDLE:', "and age >= WAIT_S and False:", c9),
           "M4": ("    for _ in range(depth):", "    for _ in range(2):", c20),
           "M5": ('idle = age is not None and age >= idle_s and (shell or cpu == "idle")', 'idle = (shell or cpu == "idle")', c6),
           "M6": ('and isinstance(rec.get("work"), str) and rec["work"] not in sent', 'and rec.get("work") and rec["work"] not in sent', c25a)}   # ㉕ str 가드


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(world(tmp_path / "w1", monkeypatch, tree))
    case(world(tmp_path / "w2", monkeypatch))
