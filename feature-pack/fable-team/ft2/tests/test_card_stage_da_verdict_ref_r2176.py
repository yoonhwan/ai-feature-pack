"""r2176 card_stage --da 판정문 읽는 곳 시험 (카드 반례 ①~⑧-c · 변이 M1~M6 · ⑨ = 기존 시험 재실행).
r2037 world 꼴 그대로 — 임시 bare 원격(byz.git · main·ops/main-base) + 임시 루트 클론(작업 트리 · 낡은 체크아웃 대역) · 실 리포·실 push·외부 호출 0 · sleep 0.
판정문 = 루트 리포 안 상대 경로 V(실행 폴더 = 루트) · git 호출 = card_stage.spawn 을 세는 감싸개.
기준판 = 팩 main ba0548d68b → ① ② ⑤ ⑧ ⑧-b ⑧-c Red · ⑦ 도 Red(기준판엔 git 판정문 읽기가 없어 파일 사유로 REJECT) · ③ ④ ⑥ 은 기준판과 같은 결과 · 같은 git 호출 수.
"""
import importlib.util
import subprocess
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("cs2037_world_r2176", str(Path(__file__).with_name("test_card_stage_da_close_legacy_r2037.py")))
base = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(base)
kw, TEAM, MAIN, OPS, CARD, SHA = base.kw, base.TEAM, base.MAIN, base.OPS, base.CARD, base.SHA
V = "design/harness/evidence/r9-da/verdict.md"
GIT_REJECT, GIT_PASS = 9, 19   # 기준판(ba0548d68b)에서 잰 git 호출 수 — 거절 = fetch·rev-parse 2·show 2·ls-tree 4 · 통과 = 그 뒤 show 2·임시 index 5·commit-tree·diff-tree·push(판정문 git 0)


def body(closed=True, name="r9-x"):
    head = "# DA 판정\n\n## §1 다른 일\n- 보류\n"
    return head + ("\n## §2 %s — 닫힘 (CLOSE)\n- 닫힘 — %s — main `%s`\n" % (name, name, SHA) if closed else "")


def world(tmp, mp, local=None, ops=None, main=None, ledger=None):
    """local = 작업 트리 판정문(None = 파일 없음) · ops/main = 그 가지에 올린 판정문(None = 경로 없음)."""
    w = base.world(tmp, mp, ledger=ledger)
    for ref, text in ((OPS, ops), (MAIN, main)):
        if text is not None:
            w.commit("byz", {V: text}, ref)
    if local is not None:
        kw._put(w.root / V, local)
    mp.chdir(w.root)
    return w


def run(w, capsys, mp, spec="%s#§2" % V, fail=None):
    """(rc, 출력, git 호출 인자 목록) · fail(args) = 주입 결과(None = 진짜 git)."""
    mod, calls = kw._mod(w.ft2 / "adapters" / "pi" / "card_stage.py", "cs2176_%d" % id(w)), []
    real = mod.spawn

    def counted(cwd, args, env=None):
        calls.append(list(args))
        hit = fail and fail(list(args))
        return hit if hit else real(cwd, args, env)
    mp.setattr(mod, "spawn", counted)
    rc = mod.main(["--root", str(w.root), "--team", TEAM, "--work", "r9", "--da", spec])
    return rc, capsys.readouterr().out.strip(), calls


def verdict_calls(calls):
    return [c for c in calls if c[0] in ("ls-tree", "show") and any("verdict.md" in x for x in c)]


def staged(w, out, rc, ref, pin, frm="진행"):
    lines = out.splitlines()
    assert rc == 0 and lines[0].startswith("STAGED r9-x %s→완성 " % frm), out
    assert lines[1] == "판정문 출처 %s %s" % (ref, pin[:10]), out
    card = base.bare(w, "show", OPS + ":" + CARD % "완성")
    assert "\n- 상태: 완성 · %s · DA %s#§2\n" % (kw.NOW, V) in card and "판정문 출처" not in card, card
    assert base.bare(w, "log", "-1", "--format=%s", OPS) == "[docs] r9-x 2.0 완성 폴더(DA %s#§2)" % V
    return lines


def test_1_stale_worktree_reads_pinned_ops(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), ops=body())
    pin = base.heads(w)[OPS]
    rc, out, _ = run(w, capsys, monkeypatch)
    assert len(staged(w, out, rc, "origin/" + OPS, pin)) == 2, out


def test_2_missing_file_falls_through_to_main(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, main=body())
    pin = base.heads(w)[MAIN]
    rc, out, _ = run(w, capsys, monkeypatch)
    staged(w, out, rc, "origin/" + MAIN, pin)


