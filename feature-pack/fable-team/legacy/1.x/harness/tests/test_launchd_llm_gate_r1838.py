"""r1838 — launchd 잡 LLM 0 판정기(ft_launchd_llm_gate.py) 반례 ①~⑥ · G1 = B(master #295034 — 입구에서 글자 그대로 닿는 파일만 통째).
① 할당 두 줄만 바뀜 → 결합 불일치 · ①′ source lib 만 바뀜 · ①″ 변수 경로 source = 결합 불가 · ② 본 판 그대로 ALLOW · ③ 미할당 변수 지점 = 결합 불가
④ 직접 회귀(글자 그대로 · helper · 새 동적 지점 · 주석 · 판독 실패 · 허용 장부 ts) · ⑤ 입구 뿌리 밖·외부 실행 파일 · ⑥ⓐ install.sh · ⑥ⓑ ft2 install.py
임시 폴더·가짜 plist·가짜 기준선·stub 만 · launchctl 0 · 실 LLM·네트워크 0 · sleep 0 · 판정기 대역 = env R1838_GATE."""
import hashlib, json, os, plistlib, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

H = Path(__file__).resolve().parents[1]
GATE = os.environ.get("R1838_GATE") or str(H / "bin/ft_launchd_llm_gate.py")
FT2 = H.parents[2] / "ft2"
ORIG = 'root={ext}\nrunner="$root"/safe\nrunner=${{runner}}tool\n"$runner" exec sample\n'
CHANGED = 'root={ext}\nrunner="$root"/co\nrunner=${{runner}}dex\n"$runner" exec sample\n'

@pytest.fixture
def w(tmp_path):
    t = tmp_path.resolve()
    [(t / d).mkdir() for d in ("bin", "ext", "out")]
    (t / "roots.tsv").write_text(f"bin\t{t / 'bin'}\n")
    return t

def put(path: Path, text, mode=0o755):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text if isinstance(text, bytes) else text.encode())
    path.chmod(mode)
    return path

def plist(w, *args, label="com.byz.ft-fx"):
    return put(w / f"{label}.plist", plistlib.dumps({"Label": label, "ProgramArguments": [str(a) for a in args]}), 0o644)

def gate(w, *args):
    r = subprocess.run([sys.executable, GATE, *map(str, args)], capture_output=True, text=True, timeout=25, cwd=w)
    return r.returncode, (r.stdout + r.stderr).strip()

def case(w, **files):
    """bin/ 아래 파일들을 쓰고 entry.sh 를 입구로 하는 plist 를 만든다(이름의 __ = /)."""
    [put(w / "bin" / k.replace("__", "/").replace("_sh", ".sh").replace("_py", ".py"), v) for k, v in files.items()]
    return plist(w, "/bin/bash", w / "bin/entry.sh")

def check(w, p, *extra):
    return gate(w, "check", "--plist", p, "--roots", w / "roots.tsv", "--baseline", w / "base.tsv", "--allow", w / "allow.tsv", *extra)

def record_baseline(w):  # H1 대역 — list-dyncalls 줄에 «본 사람 근거» 칸을 채워 기준선으로 쓴다(결합 불가 줄 = 결합 칸 '-')
    rc, out = gate(w, "list-dyncalls", "--roots", w / "roots.tsv")
    assert rc == 0, out
    rows = [ln.split("\t") for ln in out.splitlines() if ln.strip()]
    (w / "base.tsv").write_text("".join(f"{r[0]}\t{r[1]}\t{r[2]}\th-test-oppa\n" for r in rows))
    return rows

