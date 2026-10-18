#!/bin/bash
# comm 정본/도구 드리프트 체커 (읽기 전용).
# 런타임(추적 밖) vs 백업(tools/comm-canonical/) 을 diff -q 로 비교만 한다.
# 조용히 덮지 않는다 — 복사·수정 기능 없음. 판단은 사람이 한다.
#
# 출력: 파일당 한 줄 — SAME / DRIFT / MISSING_RUNTIME / MISSING_BACKUP
# 종료: 전부 SAME 이면 0, DRIFT/MISSING 하나라도 있으면 1.

set -u

# 스크립트 위치에서 리포 루트 유도 (하드코딩 금지: tools/comm-canonical/ 의 두 단계 위).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKUP_DIR="${SCRIPT_DIR}"

# 14개 매핑: "<백업파일명>|<런타임 상대경로>"
#
# ★mbox.sh 를 뒤늦게 넣은 이유 (2026-09-03)★
#   최초 등록은 「정본 mbox.py + bin/ 도구 10」이었는데, 좌석이 실제로 «치는» 명령은
#   `bash .../comm/mbox.sh recv <me>` 다 — doorbell 주입 문자열도 이것이고, 억제 로직도
#   여기 산다. 그런데 이 파일은 v6 워크트리에만 있는 «일반 파일»이라 백업이 없었다.
#   ★그 워크트리를 정리하면 전 좌석의 mbox 진입점이 통째로 사라진다★ — mbox.py 가
#   살아 있어도 아무도 그걸 부르지 못한다. 도구 10개보다 이쪽이 더 치명적이다.
MAP=(
  "mbox.py|.claude/fable-team/bin/mbox.py"
  "mbox_conf.py|.claude/fable-team/bin/mbox_conf.py"
  "mbox_store.py|.claude/fable-team/bin/mbox_store.py"
  "mbox_guard.py|.claude/fable-team/bin/mbox_guard.py"
  "mbox_ops.py|.claude/fable-team/bin/mbox_ops.py"
  # ★mbox_lineage.py = mbox_ops.py 가 import 함 — 한쪽만 깔리면 recv ImportError 로 전 좌석 수신 정지 · 감시 밖이면 무증상 (P1 r-recv-lineage · 2026-10-12)★
  "mbox_lineage.py|.claude/fable-team/bin/mbox_lineage.py"
  # v6-realtime-live 워크트리 소멸 뒤 라이브 = 루트 .fable-team/comm — 분리 쌍만 고침, 나머지 행은 별 카드
  "mbox.sh|.fable-team/comm/mbox.sh"
  "mbox_doorbell.sh|.fable-team/comm/mbox_doorbell.sh"
  # ★ft-agent-alive.sh = mbox_doorbell.sh 가 source 하는 판정기(전경 셸·정지 본체 = NOAGENT) + 틱·seat-live CLI (R346) — 한쪽만 깔리면 doorbell 이 «판정 불가»(주입 0) · 틱은 발사 0 — 설치 전엔 MISSING_RUNTIME(master 라이브 설치 cp 뒤 SAME)★
  "ft-agent-alive.sh|.fable-team/comm/ft-agent-alive.sh"
  # ★ft_seat_bind.py = 좌석 pane 소유 결속 판정기(R364) — comm 쪽 소비자(ft-agent-alive 본체 후보 · 2단계)가 «같은 폴더» 고정 경로로 부른다 · 설치 전엔 MISSING_RUNTIME★
  "ft_seat_bind.py|.fable-team/comm/ft_seat_bind.py"
  # ★mbox_guard.sh = mbox.sh 가 source 함 — 한쪽만 깔리면 전 좌석 send 정지(set -e) · 감시 밖이면 무증상 (N3 · 2026-10-12)★
  "mbox_guard.sh|.fable-team/comm/mbox_guard.sh"
  # ★mbox_guard_goal.sh = mbox_guard.sh 가 source 하는 문 ③ 골 표 게재(R362) — 한쪽만 깔리면 WARN 만 남고 문이 열린다 · 감시 밖이면 무증상★
  "mbox_guard_goal.sh|.fable-team/comm/mbox_guard_goal.sh"
  # ★mbox_guard_lib.sh = 두 문이 판정기 폴더를 찾는 공용 함수 _ft_live_bin(R372) — 없으면 판정기 해석 실패로 fail-closed REJECT★
  "mbox_guard_lib.sh|.fable-team/comm/mbox_guard_lib.sh"
  # ★ft-goal-table.sh·ft_goal_table.py = 문 ③ 이 부르는 판정기(R362 · 라이브 bin) — LIVE_BIN 쪽은 ft-live-install-check 가 본다★
  # ★ft-boot-report-lint.py = mbox_guard.sh 가 부팅 보고 때 부르는 lint (P4 · 2026-10-12) — 감시 밖이면 한쪽만 깔려도 무증상★
  "ft-boot-report-lint.py|.claude/fable-team/bin/ft-boot-report-lint.py"
  # ★ft-fp-run.sh = 훅 오탐 «기록+허용» 래퍼 (R105-a · 2026-10-17) — 설치 전엔 MISSING_RUNTIME(master 라이브 설치 cp 뒤 SAME)★
  "ft-fp-run.sh|.fable-team/bin/ft-fp-run.sh"
  "ft-broadcast.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-broadcast.sh"
  "ft-claude-context.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-claude-context.sh"
  "ft-context-monitor.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-context-monitor.sh"
  "ft-master-tick.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-master-tick.sh"
  "ft-pm-tick.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-pm-tick.sh"
  "ft-reach-check.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-reach-check.sh"
  "ft-seat-status.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh"
  "ft-send-verified.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-send-verified.sh"
  "ft-wall-check.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-check.sh"
  "ft-wall-read.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-read.sh"
  # ★loom 워크트리의 ft-mbox.sh 2종을 뒤늦게 넣은 이유 (2026-09-06)★
  #   감시 목록에서 빠진 파일은 다음 드리프트를 ★조용히 통과★ 시킨다 — 체커가 초록인데
  #   그 파일만 갈려 있는 상태가 무증상으로 남는다. mbox.sh 를 넣었던 이유와 같은 계열이다.
  #
  # ★백업 «이름»을 구분한 이유★: 둘 다 basename 이 `ft-mbox.sh` 로 같다. 같은 이름을 쓰면
  #   백업 파일 하나를 두 런타임이 공유하게 되어, 뒤엣것이 앞엣것을 덮고 ★둘 다 못 믿게★ 된다
  #   (한쪽은 항상 SAME, 다른 쪽은 항상 DRIFT 로 보인다). 그래서 워크트리명을 이름에 박는다.
  #
  # ★이 둘의 «상류»는 팩(ai-feature-pack) 의 ft-mbox.sh 다★ — 여기 백업은 «현재 런타임을
  #   그대로 뜬 사본» 일 뿐 정본이 아니다. ⇒ 팩이 바뀌어 런타임이 갱신되면 ★여기 백업도
  #   같이 갱신해야★ DRIFT 가 안 뜬다. (2026-09-06 실측: loom 2종과 팩 ft-mbox.sh 는 동일.)
  "ft-mbox.loom-domain-hierarchy.sh|.worktrees/loom-domain-hierarchy/.fable-team/bin/ft-mbox.sh"
  "ft-mbox.loom-pack-layer.sh|.worktrees/feat/loom-pack-layer/.fable-team/bin/ft-mbox.sh"
)

rc=0
for entry in "${MAP[@]}"; do
  name="${entry%%|*}"
  rel="${entry#*|}"
  runtime="${ROOT}/${rel}"
  backup="${BACKUP_DIR}/${name}"

  if [ ! -f "$runtime" ]; then
    echo "MISSING_RUNTIME  ${name}  (${rel})"
    rc=1
    continue
  fi
  if [ ! -f "$backup" ]; then
    echo "MISSING_BACKUP   ${name}"
    rc=1
    continue
  fi
  if diff -q "$runtime" "$backup" >/dev/null 2>&1; then
    echo "SAME             ${name}"
  else
    echo "DRIFT            ${name}  (${rel})"
    rc=1
  fi
done

exit $rc
