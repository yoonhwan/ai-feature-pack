"""ft2 keeper 선행불명 — 로그는 «선행 값 + 까닭» 이 바뀔 때만 1줄, 팀장에게 [다음 막힘] 1통
(카드 ft2-prereq-unreadable-once · ㉟가~하 14칸 + 인수 칸 ㉟거 · 변이 M39·M40·M41·M56·M57·M58).

계약 = `contracts/keeper-settle/CONTRACT.md` §12(I1~I9) · 설계 = `design/DESIGN-pI-prereq-unreadable-log-once-20261116.md`.
대역 = r1871 세계(임시 root·git·가짜 tmux·launch·record·mbox) + 주입 시계(사례가 w.t 를 민다) · 실 tmux·명부·우편함·설치 0 · sleep 0 · 사례 하나 70초 안.
바퀴마다 keeper 를 새로 만든다 = 실제처럼 프로세스가 바뀐다(상태는 상태 파일로만 이어진다 · I9 · 쪽지 상한 3통은 바퀴당).
기준판(팩 origin/main 2b5037d1) = ㉟가 · ㉟바 · ㉟차 · ㉟타 Red(바퀴 캐시만 있어 둘째 바퀴에 같은 줄이 또 찍히고, [다음 막힘] 쪽지가 없다).
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1871_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw, TEAM = base.kw, base.kw.TEAM
KN = "adapters/pi/keeper_next.py"
ROOT = "design/harness/indices/%s/%s.md"
FIX = "고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»"
PLAIN, OTHER, PLAIN2, PLAIN3, PLAIN4 = ("- 선행: 팩 origin/main 착지(충족)\n", "- 선행: 다른 글 착지 완료\n",
                                        "- 선행: 5항 env 착지 · 6항 원인 판정\n", "- 선행: 재자율(지금 정지 레디)\n",
                                        "- 선행: 사전 단계 GPU 스택 기동 = HIL 1줄\n")


def put(w, stage, stem, head=""):
    """카드 1장을 그 폴더에 커밋(대기 → 완성 이동도 같은 길 · w.commit 은 파일을 더하기만 한다)."""
    w.commit("byz", {ROOT % (stage, stem): "# 인덱스: %s\n%s- 상태: 대기\n" % (stem, head)}, "main")


def world(tmp, mp, cards, cap="4", ft2=kw.FT2):
    """대기 카드 {stem: 머리 줄} · 빈 나노 칸 4(바퀴마다 fill 이 골라도 계속 열림) · 닫힐 일 1장."""
    tmp.mkdir(parents=True, exist_ok=True)
    w = base.world(tmp, mp, cards, ft2=ft2)
    w.env["FT2_TEAM_NANO_MAX"] = cap   # r1871 세계 기본 1 = 첫 launch 뒤 fill 닫힘 → 여러 바퀴 사례가 choose 를 못 부른다
    return w


def rnd(w):
    """한 바퀴 = keeper 를 새로 만들어 돌린다(실제 프로세스와 같다 · 상태는 상태 파일로만 이어진다)."""
    return w.round(w.keeper())


def more(w, n):
    """다음 바퀴에도 choose 를 부르게 닫을 일 1장을 더한다(닫기 영수 자리 = 선행불명 로그·쪽지 자리)."""
    base.close(w, "r99%02d" % n)


def plume(w):
    """keeper 로그 파일에 남은 `선행 줄 판독 불가` 줄 — 인스턴스와 무관(바퀴마다 새 keeper 여도 같은 수)."""
    return [json.loads(x)["line"] for p in sorted((w.state / "ft2-keeper").glob("*.jsonl")) for x in kw._lines(p)
            if "선행 줄 판독 불가" in x]


def hits(w, mark):
    """가짜 mbox 가 받은 줄 중 그 표식이 든 것 — [다음 막힘] / [다음 없음]."""
    return [x for x in kw._lines(str(w.mbox) + ".log") if mark in x]


def mbox_rc(w, rc):
    Path(str(w.mbox) + ".rc").write_text(str(rc), encoding="utf-8")


def c_ga(tmp, mp, mk):   # ㉟가 글뿐인 선행 1장 · 두 바퀴 → 1줄(까닭 번호 참조 없음 · 고칠 꼴) · 둘째 0줄 · 두 바퀴 모두 submit 0
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    assert plume(w) == ["판정 불가 harness %s 선행 줄 판독 불가(번호 참조 없음) — 건너뜀 · %s" % (P, FIX)], plume(w)
    assert len(hits(w, "[다음 막힘]")) == 1 and base.count(w, "accept", P) == 0, (hits(w, "[다음 막힘]"), plume(w))
    more(w, 1)
    rnd(w)
    assert len(plume(w)) == 1 and base.count(w, "accept", P) == 0, (plume(w), base.launched(w))


def c_na(tmp, mp, mk):   # ㉟나 ㉟가 뒤 선행 글을 다른 글로 바꿈 → 1줄 다시
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    put(w, "대기", P, OTHER)
    more(w, 1)
    rnd(w)
    assert len(plume(w)) == 2 and all("번호 참조 없음" in x for x in plume(w)), plume(w)


def c_da(tmp, mp, mk):   # ㉟다 선행 `r5 착지` · 루트에 r5 없음 → 1줄 · 까닭 루트에 없는 번호 r5
    P = "r9201-plain"
    w = mk(tmp / "w", {P: "- 선행: 결정 원문 r5 PR 8503 착지\n"})
    rnd(w)
    assert plume(w) == ["판정 불가 harness %s 선행 줄 판독 불가(루트에 없는 번호 r5) — 건너뜀 · %s" % (P, FIX)], plume(w)


def c_ra(tmp, mp, mk):   # ㉟라 ㉟가 뒤 keeper 다시 만듦(상태 파일 그대로) → 0줄
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    more(w, 1)
    rnd(w)   # 새 keeper = 상태 파일만 읽는다
    assert len(plume(w)) == 1 and len(hits(w, "[다음 막힘]")) == 1, (plume(w), hits(w, "[다음 막힘]"))


def c_ma(tmp, mp, mk):   # ㉟마 `없음` 으로 고침 → 고름 → 다시 글로 바꿈 → 고친 바퀴 0줄 · submit 1 · 다시 바꾼 바퀴 1줄
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    put(w, "대기", P, "- 선행: 없음\n")
    more(w, 1)
    rnd(w)
    assert len(plume(w)) == 1 and base.count(w, "accept", P) == 1 and base.launched(w) == [P], (plume(w), base.launched(w))
    put(w, "대기", P, PLAIN)
    more(w, 2)
    rnd(w)
    assert len(plume(w)) == 2 and base.count(w, "accept", P) == 1, plume(w)


def c_ba(tmp, mp, mk):   # ㉟바 선행불명 2장 + 고를 카드 1장 → [다음 막힘] 1통(2장 · 이름 2개) · 고를 카드 submit 1 · 둘째 바퀴 쪽지 0
    P, Q, G = "r9201-plain", "r9202-plain", "r9203-open"
    w = mk(tmp / "w", {P: PLAIN, Q: OTHER, G: "- 선행: 없음\n"}, cap="1")   # 고른 카드가 뜨면 칸이 꽉 참 = 이 바퀴 choose 1번(둘째 부름에 가려지지 않는다)
    rnd(w)
    mail = hits(w, "[다음 막힘]")
    assert len(mail) == 1 and "카드 2장" in mail[0] and P in mail[0] and Q in mail[0], mail
    assert base.count(w, "accept", G) == 1 and base.count(w, "accept", P) == 0 and base.launched(w) == [G], (mail, base.launched(w))
    w.env["FT2_TEAM_NANO_MAX"] = "4"   # 둘째 바퀴는 칸을 열어 choose 가 다시 돌게 한다(쪽지 0 이 가려지지 않게)
    more(w, 1)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 1, hits(w, "[다음 막힘]")


def c_sa(tmp, mp, mk):   # ㉟사 ㉟바 뒤 선행불명 카드 1장이 더 생김 → [다음 막힘] 1통 다시(3장)
    P, Q, G, R = "r9201-plain", "r9202-plain", "r9203-open", "r9204-plain"
    w = mk(tmp / "w", {P: PLAIN, Q: OTHER, G: "- 선행: 없음\n"})
    rnd(w)
    put(w, "대기", R, PLAIN3)
    more(w, 1)
    rnd(w)
    mail = hits(w, "[다음 막힘]")
    assert len(mail) == 2 and "카드 3장" in mail[1] and R in mail[1], mail


def c_aa(tmp, mp, mk):   # ㉟아 선행불명 5장 → 쪽지 이름 3개 · 수 5
    cards = {"r92%02d-plain" % n: head for n, head in zip(range(1, 6), (PLAIN, OTHER, PLAIN2, PLAIN3, PLAIN4))}
    w = mk(tmp / "w", cards)
    rnd(w)
    mail = hits(w, "[다음 막힘]")
    assert len(mail) == 1 and "카드 5장" in mail[0], mail
    assert len([stem for stem in cards if stem in mail[0]]) == 3, mail
    assert len(plume(w)) == 5, plume(w)


def c_ja(tmp, mp, mk):   # ㉟자 `r9100` 이 대기에 있음 → 선행(막힘 · 줄 0) / 완성에 있음 → 열림
    P, DEP = "r9201-plain", "r9100-dep"
    wa = mk(tmp / "a", {P: "- 선행: r9100 착지\n", DEP: "- 선행: 없음\n"})
    rnd(wa)
    assert plume(wa) == [] and hits(wa, "[다음 막힘]") == [] and base.count(wa, "accept", P) == 0, (plume(wa), base.launched(wa))
    wb = mk(tmp / "b", {P: "- 선행: r9100 착지\n"})
    put(wb, "완성", DEP)
    rnd(wb)
    assert base.count(wb, "accept", P) == 1 and base.launched(wb) == [P] and plume(wb) == [], (plume(wb), base.launched(wb))


def c_cha(tmp, mp, mk):   # ㉟차 같은 날 X 쪽지 성공 → `없음` 으로 고침(빈 묶음) → 같은 글로 되돌림(X) → 2통 · 로그 2줄
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    put(w, "대기", P, "- 선행: 없음\n")
    more(w, 1)
    rnd(w)
    put(w, "대기", P, PLAIN)
    more(w, 2)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2 and len(plume(w)) == 2, (hits(w, "[다음 막힘]"), plume(w))


def c_ka(tmp, mp, mk):   # ㉟카 같은 날 X 쪽지 성공 → 카드 1장 더 생겨 Y 쪽지 성공 → 그 카드를 고쳐 다시 X → 3통
    P, Q = "r9201-plain", "r9202-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    put(w, "대기", Q, OTHER)
    more(w, 1)
    rnd(w)
    put(w, "대기", Q, "- 선행: 없음\n")
    more(w, 2)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 3, hits(w, "[다음 막힘]")


def c_ta(tmp, mp, mk):   # ㉟타 `r9100 r9101` 둘 다 없음 → 다음 바퀴 r9100 이 완성에 생김(선행 글 그대로) → 1줄 다시(까닭 r9101) · 쪽지 2통 · submit 0
    P, DEP = "r9201-plain", "r9100-dep"
    w = mk(tmp / "w", {P: "- 선행: r9100 r9101 착지\n"})
    rnd(w)
    assert plume(w) == ["판정 불가 harness %s 선행 줄 판독 불가(루트에 없는 번호 r9100 r9101) — 건너뜀 · %s" % (P, FIX)], plume(w)
    put(w, "완성", DEP)
    more(w, 1)
    rnd(w)
    assert len(plume(w)) == 2 and plume(w)[1].endswith("선행 줄 판독 불가(루트에 없는 번호 r9101) — 건너뜀 · %s" % FIX), plume(w)
    assert len(hits(w, "[다음 막힘]")) == 2 and base.count(w, "accept", P) == 0, (hits(w, "[다음 막힘]"), plume(w))


def c_pa(tmp, mp, mk):   # ㉟파 X 쪽지 성공 → Y 가 됨 · send rc 3 → 같은 날 다음 바퀴 → 날짜 바뀐 바퀴 / 넘김이면 다음 바퀴 1
    P, Q = "r9201-plain", "r9202-plain"
    w = mk(tmp / "w" / "a", {P: PLAIN})
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 1, plume(w)
    put(w, "대기", Q, OTHER)
    mbox_rc(w, 3)
    more(w, 1)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2, hits(w, "[다음 막힘]")   # 보냄(rc 3 = 실패 · told 그대로)
    more(w, 2)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2, hits(w, "[다음 막힘]")   # 같은 날 = 실패 지문이라 재시도 0
    w.t += 86400
    more(w, 3)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 3, hits(w, "[다음 막힘]")   # 날짜가 바뀌면 1회 다시
    mbox_rc(w, 0)
    w.t += 86400
    more(w, 4)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 4, hits(w, "[다음 막힘]")   # 성공 → told = Y
    more(w, 5)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 4, hits(w, "[다음 막힘]")   # 성공한 뒤 = 0
    # 넘김(defer) = 바퀴 3통 상한 밖 → 지문 0 · 다음 바퀴 1
    wb = mk(tmp / "w" / "b", {P: PLAIN})
    rnd(wb)
    put(wb, "대기", Q, OTHER)
    kb = wb.keeper()
    kb.notify_used = 3   # 이 바퀴 쪽지 상한을 이미 썼다 = budget 거짓
    wb.round(kb)
    assert len(hits(wb, "[다음 막힘]")) == 1, hits(wb, "[다음 막힘]")   # 넘김 = 보내지 않음
    more(wb, 2)
    rnd(wb)   # 다음 바퀴 = 상한 풀림
    assert len(hits(wb, "[다음 막힘]")) == 2, hits(wb, "[다음 막힘]")


def c_ha(tmp, mp, mk):   # ㉟하 X 성공 → Y send 실패 → 카드를 고쳐 다시 X → 쪽지 0(팀장이 아는 묶음) · 로그는 바뀐 카드만 1줄
    P, Q = "r9201-plain", "r9202-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    put(w, "대기", Q, OTHER)
    mbox_rc(w, 3)
    more(w, 1)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2 and len(plume(w)) == 2, (hits(w, "[다음 막힘]"), plume(w))
    put(w, "대기", Q, "- 선행: 없음\n")
    more(w, 2)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2 and len(plume(w)) == 2, (hits(w, "[다음 막힘]"), plume(w))


def c_geo(tmp, mp, mk):  # ㉟거(인수 칸 · DA 310229) 상태 저장 뒤 keeper 다시 만듦 → 변화 없음 발신 0 → 그 뒤 X 재발 1통
    P = "r9201-plain"
    w = mk(tmp / "w", {P: PLAIN})
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 1, hits(w, "[다음 막힘]")
    more(w, 1)
    rnd(w)   # 새 keeper · 상태 파일 그대로 = 묶음 그대로 → 발신 0 · 줄 0
    assert len(hits(w, "[다음 막힘]")) == 1 and len(plume(w)) == 1, (hits(w, "[다음 막힘]"), plume(w))
    put(w, "대기", P, "- 선행: 없음\n")
    more(w, 2)
    rnd(w)   # 빈 묶음 = told 를 비운다
    assert len(hits(w, "[다음 막힘]")) == 1, hits(w, "[다음 막힘]")
    put(w, "대기", P, PLAIN)
    more(w, 3)
    rnd(w)
    assert len(hits(w, "[다음 막힘]")) == 2 and len(plume(w)) == 2, (hits(w, "[다음 막힘]"), plume(w))


CASES = {"㉟가": c_ga, "㉟나": c_na, "㉟다": c_da, "㉟라": c_ra, "㉟마": c_ma, "㉟바": c_ba, "㉟사": c_sa,
         "㉟아": c_aa, "㉟자": c_ja, "㉟차": c_cha, "㉟카": c_ka, "㉟타": c_ta, "㉟파": c_pa, "㉟하": c_ha, "㉟거": c_geo}
MUTANTS = {   # (바꾸는 곳, 고칠 글자, 새 글자, 반드시 FAIL 이어야 하는 사례)
    "M39": (KN, "            if book.get(key) != seen:",
            '            if once(k, ("prereq-log", team, stem), lambda: True):', ("㉟가", "㉟라")),
    "M40": (KN, "        book.pop(key)", "        pass", ("㉟마",)),
    "M41": (KN, "    prereq_tell(k, team, {s: row[4] for s, row in found.items() if row[3] == \"선행불명\"})",
            "    prereq_tell(k, team, {s: row[4] for s, row in found.items() if row[3] == \"선행불명\"}) if not ready else None",
            ("㉟바",)),
    "M56": (KN, "    if ok:   # I8 성공(rc 0·도착 확인)일 때만 told 를 바꾼다 · 실패·넘김(defer)은 그대로\n        told[team] = fp",
            "    told[team] = fp", ("㉟파",)),
    "M57": (KN, '"prereq|%s|%s|%s" % (team, fp, n)', '"prereq|%s|%s" % (team, fp)', ("㉟차", "㉟카")),
    "M58": (KN, "            if book.get(key) != seen:", '            if book.get(key, {}).get("val") != seen["val"]:', ("㉟타",)),
}


def run(name, tmp, mp, ft2=kw.FT2):
    """사례 하나 = 세계 하나 · 변이는 ft2 사본으로 같은 사례를 돈다."""
    CASES[name](tmp, mp, lambda path, cards, cap="4": world(path, mp, cards, cap=cap, ft2=ft2))


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
