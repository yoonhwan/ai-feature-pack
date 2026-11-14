"""r1967 keeper 동시 열기 · checkout hook 끔 · 반쪽 워크트리 치우기 (반례 ①~④ ③b~③e · 변이 M1~M5).
① = keeper_next.reconcile 대역 k(launching 기록만) · ②~④ = 임시 git 리포 + 진짜 launch.py · 가짜 git(진짜 git 에 넘김 · checkout 만
FAKE_CO 를 그 자리에서 돌리고 rc1 = «상한 초과로 죽은 checkout» 꼴) · 가짜 tmux(has-session rc = FAKE_ALIVE · 기본 1 = 없음) · sleep 0.
"""
import importlib.util, json, shutil, subprocess, sys, types  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
pl = _mod("r1967_pl", HERE / "test_pi_launch.py")
GIT = '#!/bin/sh\ncase " $* " in\n  *" checkout -q "*) if [ -n "$FAKE_CO" ]; then cd "$2" && eval "$FAKE_CO"; exit 1; fi;;\n' \
      '  *" worktree remove "*) [ -n "$FAKE_RM_RC" ] && exit "$FAKE_RM_RC";;\nesac\nexec "$REAL_GIT" "$@"\n'
TMUX = '#!/bin/sh\necho "$1" >> "$TLOG"\n[ "$1" = has-session ] && exit "${FAKE_ALIVE:-1}"\nexit 0\n'
MINE = '"$REAL_GIT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m mine'
def c1(tmp, ft2):   # ① 같은 바퀴 같은 리포 열기 3개 → launching 1회 · 나머지 LAUNCH-WAIT(다음 바퀴 · 여는 중 1칸) · 다른 리포 1개는 열림
    nx, seen = _mod("r1967_nx_%d" % id(tmp), ft2 / "adapters" / "pi" / "keeper_next.py"), []
    nx.kl.launching = lambda k, team, stem, attempt, nh, argv: seen.append(stem) or True
    nx.ft2_state = lambda k, team: {"deliveries": {}}
    k = types.SimpleNamespace(root=str(tmp), env={}, cache={}, lines=[], state={"handled": {}}, probe=lambda nh: "absent", read_json=lambda p: {})
    k.log = lambda kind, team, text: k.lines.append("%s %s %s" % (kind, team, text))
    for stem, repo in (("A", "/pack"), ("B", "/pack"), ("C", "/pack"), ("D", "/byz")):
        nx.reconcile(k, "harness", "w-" + stem, "a1", stem, "nano-" + stem, (stem, repo, "origin/main"))
    assert seen == ["A", "D"] and sum("같은 리포 열기 1개" in x for x in k.lines) == 2, (seen, k.lines)
    assert k.cache.get("launching") == {"nano-B", "nano-C", "repo:/pack", "repo:/byz"} and not k.state["handled"], k.cache
def world(tmp, hook=False):
    root, fake = pl._paths(tmp)
    for name, body in (("git", GIT), ("tmux", TMUX)):
        (fake / name).write_text(body, encoding="utf-8")
    run = lambda *a: subprocess.run(["git", "-C", str(root)] + list(a), capture_output=True, text=True, timeout=25, check=True).stdout  # noqa: E731
    run("init", "-q")
    for rel, text in (("a/f", "1\n"), ("g", "2\n"), (".gitignore", "*.local\n.fable-team/\n")):
        (root / rel).parent.mkdir(parents=True, exist_ok=True), (root / rel).write_text(text, encoding="utf-8")
    run("add", "-A"), run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i"), run("update-ref", "refs/remotes/origin/main", "HEAD")
    if hook:   # ④ post-checkout 가짜 hook = 첫 인자(이전 HEAD)를 표식 파일에 1줄
        (root / ".git" / "hooks" / "post-checkout").write_text('#!/bin/sh\necho "$1" >> "$MARK"\n', encoding="utf-8")
        (root / ".git" / "hooks" / "post-checkout").chmod(0o755)
    pl._runtime(root)
    return root, fake
def launch(tmp, ft2, hook=False, **env):
    root, fake = world(tmp, hook)
    extra = dict(REAL_GIT=shutil.which("git"), TLOG=str(tmp / "tmux.log"), MARK=str(tmp / "mark"), **env)
    out, rc = pl._launch(root, fake, ft2 / "adapters" / "pi" / "launch.py", env_extra=extra)
    tlog = (tmp / "tmux.log").read_text().split() if (tmp / "tmux.log").exists() else []
    return out, rc, json.loads(pl._intent(root).read_text(encoding="utf-8")), pl._worktree(root), tlog
