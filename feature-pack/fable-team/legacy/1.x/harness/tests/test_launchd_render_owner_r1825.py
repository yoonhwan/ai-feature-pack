"""r1825 — 공용 launchd 잡 렌더 주인 루트 · secret-scan 기본 계획 목록 = 일반 파일만.
① 주인 표식(seats-planner.json) 없는 리포 --apply → plist 바이트 그대로 · SKIP 1줄 · launchctl 0
①′ 같은 리포 --launchd-new → 쓰기 0 · SKIP 1줄   ② 주인 리포 → 그 경로로 다시 그림 · env·주기 보존
③ 기본 목록 = 파일만(폴더 판정 0)   ③′ --plans <폴더> 는 지금 그대로   ④ 주인 루트 명부 → 새 검출 1 → 쪽지 1 · rc0
임시 HOME·임시 리포·launchctl 대역·판정기 대역만 · 실 LaunchAgents·실 launchd·실 /tmp/h* 0 · sleep 0.
"""
import os, plistlib, shutil, subprocess, sys  # noqa: E401
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541

H = Path(__file__).resolve().parents[1]
SCAN = "com.byz.ft-secret-scan"
TPL = H / "kit/fable-team" / f"{SCAN}.plist.template"
FAKE_LC = '#!/bin/bash\necho "$*" >> "$LC_LOG"\n[ "$1" = list ] && exit 113\n[ "$1" = print ] && echo "state = waiting"\nexit 0\n'
JUDGE = """import os, sys
p = sys.argv[2]
open(os.environ["JUDGE_LOG"], "a").write(p + "\\n")
if os.path.isdir(p):
    sys.exit(2)   # 진짜 판정기와 같은 꼴(폴더 = rc2)
if os.path.basename(p) == "h-secret":
    print("reject 1 비밀 모양"); sys.exit(1)
print("ok")
"""

def _env(**kw):
    e = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "FT_"))}
    e.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", **kw)
    return e

def _repo(path: Path, owner: bool) -> Path:
    (path / ".fable-team/bin").mkdir(parents=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True, env=_env())
    subprocess.run(["git", "-C", str(path), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "p0"],
                   check=True, env=_env())
    if owner:
        (path / ".fable-team/seats-planner.json").write_text('{"_hil_route":"fx-desk#0"}\n')
    return path.resolve()

@pytest.fixture
def world(tmp_path):
    t, home = tmp_path.resolve(), tmp_path.resolve() / "home"
    (home / "Library/LaunchAgents").mkdir(parents=True)
    (t / "lc").write_text(FAKE_LC); (t / "lc").chmod(0o755)  # noqa: E702
    w = {"t": t, "home": home, "la": home / "Library/LaunchAgents", "owner": _repo(t / "byz", True), "pack": _repo(t / "pack", False)}
    w["run_env"] = _env(HOME=str(home), FT_LAUNCHCTL=str(t / "lc"), LC_LOG=str(t / "lc.log"))
    rows = subprocess.run([sys.executable, str(H / "bin/ft_launchd_llm_gate.py"), "list-dyncalls", "--root-dir", str(H / "kit/fable-team/bin"), "--root-key", "live-bin"],
                          capture_output=True, text=True, timeout=25).stdout.splitlines()   # r1838: H1 뒤 상태 = 키트 동적 지점 사람 확인 기준선(실 판정기 그대로)
    (w["owner"] / ".fable-team/state").mkdir(exist_ok=True)
    (w["owner"] / ".fable-team/state/launchd-dyncall-baseline.tsv").write_text("".join("\t".join(r.split("\t")[:3] + ["fx-h1"]) + "\n" for r in rows))
    return w

def _render(w, root: Path, minute=17, extra_env=None) -> bytes:
    r = subprocess.run([sys.executable, str(H / "bin/ft_plist_env.py"), "render-bin", str(TPL), str(root)],
                       capture_output=True, text=True, env=w["run_env"], timeout=25)
    assert r.returncode == 0, r.stdout + r.stderr
    d = plistlib.loads(r.stdout.encode())
    d["StartCalendarInterval"]["Minute"] = minute
    d["EnvironmentVariables"].update(extra_env or {})
    return plistlib.dumps(d)

def _install(w, project: Path, *extra):
    r = subprocess.run(["bash", str(H / "install.sh"), "--apply", "--project", str(project), "--home", str(w["home"]), *extra],
                       capture_output=True, text=True, env=w["run_env"], cwd=w["t"], timeout=70)
    lc = (w["t"] / "lc.log").read_text() if (w["t"] / "lc.log").exists() else ""
    return r.returncode, r.stdout + r.stderr, lc

