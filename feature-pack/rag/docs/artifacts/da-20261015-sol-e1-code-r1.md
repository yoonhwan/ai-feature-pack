골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업/타임아웃 해결. E1 터미널 조건별 측정 도구의 구현 DA다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 · Serena unavailable, grep-based). 답변 한국어.

판정: **PASS — blocker 0 / major 0 / minor 2**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2543. 대상 `7aecea0`·`6bf9dac`, 기준 HEAD `6bf9dac6f959d32b68bf9d0d11bf6c1461b1fe1a`.
정본은 `arch-20261015-opa-popup-design-r6.md` §6, 설계 판정은 `da-20261015-sol-opa-design-r6.md`다. 이하 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/compare.py`, `sh:N`은 같은 폴더 `compare.sh`, `core:N`은 `probe.py`, `시험:N`은 `feature-pack/rag-consumer/tests/test_compare_opa.py`의 행이다.

**오빠 터미널에서 E1을 한 번 실행하는 경로의 새 blocker/major는 발견하지 않았다.** 원본 합성 시험 43건과 직접 변이 18종, 실제 터미널 신호 전달을 재현한 PTY 검증을 확인했다. 새 minor 두 건은 인위적인 종료 미확인/로컬 I/O 지연에서 드러난 조건부 보강점이다. 실제 op에서 그 조건을 관측한 것은 아니며, 발주의 심각도 기준에 따라 비차단으로 둔다. 이 PASS는 구현 DA이며 **실제 op 실행에 대한 사람 HIL을 대신하지 않는다.**

## 1. 설계 대조와 import 편차

| 항목 | 구현 및 확인 | 판정 |
|---|---|---|
| A/B/C × 2회, 명령과 환경 | py:53,133–143,269–295. A는 OP_*·이름 패턴 6종 제거, B는 정본 허용 목록, C는 HOME 교체 + OP_CONFIG_DIR 추가/TMPDIR 유지. PATH에서 찾은 절대 경로에 `--version`만 전달. 시험:256–359 | 부합 |
| 7초·재시도 없음·회수 | py:46–51,89–116. 시작 전에 deadline을 잡고 남은 시간으로 communicate, 단일 호출, 만료/중단 때 소유한 직접 자식만 core:237–263으로 회수. 공유 데몬·비소유 op·그룹/후손 종료 없음 | 부합. 새 Timer/회수 경쟁을 만들지 않음 |
| 전체 예산·부분 완료 | py:47–51,269–277,292–297. 75초/5초 예약/시작 전 15초 확보, 단축 시도 없음. 종료 미확인 뒤 후속 라운드 skipped, 매 라운드 원자 저장. 시험:503–610 | 정상 예산 모델 부합. 아래 minor의 범위 한계 있음 |
| 결론 우선순위 | py:168–200. 취소 → 종료 미확인 → 누락 → 실행 오류가 27개 조합보다 우선. 시험:215–251 | 부합 |
| 신호·사람 터미널 | sh:48–50의 exec로 foreground Python에 인계. py:235–243,298–305,322–324에서 신호별 130/143/129 및 자식 회수. 시험:418–447 및 독립 PTY Ctrl-C | 측정 중 정상 취소 부합 |
| 값 비출력·토큰 비접근 | py:92–129,252–263,327–341. 출력은 메모리에서 분류 후 결과 스키마에서 제외, 오류는 분류/고정 문구. 이름은 개수만 기록. core.read_token/execute를 호출하지 않음. 센티넬·파일 open 감시·정적 시험 및 import 전 audit 확인 | 실제 자격 값 열람/출력 없이 확인 |
| 설계 r6 minor 1 보존 | py:309–315. 개수 증가/감소/미관측, 종료 미확인, C 생성 후 취소이면 보존·확인 필요. py:337은 개수 일치가 새 데몬 부재의 증명이 아님을 명시. 시험:452–531 | 요구한 보수적 처리 반영. 개수 상쇄의 이론적 한계를 새 major로 올리지 않음 |
| 설계 r6 minor 2 시험 문구 | 시험:330–333은 C의 OP_CONFIG_DIR 예외를 포함. 시험:362–413은 비소유 op 생존과 직접 자식 회수를 구분 | 반영 |

**probe.py import 편차는 이 구현 범위에서 수용한다.** 설계는 import 없는 단일 파일을 제안했으나 py:38–41은 인접 파일을 별도 모듈명으로 불러와 상수·override·환경 구성·원자 쓰기·Budget·직접 자식 회수 함수만 사용한다. core의 실행 진입점은 `__name__ == "__main__"` 아래에 있어 이 import로 실행되지 않는다. 독립 audit를 **import 전부터** 걸어 subprocess 생성 0·토큰 경로 접근 0을 확인했다. 원래 파일을 수정하거나 기존 P의 실행 모드/전이표를 변경하지 않는다. 실제로 대상 두 커밋의 변경 파일도 신규 E1 3개뿐이며 probe.py/probe.sh diff는 0이다.

따라서 이 편차는 승인된 core 함수의 재사용이고, 닫힌 P 구현을 다시 여는 이유가 아니다. 장래 core 변경 시 E1 회귀를 함께 확인해야 하는 의존성은 생긴다. E1 전용 run_attempt에는 core의 PID 기록/Timer가 없어 과거 P의 Timer 문제를 그대로 이식하지 않았다.

## 2. 실행 증거

| 검증 | 결과 |
|---|---|
| 원본 E1 합성 시험 | **43 passed in 19.19s**, rc=0 |
| 직접 변이 | **18/18 탐지**. 제품 원본은 수정하지 않고 각 격리 사본에 한 변이씩 적용 |
| 실제 foreground PTY Ctrl-C | 가짜 측정 자식 진행 중 터미널에 `0x03` 전송 → **130 / cancelled_incomplete / reaped=true / 소유 자식 생존 0** |
| import 전 audit | subprocess 생성 0, 정본 토큰 경로 접근 0 |
| 셸 문법·범위 | `bash -n` 통과, 대상 두 커밋의 변경은 compare.py·compare.sh·test_compare_opa.py뿐, core.bare=false |

원본 명령은 `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_compare_opa.py -q -p no:cacheprovider`이며 실행 cwd는 `feature-pack/rag-consumer`다. Master 병행 전체 회귀 결과는 작성 시점 미수신이므로 이 통과 건수에 합산하지 않았다.

변이는 판정/취소/종료 미확인/오류 우선순위 4종, 실행 순서, OP_*·AUTH 필터, B 환경 확장, C 격리 제거, stdout 저장, 시도 8초·단축 시도·예산 검사 제거, 종료 미확인 뒤 계속 실행·폴더 보존 제거, 전후 개수 변화 무시, 신호 종료코드 0, production의 시험 변수 거부 제거다. 각 선택 시험이 실패했다. 종료 미확인 뒤 계속 실행하는 변이는 고정 길이 합성 응답을 초과 호출해 fixture의 IndexError로 탐지됐다. OP_* 필터 변이는 병렬 최초 실행에서 축소 0.6초 시도가 지연되어, **직렬 재실행의 OP_FOO 잔존 단언 실패**로 의도한 탐지를 재확인했다. 수집 실패나 문법 오류를 변이 탐지로 센 것은 아니다.

## m1 — 마지막 라운드가 종료 미확인이면 완료 플래그와 종료코드가 모순된다 (minor, 비차단)

근거: py:181–184,296,310,316–324 / 시험:503–510.

종료 미확인이 중간에 생기면 다음 라운드의 skipped 상태가 complete를 False로 만든다. 하지만 **마지막 C 2회차**에 처음 생기면 후속 라운드가 없어, `complete` 계산이 여섯 상태가 RAN에 속하는지만 보고 True로 만든다. 합성 응답으로 첫 다섯 회 success/마지막 회 timeout+종료 미확인을 주면 **종료코드 0, complete=true, exit_class=ran_all**이면서 conclusion은 `incomplete_exit_unconfirmed`였다. 폴더 보존과 화면의 해석 금지는 올바르게 유지됐다.

실제 자식이 SIGKILL 뒤 2초 안에도 종료 확인되지 않는 조건은 관측하지 않았다. 정상 사용 결과를 오판한 증거도 없어 발주 기준상 minor로 둔다. 보강은 `complete`에 종료 미확인 부재를 포함하고 마지막 회차 사례를 합성 시험에 추가하는 정도면 된다. 현재 시험은 세 번째 회차만 미확인으로 만들어 이 경계를 놓친다. 이 문제를 이유로 기존 core 회수 구현을 바꿀 필요는 없다.

## m2 — 75초는 라운드 진입 예산으로 집행하며, 로컬 I/O 정체까지 강제하지는 않는다 (minor, 비차단)

근거: py:214,262,274–297,302–321 / sh:48–50 / core:116–123.

정상적인 관측/쓰기 시간 안에서는 시작 전 15초 조건으로 7초 시도와 정리 몫을 보존한다. 그러나 최상위 타이머/감시자가 없고, 라운드마다 하는 fsync·최종 기록·폴더 정리가 전체 마감에 의해 중단되지는 않는다. 가짜 시계에서 원자 쓰기마다 **인위적 20초 로컬 지연**을 더하면 진입 예산 검사로 뒤 라운드는 생략해도 쓰기를 계속하여 종료까지 140초로 모델링됐다. 실제로 20초를 기다리거나 운영 파일시스템 정체를 재현한 것은 아니다.

이는 예상된 짧은 로컬 작업을 벗어난 장애 조건이므로 이번 1회 터미널 경로에서 blocker/major로 올리지 않는다. 다만 문서/고지의 «하드 상한»을 OS·파일시스템 정체까지 포함하는 전면 보장으로 읽으면 구현보다 강하다. 보강 시에는 라운드 사이/최종화의 남은 시간 확인과 반복 저장 생략 정책을 명확히 하거나, 고지를 정상 로컬 I/O 조건의 시간 상한으로 한정할 수 있다. 시간 초과를 이유로 공유 op나 프로세스 그룹을 종료하는 방식은 요구하지 않는다.

## 3. 재현 위치와 범위

- 변이 실행기: `/tmp/airag-e1-da-code-r1-mutations.py`.
- 변이 요약/개별 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-e1-da-r1-mutations-bc7hxmt9/summary.json`; OP_* 직렬 재확인은 같은 폴더의 `serial-recheck.json`.
- 독립 확인 실행기: `/tmp/airag-e1-da-code-r1-checks.py`.
- import/마지막 미확인/가짜 I/O 지연/PTY 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-e1-da-r1-checks-rdi4qhfz/evidence.json`.

모든 실행은 가짜 op·가짜 pgrep·합성 HOME/토큰 파일을 사용하거나 자식 실행을 대체했다. PTY 검증에서도 실제 op는 호출하지 않았다. 시험이 만든 프로세스만 시험 자체가 회수했다. 실제 op·운영 launchctl·운영 토큰/자격 값·네트워크·DB 접촉은 0이다. 제품 소스/시험·설치·커밋·push 변경은 없고, 쓰기는 이 판정서 및 임시 합성 검증물이다. Serena 연결 실패에 따라 관련 정의·호출/출력 경로는 exhaustive grep과 직접 읽기로 확인했으며 도구 복구 시 참조 재확인 여지는 남는다.

다음 단계는 Master의 전체 회귀 확인과 기존 절차에 따른 사람 HIL이다. 이 판정으로 E1 실행 결과·원인 규명·팝업 해결·consumer 복구가 확인된 것은 아니다.
