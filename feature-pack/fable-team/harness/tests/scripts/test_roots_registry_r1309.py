"""r1309 — 루트 명부(roots.tsv) + 정상화 장치 일반화: 명부 칸 · 기준 ref · 우편 다리 · 다른 루트 좌석 제외 · 루트 plist 렌더.

기획 3184 r3(DA③ APPROVE) §3·§5 의 반례 X2~X12 중 «나노 손 안에서 끝나는» 것만 잰다.
  X1·X1b(kakao 루트 stall-scan plist 를 실제로 적재한 뒤의 [멈춤] 0/1)는 설치 h(카드 B·C) 뒤에만 잴 수 있다 — 여기서 재지 않는다.

세계 = 임시 루트 2개: `byz`(주 루트 · 사람 우편함 «.») + `kakao`(origin 없는 git 리포의 **하위 폴더** 루트 · 명부 = seats.json).
환경: R1309_BIN(시험할 bin) · R1309_COMM(시험할 comm) — 셸 짝 tests/test_roots_registry_r1309.sh 가 변이 사본을 넣는다.
격리: 실 launchd·실 우편함·실 /tmp 상태·실 좌석 tmux 0 · 가짜 tmux 만 PATH 에 · git 은 임시 폴더에만.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

HERE = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get("R1309_BIN") or HERE / "kit/fable-team/bin")
COMM = Path(os.environ.get("R1309_COMM") or HERE / "comm")

TEAMS_BYZ = "| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| planner | design/planner/ | 현역 | seats-planner.json |\n"
TEAMS_KAKAO = "| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| kakao | design/kakao/ | 현역 | seats.json |\n"


def write(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    return path


def seats(name: str, master: str, extra: list[str]) -> str:
    rows = {"_master": master, "_label": name, "_cards": f"design/{name}/indices", "_cards_wt": ""}
    rows.update({m: {"role": "master" if m == master else "nano"} for m in [master, *extra]})
    return json.dumps(rows, ensure_ascii=False)


def fake_plist(label: str, script: str) -> str:
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>{label}</string>'
            f'<key>ProgramArguments</key><array><string>/bin/bash</string><string>{script}</string></array>'
            f'<key>EnvironmentVariables</key><dict><key>FT_ROOT</key><string>/x</string></dict></dict></plist>\n')


class World:
    """임시 루트 2개 + 기계 루트 명부 1장 — 실 상태 파일은 하나도 안 건드린다."""

    def __init__(self, tmp: Path) -> None:
        self.tmp = tmp
        self.byz = tmp / "byz"
        self.kakao_top = tmp / "kakao"                     # git toplevel (origin 없음)
        self.kakao = self.kakao_top / ".worktrees/bootstrap/kakao-agent-bot-planning"   # 하위 폴더 루트
        self.plists = tmp / "plists"
        self.plists.mkdir()
        self.stub = tmp / "stub"
        self.stub.mkdir()
        t = self.stub / "tmux"
        t.write_text('#!/bin/sh\ncase "$1" in list-sessions) exit 0;; list-panes) exit 0;; esac\nexit 0\n')
        t.chmod(0o755)
        lc = self.stub / "launchctl"
        lc.write_text(
            '#!/bin/sh\n'
            f'log="{self.tmp}/launchctl.log"\n'
            'echo "$*" >> "$log"\n'
            'case "$1" in\n'
            '  print) label="${2##*/}"; [ -f "$FT_LCTL_DIR/$label.loaded" ] && exit 0; echo "Could not find service" >&2; exit 1;;\n'
            '  bootout) label="${2##*/}"; rm -f "$FT_LCTL_DIR/$label.loaded"; exit 0;;\n'
            '  bootstrap) label="$(basename "$3" .plist)"; echo loaded > "$FT_LCTL_DIR/$label.loaded"; exit 0;;\n'
            'esac\nexit 0\n')
        lc.chmod(0o755)
        (self.tmp / "lctl").mkdir()
        self._comm(self.byz)
        self._comm(self.kakao)
        write(self.byz / "design/TEAMS.md", TEAMS_BYZ)
        write(self.kakao / "design/TEAMS.md", TEAMS_KAKAO)
        write(self.byz / ".fable-team/seats-planner.json", seats("planner", "byz-planner-master-claude#150", ["byz-harness-master-claude#150"]))
        write(self.kakao / ".fable-team/seats.json", seats("kakao", "kakao-master#1", ["kakao-nano#0"]))
        for team in ("planner", "kakao"):
            (self.byz if team == "planner" else self.kakao).joinpath(f"design/{team}/indices").mkdir(parents=True, exist_ok=True)
        (self.byz / "design/planner/indices").mkdir(parents=True, exist_ok=True)
        for name in ("ft-tick.sh", "ft-stall-scan.sh"):
            src = BIN / name
            if src.is_file():
                for base in (self.byz, self.kakao):
                    (base / ".fable-team/bin").mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(src, base / ".fable-team/bin" / name)
        self.tsv = tmp / "roots.tsv"
        self.write_roots()
        git(self.kakao_top, "init", "-q")
        git(self.kakao_top, "config", "user.email", "r1309@example.com")
        git(self.kakao_top, "config", "user.name", "r1309")
        git(self.kakao_top, "add", "-A")
        git(self.kakao_top, "commit", "-qm", "base")
        git(self.kakao_top, "branch", "-M", "feature/bootstrap")
        self.env = {**os.environ, "FT_ROOTS_TSV": str(self.tsv), "FT_TEAMS_MD": "",
                    "FT_TICK_PLIST_DIR": str(self.plists), "PATH": f"{self.stub}{os.pathsep}{os.environ['PATH']}",
                    "FT_TICK_LAUNCHCTL": str(self.stub / "launchctl"), "FT_LCTL_DIR": str(self.tmp / "lctl")}
        self.env.pop("FT_TEAM_ATTACH_SANDBOX", None)
        self.env.pop("FT_MBOX_BRIDGED", None)

    def _comm(self, root: Path) -> None:
        dst = root / ".fable-team/comm"
        dst.mkdir(parents=True, exist_ok=True)
        for f in COMM.iterdir():
            if f.is_file() and f.suffix in (".py", ".sh"):
                shutil.copyfile(f, dst / f.name)

    def write_roots(self, kakao: bool = True) -> None:
        rows = [f"byz\t{self.byz}\t현역\torigin/main\t.\t기본"]
        if kakao:
            rows.append(f"kakao\t{self.kakao}\t현역\tfeature/bootstrap\t{self.byz}/.fable-team/comm\t{self.tmp}/ft-tick-root-kakao")
        write(self.tsv, "# 이름\t경로\t상태\t기준ref\t사람우편함\t틱잠금접두\n" + "\n".join(rows) + "\n")

    def env_for(self, root: Path, **extra: str) -> dict[str, str]:
        return {**self.env, "FT_ROOT": str(root), "FT_REPO_ROOT": str(root),
                "FT_MBOX_DIR": str(root / ".fable-team/comm"), **extra}

    def attach(self, root: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(BIN / "ft-team-attach.sh"), *args], env=self.env_for(root),
                              capture_output=True, text=True, timeout=60)

    def mbox(self, root: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(root / ".fable-team/comm/mbox.sh"), *args], env=self.env_for(root),
                              capture_output=True, text=True, timeout=60)

    def queue(self, root: Path) -> list[dict]:
        p = root / ".fable-team/comm/mailbox.jsonl"
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.is_file() else []

    def launchctl_loaded(self, label: str) -> Path:
        """가짜 launchctl 의 «적재됨» 표식 경로 — bootstrap 이 만들고 bootout 이 지운다."""
        return self.tmp / "lctl" / f"{label}.loaded"


def git(base: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(base), *args], capture_output=True, text=True, timeout=30)


def py(env: dict[str, str], code: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, timeout=60)


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


# ── X2 — roots.tsv 없음 = 지금 동작 그대로 + INFO 1줄
def test_r1_no_roots_tsv_keeps_today_and_says_info(w: World) -> None:
    w.tsv.unlink()
    w.tsv = w.tmp / "absent.tsv"
    w.env["FT_ROOTS_TSV"] = str(w.tsv)
    out = w.attach(w.kakao, "--all", "--check")
    assert "INFO 루트 명부 없음" in out.stdout, out.stdout
    base = subprocess.run(["bash", str(BIN / "ft-team-attach.sh"), "--all", "--check"],
                          env={**w.env_for(w.kakao), "FT_ROOTS_TSV": str(w.tmp / "absent.tsv")},
                          capture_output=True, text=True, timeout=60)
    assert base.stdout == out.stdout          # 명부 장치들이 «지금 그대로» 를 낸다
    # X2 의 나머지 절반: r1298 --check 의 «명단 밖 파생» 도 그대로 센다
    write(w.kakao / ".fable-team/seats-ghost.json", seats("ghost", "ghost#1", []))
    assert "명단 밖 파생 1: ghost" in w.attach(w.kakao, "--all", "--check").stdout


# ── X8 — 명부 = TEAMS.md «명부» 칸(seats.json) → rosters()·attach·ft-tick 이 같은 파일 · seats-kakao.json 생성 0
def test_r2_roster_column_is_the_single_source(w: World) -> None:
    env = w.env_for(w.kakao)
    code = ("import sys,json;sys.path.insert(0,%r);import ft_team_lib as L;"
            "r=L.rosters(%r);print(r[0]['seats_path'].name, r[0]['diag']);"
            "print(L.roster_path('kakao',%r).name)" % (str(BIN), str(w.kakao), str(w.kakao)))
    got = py(env, code)
    assert got.returncode == 0, got.stderr
    assert got.stdout.split() == ["seats.json", "OK", "seats.json"], got.stdout
    check = w.attach(w.kakao, "kakao", "--check")
    assert "S3 OK" in check.stdout, check.stdout
    assert not (w.kakao / ".fable-team/seats-kakao.json").exists()
    # ft-tick 좌석표 = 같은 칸(단일 현역 팀 루트)
    tick = subprocess.run([sys.executable, str(BIN / "ft_team_lib.py"), "seats-file", str(w.kakao)],
                          env=env, capture_output=True, text=True, timeout=30)
    assert tick.stdout.strip() == str(w.kakao / ".fable-team/seats.json"), tick.stdout + tick.stderr


# ── X5/X12 — 기준 ref = roots.tsv 칸(origin 없는 로컬 가지) · fetch 0 · 하위 폴더 루트
def test_r3_basis_ref_from_roots_tsv_for_directive_row(w: World) -> None:
    got = w.attach(w.kakao, "kakao", "--apply")
    assert got.returncode == 0, got.stdout + got.stderr
    row = (w.kakao / ".fable-team/state/directive-roots.tsv").read_text(encoding="utf-8").splitlines()
    assert row and row[0].split("\t")[2] == "feature/bootstrap", row
    ref = git(w.kakao, "rev-parse", "--verify", "feature/bootstrap")
    assert ref.returncode == 0, ref.stderr        # 로컬 가지가 실재한다(= fetch 없이 읽을 수 있다)
    basis = py(w.env_for(w.kakao), "import sys;sys.path.insert(0,%r);import ft_team_lib as L;print(L.basis_ref(%r))"
               % (str(BIN), str(w.kakao)))
    assert basis.stdout.strip() == "feature/bootstrap", basis.stdout + basis.stderr


# ── X5(배정 감시) — directive-roots 의 기본값 origin/main 은 roots.tsv 기준 ref 로 바뀐다
def test_r4_card_assign_uses_basis_ref(w: World) -> None:
    state = w.kakao / ".fable-team/state"
    state.mkdir(parents=True, exist_ok=True)
    (state / "directive-roots.tsv").write_text(f"kakao\t.\torigin/main\tdesign/kakao/indices\n", encoding="utf-8")
    code = ("import sys;sys.path.insert(0,%r);import ft_card_assign_watch as C;"
            "from pathlib import Path;print(C.strict_roots(Path(%r))[0][2])" % (str(BIN), str(w.kakao)))
    got = py(w.env_for(w.kakao), code)
    assert got.returncode == 0, got.stderr
    assert got.stdout.strip() == "feature/bootstrap", got.stdout


# ── X9 — 루트 틱·stall-scan plist 렌더: 잠금 경로 3개 필수 · BYZ 기본값과 중복이면 REJECT
def test_r5_root_plists_render_and_reject_lock_duplicate(w: World) -> None:
    write(w.plists / "com.byz.ft-tick.plist",
          '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key>'
          '<string>com.byz.ft-tick</string><key>EnvironmentVariables</key><dict>'
          '<key>FT_TICK_SEATS</key><string>x</string></dict></dict></plist>\n')
    got = w.attach(w.byz, "--root-render", "kakao")
    assert got.returncode == 0, got.stdout + got.stderr
    tick, stall = w.plists / "com.byz.ft-tick-kakao.plist", w.plists / "com.byz.ft-stall-scan-kakao.plist"
    assert tick.is_file() and stall.is_file(), got.stdout
    doc = json.loads(subprocess.run([sys.executable, "-c",
                                     "import plistlib,sys,json;print(json.dumps(plistlib.load(open(sys.argv[1],'rb'))))", str(tick)],
                                    capture_output=True, text=True).stdout)
    env = doc["EnvironmentVariables"]
    assert env["FT_TICK_PIDFILE"] == f"{w.tmp}/ft-tick-root-kakao.pid"
    assert env["FT_TICK_STATE_DIR"] == f"{w.tmp}/ft-tick-root-kakao-state"
    assert env["FT_TICK_STAMP_PREFIX"] == f"{w.tmp}/ft-tick-root-kakao-"
    assert doc["Label"] == "com.byz.ft-tick-kakao" and env["FT_ROOT"] == str(w.kakao)
    # BYZ 자신(틱잠금접두 «기본»)은 메인 틱과 잠금이 겹친다 → REJECT(중복) · 파일 0
    bad = w.attach(w.byz, "--root-render", "byz")
    assert bad.returncode != 0 and "중복" in bad.stdout + bad.stderr, bad.stdout + bad.stderr
    assert not (w.plists / "com.byz.ft-tick-byz.plist").exists()


# ── X10a — 평소 send 로 다른 루트 받는이 → 다리 1줄 · 내 큐 쓰기 0
def test_r6_mbox_send_bridges_other_root(w: World) -> None:
    got = w.mbox(w.kakao, "send", "byz-planner-master-claude#150", "kakao-master#1", "[HIL] 루트 넘는 쪽지")
    assert "BRIDGED" in got.stdout, got.stdout + got.stderr
    assert w.queue(w.kakao) == [], "내 큐에 쓰면 안 된다"
    rows = w.queue(w.byz)
    assert [r["to"] for r in rows] == ["byz-planner-master-claude#150"], rows
    assert rows[0]["from"] == "kakao-master#1"


# ── X10b — 어느 명부에도 없는 받는이 → «받는이 판정 불가» rc≠0 · 큐 쓰기 0
def test_r7_mbox_send_unknown_recipient_is_loud(w: World) -> None:
    got = w.mbox(w.kakao, "send", "ghost-seat#9", "kakao-master#1", "x")
    assert got.returncode != 0 and "받는이 판정 불가" in got.stderr, (got.returncode, got.stderr)
    assert w.queue(w.kakao) == [] and w.queue(w.byz) == []


# ── X10c — 다리 실패(그 루트 우편함 없음) = 판정 불가 rc≠0 (조용한 자기 큐 쓰기 0)
def test_r8_bridge_failure_is_loud(w: World) -> None:
    shutil.rmtree(w.byz / ".fable-team/comm")
    got = w.mbox(w.kakao, "send", "byz-planner-master-claude#150", "kakao-master#1", "x")
    assert got.returncode != 0 and "판정 불가" in got.stderr, (got.returncode, got.stderr)
    assert w.queue(w.kakao) == []


# ── X10d — 내 루트 명부에 있으면 다리 0(지금 그대로)
def test_r9_own_roster_is_not_bridged(w: World) -> None:
    got = w.mbox(w.kakao, "send", "kakao-nano#0", "kakao-master#1", "제 큐로")
    assert "BRIDGED" not in got.stdout and "QUEUED" in got.stdout, got.stdout + got.stderr
    assert [r["to"] for r in w.queue(w.kakao)] == ["kakao-nano#0"]
    assert w.queue(w.byz) == []


# ── X11 — 다른 루트 좌석은 «명부 밖» 이 아니다
def test_r10_other_root_seats_are_not_off_roster(w: World) -> None:
    code = ("import sys;sys.path.insert(0,%r);import ft_stall_detect as D;from pathlib import Path;"
            "root=Path(%r);teams=D.load_teams(root,warn=False);"
            "live=['kakao-master#1','byz-planner-master-claude#150','ghost#0'];"
            "print([x[0] for x in D.off_roster_live(root,live,teams)])" % (str(BIN), str(w.byz)))
    got = py(w.env_for(w.byz), code)
    assert got.returncode == 0, got.stderr
    assert got.stdout.strip() == "['ghost#0']", got.stdout
    # X11 의 반대편(= roots.tsv 없음 = 지금 동작): kakao 좌석도 e 로 센다
    got2 = py(w.env_for(w.byz, FT_ROOTS_TSV=str(w.tmp / "absent.tsv")), code)
    assert got2.stdout.strip() == "['ghost#0', 'kakao-master#1']", got2.stdout


# ── X4 — 같은 팀 이름이 두 루트: 각 루트 안에서만 센다(루트 넘는 명부 합치기 0)
def test_r11_same_team_name_two_roots_stay_separate(w: World) -> None:
    write(w.byz / "design/TEAMS.md", TEAMS_BYZ + "| kakao | design/kakao/ | 현역 | seats.json |\n")
    write(w.byz / ".fable-team/seats.json", seats("kakao", "byz-kakao-master#1", ["byz-kakao-nano#0"]))
    code = ("import sys;sys.path.insert(0,%r);import ft_stall_detect as D;from pathlib import Path;"
            "print([(t['team'],sorted(t['seats'])) for t in D.load_teams(Path(%r),warn=False)])" % (str(BIN), "%s"))
    left, right = py(w.env_for(w.byz), code % str(w.byz)), py(w.env_for(w.kakao), code % str(w.kakao))
    assert "'byz-kakao-nano#0'" in left.stdout and "'kakao-nano#0'" not in left.stdout, left.stdout
    assert "'kakao-nano#0'" in right.stdout and "'byz-kakao-nano#0'" not in right.stdout, right.stdout


# ── X3 — 그 팀 plist 의 ProgramArguments 가 «다른 현역 루트 아래» 면 «다른 루트 틱 OK» · 어긋나면 «어긋남»(plist 를 실제로 읽는다)
def test_r12_other_root_derived_ok_and_stray_path_is_bad(w: World) -> None:
    write(w.byz / ".fable-team/seats-kakao.json", seats("kakao", "kakao-master#1", []))
    plist = w.plists / "com.byz.ft-tick-kakao.plist"
    write(plist, fake_plist("com.byz.ft-tick-kakao", str(w.kakao / ".fable-team/bin/ft-tick.sh")))
    got = w.attach(w.byz, "--all", "--check")
    assert "다른 루트 틱 OK 1: kakao" in got.stdout, got.stdout
    assert "명단 밖 파생" not in got.stdout, got.stdout
    # 같은 파생인데 plist 가 «옛 사본» 을 가리키면 어긋남(bad 로 센다)
    write(plist, fake_plist("com.byz.ft-tick-kakao", "/opt/old-copy/.fable-team/bin/ft-tick.sh"))
    bad = w.attach(w.byz, "--all", "--check")
    assert "어긋남 kakao" in bad.stdout and "명단 밖 파생 1: kakao" in bad.stdout, bad.stdout
    # roots.tsv 에서 빠지면(plist 경로는 그대로) 다시 «명단 밖 파생»
    write(w.tsv, f"byz\t{w.byz}\t현역\torigin/main\t.\t기본\n")
    plain = w.attach(w.byz, "--all", "--check")
    assert "명단 밖 파생 1: kakao" in plain.stdout, plain.stdout


# ── 루트 명부가 깨지면 «판정 불가» 1줄(조용한 기본값 0)
def test_r13_broken_roots_tsv_is_loud(w: World) -> None:
    write(w.tsv, "byz\t/only/two\n")
    out = w.attach(w.byz, "--all", "--check")
    assert "ERROR 루트 명부 판정 불가" in out.stdout, out.stdout


# ── X6 — 덮기 전 사본 + 되돌림(복원 → bootout → 확인 → bootstrap) · 두 번째 되돌림 REJECT
def test_r14_render_snapshots_and_revert_restores(w: World) -> None:
    before = fake_plist("com.byz.ft-tick-kakao", "/old/bin/ft-tick.sh")
    tick = w.plists / "com.byz.ft-tick-kakao.plist"
    write(tick, before)
    lc = w.launchctl_loaded("com.byz.ft-tick-kakao")
    lc.write_text("loaded\n", encoding="utf-8")   # 설치 상태 = 이미 launchd 에 적재돼 있다
    got = w.attach(w.kakao, "--root-render", "kakao")
    assert got.returncode == 0, got.stdout + got.stderr
    assert tick.read_bytes() != before.encode(), "렌더가 plist 를 바꿔야 한다"
    snaps = sorted((w.kakao / ".fable-team/state/root-attach").glob("*-kakao"))
    assert snaps and (snaps[-1] / "before/com.byz.ft-tick-kakao.plist").is_file(), snaps
    manifest = json.loads((snaps[-1] / "manifest.json").read_text(encoding="utf-8"))
    assert [f["before_exists"] for f in manifest["files"]].count(True) == 1, manifest
    # 되돌림 — 「처음에 없던」 stall-scan plist 는 .disabled-<stamp> 로 «옮긴다»(삭제 0)
    rev = w.attach(w.kakao, "--root-revert", "kakao")
    assert rev.returncode == 0, rev.stdout + rev.stderr
    assert tick.read_bytes() == before.encode(), "사본 바이트로 복원돼야 한다"
    log = (w.tmp / "launchctl.log").read_text(encoding="utf-8")
    assert log.index("bootout") < log.index("bootstrap"), log
    assert lc.is_file() and "loaded" in lc.read_text(encoding="utf-8"), "bootout 뒤 bootstrap 으로 다시 적재"
    assert list(w.plists.glob("com.byz.ft-stall-scan-kakao.plist.disabled-*")), list(w.plists.iterdir())
    again = w.attach(w.kakao, "--root-revert", "kakao")
    assert again.returncode != 0 and "이미 되돌린 사본" in again.stdout + again.stderr, again.stdout + again.stderr
