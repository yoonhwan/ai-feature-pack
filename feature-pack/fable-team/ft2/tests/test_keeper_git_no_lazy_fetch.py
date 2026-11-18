"""카드 ft2-keeper-git-no-lazy-fetch — keeper 착지 고리(착지 sha 가 어느 ref 에 닿았는지 묻는 자리)의 조상 확인·착지 sha 존재 확인이 원격 lazy fetch 없이 로컬 객체만 보고 끝난다.

사례표(카드 §반례 표) — 대역 = bare 원격(uploadpack.allowFilter) + blob:none 클론(느린 upload-pack = 호출 1줄 기록 + 0.4초) + 전체 클론(팩 대역)
(= legacy/1.x/harness/tests/test_landed_git_no_lazy_r1401.sh 꼴을 파이썬으로 옮김) · 실 원격 0 · 실 라이브 쓰기 0 · sleep 은 upload-pack 대역에만.
| # | 입력 | 기대 |
| ㊸가 | 루트 = partial clone · 착지 sha = 그 리포에 없는 sha(팩 대역 객체 · 팩 origin/main 에는 없음) | upload-pack 0줄 · (sha, None, "미도달") · 2초 안 (기준판 FAIL) |
| ㊸나 | intent base_sha = 그 리포에 없는 sha · 착지 sha 는 그 리포 ref 의 조상 | r2247 cat-file = git_local rc 1 → 시각 비교 길 · upload-pack 0줄 · env=1 1줄 |
| ㊸다 | 착지 sha = 팩 origin/main 의 조상(있는 객체) | (sha, "pack:origin/main", "") · upload-pack 0줄 |
| ㊸라 | 착지 sha 가 세 ref 어디에도 조상 아님(로컬 객체) | «미도달» 그대로 · upload-pack 0줄 |
| ㊸마 | PR 착지 — worktree 리포에 gh mergeCommit sha 없음 | PR 착지 손 0(git_local 0회) · upload-pack 수·판정이 env 없앤 판과 같다 |
| ㊸바 | self.env 에 GIT_NO_LAZY_FETCH=0 이 이미 있음 | 호출 자식 env = 1 · 호출 뒤 self.env["GIT_NO_LAZY_FETCH"] == "0" · self.env 는 같은 객체 |
| ㊸사 | git_local 안에서 self.git 이 예외 | 예외 그대로 · self.env 에 GIT_NO_LAZY_FETCH 없음(되돌림) |
| ㊸아 | 한 바퀴: 카드 본문 show(blob 없음) → 착지 판정 → Popen 대역 | show 는 본문을 읽어 온다(upload-pack 1줄 이상) · Popen 대역 env 에 GIT_NO_LAZY_FETCH 없음 · git_local 밖 git 자식 env 에도 없음 |
| ㊸자 | 루트가 낡은 리포(self.stale) | 그 리포로 git 호출 0 · «판정 불가 · 팩 fetch 실패» 그대로 |
| ㊸차 | pre_attempt · base 가 그 리포에 없음 · L 시각 < at | "" (진행) · upload-pack 0줄 · env=1 1줄(r2247) |
| ㊹가 | pre_attempt · base 로컬(fetch 로 받음) · L 이 base 의 조상 | «옛 착지 줄(attempt 전) <sha8>» · env=1 = cat-file 1줄(r2247) |
| ㊹다 | pre_attempt · base 가 어디에도 없는 sha | 시각 비교 길 · env=1 = cat-file 1줄(r2247) |
| 㓈가 | pre_attempt · base 로컬(fetch 로 받음) · L·base 시각 = at | «옛 착지 줄(attempt 전) <sha8>» · env=1 = cat-file 1줄(r2247) |
| 㓈나 | pre_attempt · base 로컬(fetch 로 받음) · L 이 base 의 조상 아님 | "" (진행) · env=1 = cat-file 1줄(r2247) |
| 㓈다 | 착지 고리 · 착지 sha 원격 다른 가지에만 · ref 하나가 그 리포에 없음(안 풀림) | «판정 불가 · 착지 조상 git rc 128» · ⓒ 로 가서 upload-pack 1줄 |
| 㓈라 | 착지 고리 · 착지 sha 로컬 · ref 그 리포에 없음 | «판정 불가 · 착지 조상 git rc 128» · upload-pack 0줄 |
| 㓈마 | 착지 고리 · 착지 sha 원격 다른 가지에만 · ref 는 풀림 · 조상 아님 | 다음 ref · upload-pack 0줄 (기준판 FAIL) |
"""
import importlib.util
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
LAND_PY = "adapters/pi/keeper_land.py"
TEAM, WORK = "harness", "r9300"
GIT = shutil.which("git") or "/usr/bin/git"


