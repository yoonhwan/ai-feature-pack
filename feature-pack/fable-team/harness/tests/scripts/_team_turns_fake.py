"""r850 r5 — 판정 원천(턴 판독)을 «실 jsonl + 가짜 tmux» 로 만든다.

r4 까지 시험은 `ft_team_turns.team_turns` 를 스텁했는데, 판정이 하위 프로세스 1개로 옮겨 가 스텁이 프로세스 경계를 못 넘는다.
그래서 스텁 대신 원천 자체(좌석 jsonl · tmux pane 목록)를 임시 폴더에 만든다 — 판정 하위가 실제로 읽는다(실 좌석·실 tmux·실 홈 0).
"""
import json
import re
from pathlib import Path

END = "2026-10-24T13:50:00"  # 턴 끝(고정) — 시계는 부르는 쪽 FT_NEWS_NOW/FT_BOARD_NOW 가 정한다


def _enc(cwd: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


def write_jsonl(path: Path, seat: str, state: str, end: str = END) -> None:
    """턴 1개 — 이름표(머리에 있어야 ft_api_outage_util.find_jsonls 가 찾는다) + user/assistant + (WORKING 아니면 turn_duration) + (WORKING 이면 다음 user)."""
    rows = [{"type": "custom-title", "customTitle": seat},
            {"type": "user", "message": {"content": "일"}}, {"type": "assistant", "message": {"content": []}}]
    rows.append({"type": "user", "message": {"content": "다음"}} if state == "WORKING"
                else {"type": "system", "subtype": "turn_duration", "timestamp": end, "durationMs": 1000})
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows), encoding="utf-8")


def install(tmp_path: Path, monkeypatch, turns: dict[str, tuple[str, str]]) -> str:
    """turns = 좌석 → (턴 상태, 사유) — 사유 «jsonl 없음» = pane 만 있고 파일 없음 · 상태 WORKING/IDLE/PENDING/UNKNOWN.
    FT_TMUX = 가짜 tmux(list-panes 만 응답 · 좌석 cwd = /wt/<계보>) · FT_CLAUDE_PROJECTS = 임시 폴더. 돌려주는 값 = projects 경로."""
    projects = tmp_path / "projects"
    lines = []
    for seat, (state, why) in turns.items():
        cwd = f"/wt/{seat.split('#')[0]}"
        lines.append(f"{seat}\t{cwd}")
        if why != "jsonl 없음":
            write_jsonl(projects / _enc(cwd) / f"{seat.replace('#', '_')}.jsonl", seat, state)
    stub = tmp_path / "tmux-turns-fake"
    stub.write_text("#!/bin/sh\ncat <<'EOF'\n" + "\n".join(lines) + "\nEOF\n", encoding="utf-8")
    stub.chmod(0o755)
    monkeypatch.setenv("FT_TMUX", str(stub))
    monkeypatch.setenv("FT_CLAUDE_PROJECTS", str(projects))
    return str(projects)
