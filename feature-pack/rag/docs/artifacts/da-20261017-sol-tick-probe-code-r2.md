골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — tick.py 계측+상한 구현 재심 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a14561-dd3c-7860-ad11-c4e62f7da8a4

**최종 PASS — blocker 0 / major 0 / minor 0 / note 2**

`8532bd8..80ca349 -- feature-pack/rag-consumer` 전체 diff를 직접 읽었다. 1차 수용 항목은 재개봉하지 않았다.

1. **Major 1 해소 — 재시도 예산을 기록·오류 분류 뒤 현재 시각으로 계산한다.**

   `tick.py:323`에서 종료 계측값과 재시도 예산을 분리했다. 직접 재현 결과:

   | 조건 | 결과 |
   |---|---|
   | 7.0/14.0, 첫 timeout 13.9초 + 분류 지연 0.2초 | 호출 1회, exit 30 |
   | 10.5/21.0, 첫 timeout 20.9초 + 기록 지연 0.2초 | 호출 1회, exit 30 |

   두 상한 모두에서 분류·기록 지연을 각각 적용해 재시도 금지를 확인했다. 종료 시각을 재사용하는 옛 결함을 메모리에 복원하면 두 번째 호출이 발생하며, **새 고정 기준 비교 시험이 두 경계 모두 탐지했다.**

   `_tick_baseline_e529d96.py`는 e529d96 원본과 **import 경로 한 줄만 다르고 나머지 변형은 0**이다. 설계 밖 결정 ⑴은 수용한다.

2. **Major 2 해소 — `op_resident` 삭제 선택을 수용한다.**

   필드·수집 함수·`ps` 실행·수집 timeout·전용 검증 함수·상한·`op_resident_unavailable` 사유를 제거했다. 정상 스키마에서도 삭제했고 `v=1`을 유지했다. Consumer 내 남은 참조 7곳은 삭제 확인 또는 재유입 거부 시험이다. 실행 코드의 남은 수집 경로·죽은 코드는 발견하지 못했다.

   고정 문서에는 삭제 전 설명이 남지만, 정오표 2차 §3.1·§4가 **필드째 삭제·모든 레코드 생략·v=1 유지**를 명시적으로 허용한다. 이번 판정은 그 삭제 분기를 수용한다.

   축소 스키마의 최대폭 숫자·오류 사유 **16개 조합**에서 최대 probe **684B**, 줄 증가분 **693B**였다. 최소 레코드는 **49~51B**이며 정상·최소 경로와 기존 시험이 정합한다.

3. **Major 3 해소 — 최종 합성 직렬화도 복구 사슬을 따른다.**

   `_line_with_probe`를 직접 실행해 정상 합성만 실패하거나 정상·최소 합성이 모두 실패하는 경우 모두 **시도 순서 `['normal', 'minimal']`**을 확인했다. 전자는 `collect_failed` 최소 probe를 출력하고, 후자는 기준 줄과 바이트 동일한 문자열을 반환했다.

4. **새 설계 밖 결정 ⑵ — 최종 직렬화 실패 처리 수용.**

   `_compose`를 정상·최소 합성에 공통으로 사용하고, 정상 합성 실패 시 검증된 최소 레코드를 다시 합성한다. 최소 생성·합성도 실패하면 확정된 기준 줄을 반환한다. 해당 복구 경로에서 예외 메시지·값을 출력하거나 기존 payload를 변경하지 않는다.

**Note 1 — 직접 확인한 시험 증거**

- `test_tick.py`·`test_tick_probe.py`·`test_reason_codes.py`: **265 passed, 0 failed, 377.98초**.
- 파일 쓰기 없는 인라인 메모리 변이 **4종 탐지, 생존 0**: 종료 시각 재사용·남은 마감 제한 제거·최종 최소 합성 생략·삭제 필드 허용. Nano 보고의 완전성을 추정하지 않고 직접 선택한 4종을 확인했다.
- `80ca349`는 review 줄 키 **489→465 한 곳**만 변경했다. reason-code 레지스트리 diff는 **0**이다.

**Note 2 — 검증 범위와 승인 경계**

Serena handshake와 참조를 확인했다. 실제 `op`·launchctl·운영 plist/설치본/runtime.json 변경·mbox·서브에이전트 사용은 0이다. 저장소 파일을 작성하지 않았으며 시험 종료 후 대상 트리는 `80ca349`와 동일하다. 기존 미추적 `.claude/`, `CLAUDE.md` 상태도 동일하다.

**최종 PASS. 구현 재심 통과이며, 설치·재개 승인이나 C12 운영 회복 관찰 완료를 뜻하지 않는다.**
