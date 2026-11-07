최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 — C12. 카드 airag-tick-op-7s 끝 줄 6(설치본 tick.py 교체 h) 앞 코드 DA 1회차 — 범위 = R-H·R-F.

시험 단계별 초: R-H 14.344초 / R-F 19.036초(두 묶음 병렬) / 추가 반례·호환 0.009초 / 변이 29.686초 / 크기 변이 후속 0.005초. 각 pytest 호출 70초 이내, 변이 동시 최대 4개.

REJECT — 동작 반례 1 / 형식 2 / 범위 밖 0.

2026-11-07, aifp-airag-da-codex#5, GPT-6.1 Sol. 판정은 R-H·R-F 코드에 한정한다. 설치와 운영 승인이 아니다.

## 대상과 기준

- 고정 대상은 13b35ce9의 tick.py와 reason_codes.py다. 작업 시 HEAD는 3f9b5bce01e16cd07a4af8535b267ca3d8700335였으며, 두 파일에 대한 `git diff 13b35ce9 -- ...` 출력은 시작과 종료 모두 없었다.
- 설치본 `~/.local/share/airag/runtime/lib/python3.13/site-packages/airag_consumer/`과의 읽기 전용 diff는 tick.py 추가 102줄, 삭제 4줄과 reason_codes.py 추가 2줄이다.
- 범위는 82a5b737의 R-H와 3b9f1fdf의 R-F다. 7초 상수의 기승인 판정은 재검토하지 않았다.
- 기준은 발주문 질문 1~5, arch-20261028-appreg.md §5·Q3, arch-20261029-appB.md §6 K2·K3와 planner arch#43 덧판정 #270992다.
- 실제 op, 키체인, launchd, 앱은 실행하지 않았다. 추가 시험은 subprocess.run을 가짜 함수로 바꿨다. 기존 시험은 임시 폴더의 synthetic op만 실행했다.

## 반례 전수

### 동작 1: 상위 symlink를 따라 real HOME 밖에 op-home을 만든다

재현 입력 1줄: 임시 HOME의 `.config`를 HOME 밖의 별도 임시 directory로 symlink한 뒤, 정상 synthetic op credentials로 `load_keys({'HOME': str(home)}, credentials)`를 호출한다.

- 위치: `feature-pack/rag-consumer/src/airag_consumer/tick.py:338`~356, 특히 parent mkdir 340행과 최종 항목만 보는 lstat 345행.
- 기대: real HOME 밖으로 나가는 경로는 생성 전에 거절하고 `OP_HOME_INVALID`로 실패한다. op 호출은 0회다.
- 실제: HOME 밖에 `airag/op-home`을 만들고 정상 반환한다. 가짜 op 호출은 3회다. 자식 HOME의 resolve 결과가 real HOME 바깥이다.
- 실측 출력: `PARENT_SYMLINK {"op_calls": 3, "escaped_home": true, "created_outside": true}`.
- 계약 위반: 코드가 명시한 real HOME 아래 격리와 appreg Q3의 symlink 안전 조건을 충족하지 않는다. `.config`를 별도 dotfiles directory로 연결하는 구성에서도 생길 수 있다.
- 고쳐야 할 동작: 상위 symlink 때문에 HOME 경계를 벗어나는 경우 외부 directory 생성과 op 실행 전에 거절해야 한다. 최종 op-home 항목의 symlink 검사만으로 통과시키지 않는다.

### 형식 1: R-H 실패에는 stderr 안내가 없다

재현 입력 1줄: 임시 HOME에 mode 0755인 op-home을 만들고, 존재하는 임시 config와 synthetic credentials로 `tick.main(...)`을 호출한다.

- 위치: `tick.py:600`~601의 안내 분기가 `OP_STORE_KEYS_INVALID`에만 적용된다.
- 기대: 발주 질문 4의 고정 stderr 안내 1줄.
- 실제: rc 30, code `OP_HOME_INVALID`, op 호출 0회, stderr 0줄.
- 실측 출력: `RH_STDERR {"rc": 30, "code": "OP_HOME_INVALID", "stderr_lines": 0, "op_calls": 0}`.
- 실패 자체는 JSON과 rc로 드러난다. 조용한 성공은 아니므로 형식으로 분류한다. 고쳐야 할 동작은 R-H 실패에도 값 없는 stderr 안내를 1줄 내보내는 것이다.

### 형식 2: 값이 중복된 키 파일은 고정 이유 코드와 안내를 벗어난다

재현 입력 1줄: 이름이 정확한 키 3개 모두에 동일한 유효 64자리 hex를 넣은 0600 일반 파일을 store_keys_file로 지정하고 `tick.main(...)`을 호출한다.

- 위치: `tick.py:324`에서 파일을 통과시킨 뒤 438~439행이 `STORE_KEYS_MUST_BE_DISTINCT`를 올린다. 600행의 안내 조건에도 들어가지 않는다.
- 기대: 발주 질문 2와 `_read_store_keys` 계약에 따라 파일 원천 문제는 `OP_STORE_KEYS_INVALID`로 실패하고 고정 안내를 1줄 낸다.
- 실제: rc 30, code `STORE_KEYS_MUST_BE_DISTINCT`, op 호출 0회, stderr 0줄.
- 실측 출력: `RF_SAME_KEYS {"rc": 30, "code": "STORE_KEYS_MUST_BE_DISTINCT", "stderr_lines": 0, "op_calls": 0}`.
- 동일 키는 안전하게 거절하므로 형식으로 분류한다. 기존 `test_a_store_file_whose_keys_are_not_distinct_is_refused`는 실제 코드를 기대하도록 작성돼 있어 green이다. 고쳐야 할 동작은 파일 원천의 잘못된 내용도 고정 코드와 안내로 끝내는 것이다.