def _land(ft2=FT2):
    spec = importlib.util.spec_from_file_location("knl_%d" % id(ft2), str(Path(ft2) / LAND_PY))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run(argv, env, check=True):
    p = subprocess.run([str(a) for a in argv], capture_output=True, text=True, env=env, timeout=60)
    assert not check or p.returncode == 0, (argv, p.returncode, p.stderr[:400])
    return p.stdout.strip()


class World:
    """bare 원격 + blob:none 클론(느린 upload-pack 기록) + 전체 클론(팩 대역) · git 자식 env 기록(shim = PATH 첫 칸)."""

    def __init__(s, tmp):
        tmp.mkdir(parents=True, exist_ok=True)
        s.tmp, s.home = tmp, tmp / "home"
        s.home.mkdir()
        s.env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0", HOME=str(s.home))
        s.env.pop("GIT_NO_LAZY_FETCH", None)
        s.up, s.glog = tmp / "upload-pack.log", tmp / "git.log"
        s.up.write_text(""), s.glog.write_text("")
        s.shim = tmp / "shim"
        s.shim.mkdir()
        (s.shim / "git").write_text('#!/bin/sh\nprintf "env=%s ::%s\\n" "${GIT_NO_LAZY_FETCH:-unset}" "$*" >> ' + str(s.glog)
                                    + '\nexec ' + GIT + ' "$@"\n', encoding="utf-8")
        (s.shim / "git").chmod(0o755)
        up = tmp / "upload-pack.sh"   # 느린 upload-pack — 호출 1줄 기록 + 0.4초(r1401 대역과 같은 꼴 · 시험 상한 안)
        up.write_text('#!/bin/sh\necho x >> %s\nsleep 0.4\nexec %s/git-upload-pack "$@"\n' % (s.up, _run([GIT, "--exec-path"], s.env)),
                      encoding="utf-8")
        up.chmod(0o755)
        s.origin = tmp / "origin.git"
        _run([GIT, "init", "-q", "--bare", "-b", "main", s.origin], s.env)
        _run([GIT, "-C", s.origin, "config", "uploadpack.allowFilter", "true"], s.env)
        s.mk = tmp / "mk"
        _run([GIT, "init", "-q", "-b", "main", s.mk], s.env)
        for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
            _run([GIT, "-C", s.mk, "config", k, v], s.env)
        _run([GIT, "-C", s.mk, "remote", "add", "origin", "file://" + str(s.origin)], s.env)
        s.c1 = s.commit("c1", push="main")
        _run([GIT, "-C", s.mk, "push", "-q", "origin", "%s:refs/heads/ops/main-base" % s.c1], s.env)
        s.pc, s.pk = tmp / "pc", tmp / "pk"   # pc = 카드 리포(blob:none) · pk = 팩 리포(전체 클론)
        _run([GIT, "clone", "-q", "--filter=blob:none", "--no-local", "file://" + str(s.origin), s.pc], s.env)
        _run([GIT, "clone", "-q", "file://" + str(s.origin), s.pk], s.env)
        _run([GIT, "-C", s.pc, "config", "remote.origin.uploadpack", up], s.env)
        for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
            _run([GIT, "-C", s.pc, "config", k, v], s.env)
        s.r1 = s.commit("c2", push="side")   # 클론 뒤 원격에만 — pc 에는 없다 · 팩 대역에는 객체만
        _run([GIT, "-C", s.mk, "checkout", "-q", "--orphan", "root2"], s.env)
        s.orphan = s.commit("root2", push="root2")   # 팩 origin/main 대역 = 이 커밋(착지 sha 와 조상 관계 0)
        _run([GIT, "-C", s.mk, "checkout", "-q", s.r1], s.env)
        s.side = s.commit("c3", push="side")         # side 가지 자식 = base 로컬 대역
        _run([GIT, "-C", s.pk, "fetch", "-q", "origin", "side", "root2"], s.env)
        _run([GIT, "-C", s.pk, "update-ref", "refs/remotes/origin/main", s.orphan], s.env)
        for k, v in (("user.email", "t@t"), ("user.name", "t")):
            _run([GIT, "-C", s.pk, "config", k, v], s.env)
        _run([GIT, "-C", s.pk, "commit", "-q", "--allow-empty", "-m", "hidden"], s.env)
        s.hidden = _run([GIT, "-C", s.pk, "rev-parse", "HEAD"], s.env)   # 팩 대역에만 있는 객체 — 원격 어느 가지도 안 가리킨다(받기 실패 = cat-file rc 1)
        (s.pc / ".fable-team" / "teams" / TEAM / "runtime").mkdir(parents=True, exist_ok=True)   # pre_attempt journal 자리(기록 0)
        s.clear()

    def commit(s, msg, push=None):
        _run([GIT, "-C", s.mk, "commit", "-q", "--allow-empty", "-m", msg], s.env)
        sha = _run([GIT, "-C", s.mk, "rev-parse", "HEAD"], s.env)
        if push:
            _run([GIT, "-C", s.mk, "push", "-q", "origin", "HEAD:refs/heads/" + push], s.env)
        return sha

    def local(s, msg):
        """pc 안에서만 커밋(ref 를 옮기지 않는다) — 로컬 객체 대역."""
        _run([GIT, "-C", s.pc, "commit", "-q", "--allow-empty", "-m", msg], s.env)
        return _run([GIT, "-C", s.pc, "rev-parse", "HEAD"], s.env)

    def card_commit(s, sha):
        """카드 본문을 원격 cards 가지에 올리고 pc 에 ref 만 받는다(blob 은 filter 로 안 온다 = ㊸아 show lazy fetch)."""
        (s.mk / "design" / "harness" / "indices" / "진행").mkdir(parents=True, exist_ok=True)
        (s.mk / "design" / "harness" / "indices" / "진행" / (WORK + ".md")).write_text(
            "# 인덱스: %s\n- 상태: 대기\n- 착지: %s\n" % (WORK, sha), encoding="utf-8")
        _run([GIT, "-C", s.mk, "checkout", "-q", "-B", "cards", s.c1], s.env)
        _run([GIT, "-C", s.mk, "add", "-A"], s.env)
        _run([GIT, "-C", s.mk, "commit", "-q", "-m", "card"], s.env)
        _run([GIT, "-C", s.mk, "push", "-q", "origin", "HEAD:refs/heads/cards"], s.env)
        _run([GIT, "-C", s.pc, "fetch", "-q", "origin", "cards"], s.env)
        s.clear()
        return "origin/cards", "design/harness/indices/진행/%s.md" % WORK

    def drop(s, ref):
        _run([GIT, "-C", s.pc, "update-ref", "-d", ref], s.env)

    def clear(s):
        s.up.write_text(""), s.glog.write_text("")

    def upn(s):
        return len(s.up.read_text().splitlines())

    def glines(s):
        return s.glog.read_text().splitlines()

    def env1(s):
        return [x for x in s.glines() if x.startswith("env=1 ::")]


