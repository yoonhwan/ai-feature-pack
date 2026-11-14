"""r1972 keeper — 원장 done · 커밋 0 · 변경 0 · PR 닫힘(merge 0)/없음 나노는 B2 가 닫는다(CLOSED-ENDING empty · complete 0) · 반례 ①~⑩ · 변이 M1~M5.
대역 = r1812 World(임시 BYZ·팩 리포·가짜 tmux·쪽지·실제 core) + 가짜 gh(FT2_GH · --state merged/all 따로) + 임시 git worktree · 실 세션 0 · sleep 0."""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
_S = importlib.util.spec_from_file_location("r1972_kw", str(FT2 / "tests" / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
TEAM, _git, _put = kw.TEAM, kw._git, kw._put
ID = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"]
GH = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FAKE_GH.log"\ncase "$*" in *"--state merged"*) s=merged;; *) s=all;; esac\ncat "$FAKE_GH.$s" 2>/dev/null || echo "[]"\nexit "$(cat "$FAKE_GH.rc" 2>/dev/null || echo 0)"\n'
CLOSED = json.dumps([{"number": 8476, "state": "CLOSED", "mergedAt": None}])
def world(tmp, mp, ft2=FT2):
    tmp.mkdir(parents=True, exist_ok=True)
    w = kw.World(tmp, mp, ft2)
    _put(tmp / "bin" / "gh", GH), (tmp / "bin" / "gh").chmod(0o755)
    w.env.update(FT2_GH=str(tmp / "bin" / "gh"), FAKE_GH=str(tmp / "gh"))
    return w
def nano(w, work, done=True, prs=CLOSED, rc=0, commit=False, dirty=False, **kv):
    """cfo-2659 꼴 1석 — 카드(착지 줄 0) · submit→assign→deliver(→complete) · 팩 worktree 가지 nano/<work>(base 그대로) · intent base_sha · gh all 출력."""
    w.enable(), w.card(work), w.work(work, done=done, intent=False, alive=True, **kv)
    base, path = w.pack_sha(), w.tmp / "wt" / work
    _git(w.tmp / "pack", "fetch", "-q", "origin"), _git(w.tmp / "pack", "worktree", "add", "-q", "-b", "nano/" + work, str(path), base)
    commit and _git(path, *ID, "commit", "-q", "--allow-empty", "-m", "n-" + work)
    dirty and _put(path / "new.txt", "x")
    _put(str(w.tmp / "gh") + ".all", prs), _put(str(w.tmp / "gh") + ".rc", str(rc))
    _put(w.runtime() / "launch" / ("%s@a1.intent" % work), {"FT2_HOLDER": "byz-harness-nano-%s-t#0" % work, "state": "opened", "worktree": str(path), "at": "2026-01-01T00:00:00", "base_sha": base})
def run(w, k=None):
    return w.round(k), w.tmux("kill-session")
def has(lines, head, word=""):
    return any(x.startswith(head) and word in x for x in lines)
def shut(w, work):   # 닫기 0 · complete 추가 0
    lines, kills = run(w)
    assert kills == [] and not has(lines, "CLOSED") and w.kinds("complete") <= 1, lines
    return lines
def c1(w):   # ① cfo-2659 꼴 → CLOSED-ENDING empty · kill 1 · complete 추가 0(done 1 그대로) · gh all 질의 = 그 가지
    nano(w, "r9701")
    lines, kills = run(w)
    assert has(lines, "CLOSED-ENDING harness r9701 byz-harness-nano-r9701-t#0", "empty") and has(lines, "CLOSED-ENDING", "PR 닫힘 #8476") and len(kills) == 1 and w.kinds("complete") == 1, lines
    assert any("--head nano/r9701 --state all" in x for x in kw._lines(str(w.tmp / "gh") + ".log"))
def c2(w):   # ② PR 0개 → 닫음
    nano(w, "r9702", prs="[]")
    lines, kills = run(w)
    assert has(lines, "CLOSED-ENDING harness r9702", "PR 없음") and len(kills) == 1, lines
def c3(w):   # ③ 자기 커밋 1 → 닫기 0
    nano(w, "r9703", commit=True), shut(w, "r9703")
def c4(w):   # ④ untracked 1 → 닫기 0
    nano(w, "r9704", dirty=True), shut(w, "r9704")
def c5(w):   # ⑤ PR OPEN → 닫기 0
    nano(w, "r9705", prs=json.dumps([{"number": 1, "state": "CLOSED", "mergedAt": None}, {"number": 2, "state": "OPEN", "mergedAt": None}])), shut(w, "r9705")
def c6(w):   # ⑥ PR merged(merged 목록 근거 못 채움) → empty 아님
    nano(w, "r9706", prs=json.dumps([{"number": 3, "state": "MERGED", "mergedAt": "2026-11-14T00:00:00Z"}])), shut(w, "r9706")
def c7(w):   # ⑦ gh 실패 → None(HELD 그대로)
    nano(w, "r9707", prs="[]", rc=1)
    assert has(shut(w, "r9707"), "HELD harness r9707", "착지 줄 없음")
def c8(w):   # ⑧ Working → HELD · kill 0
    nano(w, "r9708", pane="⠋ Working...\n")
    assert has(shut(w, "r9708"), "HELD harness r9708", "Working")
def c9(w):   # ⑨ 원장 holder ≠ 세션 이름 → None · 같은 이름 = empty (ending 직접 · orphans 길은 seat 0)
    nano(w, "r9709"), _git(w.root, "fetch", "-q", "origin")
    K = w.K
    k = K.Keeper(str(w.root), env=w.env, now=lambda: w.t)
    assert K.endings.ending(k, TEAM, "r9709", "byz-harness-nano-other#0") is None
    assert K.endings.ending(k, TEAM, "r9709") is None and K.endings.ending(k, TEAM, "r9709", "byz-harness-nano-r9709-t#0")[0] == "empty"
def c10(w):  # ⑩ done 아님 → 닫기 0
    nano(w, "r9710", done=False), shut(w, "r9710")
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10}
KE = "adapters/pi/keeper_endings.py"
MUTANTS = {"M1": (' or k.git(tree, "rev-list", "--count", base + "..HEAD")[:2] != (0, "0\\n"):', ":", c3),
           "M2": ('if k.git(tree, "status", "--porcelain", "--untracked-files=all")[:2] != (0, ""):', "if False:", c4),
           "M3": ('p.get("state") == "CLOSED"', 'p.get("state") in ("CLOSED", "OPEN")', c5),
           "M4": (" or holder != seat:", ":", c9),
           "M5": ("prs = json.loads(out) if rc == 0 else None", "prs = json.loads(out) if rc == 0 else []", c7)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path / "w", monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    shutil.copytree(FT2, copy := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / KE).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / KE).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(world(tmp_path / "w1", monkeypatch, copy))
    case(world(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