def test_1_da_assignments_changed_rejects(w):
    p, rows = case(w, entry_sh=ORIG.format(ext=w / "ext")), record_baseline(w)
    assert len(rows) == 1 and rows[0][0] == "bin/entry.sh" and len(rows[0][1]) == 16 and len(rows[0][2]) == 64, rows
    assert check(w, p) == (0, "ALLOW com.byz.ft-fx")                      # ② 사람이 본 판 그대로
    put(w / "bin/entry.sh", CHANGED.format(ext=w / "ext"))
    rc, out = check(w, p)
    assert rc == 1 and out.startswith("REJECT launchd-llm com.byz.ft-fx ") and "기준선 결합 불일치" in out and "entry.sh:4" in out, out

def test_1b_sourced_lib_changed_rejects(w):
    p = case(w, lib_sh="runner=/usr/bin/true\n", entry_sh=f'root={w / "bin"}\n. "$root/lib.sh"\n"$runner" exec sample\n')
    assert record_baseline(w) and check(w, p)[0] == 0
    put(w / "bin/lib.sh", "runner=/tmp/codex\n", 0o644)
    rc, out = check(w, p)
    assert rc == 1 and "기준선 결합 불일치" in out and "entry.sh:3" in out, out

def test_r1a_same_line_source_bound(w):  # DA HOLD R1(#295443): 앞 명령 뒤 같은 줄 source 도 결합·추적
    p = case(w, lib_sh="y=1\n", entry_sh=f'runner=/usr/bin/true\ntrue; source "{w / "bin"}/lib.sh"\n"$runner" exec sample\n')
    assert record_baseline(w) and check(w, p)[0] == 0
    put(w / "bin/lib.sh", f"runner={w / 'ext'}/codex\n", 0o644)
    rc, out = check(w, p)
    assert rc == 1 and "기준선 결합 불일치" in out and "entry.sh:3" in out, out

def test_r1b_same_line_source_literal_helper(w):
    rc, out = check(w, case(w, lib_sh=f"{w / 'ext'}/codex exec x\n", entry_sh=f'true && source "{w / "bin"}/lib.sh"\n'))
    assert rc == 1 and "글자 그대로 LLM 호출" in out and "lib.sh:1" in out, out

def test_r3_guarded_missing_source_marker(w):  # r3 R1: [ -f P ] && . P · P 없음 = 없음 표식 결합 · 생기면 불일치 · 가드 없으면 결합 불가
    opt = w / "bin/opt.sh"
    p = case(w, entry_sh=f'runner=/usr/bin/true\nif [ -f "{opt}" ]; then x="$(. "{opt}" && echo y)"; fi\n"$runner" exec sample\n')
    assert record_baseline(w) and check(w, p) == (0, "ALLOW com.byz.ft-fx")
    put(opt, f"runner={w / 'ext'}/codex\n", 0o644)
    rc, out = check(w, p)
    assert rc == 1 and "기준선 결합 불일치" in out and "entry.sh:3" in out, out
    rc, out = check(w, case(w, entry_sh=f'runner=/usr/bin/true\n. "{w / "bin/none.sh"}"\n"$runner" exec sample\n'))
    assert rc == 1 and "결합 불가" in out, out

@pytest.mark.parametrize("where,expect", [("bin", 0), ("ext", 1)])
def test_r3_python_import_from_root(w, where, expect):  # r3 R2: 뿌리 폴더 안 모듈 = 따라가 결합 · 뿌리 밖 = 결합 불가
    (w / "roots.tsv").write_text(f"bin\t{w / 'bin'}\nst\t{w / 'st'}\n")
    put(w / where / "seatmod.py", "def judge():\n    return 1\n", 0o644)
    p = plist(w, "/usr/bin/python3", put(w / "st/check.py", "import subprocess, sys\nimport seatmod\nsubprocess.run(sys.argv[1:])\n"))
    rc, out = record_baseline(w) and check(w, p)
    assert rc == expect and ("결합 불가" in out if expect else out == "ALLOW com.byz.ft-fx"), out
    if not expect:
        put(w / "bin/seatmod.py", "import os\nos.system('true')\n", 0o644)
        assert "기준선 결합 불일치" in check(w, p)[1]