class K:
    """Landing 대역 — 실 git 을 self.env 로 돌린다(keeper.call 과 같은 꼴) · show 는 대본(body) 이 있으면 그 글자를 준다."""

    @staticmethod
    def make(land):
        class Fake(land.Landing):
            def __init__(self, w, root=None, pack=None, env=None):
                self.w, self.root, self.pack = w, str(root or w.pc), str(pack or w.pk)
                self.stale, self.cache, self.sent, self.logs, self.cards, self.body = set(), {}, [], [], [], None
                self.exc, self.gitlocal, self.real_show = None, 0, False
                self.env = dict(w.env if env is None else env)
                self.env["PATH"] = str(w.shim) + os.pathsep + self.env["PATH"]

            def resolve_card(self, team, work):
                return list(self.cards), None

            def git(self, repo, *a, retry=0, timeout=7):
                if self.exc is not None:
                    raise self.exc
                if a[:1] == ("show",) and self.body is not None and not self.real_show:
                    return 0, self.body, ""
                p = subprocess.run(["git", "-C", str(repo)] + [str(x) for x in a], capture_output=True, text=True,
                                   env=self.env, timeout=60)
                return p.returncode, p.stdout, p.stderr.strip()[:200]

            def git_local(self, *a, **kw):   # 계측 — 기준판(손 없음)은 그대로 git 으로 떨어짐다
                self.gitlocal += 1
                fn = getattr(type(self).__mro__[1], "git_local", None)
                return self.git(*a, **kw) if fn is None else fn(self, *a, **kw)

            def notify(self, *a):
                self.sent.append(a)

            def log(self, kind, *a):
                self.logs.append((kind,) + a)

        return Fake


