"""r2358 묶기 전 재판정 — 카드 r2358-transition-watch-recheck-before-bundle(사전 DA#47 HOLD 2/2 뒤 재검 · 설계 arch-pi#500).
K1 묶기 전 재판정(알림 칸의 표시 없는 hit 만 · 위임 칸 손 0 · 같은 칸 = 새 내용 · «판정 불가» = 원 칸 · 칸 이동·카드 없음 = 버림) ·
K2 예산·이어 보기(셋째 자리 표시 1 · deadline 넘음 = done 0 · 다음 바퀴 표시 없는 항목만) · K3 «장부 done 은 거짓» 표지 = 장부 칸 0 · K4 다른 길 그대로.
r2275 대역(world · card · at · once · sends) 재사용 · 주입 시계 = classify 1회마다 +1초(deadline 을 부름 사이에 둔다) · 실 리포·실 mbox 0 · sleep 0.
R2358_FT2=<ft2 폴더> 로 대상 바꿈(기준판 Red = ① · ⑨) · 변이 = ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2275_cases_r2358", str(Path(__file__).with_name("test_transition_watch_r2275.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
kw = T.kw
FT2 = Path(os.environ.get("R2358_FT2") or T.FT2)
HOUR = T.HOUR
SET = "- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n" % ("a" * 40)
HEAD = "send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · "
LANDW, LEDGER = HEAD + "착지 대기 · harness ", HEAD + "장부 완료 · 카드 열림 · harness 1장 — "
FLAG = "- 대기 사유: 장부 done 은 거짓 · 13장 분류 master#344\n"


def tick(w):   # 주입 시계 — classify 1회마다 +1초 · [지금 시계, 이번 바퀴 classify 부름 수]
    real, box = w.T.Watch.classify, [0.0, 0]

    def classify(s, c):
        box[0], box[1] = box[0] + 1, box[1] + 1
        return real(s, c)
    w.T.Watch.classify = classify
    return box
def watch(w, k=None, budget=1, sec=11 * 60):   # 감시 1회 = 바퀴 몫 budget(부름 수) · k 이어 씀(바퀴 사이 st) · 시계 = 지금 + sec
    T.at(w, sec)
    box = tick(w)
    return T.once(w, k, clock=lambda: box[0], budget=budget), box
def hits(w, k, cell):   # 그 칸 hit 목록([[이름, 내용, …], …])
    return k.state["transition"].get("hits", {}).get("harness|" + cell) or []
def move(w, old, new, body):   # 같은 stem 새 경로(옛 경로 지움) = r2331 실사건 꼴 — index 의 (팀, stem) 은 그대로
    (w.tmp / "seed-byz" / old).unlink()
    w.commit("byz", {new: body}, "ops/main-base")
def drop(w, stage, stem):   # 카드 지움 = 커밋 1개
    seed = w.tmp / "seed-byz"
    kw._git(seed, "rm", "-q", "design/harness/indices/%s/%s.md" % (stage, stem))
    kw._git(seed, "commit", "-q", "-m", "x"), kw._git(seed, "push", "-q", "origin", "ops/main-base")


def c1(w):   # ① 바퀴 1 «착지 대기» hit → 끝 바퀴 전 착지 줄 → 묶음 0 · 알림 0(기준판 = 1통 → Red)
    T.card(w, "진행", "r9501-land", SET)
    T.card(w, "진행", "r9502-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), box[1], [len(x) for x in hits(w, k, "land")]) == ([], 1, [2]), (T.sends(w), box, hits(w, k, "land"))
    T.card(w, "진행", "r9501-land", SET + T.land("b" * 40))
    k, box = watch(w, k, budget=5)
    assert (T.sends(w), box[1], hits(w, k, "land")) == ([], 2, []), (T.sends(w), box, hits(w, k, "land"))
def c1b(w):   # ①' 실사건 꼴(r2331): 대기/ → 완성/ 으로 옮겨짐 · 착지 줄 생김 → 재판정 = 착지 대기 아님 → 0통
    T.card(w, "진행", "r9511-land", SET)
    T.card(w, "진행", "r9512-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), box[1]) == ([], 1), (T.sends(w), box)
    move(w, "design/harness/indices/진행/r9511-land.md", "design/harness/indices/완성/r9511-land.md",
         "# 인덱스: r9511-land\n- 상태: 완성\n" + SET + T.land("c" * 40))
    k, box = watch(w, k, budget=5)
    assert (T.sends(w), hits(w, k, "land")) == ([], []), (T.sends(w), hits(w, k, "land"))
def c1c(w):   # ①'' 끝 바퀴(r2331): 옛 대기/A 항목은 표시가 없어 재판정 · 새 path 는 그 바퀴 본 루프가 판정 → 0통
    T.card(w, "대기", "r9521-land", SET)
    T.card(w, "진행", "r9522-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), box[1], [x[0] for x in hits(w, k, "land")]) == ([], 1, ["r9521-land"]), (T.sends(w), box, hits(w, k, "land"))
    move(w, "design/harness/indices/대기/r9521-land.md", "design/harness/indices/완성/r9521-land.md",
         "# 인덱스: r9521-land\n- 상태: 완성\n" + SET + T.land("d" * 40))
    k, box = watch(w, k, budget=5)
    assert (T.sends(w), hits(w, k, "land")) == ([], []), (T.sends(w), hits(w, k, "land"))
def c2(w):   # ② ① 과 같되 본문 그대로 → 묶음 1 · 알림 1통(기준판과 같은 지문)
    T.card(w, "진행", "r9531-land", SET)
    T.card(w, "진행", "r9532-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), box[1]) == ([], 1), (T.sends(w), box)
    k, box = watch(w, k, budget=5)
    assert T.sends(w) == [LANDW + "1장 — r9531-land 세트 뒤 11분 · 착지 줄 0 · 다음 수 = 착지(h 또는 try-auto --land) · 막힌 단계 확인"], T.sends(w)
def c3(w):   # ③ hit 카드 B 가 끝 바퀴 index 에 없음(지움) → 버림 · 같은 칸 카드 C 는 남음
    T.card(w, "진행", "r9541-hit", SET), T.card(w, "진행", "r9542-gone", SET), T.card(w, "진행", "r9543-plain")
    k, box = watch(w, budget=2)
    assert (T.sends(w), box[1], len(hits(w, k, "land"))) == ([], 2, 2), (T.sends(w), box, hits(w, k, "land"))
    drop(w, "진행", "r9542-gone")
    k, box = watch(w, k, budget=5)
    assert len(T.sends(w)) == 1 and "r9541-hit" in T.sends(w)[0] and "r9542-gone" not in T.sends(w)[0], T.sends(w)
    assert "harness 1장" in T.sends(w)[0] and box[1] == 2, (T.sends(w), box)
def c4(w):   # ④ 재판정 = 다른 칸(착지 대기 → 진행 24시간) → 착지 대기 묶음에서 빠짐 · 그 칸에도 안 넣음(다음 스캔 몫)
    T.card(w, "진행", "r9551-d", SET)
    T.card(w, "진행", "r9552-seat")
    T.claim(w, "r9552-seat", "byz-harness-nano-r9552-seat#0")   # 위임 칸(진행 24시간 아님) = 같이 오래된 카드의 잡음 0
    k, box = watch(w, budget=1, sec=25 * HOUR)
    assert (T.sends(w), [x[1] for x in hits(w, k, "land")]) == ([], ["r9551-d 세트 뒤 1500분 · 착지 줄 0"]), (T.sends(w), hits(w, k, "land"))
    T.card(w, "진행", "r9551-d")
    k, box = watch(w, k, budget=5, sec=25 * HOUR)
    assert (T.sends(w), box[1], hits(w, k, "land"), hits(w, k, "prog")) == ([], 2, [], []), (T.sends(w), box, hits(w, k, "land"), hits(w, k, "prog"))
def c5(w):   # ⑤ 재판정 2장째에서 deadline → done 0 · 묶음 0 · 다음 바퀴 표시 없는 1장만 재판정(부름 1) 뒤 묶음 1
    for stem in ("r9561-hit", "r9562-hit", "r9563-hit"):
        T.card(w, "진행", stem, SET)
    T.card(w, "진행", "r9564-plain")
    k, box = watch(w, budget=3)
    assert (T.sends(w), box[1], [len(x) for x in hits(w, k, "land")]) == ([], 3, [2, 2, 2]), (T.sends(w), box, hits(w, k, "land"))
    k, box = watch(w, k, budget=3)
    assert (T.sends(w), box[1], [len(x) for x in hits(w, k, "land")]) == ([], 3, [3, 3, 2]), (T.sends(w), box, hits(w, k, "land"))
    k, box = watch(w, k, budget=5)
    assert (len(T.sends(w)), box[1], "harness 3장" in T.sends(w)[0]) == (1, 1, True), (T.sends(w), box)
def c6(w):   # ⑥ 재판정 내용이 바뀜(11분 → 95분) → 본문에 새 내용
    T.card(w, "진행", "r9571-land", SET), T.card(w, "진행", "r9572-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), [x[1] for x in hits(w, k, "land")]) == ([], ["r9571-land 세트 뒤 11분 · 착지 줄 0"]), (T.sends(w), hits(w, k, "land"))
    k, box = watch(w, k, budget=5, sec=95 * 60)
    assert len(T.sends(w)) == 1 and "r9571-land 세트 뒤 95분 · 착지 줄 0" in T.sends(w)[0], T.sends(w)
def c7(w):   # ⑦ 위임 칸 hit 500 + 알림 칸 hit 1 → 위임 hit 은 재판정 0 · 착지 대기 1장만 1통
    T.card(w, "진행", "r9601-land", SET)
    T.card(w, "진행", "r9600-seat"), T.card(w, "진행", "r9610-seat")
    T.claim(w, "r9600-seat", "byz-harness-nano-r9600-seat#0"), T.claim(w, "r9610-seat", "byz-harness-nano-r9610-seat#0")
    k = w.keeper()
    k.state["transition"] = {"seen": ["design/harness/indices/진행/%s.md" % x for x in ("r9601-land", "r9600-seat", "r9610-seat")],
                             "hits": {"harness|seat": [["r9600-seat" if i % 2 else "r9610-seat", "x"] for i in range(500)],
                                      "harness|land": [["r9601-land", "r9601-land 세트 뒤 11분 · 착지 줄 0"]]}}
    k, box = watch(w, k, budget=5)
    assert len(T.sends(w)) == 1 and box[1] == 1 and "harness 1장" in T.sends(w)[0], (T.sends(w), box)
def c8(w):   # ⑧ 끝 바퀴 본 루프가 처음 판정한 카드 E → 재판정 0(부름 1) · E 는 묶음에 듦
    T.card(w, "진행", "r9581-land", SET)
    k, box = watch(w, budget=5)
    assert (len(T.sends(w)), box[1]) == (1, 1), (T.sends(w), box)
def c9(w):   # ⑨ «장부 done 은 거짓» 표지 카드 = 장부 칸 hit 0(기준판 = hit → Red) · 다른 칸 손 0
    work = "r9591-ledger-flag"
    w.work(work, done=True, intent=False, turn=None)
    T.card(w, "대기", work, FLAG)
    k, box = watch(w, budget=5, sec=2 * HOUR)
    assert (T.sends(w), hits(w, k, "ledger")) == ([], []), (T.sends(w), hits(w, k, "ledger"))
def c10(w):   # ⑩ 표지 없는 같은 꼴 → 장부 칸 hit 1(지금 그대로) = 1통
    work = "r9592-ledger-plain"
    w.work(work, done=True, intent=False, turn=None)
    T.card(w, "대기", work)
    k, box = watch(w, budget=5, sec=2 * HOUR)
    assert T.sends(w) == [LEDGER + "%s · 다시 접수 = %s-r2 · 다음 수 = 다시 접수" % (work, work)], T.sends(w)
def c11(w):   # ⑪ 재판정이 «판정 불가» 내용(장부 못 읽음) → 원 칸에 새 내용으로 남고 판정 불가 1줄 갈래(알림 0)
    T.card(w, "진행", "r9611-land", SET), T.card(w, "진행", "r9612-plain")
    k, box = watch(w, budget=1)
    assert (T.sends(w), box[1]) == ([], 1), (T.sends(w), box)
    kw._put(w.runtime() / "journal.000001.jsonl", "{oops\n")
    k, box = watch(w, k, budget=5)
    assert T.sends(w) == [] and box[1] == 2, (T.sends(w), box)   # 본 루프 1(r9612) + 재판정 1(r9611) · 알림 0
    assert [x for x in k.lines if "판정 불가" in x and "착지 대기" in x and "장부 harness" in x], k.lines


CASES = {"c1": c1, "c1b": c1b, "c1c": c1c, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6,
         "c7": c7, "c8": c8, "c9": c9, "c10": c10, "c11": c11}
TW = ("adapters", "pi", "transition_watch.py")
MUTANTS = {   # 변이 이름 → (글자 바꿈, 사례)
    "M1": ([('return recheck(w, cards, deadline), ""', 'return True, ""')], c1),   # 재판정 부름 지움
    "M2": ([('if got is not None and (got[0][1] == fn or got[1].startswith("판정 불가")):', "if got is not None:")], c4),   # 칸 비교 지움
    "M3": ([("            if deadline is not None and w.clock() >= deadline:\n                hits[key][:] = out + [item] + left\n                return False   # 이어 보기 — 재판정을 끝낸 항목만 표시 1\n", "")], c5),   # 재판정 deadline 검사 지움
    "M4": ([("item[1:] = [got[1], 1]", "item[1:] = [item[1], 1]")], c6),   # 새 내용 대신 옛 내용
    "M5": ([('        if LEDG.search(c["body"]):\n            return None', "        if False:\n            return None")], c9),   # 표지 줄 지움
    "M6": ([("if row is None or row[4]:", "if row is None:")], c7),   # 위임 칸 거름 지움
    "M7": ([("if len(item) > 2 and item[2]:", "if False:")], c5),   # 표시 무시(매 바퀴 전부 다시)
    "M8": ([('[c["stem"], got[1], 1]', '[c["stem"], got[1]]')], c8),   # append 때 표시 지움
    "M9": ([("if len(item) > 2 and item[2]:", 'if item[0] in {x["stem"] for x in cards}:')], c1c),   # 거름 = 이번 부름 stem
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](T.world(tmp_path / "w", monkeypatch, ft2=FT2))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy.joinpath(*TW)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(T.world(tmp_path / "m", monkeypatch, ft2=copy))
    case(T.world(tmp_path / "o", monkeypatch, ft2=FT2))
