"""ft_news_ledger_round — planner 뉴스 회차의 «한 회차 = 한 sha» 고정 + 원장 사본 checkout 막힘 통지 (r1348 · ft_news_ledger.py 가 부른다).

고정(설계 3·4): 회차 시작에 FT_GOAL_REPO(기본 원장 리포)의 «FT_TEAMS_REF 또는 origin/main» 을 rev-parse 1회(7초)로 40자 sha 로 풀어
  os.environ["FT_TEAMS_REF"] = sha · os.environ["FT_TEAMS_REF_PINNED_FROM"] = 푼 ref 이름. 초안 표지·골 표·팀 표·검증 렌더가 전부 같은 sha 를 읽는다.
  원장 사본은 BYZ 워크트리라 다른 좌석의 fetch 가 회차 도중 origin/main 을 옮긴다(회차 5분 · 표지 sha10 ≠ 검증 sha10 → 발행 0).
  풀기 실패 = RuntimeError(호출부가 ERROR 1줄 · rc≠0 · 발행 0) — 움직이는 ref 로 되돌아가는 폴백 0.
통지(설계 5): 원장 사본 checkout 이 «untracked … would be overwritten» 로 막히면 planner [긴급] 1통(같은 사유 10분 1번 · goal_gate.notify_planner 꼴).
  자동으로 지우거나 옮기지 않는다 — 남의 파일일 수 있다(옮김은 사람·master 손).
"""
import hashlib
import json
import logging
import os
import re
import subprocess
import time
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")
GIT_S = 7           # rev-parse 1회 상한(7초 룰)
DEDUP_S = 10 * 60   # 같은 사유 통지 억제 창
SHA40 = re.compile(r"[0-9a-f]{40}")
FROM_ENV = "FT_TEAMS_REF_PINNED_FROM"


def pin_round_ref(repo: Path) -> str:
    """회차 시작 ref 를 40자 sha 로 고정하고 sha 를 돌려준다. 이미 고정된 프로세스(같은 프로세스 둘째 회차)는 «처음 푼 ref 이름» 에서 다시 푼다."""
    base = os.environ.get(FROM_ENV) or os.environ.get("FT_TEAMS_REF") or "origin/main"
    git_repo = Path(os.environ.get("FT_GOAL_REPO") or repo)
    try:
        done = subprocess.run(["git", "-C", str(git_repo), "rev-parse", "--verify", f"{base}^{{commit}}"], capture_output=True, text=True, timeout=GIT_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"회차 시작 ref 고정 실패 {base}@{git_repo.name}: {e}") from e
    sha = done.stdout.strip()
    if done.returncode != 0 or not SHA40.fullmatch(sha):
        raise RuntimeError(f"회차 시작 ref 고정 실패 {base}@{git_repo.name}: rc={done.returncode} {done.stderr.strip()[:120]}")
    os.environ[FROM_ENV], os.environ["FT_TEAMS_REF"] = base, sha
    LOG.info("회차 ref 고정 %s → %s", base, sha[:10])
    return sha


def is_blocked_checkout(line: str) -> bool:
    """ft-ledger-repo-sync.sh 의 실패 줄이 «사본 checkout 이 untracked 에 막힘» 인가."""
    return "checkout 실패" in line and ("untracked" in line or "overwritten" in line)


def notify_checkout_blocked(root: Path, repo: str, line: str) -> bool:
    """planner [긴급] 1통 — 같은 (사본 + 사유) 지문은 10분 안 1번. 실패는 로그만(원래 ERROR 줄은 이미 났다). True = 보냈다."""
    state = root / ".fable-team" / "state"
    stamp, key = state / "ledger-checkout-notify.json", hashlib.sha1(f"{repo}\n{line}".encode()).hexdigest()[:16]
    try:
        seen = json.loads(stamp.read_text(encoding="utf-8")) if stamp.exists() else {}
        if time.time() - seen.get(key, 0) < DEDUP_S:
            return False
        master = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"]
        mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
        body = f"[긴급] 뉴스 원장 사본 checkout 막힘\n사본: {repo}\n{line[:280]}\n조치: untracked 파일을 사람·master 가 옮긴다(자동 정리 0)"
        done = subprocess.run(["bash", mbox, "send", master, "ft-news-ledger", body], capture_output=True, check=False, timeout=15)
        if done.returncode == 0:
            state.mkdir(parents=True, exist_ok=True)
            stamp.write_text(json.dumps({**seen, key: time.time()}), encoding="utf-8")
        return done.returncode == 0
    except (OSError, KeyError, ValueError, subprocess.TimeoutExpired) as e:
        LOG.warning("원장 사본 checkout 막힘 통지 실패: %s", e)
        return False