def keeper(w, land, **kw):
    return K.make(land)(w, **kw)


def landing_card(k, sha):
    k.cards = [("origin/cards", "design/harness/indices/진행/%s.md" % WORK)]
    k.body = "# 인덱스\n- 착지: %s\n" % sha
    k.pre_attempt = lambda *a, **kv: ""
    return k


def popen_env(w, k):
    """Popen 대역 — keeper 가 자식을 띄울 때 넘기는 env(k.env) 를 그대로 받아 적는다."""
    out = w.tmp / "popen.env"
    subprocess.run(["/bin/sh", "-c", 'printf "env=%s\\n" "${GIT_NO_LAZY_FETCH:-unset}" > ' + str(out)], env=k.env)
    return out.read_text(encoding="utf-8").strip()


# ── ㊸가 · 㓈마 — partial clone 에 없는 sha · 원격 lazy fetch 0줄 (기준판 FAIL)
def test_ga_absent_sha_local_only(w, land=_land):
    k = landing_card(keeper(w, land()), w.r1)
    t0 = time.monotonic()
    out = k.landing(TEAM, WORK)
    el = time.monotonic() - t0
    assert out == (w.r1, None, "미도달"), out
    assert w.upn() == 0, w.up.read_text()
    assert el <= 2.0, el


def test_ma_next_ref_without_fetch(w, land=_land):
    k = landing_card(keeper(w, land()), w.r1)
    assert k.landing(TEAM, WORK)[2] == "미도달"
    assert w.upn() == 0, w.up.read_text()
    assert len([x for x in w.glines() if "merge-base --is-ancestor" in x]) == 3, w.glines()


# ── ㊸다 · ㊸라 — 판정값 그대로(회귀 고정)
def test_da_pack_ref_ancestor(w, land=_land):
    k = landing_card(keeper(w, land()), w.orphan)
    assert k.landing(TEAM, WORK) == (w.orphan, "pack:origin/main", "")
    assert w.upn() == 0, w.up.read_text()


def test_ra_local_object_not_ancestor(w, land=_land):
    sha = w.local("local-only")
    k = landing_card(keeper(w, land()), sha)
    assert k.landing(TEAM, WORK) == (sha, None, "미도달")
    assert w.upn() == 0, w.up.read_text()


# ── 㓈다 · 㓈라 — ref 가 안 풀림 = ⓒ(지금 호출 그대로)
def test_da_ref_missing_remote_only_sha(w, land=_land):
    k = landing_card(keeper(w, land()), w.r1)
    w.drop("refs/remotes/origin/ops/main-base")
    out = k.landing(TEAM, WORK)
    assert out == (None, None, "판정 불가 · 착지 조상 git rc 128"), out
    assert w.upn() >= 1, w.up.read_text()


def test_ra_ref_missing_local_sha(w, land=_land):
    k = landing_card(keeper(w, land()), w.c1)
    w.drop("refs/remotes/origin/ops/main-base")
    out = k.landing(TEAM, WORK)
    assert out == (None, None, "판정 불가 · 착지 조상 git rc 128"), out
    assert w.upn() == 0, w.up.read_text()


# ── G3 ⓒ — 로컬만으로 값을 못 정하는 rc(None·그 밖) = 지금 판 두 호출 그대로 다시(환경변수 없이)
def test_branch_c_other_rc_asks_remote(w, land=_land):
    k = landing_card(keeper(w, land()), w.c1)
    script = [(None, "", "timeout"), (0, "", "")]

    def git(repo, *a, **kw):
        return (0, k.body, "") if a[:1] == ("show",) else script.pop(0)

    k.git = git
    assert k.landing(TEAM, WORK) == (w.c1, "pack:origin/main", "")


