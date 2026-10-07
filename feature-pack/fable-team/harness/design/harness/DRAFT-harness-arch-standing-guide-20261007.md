# DRAFT — 하네스 기획 arch 상시 사용 지침 (byz-harness-arch-claude#5 안 · 2026-10-07 · 미커밋)

골 원문 3줄(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 안의 골 축: 원문 6-b(오케 요청을 사용자와 협의해 개선) — «master 단독 결정» 을 «arch 안 → master 집행» 으로 바꾼다.
출처(오빠 10-07): 「하네스에도 기획 arch 상시 사용 지침하고 랜딩」 · 「작업들 arch 검토 받고 결정 진행. 너가 독단으로 하지 말고」

---

## A. 정본 위치 (3곳 · 전역 CLAUDE.md 는 넣지 않는다)

| 곳 | 무엇 | 이유 |
|---|---|---|
| ①`~/.claude/skills/fable-team/references/main-team-governance.md` **§6** (새 절) | 아래 B 본문 | 팀 운영 정본은 이 파일이 이긴다(머리말). §5 는 인계문 열린 일 3번(gh 쓰기 래퍼)이 이미 예약 |
| ②`templates/session-prompts/architect.md` 머리에 3줄 + 스킬 키트 사본(`scripts/harness-install/fable-team/templates/session-prompts/architect.md`) 동일 반영 | 「메인 팀 상시 arch 이면 governance §6 을 먼저 Read」 | 부팅 때 읽히는 곳에 걸어야 읽힌다(하드 룰 7) |
| ③`design/harness/GUIDE-harness-master.md`(없으면 HANDOFF 템플릿) 1줄 | 「검토 대상이면 arch 안 없이 집행 0」 | master 쪽 강제점 |
| ✗ 전역 `~/.claude/CLAUDE.md` | 넣지 않는다 | 전 세션 상시 비용 · harness 팀에만 해당 · 정본 2곳이면 어긋난다 |

## B. governance §6 본문 안

```
## 6. 하네스 기획 arch 상시 좌석 (오빠 2026-10-07 「작업들 arch 검토 받고 결정 진행. 독단으로 하지 말고」)
- 좌석: byz-harness-arch-claude#N · 모델 Opus 5.5 high 상시 · Fable 5.1 은 에스컬레이션(같은 건 2회 수렴 실패·신규 구조 설계) 때만, 닫히면 Opus 5.5 로 복귀.
- 역할: arch = 설계·검토·판정 «안» · master = 집행(커밋·push·설치·좌석 개설/닫기·명부). arch 는 커밋·push·설치·좌석 조작을 하지 않는다(설계 초안 파일 Write 만, 커밋은 master).
- arch 검토 대상(안 없이 집행 0): ①설계·새 스크립트/훅 기능 ②가드·차단 훅(설치·등록 포함) ③설치·배포(홈 디렉터리·settings.json·~/.tmm·원격 머신) ④정본 변경(governance·COMM-GUIDE·BOOT·스킬 SKILL.md·전역/프로젝트 CLAUDE.md) ⑤좌석·모델·이름 규칙 변경 ⑥PR 랜딩 순서·되돌림.
- master 직접(검토 불요): 조회(seats·map·gh view) · 문서 오타 · 원장 행 추가(결정 내용 없는 기록) · 이미 arch 안이 승인한 범위 안의 집행 · 나노 생존 확인.
- ★집행 = 랜딩·커밋·push·검증된 파일의 설치 복사(cp+cmp)·.bak 복원·머지 충돌의 문서 줄 정리·좌석·명부 — 파일 «내용을 쓰는 것»은 집행이 아니다★. 코드는 나노, 설계·시안(HTML 포함)은 arch, 나노 증거 줄 REJECT 는 그 나노에 반송(닫혔으면 재spawn). arch 안이 있어도 master 가 손으로 쓰면 위반이다(오빠 10-07 「코드를 왜 너가 작업해?」 · 「독단으로 하지 말고」). 게이트가 안 막아도 같다.
- 흐름: master 발주(mbox · 골 원문 3줄 + 골 축 1줄) → arch 안(결론 1줄 · 판정 승인/수정/반려 · 이유 3줄 · 근거 경로 · 긴 것은 design/harness/ 초안 파일) → master 집행 → master 가 결과(sha·설치 위치·되돌림 명령)를 arch 에 통지 → arch 가 닫힘 확인 1줄.
- 사후 검토: 긴급(라이브 장애·권한 사고)으로 master 가 먼저 집행했으면 같은 턴에 arch 에 사후 검토 발주 + 되돌림 명령을 함께 적는다.
- 사람 판정: arch·master 모두 하위 좌석 — AskUserQuestion 금지. 오빠 값이 필요하면 [HIL] 로 현역 planner 에 올린다. 단 «하네스 내부 작업»(래퍼·가드 훅·설치)은 오빠 지시(10-07)로 인터뷰에 올리지 않는다 — arch 안 + master 집행으로 닫는다.
- 이름: §1 규칙 · 승계 때 번호 이어받음 · 발신 전 ft-harness-info.sh seats 로 현역 이름 확인.
```

## C. 검토 흐름 그림

```
master ──발주(mbox)──▶ arch ──안(mbox + 초안 파일)──▶ master ──집행──▶ 결과 통지 ──▶ arch 닫힘 1줄
                                   │
                                   └─ 오빠 값 필요(하네스 내부 아님) → [HIL] → planner 인터뷰 → 값 회신
```

## D. 미결(이 안이 정하지 않는 것)
- ③ 의 `GUIDE-harness-master.md` 가 리포에 없으면 새 파일 vs HANDOFF 템플릿 1줄 — master 판단.
- §6 을 governance 에 넣는 것 자체가 «정본 변경»이라 머리말 규칙상 오빠 값 1회가 필요한지: 오빠 원문 「기획 arch 상시 사용 지침하고 랜딩」 이 그 값이라고 본다(안).
