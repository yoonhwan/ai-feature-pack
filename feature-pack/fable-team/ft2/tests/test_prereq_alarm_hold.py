"""ft2 keeper 선행 줄 쪽지 — 멈춘 팀·팀장 없는 팀에는 가지 않고, 풀리면 전체 목록이 한 번에
(카드 ft2-prereq-alarm-hold · ㊵가~더 18칸 + 변이 M85~M91).

계약 = `contracts/keeper-settle/CONTRACT.md` §선행불명 로그·쪽지(P1~P8) · 설계 = 카드 «계약»·«반례 표».
「실제 fill 길」·「실제 닫기 뒤 고르기 길」 칸 = keeper_next.fill · keeper_next.close 를 부르고 prereq_tell 호출 수를 센다
(prereq_tell 을 직접 부르는 칸 = 함수 단위 방어 ㊵라·㊵하·㊵너 뿐).
대역 = r1871 세계(임시 root·git·가짜 tmux·launch·record·mbox) + 주입 시계 · 실 tmux·명부·우편함·설치 0 · sleep 0 · 사례 하나 70초 안.
기준판(팩 origin/main c4b78196) = ㊵다·㊵라·㊵마·㊵바·㊵사·㊵아·㊵차·㊵카·㊵타·㊵파·㊵하·㊵거·㊵너 Red,
㊵가·㊵나·㊵러·㊵자·㊵더 = 회귀 고정(Green).
"""
import importlib.util, json, os, re, shutil, sys  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pu = _mod("prereq_hold_prev", HERE / "test_prereq_unreadable_once.py")   # 앞 카드 시험(세계·put·plume) 그대로 쓴다
base, kw = pu.base, pu.kw
TEAM, KN, ROOT, FIX = pu.TEAM, pu.KN, pu.ROOT, pu.FIX
PLAIN, OTHER, PLAIN2, PLAIN3, PLAIN4 = pu.PLAIN, pu.OTHER, pu.PLAIN2, pu.PLAIN3, pu.PLAIN4
PLAN = "planner"   # 팀장 없는 팀 대역(대신 받는 곳 = _desk · harness master)
P, Q, R, S, T = "r9201-plain", "r9202-plain", "r9203-plain", "r9204-plain", "r9205-plain"
WAIT = "PREREQ-WAIT"