def test_r3_comment_dot_word_is_not_source(w):  # r3 R3: 주석 속 «). 낱말» ≠ source · 같은 줄 코드 . "$X" = 그대로 결합 불가
    p = case(w, entry_sh='runner=/usr/bin/true\nN=$(date +%s); E=3600      # 단일 임계 (§4-3). 축별 상수 없음\n"$runner" exec sample\n')
    assert record_baseline(w) and check(w, p) == (0, "ALLOW com.byz.ft-fx")   # 결합 계산(동적 지점 있음)에서도 주석 속 «. 축별» = source 0
    rc, out = check(w, case(w, entry_sh='x=1; . "$X/lib.sh"   # (참고). 메모\n'))
    assert rc == 1 and "결합 불가" in out and "entry.sh:1" in out, out

def test_1c_variable_source_path_unbindable(w):
    p = case(w, lib_sh="x=1\n", entry_sh='. "$X/lib.sh"\nrunner=/usr/bin/true\n"$runner" exec sample\n')
    rc, out = record_baseline(w) and check(w, p)
    assert rc == 1 and "결합 불가" in out and "entry.sh:1" in out, out

def test_3_unassigned_variable_unbindable_but_plist_args_bindable(w):
    p = case(w, entry_sh='"$RUNNER" exec x\n')
    rc, out = record_baseline(w) and check(w, p)
    assert rc == 1 and "결합 불가" in out and "entry.sh:1" in out, out
    case(w, entry_sh='exec "$@"\n')                                       # plist 인자가 정하는 값 = 기준선 + 결합으로 통과
    assert record_baseline(w) and check(w, p) == (0, "ALLOW com.byz.ft-fx")

@pytest.mark.parametrize("files,expect,why", [
    ({"entry.sh": "codex exec sample\n"}, 1, "entry.sh:1"),
    ({"entry.sh": 'bash "$(dirname "$0")/helper.sh"\n', "helper.sh": 'H="$(cd "$(dirname "$0")" && pwd)"\nbash "$H/lib/worker.sh"\n',
      "lib/worker.sh": "x=1\nclaude -p hi\n", "lib/far.sh": "codex exec x\n"}, 1, "worker.sh:2"),       # 2단계 helper · 안 닿는 far.sh 는 범위 밖(G1 = B)
    ({"entry.sh": "bash helper.sh\n", "helper.sh": "x=1\n"}, 1, "검사 불가 동적 실행"),                   # 상대 경로 = cwd 따라 다름 = 따라갈 수 없음
    ({"entry.sh": "x=1\n", "far.sh": "codex exec x\n"}, 0, "ALLOW"),
    ({"entry.sh": "runner=co\nrunner=${runner}dex\n\"$runner\" exec sample\n"}, 1, "검사 불가 동적 실행"),
    ({"entry.sh": "# haiku 로 요약하던 옛 잡\n: codex\necho haiku\n"}, 0, "ALLOW"),
    ({"entry.sh": "curl -s https://api.anthropic.com/v1/messages\n"}, 1, "entry.sh:1"),
    ({"entry.sh": 'exec python3 "$(dirname "$0")/helper.py"\n', "helper.py": "import subprocess\nsubprocess.run(['codex', 'exec', 'x'])\n"}, 1, "helper.py:2"),
    ({"entry.sh": 'exec python3 "$(dirname "$0")/helper.py"\n', "helper.py": "import subprocess, sys\nsubprocess.run(sys.argv[1:])\n"}, 1, "검사 불가 동적 실행"),
    ({"entry.sh": 'exec python3 "$(dirname "$0")/helper.py"\n', "helper.py": "import mylib\n", "mylib.py": "import os\nos.system('claude -p x')\n"}, 1, "mylib.py:2"),
    ({"entry.sh": 'exec python3 "$(dirname "$0")/helper.py"\n', "helper.py": "import os\nimport anthropic\n"}, 1, "helper.py:2"),
])
def test_4_direct_regressions(w, files, expect, why):
    rc, out = check(w, case(w, **{k.replace("/", "__").replace(".", "_"): v for k, v in files.items()}))
    assert rc == expect and why in out, out

