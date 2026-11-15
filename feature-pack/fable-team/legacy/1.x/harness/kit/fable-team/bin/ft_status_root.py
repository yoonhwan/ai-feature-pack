"""ft_status_root — r1982: 위성 루트에서 부른 감시 «status» 의 데이터 루트(roots.tsv 사람우편함 칸이 가리키는 본 루트 · 읽기만 · 쓰기 0)."""
import os
from pathlib import Path

from ft_team_lib import TeamPathError, root_row, roots


def status_root(R: Path) -> tuple[Path, str]:
    """(데이터 루트, 머리 꼬리) — FT_ROOT 있음·R 에 directive-roots.tsv 있음·명부 행 없음·5칸 «.»·경로 없음·명부 깨짐 = (R, "") 지금 그대로(추정 0)."""
    if os.environ.get("FT_ROOT") or (R / ".fable-team/state/directive-roots.tsv").is_file():
        return R, ""
    try:
        me, rows = root_row(R), roots()
    except TeamPathError:
        return R, ""
    human = Path(str(me["human_mail"])) if me and str(me["human_mail"]).startswith("/") else None
    for r in rows:
        if human and r["name"] != me["name"] and human.is_dir() and human.resolve() == (r["path"] / ".fable-team/comm").resolve():
            return r["path"], f" · 데이터 루트 {r['name']}"
    return R, ""