def world(tmp, mp, cards=None, cap="4", ft2=kw.FT2, prep=None):
    """r1871 세계(임시 root·git·가짜 tmux·launch·record) + 첫 바퀴 = 닫을 일 1장(닫기 영수 자리 = choose 가 불리는 길).
    prep = 표식 놓는 자리(첫 바퀴 «전» · 실제 설치 상태와 같다) · cards = 대기 카드 {stem: 머리 줄}."""
    Path(tmp).mkdir(parents=True, exist_ok=True)
    w = kw.World(tmp, mp, ft2)
    b, tm = tmp / "bin", kw.TMUX.replace("__PY__", sys.executable)
    i = tm.index('if a[0] == "kill-session"')
    kw._put(b / "tmux", tm[:i] + base.LS + tm[i:])
    kw._put(b / "launch.py", base.LAUNCH), kw._put(b / "record", base.RECORD)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"),
                 FT2_TEAM_NANO_MAX=cap, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n")
    if cards:
        w.commit("byz", {"design/harness/indices/대기/%s.md" % s: "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h) for s, h in cards.items()}, "main")
    w.enable()
    if prep:
        prep(w)
    base.close(w, base.W1)
    return base.settle(w)


def mkf(mp, ft2=kw.FT2):
    """사례가 세계를 만드는 문 — 변이는 ft2 사본으로 같은 사례를 돈다."""
    return lambda path, cards, cap="4", prep=None: world(path, mp, cards, cap=cap, ft2=ft2, prep=prep)


def hold(w, reason="배포 중"):
    kw._put(w.state / "NEW_CARD_HOLD.json", {"reason": reason, "until": "-"})


def unhold(w):
    (w.state / "NEW_CARD_HOLD.json").unlink()


def pause(w, team=TEAM):
    kw._put(w.state / (team + "-tick") / "PAUSED", "")


def allstop(w):
    kw._put(w.state / "ALL_STOP.json", {"reason": "전팀 정지"})


def run_round(w, mp=None):
    """한 바퀴 = keeper 를 새로 만들어 돌리고 prereq_tell 호출 수를 센다(그 keeper 가 쓰는 그 모듈 하나)."""
    K = w.K
    kn = K.closing.keeper_next
    orig, calls = kn.prereq_tell, []

    def spy(k, team, unread, _orig=orig, _calls=calls):
        _calls.append((team, sorted(unread)))
        return _orig(k, team, unread)
    kn.prereq_tell = spy
    try:
        w.round(K.Keeper(str(w.root), env=w.env, now=lambda: w.t))
    finally:
        kn.prereq_tell = orig
    return calls


def kstate(w):
    p = w.state / "ft2-keeper" / "state.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def told(w, team=TEAM):
    return kstate(w).get("prereq_told", {}).get(team)


def nows(w, team=TEAM):
    return kstate(w).get("prereq_now", {}).get(team) or {}


def waiting(w, team=TEAM):
    return kstate(w).get("prereq_wait", {}).get(team)


def lpath(w, team=TEAM):
    return w.state / "ft2-keeper" / ("prereq-%s.txt" % team)


def rows(w, team=TEAM):
    return kw._lines(str(lpath(w, team)))


def mails(w):
    """가짜 mbox 가 받은 [다음 막힘] 줄(받는 곳·본문 그대로)."""
    return pu.hits(w, "[다음 막힘]")


def lines(w, mark):
    """keeper 로그 파일의 그 표식 줄 — 인스턴스와 무관(바퀴마다 새 keeper 여도 같은 수)."""
    return [json.loads(x)["line"] for p in sorted((w.state / "ft2-keeper").glob("*.jsonl")) for x in kw._lines(p) if mark in x]


def team_on(w, team=PLAN, master="", desk=""):
    """팀 1개를 켠다 — ft20-switch·runtime·CLOSE-NEXT·명부·카드 루트 표 행(실제 조건 그대로 · 팀장 칸은 인자 그대로)."""
    kw._put(w.state / "ft20-switch" / (team + ".json"), "{}")
    (w.root / ".fable-team" / "teams" / team / "runtime").mkdir(parents=True, exist_ok=True)
    w.enable(team)
    kw._put(w.root / ".fable-team" / ("seats-%s.json" % team), {"_master": master, "_desk": desk})
    with open(w.state / "directive-roots.tsv", "a", encoding="utf-8") as fh:
        fh.write("%s\t.\torigin/main\tdesign/%s/indices\n" % (team, team))


def put_team(w, team, stem, head, stage="대기"):
    w.commit("byz", {"design/%s/indices/%s/%s.md" % (team, stage, stem): "# 인덱스: %s\n%s- 상태: 대기\n" % (stem, head)}, "main")


def unit(w, unread, team=TEAM, halt=None):
    """함수 단위 방어 — prereq_tell 을 직접 부른다(실제 길 증거로 세지 않는다) · keeper 상태 파일은 그대로 읽는다."""
    k = w.K.Keeper(str(w.root), env=w.env, now=lambda: w.t)
    k.state.update(k.read_json(os.path.join(k.dir, "state.json")))
    k.halt = k.stopped() if halt else False
    w.K.closing.keeper_next.prereq_tell(k, team, unread)
    return k


UN2 = {P: {"val": "다른 글 착지 완료", "why": "번호 참조 없음"}}


def c_ga(tmp, mp, mk):   # ㊵가 실제 fill 길 · NEW_CARD_HOLD 있음 · 선행불명 2장 · 두 바퀴 → 쪽지 0 · 호출 0 · 기억·파일 손 0
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=hold)
    calls = run_round(w) + run_round(w)
    assert calls == [], calls
    assert mails(w) == [], mails(w)
    assert nows(w) == {} and told(w) is None and not lpath(w).exists(), kstate(w)
    assert len(lines(w, "NEW-CARD-HOLD")) == 1, lines(w, "NEW-CARD-HOLD")


def c_na(tmp, mp, mk):   # ㊵나 실제 fill 길 · 팀 PAUSED 있음 · 선행불명 2장 → 쪽지 0 · 기억·파일 손 0
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=pause)
    calls = run_round(w)
    assert calls == [] and mails(w) == [] and nows(w) == {} and told(w) is None and not lpath(w).exists(), (calls, mails(w))


