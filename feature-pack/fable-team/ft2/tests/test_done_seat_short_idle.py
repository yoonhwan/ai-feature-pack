"""카드 ft2-done-seat-short-idle — 착지한 좌석은 무활동 300초에 닫히고, «닫힌 꼴 마감 쪽지» 만 쉼 판정에서 뺀다.

설계 = `design/DESIGN-pA-done-idle-threshold-20261116.md` r4(DA 대행 APPROVE · BYZ 310212). 계약 A1~A9.
사례 ㉙가~저(26) · 변이 M20 · M21 · M22 · M44 · M45 · M51~M55.
대역 = r1812 keeper_world(임시 root · 두 ref · 가짜 tmux · 가짜 tmuxc·ps) + 실 임시 nano worktree(clone · push) + 가짜 mbox(peek --rows = 머리줄 + JSON 줄)
· ps·pane 표 = keeper 인스턴스 주입 · sleep 0(시계 = 주입 w.t) · 실 tmux·실 runtime·실 명부·실 우편함 쓰기 0.
기준판(팩 origin/main cd0bd9ee) Red = ㉙가 · ㉙아 · ㉙마 · ㉙너 · ㉙서(첫 줄) — 나머지 21 사례는 지킴·양성 회귀.
"""
import datetime
import importlib.util
import json
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_world_pA", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
FT2, T0, TEAM, IDLE_PANE = kw.FT2, kw.T0, kw.TEAM, "✻ Brewed for 3s\n❯ "
KS, KC = "adapters/pi/keeper_settle.py", "adapters/pi/keeper_close.py"
MBOX = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\n'
        'if [ "$1" = peek ]; then\n'
        '  if [ -f "$0.peekrc" ]; then exit "$(cat "$0.peekrc")"; fi\n'
        '  if [ -f "$0.head" ]; then cat "$0.head"; else echo "pending=0 scanned=1 lineage=0"; fi\n'
        '  if [ -f "$0.rows" ]; then cat "$0.rows"; fi\n'
        '  exit 0\nfi\n'
        'echo "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n')
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
         body=None, done=False, branch=None, num=0):
    """나노 1석 = 접수 → 배정 → 전달 · 실 worktree(clone · 가지 커밋 · push) · intent · Pi jsonl(mtime = 시계 − age)."""
    holder, res = "byz-%s-nano-%s#%d" % (TEAM, work, num), res or "R-" + work
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


def landed(w, work, num=0, **kv):
    """착지 참 — 팩 origin/main 카드(팀 폴더 진행)에 «- 착지: <sha>» 줄 · sha = 팩 main 커밋(조상)."""
    w.card(work, sha=w.pack_sha(), stage="진행")
    return nano(w, work, num=num, **kv)


def at(w, mins):
    return datetime.datetime.fromtimestamp(w.t - mins * 60).strftime("%Y-%m-%dT%H:%M:%S")


def mail(w, seat, msgs=(), pending=None, rc=None):
    """가짜 mbox `peek --rows` 대역 — msgs (seq, 분 전, from, body[, to]) · pending 기본 = len(msgs) · rc = 판독 실패
    · pending>0 ∧ 줄 0 = 옛 mbox(--rows 모름) · pending≠줄 수 = 새 mbox 의 깨진 출력."""
    rows = []
    for m in msgs:
        seq, mins, frm, body = m[:4]
        rows.append(json.dumps({"seq": seq, "ts": at(w, mins), "to": m[4] if len(m) > 4 else seat,
                                "from": frm, "body": body}, ensure_ascii=False))
    kw._put(str(w.mbox) + ".head", "pending=%d scanned=1 lineage=0\n" % (len(rows) if pending is None else pending))
    kw._put(str(w.mbox) + ".rows", "".join(x + "\n" for x in rows))
    Path(str(w.mbox) + (".peekrc" if rc is not None else ".peekrc")).unlink(missing_ok=True)
    if rc is not None:
        kw._put(str(w.mbox) + ".peekrc", str(rc))


