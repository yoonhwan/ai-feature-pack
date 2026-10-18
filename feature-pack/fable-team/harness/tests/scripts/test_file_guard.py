"""file_guard — 슬랙 첨부 파일 게시 «전» 검사 (R231a). 로컬 파일만 · 슬랙 호출 0.

실행: python3 -m pytest tests/scripts/test_file_guard.py -q
"""
import pytest
from _thread_fakes import CARD  # noqa: F401 — sys.path 에 키트 경로를 넣는다

import file_guard as fg
import post_guard as pg

SECRET = "token xoxb-123 here\n"
INTERNAL = "좌석 byz-harness-arch-claude#63 에게\n"


@pytest.fixture(autouse=True)
def _no_human_channels(monkeypatch):
    monkeypatch.delenv(pg.HUMAN_CHANNELS_ENV, raising=False)


def put(tmp_path, name, content="평범한 글\n", mode="w"):
    p = tmp_path / name
    if mode == "wb":
        p.write_bytes(content)
    else:
        p.write_text(content, encoding="utf-8")
    return str(p)


def test_clean_md_passes_on_human_channel(tmp_path):
    fg.check_files([put(tmp_path, "a.md")], "C1", human=True)


def test_secret_in_md_is_rejected_without_quoting_content(tmp_path):
    with pytest.raises(pg.PostGuardError) as e:
        fg.check_files([put(tmp_path, "a.md", SECRET)], "C1", human=True)
    assert "묶음1:slack-token" in str(e.value) and "xoxb" not in str(e.value)


def test_internal_vocab_rejected_on_human_but_passes_on_non_human(tmp_path):
    f = put(tmp_path, "a.md", INTERNAL)
    with pytest.raises(pg.PostGuardError, match="묶음2"):
        fg.check_files([f], "C1", human=True)
    fg.check_files([f], "C1")


def test_env_human_channel_applies_strict_rules(tmp_path, monkeypatch):
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "CH")
    f = put(tmp_path, "a.md", INTERNAL)
    with pytest.raises(pg.PostGuardError, match="묶음2"):
        fg.check_files([f], "CH")
    fg.check_files([f], "CX")


def test_secret_in_file_name_is_rejected(tmp_path):
    with pytest.raises(pg.PostGuardError, match="묶음1:slack-token"):
        fg.check_files([put(tmp_path, "xoxb-123.md")], "C1")


def test_pdf_rejected_on_human_passes_on_non_human(tmp_path):
    f = put(tmp_path, "a.pdf", b"%PDF-x", "wb")
    with pytest.raises(pg.PostGuardError, match="내용 검사 불가 종류"):
        fg.check_files([f], "C1", human=True)
    fg.check_files([f], "C1")


def test_missing_file_is_rejected(tmp_path):
    with pytest.raises(pg.PostGuardError, match="실재하는 파일이 아님"):
        fg.check_files([str(tmp_path / "없음.md")], "C1")


def test_over_one_mib_rejected_exactly_at_limit_passes(tmp_path):
    fg.check_files([put(tmp_path, "ok.txt", b"a" * fg.MAX_BYTES, "wb")], "C1", human=True)
    with pytest.raises(pg.PostGuardError, match="1 MiB"):
        fg.check_files([put(tmp_path, "big.txt", b"a" * (fg.MAX_BYTES + 1), "wb")], "C1", human=True)


@pytest.mark.parametrize("raw", ["hello xoxb-1".encode("utf-16"), b"\xff\xfe\x00ok", b"\xc3\x28 broken"])
def test_non_utf8_or_utf16_rejected(tmp_path, raw):
    with pytest.raises(pg.PostGuardError, match="검사 불가"):
        fg.check_files([put(tmp_path, "a.md", raw, "wb")], "C1")


def test_utf8_bom_secret_still_caught(tmp_path):
    with pytest.raises(pg.PostGuardError, match="묶음1"):
        fg.check_files([put(tmp_path, "a.md", b"\xef\xbb\xbf" + SECRET.encode(), "wb")], "C1")


def test_second_of_three_rejects_the_whole_set(tmp_path):
    files = [put(tmp_path, "a.md"), put(tmp_path, "b.md", SECRET), put(tmp_path, "c.md")]
    with pytest.raises(pg.PostGuardError, match="b.md"):
        fg.check_files(files, "C1", human=True)


def test_symlink_is_judged_by_its_target(tmp_path):
    target = tmp_path / "secret.md"
    target.write_text(SECRET, encoding="utf-8")
    link = tmp_path / "safe.md"
    link.symlink_to(target)
    with pytest.raises(pg.PostGuardError, match="묶음1"):
        fg.check_files([str(link)], "C1")
    pdf_link = tmp_path / "ok.md"
    pdf_link.symlink_to(put(tmp_path, "t.pdf", b"%PDF", "wb"))
    with pytest.raises(pg.PostGuardError, match="내용 검사 불가 종류"):
        fg.check_files([str(pdf_link)], "C1", human=True)


