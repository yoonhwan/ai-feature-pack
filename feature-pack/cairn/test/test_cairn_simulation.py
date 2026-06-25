"""§10.5 완성 게이트 — 랜덤 시나리오 시뮬레이션."""
import datetime
import subprocess
from pathlib import Path
import cairn

GOLDEN = Path(__file__).resolve().parent.parent / "core" / "golden.yaml"


def _init_repo(tmp_path):
    (tmp_path / ".cairn" / "views").mkdir(parents=True)
    cairn.save_atomic(cairn.load_plan(GOLDEN), tmp_path / ".cairn" / "plan.yaml")
    for c in (["init", "-q"], ["config", "user.email", "t@t"],
              ["config", "user.name", "t"], ["add", "-A"], ["commit", "-q", "-m", "seed"]):
        subprocess.run(["git", *c], cwd=tmp_path, check=True)
    return tmp_path


def _mp(monkeypatch, repo):
    for attr, val in [("REPO", repo), ("PLAN_PATH", repo / ".cairn" / "plan.yaml"),
                      ("VIEW_PATH", repo / ".cairn" / "views" / "plan.md"),
                      ("LOCK_PATH", repo / ".cairn" / ".lock")]:
        monkeypatch.setattr(cairn, attr, val)


def test_random_scenario_keeps_ledger_valid(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    # 결정론적 — Date.now/random 불가 환경이므로 인덱스 기반 의사난수
    spawned = []
    for i in range(40):
        d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
        all_tids = [t["id"] for p in d["projects"] for m in p.get("milestones", [])
                    for t in m.get("tasks", [])]
        op = ["spawn", "complete", "link", "return"][i % 4]
        parent = all_tids[i % len(all_tids)]
        if op == "spawn":
            before = set(all_tids)
            if cairn.main(["spawn", f"sim{i}", "--from", parent]) == 0:
                d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
                after = {t["id"] for p in d2["projects"] for m in p.get("milestones", [])
                         for t in m.get("tasks", [])}
                new_ids = after - before   # [DA#6] parent의 실제 milestone에 생긴 새 노드
                spawned.extend(new_ids)
        elif op == "complete" and spawned:
            cairn.main(["complete", spawned[i % len(spawned)], "--force"])
        elif op == "link":
            cairn.main(["link", parent, "--execution-ref", f"wt{i}"])
        elif op == "return":
            cairn.main(["return", "--to", parent])
        # 불변식: 매 연산 후 원장은 항상 valid
        assert cairn.validate(cairn.load_plan(repo / ".cairn" / "plan.yaml")) == [], f"step {i} ({op})"
    # 복구 엣지: 모든 task의 return_to/merge_back_to/spawned_from이 유효 노드
    final = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    node_ids = cairn._all_node_ids(final)
    for p in final["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                for ref in ("return_to", "merge_back_to", "spawned_from"):
                    if t.get(ref):
                        assert t[ref] in node_ids, f"{t['id']}.{ref}={t[ref]} 끊김"