def rnd(w, cmd="pi", cpu=0.0, dt=0, clean=None):
    """한 바퀴 — 시계 dt 초 전진 · pane 명령·ps 표(사슬 끝 %cpu) 주입 · tmuxc clean 대역 · 반환 = 로그 줄."""
    w.t += dt
    alive = json.loads(w.tm.read_text(encoding="utf-8"))["alive"]
    shells = alive if os.path.basename(cmd) in ("zsh", "bash", "fish") else []
    kw._put(str(w.tm) + ".clean", "".join(x + "\n" for x in shells) if clean is None else clean)
    k = w.keeper()
    k.pane_info = lambda seat: (100, cmd)
    k.ps_rows = lambda: [(p, pp, cpu if c is None else c, n) for p, pp, c, n in CHAIN]
    return w.round(k)


def two(w, **kv):
    """CPU idle 판정 = 표본 2개 · 간격 30초."""
    return rnd(w, **kv) + rnd(w, dt=30, **kv)


def has(lines, *words):
    return [x for x in lines if all(word in x for word in words)]


def calls(w, verb):
    return [x for x in kw._lines(str(w.mbox) + ".log") if x.split()[:1] == [verb]]


def queue(w):
    return len([x for x in kw._lines(str(w.mbox) + ".rows") if x.strip()])


MASTER, OTHER = "M-harness", "byz-harness-nano-r9899#0"


def park_ready(w, work, age=3660):
    """착지 0 · 유휴 ≥ PARK_IDLE · clean · push — 쉼 판정까지 가는 기본 꼴(㉙마 가족)."""
    w.card(work, stage="진행")
    return nano(w, work, age=age)


def blocked(w, work, msgs, **kv):
    """㉙ 거른 사례 공통 — 착지 0 · 61분 · 미읽음 = msgs → UNKNOWN mail-pending · 닫기 0 · 쉼 0."""
    holder = park_ready(w, work)
    mail(w, holder, msgs, **kv)
    lines = two(w)
    assert has(lines, "UNKNOWN harness %s" % work, "mail-pending"), lines
    assert not w.tmux("kill-session") and w.kinds("parked") == 0, lines
    return lines


def c29a(w):   # ㉙가 착지 참 · stop · 무활동 6분 · CPU idle ×2 · 쪽지 0 → complete 1 · 닫기 1
    landed(w, "r9801", age=360)
    lines = two(w)
    assert has(lines, "COMPLETED harness r9801"), lines
    assert len(w.tmux("kill-session")) == 1 and w.kinds("complete") == 1, lines


def c29b(w):   # ㉙나 착지 참 · 마지막 줄 toolUse · 6분 → WORKING landed-wait · 닫기 0(턴이 안 닫혔으면 일하는 중)
    landed(w, "r9803", age=360, turn="toolUse")
    lines = two(w)
    assert has(lines, "WORKING harness r9803", "landed-wait"), lines
    assert not w.tmux("kill-session") and w.kinds("complete") == 0, lines


def c29c(w):   # ㉙다 착지 참 · stop · 4분(문턱 안) → WORKING landed-wait · 닫기 0
    landed(w, "r9804", age=240)
    lines = rnd(w) + rnd(w, dt=30)
    assert has(lines, "WORKING harness r9804", "landed-wait"), lines
    assert not w.tmux("kill-session") and w.kinds("complete") == 0, lines


def c29d(w):   # ㉙라 착지 참 · stop · 6분 · CPU busy → WORKING · 닫기 0
    landed(w, "r9805", age=360)
    lines = two(w, cpu=0.5)
    assert has(lines, "WORKING harness r9805", "cpu-busy"), lines
    assert not w.tmux("kill-session") and w.kinds("complete") == 0, lines


def c29e(w):   # ㉙마 착지 0 · stop · 61분 · 미읽음 `[마감 #N] 할 일 0`(75분 · _master) → PARKED idle-done · 꼬리 제외 1통 · 큐 그대로
    holder = park_ready(w, "r9808")
    mail(w, holder, [(3201, 75, MASTER, "[마감 #3200] 할 일 0")])
    lines = two(w)
    assert has(lines, "PARKED harness r9808", "idle-done", "미읽음 마감 1통 제외"), lines
    assert len(w.tmux("kill-session")) == 1 and queue(w) == 1, lines
    assert not calls(w, "mark") and not calls(w, "recv"), kw._lines(str(w.mbox) + ".log")


