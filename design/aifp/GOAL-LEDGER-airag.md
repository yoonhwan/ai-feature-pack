# AIRAG completion goal ledger

## Goal

최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.

## Open units

| Unit | Closing evidence | State |
|---|---|---|
| H01 | 최신 fable-team 스킬·bin·파일 통신·버전 검증 | DONE |
| H02 | Opus 5.5 `[1m]` HELM 개설 및 6단계 승계 확인 | DONE |
| H03 | 뉴스·골 틱 및 seats 원장 연결 | DONE |
| A01 | 기존 테스트·투어·문서·운영 상태 재대조 보고서 | DONE |
| A02 | 미완료 작업 트리와 우선순위 확정 | DONE |
| A03 | Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프 | DOING |
| A04 | 사용자 투어와 실제 운영 검증 후 완료 판정 | BLOCKED_BY_A03 |

## Fixed decisions

- HELM은 Claude Code Opus 5.5 `[1m]`.
- Master와 Nano는 Claude Sonnet 5.5 `[1m]`.
- DA는 GPT-6.1 Sol.
- 첫 라운드는 하네스 복원과 증거 재대조이며 AIRAG 기능 코드는 수정하지 않는다.
- 기존 `ft-airag-arch-astra`와 최근 세션 계보를 보존한다.
- 삭제·브랜치 제거·DB 초기화·GPU 자원 종료는 별도 사용자 승인 없이는 수행하지 않는다.

## Next

A03 — A02 트리 1~4순위 DONE(HEAD 6f135ab · 투어 14 사용자 수용). 5순위(운영·백업 증거 + DA r6 잔존)를 Master가 조사·준비하고 운영 활성화는 사용자 승인 후 집행한다. (트리: .fable-team/state/airag/A02-work-tree.md)