## 기준 대조와 실행 증거

| 기준 | 실행 결과 | 판정 |
|---|---|---|
| op-home 없음 | 0700으로 생성, 기존 정상 directory 재사용, 자식 HOME만 변경 | 통과 |
| op-home 권한·소유·최종 symlink·일반 파일·상대 HOME | rc 30 또는 TickError, `OP_HOME_INVALID`, op 0회 | 통과 |
| 상위 symlink로 HOME 이탈 | HOME 밖 생성 후 op 3회 | 동작 반례 1 |
| store_keys_file 정상 | 키 3개 취득, 기존 환경 키 우선, op 0회 | 통과 |
| 파일 없음·mode 불일치·남의 소유·비일반 파일·잘못된 내용 | `OP_STORE_KEYS_INVALID`, op fallback 0, 합성 값 노출 없음 | 통과 |
| 파일 내용의 키 중복 | 거절하지만 이유 코드와 안내가 다름 | 형식 2 |
| 설정 없음 | 설치본과 고정 소스의 op argv·reference·token·나머지 자식 env가 같음 | 통과 |
| 실패가 성공으로 바뀌는가 | 재현한 실패 모두 rc 30, key_error, op fallback 0 | 통과, stderr는 형식 1·2 |
| reason_codes 추가 | 두 고정 코드가 registry에 있음 | 통과 |

설정 없음 비교에서는 두 모듈을 같은 임시 token·credentials와 가짜 subprocess로 실행했다. 각각 op read 3회이며 최종 키 환경도 같다. 자식 HOME만 R-H가 의도한 격리 directory로 달라진다. R-H에는 별도 off 설정이 없으므로 이 의도된 차이를 회귀 반례로 세지 않았다.

| 실행 | 결과 | subprocess를 포함한 경과 |
|---|---|---|
| `../rag/.venv/bin/python -m pytest tests/test_tick_op_home.py -q -p no:cacheprovider` | 18 passed, pytest 12.37초 | 14.344초 |
| `../rag/.venv/bin/python -m pytest tests/test_tick_store_keys.py -q -p no:cacheprovider` | 32 passed, pytest 17.88초 | 19.036초 |
| 추가 반례와 설치본 비교 | 위 JSON 4건, synthetic 값 출력 0 | 0.009초 |

기본 시험은 rag-consumer directory에서 실행했다. 각 호출에 subprocess timeout 70초를 뒀다. 기존 9파일 전체 회귀는 이번 발주 대상이 아니며 재실행하지 않았다. planner 덧판정에 이미 회귀 green 근거가 있다.

## 검사 제거 변이

작업 트리를 수정하지 않고 임시 package 사본마다 검사 하나만 제거했다. 각 변이는 해당 단일 pytest node로 검증했다. 원본 파일은 유지했다.

| 제거한 검사 | pytest rc | 경과 초 | 해석 |
|---|---|---|---|
| R-H mode | 1 | 9.474 | 시험이 잡음 |
| R-H owner | 1 | 8.853 | 시험이 잡음 |
| R-H directory | 1 | 8.739 | 시험이 잡음 |
| R-H absolute HOME | 1 | 9.080 | 시험이 잡음 |
| R-H 최종 symlink | 0 | 7.706 | 남아 있는 directory 검사가 같은 입력을 거절함 |
| R-F mode | 1 | 7.572 | 시험이 잡음 |
| R-F owner | 1 | 7.353 | 시험이 잡음 |
| R-F O_NOFOLLOW | 1 | 6.933 | 시험이 잡음 |
| R-F regular file | 0 | 12.951 | directory를 읽을 때 OSError로 거절됨 |
| R-F size | 0 | 12.941 | 기존 oversized 입력은 JSON·schema 검사로도 거절됨 |
| R-F content | 1 | 12.967 | 시험이 잡음 |

전체 변이 묶음 경과는 29.686초다. 동시 pytest는 최대 4개이며 단일 실행 최장은 12.967초다. rc 2 같은 수집 실패는 없었다.

크기 변이 후속 입력은 정상 키 JSON 뒤에 공백을 붙여 정확히 4097 bytes로 만든 0600 파일이다. 원본은 rc 30과 `OP_STORE_KEYS_INVALID`로 거절했다. size 검사만 제거한 임시 모듈은 키 3개를 반환했다. 후속 경과는 0.005초다. 따라서 기존 oversized 시험 하나는 크기 검사 제거를 잡지 못한다. 이는 원본 동작 반례로 세지 않은 시험의 한계다.

## 재현과 다음 수

- 추가 재현 스크립트: `/tmp/da_airag_r1_extra.py`. 저장소 root에서 `feature-pack/rag/.venv/bin/python /tmp/da_airag_r1_extra.py`로 실행한다. 모든 경로와 token은 synthetic이다.
- 변이 재현 스크립트: `/tmp/da_airag_r1_mutations.py`. 같은 Python으로 실행한다. package 사본과 상대 HOME 입력의 생성물도 임시 directory 안에 둔다.
- 남은 것: 동작 반례 1건과 형식 2건을 구현 좌석이 처리한 뒤, 같은 R-H·R-F 범위로 2회차 판정을 받는다. 크기 제한 시험의 빈틈도 위 후속 입력으로 확인할 수 있다.
- build.sh 상한, test_probe_opa 간헐 실패, 앱 아래 실제 실행은 발주에서 제외됐으므로 시험·판정하지 않았다. 새 범위 밖 지적은 0건이다.
- 실제 op 실행 0, 키체인·launchd·앱 조작 0, 설치본 쓰기 0, 저장소 코드 수정 0, commit·push 0. 저장소 산출물은 이 판정 파일 1개다.
