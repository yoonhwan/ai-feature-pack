"""r1666: 시험용 지침 사본을 짧은 /tmp 경로로 만든다.

doorbell 1줄 = «지침 경로 + sha 12자» 라 200바이트 상한이 있다. 워크트리가 깊으면
(예: 팩 .worktrees/<카드>/feature-pack/fable-team/... = 경로 164바이트) 시험 폴더 경로만으로
상한을 넘어 수집 단계에서 죽는다. 지침 내용·지문은 그대로 두고 경로만 짧게 쓴다.
"""
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def short_brief(name='CHECK-BRIEF.md'):
    folder = Path(tempfile.mkdtemp(dir='/tmp'))
    path = folder / name
    path.write_text((HERE / name).read_text(encoding='utf-8'), encoding='utf-8')
    return path


SHORT_BRIEF = short_brief()