def test_dotdot_path_resolves_to_real_file(tmp_path):
    (tmp_path / "sub").mkdir()
    put(tmp_path, "s.md", SECRET)
    with pytest.raises(pg.PostGuardError, match="묶음1"):
        fg.check_files([str(tmp_path / "sub" / ".." / "s.md")], "C1")


def roster(tmp_path, monkeypatch, **seats):
    (tmp_path / ".fable-team").mkdir(exist_ok=True)
    for name, body in seats.items():
        (tmp_path / ".fable-team" / f"seats-{name}.json").write_text(body, encoding="utf-8")
    monkeypatch.setenv(pg.ROOT_ENV, str(tmp_path))


def test_roster_slack_channel_makes_pdf_and_internal_md_rejected(tmp_path, monkeypatch):
    roster(tmp_path, monkeypatch, planner='{"_slack_channel": "CDESK"}', kk='{"_master": "m#1"}')
    with pytest.raises(pg.PostGuardError, match="내용 검사 불가 종류"):
        fg.check_files([put(tmp_path, "a.pdf", b"%PDF", "wb")], "CDESK")
    with pytest.raises(pg.PostGuardError, match="묶음2"):
        fg.check_files([put(tmp_path, "a.md", INTERNAL)], "CDESK")
    fg.check_files([put(tmp_path, "b.md", INTERNAL)], "COTHER")  # 명부에 없는 채널 = 비사람


def test_roster_channel_list_and_env_union(tmp_path, monkeypatch):
    roster(tmp_path, monkeypatch, a='{"_slack_channel": ["C1", "C2"]}')
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "C3")
    assert pg.human_channels() == {"C1", "C2", "C3"}


def test_env_only_when_no_roster_has_slack_channel(tmp_path, monkeypatch):
    roster(tmp_path, monkeypatch, kk='{"_master": "m#1"}')
    monkeypatch.setenv(pg.HUMAN_CHANNELS_ENV, "CENV")
    assert pg.human_channels() == {"CENV"}


def test_broken_roster_json_raises_and_blocks_post(tmp_path, monkeypatch):
    roster(tmp_path, monkeypatch, planner="{not json")
    with pytest.raises(pg.PostGuardError, match="사람 채널 판정 불가"):
        pg.check("평범", "C1")
    with pytest.raises(pg.PostGuardError, match="사람 채널 판정 불가"):
        fg.check_files([put(tmp_path, "a.md")], "C1")


def test_missing_roster_dir_raises_and_neither_source_means_secret_check_only(tmp_path, monkeypatch):
    monkeypatch.setenv(pg.ROOT_ENV, str(tmp_path / "없음"))
    with pytest.raises(pg.PostGuardError, match="명부 폴더 없음"):
        pg.check("평범", "C1")
    roster(tmp_path, monkeypatch)  # 폴더만 있고 명부 0개 · env 없음
    fg.check_files([put(tmp_path, "a.md", INTERNAL)], "C1")  # 내부 어휘 통과
    with pytest.raises(pg.PostGuardError, match="묶음1"):
        fg.check_files([put(tmp_path, "b.md", SECRET)], "C1")


# ── R231a 교정 3 H1 — 종류·내용 판정은 «실제 대상» 기준(별칭 확장자 무시) ──


def test_pdf_alias_to_secret_md_is_content_checked_on_non_human(tmp_path):
    real = put(tmp_path, "source.md", SECRET)
    alias = tmp_path / "alias.pdf"
    alias.symlink_to(real)
    with pytest.raises(pg.PostGuardError, match="묶음1"):
        fg.check_files([str(alias)], "C1")


def test_md_alias_to_pdf_rejected_on_human_and_content_skipped_on_non_human(tmp_path):
    real = put(tmp_path, "real.pdf", b"%PDF-" + SECRET.encode(), "wb")
    alias = tmp_path / "alias.md"
    alias.symlink_to(real)
    with pytest.raises(pg.PostGuardError, match="내용 검사 불가 종류"):
        fg.check_files([str(alias)], "C1", human=True)
    got = fg.check_files([str(alias)], "C1")  # 비사람 · 대상 PDF = 실재만
    assert got[0].name == "alias.md" and got[0].data.startswith(b"%PDF-")


def test_secret_in_target_file_name_rejected_even_if_alias_is_clean(tmp_path):
    real = put(tmp_path, "xoxb-123.md")
    alias = tmp_path / "clean.md"
    alias.symlink_to(real)
    with pytest.raises(pg.PostGuardError, match="묶음1:slack-token"):
        fg.check_files([str(alias)], "C1")


def test_check_files_returns_the_checked_bytes(tmp_path):
    got = fg.check_files([put(tmp_path, "a.md", "정상\n")], "C1")
    assert [(c.name, c.data, c.content_type) for c in got] == [("a.md", "정상\n".encode(), "text/markdown")]