# ── ㊸자 — 낡은 리포 = git 호출 0 · «판정 불가 · 팩 fetch 실패» 그대로
def test_ja_stale_repos(w, land=_land):
    k = landing_card(keeper(w, land()), w.r1)
    k.stale = {str(w.pk), str(w.pc)}
    assert k.landing(TEAM, WORK) == (None, None, "판정 불가 · 팩 fetch 실패")
    assert w.upn() == 0 and k.gitlocal == 0, (w.glines(), k.gitlocal)


# ── ㊸바 · ㊸사 — env 되돌림 · 새지 않음
def test_ba_env_already_zero(w, land=_land):
    env = dict(w.env, GIT_NO_LAZY_FETCH="0")
    k = keeper(w, land(), env=env)
    keep = k.env
    k.git_local(w.pc, "cat-file", "-e", w.c1)
    assert k.env["GIT_NO_LAZY_FETCH"] == "0", k.env["GIT_NO_LAZY_FETCH"]
    assert k.env is keep
    assert w.env1() == ["env=1 ::-C %s cat-file -e %s" % (w.pc, w.c1)], w.glines()


def test_sa_exception_restores_env(w, land=_land):
    k = keeper(w, land(), env=dict(w.env))
    k.exc = RuntimeError("끊김 예외 대역")
    with pytest.raises(RuntimeError):
        k.git_local(w.pc, "cat-file", "-e", w.c1)
    assert "GIT_NO_LAZY_FETCH" not in k.env, k.env.get("GIT_NO_LAZY_FETCH")


# ── ㊸아 — 한 바퀴: show(blob 없음) → 착지 판정 → Popen 대역
def test_a_round_show_and_popen(w, land=_land):
    ref, path = w.card_commit(w.c1)
    k = keeper(w, land())
    k.real_show, k.cards = True, [(ref, path)]
    k.pre_attempt = lambda *a, **kv: ""
    assert k.landing(TEAM, WORK) == (w.c1, "byz:origin/ops/main-base", "")
    assert w.upn() >= 1, w.up.read_text()   # show 는 본문을 받아 온다 = lazy fetch 가 살아 있다
    assert popen_env(w, k) == "env=unset"
    assert "GIT_NO_LAZY_FETCH" not in k.env


# ── ㊸나 · ㊸차 · ㊹가 · ㊹다 · 㓈가 · 㓈나 — r2247 pre_attempt cat-file = git_local(판정값 그대로 · env=1 은 cat-file 1줄뿐)
def pre(w, land, sha, base, at, fetch=None):
    if fetch:   # base 를 pc 에 실제로 받아 둔다(로컬 base 대역)
        _run([GIT, "-C", w.pc, "fetch", "-q", "origin", fetch], w.env)
        w.clear()
    k = keeper(w, land)
    return k, k.pre_attempt(TEAM, WORK, w.pc, sha, {"base_sha": base, "at": at})


def cat1(w, base):
    return ["env=1 ::-C %s cat-file -e %s" % (w.pc, base)]


def test_na_base_absent_remote(w, land=_land):
    k, out = pre(w, land(), w.c1, w.hidden, "2030-01-01T00:00:00")
    assert out.startswith("옛 착지 줄(attempt 전 · 다른 repo 시각)"), out
    assert w.upn() == 0, w.up.read_text()
    assert w.env1() == cat1(w, w.hidden), w.env1()


def test_cha_base_absent_progress(w, land=_land):
    sha = w.local("local-only")
    k, out = pre(w, land(), sha, w.hidden, "2000-01-01T00:00:00")
    assert out == "", out
    assert w.upn() == 0, w.up.read_text()
    assert w.env1() == cat1(w, w.hidden), w.env1()


def test_ga_base_local_ancestor(w, land=_land):
    k, out = pre(w, land(), w.c1, w.side, "2030-01-01T00:00:00", fetch="side")
    assert out == "옛 착지 줄(attempt 전) " + w.c1[:8], out
    assert w.env1() == cat1(w, w.side), w.env1()


def test_da_base_nowhere(w, land=_land):
    base = "0123456789" + "0" * 30
    k, out = pre(w, land(), w.c1, base, "2000-01-01T00:00:00")
    assert out == "", out
    assert w.env1() == cat1(w, base), w.env1()


def test_ga_base_local_equal_second(w, land=_land):
    k, out = pre(w, land(), w.c1, w.side, "2000-01-01T00:00:00", fetch="side")
    assert out == "옛 착지 줄(attempt 전) " + w.c1[:8], out
    assert w.env1() == cat1(w, w.side), w.env1()


