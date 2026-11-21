"""r2371 keeper plist 틀 ProcessType — launchd 틀(com.byz.ft2-keeper.plist.in)이 ProcessType Interactive 키를 가진다.
반례 ①~⑤ · 변이 M1~M5 · 실 launchd·LaunchAgents·launchctl 0 · sleep 0 · 시험 1개 70초 안팎.
기준판 = 팩 main 9845a0cf(이 카드 전 · 키 0) → ① Red. ③ 의 기준판 렌더도 그 커밋의 틀에서 뽑는다(착지 뒤에도 뜻 그대로).
치환 표 = r1812 ⑩ 과 같은 다섯 자리(@FT2_HOME@ @ROOT@ @PACK_REPO@ @SEAT_CLOSE@ @TMUX_SOCKET@).
"""
import importlib.util
import plistlib
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

FT2 = Path(__file__).resolve().parents[1]
BASE = "9845a0cffa03497add88b242828c136723c60733"   # 팩 main r2362 = 이 카드 전
PL = "adapters/pi/launchd/com.byz.ft2-keeper.plist.in"
SL = "adapters/slack/launchd/com.byz.ft2-slack-listen.plist.in"
SUB = (("@FT2_HOME@", "/x/ft2"), ("@ROOT@", "/x/root"), ("@PACK_REPO@", "/x/pack"),
       ("@SEAT_CLOSE@", "/x/c.sh"), ("@TMUX_SOCKET@", "/x/tmux-501/default"))
KEY = "<key>ProcessType</key><string>Interactive</string>"


def render(text):   # r1812 ⑩ 치환 표 그대로
    for old, new in SUB:
        text = text.replace(old, new)
    return text


def rendered(ft2, path=PL):   # 틀 → 설치 렌더 글자
    return render((Path(ft2) / path).read_text(encoding="utf-8"))


def base_text(path):   # 기준판(이 카드 전 팩 main) 틀 바이트
    out = subprocess.run(["git", "-C", str(FT2), "show", "%s:feature-pack/fable-team/ft2/%s" % (BASE, path)],
                         capture_output=True, timeout=25, check=True)
    return out.stdout.decode("utf-8")


def c1(ft2, tmp):   # ① 지금 틀 렌더 → plistlib ProcessType == «Interactive» (기준판 = 키 0 → Red)
    assert plistlib.loads(rendered(ft2).encode("utf-8")).get("ProcessType") == "Interactive"


def c2(ft2, tmp):   # ② ① 렌더 파일 plutil -lint rc0 · Label 줄 바로 다음 키 = ProcessType
    text = rendered(ft2)
    dst = Path(tmp) / "keeper.plist"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")
    assert subprocess.run(["plutil", "-lint", str(dst)], capture_output=True).returncode == 0
    lines = [x.strip() for x in text.splitlines() if x.strip()]
    at = [i for i, x in enumerate(lines) if x.startswith("<key>Label</key>")]
    assert len(at) == 1 and lines[at[0] + 1] == KEY, lines[at[0]:at[0] + 2]


def c3(ft2, tmp):   # ③ ① 렌더에서 ProcessType 을 뺀 dict = 기준판 렌더 dict(키 수 · 값 모두 같음)
    now = plistlib.loads(rendered(ft2).encode("utf-8"))
    old = plistlib.loads(render(base_text(PL)).encode("utf-8"))
    old.pop("ProcessType", None)
    assert now.pop("ProcessType", None) == "Interactive" and now == old


def c4(ft2, tmp):   # ④ slack-listen 틀 바이트 = 기준판 바이트
    assert (Path(ft2) / SL).read_bytes() == base_text(SL).encode("utf-8")


def c5(ft2, tmp):   # ⑤ r1975 ⑨ 새 글자 = 지금 틀 PASS · ProcessType 을 Background 로 바꾼 사본 FAIL
    r1975 = importlib.util.module_from_spec(importlib.util.spec_from_file_location(
        "r1975_c9_r2371", str(Path(__file__).with_name("test_pi_keeper_fetch_targets_r1975.py"))))
    r1975.__spec__.loader.exec_module(r1975)
    r1975.c9(SimpleNamespace(ft2=Path(ft2)))
    tree = Path(tmp) / "bg" / "ft2"
    shutil.copytree(Path(ft2), tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    src = (tree / PL).read_text(encoding="utf-8")
    assert src.count(KEY) == 1, KEY
    (tree / PL).write_text(src.replace(KEY, "<key>ProcessType</key><string>Background</string>"), encoding="utf-8")
    with pytest.raises(AssertionError):
        r1975.c9(SimpleNamespace(ft2=tree))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}


def m1(text):   # 키 지움
    assert text.count("  " + KEY + "\n") == 1
    return text.replace("  " + KEY + "\n", "")


def m2(text):   # 값을 Background 로
    assert text.count(KEY) == 1
    return text.replace(KEY, "<key>ProcessType</key><string>Background</string>")


def m3(text):   # 키를 dict 밖(</dict> 뒤)으로
    assert text.count("  " + KEY + "\n") == 1 and text.count("</dict></plist>") == 1
    return text.replace("  " + KEY + "\n", "").replace("</dict></plist>", "</dict>" + KEY + "</plist>")


def m4(text):   # StartInterval 30
    assert text.count("<key>StartInterval</key><integer>60</integer>") == 1
    return text.replace("<key>StartInterval</key><integer>60</integer>", "<key>StartInterval</key><integer>30</integer>")


def m5(text):   # slack-listen 틀에도 같은 키
    assert text.count("<key>Label</key><string>com.byz.ft2-slack-listen</string>\n") == 1
    return text.replace("<key>Label</key><string>com.byz.ft2-slack-listen</string>\n",
                        "<key>Label</key><string>com.byz.ft2-slack-listen</string>\n  " + KEY + "\n")


MUTANTS = {"M1": (PL, m1, "①"), "M2": (PL, m2, "①"), "M3": (PL, m3, "②"), "M4": (PL, m4, "③"), "M5": (SL, m5, "④")}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](FT2, tmp_path / name)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):   # 변이 = 사본에서만 → 그 사례 FAIL · 변이마다 원본으로 같은 사례 1회 더
    path, mutate, case = MUTANTS[name]
    tree = tmp_path / name / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    target = tree / path
    target.write_text(mutate(target.read_text(encoding="utf-8")), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[case](tree, tmp_path / name / "mut")
    CASES[case](FT2, tmp_path / name / "orig")