def c29f(w):   # ㉙바 착지 0 · stop · 6분(문턱 안) → WORKING · 닫기 0 · park 0(짧은 문턱은 착지 좌석만)
    park_ready(w, "r9806", age=360)
    lines = two(w)
    assert has(lines, "WORKING harness r9806") and not w.tmux("kill-session") and w.kinds("parked") == 0, lines


def c29g(w):   # ㉙사 착지 0 · stop · 61분 → PARKED idle-done(지금 그대로)
    park_ready(w, "r9807")
    lines = two(w)
    assert has(lines, "PARKED harness r9807", "idle-done") and len(w.tmux("kill-session")) == 1, lines


def c29h(w):   # ㉙아 착지 참 · 셸만 남은 pane · 6분 → complete 1 · 닫기 1(셸은 CPU 무관 · 문턱만 300초)
    landed(w, "r9802", age=360)
    lines = rnd(w, cmd="zsh")
    assert has(lines, "COMPLETED harness r9802"), lines
    assert len(w.tmux("kill-session")) == 1 and w.kinds("complete") == 1, lines


def c29i(w):   # ㉙자 미읽음 = [긴급] 75분 → UNKNOWN mail-pending · 닫기 0
    blocked(w, "r9809", [(3210, 75, MASTER, "[긴급] r9809 확인 부탁드립니다")])


def c29j(w):   # ㉙차 미읽음 = [발주] 75분 → UNKNOWN mail-pending
    blocked(w, "r9810", [(3211, 75, MASTER, "[발주 #3210] 이어서 확인해 주세요")])


def c29k(w):   # ㉙카 미읽음 1통 2줄(첫 줄 닫힌 꼴 + 둘째 줄 [발주]) → UNKNOWN mail-pending(줄 전체가 안 맞으면 막는다)
    blocked(w, "r9811", [(3212, 75, MASTER, "[마감 #3211] 할 일 0\n[발주] 이어서 확인")])


def c29l(w):   # ㉙타 닫힌 꼴 10분 전(문턱 60분 안쪽) → UNKNOWN mail-pending
    blocked(w, "r9812", [(3214, 10, MASTER, "[마감 #3213] 할 일 0")])


def c29m(w):   # ㉙파 미읽음 2통 = 닫힌 꼴 75분 + [발주] 70분 → UNKNOWN mail-pending
    blocked(w, "r9813", [(3215, 75, MASTER, "[마감 #3214] 할 일 0"), (3216, 70, MASTER, "[발주] 검증 실패 건")])


def c29n(w):   # ㉙하 머리 없는 글 75분 → UNKNOWN mail-pending
    blocked(w, "r9814", [(3217, 75, MASTER, "확인 부탁드립니다. 실패 테스트가 남아 있습니다.")])


def c29o(w):   # ㉙거 peek 못 읽음(rc 2) → UNKNOWN mail-unknown(지금과 같음)
    holder = park_ready(w, "r9815")
    mail(w, holder, [(3218, 75, MASTER, "[마감 #3217] 할 일 0")], rc=2)
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9815", "mail-unknown"), lines
    assert not w.tmux("kill-session") and w.kinds("parked") == 0, lines


def c29p(w):   # ㉙너 착지 참 · 6분 · `[마감] 할 일 0 · 착지 4ccf2a6` + 골좌표 줄(7분) → complete 1 · 닫기 1 · 꼬리 제외 1통
    holder = landed(w, "r9816", age=360)
    mail(w, holder, [(3219, 7, MASTER, "[마감] 할 일 0 · 착지 4ccf2a6\n골좌표: 하네스 GOAL 표 — 이 줄은 빈 줄·골좌표 줄이라 빼고 센다")])
    lines = two(w)
    assert has(lines, "CLOSED-SESSION harness r9816", "미읽음 마감 1통 제외"), lines
    assert len(w.tmux("kill-session")) == 1 and w.kinds("complete") == 1, lines
    assert queue(w) == 1, kw._lines(str(w.mbox) + ".rows")


def c29q(w):   # ㉙더 착지 참 · 6분 · 닫힌 꼴 2분 전(짧은 문턱 안쪽) → 닫기 0
    holder = landed(w, "r9817", age=360)
    mail(w, holder, [(3220, 2, MASTER, "[마감] 할 일 0")])
    lines = two(w)
    assert not w.tmux("kill-session") and w.kinds("complete") == 0, lines


