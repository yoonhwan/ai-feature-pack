"""R218 — 자원 문지기(ft-resource-gate.sh)를 부르는 시험용 «가짜 센서» 공통 헬퍼 (셸 판 = tests/harness/lib/fake_resource_env.sh).

문지기 코드는 진짜로 돌고 «값»만 대역이다(우회 플래그 아님). 실 측정·실 RESOURCE_FREEZE·실 tmux 0.
ok = 압력 1·메모리 51%·스왑 6133MiB·에이전트 35 · reject = 압력 4·에이전트 99(문지기가 반드시 막는 값).
pgrep 은 `-a -x claude`/`-a -x codex` 만 가짜 수로 답하고 그 밖의 인자는 /usr/bin/pgrep 으로 넘긴다.
"""
import os
import stat
import time
from pathlib import Path

LEVEL = {"ok": 1, "reject": 4}
THRESHOLD_VARS = tuple("FT_AGENT_MAX FT_DISK_MIN_GIB FT_MEM_FREE_MIN_PCT FT_MEM_FREE_MIN_SUCC FT_PRESSURE_MAX FT_PRESSURE_MAX_SUCC FT_SWAP_HARD_MIB FT_SWAP_MAX_MIB FT_SWAP_RATE_MAX FT_SWAP_RATE_MAX_SUCC".split())  # 문지기 문턱 env 10개 — 호출자 값을 물려받지 않게 지운다
AGENTS = {"ok": 35, "reject": 99}

SENSORS = {
    "sysctl": (
        '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 6133.00M  free = 1000.00M  (encrypted)";;\n'
        + '  kern.memorystatus_vm_pressure_level) echo {level};;\n  *) exit 1;;\nesac\n'
    ),
    "memory_pressure": '#!/bin/sh\necho "System-wide memory free percentage: 51%"\n',
    "vm_stat": '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n',
    "df": '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1% /System/Volumes/Data"\n',
    "pgrep": '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 {last}; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n',
}


def fake_resource_env(tmp: Path, mode: str = "ok", base: dict[str, str] | None = None) -> dict[str, str]:
    """tmp 아래에 가짜 센서·임시 FT_RES_ROOT 를 만들고, 그것이 걸린 env dict 를 돌려준다(base 기본 = os.environ)."""
    if mode not in LEVEL:
        raise ValueError(f"mode={mode!r} — ok|reject")
    sensors = tmp / "fake-sensors"
    res_root = tmp / "resroot"
    sensors.mkdir(parents=True, exist_ok=True)
    (res_root / ".fable-team/state").mkdir(parents=True, exist_ok=True)
    for name, body in SENSORS.items():
        path = sensors / name
        _ = path.write_text(body.replace("{level}", str(LEVEL[mode])).replace("{last}", str(100 + AGENTS[mode])))
        path.chmod(path.stat().st_mode | stat.S_IEXEC)
    now = int(time.time())  # 신선한 표본 2줄(스왑 증가 0) — 샘플러 없이도 문지기가 통과한다
    rows = "".join(f"{t}\t6133\t51\t{LEVEL[mode]}\t2303978\n" for t in (now - 60, now))
    _ = (res_root / ".fable-team/state/pressure.tsv").write_text(rows)
    env = dict(os.environ if base is None else base)
    for var in THRESHOLD_VARS:
        _ = env.pop(var, None)
    env["PATH"] = f"{sensors}{os.pathsep}{env.get('PATH', '')}"
    env["FT_RES_ROOT"] = str(res_root)
    return env
