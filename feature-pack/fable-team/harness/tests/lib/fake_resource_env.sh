#!/usr/bin/env bash
# fake_resource_env.sh — 자원 문지기(ft-resource-gate.sh)를 부르는 시험용 «가짜 센서» 공통 헬퍼 (R218).
# 사용: source 한 뒤 `fake_resource_env <임시 폴더> [ok|reject]` — PATH 앞에 가짜 sysctl·vm_stat·memory_pressure·df·pgrep 을 두고
#   임시 FT_RES_ROOT 를 export 한다. 문지기 코드는 진짜로 돌고 «값»만 대역이다(우회 플래그 아님). 실 측정·실 RESOURCE_FREEZE·실 tmux 0.
# ok = 오늘 정상 범위(압력 1·메모리 51%·스왑 6133MiB·에이전트 35) · reject = 압력 4·에이전트 99(문지기가 반드시 막는 값).
# pgrep 은 `-a -x claude`/`-a -x codex` 만 가짜 수로 답하고 그 밖의 인자는 /usr/bin/pgrep 으로 넘긴다.
# 문지기 문턱 env 10개 — 호출자 셸 값을 물려받지 않게 전부 지운다(문지기 기본값으로 판정).
FAKE_RES_THRESHOLD_VARS="FT_AGENT_MAX FT_DISK_MIN_GIB FT_MEM_FREE_MIN_PCT FT_MEM_FREE_MIN_SUCC FT_PRESSURE_MAX FT_PRESSURE_MAX_SUCC FT_SWAP_HARD_MIB FT_SWAP_MAX_MIB FT_SWAP_RATE_MAX FT_SWAP_RATE_MAX_SUCC"
fake_resource_env() {
  local dir="$1" mode="${2:-ok}" s lvl agents
  case "$mode" in ok) lvl=1; agents=35;; reject) lvl=4; agents=99;; *) echo "fake_resource_env: mode=ok|reject" >&2; return 2;; esac
  s="$dir/fake-sensors"; FT_RES_ROOT="$dir/resroot"; mkdir -p "$s" "$FT_RES_ROOT/.fable-team/state"
  printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 6133.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo %s;;\n  *) exit 1;;\nesac\n' "$lvl" > "$s/sysctl"
  printf '#!/bin/sh\necho "System-wide memory free percentage: 51%%"\n' > "$s/memory_pressure"
  printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$s/vm_stat"
  printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$s/df"
  printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 %s; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' "$((100+agents))" > "$s/pgrep"
  chmod 755 "$s"/*
  # 신선한 표본 2줄(스왑 증가 0) — 문지기를 임시 bin 에 복사해 쓰는 시험도 샘플러 없이 통과한다
  local now; now="$(date +%s)"; printf '%s\t6133\t51\t%s\t2303978\n%s\t6133\t51\t%s\t2303978\n' "$((now-60))" "$lvl" "$now" "$lvl" > "$FT_RES_ROOT/.fable-team/state/pressure.tsv"
  # shellcheck disable=SC2086
  unset $FAKE_RES_THRESHOLD_VARS
  export FT_RES_ROOT PATH="$s:$PATH"
}
# fake_comm_root <임시 폴더> [LIVE_BIN 폴더] — r459·r383 뒤 도구가 «필수»로 찾는 공용 루트를 임시로 만든다 (r537 · r516 묶음 ③).
#   git init 리포 + .fable-team/comm · .fable-team/state · .fable-team/LIVE_BIN(기본 = 팩 harness/bin) · design/TEAMS.md 최소 명단(harness·planner·v65)
#   → FT_ROOT export(ft_comm_dir·ft_data_root 가 git 을 부르지 않고 이 루트로 푼다). 실 공용 루트·우편함 읽기·쓰기 0.
fake_comm_root() {
  local dir="$1" lb="${2:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../bin" && pwd)}"
  mkdir -p "$dir/.fable-team/comm" "$dir/.fable-team/state" "$dir/design"
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY git init -q "$dir" || return 1
  printf '%s\n' "$lb" > "$dir/.fable-team/LIVE_BIN"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$dir/design/TEAMS.md"
  FT_ROOT="$(cd -- "$dir" && pwd -P)"; export FT_ROOT
}
