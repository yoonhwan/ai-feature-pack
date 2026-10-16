골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — 설계 r17 정정 정오표 재심 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a145b4-9ffa-73b0-b305-c96d98fb7ed5

**최종 REJECT — blocker 0 · major 4 · minor 3 · note 4.**

대상은 [r17 정오표](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:1)와 원문이다. 원문은 `d977ad8`, 1차 판정문은 `59d4211`과 현재 파일의 차이가 없음을 확인했다. 수용 유지 항목은 다시 열지 않았다. 아래 반례는 문서 계약의 논리적 대조이며 실행 결과가 아니다.

파일 쓰기·시험 실행·운영 DB 열기·op·launchctl·mbox·서브에이전트는 수행하지 않았다. Serena 연결과 언어 서버 ready 상태를 확인하고 심볼·참조 조회를 사용했다.

**major 1 — M1 정정: `_post_json`의 인자 위치가 실제 소스와 다르다.**

[정오표 L33](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:33)은 “첫 위치 인자 `path`”를 비교하도록 한다. 실제 [함수 서명](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/llm_enrichment.py:193)은 `_post_json(cfg, path, body_obj, ...)`이며, Serena 참조에서도 `_post_json(cfg, "/tokenize", ...)` 호출을 확인했다.

문장대로 구현하면 `cfg`를 비교하므로 tokenize 호출을 구분하지 못한다. **바인딩된 `path` 값—현재 위치 호출에서는 두 번째 인자—만 상수와 비교**하도록 정정해야 한다.

어댑터 함수 전체를 감싸 read·파싱을 포함하는 방향, 모듈 전역 이름 교체, 클래스 `__call__` 교체는 수용한다. 원함수에 인자를 그대로 전달하고 추적의 `Exception`만 격리하며 업무 예외를 bare `raise`하는 구조도 수용한다.

**major 2 — M2 정정: trace 최초 생성 경로가 없다.**

[정오표 L48](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:48)은 `lstat`·회전·열기 중 어느 하나라도 실패하면 해당 pass의 추적 전체를 비활성화한다.

최초 배포처럼 trace가 없는 경우 `lstat`가 `ENOENT`로 실패한다. 따라서 `O_CREAT`에 도달하지 못하고, 다음 pass에서도 같은 상태가 반복된다. **원본 trace 부재는 정상적인 최초 생성으로 처리하고, 나머지 검사·회전 실패와 구분**해야 한다. 업무 호출이 계속된다는 계약은 유지할 수 있지만, 현재 문장으로는 계측을 시작할 수 없다.

**major 3 — M4 미종결: `running` 기록 실패 뒤 오래된 `clean`으로 우회할 수 있다.**

[정오표 L88–90의 계약](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:88)은 다음 경로를 허용한다.

1. 유효한 기존 `clean`을 읽어 점검을 생략한다.
2. `running` 임시 파일 작성 또는 `os.replace`가 실패한다.
3. 기록 실패는 업무를 바꾸지 않으므로 pass를 실행한다.
4. pass가 강제 종료된다.
5. 기존 `clean`이 그대로 남아 다음 틱도 점검을 생략한다.

따라서 “기록 실패 = 다음 틱도 점검”과 “중단 뒤 첫 틱 자동 점검”이 보장되지 않는다. **안전한 `running` 기록이 없으면 pass를 시작하지 않거나, `clean`에 의한 생략을 없애는 등 기존 `clean`이 살아남아도 우회할 수 없는 계약**이 필요하다. 경로 해시·닫힌 스키마·권한 검증만으로 이 경로가 닫히지는 않는다.

**major 4 — M5 일부 미종결: ‘시작부터 D 안에 반환’과 소켓 밖 대기 제외가 충돌한다.**

[정오표 L98](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:98)은 대기마다 잔여 시간을 적용하도록 고쳤다. 단순 read 루프 시계 확인보다 진전된 계약이다.

그러나 같은 문장에서 “시작부터 D 안에 반환 또는 timeout”을 요구하면서 이름 조회 등 소켓 밖 대기는 보장 밖으로 둔다. 이름 조회가 D를 넘겨 지연되면 아직 제한할 연결 소켓이 없으므로, 제시한 소켓 timeout·소켓 닫기만으로 어댑터 반환을 보장하지 못한다.

**소켓 밖 대기까지 포함하는 호출 총마감 계약을 닫거나, 보장 범위를 소켓 I/O로 한정하고 호출 전체의 D 내 반환은 미확정으로 명시**해야 한다. pass 최악 시간 미확정, consumer 윈도우와 core semantic window 구분, `120+70=190` 철회는 수용한다.

**minor 1 — B1: projection의 `open_error`·`identity_error` 분류 계약이 부족하다.**

DB별 opener 분리는 맞다. consumer의 범용 읽기 전용 연결은 [operations.py](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/operations.py:156)와 맞으며, engine·`user_version=4` 검사는 [ledger.py](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/ledger.py:314)와 맞는다. **기존 B1의 정상 consumer 차단 문제는 해소됐다.**