def c_da(tmp, mp, mk):   # ㊵다 ALL_STOP 중 · 닫기 뒤 고르기 길로 choose 가 불림(세션 없음) · 선행불명 2장 → 쪽지 0 · told 없음
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=allstop)
    calls = run_round(w)
    assert calls and calls[0][0] == TEAM, calls          # choose 는 실제로 불렸다(그 자리에서 막는지 본다)
    assert mails(w) == [] and told(w) is None, (mails(w), kstate(w))


def c_la(tmp, mp, mk):   # ㊵라 함수 단위 방어 — 세 표식을 하나씩 켠 3칸: 쪽지 0 · told 그대로 · now·목록 파일은 고쳐짐
    for name in ("halt", "paused", "hold"):
        w = mk(tmp / name, {P: PLAIN})
        run_round(w)
        assert len(mails(w)) == 1, (name, mails(w))
        before, one = told(w), rows(w)
        assert before and len(one) == 2, (name, before, one)
        if name == "halt":
            allstop(w)
        elif name == "paused":
            pause(w)
        else:
            hold(w)
        k = unit(w, UN2, halt=name == "halt")   # 전팀 정지 판독 = keeper 바퀴와 같은 함수(k.stopped)
        assert len(mails(w)) == 1, (name, mails(w))                                       # 묵음 = 쪽지 0
        assert k.state["prereq_told"].get(TEAM) == before, (name, k.state["prereq_told"])   # told 그대로
        assert k.state["prereq_now"][TEAM]["fp"] != before, name                           # now 는 고쳐짐
        assert rows(w)[0].startswith("# 관측 ") and "다른 글 착지 완료" in rows(w)[1], (name, rows(w))


def c_ma(tmp, mp, mk):   # ㊵마 실제 fill 길 · ㊵가 뒤 표식 파일을 지움 → 첫 fill 바퀴 1통 · 그 다음 0통
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=hold)
    run_round(w)
    assert mails(w) == [] and told(w) is None, (mails(w), kstate(w))
    unhold(w)
    w.t += 60
    calls = run_round(w)
    assert calls and len(mails(w)) == 1 and "카드 2장" in mails(w)[0], (calls, mails(w))
    assert told(w) and len(rows(w)) == 3 and rows(w)[0].endswith("· 2장"), (kstate(w), rows(w))
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 1, mails(w)


def c_ba(tmp, mp, mk):   # ㊵바 실제 fill 길 · 보류 중 카드를 Y 로 바꿈 → 보류 바퀴 손 0(now·파일 = X) · 풀린 뒤 Y 1통
    w = mk(tmp, {P: PLAIN})
    run_round(w)
    x_fp, x_rows, x_mail = nows(w)["fp"], rows(w), mails(w)
    assert len(x_mail) == 1 and len(x_rows) == 2, (x_mail, x_rows)
    hold(w)
    pu.put(w, "대기", P, OTHER)   # Y
    w.t += 60
    calls = run_round(w) + run_round(w)
    assert calls == [] and len(mails(w)) == 1, (calls, mails(w))
    assert nows(w)["fp"] == x_fp and rows(w) == x_rows, (nows(w), rows(w))   # 마지막 관측값 그대로 · 손 0
    unhold(w)
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 2, mails(w)                                          # 풀린 바퀴 = Y 1통(본문 이름은 X 와 같다)
    assert told(w) == nows(w)["fp"] and nows(w)["fp"] != x_fp, kstate(w)          # 지문이 바뀌어 다시 보낸다
    assert len(rows(w)) > 1 and "다른 글 착지 완료" in rows(w)[1] and "팩 origin/main" not in "".join(rows(w)), rows(w)