def test_na_base_local_not_ancestor(w, land=_land):
    k, out = pre(w, land(), w.c1, w.orphan, "2030-01-01T00:00:00", fetch="root2")
    assert out == "", out
    assert w.env1() == cat1(w, w.orphan), w.env1()


# ── ㊸마 — PR 착지 손 0(git_local 0회) · upload-pack 수·판정이 env 없앤 판과 같다
def pr_round(w, land):
    k = keeper(w, land, env=dict(w.env))
    k.env.pop("GIT_NO_LAZY_FETCH", None)
    land.endings.latest = lambda kk, team: {WORK: ("a1", "h")}
    land.endings.intent = lambda kk, team, work, attempt, holder: {"worktree": str(w.pc)}
    land.endings._prs = lambda kk, repo, branch: [{"number": 7, "mergeCommit": {"oid": w.r1}, "baseRefName": "main"}]
    k.git = (lambda real: lambda repo, *a, **kv: (0, "nano/" + WORK, "") if a[:1] == ("rev-parse",) else
             (0, "https://github.com/o/r.git", "") if a[:1] == ("config",) else real(repo, *a, **kv))(k.git)
    w.clear()
    return land.endings.pr_landed(k, TEAM, WORK), w.upn(), k.gitlocal


def test_ma_pr_landing_untouched(w, land=_land):
    out, n, g = pr_round(w, land())
    assert g == 0, g                             # PR 착지 손 0 = git_local 0회
    assert out == (None, None, "착지 줄 없음"), out   # 카드 ㊸마 «none(착지 아님)» 그대로
    assert n == 1, (n, w.up.read_text())         # upload-pack 수가 지금과 같다


# ── 변이 M98 ~ M102 · M106 ~ M108 — 고친 글자 1곳만 바꾼 사본에서 그 사례가 FAIL
MUTANTS = {
    "M98": ('dict(keep, GIT_NO_LAZY_FETCH="1")', "keep", (test_ga_absent_sha_local_only, test_ma_next_ref_without_fetch)),
    "M99": ('keep = self.env\n        self.env = dict(keep, GIT_NO_LAZY_FETCH="1")',
            'keep = self.env\n        self.env["GIT_NO_LAZY_FETCH"] = "1"',
            (test_ba_env_already_zero, test_a_round_show_and_popen)),
    "M100": ("        try:\n            return self.git(repo, *args, **kw)\n        finally:\n            self.env = keep",
             "        return self.git(repo, *args, **kw)", (test_sa_exception_restores_env,)),
    "M101": ('rc, body, _ = self.git(self.root, "show"', 'rc, body, _ = self.git_local(self.root, "show"', (test_a_round_show_and_popen,)),
    "M102": ("if rc == 128 and self.git_local(", "if False and self.git_local(", (test_ga_absent_sha_local_only, test_ma_next_ref_without_fetch)),
    "M106": (' and self.git_local(repo, "rev-parse", "-q", "--verify", ref + "^{commit}", timeout=endings.ANC_S)[0] == 0', "",
             (test_da_ref_missing_remote_only_sha,)),
    "M107": ('rc = self.git(repo, "merge-base", "--is-ancestor", sha, ref, timeout=endings.ANC_S)[0]   # G3 ⓒ', 'rc = 128   # G3 ⓒ',
             (test_branch_c_other_rc_asks_remote,)),
    "M108": ('have = self.git_local(repo, "cat-file", "-e", base)[0] if base else 0', 'have = self.git(repo, "cat-file", "-e", base)[0] if base else 0',
             (test_na_base_absent_remote, test_cha_base_absent_progress, test_ga_base_local_ancestor, test_da_base_nowhere,
              test_ga_base_local_equal_second, test_na_base_local_not_ancestor)),   # r2247 방향 뒤집음 = 손 되돌림 → 6칸 FAIL
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, cases = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / LAND_PY).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, text.count(old))
    (copy / LAND_PY).write_text(text.replace(old, new), encoding="utf-8")
    land = _land(copy)
    for i, case in enumerate(cases):
        with pytest.raises(AssertionError):
            case(World(tmp_path / ("w%d" % i)), lambda: land)


@pytest.fixture()
def w(tmp_path):
    return World(tmp_path)
