#!/usr/bin/env python3
"""cartier-auto CLI: doctor / wishlist / schedule / status / logs / stop."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from ._common import (
    INSTALL_FILE, JOBS_DIR, LOG_DIR, PROJECT_DIR, STATE_HOME,
    install_targets, is_installed, load_creds, load_job, missing_creds,
    now_kst, read_install_state, run_capture, save_job, ts,
)
from .config import load_site_config, write_default_config
from .monitor import (
    DEFAULT_INTERVAL, SCHEDULED,
    validate_interval, validate_run_at,
)
from .site import SiteClient


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="cartier-auto", description="까르띠에 리스톡 자동 구매 감시")
    sub = parser.add_subparsers(dest="command", required=True)

    d = sub.add_parser("doctor", help="설치·자격증명 readiness")
    d.add_argument("--json", action="store_true")

    setup_p = sub.add_parser("setup", help="설치 상태 확인·설치 진행/유도")
    setup_p.add_argument("--json", action="store_true")

    w = sub.add_parser("wishlist", help="위시리스트 상품 조회")
    w.add_argument("--json", action="store_true")

    s = sub.add_parser("schedule", help="구매 예약 작업 생성")
    s.add_argument("--pid", required=True)
    s.add_argument("--name", default="")
    s.add_argument("--price", type=int, default=None)
    s.add_argument("--at", required=True, help="YYYY-MM-DD HH:MM:SS (KST)")
    s.add_argument("--interval", type=float, default=DEFAULT_INTERVAL)
    s.add_argument("--approved-price", type=int, required=True)
    s.add_argument("--confirm", action="store_true", help="최종 승인 후에만 실제 감시 시작")

    st = sub.add_parser("status", help="작업 상태 조회")
    st.add_argument("--job")
    st.add_argument("--json", action="store_true")

    lg = sub.add_parser("logs", help="작업 로그 출력")
    lg.add_argument("--job", required=True)

    launcher = sub.add_parser("launch", help="예약 감시를 백그라운드로 시작")
    launcher.add_argument("--job", required=True)

    runner_p = sub.add_parser("run", help="감시 프로세스 직접 실행 (백그라운드 런처가 호출)")
    runner_p.add_argument("--job", required=True)

    sp = sub.add_parser("stop", help="작업 중지 (사용자 명시 요청 시에만)")
    sp.add_argument("--job", required=True)

    return parser


def cmd_doctor(args) -> int:
    write_default_config()
    creds = load_creds()
    missing = missing_creds()
    py_ok, py_ver, py_msg = check_python()
    chrome = chrome_path()
    venv = find_venv_python()
    inst_state = read_install_state()
    targets = install_targets()
    ready = not missing and py_ok and bool(chrome) and bool(venv) and inst_state.get("installed")
    status = {
        "ready": ready,
        "install": {
            "installed": inst_state.get("installed"),
            "version": inst_state.get("version"),
            "installed_at": inst_state.get("installed_at"),
            "skill_dir": targets.get("skill_dir"),
            "skill_exists": targets.get("exists"),
            "targets": {k: v.get("exists") for k, v in targets.items() if isinstance(v, dict)},
        },
        "python": {"ok": py_ok, "version": py_ver or py_msg},
        "chrome": {"ok": bool(chrome), "path": chrome},
        "runtime": {"ok": bool(venv), "venv_python": venv},
        "credentials": {"ok": not missing, "missing": missing},
        "state_dir": str(STATE_HOME),
    }
    if args.json:
        print(_json(status))
    else:
        inst_state = read_install_state()
        print("cartier-auto doctor")
        print(yesno(bool(inst_state.get("installed")), f"설치 완료 (버전 {inst_state.get('version','?')})"))
        print(yesno(py_ok, f"Python 3.11+ ({py_ver or py_msg})"))
        print(yesno(bool(chrome), f"Google Chrome ({chrome})"))
        print(yesno(bool(venv), f"Playwright 런타임 ({venv})"))
        print(yesno(not missing, f"자격증명 4종 (누락: {', '.join(missing) or '없음'})"))
        print("READY" if ready else "NOT_READY")
    return 0 if ready else 1


def _ready_check() -> tuple[bool, list[str]]:
    reasons = []
    py_ok, _, msg = check_python()
    if not py_ok:
        reasons.append(f"python: {msg}")
    if not chrome_path():
        reasons.append("chrome: Google Chrome 없음")
    if not _ready_python():
        reasons.append("playwright: venv에 playwright 없음")
    missing = missing_creds()
    if missing:
        reasons.append(f"credentials missing: {', '.join(missing)}")
    return (not reasons), reasons


def cmd_wishlist(args: argparse.Namespace) -> int:
    return _wishlist_impl(args)


def _wishlist_impl(args: argparse.Namespace) -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print(_json({"error": "playwright 런타임이 없습니다 — install.sh 실행 필요"}))
        return 3
    creds = load_creds()
    if not all(creds.get(k) for k in ("CARTIER_ID", "CARTIER_PASSWORD")):
        print(_json({"error": "CARTIER_ID/CARTIER_PASSWORD 자격증명 필요"}))
        return 2
    config = load_site_config()
    from ._common import ensure_dirs
    ensure_dirs()
    state_path = STATE_HOME / "session-state.json"
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=False, channel="chrome",
            args=["--disable-blink-features=AutomationControlled", "--disable-infobars"])
        context = browser.new_context(
            storage_state=str(state_path) if state_path.exists() else None,
            viewport={"width": 1440, "height": 900}, locale="ko-KR",
            user_agent=chrome_user_agent())
        context.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined});")
        page = context.new_page()
        client = SiteClient(config=config)
        page.goto(config["base_url"] + "/ko-kr/home", wait_until="domcontentloaded")
        SiteClient.dismiss_banners(page)
        if not client.is_logged_in(page):
            if not client.login(page, creds):
                browser.close()
                print(_json({"error": "까르띠에 로그인 실패"}))
                return 1
            context.storage_state(path=str(state_path))
        client.set_page(page)
        items = client.fetch_wishlist()
        browser.close()
    payload = {"items": items, "count": len(items)}
    print(_json(payload))
    return 0


# ---- 헬퍼 ----

def _json(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2)


def yesno(ok: bool, text: str) -> str:
    return ("✔ " if ok else "✖ ") + text


def check_python() -> tuple[bool, str, str]:
    """(ok, version, message) — 설치 venv 또는 python3의 3.11+ 확인."""
    import subprocess
    candidates = []
    venv_py = find_venv_python()
    if venv_py:
        candidates.append(venv_py)
    candidates.append("python3")
    for candidate in candidates:
        try:
            proc = subprocess.run([candidate, "--version"], capture_output=True, text=True, timeout=10)
            out = (proc.stdout or proc.stderr or "").strip()
            ver = out.split()[-1] if out else ""
            parts = [int(x) for x in ver.split(".")[:2] if x.isdigit()]
            if parts and (parts[0], parts[1]) >= (3, 11):
                return True, ver, ""
        except Exception:
            continue
    return False, "", "Python 3.11+ 필요 (venv 또는 python3)"


def chrome_path() -> str:
    import subprocess
    candidates = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
    ]
    for c in candidates:
        if Path(c).exists():
            return c
    rc, out = run_capture(["bash", "-lc", "command -v google-chrome google-chrome-stable chromium 2>/dev/null | head -1"])
    return out.strip()


def find_venv_python() -> str:
    """venv(설치 시 생성)에서 playwright 지원 Python 경로. 없으면 빈 문자열."""
    candidates: list[str] = []
    env_py = os.environ.get("CARTIER_AUTO_PYTHON")
    if env_py:
        candidates.append(env_py)
    venv_dirs = [
        PROJECT_DIR / ".venv",
        STATE_HOME / ".venv",
        Path.home() / ".local" / "state" / "cartier-auto" / ".venv",
    ]
    for v in venv_dirs:
        candidates.append(str(v / "bin" / "python"))
    candidates.append("python3")
    for candidate in candidates:
        if not candidate:
            continue
        rc, out = run_capture(["bash", "-lc", f"command -v '{candidate}' >/dev/null 2>&1 && '{candidate}' -c 'import playwright'"])
        if rc == 0:
            return candidate
    return ""


def _ready_python() -> bool:
    return bool(find_venv_python())


# ---- schedule / status / logs / stop ----

def cmd_schedule(args: argparse.Namespace) -> int:
    if not args.confirm:
        print("schedule은 최종 승인(--confirm)이 있어야만 작업을 생성합니다.")
        return 2
    try:
        validate_run_at(args.at)
    except ValueError as exc:
        print(_json({"error": str(exc)}))
        return 2
    try:
        interval = validate_interval(args.interval)
    except ValueError as exc:
        print(_json({"error": str(exc)}))
        return 2
    job_id = now_kst().strftime("%Y%m%d_%H%M%S_%f")[:-3]
    spec = {
        "pid": args.pid,
        "name": args.name or args.pid,
        "price_krw": args.price,
        "run_at": normalize_kst(args.at),
        "interval": interval,
        "approved_price": args.approved_price,
        "created_at": ts(),
    }
    job = {
        "id": job_id,
        "spec": spec,
        "status": SCHEDULED,
        "approved": True,
        "transitions": [{"status": SCHEDULED, "at": ts(), "note": "사용자 최종 승인"}],
        "created_at": ts(),
    }
    save_job(job)
    print(_json({"job_id": job_id, **spec}))
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    if args.job:
        job = load_job(args.job)
        if not job:
            print(_json({"error": f"작업 없음: {args.job}"}))
            return 1
        payload = {
            "id": job.get("id"),
            "status": job.get("status"),
            "spec": job.get("spec"),
            "transitions": job.get("transitions", [])[-6:],
        }
        print(_json(payload))
        return 0
    jobs = []
    if JOBS_DIR.exists():
        for path in sorted(JOBS_DIR.glob("*.json")):
            job = load_job(path.stem)
            if job:
                jobs.append({"id": job.get("id"), "status": job.get("status")})
    print(_json({"jobs": jobs}))
    return 0


def cmd_logs(args: argparse.Namespace) -> int:
    path = LOG_DIR / f"{args.job}.log"
    if not path.exists():
        print(f"로그 없음: {args.job}")
        return 1
    print(path.read_text(encoding="utf-8"), end="")
    return 0


def _terminate(pid: int) -> None:
    """PID 프로세스 종료 (graceful 후 강제)."""
    import subprocess as _sp
    _sp.run(["kill", str(pid)], check=False)
    import time as _t
    _t.sleep(0.5)
    try:
        _sp.run(["kill", "-0", str(pid)], check=True, capture_output=True)
        _sp.run(["kill", str(pid)], check=False)
    except Exception:
        pass


def cmd_stop(args: argparse.Namespace) -> int:
    """사용자 명시 요청 시 작업을 STOPPED로 전이하고, 실제 감시 루프도 종료한다."""
    from ._common import RUNS_DIR, is_running
    from .monitor import STOPPED
    job = load_job(args.job)
    if not job:
        print(_json({"error": f"작업 없음: {args.job}"}))
        return 1
    job["status"] = STOPPED
    job["stopped_at"] = ts()
    save_job(job)
    # tmux 세션 종료
    tmux_file = RUNS_DIR / f"{args.job}.tmux"
    if tmux_file.exists():
        session = tmux_file.read_text(encoding="utf-8").strip()
        run_capture(["bash", "-lc", f"tmux kill-session -t {session} 2>/dev/null"])
        # run 프로세스도 후속 정리
        run_capture(["bash", "-lc", f"pkill -f 'cartier_auto.py run --job {args.job}' 2>/dev/null"])
    # nohup/PID 파일 종료
    pid_file = RUNS_DIR / f"{args.job}.pid"
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text(encoding="utf-8").strip())
            if is_running(pid):
                _terminate(pid)
        except Exception:
            pass
    print(_json({"job": args.job, "status": STOPPED, "stopped": True}))
    return 0



def cmd_launch(args: argparse.Namespace) -> int:
    """백그라운드 감시 실행. tmux 있으면 전용 세션, 없으면 nohup+PID 파일."""
    job = load_job(args.job)
    if not job:
        print(_json({"error": f"작업 없음: {args.job}"}))
        return 1
    from ._common import RUNS_DIR, tmux_available
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    python = find_venv_python() or "python3"
    script = PROJECT_DIR / "scripts" / "cartier_auto.py"
    runner = [python, str(script), "run", "--job", args.job]
    logfile = LOG_DIR / f"{args.job}.log"
    if tmux_available():
        import os as _os
        import shlex
        session = f"cartier-auto-{args.job}"
        envs = []
        if _os.environ.get("CARTIER_AUTO_STATE"):
            envs.append(f"CARTIER_AUTO_STATE={shlex.quote(_os.environ['CARTIER_AUTO_STATE'])}")
        if _os.environ.get("CARTIER_AUTO_CREDENTIALS"):
            envs.append(f"CARTIER_AUTO_CREDENTIALS={shlex.quote(_os.environ['CARTIER_AUTO_CREDENTIALS'])}")
        env_prefix = (" ".join(envs) + " ") if envs else ""
        cmd = f"tmux kill-session -t {session} 2>/dev/null; tmux new-session -d -s {session} -x 220 -y 50 {env_prefix}{shlex.join(runner)} 2>&1"
        rc, _ = run_capture(["bash", "-lc", cmd])
        if rc == 0:
            (RUNS_DIR / f"{args.job}.tmux").write_text(session, encoding="utf-8")
            print(_json({"launched": True, "mode": "tmux", "session": session}))
            return 0
    import subprocess as _subprocess
    with open(logfile, "a", encoding="utf-8") as fh:
        proc = _subprocess.Popen(runner, stdout=fh, stderr=fh, start_new_session=True)
    (RUNS_DIR / f"{args.job}.pid").write_text(str(proc.pid), encoding="utf-8")
    print(_json({"launched": True, "mode": "nohup", "pid": proc.pid}))
    return 0


def chrome_user_agent() -> str:
    """시스템 Chrome의 실제 메이저 버전을 읽어 UA를 구성 (없으면 기본 Chrome UA)."""
    chrome = chrome_path()
    if chrome:
        rc, out = run_capture([chrome, "--version"], timeout=5)
        if rc == 0:
            for token in (out or "").split():
                token = token.strip(".")
                if token.isdigit() and len(token) >= 2:
                    return f"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{token}.0.0.0 Safari/537.36"
    return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"


def normalize_kst(text: str) -> str:
    return validate_run_at(text).isoformat(timespec="seconds")


def _sleep_interruptible(sec: float) -> None:
    import time as _time
    end = _time.time() + sec
    while _time.time() < end:
        _time.sleep(min(1.0, end - _time.time()))


def _job_log(job_id: str, msg: str) -> None:
    from ._common import log as _log
    _log(msg, job_id=job_id)


def cmd_run(args: argparse.Namespace) -> int:
    """감시 프로세스 본체: 예약 대기 → 예열 → 감시 → 결제 → COMPLETED."""
    from ._common import STATE_HOME, load_creds
    from .config import load_site_config
    from .monitor import FAILED, PREWARM, SCHEDULED, STOPPED, TransitionRecorder, parse_kst
    from .runner import guard_completed
    from .purchaser import BrowserFlow

    job = load_job(args.job)
    if not job:
        print(_json({"error": f"작업 없음: {args.job}"}))
        return 1
    recorder = TransitionRecorder(args.job)
    try:
        creds = load_creds()
        missing = [k for k in ("CARTIER_ID", "CARTIER_PASSWORD", "NAVER_ID", "NAVER_PASSWORD") if not creds.get(k)]
        if missing:
            raise RuntimeError(f"자격증명 누락: {', '.join(missing)}")
        config = load_site_config()
        run_at = parse_kst(job["spec"]["run_at"])
        lead = int(config["watch"].get("lead_time_sec", 300))
        sleep_sec = (run_at - now_kst()).total_seconds() - lead
        if sleep_sec > 0:
            _job_log(args.job, f"예약 시각 {run_at.isoformat()}까지 {sleep_sec:.0f}초 대기 (예열 {lead}초 전)")
            _sleep_interruptible(sleep_sec)
        job = load_job(args.job) or {}
        if job.get("status") not in (SCHEDULED, PREWARM):
            _job_log(args.job, f"작업 상태 {job.get('status')} — 실행하지 않음")
            return 0
        recorder.transition(PREWARM, "예약 시각 -5분, 예열 시작")
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=False, channel="chrome")
            state_path = STATE_HOME / f"session-{args.job}.json"
            context = browser.new_context(
                storage_state=str(state_path) if state_path.exists() else None,
                viewport={"width": 1440, "height": 900}, locale="ko-KR")
            flow = BrowserFlow(config, creds, job)
            flow.state_path = str(state_path)
            flow.warm(context)
            context.storage_state(path=str(state_path))
            order_id = flow.watch(context)
            if order_id:
                job = load_job(args.job) or {}
                guard_completed(job, order_id=order_id)
                _job_log(args.job, f"COMPLETED — 주문번호 {order_id}")
            browser.close()
        return 0
    except Exception as exc:
        job = load_job(args.job) or {}
        if job.get("status") not in (None, STOPPED):
            recorder.transition(FAILED, f"{exc}"[:300])
        _job_log(args.job, f"실패: {exc}")
        return 1


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "doctor":
        return cmd_doctor(args)
    if args.command == "setup":
        return cmd_setup(args)
    if args.command == "wishlist":
        return cmd_wishlist(args)
    if args.command == "schedule":
        return cmd_schedule(args)
    if args.command == "status":
        return cmd_status(args)
    if args.command == "launch":
        return cmd_launch(args)
    if args.command == "run":
        return cmd_run(args)
    if args.command == "logs":
        return cmd_logs(args)
    if args.command == "stop":
        return cmd_stop(args)
    parser.print_help()
    return 2




def cmd_setup(args: argparse.Namespace) -> int:
    """설치 상태 확인 → 미설치면 환경 체크 후 설치 진행 유도 / 설치 완료면 상태 보고.

    설치 완료 여부는 installed.json 에 저장되어 있어, 다시 setup을 호출하면
    미설치 시 설치 경로로, 설치 완료 시 상태 확인 경로로 분기한다.
    """
    inst = read_install_state()
    targets = install_targets()
    install_script = PROJECT_DIR / "scripts" / "install.sh"

    # 이미 설치 완료됨 → 상태 보고
    if inst.get("installed") and targets.get("exists"):
        print(_json({
            "installed": True,
            "version": inst.get("version"),
            "installed_at": inst.get("installed_at"),
            "env": inst.get("env", {}),
            "skill_dir": targets.get("skill_dir"),
            "codex": targets.get("codex_skill", {}).get("exists"),
            "claude": targets.get("claude_skill", {}).get("exists"),
            "command": targets.get("claude_command", {}).get("exists"),
            "bin": targets.get("bin", {}).get("exists"),
            "message": "설치 완료 상태입니다. 필요하면 doctor --json 으로 readiness를 확인하세요.",
        }))
        return 0

    # 미설치 → 환경 체크 후 설치 형태
    py_ok, py_ver, _ = check_python()
    chrome = chrome_path()
    payload = {
        "installed": False,
        "env_check": {
            "python": {"ok": py_ok, "version": py_ver or ""},
            "chrome": {"ok": bool(chrome), "path": chrome or ""},
        },
        "skill_dir": targets.get("skill_dir"),
        "install_script": str(install_script),
        "message": (
            "미설치 상태입니다. 설치하려면:\n"
            f"  bash {install_script}\n"
            "설치 완료 후 다시 setup 하면 설치 상태로 전환됩니다."
        ),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 2

