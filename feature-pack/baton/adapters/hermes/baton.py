#!/usr/bin/env python3
"""
baton — Hermes adapter
설치: cp adapters/hermes/baton.py ~/.hermes/plugins/baton.py
      (또는 adapters/hermes/INSTALL.md 참고)

Hermes는 범용 Python plugin hook 시스템이 없으므로,
이 스크립트는 Hermes 세션 전후에 직접 실행하는 CLI 래퍼입니다.

사용법:
  python ~/.hermes/plugins/baton.py on_session_start   # 세션 시작 시
  python ~/.hermes/plugins/baton.py on_session_end     # 세션 종료 시
  python ~/.hermes/plugins/baton.py status             # 현재 phase 상태
  python ~/.hermes/plugins/baton.py journal <message>  # JOURNAL.md 기록
  python ~/.hermes/plugins/baton.py harness <name>     # HARNESS 필드 갱신

Hermes 설정(.hermes/config.yaml)에 shell_hooks 지원 시:
  pre_session:  python ~/.hermes/plugins/baton.py on_session_start
  post_session: python ~/.hermes/plugins/baton.py on_session_end

키워드 트리거:
  "이어서" / "진행" / "go" / "continue" / "next" → /baton:resume 안내 출력
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# 상수
# ---------------------------------------------------------------------------

BATON_HOME = Path(os.environ.get("BATON_HOME", Path.home() / ".baton" / "current"))
BATON_BIN = BATON_HOME / "bin" / "baton"

RESUME_KEYWORDS = re.compile(
    r"\b(이어서|진행|go|continue|next)\b", re.IGNORECASE
)

HARNESS_TOOL_NAMES = {"Skill", "Agent", "Task", "skill", "agent", "task"}


# ---------------------------------------------------------------------------
# 헬퍼: baton CLI 실행
# ---------------------------------------------------------------------------

def _baton_run(*args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    """baton CLI 호출. BATON_HOME 미설치 시 silent skip."""
    if not BATON_BIN.exists():
        return subprocess.CompletedProcess(args=[], returncode=1, stdout="", stderr="")
    cmd = [str(BATON_BIN)] + list(args)
    return subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        env={**os.environ, "BATON_HOME": str(BATON_HOME)},
    )


def _baton_installed() -> bool:
    return BATON_BIN.exists()


# ---------------------------------------------------------------------------
# 헬퍼: .baton/handoff/ 탐색 (부모 방향)
# ---------------------------------------------------------------------------

def find_baton_handoff(start: Path | None = None) -> Path | None:
    """현재 디렉토리에서 부모 방향으로 .baton/handoff/ 탐색."""
    d = Path(start or os.getcwd()).resolve()
    while d != d.parent:
        candidate = d / ".baton" / "handoff"
        if candidate.is_dir():
            return candidate
        d = d.parent
    return None


def find_current_md(start: Path | None = None) -> Path | None:
    handoff = find_baton_handoff(start)
    if handoff:
        p = handoff / "CURRENT.md"
        if p.exists():
            return p
    return None


def find_journal_md(start: Path | None = None) -> Path | None:
    handoff = find_baton_handoff(start)
    if handoff:
        p = handoff / "JOURNAL.md"
        if p.exists():
            return p
    return None


# ---------------------------------------------------------------------------
# 헬퍼: frontmatter 읽기/쓰기
# ---------------------------------------------------------------------------

def _parse_frontmatter(text: str) -> dict[str, str]:
    """YAML frontmatter(---...---) 파싱 → dict."""
    lines = text.splitlines()
    in_fm = False
    result: dict[str, str] = {}
    for line in lines:
        if line.strip() == "---":
            in_fm = not in_fm
            continue
        if in_fm:
            m = re.match(r"^(\w+):\s*(.*)$", line)
            if m:
                result[m.group(1)] = m.group(2).strip()
    return result


def _update_frontmatter_field(path: Path, field: str, value: str) -> None:
    """CURRENT.md frontmatter의 특정 필드를 갱신."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"^{re.escape(field)}:.*$", re.MULTILINE)
    if pattern.search(text):
        new_text = pattern.sub(f"{field}: {value}", text)
        path.write_text(new_text, encoding="utf-8")


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# 헬퍼: JOURNAL.md 조작
# ---------------------------------------------------------------------------

def _last_turn_number(journal: Path) -> int:
    """JOURNAL.md에서 마지막 Turn 번호 추출."""
    text = journal.read_text(encoding="utf-8")
    matches = re.findall(r"^## .+? — Turn (\d+)", text, re.MULTILINE)
    return int(matches[-1]) if matches else 0


