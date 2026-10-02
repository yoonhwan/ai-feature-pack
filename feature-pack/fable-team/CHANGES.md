# Changes

## 2026-10-02 — 단일 세트 · 나노 생애 · 오래된 나노는 루트부터 (1.0.3)

BYZ-Agents v65 에서 09-25 카드를 재대조 없이 10-02 코드에 집행하고, 옛 sha worker 로 돌린 A/B 를 근거로 HEAD 를 덮어쓸 뻔했습니다(미랜딩 nano 277/590 · 나노 브랜치 221커밋 뒤처짐).

- **규칙**(`references/SEATBELT.md` §6-3): 단일 세트 시험 · 나노 생애 ①~⑤(최신 루트 병합→시험→이슈 확인→squash) · 랜딩 = 라이브 1회까지 · 방치 0.
- **스크립트** `scripts/ft-nano-freshness.sh`(읽기 전용): base·루트 뒤처짐·겹침 파일·미랜딩 패치·dirty → FRESH/STALE/STALE-OVERLAP/LANDED.

## 2026-10-02 — 워크트리 위생: Serena project.yml 커밋 금지

BYZ-Agents 의 모든 워크트리에서 Serena 가 `.serena/project.yml` 을 자동 갱신해 세션마다 modified 로 떴습니다.
추적 해제 + gitignore 를 BYZ 가 적용했고(4305b6925), 같은 규칙을 팩의 플레이북에 넣었습니다.

- **규칙**(`references/orchestration-playbook.md` «워크트리 위생»): project.yml 커밋 금지 · Serena 는 본인 워크트리 절대경로로 활성화.

## 2026-10-01 — checkpoint 계약: 시험·press 를 돌린 워커가 그 회차의 tester·checker

BYZ-Agents v65 에서 과금 랜딩이 폴리싱·완료 말풍선을 끊는 회귀를 냈는데, 측정 워커가 자기 측정 조건만 보고
6회차를 VALID 로 넘겼고 사용자가 화면을 보고 잡았습니다. 수정 범위가 넓고 시스템이 커서 «한 곳을 고치면 다른 곳이
끊기는» 일이 잦기 때문에, 랜딩마다 BTS 4축 + poller 고정 칸을 도구로 확인하는 계약을 팩에 넣었습니다.

- **계약**(`references/SEATBELT.md` §6-2): 시험·press 를 돌린 워커 = 그 회차 tester·checker. 회차마다 프로젝트가 선언한
  checkpoint 를 돌려 고정 칸 표를 보고에 첨부 · 경보(exit 3)면 VALID/완료 보고 금지 → 4축 정리 → arch(+DA) 처방 →
  같은 워커 수정 → 재실행.
- **도구**(`scripts/ft-checkpoint.sh`): 프로젝트 `.fable-team/checkpoint.json`(명령·경보 exit·필수 칸)을 실행 ·
  exit 0 정상 / 3 경보 / 4 표·칸·명령 실패 / 5 미설정(무음 통과 금지).
- **닫기 조건**(`scripts/ft-nano-close.sh` ④): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no. 미설정 프로젝트는 경고만.
- **적용**(`references/update.md`): 프로젝트별 checkpoint.json 예시 3줄.

## 2026-09-30 — 승계 6단계 + 지시 원장 트리 + 누락 전수 점검

