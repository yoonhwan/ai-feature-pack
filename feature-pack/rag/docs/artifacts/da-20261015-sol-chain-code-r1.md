골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업/타임아웃 해결. N1→N2→N3 연속 실행 래퍼의 구현 DA다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 · Serena unavailable, grep-based). 답변 한국어.

판정: **PASS — blocker 0 / major 0 / minor 2**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2560. 대상 `a103f00`·`6f1bca3`, 기준 HEAD `6f1bca37d80964df193e024d325e7ab760e09c42`.
정본은 `arch-20261015-opa-popup-design-r8.md` §4, 설계 판정은 `da-20261015-sol-opa-design-r8.md`다. 이하 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/chain.py`, `sh:N`은 같은 폴더 `chain.sh`, `시험:N`은 `feature-pack/rag-consumer/tests/test_chain_opa.py`다.

**오빠가 한 줄로 한 번 실행하는 정상 주 경로의 새 blocker/major를 발견하지 않았다.** 원본 합성 시험 99건, 독립 직접 변이 22종, 실제 foreground 터미널 신호를 재현한 PTY 검증을 확인했다. 조건부 취소 경계와 잘못된 JSON 형의 오류 처리는 비차단 minor 두 건으로 둔다. 기존 P/E1 구현의 PASS·종결 상태는 유지한다. 이 판정은 **구현 DA**이며 실제 op 실행에 대한 별도 사람 HIL을 대신하지 않는다.

## 1. 설계 대조

| 항목 | 코드와 검증 | 평가 |
|---|---|---|
| 기존 도구·N3 정책 범위 | py:34–38,84–88. 원본 probe.sh→compare.sh→taskpolicy -b compare.sh를 동일 Python 인자로 호출. 도구 전체/후손에 적용되며 기존 데몬의 정책은 변경하지 않음. 대상 두 커밋 변경은 chain.py·chain.sh·test_chain_opa.py·_chain_fake_tool.py뿐 | 부합 |
| G1·G2·G3 | py:104–173,225–239,347–359. 코드 0 뒤에도 스키마/실제 실행 상태/잔존 flag/개수/회수/불완전/실행 오류를 확인. G3도 마지막 결과를 거절하면 5. 시험:115–230,351–395 | r7 반례 세 건 모두 차단 |
| 관측 대상의 양성 대조 | P0의 회수 확인 timeout/TCC unknown·후속 skipped, P4 network_error·auth_error, E1의 회수 확인 timeout은 게이트 통과. 시험:115–132,171–174,335–347 | 설계의 측정 목적 유지 |
| 이번 실행의 결과 찾기 | py:177–224. 전후 새 이름 중 단계별 후보 유형만 선택, 정확히 하나·일반 파일·1MiB 이하·JSON/닫힌 스키마 검사. E1의 남은 HOME 폴더·다른 유형 파일은 결과 후보가 아님. 시험:400–469 | 과거 결과/복수 결과/잘림/심링크·스키마 실패는 중단 |
| 값 비출력 | py:247–248에서 도구 stdout/stderr는 DEVNULL. py:225–239는 검증된 숫자·불리언·열거형만 요약. 결과 경로/환경 이름·값·raw stdout을 파싱해 출력하지 않음. 시험:661–679 | 센티넬과 free-text 결과 거부 통과 |
| 7초 룰·토큰 읽기 고지 | 래퍼는 측정 시도를 새로 만들거나 재시도하지 않으며 검수된 도구의 7초 시도 계약을 유지. N1 부모의 토큰 파일 읽기 시도·P0 미전달·조건부 계정 조회 및 N2/N3의 토큰 파일 비접근에 대한 r8 §6 고지는 그대로 필요 | 기존 도구 변경/새 토큰 파일 접근 없음 |
| 마감·후퇴안 | py:40–48,69–72,243–267,333–345. 기본 전체 240·83초 시작 조건·77초 뒤 TERM 한 번/3초 대기, 후속 중단. 후퇴안 총합을 **e1=162초/probe=84초**로 산출해 설계 DA minor의 여유 부족 해소. 시험:243–254,570–638 | 정상/초과 경로 부합. 취소 경계는 아래 minor |
| 신호·소유 범위 | sh:54–56 exec, py:259–267,321–325,361–369. 신호는 직접 도구 프로세스에만 전달하고 그룹/기존 op/공유 데몬은 대상으로 삼지 않음. 시험:494–541,647–657,730–757 및 독립 PTY | 정상 취소·중복 foreground 전달 경로 통과 |

원본 도구의 소스·시험을 다시 수정하거나 닫힌 회수 계약을 재심할 필요는 없다. 후퇴안을 실제 제시할 때는 새 래퍼 총합 **162초/84초**를 고지해야 하며, 원래 설계의 150초/75초를 래퍼 전체 상한으로 재사용하지 않는다. full의 사람 고지는 240초 그대로다.

## 2. 실행 증거

| 검증 | 결과 |
|---|---|
| 원본 chain 합성 시험 | **99 passed in 31.21s**, rc=0 |
| 독립 직접 변이 | **22/22 탐지**. Nano 보고 재인용이 아니라 원본에서 새로 만든 격리 사본에 직접 대입 |
| PTY Ctrl-C / 실제 probe.sh + 가짜 launchctl·op·log | **3/3: rc=130, 임시 job 0, 측정 직접 자식 생존 0** |
| PTY Ctrl-C / 실제 compare.sh + 가짜 op | **1/1: rc=130, 측정 직접 자식 생존 0** |
| 셸·변경 범위 | `bash -n chain.sh` 통과, 대상 커밋 변경 4파일만, 기존 probe/compare/s2 소스·시험 diff 0, core.bare=false |

원본 명령은 `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_chain_opa.py -q -p no:cacheprovider`이며 cwd는 `feature-pack/rag-consumer`다. 실제 검수 도구를 가짜 운영 의존성 위에서 잇는 시험과 두 번의 INT 전달 시험도 이 99건에 포함된다. 별도 PTY는 foreground 그룹에 `0x03`을 보내 chain·도구·보조 프로세스가 함께 받는 경로를 확인했다. 프로브 fake 명령은 기록 후 정체성을 바꾸지 않는 shell+sleep 형태다.

변이는 G1/G2 우회·대기 초과/회수/생략 단계 처리·스키마 extra key 허용·과거/복수 결과 선택·G3 무시·stdout/환경 센티넬 노출·비정상 코드/신호 코드·순서·N3의 -b 제거·예산 검사·TERM 제거/반복·취소 전달 제거/종료코드 0·후퇴안 짧은 총합·None 개수 허용이다. 모두 기존 시험의 관련 단언으로 탐지됐다. 생략 단계 변이는 첫 양성 대조에서는 차이가 없어 통과했지만, **기존 전용 시험 `test_g1_never_inspects_a_skipped_step_for_exit_state`가 탐지**했다. 이 재확인을 포함한 22/22이며 각 변이에 원본 99건 전체를 다시 돌렸다는 뜻은 아니다. 수집/문법 오류를 탐지 건수에 넣지 않았다.

Master가 병행한 clean HEAD 전체 회귀 결과는 작성 시점 미수신이므로 위 99건과 합산하지 않았다.

## m1 — 초과/취소의 복합 경계에는 1회 신호·잔여 마감 제약이 빠져 있다 (minor, 비차단)

근거: py:44–46,243–267,318,334–340 / 시험:508–525,631–644.

첫째, 초과 감시가 TERM을 보낸 뒤 GRACE 대기 중 Cancelled가 오면 예외 분기는 이를 이미 신호를 보낸 상태로 기억하지 않아 같은 도구에 다시 취소 신호를 보낸다. TERM을 무시하는 가짜 도구에서 **TERM 수신 뒤 chain에 INT**를 보내 **도구 신호 [15,2] / chain rc=130 / 후속 미실행 / 잔존 경고**를 재현했다. 따라서 주석의 «첫 신호 뒤에는 다시 보내지 않음»은 이 복합 경계까지 성립하지 않는다.

둘째, 취소 대기는 잔여 전체 시간이 아니라 고정 CANCEL_WAIT_S=16초다. 첫 두 단계가 75+3초씩 끝나고 마지막 도구가 74초째 취소된 뒤 16초를 모두 쓰는 가짜 시계 모형에서는 **246초 / rc=130**이었다. 실제로 246초 기다린 것이 아니며, 승인된 E1의 정상 정리가 16초 필요하다고 관측한 것도 아니다.

두 경우는 기존 도구가 77초를 넘기거나 정상 취소 정리를 제때 끝내지 못하는 조건이 필요하다. 실제 op/운영 도구에서 이 조건을 관측하지 않았고 정상 Ctrl-C 검증도 통과했으므로, 발주의 실사용 기준에 따라 minor로 둔다. 보강은 이미 전달한 신호 상태를 보존하고 취소 대기를 남은 계획 시간/최종 표시 예약과 함께 제한하는 방향이면 된다. 기존 P/E1 코드나 공유 데몬/그룹 종료로 해결할 필요는 없다.

## m2 — JSON의 conclusion이 list/dict이면 스키마 거부 대신 TypeError가 난다 (minor, 비차단)

근거: py:104–117,219–224,351 / 시험:218–230,439–448.

valid_e1은 conclusion의 형을 먼저 검사하지 않고 `compare.CONCLUSION_TEXT` 딕셔너리 membership을 검사한다. `conclusion=["SYNTH_INVALID_CONCLUSION"]`을 넣으면 **TypeError**가 전파되어 의도한 `result_schema`/종료 5 경로로 가지 않는다. json.loads 단계의 ValueError/OSError catch로는 이 형 오류를 잡지 못한다.

검수된 E1은 conclusion을 정해진 문자열/null로 쓰므로 정상 산출물이 이 형을 만드는 경로는 없다. 잘못된 결과 파일을 강제로 준 조건이며, 예외가 나도 N3로 진행하거나 값을 결과 요약으로 출력하지는 않는다. 비차단 minor로 두고, 보강 시 conclusion이 null 또는 문자열 enum인지 먼저 확인하고 list/dict 부정 사례를 추가하면 된다. 기존 E1 구현을 바꾸라는 요구가 아니다.

## 3. 재현 위치·범위

- 변이 실행기: `/tmp/airag-chain-da-code-r1-mutations.py`.
- 변이 원기록/개별 실패: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-chain-da-r1-mutations-k0dd64e3/summary.json`; 생략 단계 재확인과 최종 22/22는 같은 폴더의 `recheck.json`.
- PTY 실행기: `/tmp/airag-chain-da-code-r1-pty.py`; 유효 fixture의 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-chain-da-r1-pty-wuq1e3hp/evidence.json`.
- 조건부 경계 실행기: `/tmp/airag-chain-da-code-r1-checks.py`; 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-chain-da-r1-checks-dgmrdufu/evidence.json`.

실제 op·운영 launchctl·실제 taskpolicy·운영 토큰/자격 값·네트워크·DB 호출/열람은 0이다. 신호 전송/정리는 이 세션이 시작한 합성 도구·시험 프로세스에만 했다. 제품 소스/시험·운영 설정·설치·커밋·push 변경은 0이고 쓰기는 판정서 및 임시 합성 검증물이다. Serena 연결 실패 뒤 관련 정의·호출·출력·신호 경로는 exhaustive grep/직접 읽기로 대조했으며 도구 복구 시 참조 재확인은 가능하다.

다음 단계는 Master의 전체 회귀 확인과 실제 한 줄 스크립트/고지의 최종 대조 뒤 별도 사람 HIL이다. 이 판정은 실제 3단계 실행 결과·원인 규명·팝업 해결·consumer 복구 완료를 확인한 것이 아니다.
