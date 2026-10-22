#!/usr/bin/env bash
# test_mirror_install_list.sh — 미러 설치본이 «본체가 import 하는 로컬 모듈» 을 전부 가져가는가 (r739 반송 · arch §195)
#  사건: r739 이 새 모듈 mirror_backlog.py 를 추가했는데 install.sh 고정 목록에 없어 설치본이
#        ModuleNotFoundError 로 30초마다 죽었다(KeepAlive 데몬 = 미러 전면 정지).
#  ① 목록 대조 — byz_mbox_slack_mirror.py 의 로컬 import(같은 폴더 .py) 가 install.sh 목록에 전부 있다
#  ② 설치 시뮬 — 임시 HOME 에 install.sh 를 그대로 흉내(launchctl·plutil 은 스텁) → 설치본에서 import 성공
#  ③ 변이 — 목록에서 mirror_backlog.py 를 빼면 ①②가 FAIL(빨강이 실제로 잡힌다)
# 실 launchd·실 ~/.hermes 쓰기 0 — HOME·PATH 전부 임시.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../harness/kit/slack-mirror}"
INSTALL="${SLACK_MIRROR_INSTALL:-$KIT/install.sh}"
[ -f "$INSTALL" ] || { echo "FAIL install.sh 없음: $INSTALL"; exit 1; }
out="$(python3 -I - "$KIT" "$INSTALL" <<'PYEOF' 2>&1
import os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

KIT, INSTALL = Path(sys.argv[1]), Path(sys.argv[2])
BODY = "byz_mbox_slack_mirror.py"
fails = 0
def check(name, cond, detail=""):
    global fails
    if cond:
        print(f"PASS {name}")
    else:
        fails += 1
        print(f"FAIL {name} {detail}")

def install_list(path: Path) -> list[str]:
    """install.sh 의 `for f in …; do` 고정 목록 → 파일 이름들."""
    m = re.search(r"^for f in (.+?); do$", path.read_text(encoding="utf-8"), re.M)
    assert m, "install.sh 에 고정 목록(for f in …; do)이 없다"
    return m.group(1).split()

def local_imports(body: Path) -> list[str]:
    """본체가 import 하는 로컬 모듈(같은 폴더에 .py 가 있는 이름) — 설치 목록에 반드시 있어야 한다."""
    names = set()
    for ln in body.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(?:import|from)\s+([A-Za-z_][\w]*)", ln)
        if m and (KIT / f"{m.group(1)}.py").is_file():
            names.add(f"{m.group(1)}.py")
    return sorted(names)

def simulate(install: Path, tag: str) -> tuple[bool, str, Path]:
    """install.sh 를 임시 HOME 에서 그대로 실행 — launchctl·plutil 은 PATH 스텁(실 launchd 0). 설치본 폴더를 돌려준다."""
    t = Path(tempfile.mkdtemp(prefix=f"r739-inst-{tag}-"))
    home, root, shim = t / "home", t / "root", t / "bin"
    for d in (home / ".hermes" / "scripts", root / ".fable-team" / "comm", shim):
        d.mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "comm" / "mailbox.log.jsonl").write_text("", encoding="utf-8")
    tok = home / ".hermes" / "secrets" / "yoonhwan_bot.env"
    tok.parent.mkdir(parents=True, exist_ok=True)
    tok.write_text("xoxb-000\n", encoding="utf-8")
    tok.chmod(0o600)
    inbox = t / "ft-inbox.sh"
    inbox.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    for tool in ("launchctl", "plutil"):  # 실 데몬·실 plist 건드리지 않는다
        f = shim / tool
        f.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        f.chmod(0o755)
    env = {**os.environ, "HOME": str(home), "BYZ_ROOT": str(root), "FT_INBOX_BIN": str(inbox),
           "PATH": f"{shim}:{os.environ.get('PATH', '')}"}
    got = home / ".hermes" / "scripts"
    r = subprocess.run(["bash", str(install)], env=env, capture_output=True, text=True)
    if r.returncode != 0:
        return False, f"install rc={r.returncode}: {(r.stderr or r.stdout).strip()[:200]}", got
    imp = subprocess.run([sys.executable, "-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); import byz_mbox_slack_mirror", str(got)],
                         capture_output=True, text=True)
    tail = (imp.stderr or "").strip().splitlines()
    return imp.returncode == 0, (tail[-1] if tail else "")[:200], got


need = local_imports(KIT / BODY)
listed = install_list(INSTALL)
missing = [n for n in need if n not in listed]
check("① 본체 로컬 import 전부 목록에 있다", not missing, f"목록 누락: {missing} (목록 {len(listed)}개)")
check("① 새 모듈 mirror_backlog.py 가 목록에 있다", "mirror_backlog.py" in listed, str(listed[:5]))
ok, why, got = simulate(INSTALL, "real")
check("② 설치 시뮬 → 설치본에서 import 성공", ok, why)
check("② 설치본에 mirror_backlog.py 사본 존재", (got / "mirror_backlog.py").is_file(), str(got))

# ③ 변이 — 목록에서 mirror_backlog.py 를 빼면 ①② 가 FAIL (실제 사건 재현)
mut_kit = Path(tempfile.mkdtemp()) / "kit"  # 키트 사본에서만 목록을 고친다(정본 쓰기 0)
shutil.copytree(KIT, mut_kit)
mut = mut_kit / "install.sh"
mut.write_text(INSTALL.read_text(encoding="utf-8").replace(" mirror_backlog.py", "", 1), encoding="utf-8")
mlist = install_list(mut)
check("③ 변이: 목록에서 빼면 ① 이 먼저 잡는다", "mirror_backlog.py" not in mlist and bool([n for n in local_imports(KIT / BODY) if n not in mlist]))
ok2, why2, _ = simulate(mut, "mutant")
check("③ 변이: 설치본 import 가 ModuleNotFoundError 로 죽는다", not ok2 and "mirror_backlog" in why2, why2)

print(f"RESULT fail={fails}")
sys.exit(1 if fails else 0)
PYEOF
)"
rc=$?
echo "$out"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED"; exit 1
