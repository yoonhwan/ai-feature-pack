#!/usr/bin/env python3
"""ft 2.0 설치 — install·verify·rollback·status 네 동사 하나. 설치 루트 꼴: `<루트>/versions/<버전>/`(패키지 복사본) · `<루트>/CURRENT`(일반 파일 1줄 · tmp 쓰고 os.replace) · `<루트>/install-log.jsonl`(한 줄 = {ts, op, version, prev, manifest_sha256, rc}). 판 전환은 PACKAGE.json manifest_sha256 = MANIFEST.json 바이트 sha · 숨은 파일 0 · MANIFEST 대조 rc0 일 때만 한다. 대조가 틀리면 CURRENT 를 건드리지 않고 복사본을 `<버전>.bad-<ts>` 로 rename 만 한다(지우기 0 · 하드 룰 2·19). 되돌림은 log 의 `prev` 로 가고, 그 판이 없거나 대조가 틀리면 rc2 이며 CURRENT 는 그대로다. 종료 코드: 0 = 됨/같음 · 1 = 대조 다름(전환 0) · 3 = 판 바뀜·상주 라벨 재기동 확인 못 함(r1826) · 2 = 판정 불가(인자·손상·이미 있음·쓰기 실패) — traceback 0.
"""
import contextlib
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest  # noqa: E402 — r1631 의 verify·skip_entry 만 쓴다

SCHEMA, META = 1, ("MANIFEST.json", "PACKAGE.json")


def read(path, as_json=False):
    try:
        text = open(path, encoding="utf-8").read()
        return json.loads(text) if as_json else text
    except (OSError, ValueError):
        return None


def state(root):
    """(CURRENT 판, versions 폴더 이름들, log 줄들) — 없으면 None·[]·[]."""
    versioned = sorted(os.listdir(os.path.join(root, "versions"))) if os.path.isdir(os.path.join(root, "versions")) else []
    docs = []
    for line in (read(os.path.join(root, "install-log.jsonl")) or "").splitlines():
        try:
            docs += [json.loads(line)]
        except ValueError:
            continue
    return (read(os.path.join(root, "CURRENT")) or "").strip() or None, versioned, [doc for doc in docs if isinstance(doc, dict)]


def set_current(root, version):
    tmp = os.path.join(root, "CURRENT.tmp")
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(version + "\n")
    os.replace(tmp, os.path.join(root, "CURRENT"))  # 심링크 0 · 일반 파일


