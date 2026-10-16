실행 헤더(raw 인용): model: gpt-6.1-sol · provider: headroom · codex exec 1회성 · 정독 전용 · 2026-10-17

골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

**최종 REJECT — blocker 0 / major 2 / minor 0 / note 1.**

대상: `git diff c32e726..94f9bb4`. 원문→정오표 1→2→3과 DA 1~4차의 수용·종결 사항을 적용했다. 아래 반례는 코드 정독에 따른 판단이며 실행 결과가 아니다.

**M1 · major — 설정 읽기 실패를 허용하면 `running` 없는 pass가 실행될 수 있다.**

근거: [_pass_gate.py:276](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_gate.py:276)은 `RuntimeConfig.load`의 모든 `Exception`을 잡고, 거부도 프로젝트 식별자도 없는 `Gate()`를 반환한다. [_pass_child.py:91](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_child.py:91)은 이를 실행 허용으로 처리한다. 이후 [cli.py:96](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/cli.py:96)이 설정을 다시 읽는다.

가능한 경로:

1. 이전의 유효한 `clean`이 남아 있다.
2. 게이트의 첫 설정 읽기가 일시적인 파일 접근 오류 등으로 실패한다.
3. CLI의 두 번째 읽기는 성공하여 업무를 실행한다. 점검과 `running` 기록은 모두 없었다.
4. 업무 도중 프로세스가 강제 종료되면 이전 `clean`이 남아 다음 틱도 점검을 생략한다.

이는 [정오표2:31](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata2.md:31)의 **“안전한 `running` 기록 없이는 pass를 시작하지 않는다”**를 위반한다. 이미 종결된 설계를 재개방하는 지적이 아니라 구현이 만든 우회 경로다.

종결 조건: 설정 읽기 실패를 업무 실행 허용으로 바꾸지 않고, 실제 업무가 시작되는 모든 경로에서 유효한 게이트와 `running` 기록을 선행시킨다.

**M2 · major — DB별 마감 중단이 `deadline` 대신 손상 판정으로 기록된다.**

근거: [_pass_gate.py:157](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_gate.py:157)의 진행 핸들러는 DB별 마감 뒤 SQL을 중단한다. 하지만 [_pass_gate.py:187](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_gate.py:187)은 스캔 직전 결과를 `not_ok`로 정하고, 중단 예외도 그대로 그 결과로 반환한다.

예를 들어 두 DB의 예산이 각각 7초일 때, consumer 스캔이 7초를 넘어 진행 핸들러로 중단되고 projection이 빠르게 끝나면 합계 14초 전에 스레드가 종료된다. 저장된 `not_ok`는 [_pass_gate.py:241](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_gate.py:241)에서 유지되고, 최종 코드는 `DATABASE_INTEGRITY_FAILED`가 된다. 계약상 결과는 `deadline`·`DATABASE_INTEGRITY_UNAVAILABLE`이어야 한다. 열기·식별 단계의 마감 중단도 같은 방식으로 잘못 분류될 수 있다.

[정오표2:65](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata2.md:65)는 **단계 안에서 마감이 만료되면 `deadline`**이라고 명시한다. 계획 예산과 보장 상한의 구분은 수용하며, 지적 대상은 만료 결과의 분류다.

종결 조건: 진행 핸들러가 마감 때문에 중단한 결과를 단계별 오류보다 우선하여 `deadline`으로 보존한다.

**설계 밖 결정 ⑴~⑼ 판정**

아래 코드 경로의 기준은 `feature-pack/rag-consumer/`이다.