사용자 지시(BYZ-Agents v65 master#86 작업 방법 공유)를 베이스에 반영했습니다. 승계 때 후계에 상태·할 일이
안 넘어가고, 범위 한정으로 닫힌 행 아래의 사용자 지시가 통째로 누락되던 문제(16건 중 8건)에 대한 규율입니다.

- **승계 6단계**: 스냅샷 커밋 → 후계 스폰 → 상태·할 일·컨텍스트 요약 mbox 재송신 → 후계 응답(골 대조) recv →
  뉴스·크론이 후계로 가는지 확인 → 구 좌석 유휴. 후계 발주문에도 6단계를 적습니다.
- **트리 = 골 원장 행 + 사용자 지시 원장 열린 항목**: 행을 범위 한정으로 닫을 땐 하위 지시 항목의 완성 전/후 이관 줄 필수.
- **승계 첫 일 누락 전수 점검**: 지시 × 카드 × 닫힘 sha 대조, «카드 없음 + 증거 없음» 맨 위.
- **설명은 사용자가 겪는 일로**, **아키텍처 영향 사건은 즉시 아키텍처 원장에 기록**.

반영 위치: `skill/SKILL.md`(운영 규율 5~7), `skill/templates/rules/orchestration.md`(컨텍스트 증류 절 — 프로젝트로 복사되는 정본),
`skill/references/context-management.md`(§2.5 승계 6단계).

## 2026-07-28 — 문제해결 표준 체인 + checker 4축 실측 규칙

역할 경계를 두 군데 조였습니다. 출처는 BYZ-Agents v6-realtime-live 커밋 `2216ffdc`(FB_Master#88 규율 업데이트).

- **문제해결 표준 체인**: `checker → 오케(Master) → architect → (DA) → 오케(Master) → impl`.
  checker는 실측·정리만 하고 판정을 붙이지 않습니다. 오케(Master)는 checker 정리에 의심 방향을 얹어
  architect에 넘기되 **그것이 관찰이지 판정이 아님을 명시**합니다. 원인 규명·설계 판정은 architect가
  하고 **DA 소환 여부도 architect가 정합니다**(DA는 architect에 회신). 최종본 라우팅은 다시 Master.
  - 오케(Master)가 **하지 않는 것 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환.
  - **DA 상시 대기 금지** — `DA approve loop` / `DA review`로 필요할 때만. 대기 유지 자체가 왕복과
    조건 증식을 만듭니다(실증: 조건 7항 증식 → 라이브 지연).
- **checker 4축 실측**: FE 콘솔 / poller·DOM / worker(서버 로그) / durable 저장소를 전부 봅니다.
  FE 미확인 전 "처리 실패" 판정 금지, poller·DOM 미확인 전 "출력 없음" 판정 금지, 복수 호출은 전부
  나열하고 실패 지표가 몇 번째인지 명시. **사용자가 눈으로 본 것과 분석이 어긋나면 분석이 틀린 것**
  — 그때는 안 본 축부터 봅니다.

반영 위치: `skill/SKILL.md`, `skill/references/rapid-iteration-loop.md`(정본 — 역할 체인·4축·안티패턴 11~13),
`skill/templates/rules/orchestration.md`, `skill/templates/session-prompts/{checker,architect,da-codex,da-cursor}.md`,
`skill/references/agent-templates/{ft-checker,ft-architect,ft-da,ft-da-cursor,ft-da-claude}.md.tpl`.

## 2026-07-11 — v3 업그레이드 (tmux 기반 전면 개편)

fable-team이 각 에이전트를 tmux 세션으로 직접 띄우고, 서로 메시지를 주고받고, 작업이 끝나면 스스로
정리하도록 구조를 전면 교체했습니다. 여기에 더해 세션 압축(증류) 시 모델의 확장 컨텍스트(1M)/추론
강도 설정이 유실되던 문제 수정, 전문가(fable-5) 브레인의 전체 구현 재검토, 대규모 동작 검증(23개
시나리오) 중 실측으로 발견한 버그 다수를 함께 처리했습니다.

- 요약 문서: [docs/artifact/2026-07-11-v3-upgrade-summary.html](docs/artifact/2026-07-11-v3-upgrade-summary.html)
- 설계 원문: [.fable-team/designs/roster-v3-design.md](.fable-team/designs/roster-v3-design.md)
- 구현 전체 검토 보고서: [.fable-team/state/v3-upgrade-design/implementation-review-fable5.md](.fable-team/state/v3-upgrade-design/implementation-review-fable5.md)
- 진행 원장(전 과정 기록): [.fable-team/state/state.md](.fable-team/state/state.md)
