골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰. consumer 가 macOS 권한 팝업/타임아웃으로 꺼져 있다. 이 DA 라운드는 architect 의 «원인 규명 프로브 + 해결안 비교» 설계 검토다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **PASS — blocker 0 / major 0 / minor 0**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2477 · 기준 HEAD `96d844db4068d1789effd0071476ca9c36ec8ca9`.
대상은 `feature-pack/rag/docs/artifacts/arch-20261015-opa-popup-design-r4.md` 1–252행이다. 아래 `설계:N`은 이 파일의 행 번호다. 재심은 `da-20261015-sol-opa-design-r3.md`의 M1·m1·m2와 r4 변경이 만든 결함에 한정했다. 이미 닫힌 항목과 운영 로그 집계는 다시 요구하거나 재측정하지 않았다.

## 1. 재심 3건 폐쇄

| r3 항목 | r4 근거 | 판정 |
|---|---|---|
| M1 무제한 파이프 회수 | 설계:151–165 — 직접 자식 kill 후 유한 wait, 남은 예산 안의 유한 파이프 회수, 시간 초과 시 읽기 끝 닫기, wait 확인 뒤에만 reaped, 미확인 상태 보고, 후손/공유 데몬 일괄 종료 금지, 합성 (k) | **종결**. 기존 반례 재현 후 새 계약으로 유한 반환 확인 |
| m1 skipped_not_applicable 목록 누락 | 설계:97,133,165(m) — 정식 9종에 추가, 스키마/소비자가 같은 목록 사용 | **종결**. 문서의 목록과 전이표가 일치 |
| m2 P1b 이전 unknown 조건 | 설계:110,113–114,125,165(l) — P0/P2/P1 모두 success AND none_logged_ok라는 단일 식, unknown 보존, 반례 결과 고정 | **종결**. 이전 unknown을 놓쳐 추가 실행하는 해석 여지 제거 |

r4의 새 회수 상태 불리언과 예산 합산, I-1 구현 DA 확인 항목(설계:67,133,153–165,221–222)을 함께 검토했고 이번 범위에서 추가 blocker/major/minor는 발견하지 않았다.

## 2. 합성 반례 재실행 증거

설치 런타임 `/Users/yoonhwan/.local/share/airag/runtime/bin/python -I -B`를 사용했다. 버전은 **3.13.12**다. 운영 op·토큰·launchd를 사용하지 않고 메모리 안의 합성 Python 코드로 직접 자식과 짧게 실행되는 후손을 만들었다. 자식 env는 PATH만 전달했고 원문 출력은 세션에 내보내지 않았다.

합성 자식은 후손을 만들어 stdout/stderr를 상속시킨 뒤 대기한다. 후손은 **0.8초 뒤 자연 종료**하며 출력 파이프를 유지한다. 축소 예산은 시도 0.12초, 직접 자식 wait 0.20초, 파이프 회수 0.12초다. 상한 단언에는 스케줄링 여유 0.16초를 더했다.

| 검증 | 실제 결과 |
|---|---|
| r3 반례 재현: 첫 timeout 뒤 직접 자식을 종료해도 후손이 파이프를 유지 | **재현** — 직접 자식 종료 뒤에도 두 번째 유한 communicate가 timeout. 후손 자연 종료 뒤 회수됨 |
| r4 방식: kill → wait(timeout) → 유한 communicate → 읽기 끝 닫기 | **PASS, 244ms**. 축소 상한 600ms 이내 반환, 직접 자식 returncode 확인·재수거 완료, 파이프 유지 상태 확인 |
| 후손 비종료 경계 | r4 반환 시 후손이 **살아 있음**을 PID 존재 조회로 확인. 후손에 신호를 보내지 않고 자연 종료까지 기다림 |
| 설치 POSIX subprocess.run timeout 경로 | **PASS, 123ms**. 후손이 살아 있는 동안 TimeoutExpired로 반환 |
| P1b 문서 조건의 unknown 조합 | P0/P2/P1 각각 none/unknown인 **8개 조합** 중 셋 모두 none일 때 **1개만 실행 가능**. 다른 7개는 보류 |
| 상태 목록 계약 | 9종이며 skipped_not_applicable 포함, 목록 밖 값 제외 확인 |

전체 합성 검증 스크립트 **rc=0**. 모든 직접 자식은 재수거했고, 짧은 후손은 자연 종료시켰다. 후손·공유 프로세스에 종료 신호를 보내지 않았다. 상태/조건 검증은 **문서 계약을 평가한 모델**이며 아직 없는 실제 프로브 스키마 검증기나 운영 실행을 시험했다고 주장하지 않는다.

추가로 설치 Python의 `subprocess.run` 소스를 읽어 설계:67의 설명을 확인했다. 해당 버전은 TimeoutExpired에서 직접 자식을 kill한 뒤, POSIX에서는 wait하고 예외를 다시 던진다. timeout 없는 두 번째 communicate는 Windows 분기다. 설치 런타임/플랫폼에 대한 확인이며 다른 플랫폼까지 확대하지 않는다.

## 3. PASS의 범위와 다음 게이트

이번 **PASS는 설계 r4의 재심 3건 폐쇄**다. I-1 구현, 프로브 전체, 합성 (a)~(m), 실제 계정 JSON 스키마, S2 또는 운영 회복을 통과시킨 판정은 아니다. 현행 30초 호출의 I-1 수정과 실제 코드의 유한 종료/회수는 구현 DA에서 확인해야 한다.

기존 단계 경계를 그대로 따른다. I-1은 Master의 구현 발주와 구현 DA로 진행하고, 운영 프로브 P는 실제 스크립트·합성 시험·구현 DA 뒤 HIL, 실제 키 읽기 S2는 별도 HIL이다. consumer는 서버 18712·18703 복구 통보와 HELM 재개 절차 전까지 disabled를 유지한다. 이 설계 PASS가 운영 op 실행이나 재개 승인을 대신하지 않는다.

이 회차의 산출은 본 판정 파일뿐이다. 운영 변경·토큰 내용 열람·op 실행·설치·DB 쓰기·커밋·push는 0이다.
