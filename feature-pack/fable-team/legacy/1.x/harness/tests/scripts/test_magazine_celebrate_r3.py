"""r867 r3·r4 — 원장 행 축하 0(r4 · 카드만) · eli5 상한 = 조립된 호출 프롬프트 전체 · 카드 축하 = 제목 + sha (DA⑥ r2 반례 3건).

판 날짜 10-18 → 창 = 10-17 00:00 ~ 10-18 08:00 KST. 그 전 이력은 test_magazine_celebrate 의 같은 fixture.
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE python3 -m pytest tests/scripts/test_magazine_celebrate_r3.py -q
"""
import json

import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다
from test_magazine_celebrate import CARD, SHAS, commit, env, ledger, part1, run  # noqa: F401 — 같은 임시 원장·git 이력

import magazine_celebrate as mc
import magazine_celebrate_eli5 as mb

DAY = "2026-10-18"
LONG = "가 " * 25280


def _runner(prompts: list[str]):
    def runner(cmd, prompt, timeout):
        prompts.append(prompt)
        ids = [u["ref"] for u in json.loads(prompt.split("<자료>\n", 1)[1].split("\n</자료>", 1)[0])]
        return json.dumps({"units": [{"ref": r, "icon": "🌱", "title": "좋아졌어요", "analogy": "꽃이 피었어요", "lines": ["쉬워졌어요"]} for r in ids]}, ensure_ascii=False)
    return runner


def test_a_whole_prompt_stays_under_the_limit_whatever_the_input():
    prompts: list[str] = []
    odd = '"\\\n' * 9000  # JSON 이스케이프로 두 배가 되는 글
    cases = [[{"ref": "원장:" + LONG, "자료": LONG + " — 완료"}, {"ref": "b", "자료": "짧아요"}], [{"ref": "c", "자료": odd}], [{"ref": "d", "자료": "짧아요"}]]
    for units in cases:
        result = mb.explain(units, "cmd", "쉬운 말", _runner(prompts))
        assert all(isinstance(result[u["ref"]], dict) for u in units)  # 원래 ref 로 되돌려 받는다
    assert len(prompts) == 3 and all(len(p) <= mb.PROMPT_LIMIT for p in prompts)
    assert mb.CUT_MARK in prompts[0] and mb.CUT_MARK in prompts[1] and mb.CUT_MARK not in prompts[2]
    assert '"자료": "짧아요"' in prompts[0]  # 짧은 칸은 그대로 — 긴 칸부터 깎는다


def test_c_ledger_rows_alone_are_not_celebrated_and_the_head_says_so(env):  # noqa: F811 — 위에서 가져온 fixture
    # r4 — 원장 행 축하 갈래 삭제(카드만 · DA⑥ r1~r3 반례 8 중 5 가 원장 행) · 창 안 sha 행·상태 칸 sha 가 앞인 행(DA r3 반례 1)·sha 없는 완료 행(반례 2) 모두 축하 0
    _, repo, _ = env
    sha = commit(repo, "2026-10-17T09:00:00+09:00", {"code/new.txt": "n"})
    rows = {"새 화면 열기": f"완료 — 화면 확인 (main {sha})", "상태 칸 앞 커밋": f"완료 — 옛 착지 {SHAS['운영']} 뒤 새 착지 (main {sha})",
            "근거 없는 완료": "완료 — 시험 통과", "운영 화면 새 이름": f"완료 — 창 전 착지 (main {SHAS['운영']})"}
    commit(repo, "2026-10-17T10:00:00+09:00", {"doc.md": ledger(rows)})
    assert mc.collect(str(repo), "HEAD", DAY)[1] == []
    rc, page = run(env, DAY)
    top = part1(page)
    assert rc == 0 and "10-17 00:00 ~ 10-18 08:00 사이 인덱스 카드 기준 0건 — 원장 행 완료는 이번 판 축하에 싣지 않아요" in top
    assert "끝낸 일은 0건" not in page and 'class="done"' not in top and not any(task in top for task in rows)


def test_d_card_celebration_carries_only_title_and_sha(env):  # noqa: F811
    _, repo, _ = env
    bg = "카드 배경이 길어요. " * 60 + "일부 읽기는 실패했어요"
    sha = commit(repo, "2026-10-17T10:00:00+09:00", {"design/harness/indices/완성/r950-long-card.md": CARD.format(n=950, bg=bg)})
    done = mc.collect(str(repo), "HEAD", DAY)[1]
    assert [(d.title, d.source) for d in done] == [("r950-easy-news", "r950-easy-news")] and done[0].evidence.startswith(sha)  # 제목 = 카드 머리 «끝:» 앞 이름
    rc, page = run(env, DAY)
    top = part1(page)
    assert rc == 0 and "r950-easy-news" in top and "카드 배경" not in top and "실패했어요" not in page