def test_3_worktree_pass_is_unchanged(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(), ops=body(False))
    rc, out, calls = run(w, capsys, monkeypatch)
    assert rc == 0 and len(out.splitlines()) == 1 and out.startswith("STAGED r9-x 진행→완성 "), out
    assert verdict_calls(calls) == [] and len(calls) == GIT_PASS, calls
    card = base.bare(w, "show", OPS + ":" + CARD % "완성")
    assert "\n- 상태: 완성 · %s · DA %s#§2\n" % (kw.NOW, V) in card


def test_4_no_branch_passes_rejects_like_base(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), ops=body(False), main=body(False))
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert (rc, out) == (1, "REJECT 판정문에 §2 절 없음")
    assert base.heads(w) == before


def test_5_missing_file_first_branch_reason(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ops=body(name="r9-xy"))
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert rc == 1 and out.startswith("REJECT ") and len(out.splitlines()) == 1 and "절 없음" not in out, out
    assert base.heads(w) == before


def test_6_outside_repo_path_no_git(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ops=body())
    before = base.heads(w)
    rc, out, calls = run(w, capsys, monkeypatch, base.spec(w, "§3"))
    assert (rc, out) == (1, "REJECT 판정문에 §3 절 없음")
    assert verdict_calls(calls) == [] and len(calls) == GIT_REJECT, calls
    assert base.heads(w) == before


def _ls_tree_fails(args):
    return (128, "") if args[0] == "ls-tree" and V in args else None


def test_7a_ls_tree_failure_is_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), ops=body())
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch, fail=_ls_tree_fails)
    assert rc == 3 and out.startswith("판정 불가 ") and "ls-tree" in out, out
    assert base.heads(w) == before


def test_7b_show_timeout_is_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), ops=body())
    before, real = base.heads(w), subprocess.run

    def slow(cmd, *a, **k):   # spawn 안의 subprocess.run 이 7초 초과를 낸 것과 같은 예외(실제 대기 0)
        if cmd[:1] == ["git"] and "show" in cmd and any(x.endswith(":" + V) for x in cmd):
            raise subprocess.TimeoutExpired(cmd, 7)
        return real(cmd, *a, **k)
    monkeypatch.setattr(subprocess, "run", slow)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert (rc, out) == (3, "판정 불가 git show 시간초과 7초"), out
    assert base.heads(w) == before


def test_7c_branch_not_utf8_is_unsure(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False))
    seed = w.tmp / "seed-byz"
    kw._git(seed, "checkout", "-q", OPS)
    (seed / V).parent.mkdir(parents=True, exist_ok=True)
    (seed / V).write_bytes(b"## \xa7\xff2 r9-x\n")
    kw._git(seed, "add", "-A"), kw._git(seed, "commit", "-q", "-m", "x"), kw._git(seed, "push", "-q", "origin", OPS)
    before = base.heads(w)
    rc, out, _ = run(w, capsys, monkeypatch)
    assert rc == 3 and out.startswith("판정 불가 ") and "UnicodeDecodeError" in out, out
    assert base.heads(w) == before


def test_8_first_pass_wins_not_first_path(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, ops=body(False), main=body())
    pin = base.heads(w)[MAIN]
    rc, out, _ = run(w, capsys, monkeypatch)
    staged(w, out, rc, "origin/" + MAIN, pin)


def test_8b_reads_pinned_sha_not_head(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), main=body())
    kw._git(w.root, "add", V), kw._git(w.root, "commit", "-q", "-m", "낡은 판정문")   # 로컬 main(HEAD) = §2 없음 · origin/main = §2 닫힘
    pin = base.heads(w)[MAIN]
    assert kw._git(w.root, "rev-parse", "HEAD") != pin
    rc, out, _ = run(w, capsys, monkeypatch)
    staged(w, out, rc, "origin/" + MAIN, pin)


def test_8c_done_ledger_compare_uses_same_reader(tmp_path, monkeypatch, capsys):
    w = world(tmp_path, monkeypatch, local=body(False), ops=body(), ledger=True)
    pin = base.heads(w)[OPS]
    rc, out, _ = run(w, capsys, monkeypatch)
    lines = out.splitlines()
    assert rc == 0 and len(lines) == 3 and lines[0].startswith("STAGED r9-x 진행→완성 "), out
    assert lines[1:] == ["DA 대조 일치 %s#§2" % V, "판정문 출처 origin/%s %s" % (OPS, pin[:10])], out