def log_write(root, op, version, prev, man_sha, rc):
    line = {"ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "op": op, "version": version, "prev": prev, "manifest_sha256": man_sha, "rc": rc}
    with open(os.path.join(root, "install-log.jsonl"), "a", encoding="utf-8") as handle:
        handle.write(json.dumps(line, ensure_ascii=False) + "\n")


def _call(name, args, timeout=7):
    """외부 명령 1회 7초 + 재시도 1 → (rc, stdout) · 두 번 다 실패면 None(하드 룰 12·20) · FT2_LAUNCHCTL·FT2_PS = 대역 · 판정기 = 30초(안에서 25초 상한)."""
    for _ in range(2):
        with contextlib.suppress(OSError, subprocess.TimeoutExpired):
            proc = subprocess.run([os.environ.get("FT2_" + name.upper(), name), *args], capture_output=True, text=True, timeout=timeout, env={**os.environ, "LC_ALL": "C"})
            return proc.returncode, proc.stdout


def _pid(label):  # 등록 안 됨 = "" · 멈춤 = "-" · 판독 불가 = None · 아니면 pid 글자
    got = _call("launchctl", ["print", f"gui/{os.getuid()}/{label}"])
    return None if got is None or got[0] not in (0, 113) else "" if got[0] else next((ln.split("=")[1].strip() for ln in got[1].splitlines() if ln.strip().startswith("pid =")), "-")


def _started(pid):  # ps 기동 시각(지역 시각 · 초) → epoch 초 · 판독 불가 = None
    got = _call("ps", ["-o", "lstart=", "-p", pid]) or (1, "")
    with contextlib.suppress(ValueError):
        return int(time.mktime(time.strptime(" ".join(got[1].split()), "%a %b %d %H:%M:%S %Y"))) if got[0] == 0 else None


def switched(root, rc, out):
    """R1·R2(r1826) — 판 전환 뒤 이 루트를 부르는 com.byz.ft2-* 중 KeepAlive true 만 kickstart -k 1회 · 확인 못 하면 rc3(판은 그대로 둔다)."""
    agents, since, lines = os.environ.get("FT2_LAUNCH_AGENTS", os.path.expanduser("~/Library/LaunchAgents")), int(os.stat(os.path.join(root, "CURRENT")).st_mtime), [out]
    for name in sorted(n for n in (os.listdir(agents) if os.path.isdir(agents) else []) if n.startswith("com.byz.ft2-") and n.endswith(".plist")):
        doc = {"Label": name, "ProgramArguments": [root], "KeepAlive": True, "bad": 1}  # plist 판독 실패 = 판정 불가 줄(숨김 0)
        with contextlib.suppress(OSError, ValueError):
            doc = plistlib.load(open(os.path.join(agents, name), "rb"))
        label, alive = doc.get("Label", name), doc.get("KeepAlive") is True
        if os.path.realpath(root) in {os.path.realpath(str(arg)) for arg in doc.get("ProgramArguments") or []}:  # 다른 설치 루트 라벨 = 손 0
            old = _pid(label) if alive and "bad" not in doc else None
            new = (_pid(label) or "") if (kick := old and _call("launchctl", ["kickstart", "-k", f"gui/{os.getuid()}/{label}"])) and kick[0] == 0 else ""
            began = _started(new) if new.isdigit() and new != old else None
            why = "plist·launchctl 판독 실패" if old is None else "kickstart 실패" if not kick or kick[0] else "새 pid 없음" if not new.isdigit() else "pid 그대로" if new == old else "기동 시각 판독 실패" if began is None else "기동 < CURRENT" if began < since else ""
            lines.append(f"SKIP {label} 바퀴마다 새로 뜸" if not alive else f"SKIP {label} 등록 안 됨" if old == "" else f"RELOAD 판정 불가 {label} {why}" if why
                         else f"RELOADED {label} pid {old}→{new} 기동 {time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(began))} ≥ CURRENT {time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(since))}")
    return (3 if any(line.startswith("RELOAD 판정 불가") for line in lines) else rc), "\n".join(lines)


def hidden_files(root, known):
    """숨은·여분 파일 — __pycache__ 안 면제는 «파일» <이름>.cpython-*.pyc 이고 짝 <이름>.py 가 MANIFEST 에 있을 때뿐, 폴더는 늘 센다."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        prefix = "" if dirpath == root else os.path.relpath(dirpath, root).replace(os.sep, "/") + "/"
        cache = "__pycache__/" in prefix  # 어느 깊이든 __pycache__ 안이면 셈 대상
        found += [prefix + name for name in dirnames + filenames if name.startswith(".") or (cache and not (
            name in filenames and ".cpython-" in name and name.endswith(".pyc") and f"{prefix[:prefix.rindex('__pycache__/')]}{name.split('.')[0]}.py" in known)) or (
            name.endswith((".pyc", ".pyo")) and not cache)]
    return sorted(found)


def package_of(folder):
    """PACKAGE.json·MANIFEST.json 이 다 있고 칸이 맞으면 그 문서, 아니면 None."""
    doc = read(os.path.join(folder, "PACKAGE.json"), True)
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA or doc.get("name") != "ft2":
        return None
    version, files = doc.get("version"), doc.get("files")
    named = isinstance(version, str) and version and "/" not in version and version not in (".", "..")
    counted = bool(files) if isinstance(files, list) else type(files) is int and files >= 0  # r1613 은 개수(정수)
    shaped = named and counted and isinstance(doc.get("source"), dict) and isinstance(doc.get("manifest_sha256"), str)
    return doc if shaped and manifest.load_manifest(os.path.join(folder, "MANIFEST.json")) is not None else None


def consistent(folder):
    """폴더 하나가 제 MANIFEST·PACKAGE 와 맞는가 — (맞음, "") 아니면 (거짓, 이유)."""
    doc, man = package_of(folder), os.path.join(folder, "MANIFEST.json")
    if doc is None:
        return False, "PACKAGE.json·MANIFEST.json 칸이 없다"
    if hashlib.sha256(open(man, "rb").read()).hexdigest() != doc["manifest_sha256"]:
        return False, "MANIFEST.json 바이트 sha 가 PACKAGE.json 과 다르다"
    stray = hidden_files(folder, manifest.load_manifest(man) or {})
    if stray:
        return False, f"숨은 파일 {len(stray)}개 — 첫째 {stray[0]}"
    rc, out = manifest.verify(man, folder)
    wrong = ["MANIFEST 를 읽지 못했다"] if rc == 2 else out["missing"] + out["different"] + [rel for rel in out["extra"] if rel not in META]
    return (False, f"MANIFEST 대조 다름 — {wrong[:3]}") if wrong else (True, "")


def llm_gate(folder):
    """r1838 — CURRENT 전환·되돌림 «전» 새 판 폴더를 launchd LLM 0 판정기(1.x 팩 하나 · 사본 0)로 1회 → (rc, 줄) · 판정기 없음·실패 = 판정 불가(rc 3)."""
    data, here = os.environ.get("FT_ROOT", ""), os.path.dirname(os.path.abspath(__file__))
    state = lambda name: os.environ.get(f"FT2_LLM_GATE_{name.split('-')[1].upper()}") or (os.path.join(data, ".fable-team/state", name) if data else "")  # noqa: E731
    gate = next((p for p in (os.environ.get("FT2_LLM_GATE", ""), f"{here}/../../legacy/1.x/harness/bin/ft_launchd_llm_gate.py", f"{data}/.fable-team/bin/ft_launchd_llm_gate.py") if p and os.path.isfile(p)), "")
    got = gate and _call(sys.executable, [gate, "check", "--root-dir", folder, "--baseline", state("launchd-dyncall-baseline.tsv"), "--allow", state("launchd-llm-allow.tsv")], 30)
    return (got[0], got[1].strip()) if got else (3, f"UNDECIDABLE launchd-llm ft2-current 판정기 {'실행 실패' if gate else '없음'} {folder}")


def install(pkg, root):
    doc = package_of(pkg)
    if doc is None:
        return 2, f"판정 불가 {pkg}: PACKAGE.json·MANIFEST.json 칸이 없다"
    version, prev, target = doc["version"], state(root)[0], os.path.join(root, "versions", doc["version"])
    if os.path.exists(target):
        return 2, f"판정 불가 {version}: 이미 있음 — 덮어쓰기 0"
    os.makedirs(os.path.join(root, "versions"), exist_ok=True)
    shutil.copytree(pkg, target)
    ok, reason = consistent(target)
    if not ok:
        bad = os.path.join(root, "versions", f"{version}.bad-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}")
        os.replace(target, bad)
        log_write(root, "install", version, prev, doc["manifest_sha256"], 1)
        return 1, f"다름 {version}: {reason} — 전환 0 · {os.path.basename(bad)} 로 옮겼다"
    grc, gline = llm_gate(target)
    if grc:
        os.replace(target, os.path.join(root, "versions", f"{version}.llm-reject-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"))
        log_write(root, "install", version, prev, doc["manifest_sha256"], 1)
        return 1, f"{gline} — CURRENT 전환 0 · 복사본은 .llm-reject 로 옮겼다"
    set_current(root, version)
    log_write(root, "install", version, prev, doc["manifest_sha256"], 0)
    done = 0, f"설치 {version} (이전 {prev}) — 대조 맞음"
    return switched(root, *done) if prev != version else done


def rollback(root):
    cur, _versioned, lines = state(root)
    if cur is None:
        return 2, f"판정 불가 {root}: CURRENT 가 없다"
    prev = next((line.get("prev") for line in reversed(lines)
                 if (line.get("op"), line.get("rc"), line.get("version")) == ("install", 0, cur)), None)
    if not prev or prev == cur:
        return 2, f"판정 불가 {cur}: 직전 판이 없다"
    folder = os.path.join(root, "versions", prev)
    if not os.path.isdir(folder):
        return 2, f"판정 불가 {prev}: versions 폴더에 없다"
    ok, reason = consistent(folder)
    if not ok:
        log_write(root, "rollback", prev, cur, None, 2)
        return 2, f"판정 불가 {prev}: 직전 판 대조 실패 — {reason}"
    grc, gline = llm_gate(folder)
    if grc:
        log_write(root, "rollback", prev, cur, None, 1)
        return 1, f"{gline} — 되돌림 0 · CURRENT {cur} 그대로"
    set_current(root, prev)
    log_write(root, "rollback", prev, cur, package_of(folder)["manifest_sha256"], 0)
    return switched(root, 0, f"되돌림 {cur} → {prev}")


def verify_root(root):
    cur = state(root)[0]
    if cur is None:
        return 2, f"판정 불가 {root}: CURRENT 판이 없다"
    folder = os.path.join(root, "versions", cur)
    if not os.path.isdir(folder):
        return 2, f"판정 불가 {cur}: versions 폴더에 없다"
    ok, reason = consistent(folder)
    return (0, f"같음 {cur}") if ok else (1, f"다름 {cur}: {reason}")


def status(root):
    cur, versioned, lines = state(root)
    return 0, json.dumps({"current": cur, "versions": versioned, "last_op": lines[-1].get("op") if lines else None}, ensure_ascii=False)


def main(argv):
    verbs = {"install": (install, 2), "rollback": (rollback, 1), "verify": (verify_root, 1), "status": (status, 1)}
    verb, args = (argv[1] if len(argv) > 1 else ""), argv[2:]
    if verb not in verbs or len(args) != verbs[verb][1]:
        print("사용법: install.py install <패키지> <루트> | rollback <루트> | verify <루트> | status <루트>", file=sys.stderr)
        return 2
    try:
        rc, out = verbs[verb][0](*args)
    except OSError as exc:  # 루트 쓰기 실패 = 판정 불가 · traceback 0
        rc, out = 2, f"판정 불가 {exc.filename or exc}: 쓰거나 읽지 못했다"
    print(out, file=sys.stderr if rc == 2 else sys.stdout)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
