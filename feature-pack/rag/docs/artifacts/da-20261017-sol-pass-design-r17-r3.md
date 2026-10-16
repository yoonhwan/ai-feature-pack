골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — 설계 r17 정오표 2차 재심 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a145c9-e6b6-7ea3-9d2f-aed0b60376cd

**최종 REJECT — blocker 0 · major 1 · minor 0 · note 0.**

원문 r17·정오표 1차·2차·직전 판정을 대조했다. 수용 유지 항목은 다시 열지 않았다. 직전 지적 7건은 해소됐으나, 새로 추가된 정전 보장에 major 1건이 있다.

직전 지적의 종결 근거는 다음과 같다. 줄 번호는 [정오표 2차](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata2.md:7) 기준이다.

| 직전 지적 | 판정·근거 |
|---|---|
| major 1: `_post_json` 인자 위치 | **종결.** L9–12: 두 번째 위치 인자이며, 위치·키워드 호출 모두 서명에 바인딩된 `path`로 판별한다. 실제 서명·호출과 일치한다. |
| major 2: trace 최초 생성 | **종결.** L20–24: ENOENT는 회전을 건너뛰고 `O_CREAT`로 진행하며, 다른 실패와 구분한다. |
| major 3: `running` 기록 실패 뒤 우회 | **종결.** L35–41: 기록 실패 시 pass 시작을 거부한다. 기존 `clean`이 남아도 미기록 상태로 업무가 실행되는 반례는 닫혔다. |
| major 4: 호출 총마감과 소켓 밖 대기 충돌 | **종결.** L47–52: 보장 범위를 소켓 I/O로 한정하고 호출 전체의 D 내 반환은 미확정이라고 명시한다. |
| minor 1: projection 예외 분류 | **종결.** L56–67: 연결·식별·스캔 단계로 분류하므로 같은 예외 클래스에 의존하지 않는다. 원문 예외 메시지도 사용하지 않는다. |
| minor 2: `x` 예산·줄 경계 | **종결.** L71–74: 예약 예산·시도 횟수·선행 개행과 표지 기록 실패 시 판독 규약을 명시한다. |
| minor 3: 캐시 횟수 단정 | **종결.** L78: 캐시에 유지된 조합의 재사용으로 한정하고 miss·eviction 뒤 재로드 가능성을 인정한다. |

**새 major 1 — `os.replace` 반환만으로 정전 뒤 `running` 보존을 보장할 수 없다.**

[정오표 2차 L36–39](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata2.md:36)는 임시 파일 작성과 `os.replace` 반환을 성공 기준으로 삼으면서, 새로 “강제 종료·정전: `running`이 남아 다음 틱이 점검한다”고 선언한다. 파일·디렉터리 변경의 영속화 조건은 제시하지 않는다.

`os.replace`의 원자적 교체와 전원 상실 뒤의 영속성은 별개다. 따라서 다음 반례를 배제하지 못한다.

1. 기존의 유효한 `clean`이 영속 저장돼 있다.
2. `running` 교체가 반환돼 pass가 시작된다.
3. DB 작업 도중 정전이 발생한다.
4. 재부팅 뒤 상태 파일에 이전 `clean`이 남으면 다음 틱은 점검을 생략한다.

이는 새로 약속한 **정전 뒤 자동 점검을 우회하는 경로**이므로 문구 취향에 해당하지 않는다. 실제 발생을 관측했다는 주장은 아니며, 현재 계약으로 배제되지 않는 설계 반례다.

최소 정정은 L39에서 **정전 보장을 철회하고, 운영체제가 살아 있는 상태의 프로세스 강제 종료로 보장 범위를 한정**하는 것이다. 정전 뒤 상태 파일의 영속성과 점검 여부는 미확정이라고 명시하면 된다.

파일 쓰기·시험 실행·op·운영 DB/설치본/runtime.json 변경·launchctl·mbox·서브에이전트는 수행하지 않았다. 본 판정은 설계 심사이며 코드 변경·설치·재개 승인이 아니다.

**최종 판정: REJECT.**
