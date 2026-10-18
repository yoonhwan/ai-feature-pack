# DA — 판정 511 상태 칸 실측 · 팀 master 정지 감시 (사전검증 · r1)

- 요청: byz-harness-arch-claude#17 · 2026-10-08 · 발주 master#17 #64752(최우선)
- 설계: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/teams/harness/DESIGN-511-seat-stall-watch-20261008.md`
- 함께 볼 것: `~/.claude/skills/fable-team/references/main-team-governance.md`(§6·§7) · `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`(7·17) · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh`(turn) · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-planner/planner-idle-scan.sh` · 카드 `design/teams/harness/indices/대기/v421-board.md`
- 범위 고정: 설계 §6 Q1~Q4 만. 10분 + 10분 · HOLD 2회면 종료.
- 판정은 이 파일 맨 아래 「## r1 판정」 절에(모델·provider 두 줄).

## r1 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q1 HOLD — §4 상태 매핑이 실제 turn 계약을 모두 덮지 않습니다. 정본은 PENDING도 내보내고 jsonl 없으면 pane IDLE/turn_end=null/source=pane을 반환합니다(ft-seat-status.sh:164, :181-185, :193). IDLE이라는 이름만으로 분을 계산하거나 PENDING을 정지로 취급하면 지어낸 값/작업 대기 오판입니다. 시간 계산은 state=IDLE ∧ source=jsonl ∧ 유효한 TURN_END일 때만; null/깨진/미래 시간은 분 미상/확인 불가로 명시하고 PENDING 별도 표기·stalled 제외를 정하십시오. UNKNOWN/pane BUSY/NOSEAT도 관측대로 구분하는 fixture가 필요합니다.
- Q2 HOLD — mailbox.jsonl은 소비되는 현재 큐라 이전 발신과 읽힌 회신이 사라집니다(설계 §4). 현재 큐만으로 마지막 발신/회신 부재를 결론 내릴 수 없습니다. 로그/회전 기록과 큐를 seq로 중복 제거해 조회하고, 보존 범위 밖이면 «회신 여부 확인 불가»로 남기십시오. 단순 보고/알림도 회신 요청이 아닐 수 있으므로 출력은 «추정: B에 마지막 발신 #N · 기록상 이후 회신 없음»처럼 사실과 추정을 분리해야 합니다. 마지막 발신이 없거나 회신이 있다는 이유만으로 «발주 필요»를 확정할 수 없으며, HIL/외부 대기·완료/stop-ready를 구별한 뒤 master가 결정해야 합니다.
- Q3 APPROVE(기존 권한 경계 유지) — 실측 감시를 master/planner의 집행 역할에 더하는 것은 governance §6·§7과 충돌하지 않습니다. Escape는 IDLE/agent 실행 확인 뒤에만, 작업중에는 금지이며 끝난 nano 닫기는 기존 nano-close 경로/standing approval만 사용해야 합니다(BOOT 7·17, governance §7). 3분 규칙이 HIL·명시 대기·역할 좌석 종료 승인을 우회하는 근거는 아닙니다. 설계 자체도 작업중 Escape 금지를 유지합니다.
- Q4 APPROVE — 하드코딩 planner/팀 목록 및 날짜 없는 시계 파서를 키트로 승격하지 않고 v421 랜딩 뒤 정본 상태 조회로 대체하는 순서는 적정합니다. 기존 스캔의 출력은 교차 확인 보조로만 사용하고 실측 분 정본으로 간주하지 않는 경계를 유지하십시오. 삭제는 이번 승인/검토에서 집행하지 않았습니다.

§6 Q1~Q4 사전 검토만. 정본 지침 변경·설치·좌석 깨우기/닫기·실제 시험은 수행하지 않았습니다. 반송 범위는 turn의 실제 상태/시간/source 계약 및 회신 추정의 기록 범위·표시입니다.

HOLD

## r2 요청 (arch#17)
설계 `## §4-r2`(Q1-r2 turn 계약 8행 표·분 계산은 IDLE∧jsonl∧유효 turn_end 만 · Q2-r2 로그+회전본+큐 seq 중복 제거·기록 범위·사실/추정 분리·기계 결론 0 · §2 조항 교정본 · BOOT 18 경계 문구)로 r1 Q1·Q2 교정, Q3·Q4 조건 반영. 같은 Q1~Q4 범위로 아래 r2 판정 절에. (r2 HOLD 면 bounded 종료 → master 로)

## r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q1 APPROVE — §4-r2 Q1 표가 PENDING·pane IDLE/null·UNKNOWN·오류·stop-ready를 구분하며 정지 분/⚠는 IDLE∧jsonl∧유효한 과거 turn_end에서만 계산하도록 제한했습니다. r1 실제 계약 누락을 닫습니다.
- Q2 APPROVE — Q2-r2는 로그/회전본/현재 큐를 seq로 합치고 관측 범위를 명시하며 회신 부재·HIL을 추정으로 분리합니다. 기록 없음/오류는 확인 불가로, 발주 필요 같은 결론은 master 확인으로 남겨 r1 오도 사유를 닫습니다.
- Q3 APPROVE — 교정 조항의 HIL/외부 대기 확인 선택과 Escape/agent/IDLE/nano-close/기존 승인 경계를 수락합니다. 감시 시간이 기존 권한을 확대하지 않는다고 명시됐습니다.
- Q4 APPROVE — 대체 전 기존 스캔을 교차 확인 보조로만 사용하는 조건이 반영됐습니다. 승격 거부 및 별 카드/v421 랜딩 뒤 순서 수락 유지.

사전 설계 승인입니다. 상태 8행·회전 기록/승계·범위 밖·오류 fixture는 구현에서 검증해야 합니다. 이번 검토에서 정본 지침 설치·좌석 조작·실제 시험은 수행하지 않았습니다.

APPROVE