def c_sa(tmp, mp, mk):   # ㊵사 실제 fill 길 · ㊵바와 같되 보류 중 모두 고침 → 파일 X 남음 · 풀린 뒤 0통 · told 비움 · 파일 지움
    w = mk(tmp, {P: PLAIN})
    run_round(w)
    x_rows = rows(w)
    assert len(mails(w)) == 1 and len(x_rows) == 2, (mails(w), x_rows)
    hold(w)
    pu.put(w, "대기", P, "- 선행: 없음\n")
    w.t += 60
    calls = run_round(w)
    assert calls == [] and len(mails(w)) == 1 and rows(w) == x_rows, (calls, mails(w), rows(w))
    unhold(w)
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 1 and told(w) is None and not lpath(w).exists(), (mails(w), kstate(w))


def c_reo(tmp, mp, mk):  # ㊵러 실제 닫기 뒤 고르기 길 · NEW_CARD_HOLD 있음 · 선행불명 2장 → 쪽지 0 · 호출 0 · 닫기 영수 그대로
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=hold)
    w.card("r9901", sha=w.pack_sha(), stage="완성")   # 닫을 일 1장 더(닫기 영수 자리에서 choose 가 불리는 길)
    w.work("r9901", done=True)
    calls = run_round(w)
    assert calls == [] and mails(w) == [], (calls, mails(w))
    assert [r for r in w.journal() if r["kind"] == "close_receipt"], w.journal()[-5:]   # 영수는 지금처럼 남는다


def c_aa(tmp, mp, mk):   # ㊵아 열림 · 선행불명 5장 → 1통 · 수 5 · 이름 3개 · 전체 목록 경로 1개 · 파일 5줄(이름순)
    cards = dict(zip((P, Q, R, S, T), (PLAIN, OTHER, PLAIN2, PLAIN3, PLAIN4)))
    w = mk(tmp, cards)
    run_round(w)
    mail = mails(w)
    assert len(mail) == 1 and "카드 5장" in mail[0] and "전체 목록" in mail[0], mail
    assert str(lpath(w)) in mail[0] and len([s for s in cards if s in mail[0]]) == 3, mail
    assert re.fullmatch(r"# 관측 \d{4}-\d{2}-\d{2}T[\d:]{8} · 5장", rows(w)[0]), rows(w)
    assert [x.split("\t")[0] for x in rows(w)[1:]] == sorted(cards), rows(w)
    assert all(len(x.split("\t")) == 3 and x.split("\t")[1] and x.split("\t")[2] for x in rows(w)[1:]), rows(w)


def c_ja(tmp, mp, mk):   # ㊵자 열림 · 선행불명 3장 → 지금 글 그대로(경로 칸 0) · 파일 3줄
    w = mk(tmp, {P: PLAIN, Q: OTHER, R: PLAIN2})
    run_round(w)
    mail = mails(w)
    assert len(mail) == 1 and "카드 3장" in mail[0] and "전체 목록" not in mail[0], mail
    assert mail[0].endswith(FIX), mail
    assert len(rows(w)) == 4 and rows(w)[0].endswith("· 3장"), rows(w)