def journal_append_intent(user_msg: str, start: Path | None = None) -> None:
    """JOURNAL.md에 새 Turn + INTENT 추가 (UserPromptSubmit 동등)."""
    journal = find_journal_md(start)
    if not journal:
        return
    last = _last_turn_number(journal)
    turn = last + 1
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    intent = user_msg[:200].replace("\n", " ")
    entry = (
        f"\n## {ts} — Turn {turn}\n"
        f"- **INTENT**: {intent}\n"
        f"- **HARNESS**: -\n"
        f"- **ACTIONS**: -\n"
        f"- **TODO**: -\n"
    )
    with journal.open("a", encoding="utf-8") as f:
        f.write(entry)

    current = find_current_md(start)
    if current:
        _update_frontmatter_field(current, "last_updated", _iso_now())


def journal_set_last_harness(harness_name: str, start: Path | None = None) -> None:
    """JOURNAL.md 마지막 Turn의 HARNESS 필드 갱신 (PostToolUse 동등)."""
    journal = find_journal_md(start)
    if not journal:
        return
    text = journal.read_text(encoding="utf-8")
    # 마지막 "- **HARNESS**: -" 줄 교체
    lines = text.splitlines()
    last_idx = None
    for i, line in enumerate(lines):
        if line.strip() == "- **HARNESS**: -":
            last_idx = i
    if last_idx is not None:
        lines[last_idx] = f"- **HARNESS**: {harness_name}"
        journal.write_text("\n".join(lines) + "\n", encoding="utf-8")

    current = find_current_md(start)
    if current:
        _update_frontmatter_field(current, "last_harness", harness_name)


# ---------------------------------------------------------------------------
# 헬퍼: CURRENT.md status 갱신
# ---------------------------------------------------------------------------

def current_set_status(status: str, start: Path | None = None) -> None:
    """CURRENT.md frontmatter status 필드 갱신."""
    current = find_current_md(start)
    if current:
        _update_frontmatter_field(current, "status", status)
        _update_frontmatter_field(current, "last_updated", _iso_now())


# ---------------------------------------------------------------------------
# 헬퍼: tmux 세션 이름
# ---------------------------------------------------------------------------

def baton_tmux_session_name(phase_id: str, start: Path | None = None) -> str:
    """tmux 세션명 계산 (lib/tmux.sh baton_tmux_session_name 동등)."""
    project = "baton"
    d = Path(start or os.getcwd()).resolve()
    while d != d.parent:
        cfg = d / ".baton" / "config.json"
        if cfg.exists():
            try:
                data = json.loads(cfg.read_text(encoding="utf-8"))
                project = data.get("project_name", "baton")
            except Exception:
                pass
            break
        d = d.parent
    return f"baton-{project}-{phase_id}"


def _tmux_session_exists(session: str) -> bool:
    if not os.environ.get("BATON_TMUX_ENABLE", "").lower() == "true":
        return False
    try:
        r = subprocess.run(
            ["tmux", "has-session", "-t", session],
            capture_output=True,
        )
        return r.returncode == 0
    except FileNotFoundError:
        return False


# ---------------------------------------------------------------------------
# 핵심 액션: on_session_start
# ---------------------------------------------------------------------------