| 결정 | 판정 | 근거 |
|---|---|---|
| ⑴ 규칙 12 코드 변경 0 | 수용 | 이번 단위를 계측·게이트로 한정한 r17 §7과 일치. 기존 외부 호출의 규칙 준수를 인증한다는 뜻은 아니다. |
| ⑵ `--state-file` 추가 | 수용 | `src/airag_consumer/tick.py:399`, `_pass_child.py:61`. 부모의 로그 디렉터리에서 상태 경로를 전달한다. |
| ⑶ 설정 읽기 실패 시 게이트 우회 | **반려** | `_pass_gate.py:280`. M1의 무기록 실행 경로를 만든다. |
| ⑷ 복수 실패 시 `not_ok` 우선 | 수용 | `_pass_gate.py:258`. 각 DB의 결과를 남기면서 거부 코드 하나를 선정하는 방식은 계약과 양립한다. M2의 오분류는 별도 수정 대상이다. |
| ⑸ 최소 예산 7초·최대 2항목 | 수용 | `_pass_gate.py:151`, `_result.py:202`. 크기 미확인 시 0초를 피하고, 확정된 대상 2종을 따른다. |
| ⑹ 초기화 실패 표지·스키마 누락도 `d` 집계 | 수용 | `_pass_trace.py:149`, `:175`, `:184`. 표지는 최선 시도이며 업무 호출은 계속된다. |
| ⑺ `pass_elapsed_s`에 게이트 시간 포함 | 수용 | `tick.py:465`, `:476`. 기존의 자식 전체 실행 측정 의미를 유지한다. `integrity.ms`는 DB 점검 구간의 보조 수치다. |
| ⑻ 사유 코드 생성기 실행 | 수용—생성 결과 기준 | `reason_codes.py:95`, `:377`의 2개 추가와 `reason_code_review.py:66`의 줄 이동 보정이 일치한다. 과거 실행의 승인 여부까지 diff로 인증하지는 않는다. |
| ⑼ 강제 종료 시 임시 파일 잔류 | 수용 | `_pass_gate.py:87`, `:102`. 판독은 정식 상태 파일만 사용하므로 잔류 임시 파일이 점검 생략 근거가 되지 않는다. |

**N1 · note — 시험은 주요 계약을 단언하지만, 전체 행위 불변을 입증하는 비교는 부족하다.**

- 반환값·인자 전달·업무 예외 객체 동일성, `tok` 바인딩, 파일 회전·부분 쓰기·상한·락 경합은 실제 단언이 있다.
- DB 식별·읽기 전용 SQL 순서·상태 전이·거부 프레임·부모 재검증도 단언한다.
- 다만 [test_pass_gate.py:445](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/tests/test_pass_gate.py:445)는 계속 잘못된 설정만 확인하여 M1을 놓친다. [test_pass_gate.py:369](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/tests/test_pass_gate.py:369)는 연결 정지만 확인하고, 가짜 진행 핸들러는 저장만 하므로 M2를 단언하지 않는다.
- [test_pass_trace.py:531](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/tests/test_pass_trace.py:531)는 파일 생성·권한·회전을 확인하지만, 계측 활성/비활성 간 최종 로그·stdout 동일성을 비교하지 않는다. 기존 probe 비교도 양쪽 모두 새 계측·게이트를 거친다.

나머지 대조 결과: 지정 어댑터 전체 호출 래핑과 업무 예외 재발생 구조, trace 스키마·예약 예산, DB별 식별, 상태 기록 실패 거부, `integrity` 필드만 제거하는 복구는 수용한다. 새 외부 호출·재시도·600/300초 상한 도입은 없다. [_pass_gate.py:8](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/_pass_gate.py:8)은 전원 상실을 보장 밖으로 명시하며, 변경 코드·주석에서 정전 뒤 자동 점검 보장은 확인하지 못했다.

Serena 연결·프로젝트 활성화를 확인했고 참조 검색은 grep으로 보완했다. 파일 수정·시험 실행·모듈 import 실행·op·운영 DB/설치본/runtime.json 접근·launchctl·mbox·서브에이전트는 수행하지 않았다. `git diff --check`는 통과했다.

**최종 판정: REJECT. M1·M2 해소가 필요하다. 설치·재개 승인이 아니다.**