def c_cha(tmp, mp, mk):  # ㊵차 팀장 없음(_master 빈칸) · harness master 있음 · 4장 · 두 바퀴 → 쪽지 0 · 묶음 0 · PREREQ-WAIT 1줄
    w = mk(tmp, {})
    team_on(w)
    for stem, head in zip((P, Q, R, S), (PLAIN, OTHER, PLAIN2, PLAIN3)):
        put_team(w, PLAN, stem, head)
    w.t += 60
    calls = run_round(w)
    assert [c for c in calls if c[0] == PLAN], calls   # planner 고르기 바퀴가 실제로 돌았다
    assert mails(w) == [], mails(w)
    assert kstate(w).get("undelivered", {}).get(PLAN) in (None, []), kstate(w).get("undelivered")
    wait = lines(w, WAIT)
    assert len(wait) == 1 and "팀장 없음" in wait[0] and "4장" in wait[0] and str(lpath(w, PLAN)) in wait[0], wait
    assert told(w, PLAN) is None and waiting(w, PLAN) and len(rows(w, PLAN)) == 5, (kstate(w), rows(w, PLAN))
    w.t += 60
    run_round(w)
    assert len(lines(w, WAIT)) == 1 and mails(w) == [], (lines(w, WAIT), mails(w))


def c_ka(tmp, mp, mk):   # ㊵카 ㊵차 뒤 _master 칸을 채움 → 그 바퀴 팀장에게 1통 · prereq_wait 지움 · 다음 바퀴 0통
    w = mk(tmp, {})
    team_on(w)
    put_team(w, PLAN, P, PLAIN)
    w.t += 60
    run_round(w)
    assert mails(w) == [] and waiting(w, PLAN), (mails(w), kstate(w))
    kw._put(w.root / ".fable-team" / ("seats-%s.json" % PLAN), {"_master": "M-planner", "_desk": ""})
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 1 and "M-planner" in mails(w)[0], mails(w)
    assert waiting(w, PLAN) is None and told(w, PLAN), kstate(w)
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 1, mails(w)


def c_ta(tmp, mp, mk):   # ㊵타 ㊵차 뒤 카드 1장 더(묶음 바뀜) → PREREQ-WAIT 1줄 다시(5장) · 쪽지 0통
    w = mk(tmp, {})
    team_on(w)
    for stem, head in zip((P, Q, R, S), (PLAIN, OTHER, PLAIN2, PLAIN3)):
        put_team(w, PLAN, stem, head)
    w.t += 60
    run_round(w)
    assert len(lines(w, WAIT)) == 1, lines(w, WAIT)
    put_team(w, PLAN, T, PLAIN4)
    w.t += 60
    run_round(w)
    wait = lines(w, WAIT)
    assert len(wait) == 2 and "5장" in wait[1] and mails(w) == [], (wait, mails(w))


def c_pa(tmp, mp, mk):   # ㊵파 팀장 없음 · _desk 있음 → ㊵차와 같음(대신 받는 곳 = 보류)
    w = mk(tmp, {})
    team_on(w, desk="D-planner")
    put_team(w, PLAN, P, PLAIN)
    w.t += 60
    run_round(w)
    assert mails(w) == [] and kstate(w).get("undelivered", {}).get(PLAN) in (None, []), (mails(w), kstate(w).get("undelivered"))
    assert len(lines(w, WAIT)) == 1 and told(w, PLAN) is None, lines(w, WAIT)


def c_ha(tmp, mp, mk):   # ㊵하 함수 단위 방어 — NEW_CARD_HOLD 깨짐(빈 파일) · 선행불명 2장 · prereq_tell 직접 → 쪽지 0
    w = mk(tmp, {P: PLAIN, Q: OTHER}, prep=lambda w: kw._put(w.state / "NEW_CARD_HOLD.json", ""))
    k = unit(w, {P: {"val": "팩 origin/main 착지(충족)", "why": "번호 참조 없음"},
                 Q: {"val": "다른 글 착지 완료", "why": "번호 참조 없음"}})
    assert mails(w) == [] and k.state["prereq_told"].get(TEAM) is None, (mails(w), k.state.get("prereq_told"))


