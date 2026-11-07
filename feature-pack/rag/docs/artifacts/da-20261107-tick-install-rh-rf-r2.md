최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 — C12. 카드 airag-tick-op-7s 끝 줄 6(설치본 tick.py 교체 h) 앞 코드 DA 2회차 — 범위 = R-H·R-F(1회차 REJECT 수정 확인 포함).

시험 단계별 초: R-H 15.085 / R-F 13.779(기본 두 묶음 병렬) / 1회차 재현 0.033 / 수정·HOME alias·mkdir 전 경합 0.011 / 설치본 호환 0.079 / 변이 14.964 / mkdir 뒤 경합 0.005. 단일 시험 70초 이내, 변이 동시 최대 4개.

REJECT — 동작 반례 1 / 형식 0 / 범위 밖 0.

2026-11-07, aifp-airag-da-codex#5, GPT-6.1 Sol. 1회차의 정적 재현 3건은 모두 해소됐다. 발주문 §볼 것 0에 지정된 상위 경로 교체 경합에서는 같은 HOME 격리 계약이 깨진다. 새 동작 기준을 추가하지 않았다.

## 대상과 변경 확인

- 고정 대상과 작업 시작 HEAD는 `b193b054de1e0c3f5d942d103f24f7c17c55d765`다. tick.py와 reason_codes.py의 `git diff b193b054 -- ...` 출력은 없었다.
- 1회차 대상 13b35ce9와 비교하면 tick.py 추가 13줄이다. 상위 symlink 검사, 파일 내 키 중복 검사, R-H 고정 stderr 안내가 추가됐다.
- 설치본 대비 읽기 전용 diff는 tick.py 추가 115줄·삭제 4줄, reason_codes.py 추가 2줄이다.
- 범위는 R-H·R-F와 1회차 지적 수정이다. 7초 상수, build.sh 상한, test_probe_opa, 앱 아래 실행은 판정하지 않았다.

## 1회차 지적 처리 결과

| 1회차 지적 | 이번 실측 | 판정 |
|---|---|---|
| 기존 상위 symlink로 HOME 밖 이탈 | rc 30, OP_HOME_INVALID, stderr 1줄, op 0회, 외부 생성 없음 | 정적 입력 해소 |
| R-H 실패 stderr 누락 | rc 30, OP_HOME_INVALID, stderr 1줄, op 0회 | 해소 |
| 동일 키 파일의 이유 코드·안내 불일치 | rc 30, OP_STORE_KEYS_INVALID, stderr 1줄, op 0회 | 해소 |
| 크기 검사 제거를 기존 oversized 시험이 못 잡음 | 새 4097 bytes 단일 시험이 size 변이를 rc 1로 검출 | 시험 한계 해소 |

원본 `/tmp/da_airag_r1_extra.py`를 재실행하면 첫 parent_symlink 입력에서 TickError(30, OP_HOME_INVALID, symlink)가 발생한다. 이는 수정된 거절 동작이며 나머지 사례가 실행되지 않으므로, 같은 synthetic helper를 재사용한 `/tmp/da_airag_r2_extra.py`로 세 지적을 각각 측정했다.

## 남은 동작 반례 1: 경로 검사 뒤 상위 directory가 교체되면 격리가 깨진다

재현 입력 1줄: 정상 임시 HOME과 credentials를 두고, `tick.py:350` 검사 뒤 `353`행 mkdir 직전에 `.config/airag`를 다른 이름으로 rename한 뒤 HOME 밖 임시 directory로 symlink 교체하고 `load_keys`를 계속 실행한다.

- 위치: `feature-pack/rag-consumer/src/airag_consumer/tick.py:350`~367. 검사 시점의 realpath를 확인한 뒤, mkdir·lstat와 자식 HOME 전달에 같은 문자열 경로를 다시 사용한다. 최종 항목의 lstat는 상위 symlink를 따라간 결과만 검사한다. 자식 HOME 전달은 410행이다.
- 기대: 상위 경로가 HOME 밖을 가리키도록 교체돼도 외부 op-home을 만들거나 그 경로에서 op를 호출하지 않는다. 안전하게 거절하는 경우 rc 30, OP_HOME_INVALID, op 0회다.
- 실제: 외부 directory에 op-home을 만들고 load_keys가 성공한다. 가짜 op를 3회 호출하며, 호출 당시 자식 HOME을 resolve하면 real HOME 밖이다.
- 실측: `parent_race {"result": "success", "op_calls": 3, "resolved_child_HOME_outside": true, "switched": true, "outside_created": true}`.
- 고쳐야 할 동작: 상위 경로 교체가 검증과 생성·op 사용 사이에 끼어도, 검증한 HOME 안의 directory만 사용하거나 OP_HOME_INVALID로 실패해야 한다. 검사 뒤 동일 pathname을 다시 따라가며 외부 생성을 허용하지 않는다.