def c2(tmp, ft2):   # ② checkout 죽음(가짜) → 반쪽 치움 · tmux new-session 0 · 칸 반환 기록 · intent failed · status 보존본
    out, rc, it, wt, tlog = launch(tmp, ft2, FAKE_CO=":")
    assert (rc, it["state"], it["step"], it.get("cleanup"), it.get("slot_returned")) == (2, "failed", "git checkout", "치움", True), (out, it)
    assert not wt.exists() and "new-session" not in tlog and "D  g" in Path(it["cleanup_note"]).read_text(), (tlog, it)
    assert it["add_ok"] and it["path_new"] and "복구 ⓐ" not in out["reason"], out
def kept(tmp, ft2, **env):
    out, rc, it, wt, _ = launch(tmp, ft2, **env)
    assert (rc, it["state"]) == (2, "failed") and it["cleanup"].startswith("보존") and "slot_returned" not in it, it
    assert wt.is_dir() and "복구 ⓐ" in out["reason"], out
    return it, wt
def c3(tmp, ft2):   # ③ 자기 커밋 1 → 치우기 0 · 사람 복구 1줄
    assert "자기 커밋" in kept(tmp, ft2, FAKE_CO=MINE)[0]["cleanup"]
def c3b(tmp, ft2):  # ③b 사람 메모(untracked) → 치우기 0 · 메모 그대로
    it, wt = kept(tmp, ft2, FAKE_CO="echo memo > memo.txt")
    assert (wt / "memo.txt").read_text() == "memo\n" and "중간 꼴 밖" in it["cleanup"], it
def c3c(tmp, ft2):  # ③c tracked 수정 1개 → 치우기 0
    it, wt = kept(tmp, ft2, FAKE_CO='"$REAL_GIT" checkout -q HEAD -- g && echo x >> g')
    assert (wt / "g").read_text() == "2\nx\n", it
def c3e(tmp, ft2):  # ③e ignored 로컬 설정(!!) → 치우기 0(팩 .gitignore 꼴 보존)
    assert (kept(tmp, ft2, FAKE_CO='"$REAL_GIT" checkout -q HEAD -- .gitignore && echo s > s.local')[1] / "s.local").exists()
def c3d(tmp, ft2):  # ③d remove 실패(가짜) → 칸 반환 성공 기록 0 · intent «정리 실패 · 복구 필요»
    out, rc, it, wt, _ = launch(tmp, ft2, FAKE_CO=":", FAKE_RM_RC="1")
    assert rc == 2 and it["cleanup"].startswith("정리 실패 · 복구 필요") and "slot_returned" not in it and wt.is_dir(), it
def c4(tmp, ft2):   # ④ hook 끔 → checkout 단계 표식 0 · 열기 뒤 reconcile 1회(인자 0×40)
    out, rc, it, wt, _ = launch(tmp, ft2, hook=True, FAKE_ALIVE="0")
    assert (rc, it["state"], out["reconcile"]) == (0, "opened", "rc 0") and (wt / "g").exists(), out
    assert (tmp / "mark").read_text().split() == ["0" * 40], (tmp / "mark").read_text()
CASES = {"①": c1, "②": c2, "③": c3, "③b": c3b, "③c": c3c, "③d": c3d, "③e": c3e, "④": c4}
KN, LC, LA = "adapters/pi/keeper_next.py", "adapters/pi/launch_cleanup.py", "adapters/pi/launch.py"
MUTANTS = {"M1": (KN, 'if place and "repo:" + place[0] in k.cache.setdefault("launching", set())', 'if False', "①"),
           "M2": (LC, 'if rc != 0 or head.strip() != sha:', 'if rc != 0:', "③"),
           "M3": (LA, 'NOHOOK if step == "git checkout" else None', 'None', "④"),
           "M4": (LC, 'if any(not line.startswith("D  ") for line in status.splitlines()):', 'if False:', "③b"),
           "M5": (LC, 'if rc != 0 or os.path.lexists(path):', 'if False:', "③d")}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path, FT2)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    shutil.copytree(FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    [(tmp_path / sub).mkdir() for sub in ("w1", "w2")]
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", tree)
    CASES[case](tmp_path / "w2", FT2)   # 원본으로 같은 사례 1회 더 = PASS
if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