def c_geo(tmp, mp, mk):  # ㊵거 실제 fill 길 · ㊵바의 보류 중 keeper 를 다시 만듦 → 표식 지움 → fill → Y 1통(0통·2통 아님)
    w = mk(tmp, {P: PLAIN})
    run_round(w)
    assert len(mails(w)) == 1, mails(w)
    hold(w)
    pu.put(w, "대기", P, OTHER)
    w.t += 60
    run_round(w)   # 새 keeper 하나(상태 파일 그대로)
    run_round(w)   # 또 하나
    assert len(mails(w)) == 1, mails(w)
    unhold(w)
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 2 and len(rows(w)) > 1 and "다른 글 착지 완료" in rows(w)[1], (mails(w), rows(w))   # 재기동이 0통·2통 0
    w.t += 60
    run_round(w)
    assert len(mails(w)) == 2, mails(w)


def c_neo(tmp, mp, mk):  # ㊵너 함수 단위 방어 — 팀장 없음 + NEW_CARD_HOLD · prereq_tell 직접 → 쪽지 0 · PREREQ-WAIT 0줄(P6)
    w = mk(tmp, {})
    team_on(w)
    hold(w)
    unit(w, UN2, PLAN)
    assert mails(w) == [] and lines(w, WAIT) == [] and told(w, PLAN) is None, (mails(w), lines(w, WAIT))


def c_deo(tmp, mp, mk):  # ㊵더 세 표식 0 · 팀장 있음 → 앞 카드 시험 파일 전부 rc0(㉟가~거)
    for i, name in enumerate(list(pu.CASES)):
        pu.run(name, tmp / ("p%d" % i), mp)


CASES = {"㊵가": c_ga, "㊵나": c_na, "㊵다": c_da, "㊵라": c_la, "㊵마": c_ma, "㊵바": c_ba, "㊵사": c_sa,
         "㊵러": c_reo, "㊵아": c_aa, "㊵자": c_ja, "㊵차": c_cha, "㊵카": c_ka, "㊵타": c_ta, "㊵파": c_pa,
         "㊵하": c_ha, "㊵거": c_geo, "㊵너": c_neo, "㊵더": c_deo}
MUTANTS = {   # (바꾸는 곳, 고칠 글자, 새 글자, 반드시 FAIL 이어야 하는 사례)
    "M85": (KN, "    return bool(k.halt) or os.path.lexists(",
            "    return os.path.lexists(", ("㊵라", "㊵다")),
    "M86": (KN, "    if prereq_mute(k, team):   # P1 — 묵음 = 쪽지 0(told 그대로 · now·목록 파일은 위에서 고친다)\n        return",
            "    if prereq_mute(k, team):\n        told[team] = fp\n        return", ("㊵라",)),
    "M87": (KN, '    tail = " · 전체 목록 %s" % prereq_path(k, team) if len(unread) > 3 else ""',
            '    tail = ""', ("㊵아",)),
    "M88": (KN, "    if not to or stand:   # P5 팀장 없음 = 쪽지 대신 PREREQ-WAIT 1줄(묶음에 쌓지 않는다)",
            "    if not to:", ("㊵차", "㊵파")),
    "M89": (KN, "        if wait.get(team) != fp:", "        if True:", ("㊵차",)),
    "M90": (KN, "    if not unread:\n        if os.path.lexists(path):\n            os.unlink(path)\n        return",
            "    if not unread:\n        return", ("㊵사",)),
    "M91": (KN, 'prereq_list(k, team, unread, prev.get("fp", "") != fp)',
            'prereq_list(k, team, unread, False)', ("㊵바",)),
}


def run(name, tmp, mp, ft2=kw.FT2):
    """사례 하나 = 세계 하나 · 변이는 ft2 사본으로 같은 사례를 돈다."""
    CASES[name](tmp, mp, mkf(mp, ft2))


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        with pytest.raises(AssertionError):   # 변이 = 그 사례가 무너진다
            run(case, tmp_path / ("w%d" % i), monkeypatch, tree)