시험은 실제 경쟁 프로세스의 교체가 끼어들 순서를 고정했다. 시험용 os.mkdir wrapper가 최종 target 호출에서만 parent를 rename하고 symlink로 한 번 교체한 뒤 원래 os.mkdir를 실행했다. filesystem의 변경과 최종 directory 생성은 실제 작업이다. 검사 결과나 키 값을 위조하지 않았다. subprocess.run만 synthetic 함수로 바꿨다. `switched=true`로 교체가 실제 실행됐음을 함께 확인했다.

발주문에 지정된 mkdir 뒤 조건도 별도로 확인했다. HOME 밖에 정상 0700 op-home을 미리 두고, 최종 target의 lstat 직전 wrapper에서 parent를 같은 방식으로 한 번 교체했다. 결과는 `POST_MKDIR_RACE {"switched": true, "op_calls": 3, "resolved_child_HOME_outside": true}`다. 같은 원인의 실행 순서이므로 별도 반례로 중복 집계하지 않았다.

## 정상 경로와 회귀 확인

| 항목 | 결과 |
|---|---|
| R-H 기본 파일 | 23 passed, pytest 14.01초, 호출 전체 15.085초 |
| R-F 기본 파일 | 36 passed, pytest 12.66초, 호출 전체 13.779초 |
| real HOME 자체가 symlink | 정상 성공, 가짜 op 3회, resolved HOME 이탈 없음 |
| HOME 안에 머무는 상위 symlink | 기본 시험 통과 |
| 없음·mode·owner·최종 symlink·상대 HOME | 기본 R-H 시험 통과, 오류 코드와 op 0회 확인 |
| 키 파일 없음·mode·owner·비일반 파일·내용 오류 | 기본 R-F 시험 통과, 고정 코드와 fallback 0 확인 |
| 키 파일 4096/4097 bytes | 새 경계 시험 통과, 4097 size 변이 검출 |
| store_keys_file 설정 없음 | 설치본과 현재 소스의 op argv·reference·token·나머지 자식 환경 동일, 각각 호출 3회 |

설정 없음 비교에서는 의도된 R-H 자식 HOME 차이만 제외했다. 최종 키 환경도 설치본과 같았다. 실제 op는 실행하지 않았으며 임시 token만 읽었다. R-H에는 별도 off 설정이 없다는 1회차 해석을 유지했다.

기본 명령은 발주문 그대로 rag-consumer에서 실행했다. 각 pytest subprocess에 timeout 70초를 뒀다. 9파일 전체 회귀는 이번 범위에서 재실행하지 않았다.

## 검사 제거 변이

`/tmp/da_airag_r1_mutations.py`의 runner와 원래 변이 11개를 재사용했다. size 변이의 선택 시험만 새 4097 bytes 시험으로 바꿨다. 수정된 검사와 안내를 확인하는 변이 4개를 더해 총 15개를 임시 package 사본에서 실행했다. 저장소 코드는 수정하지 않았다.

| 제거한 검사·동작 | pytest rc | 경과 초 |
|---|---|---|
| R-H mode | 1 | 4.553 |
| R-H owner | 1 | 4.246 |
| R-H directory | 1 | 4.342 |
| R-H absolute HOME | 1 | 4.745 |
| R-H 최종 symlink | 0 | 3.475 |
| R-F mode | 1 | 3.407 |
| R-F owner | 1 | 3.368 |
| R-F O_NOFOLLOW | 1 | 3.355 |
| R-F regular file | 0 | 3.615 |
| R-F size, 새 4097 bytes 시험 | 1 | 3.593 |
| R-F content | 1 | 3.421 |
| R-H 생성 전 parent symlink 검사 | 1 | 3.358 |
| R-H parent mkdir 뒤 경계 재검사 | 0 | 3.530 |
| R-F 파일 내 키 중복 | 1 | 3.530 |
| R-H stderr 안내 | 1 | 3.536 |

12개는 시험이 검출했다. 생존한 3개 중 최종 symlink와 regular-file 변이는 다른 검사에서 같은 입력을 거절한다. parent mkdir 뒤 재검사 변이는 정적 symlink 시험이 앞선 검사에서 이미 실패하기 때문에 생존했다. 기존 시험은 이번 경합 실행 순서를 다루지 않는다. 수집 실패(rc 2)는 없었다. 전체 14.964초, 동시 최대 4개, 단일 변이 최장 4.745초다.

## 재현과 다음 수

저장소 root에서 `feature-pack/rag/.venv/bin/python /tmp/da_airag_r2_extra.py`로 수정 결과, HOME alias, mkdir 전 경합을 재현한다. `feature-pack/rag/.venv/bin/python /tmp/da_airag_r2_mutations.py`로 변이 15개를 재현한다. 두 파일은 1회차의 synthetic helper·runner를 재사용한다.

남은 것은 상위 경로 교체 시 HOME 격리를 지키는 동작 1건이다. 수정 뒤 같은 반례와 기준으로 3회차를 검증한다. 카드의 DA 호출 상한은 3회이며, 3회차 뒤 추가 DA 호출로 넘기지 않는다.

새 범위 밖 지적은 0건이다. 실제 op·키체인·launchd·앱 실행 0, 설치본 쓰기 0, 저장소 코드 수정 0, commit·push 0. 저장소 산출물은 이 판정 파일 1개다.