def c29r(w):   # ㉙러 4줄(첫 줄 닫힌 꼴 · 4번째 줄 [긴급][발주]) → UNKNOWN mail-pending · 닫기 0 · 쉼 0
    blocked(w, "r9818", [(3221, 75, MASTER, "[마감 #3220] 할 일 0\n앞 보고는 받았습니다.\n아래를 확인 바랍니다.\n[긴급][발주] 검증 실패 건")])


def c29s(w):   # ㉙머 DA 입력 2개(자유 글 답장 — «할 일 0» 이 들어 있어도 줄 전체가 안 맞음) → 둘 다 UNKNOWN mail-pending
    for i, body in enumerate(("[답 #3221] 수정안 승인합니다. 실패 테스트를 고친 뒤 다시 보고하세요.",
                              "[답 #3221] 할 일 0이 아닙니다. 실패 테스트를 수정해 주세요.")):
        lines = blocked(w, "r981%d" % (9 + i), [(3222 + i, 75, MASTER, body)])
        assert not has(lines, "PARKED harness r981%d" % (9 + i)), lines


def c29t(w):   # ㉙버 현역 seat#1 · 큐에 to = seat#0(옛 이름) [발주] 1통 + 자기 몫 닫힌 꼴 1통 → peek pending 2 = 판독 2통 · UNKNOWN mail-pending
    w.card("r9821", stage="진행")
    holder = nano(w, "r9821", age=3660, num=1)   # 현역 = seat#1(옛 이름 seat#0 이 큐에 남은 꼴) · 착지 0 · 61분
    old = holder[:-2] + "#0"
    mail(w, holder, [(3224, 75, MASTER, "[발주 #3223] 옛 이름 앞으로 온 발주", old), (3225, 76, MASTER, "[마감 #3222] 할 일 0")])
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9821", "mail-pending"), lines
    assert not has(lines, "mail-unknown") and not w.tmux("kill-session"), lines
    assert queue(w) == 2, kw._lines(str(w.mbox) + ".rows")


def c29u(w):   # ㉙서 줄 수 ≠ pending(2 vs 1) → UNKNOWN mail-unknown · 옛 mbox(줄 0 · pending 1) → mail-pending
    holder = park_ready(w, "r9822")
    mail(w, holder, [(3226, 75, MASTER, "[마감 #3225] 할 일 0")], pending=2)
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9822", "mail-unknown"), lines
    assert not w.tmux("kill-session") and w.kinds("parked") == 0, lines
    mail(w, holder, [(3226, 75, MASTER, "[마감 #3225] 할 일 0")])
    kw._put(str(w.mbox) + ".rows", "")   # 옛 mbox(--rows 모름) = 머리줄만 · pending 1
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9822", "mail-pending"), lines


def c29v(w):   # ㉙어 자유 글 답장 `[답 #N] 확인했습니다.` → UNKNOWN mail-pending
    blocked(w, "r9823", [(3227, 75, MASTER, "[답 #3226] 확인했습니다.")])


def c29w(w):   # ㉙저 `[답 #N] 할 일 0 은 아니고 실패 테스트를 고친 뒤 다시 보고하세요.` → UNKNOWN mail-pending
    blocked(w, "r9824", [(3228, 75, MASTER, "[답 #3227] 할 일 0 은 아니고 실패 테스트를 고친 뒤 다시 보고하세요.")])


def c29x(w):   # ㉙고 보낸 이가 역할 칸 좌석이 아님(다른 나노) → UNKNOWN mail-pending · 명부 못 읽음도 막는다
    blocked(w, "r9825", [(3229, 75, OTHER, "[마감 #3228] 할 일 0")])
    holder = park_ready(w, "r9826")
    mail(w, holder, [(3230, 75, MASTER, "[마감 #3229] 할 일 0")])
    kw._put(w.root / ".fable-team" / "seats-harness.json", "{깨짐")   # 명부 못 읽음 = 막는다
    lines = two(w)
    assert has(lines, "UNKNOWN harness r9826", "mail-pending"), lines
    assert w.kinds("parked") == 0, lines