def on_session_start() -> None:
    """세션 시작 시 실행. paused phase 감지 + 환경 검증."""
    if not _baton_installed():
        return

    current = find_current_md()
    if not current:
        # main/master 브랜치 힌트
        try:
            branch = subprocess.check_output(
                ["git", "branch", "--show-current"], stderr=subprocess.DEVNULL, text=True
            ).strip()
            if branch in ("main", "master"):
                print("─" * 41)
                print("💡 baton: main/master 브랜치입니다.")
                print("  새 페이즈: baton wt-create <name>")
                print("  목록 확인: baton status")
                print("─" * 41)
        except Exception:
            pass
        return

    fm = _parse_frontmatter(current.read_text(encoding="utf-8"))
    status = fm.get("status", "")
    phase_id = fm.get("phase_id", "?")
    branch = fm.get("branch", "(unknown)")
    last_updated = fm.get("last_updated", "(unknown)")
    last_harness = fm.get("last_harness", "")

    if status == "paused":
        print("─" * 41)
        print("📌 일시정지된 페이즈가 있어요")
        print(f"  Phase: {phase_id} (paused, by hermes)")
        print(f"  Branch: {branch}")
        print(f"  Last updated: {last_updated}")
        if last_harness and last_harness not in ("null", "-", ""):
            print(f"  Last harness: {last_harness}")
        print()
        print("이어서: \"이어서\" / \"진행\" / \"go\" / \"continue\" / \"next\"")
        print("다른 작업: 무시하고 새 요청 입력")
        print("─" * 41)

        # tmux 세션 정보 표시
        if os.environ.get("BATON_TMUX_ENABLE", "").lower() == "true":
            sess = baton_tmux_session_name(phase_id)
            if _tmux_session_exists(sess):
                print(f"  tmux: {sess} (attach: tmux a -t {sess})")

    # 환경 파일 존재 검증
    handoff = current.parent
    for fname in ("PLAN.md", "JOURNAL.md", "NEXT.md"):
        if not (handoff / fname).exists():
            print(f"[baton] WARN: .baton/handoff/{fname} 가 없습니다 (핸드오프 파일 누락).")

    # 깨진 심볼릭 링크 검증
    wt_root = handoff.parent.parent
    for link_name in (".env", ".claude", ".env.local", ".env.worktree"):
        link = wt_root / link_name
        if link.is_symlink() and not link.exists():
            print(f"[baton] WARN: 깨진 심볼릭 링크 감지: {link_name}")


# ---------------------------------------------------------------------------
# 핵심 액션: on_session_end
# ---------------------------------------------------------------------------

def on_session_end() -> None:
    """세션 종료 시 실행. active phase → paused 자동 전환."""
    if not _baton_installed():
        return

    current = find_current_md()
    if not current:
        return

    fm = _parse_frontmatter(current.read_text(encoding="utf-8"))
    status = fm.get("status", "")
    phase_id = fm.get("phase_id", "?")

    if status != "active":
        return

    current_set_status("paused")
    print("[baton SessionEnd] 세션이 종료됩니다.")
    print(f"  Phase: {phase_id} → paused 로 저장됨")
    print("  다음 세션 시작 시 .baton/handoff/NEXT.md 를 먼저 확인하세요.")
    print("  이어서 작업하려면: \"이어서\" / \"continue\" / \"go\"")

    # 마지막 dump 안내
    handoff = current.parent
    next_md = handoff / "NEXT.md"
    if next_md.exists():
        size = next_md.stat().st_size
        if size < 100:
            print("[baton] WARN: NEXT.md 가 거의 비어있습니다. 다음 세션 안내를 작성하세요.")


# ---------------------------------------------------------------------------
# 액션: status
# ---------------------------------------------------------------------------

def cmd_status() -> None:
    """baton status 출력."""
    _baton_run("status")


# ---------------------------------------------------------------------------
# 액션: keyword_check
# ---------------------------------------------------------------------------

def keyword_check(user_msg: str) -> None:
    """키워드 트리거 감지 → resume 안내."""
    if RESUME_KEYWORDS.search(user_msg):
        current = find_current_md()
        if current:
            fm = _parse_frontmatter(current.read_text(encoding="utf-8"))
            if fm.get("status") == "paused":
                phase_id = fm.get("phase_id", "?")
                print(f"[baton] 이어서 모드: phase={phase_id}")
                print("  CURRENT.md + JOURNAL.md + NEXT.md 를 확인하고 작업을 재개하세요.")
                _baton_run("status")


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------

def main() -> None:
    if not sys.argv[1:]:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]

    if cmd == "on_session_start":
        on_session_start()

    elif cmd == "on_session_end":
        on_session_end()

    elif cmd == "status":
        cmd_status()

    elif cmd == "journal":
        msg = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        if msg:
            journal_append_intent(msg)
            print(f"[baton] JOURNAL.md 에 intent 기록: {msg[:60]}...")
        else:
            print("사용법: baton.py journal <message>")

    elif cmd == "harness":
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        if name:
            journal_set_last_harness(name)
            print(f"[baton] HARNESS 필드 갱신: {name}")
        else:
            print("사용법: baton.py harness <harness-name>")

    elif cmd == "keyword":
        msg = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        keyword_check(msg)

    elif cmd == "set-status":
        status = sys.argv[2] if len(sys.argv) > 2 else ""
        if status in ("active", "paused", "done"):
            current_set_status(status)
            print(f"[baton] status → {status}")
        else:
            print("사용법: baton.py set-status <active|paused|done>")

    else:
        # 알 수 없는 명령은 baton CLI에 위임
        _baton_run(cmd, *sys.argv[2:])


if __name__ == "__main__":
    main()