def _skip_line(project):  # 계약 L1 의 SKIP 줄 꼬리
    return f"(공용 잡 주인 루트 아님: {project} — seats-planner.json 없음)"

def test_1_pack_root_keeps_owner_plist(world):
    dst = world["la"] / f"{SCAN}.plist"
    before = _render(world, world["owner"])
    dst.write_bytes(before)
    rc, out, lc = _install(world, world["pack"])
    assert dst.read_bytes() == before, out[-1500:]
    assert out.count(f"SKIP launchd {SCAN} {_skip_line(world['pack'])}") == 1, out[-1500:]
    assert "LAUNCHD rendered=0" in out and lc == "", lc   # DA 메모: 주인 guard = launchctl 대역 호출 0

def test_1b_pack_root_launchd_new_writes_nothing(world):
    label = "com.byz.ft-weekly-review"
    rc, out, lc = _install(world, world["pack"], "--launchd-new", label)
    assert not (world["la"] / f"{label}.plist").exists(), out[-1500:]
    assert out.count(f"SKIP launchd {label} {_skip_line(world['pack'])}") == 1, out[-1500:]
    assert lc == "", lc

def test_2_owner_root_renders_and_keeps_env_and_period(world):
    dst = world["la"] / f"{SCAN}.plist"
    dst.write_bytes(_render(world, world["pack"], minute=18, extra_env={"FT_MACHINE_ONLY": "keep"}))
    rc, out, lc = _install(world, world["owner"])
    d = plistlib.loads(dst.read_bytes())
    o = str(world["owner"])
    assert d["ProgramArguments"][1] == o + "/.fable-team/bin/ft-secret-scan.sh" and d["WorkingDirectory"] == o, out[-1500:]
    assert d["EnvironmentVariables"]["FT_MACHINE_ONLY"] == "keep" and d["StartCalendarInterval"]["Minute"] == 18
    assert f"LAUNCHD applied {SCAN}" in out and f"bootstrap gui/{os.getuid()} {dst}" in lc

@pytest.fixture
def scan(tmp_path):
    t = tmp_path.resolve(); b = t / "bin"; b.mkdir()  # noqa: E702
    src = (H / "bin/ft-secret-scan.sh").read_text()
    assert src.count('"/tmp/h*"') == 1   # 실 /tmp 를 대역 폴더로 — 안 바뀌면 실 /tmp 를 읽으니 여기서 멈춘다
    (b / "ft-secret-scan.sh").write_text(src.replace('"/tmp/h*"', f'"{t}/tmp/h*"'))
    for f in (H / "bin").glob("ft_secret_*.py"):
        shutil.copy(f, b)
    (b / "ft_secret_judge.py").write_text(JUDGE)
    (t / "tmp/h-b").mkdir(parents=True); (t / "tmp/h-a").write_text("plan\n")  # noqa: E702
    (t / "mbox.sh").write_text(f'printf "%s\\n" "$*" >> "{t}/mail.log"\n')
    root = _repo(t / "byz", True)

    def run(*args, cwd=root):
        r = subprocess.run(["bash", str(b / "ft-secret-scan.sh"), *args], capture_output=True, text=True, cwd=cwd, timeout=70,
                           env=_env(HOME=str(t / "home"), FT_SECRET_SCAN_ROOT=str(root), FT_MBOX_SH=str(t / "mbox.sh"),
                                    JUDGE_LOG=str(t / "judge.log")))
        judged = (t / "judge.log").read_text().split() if (t / "judge.log").exists() else []
        mail = (t / "mail.log").read_text().splitlines() if (t / "mail.log").exists() else []
        return r.returncode, r.stdout + r.stderr, judged, mail
    return t, run

def test_3_default_plans_files_only(scan):
    t, run = scan
    rc, out, judged, _ = run()
    assert judged == [f"{t}/tmp/h-a"] and "판정 불가" not in out and rc == 0, out

def test_3b_explicit_plans_folder_unchanged(scan):
    t, run = scan
    rc, out, judged, _ = run("--plans", f"{t}/tmp/h-b")
    assert judged == [f"{t}/tmp/h-b"] and out.count(f"판정 불가 {t}/tmp/h-b 판정기 rc=2") == 1 and rc == 3, out

def test_4_owner_root_seats_new_finding_sends_one(scan):
    t, run = scan
    (t / "tmp/h-secret").write_text("plan\n")  # 검출 여부 = 판정기 대역이 이름으로 정한다
    rc, out, judged, mail = run()
    sends = [m for m in mail if m.startswith("send ")]
    assert rc == 0 and len(sends) == 1 and sends[0].startswith("send fx-desk#0 ft-secret-scan [HIL]"), out + repr(mail)