def c29y(w):   # ㉙노 r2057 실사건 원문(자유 글 답장 · 옛 착지 줄) → UNKNOWN mail-pending(치르는 값 그대로 고정)
    body = ("[답 #309389] 확인 고마워 · 보고 잘 받았다. 남은 일 0 = 카드 «남은 범위» 줄은 네가 채운 그대로 "
            "마감하고 대기 · 좌석 닫기는 keeper 가 함(손 kill 0) · 옛 착지 줄(attempt 전) 4ccf2a67")
    blocked(w, "r2057-test", [(309395, 75, MASTER, body)])


def c29huh(w):   # ㉙허 `[마감 #N] 할 일 0이 아닙니다`(줄 전체가 안 맞음) → UNKNOWN mail-pending
    blocked(w, "r9827", [(3231, 75, MASTER, "[마감 #3230] 할 일 0이 아닙니다")])


CASES = {"㉙가": c29a, "㉙나": c29b, "㉙다": c29c, "㉙라": c29d, "㉙마": c29e, "㉙바": c29f, "㉙사": c29g, "㉙아": c29h,
         "㉙자": c29i, "㉙차": c29j, "㉙카": c29k, "㉙타": c29l, "㉙파": c29m, "㉙하": c29n, "㉙거": c29o, "㉙너": c29p,
         "㉙더": c29q, "㉙러": c29r, "㉙머": c29s, "㉙버": c29t, "㉙서": c29u, "㉙어": c29v, "㉙저": c29w, "㉙고": c29x,
         "㉙노": c29y, "㉙허": c29huh}

MUTANTS = {
    "M20": (KC, 'wait="landed-wait", idle_s=settle.DONE_IDLE', 'wait="landed-wait"', [c29a, c29h]),   # land_ready 가 DONE_IDLE 을 안 넘김
    "M21": (KS, 'if not shell and stop != "stop":', 'if not shell and stop != "stop" and idle_s == PARK_IDLE:', [c29b]),   # 짧은 문턱에서 stop 검사 제거
    "M22": (KS, 'got = self.look(team, work, attempt, holder, *self.pi_turn(intent))',
            'got = self.look(team, work, attempt, holder, *self.pi_turn(intent), idle_s=DONE_IDLE)', [c29f]),   # park 길에도 DONE_IDLE
    "M44": (KS, 'if not isinstance(doc, dict) or not isinstance(doc.get("body"), str):',
            'if not isinstance(doc, dict) or not isinstance(doc.get("body"), str) or doc.get("to") != seat:', [c29t]),   # to 글자 일치
    "M45": (KS, '        if len(docs) != n:\n            return n, [], "mail-unknown"\n', '', [c29u]),   # 줄 수 ↔ pending 대조 제거
    "M51": (KS, '        return len(lines) == 1 and bool(CLOSED_MAIL.match(lines[0]))',
            '        return "할 일 0" in str(body or "")', [c29s, c29huh]),
    "M52": (KS, '        return len(lines) == 1 and bool(CLOSED_MAIL.match(lines[0]))',
            '        return bool(lines) and bool(CLOSED_MAIL.match(lines[0]))', [c29r, c29k]),   # 첫 줄만 봄
    "M53": (KS, ' or not senders or doc.get("from") not in senders', '', [c29x]),   # 보낸 이 조건 제거
    "M54": (KS, 'not in senders or age < idle_s', 'not in senders', [c29l, c29q]),   # 나이 조건 제거
    "M55": (KS, '        n, docs, bad = self.mail_rows(seat, rows_first=idle_s != PARK_IDLE)\n        if bad:\n            return bad, ""',
            '        n, docs, bad = self.mail_rows(seat)\n        if bad or docs:\n            return bad or "mail-pending", ""', [c29e, c29p]),   # 미읽음 1통이라도 막음(지금 길)
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    """변이 사본 = 잡는 사례가 FAIL · 원본 사본 = 같은 사례 PASS(양성)."""
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old, text.count(old))
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        (tmp_path / ("f%d" % i)).mkdir(exist_ok=True)
        with pytest.raises(AssertionError):
            case(world(tmp_path / ("f%d" % i), monkeypatch, tree))
    (tmp_path / "ok").mkdir(exist_ok=True)
    cases[0](world(tmp_path / "ok", monkeypatch))
