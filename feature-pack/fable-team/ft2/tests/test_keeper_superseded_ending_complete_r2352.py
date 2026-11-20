"""r2352 ft2 keeper — keeper 가 «대체(superseded)» 끝으로 나노 좌석을 닫은 일도 complete 관문 1회를 거쳐 done 이 된다(카드 계약 K1~K3 · 반례 ①~⑧ · 변이 M1~M6).
① 대체 끝 · 관문 통과 · 세션 alive → kill 1 → CLOSED-ENDING → RECEIPT → complete 1 → COMPLETED 1 · done 1
② ① 에서 관문 거절(남은 범위 줄 없음) → complete 0 · UNKNOWN 사유 1줄 · done 0
③ r1965 꼴: close 키 있음 · done 0 · absent · superseded · 카드 고침 → 다음 바퀴 landing 1 · complete 1 · close-receipt 0 · done 1
④ ③ 에서 complete 뒤 done 확인 실패 → «판정 불가» 1줄 · 재시도 셈 +1 · 3번째 바퀴부터 0
⑤ 같은 팀 되찾기 후보 2건 → 그 바퀴 1건만
⑥ suspended 끝 → complete 0(지금과 같음) · ⑦ empty 끝(이미 done) → complete 0 · 줄 변화 0
대역 = r2055 settle 세계(keeper_world_r1812 임시 root·두 ref·가짜 tmux·가짜 gh·주입 시계) + 실 cli complete(임시 root) · 실 tmux·실 keeper 상주·실 pi·네트워크 0 ·
complete 셈 = 이 바퀴 keeper_close 의 cli.run 대역(감싸서 세고 그대로 부른다) · sleep 0 · 시험 1개 70초.
기준판(팩 origin/main 0225f4c7) = ① ③ Red(complete 0 · done 0) · ② ④ ⑤ ⑥ ⑦ = 지킴(양성 회귀) · ⑧ 은 0225f4c7 에 이 길이 없어 Red. 변이 M1~M6 = 자매 파일 ..._mut_r2352.py.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r2352", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
_s2 = importlib.util.spec_from_file_location("settle_world_r2352", str(HERE / "test_settle_one_path_r2055.py"))
S = importlib.util.module_from_spec(_s2)
_s2.loader.exec_module(S)
FT2, TEAM = kw.FT2, kw.TEAM
BODY = "# 인덱스: %s\n%s## 상태\n- 대체: r1752 ca6c3f2a · ALREADY · 코드·가지·PR 0\n"   # superseded 근원 = 상태 머리 «대체:»
STOP = "# 인덱스: %s\n- 남은 범위: 없음\n## 상태\n- 중단: 사람 손 대기\n"
QUIET = ("ROUND", "SLOW-CELL", "FETCH-TRY", "FULL-ALERT", "NEXT-HOLD", "NOTIFIED")


def card(w, work, body):
    """카드 1장 = 두 ref(ops/main-base → main) · landing·endings 가 읽는 자리 그대로."""
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/harness/indices/진행/%s-x.md" % work: body}, ref)


def world(tmp, mp, works=("r9352",), scope=(), ft2=FT2, done=(), bodies=None):
    """일 n개 = 카드(대체 끝) → nano 좌석(접수·배정·전달·intent·세션 살아 있음) · scope = «남은 범위: 없음» 줄 있는 work ·
    bodies = work → 카드 본문(그 밖 = 대체 끝 본문)."""
    w = S.world(tmp, mp, ft2)
    for work in works:
        body = (bodies or {}).get(work) or BODY % (work, "- 남은 범위: 없음\n" if work in scope else "")
        card(w, work, body)
        S.nano(w, work, done=work in done)
    return w


def scope(w, work):
    """카드에 «남은 범위: 없음» 줄을 더한다(관문 통과 꼴 · 새 커밋 = 다음 바퀴에 읽힌다)."""
    card(w, work, BODY % (work, "- 남은 범위: 없음\n"))


def has(lines, *words):
    return [x for x in lines if x.split(" ")[0] not in QUIET and all(word in x for word in words)]


def proj(w):
    return w.CLI.run(["project", "--root", str(w.root), "--team", TEAM])[0]


def done(w, work):
    return bool((proj(w)["works"].get(work) or {}).get("done"))


def retry(w):
    path = w.state / "ft2-keeper" / "state.json"
    return json.loads(path.read_text(encoding="utf-8")).get("superseded_retry") or {} if path.exists() else {}


def reading_of(k, work):
    """이 바퀴 keeper_close 가 그 work 의 끝을 읽은 횟수(가짜 아님 · endings.ending 을 감싸 센다) · 반환 = (셈 list, 되돌리기)."""
    mod = k.superseded_complete.__func__.__globals__["endings"]
    real, calls = mod.ending, []

    def ending(*a, **kw_):
        calls.extend([a[2]] if len(a) > 2 and a[2] == work else [])
        return real(*a, **kw_)
    mod.ending = ending
    return calls, lambda: setattr(mod, "ending", real)


def complete_calls(k, fail=False):
    """이 바퀴 keeper_close 의 cli.run 을 감싸 complete 호출만 센다(그대로 부른다 · fail = complete 를 실패로 돌려준다) · 반환 = (셈 list, 되돌리기)."""
    mod = k.superseded_complete.__func__.__globals__["cli"]
    real, calls = mod.run, []

    def run(argv, *a, **kw_):
        if argv[:1] != ["complete"]:
            return real(argv, *a, **kw_)
        calls.append(argv)
        return ({"result": "복구 필요"}, 1) if fail else real(argv, *a, **kw_)
    mod.run = run
    return calls, lambda: setattr(mod, "run", real)


def c1(w, mp):   # ① 대체 끝 · 관문 통과 · 세션 alive → kill 1 · CLOSED-ENDING · RECEIPT · complete 1 · COMPLETED 1 · done 1
    k = w.keeper()
    calls, stop = complete_calls(k)
    lines = w.round(k)
    stop()
    assert has(lines, "CLOSED-ENDING", TEAM, "r9352", "superseded") and len(w.tmux("kill-session")) == 1, lines
    assert has(lines, "RECEIPT", TEAM, "r9352") and calls and len(calls) == 1, (lines, calls)
    assert has(lines, "COMPLETED", TEAM, "r9352") and done(w, "r9352") and retry(w) == {}, (lines, retry(w))


def c2(w, mp):   # ② 관문 거절(남은 범위 줄 없음) → complete 0 · UNKNOWN 사유 1줄 · done 0
    k = w.keeper()
    calls, stop = complete_calls(k)
    lines = w.round(k)
    stop()
    assert calls == [] and has(lines, "COMPLETED") == [] and not done(w, "r9352"), lines
    assert len(has(lines, "UNKNOWN", TEAM, "r9352", "남은 범위")) == 1, lines
    assert has(lines, "RECEIPT", TEAM, "r9352"), lines   # 영수는 그대로(닫기는 끝)


def c3(w, mp):   # ③ r1965 꼴: close 키 · done 0 · absent · superseded · 카드 고침 → 다음 바퀴 landing 1 · complete 1 · close-receipt 0 · done 1
    w.round(w.keeper())   # 첫 바퀴 = 닫기 영수 + 관문 거절(②)
    scope(w, "r9352")
    k = w.keeper()
    calls, stop = complete_calls(k)
    lines = w.round(k)
    stop()
    assert len(calls) == 1 and has(lines, "COMPLETED", TEAM, "r9352") and done(w, "r9352"), lines
    assert w.kinds("close_receipt") == 1, w.kinds("close_receipt")   # 둘째 바퀴 영수 0(첫 바퀴 1건 그대로)
    assert has(lines, "RECEIPT") == [] and has(lines, "CLOSED-ENDING") == [], lines


def c4(w, mp):   # ④ complete 뒤 done 확인 실패 → «판정 불가» 1줄 · 재시도 셈 +1 · 3번째 바퀴부터 0
    w.round(w.keeper())
    scope(w, "r9352")
    seen, counts = [], []
    for _ in range(3):
        k = w.keeper()
        calls, stop = complete_calls(k, fail=True)
        lines = w.round(k)
        stop()
        seen.append(has(lines, "판정 불가", TEAM, "r9352", "done 0"))
        counts.append((len(calls), retry(w).get("%s|r9352|a1" % TEAM, 0)))
    assert counts == [(1, 1), (1, 2), (0, 2)], counts   # 상한 2 = 셋째 바퀴부터 0
    assert [len(x) for x in seen] == [1, 1, 0] and not done(w, "r9352"), seen


def c5(w, mp):   # ⑤ 같은 팀 되찾기 후보 2건 → 그 바퀴 1건만
    w.round(w.keeper())   # 두 일 모두 닫힘(영수 2)
    assert w.kinds("close_receipt") == 2, w.kinds("close_receipt")
    for work in ("r9358", "r9359"):
        scope(w, work)
    got = []
    for _ in range(2):
        got.append(has(w.round(w.keeper()), "COMPLETED", TEAM))
    assert [len(x) for x in got] == [1, 1], got   # 바퀴마다 1건
    assert done(w, "r9358") and done(w, "r9359"), got


def c6(w, mp):   # ⑥ suspended 끝 → complete 0(지금과 같음)
    card(w, "r9356", STOP % "r9356")
    S.nano(w, "r9356")
    k = w.keeper()
    calls, stop = complete_calls(k)
    lines = w.round(k)
    stop()
    assert calls == [] and has(lines, "CLOSED-ENDING", TEAM, "r9356", "suspended"), lines
    assert has(lines, "COMPLETED") == [] and not done(w, "r9356"), lines


def c7(w, mp):   # ⑦ empty 끝(이미 done) → complete 0 · 줄 변화 0(끝 판독·영수 줄 그대로)
    card(w, "r9357", "# 인덱스: r9357\n- 남은 범위: 없음\n")
    S.nano(w, "r9357", done=True)
    it = json.loads((w.runtime() / "launch" / "r9357@a1.intent").read_text(encoding="utf-8"))
    kw._git(it["worktree"], "reset", "-q", "--hard", it["base_sha"])   # 커밋 0 · 변경 0 = empty 끝
    k = w.keeper()
    calls, stop = complete_calls(k)
    lines = w.round(k)
    stop()
    assert calls == [] and has(lines, "CLOSED-ENDING", TEAM, "r9357", "empty"), lines
    assert has(lines, "COMPLETED") == [] and done(w, "r9357") and retry(w) == {}, lines


def c8(w, mp):   # ⑧ 이름순 앞 = suspended 끝 · 뒤 = 대체 끝(카드 고침) → 4바퀴 안에 뒤 일 COMPLETED 1 · 앞 일 끝 판독 ≤ 2회(DA#46 B1)
    w.round(w.keeper())   # 두 일 닫힘(r9350 suspended · r9352 대체 + 관문 거절)
    assert w.kinds("close_receipt") == 2, w.kinds("close_receipt")
    scope(w, "r9352")     # 뒤 일 카드 고침
    got = []
    for _ in range(4):
        k = w.keeper()
        reads, stop = reading_of(k, "r9350")
        got.append((len(has(w.round(k), "COMPLETED", TEAM, "r9352")), len(reads)))
        stop()
    assert sum(x for x, _ in got) == 1 and done(w, "r9352"), got   # 앞 일이 뒤 일을 가리지 않는다
    assert sum(y for _, y in got) <= 2 and not done(w, "r9350"), got   # 상한 2 뒤 앞 일 판독 0(git 판독 끝없음 0)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
WORKS = {"⑤": ("r9358", "r9359"), "⑥": (), "⑦": (), "⑧": ("r9350", "r9352")}   # ⑥⑦ = 카드를 그 사례가 직접 만든다
SCOPE = {"①": ("r9352",)}   # «남은 범위: 없음» 줄을 카드에 넣을 사례(그 밖 = 관문 거절 · 되찾기)
ALL_DONE = {"⑦": ("r9357",)}
BODIES = {"⑧": {"r9350": STOP % "r9350"}}   # 앞 일 = suspended 끝(이름순 앞 · K2 후보 조건은 다 채운다)


def build(tmp, mp, ft2=FT2, name="①"):
    return world(tmp, mp, ft2=ft2, works=WORKS.get(name, ("r9352",)), scope=SCOPE.get(name, ()), done=ALL_DONE.get(name, ()),
                 bodies=BODIES.get(name, {}))


def mutant(tmp_path, mp, pairs, case, name):
    """사본 ft2 의 변이(pairs = [(파일, old, new)] · 각 old 1회) → 그 사례 FAIL · 원본으로 같은 사례 1회 더 = 통과(반대 결과 대조).
    자매 = test_keeper_superseded_ending_complete_mut_r2352.py(변이 M1~M6 · 70초 나눔)."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    for rel, old, new in pairs:
        path = tree / rel
        text = path.read_text(encoding="utf-8")
        assert text.count(old) == 1, (rel, old)
        path.write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(build(tmp_path / "w1", mp, tree, name), mp)
    shutil.rmtree(tmp_path / "w1")
    case(build(tmp_path / "w2", mp, FT2, name), mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](build(tmp_path / "w", monkeypatch, name=name), monkeypatch)
