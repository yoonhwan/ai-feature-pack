# fable-team 모니터링·지원 체크 루프

오케스트레이터는 워커를 스폰하고 **방치하지 않는다**. 파이프라인이 도는 동안 아래 루프가 상시 가동돼야 하며, 목적은 두 가지다: ① 멈춤/실패를 즉시 감지 (보고 공백 방지) ② 워커가 **산으로 가지 않도록** 조기 교정.

## 1. 감시 채널 3종 (전부 병행)

| 채널 | 대상 | 방법 |
|------|------|------|
| Monitor 폴링 | Agent 경로 워커 | `subagents/agent-a<name>-*.jsonl`을 5초 간격 grep — 완료 마커 **와 `API Error` 문자열을 함께** 감시 (조용한 실패 방지). Monitor는 완료 시 자동 통지 |
| idle_notification | 팀 워커 전체 | 워커가 idle/failed로 전환되면 teammate-message로 자동 수신 — `idleReason: failed`의 `failureReason`을 즉시 원장에 기록 |
| task-notification | Workflow 워커 | 완료/실패 자동 통지 + `journal.jsonl`로 반환값 검증. **주의: 세션 내 백그라운드는 사용자 개입(ESC·메시지)에 동반 사망** — 개입이 잦은 구간의 장시간 워커는 미들웨어 드라이버 경로(아래 행) 사용 |
| 미들웨어 드라이버 릴레이 | 외부 CLI 실행 전부(claude -p·codex·omx) | **드라이버 서브에이전트(Agent 도구, 세션 우측 pane 가시)가 Bash로 CLI 실행 → SendMessage 즉시 릴레이**(저유실 채널). 자식 CLI 프로세스는 드라이버가 `kill -0 <PID>` + 출력 파일 mtime/크기로 감시 — 별도 OS 프로세스라 개입 내성 유지, 드라이버 사망 시에도 출력 파일 낙수로 재회수 (SKILL.md 스폰 경로 3행) |

## 2. 진로이탈(산으로 가는) 감지 — 지원 체크 루프

장시간 워커(구현·테스트)는 **중간 체크포인트**를 계약에 넣는다:

- 스폰 프롬프트에 명시: "N분 경과 또는 파일 M개 변경 시점에 SendMessage로 team-lead에게 1줄 중간보고(현재 단계 + 다음 행동)".
- 오케스트레이터는 중간보고를 받으면 **범위 검사만** 한다 (내용 판단 금지 — 그건 planner 몫):
  - ✅ 보고가 구현 SSOT(표준 형상: design-*.md, 축약 형상: features/<slug>.md)의 구현 노트 범위 안 → "CONTINUE" 회신.
  - ⚠️ 범위 밖 파일 변경/추측 확장/설계에 없는 결정 언급 → **즉시 교정**: "STOP — 설계 §X로 복귀. 설계 변경이 필요하면 근거를 보고하라. 직접 결정 금지."
  - 설계 자체가 틀렸다는 근거가 오면 → planner에 재기획 라운드 (planner_rounds만 소모, da_round 불변 — 설계 버전 축과 DA 라운드 축은 독립. 오케스트레이터가 판단하지 않는다).
- 워커 transcript에서 진로이탈 신호 grep: 설계에 없는 파일 경로의 Write/Edit, `rm -rf`/`git push` 류 위험 명령, 동일 도구 호출 5회+ 반복(루프 징후).

## 3. 멈춤 판정과 조치

- Agent 경로: jsonl 파일 mtime이 90초+ 무변화 && 완료 마커 없음 → 1차 SendMessage 독려("진행 상황 1줄 보고"). 60초 내 무응답 → TaskStop 후 재스폰 (같은 컨텍스트 노트 재사용 — 파일 경유라 손실 없음).
- Workflow 경로: task-notification이 오지 않으면 `journal.jsonl`·`agent-*.jsonl` 직접 Read로 확인. hang이면 TaskStop → `resumeFromRunId`로 재개.
- **모든 실패/멈춤/교정은 사용자에게 다음 보고 시점에 원장 형식으로 투명 공개** (감춘 실패 = 보고 공백).

## 4. 상태 원장 (오케스트레이터 유지 의무)

파이프라인 중 오케스트레이터는 워커 원장을 유지한다. **원장은 컨텍스트가 아니라 디스크(`.fable-team/state/<slug>.state.md`)가 SSOT** — 자동 컴팩션/세션 재시작/증류에 원장이 증발하지 않도록, 아래 원장을 다음 4개 이벤트마다 **디스크에 write-through**한다: ① 단계 전이(ACTIVE 생성·제거 포함) ② 게이트/검증 디스패치·판정 수신 ③ 워커 상태 변화(중간보고·STOP 교정 포함) ④ 에스컬레이션/블록. 스펙·복원 절차는 `context-management.md` 참조:

```
| 워커 | 경로 | 상태 | 마지막 신호 | 조치 |
|------|------|------|-------------|------|
| impl-02 | Agent | 🟢 작업중 | 13:35 IMPLEMENTED | — |
| tester(wf) | Workflow | ✅ ALL_PASS | 13:24 | — |
| da2-01 | Agent | 🔴 failed(400) | 13:31 | Workflow로 대체 완료 |
```

## 5. 라운드 한도 (전역)

- DA approve loop 최대 라운드(기본 2) + **동일 워커 재스폰 최대 2회(failure 사유만 — WINDOW_PRESSURE 등 계획적 재스폰은 한도 비소모)** + planner 재기획 최대 2회.
- 어느 하나라도 초과 → 자동 진행 금지, 원장과 함께 사용자 에스컬레이션. "멈추지 않는 루프"는 **한도 안에서만** 자율이다.
- 라운드 소모 판정은 카운터 산술이 아니라 파일 실재 기준(context-management §1 라운드 디스패치 규칙) — 열린 라운드(산출물 부재) 재디스패치는 한도 비소모.
