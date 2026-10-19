"""thread_post_args 기본 채널 회귀 (r474) — reply 의 기본값(None)이 다른 서브명령으로 새지 않는다. 슬랙·파일·외부 호출 0.

r414 의 `rpl.set_defaults(channel=None)` 는 `parents=[common]` 로 공유된 Action 의 `.default` 를 고쳐
start·progress·update… 의 `--channel` 기본값까지 None 으로 만들었다(뉴스 발행 channel_not_found).

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_thread_post_args.py -q
"""
import pytest

import thread_post_args as pa

BLK = ["--issue", "#1", "--seat", "s#1", "--canon", "없음", "--next", "없음", "--resume-script", "r.sh"]
CARD = ["--card", "c.md"]
ARGV = {
    "start": CARD + BLK + ["--text", "t"],
    "progress": CARD + BLK + ["--text", "t"],
    "result": CARD + BLK,
    "check": CARD,
    "repair": CARD,
    "update": ["--key", "board:2026-10-19", "--text-file", "f"],
    "attach": ["--key", "board:2026-10-19", "--file", "f", "--title", "t"],
}


@pytest.mark.parametrize("cmd", sorted(ARGV))
def test_default_channel_is_channel(cmd):  # ⓐ
    assert pa.parse([cmd, *ARGV[cmd]]).channel == pa.CHANNEL


def test_reply_thread_default_none():  # ⓑ 등록부 채널 사용(r414 불변)
    assert pa.parse(["reply", "--thread", "desk", "--text-file", "f"]).channel is None


def test_reply_ts_default_channel():  # ⓒ 옛 --ts 호출 불변
    assert pa.parse(["reply", "--ts", "1.2", "--text-file", "f"]).channel == pa.CHANNEL


@pytest.mark.parametrize("argv", [[c, *a] for c, a in sorted(ARGV.items())]
                         + [["reply", "--thread", "desk", "--text-file", "f"], ["reply", "--ts", "1.2", "--text-file", "f"]])
def test_explicit_channel_wins(argv):  # ⓓ
    assert pa.parse([*argv, "--channel", "C1"]).channel == "C1"


def test_reply_default_does_not_leak_after_parse():  # 같은 프로세스에서 reply 뒤 update — 기본값이 남지 않는다
    pa.parse(["reply", "--thread", "desk", "--text-file", "f"])
    assert pa.parse(["update", *ARGV["update"]]).channel == pa.CHANNEL
