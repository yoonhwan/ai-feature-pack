"""r2115 keeper 출력 풀기 · work 경계 — 깨진 UTF-8 바이트 1개가 keeper 를 끝내지 않는다 · one_work 예상 밖 예외 = 그 work 판정 불가 1줄 + 다음 work
(카드 r2115 반례 ① ② ③ ④ · 변이 M1 strict → ① · M2 except BaseException → ④ · M3 except 지움 → ③) · 대역 = r2088 world(임시 root·git·가짜 gh·tmux) · 실 원장·로그·명부·sleep 0."""
import importlib.util, sys  # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
_S = importlib.util.spec_from_file_location("r2115_en", str(FT2 / "tests" / "test_keeper_evidence_notice_r2088.py"))
en = importlib.util.module_from_spec(_S)
_S.loader.exec_module(en)
kw, TEAM, _git = en.kw, en.TEAM, en.kw._git
def raw_card(w, work, data):
    """카드 본문 = 날 바이트(두 ref) · 진행/ 폴더 · root fetch."""
    seed, rel = w.tmp / "seed-byz", "design/harness/indices/진행/%s-x.md" % work
    for ref in ("main", "ops/main-base"):
        _git(seed, "checkout", "-q", ref)
        (seed / rel).parent.mkdir(parents=True, exist_ok=True)
        (seed / rel).write_bytes(data)
        _git(seed, "add", "-A"), _git(seed, *en.ID, "commit", "-q", "-m", "raw"), _git(seed, "push", "-q", "origin", ref)
    _git(w.root, "fetch", "-q", "origin")
def test_1_broken_byte_card_round_finishes(tmp_path, monkeypatch):   # ① 0xbb 단독 바이트 카드 · evidence_notice 길 → 바퀴 끝 · ROUND 1줄 · 예외 0(A1 · M1)
    w = en.world(tmp_path, monkeypatch)
    en.done(w, "r9811", card=False)
    raw_card(w, "r9811", "# 인덱스: r9811\n\n## 상태\n- 2026-11-16 complete ".encode("utf-8") + b"\xbb" + " 진행\n".encode("utf-8"))
    w.enable()
    lines = w.round()
    assert len([x for x in lines if x.startswith("ROUND ")]) == 1, lines
    assert not [x for x in lines if "내부 오류" in x], lines
def test_2_call_decodes_replace_rc_kept(tmp_path, monkeypatch):   # ② 깨진 바이트 = U+FFFD · rc 그대로 · 정상 UTF-8 = 글자 같음(A1)
    w = en.world(tmp_path, monkeypatch)
    k = w.keeper()
    bad = k.call([sys.executable, "-c", "import sys; sys.stdout.buffer.write(b'a\\xbbb'); sys.stderr.buffer.write(b'e\\xbb'); sys.exit(3)"])
    assert bad == (3, "a\ufffdb", "e\ufffd"), bad
    good = k.call([sys.executable, "-c", "import sys; sys.stdout.buffer.write('완성 «끝» ✓\\n'.encode('utf-8'))"])
    assert good == (0, "완성 «끝» ✓\n", ""), good
def two_works(w, monkeypatch, first):
    """한 팀 work 2개(r9821 · r9822) · 첫 work one_work = first(그 keeper 모듈의 예외 이름) 예외 · 둘째 = close · close 호출 기록."""
    for work in ("r9821", "r9822"):
        w.work(work)
    w.enable()
    k, seen, closed = w.keeper(), [], []
    exc = type(k).run_once.__globals__.get(first, RuntimeError)   # Cut · Ungraded = 그 keeper 모듈의 클래스(대역은 모듈을 새로 읽는다)
    def one_work(team, work, *a):
        seen.append(work)
        if work == "r9821":
            raise exc("%s:%s:b1" % (team, work))
        return "close"
    monkeypatch.setattr(k, "one_work", one_work)
    monkeypatch.setattr(k, "close", lambda team, work, *a: closed.append(work))
    return k, seen, closed, exc
def test_3_unexpected_error_one_line_next_work(tmp_path, monkeypatch):   # ③ RuntimeError → 판정 불가 <work> 내부 오류 1줄 · 둘째 work close 1(A2 · M3)
    w = en.world(tmp_path, monkeypatch)
    k, seen, closed, _ = two_works(w, monkeypatch, "RuntimeError")
    lines = w.round(k)
    got = [x for x in lines if "내부 오류" in x]
    assert got == ["판정 불가 %s r9821 내부 오류 RuntimeError" % TEAM], lines
    assert seen == ["r9821", "r9822"] and closed == ["r9822"], (seen, closed, lines)
    assert len([x for x in lines if x.startswith("ROUND ")]) == 1, lines
def test_4a_ungraded_skips_no_line(tmp_path, monkeypatch):   # ④ Ungraded = 지금처럼 다음 work · 내부 오류 줄 0(A2 · A3)
    w = en.world(tmp_path, monkeypatch)
    k, seen, closed, _ = two_works(w, monkeypatch, "Ungraded")
    lines = w.round(k)
    assert seen == ["r9821", "r9822"] and closed == ["r9822"] and not [x for x in lines if "내부 오류" in x], (seen, closed, lines)
def test_4b_cut_rises(tmp_path, monkeypatch):   # ④ Cut = team_round 가 잡지 않음(위로) · 둘째 work 0 · 내부 오류 줄 0(A2 · A3 · M2)
    w = en.world(tmp_path, monkeypatch)
    k, seen, closed, cut = two_works(w, monkeypatch, "Cut")
    assert cut.__name__ == "Cut" and issubclass(cut, BaseException) and not issubclass(cut, Exception)
    with pytest.raises(cut):
        k.locked(lambda: k.team_round(TEAM))
    assert seen == ["r9821"] and closed == [] and not [x for x in k.lines if "내부 오류" in x], (seen, closed, k.lines)
