"""풀 디테일 시험 공용 — 설계 §3 `detail` 칸 픽스처 · 가짜 eli5 모듈 · 가짜 PDF 변환기 (네트워크 0).

①(수집)이 같은 모양의 DETAIL_FIXTURE 를 만든다 — 모양은 설계 §3 으로 고정, 랜딩 때 하나로 합친다.
"""
import types

from _magazine_fakes import fake_model

EASY_HTML = "<!doctype html><html><body>쉬운 판</body></html>"


class Eli5Error(RuntimeError):
    pass


def detail_fixture(extra_lines: int = 0) -> dict:
    """extra_lines > 0 이면 D3 relay 전문 줄을 늘려 여러 쪽 PDF 가 되게 한다."""
    return {
        "refs": [{"name": "origin/main", "start_sha": "a" * 40, "end_sha": "b" * 40}],
        "units": [{"team": "harness", "path": "design/harness/indices/완성/proposal-tools.md", "title": "제안서 도구 3개 <b>",
                   "why": "제안서를 한곳에서 낸다.\n두 번째 줄 — 이슈 #885 참고 (seat claude#13)", "coord": "C축 / 닫는 증거: 세트 줄",
                   "evidence": ["세트: " + "c" * 40 + " · 시험: pytest rc=0 · 이슈: 0"], "da": "design/harness/DA-x.md#§3",
                   "moved_sha": "d" * 40, "ref": "origin/main"}],
        "malformed": [],
        "verdict_sections": [{"path": "design/harness/OPS-VERDICTS-20261008.md", "section": "§47", "title": "판정 352", "body": "본문 1\n본문 2\n\n본문 4"}],
        "decisions": [
            {"n": 352, "ts": "2026-10-07T20:00:00+09:00", "to": "byz-harness-master-claude#12", "body": "판정 352 제안서 흐름 확정",
             "relay_path": "/tmp/mbox/x.md", "relay_text": "\n".join(f"전문 {i} 줄" for i in range(2 + extra_lines)),
             "rollback": ["되돌림: PR revert"], "more": 1},
            {"n": 353, "ts": "2026-10-07T21:00:00+09:00", "to": "byz-harness-arch-claude#10", "body": "판정 353", "relay_path": None,
             "relay_text": None, "rollback": [], "more": 0},
        ],
        "merge_bodies": {"1" * 40: "Why: 요약.\nWhat: 미러.\nVerify: 시험.\nImpact: 없음."},
        "issue_evidence": {"880": "닫는 증거 댓글\n둘째 줄"},
        "open": {"cards": [{"team": "harness", "state": "진행", "path": "design/harness/indices/진행/a.md", "title": "열린 카드", "tail": ["a", "b", "c"]}],
                 "requests": [{"id": "R13", "text": "열린 요청"}], "holds": [{"path": "design/harness/DA-y.md", "verdict": "HOLD"}],
                 "breaches": [{"path": "state/gce-op-model/BREACH.md", "text": "# GCE 감시\n- 86h 경과"}]},
        "seats_closed": [{"path": "design/harness/NANO-LEDGER-20261008.md", "line": "| x | 닫힘 |"}],
        "appendix": [{"path": "design/harness/BRIEFING-morning-20261008.md", "text": "브리핑 1\n브리핑 2"}],
    }


def fake_full_model(extra_lines: int = 0) -> dict:
    return {**fake_model(), "detail": detail_fixture(extra_lines)}


def fake_eli5(fail: str | None = None, html: str = EASY_HTML) -> types.ModuleType:
    """sys.modules['magazine_eli5'] 에 넣는 가짜 — fail 이면 Eli5Error(fail) 를 던진다."""
    mod = types.ModuleType("magazine_eli5")
    mod.Eli5Error = Eli5Error  # type: ignore[attr-defined]

    def build(model, notes, cmd):  # noqa: ANN001
        if fail:
            raise Eli5Error(fail)
        return html

    mod.build = build  # type: ignore[attr-defined]
    return mod


def fake_pdf(pages: int = 3):
    """cli.html_to_pdf 대신 — PDF 바이트를 쓰고 쪽 수를 돌려준다. 인자는 (html, pdf, 바닥글 라벨)."""
    def convert(_html, pdf_path, *_a, **_k):  # noqa: ANN001, ANN202
        pdf_path.write_bytes(b"%PDF-fake")
        return pages
    return convert