def test_4_unreadable_is_undecidable(w):
    rc, out = check(w, case(w, entry_sh='bash "$(dirname "$0")/bad.sh"\n', bad_sh=b"#!/bin/bash\n\xff\xfe codex\n"))
    assert rc == 3 and out.startswith("UNDECIDABLE launchd-llm com.byz.ft-fx ") and "bad.sh" in out, out
    assert check(w, w / "missing.plist")[1].startswith("UNDECIDABLE launchd-llm ")

def test_4_allow_ledger_needs_ts(w):
    p = case(w, entry_sh="codex exec sample\n")
    (w / "allow.tsv").write_text("com.byz.ft-fx\t\tcodex exec\n")
    assert check(w, p)[0] == 1
    (w / "allow.tsv").write_text("com.byz.ft-fx\t1794540000.123456\tcodex exec\n")
    assert check(w, p) == (0, "ALLOW com.byz.ft-fx")

def test_5_entry_outside_roots_and_external(w):
    put(w / "bin/entry.sh", "x=1\n")
    rc, out = check(w, plist(w, "/bin/bash", put(w / "out/x.sh", "echo hi\n")))
    assert rc == 1 and "검사 범위 밖 입구" in out, out
    rc, out = check(w, plist(w, "/bin/bash", "-c", "echo hi"))
    assert rc == 1 and "검사 범위 밖 입구" in out, out
    gcloud = put(w / "ext/gcloud", "#!/bin/bash\necho EXTERNAL_STUB\n")
    assert check(w, plist(w, gcloud, "compute", "ssh")) == (0, "ALLOW com.byz.ft-fx")
    rc, out = check(w, plist(w, put(w / "ext/claude", "#!/bin/bash\necho STUB\n"), "-p", "x"))
    assert rc == 1 and "claude" in out, out

def test_5_root_dir_mode(w):
    put(w / "bin/entry.sh", "x=1\n")
    assert gate(w, "check", "--root-dir", w / "bin", "--baseline", w / "base.tsv")[0] == 0
    put(w / "bin/t.py", "import os\nos.system('codex exec x')\n")
    rc, out = gate(w, "check", "--root-dir", w / "bin", "--baseline", w / "base.tsv")
    assert rc == 1 and "t.py:2" in out, out

def _pkg(w, version, body):
    pkg = w / f"pkg-{version}"
    put(pkg / "core/run.sh", body)
    out = subprocess.run([sys.executable, str(FT2 / "tools/manifest.py"), "build", str(pkg)], capture_output=True, text=True, timeout=25).stdout
    (pkg / "MANIFEST.json").write_text(out)
    doc = json.loads(out) | {"manifest_sha256": hashlib.sha256(out.encode()).hexdigest(), "schema": 1, "name": "ft2", "version": version}
    (pkg / "PACKAGE.json").write_text(json.dumps({k: doc[k] for k in ("schema", "name", "version", "source", "manifest_sha256")} | {"files": doc["count"]}))
    return pkg

def test_6b_ft2_current_switch_checked_before_write(w):
    root = w / "ft2root"
    env = {**os.environ, "FT2_LLM_GATE_BASELINE": str(w / "base.tsv"), "FT2_LAUNCH_AGENTS": str(w / "none")}
    run = lambda *a: subprocess.run([sys.executable, str(FT2 / "tools/install.py"), *map(str, a)], capture_output=True, text=True, env=env, timeout=70)  # noqa: E731
    first = run("install", _pkg(w, "9.0.1", "echo ok\n"), root)
    assert first.returncode == 0 and (root / "CURRENT").read_text() == "9.0.1\n", first.stdout + first.stderr
    bad = run("install", _pkg(w, "9.0.2", "codex exec x\n"), root)
    assert bad.returncode != 0 and (root / "CURRENT").read_text() == "9.0.1\n", bad.stdout + bad.stderr
    assert "launchd-llm" in bad.stdout + bad.stderr

