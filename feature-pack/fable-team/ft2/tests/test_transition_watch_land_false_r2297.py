"""r2297 착지 대기 거짓 경보 — 반례 ①~⑤ · ②ⓑ · ④ⓑ · ④ⓒ · ④ⓓ · ⑤ⓑ · git 호출 수 + 변이 M1~M5(카드 r2297-transition-watch-land-wait-false-alarms · 사전 DA#33 조건부 APPROVE-DESIGN).
r2275 대역(world · card · at · once · sends) 재사용 · 두 ref(ops/main-base · main) 대역 카드 · 실 keeper·실 mbox 0 · sleep 0.
R2297_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조) · 변이 = ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2275_cases_r2297", str(Path(__file__).with_name("test_transition_watch_r2275.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
FT2 = Path(os.environ.get("R2297_FT2") or T.FT2)
SET = "- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n" % ("a" * 40)
HEAD = "send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 착지 대기 · harness 1장 — "


def got(w):   # 전이 감시 쪽지 = «다음 수» 앞까지
    return [x.split(" · 다음 수 = ")[0] for x in T.sends(w)]
def state(*rows):   # «## 상태» 절
    return "\n## 상태\n" + "".join("- %s\n" % x for x in rows)
def main(w, stage, stem, body):   # main ref 사본 1장 = main 커밋 1개
    w.commit("byz", {"design/harness/indices/%s/%s.md" % (stage, stem): "# 인덱스: %s\n- 상태: %s\n%s" % (stem, stage, body)}, "main")
def stages(w):   # index() 가 고른 카드 단계 {stem: 단계}
    T.kw._git(w.root, "fetch", "-q", "origin")
    return {c["stem"]: c["stage"] for c in w.T.Watch(w.keeper()).index()}
def quiet(w, stem, body):   # 대기 · 세트 줄 · 11분 → 0통
    T.card(w, "대기", stem, SET + body)
    T.at(w, 11 * 60)
    T.once(w)
    assert T.sends(w) == [], T.sends(w)
def c1(w):   # ① 관측 표지
    quiet(w, "r9301-observe", "- 착지 대상: 없음 — 관측 세트\n")
def c2(w):   # ② 끝 줄 중단
    quiet(w, "r9302-stopped", state("2026-11-08 · 세트", "2026-11-09 — 중단: 오빠 1-1 닫고 카드 대기 복귀"))
def c2b(w):   # ②ⓑ 끝 줄 대체
    quiet(w, "r9312-replaced", state("2026-11-09 — 대체: r1752 로 넘김"))
def c3(w):   # ③ 짧은 착지 줄 → 1통 «착지 줄 꼴 틀림»
    T.card(w, "대기", "r9303-short", SET + "- 착지: ae5c94d6\n")
    T.at(w, 11 * 60)
    T.once(w)
    assert got(w) == [HEAD + "r9303-short 착지 줄 꼴 틀림(40hex 0) · 세트 뒤 11분"], T.sends(w)
def c4(w):   # ④ ops 진행(11-10) · main 완성(11-12) → 완성 · 25시간 = 착지 대기 0 · 진행 24시간 0
    T.card(w, "진행", "r9304-twin", SET + state("진행 · 2026-11-10 · 세트"))
    main(w, "완성", "r9304-twin", SET + state("완성 · 2026-11-12 · 착지"))
    assert stages(w) == {"r9304-twin": "완성"}
    T.at(w, 25 * 3600)
    T.once(w)
    assert T.sends(w) == [], T.sends(w)
def c4b(w):   # ④ⓑ ops 완성(11-12) · main 대기(11-10) → 완성(harness 꼴)
    T.card(w, "완성", "r9314-twin", state("완성 · 2026-11-12"))
    main(w, "대기", "r9314-twin", state("대기 · 2026-11-10"))
    assert stages(w) == {"r9314-twin": "완성"}
def c4c(w):   # ④ⓒ 정본 되돌림 — ops 대기(11-06 진행→대기) · main 진행(11-05 낡음) → 대기 · 진행 칸 경보 0
    T.card(w, "대기", "r9324-reopen", state("진행 · 2026-11-05 · 착수", "2026-11-06 · 진행→대기 · 다시 엶"))
    main(w, "진행", "r9324-reopen", state("진행 · 2026-11-05 · 착수"))
    assert stages(w) == {"r9324-reopen": "대기"}
    T.at(w, 25 * 3600)
    T.once(w)
    assert T.sends(w) == [], T.sends(w)
def c4d(w):   # ④ⓓ 날짜 같음 → REFS 앞 ref(ops)
    T.card(w, "대기", "r9334-same", state("대기 · 2026-11-10"))
    main(w, "진행", "r9334-same", state("진행 · 2026-11-10"))
    assert stages(w) == {"r9334-same": "대기"}
def c5(w, sec=11 * 60):   # ⑤ 진짜 착지 대기 → 1통 «세트 뒤 11분 · 착지 줄 0»(r2293 ① 그대로)
    T.card(w, "대기", "r9305-real", SET + state("대기 · 2026-11-19 · 세트 · 다음 = master try-auto"))
    T.at(w, sec)
    T.once(w)
    assert got(w) == ([HEAD + "r9305-real 세트 뒤 11분 · 착지 줄 0"] if sec >= 600 else []), T.sends(w)
def c5b(w):   # ⑤ⓑ 9분 → 0통
    c5(w, 9 * 60)
def c7(w):   # A5 index() git 호출 = TEAMS 1 + ref 마다 ls-tree 1 + cat-file 1(두 ref 사본이 있어도 같음)
    T.card(w, "진행", "r9307-twin", state("진행 · 2026-11-10"))
    main(w, "완성", "r9307-twin", state("완성 · 2026-11-12"))
    T.kw._git(w.root, "fetch", "-q", "origin")
    v, n = w.T.Watch(w.keeper()), []
    run = v.run
    v.run = lambda *a, **kv: (n.append(a[0][5] if a[0][:1] == ["git"] else a[0][0]), run(*a, **kv))[1]
    v.index()
    assert n == ["show", "ls-tree", "ls-tree", "cat-file"], n


CASES = {"c1": c1, "c2": c2, "c2b": c2b, "c3": c3, "c4": c4, "c4b": c4b, "c4c": c4c, "c4d": c4d, "c5": c5, "c5b": c5b, "c7": c7}
LW = ("adapters", "pi", "land_wait.py")
MUTANTS = {   # 변이 이름 → (파일, 글자 바꿈, 사례)
    "M1": (LW, [("bool(MARK.search(body)) or ", "")], c1),   # 표지 판독 지움
    "M2": (LW, [(" or endings._head(body) is not None", "")], c2),   # _head 대조 지움
    "M3": (LW, [("best = c if a and b and b > a else best", "best = best")], c4),   # 날짜 비교 → REFS 차례
    "M4": (LW, [("if LOOSE.search(body) else", "if False else")], c3),   # «- 착지: » 줄 판독 지움
    "M5": (LW, [('a, b = stamp(best["body"]), stamp(c["body"])', 'a, b = "대기진행완성".index(best["stage"]) + 1, "대기진행완성".index(c["stage"]) + 1')], c4c),   # 단계 순위
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](T.world(tmp_path / "w", monkeypatch, ft2=FT2))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, pairs, case = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy.joinpath(*rel)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(T.world(tmp_path / "m", monkeypatch, ft2=copy))
    case(T.world(tmp_path / "o", monkeypatch, ft2=FT2))