다만 projection opener는 [읽기 검증 실패](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/db/connect.py:79)와 [engine 불일치](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/db/connect.py:208)에 같은 `WrongKeyOrForeignDatabase`를 사용한다. opener를 그대로 호출하는 것만으로 두 결과가 자동 구분되지는 않는다.

5종 enum과 실패 코드 매핑은 수용하되, **projection 예외를 어느 enum으로 분류하는지** 추가 명세가 필요하다. 원문 예외 메시지 출력으로 해결해서는 안 된다.

**minor 2 — M2: 중단 표지 `x`의 유효 기록 계약이 덜 닫혔다.**

[정오표 L49–52](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:49)에는 두 빈틈이 있다.

- 부분 쓰기로 개행 없는 조각이 남은 뒤 같은 파일에 `x`를 append하면, 조각과 `x`가 한 줄로 합쳐져 판독 시 함께 폐기될 수 있다.
- 줄·바이트 상한을 소진한 뒤 `x`를 추가할 예약 공간이 없다. 쓰면 상한을 넘고, 거부하면 약속한 표지가 없다.

**중단 표지용 예산과 부분 쓰기 뒤 줄 경계 처리**, 또는 표지를 남길 수 없는 경우의 판독 규약을 명시해야 한다. 부분 줄 폐기와 “짝 없는 `b`는 원인 미확정 후보”라는 정정은 수용하므로, 이를 원인 확정 결함으로 확대하지 않는다.

**minor 3 — M7/F9: ‘조합별 최대 1회’도 아직 절대 표현이다.**

[정오표 L115](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:115)은 캐시 키를 올바르게 고쳤지만, “pass 자식마다 조합별 최대 1회”라고 단정한다. 실제 [캐시](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/chunking.py:55)는 `lru_cache(maxsize=8)`이다.

조합 수가 미확인인 상태에서는 eviction 뒤 같은 조합의 재로드 가능성을 제외할 수 없다. **“캐시에 유지된 조합은 재사용하며, miss·eviction 시 로드 가능”**으로 한정하거나 해당 pass에서 eviction이 없다는 근거가 필요하다. 실제 운영에서 eviction을 관측했다는 뜻은 아니다.

**그 밖의 1차 지적 처리 상태**

| 항목 | 재심 결과 |
|---|---|
| M2의 파일·예외 기본 계약 | `O_NOFOLLOW`·`fstat`·소유자·링크 수·`fchmod`, 비차단 쓰기 락, 번호 부여, 개행 포함 크기, 필드 조합표, 업무 예외 재발생은 수용. 위 major 2·minor 2는 남음. |
| M3 | 수용. 데몬 스레드와 `join`으로 메인 결정 시점을 분리하고, 스레드 종료·I/O 종료는 보장하지 않는다고 명시했다. 21초는 계획 예산이며 결정 지연도 미측정이다. 실행 보장이 검증됐다는 판정은 아니다. |
| M6 | 수용. 56초를 계산 예시로 제한하고 입력·출력 기준, 분할 불가 미증명, 재시도 포함 70초, 첫 출력 전 재시도, 스트림 무진행 7초를 명시했다. |
| M7 | F4의 최대 1건, F6 호출 수 도출 불가, 연결 교체 해석, 성공 관측 철회, F5·F8·F11·F12 한정은 수용. F9는 minor 3이 남음. |
| m1 | 수용. 미수행 점검을 위험 고지로 바꾸고, R-5 보고와 실제 종료 권한을 분리했다. |

**note 4건 — 기존 note 처리 기록**

- **N1:** 사실표 정정을 대체로 수용한다. 남은 F9 절대 표현은 minor 3으로 계수했다.
- **N2:** 수용 유지. 지정 로그 집계를 다시 열지 않았다. 정오표가 10-02 수치를 설계 근거에서 제외한 것도 수용한다.
- **N3:** 수용 유지. 기억 pending 고착 위험·복구 호출처 관련 판정을 다시 열지 않았다.
- **N4:** 수용. [정오표 L132–133](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17-errata.md:132)은 profile-source 제외 근거를 정상 pass 호출 경로에 두고, 3종 지시 중 해당 점검은 미수행·미확인이라고 명시했다.

정오표에서 `약화·배제·판명·우세`는 검색되지 않았다. 새 문장에 이번 지연의 원인을 확정하는 서술이나 운영 값 출력을 새로 요구하는 계약은 확인하지 못했다. 다만 금지어 부재와 별개로 위 시간 보장·캐시 횟수 단정은 정정이 필요하다.

**최종 판정: REJECT.** 기존 blocker B1의 핵심은 해소됐지만, major 4건과 minor 3건이 남았다. 본 판정은 설계 재심이며 코드 변경·설치·재개 승인을 뜻하지 않는다.