STAND_IN = """import os, plistlib, sys
p = sys.argv[sys.argv.index("--plist") + 1]
d = plistlib.load(open(p, "rb"))
open(os.environ["GATE_LOG"], "a").write(d["Label"] + " " + " ".join(d["ProgramArguments"]) + "\\n")
if d["Label"] in os.environ["GATE_REJECT"].split():
    print("REJECT launchd-llm " + d["Label"] + " 글자 그대로 LLM 호출 bin/x.sh:1"); sys.exit(1)
print("ALLOW " + d["Label"])
"""

def test_6a_install_sh_rejected_label_not_written(w):
    """⑥ⓐ 연결: 렌더한 plist 마다 판정기 1회 · REJECT label = 쓰기 0 · 다른 label = 그대로 갱신 · 설치 rc 1 (판정기 대역 = FT_LAUNCHD_GATE)."""
    home, owner = w / "home", w / "byz"
    (la := home / "Library/LaunchAgents").mkdir(parents=True), (owner / ".fable-team/bin").mkdir(parents=True)
    genv = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "FT_"))} | {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
    for repo in (owner, w / "old"):  # old = 옛 렌더 루트(설치본이 렌더본과 달라 PENDING 이 되게)
        subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True, env=genv)
        subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "p0"], check=True, env=genv)
    (owner / ".fable-team/seats-planner.json").write_text('{"_hil_route":"fx#0"}\n')
    put(w / "lc", '#!/bin/bash\necho "$*" >> "$LC_LOG"\n[ "$1" = list ] && exit 113\n[ "$1" = print ] && echo "state = waiting"\nexit 0\n')
    put(w / "gate.py", STAND_IN)
    env = genv | {"HOME": str(home), "FT_LAUNCHCTL": str(w / "lc"), "LC_LOG": str(w / "lc.log"), "FT_LAUNCHD_GATE": str(w / "gate.py"),
                  "GATE_LOG": str(w / "gate.log"), "GATE_REJECT": "com.byz.ft-weekly-review com.byz.ft-news-desk"}
    before = {}
    for label in ("com.byz.ft-secret-scan", "com.byz.ft-weekly-review"):
        tpl = H / "kit/fable-team" / f"{label}.plist.template"
        r = subprocess.run([sys.executable, str(H / "bin/ft_plist_env.py"), "render-bin", str(tpl), str(w / "old")], capture_output=True, text=True, env=env, timeout=25)
        before[label] = put(la / f"{label}.plist", r.stdout, 0o644).read_bytes()
    r = subprocess.run(["bash", str(H / "install.sh"), "--apply", "--project", str(owner), "--home", str(home), "--launchd-new", "com.byz.ft-news-desk"],
                       capture_output=True, text=True, env=env, cwd=w, timeout=70)
    out = r.stdout + r.stderr
    assert r.returncode == 1 and "REJECT launchd-llm com.byz.ft-weekly-review" in out and "REJECT launchd-llm com.byz.ft-news-desk" in out, out[-2000:]
    assert (la / "com.byz.ft-weekly-review.plist").read_bytes() == before["com.byz.ft-weekly-review"], out[-2000:]
    assert (la / "com.byz.ft-secret-scan.plist").read_bytes() != before["com.byz.ft-secret-scan"], out[-2000:]
    assert not (la / "com.byz.ft-news-desk.plist").exists(), out[-2000:]
    assert f"com.byz.ft-secret-scan /bin/bash {owner}/.fable-team/bin/ft-secret-scan.sh" in (w / "gate.log").read_text()  # 렌더본을 판정
    assert "com.byz.ft-weekly-review" not in (w / "lc.log").read_text()
