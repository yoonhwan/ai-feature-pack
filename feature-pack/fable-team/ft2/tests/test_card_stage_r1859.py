"""r1859 card_stage 시험 (카드 반례 ①~⑦ · 변이 M1~M5 · DA 설계 교정 APPROVE).
r1812 대역(keeper_world_r1812) 재사용 · 임시 bare 원격(byz.git) + 임시 루트(그 clone) 만 쓴다(실 장부·실 ops/main-base 0).
시간초과·원격 앞섬 = 모듈 git 대역 주입(sleep 0). 기준판 = card_stage.py 없음 → 전부 Red.
"""
import importlib.util
import json
import subprocess
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1859", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
TEAM, NOW = kw.TEAM, kw.NOW
CARD = "design/harness/indices/%s/r9-x.md"


def world(tmp, mp):
    w = kw.World(tmp, mp)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        kw._git(w.root, "config", k, v)
    return w


def tool(w):
    return kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs_%d" % id(w))


def call(w, capsys, mod=None, work="r9"):
    rc = (mod or tool(w)).main(["--root", str(w.root), "--team", TEAM, "--work", work])
    return rc, capsys.readouterr().out.strip()


def remote(w, ref="ops/main-base"):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), "ls-tree", "-r", "--name-only", ref).splitlines()


def show(w, path, ref="ops/main-base"):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), "show", "%s:%s" % (ref, path))


def head(w):
    return kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), "rev-parse", "ops/main-base")


def done_world(tmp, mp, done=True):
    w = world(tmp, mp)
    w.card("r9", refs=("ops/main-base",))
    w.work("r9", done=done, intent=False, turn=None)
    return w


def test_1_done_moves_card_to_complete(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch)
    rc, out = call(w, capsys)
    assert rc == 0 and out.startswith("STAGED r9-x 진행→완성 "), out
    names = remote(w)
    assert CARD % "완성" in names and CARD % "진행" not in names
    body = show(w, CARD % "완성")
    assert "\n- 상태: 완성 · %s · ft2 complete " % NOW in body and "- 상태: 대기" not in body
    assert body.rstrip().splitlines()[-1].startswith("- %s · ft2 card_stage 진행→완성" % NOW)
    assert out.split()[-1] == head(w)
    assert "[docs] r9-x 2.0 완성 폴더(ft2 done)" in kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), "log", "-1", "--format=%s", "ops/main-base")
    assert len(kw._git(w.root, "worktree", "list").splitlines()) == 1


def test_2_rerun_is_noop(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch)
    assert call(w, capsys)[0] == 0
    sha = head(w)
    rc, out = call(w, capsys)
    assert (rc, out.split()[0]) == (0, "NOOP") and head(w) == sha, out


def test_3_not_done_rejects_without_write(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch, done=False)
    sha = head(w)
    rc, out = call(w, capsys)
    assert (rc, out) == (1, "REJECT done 없음 r9") and head(w) == sha
    assert CARD % "진행" in remote(w)


def test_4_two_prefix_cards_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch)
    w.commit("byz", {"design/harness/indices/진행/r9-a.md": "- 상태: 대기\n",
                     "design/harness/indices/진행/r9-b.md": "- 상태: 대기\n"}, "ops/main-base")
    w.work("r9", done=True, intent=False, turn=None)
    sha = head(w)
    rc, out = call(w, capsys)
    assert rc == 3 and out.startswith("판정 불가 ") and head(w) == sha, out


def test_5_remote_ahead_rebases_once(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch)
    mod, seen = tool(w), []
    real = mod.git

    def git(cwd, *args):
        if args[:1] == ("push",) and not seen:
            seen.append(w.commit("byz", {"other.txt": "앞선 커밋"}, "ops/main-base"))
        return real(cwd, *args)
    monkeypatch.setattr(mod, "git", git)
    rc, out = call(w, capsys, mod)
    assert rc == 0 and out.startswith("STAGED "), out
    assert "other.txt" in remote(w) and CARD % "완성" in remote(w)
    assert kw._git(w.tmp, "--git-dir", str(w.tmp / "byz.git"), "merge-base", "--is-ancestor", seen[0], "ops/main-base") == ""


def test_6_journal_done_without_checkpoint_stages(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch)
    state = w.runtime() / "state.json"
    raw = json.loads(state.read_text(encoding="utf-8"))
    raw.get("done", {}).pop("r9", None)      # complete 줄은 journal 에 있고 checkpoint 는 그 전(끊김 대역)
    state.write_text(json.dumps(raw), encoding="utf-8")
    assert w.kinds("complete") == 1
    rc, out = call(w, capsys)
    assert rc == 0 and out.startswith("STAGED "), out
    assert "ft2 complete 20" in show(w, CARD % "완성")


def test_7_push_timeout_is_unknown(tmp_path, monkeypatch, capsys):
    w = done_world(tmp_path, monkeypatch)
    mod = tool(w)
    real = mod.git

    def git(cwd, *args):
        if args[:1] == ("push",):
            raise subprocess.TimeoutExpired(["git", "push"], 7)
        return real(cwd, *args)
    monkeypatch.setattr(mod, "git", git)
    rc, out = call(w, capsys, mod)
    assert (rc, out) == (3, "판정 불가 push 결과 불명"), out
    assert "원격 쓰기 0" not in out
    assert len(kw._git(w.root, "worktree", "list").splitlines()) == 1
