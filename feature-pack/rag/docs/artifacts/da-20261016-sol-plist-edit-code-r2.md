골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 1 / note 1**

`ft-airag-da-codex#1` · 2026-10-16 · 발주 #2669, 회신 `ft-airag-master-claude#5`. 기준 HEAD **`a07fe804d8aac302cc8d23ee6c8568c98f300613`**. 대상은 직전 `9842d92` 위 `3614263`·`b4a3005`·`c24dc43`·`c6da92f`·`a07fe80`의 보강분이다. **직전 M1·M2·m1·m2·m3 종결.** 새로 보고된 설계 밖 결정④의 부모 디렉터리 허용은 아래 비차단 minor로 한정한다.

이 PASS는 코드 심사이며 운영 plist 편집·설치본/runtime.json 변경·launchd 적재/해제·재개 승인이 아니다. 실제 op·운영 launchctl·운영 경로 쓰기·HTTP/DB·제품 코드 수정·서브에이전트 사용 0. Serena 정의/참조, 변경 diff, 기존 및 독립 fixture로 확인했다. 이하 P:N은 `ops/plist-edit/plist_edit.py`의 1-based 줄 번호다.

## 1. 직전 지적 종결

| 항목 | 코드·독립 재현 | 처분 |
|---|---|---|
| M1 게시 후 신호 | rename 성공 후 defer를 유지하고 신호는 pending에 기록한다. execute의 유일한 게시 후 목적지는 finish이며, 마지막 출력 뒤 pending 확인을 통과한 경우만 0. 이전 DA와 **동일한 사후 PASS 출력 순간** 및 완료 출력 순간의 INT/TERM을 재대입: 정상 복원은 각각 **130/143·원본 해시/metadata 복원**, 복원 실패 주입은 **항상 9** | **종결** |
| 복원 중 pending | 사후 오류로 복원하는 rename 순간 INT/TERM을 보내도 pending을 최종 반환에서 반영. 이전 8이 아니라 **130/143**이며 원본 복원. note의 출력 OSError 억제로 복원 보고 파이프가 깨져도 8/9 결과가 바뀌지 않음 | M1과 함께 종결 |
| M2 보호 공간 역할 교차 | plist/backup-dir 모두를 계정 DB 홈과 HOME의 LaunchAgents/운영 백업 트리 양쪽에 resolve 기준 대조. fixture의 두 교차 역할과 symlink/하위 경로 **5건**, Context 생성기를 호출하면 실패하도록 둔 상태에서도 모두 **Refuse 2**. launchctl/mkdir/chmod/쓰기 전 거부, 원본·디렉터리 mode 불변 | **종결**. 부모 공간은 아래 별도 minor |
| m1 key/value 사이 주석 | 공백 아닌 바이트가 있으면 classify에서 **종료 3**, launchctl/백업/후보 이전 명시 거부. 이전 삭제 fixture를 그대로 재대입해 바이트 불변 확인. 두 요소 바깥 주석 보존과 사이 공백 허용 시험도 통과 | **거부 선택 수용·종결** |
| m2 정상 경로 출력 | 정상 백업은 고정 PASS 문구만 출력. backup-dir 경로 센티넬을 재대입해 정상 stdout/stderr에 경로 0 확인. 복원 실패 9의 백업 위치 출력은 명시 예외로 유지 | **종결** |
| m3 유효 비-dict 루트·변이 | empty array 등 유효 plist 루트의 **3** 거부가 새 시험에 고정됨. root_unchecked 독립 재대입은 새 6종 시험에서 **3 failed/3 passed**로 탐지되어 더 이상 동치로 취급하지 않음 | **종결** |

finish의 성공/복원 분기는 분리되어 있다. 사후 검증·출력에서 문제가 생기거나 pending이 있으면 백업 복원·hash/meta 확인 뒤 코드 결정, 복원 실패는 신호보다 우선한 9다. 신호를 받은 뒤 새로운 완료 줄을 출력하지 않는 시험도 통과했다. 게시 뒤 main의 «운영 파일 불변» 경로로 빠지던 이전 재현은 사라졌다.

## 2. 인수 12항 재열거

| # | 재심 확인 |
|---|---|
| 1 | 편집 경로에서 미적재·disabled 조회가 백업/후보보다 앞. 이미 키 없음은 변경/백업 없는 성공 경로 |
| 2 | loaded·enabled·누락·조회 실패·지연은 상태 4/편집 0. 게시 직전 원본 hash 변화 거부 유지 |
| 3 | READ_VERBS=list/print-disabled 두 개, 허용 목록 검사·각 최대 7.0초·재시도 없음·stdin DEVNULL 유지. 변경 동사 실행 경로 없음 |
| 4 | 정상 최상위 문자열 Background/이미 없음으로 한정. 경로 인자는 명시 selftest에서만 허용 |
| 5 | 다른 값/형·ProcessType 중복·비-dict·파싱 실패·비일반/심링크 거부, 중첩 키 보존 유지. key/value 사이 주석은 추가 거부 |
| 6 | 허용하는 배치에서는 top-level key/value 항목만 제거하고 다른 바이트/순서/외부 주석 보존. 보존하기 어려운 사이 주석을 조용히 지우지 않음 |
| 7 | 실제 백업 복사·fsync·원본/복사본 sha256 일치 선행, 실패면 후보/게시 0. 원본 변경 검사 유지 |
| 8 | 운영 파일 아닌 같은 디렉터리 .tmp 후보에서 plutil lint·정확한 키/나머지 값 hash·metadata 검증 유지 |
| 9 | rename 한 번의 원자 게시·published 플래그 구간 신호 기록, 게시 후 finish로 연결. 중단 중 잘린 운영 파일 없음 |
| 10 | 후보·게시·복원에서 mode/uid/gid tuple 검사 유지. 백업 700/600은 구현 발주의 명시 정책 |
| 11 | 사후 bytes/shape/meta 재확인, 실패/신호/출력 예외면 원자 복원·최종 hash/meta 확인. 복원 실패 9/위치 표시 유지 |
| 12 | 정상 경로 출력 제거, 키 이름·고정 PASS/FAIL·고정 사유만 출력. 복원 실패 9의 위치 예외 및 외부 도구 원문 비반사 유지 |

생산 Context를 **실행하지 않고** 환경에 훅 14종과 CALL_S=0.001·PAUSE_FILE을 주입해 검증했다: 활성 훅 **0**, cap **7.0**, pause 파일 생성 0. 새 코드가 생산 환경의 시험 훅을 켜는 경로는 발견하지 않았다. 관련 wrapper와 직접 자식 신호/정리·종료코드 시험도 통과했다.

## 3. Nano 설계 밖 결정 4건

| 결정 | 판단 |
|---|---|
| ① 사이 주석을 보존하지 않고 거부 | **수용.** 유효 XML이어도 이 편집기가 안전하게 처리할 수 없는 배치를 명시 거부하는 보수적 입력 한정이다. 다른 바이트를 바꾸지 않으며 거부 3·변경/백업/조회 0으로 확인. 입력 범위와 사유가 문서/시험에 고정됨 |
| ② 마지막 pending 확인 이후 신호는 완료된 실행으로 처리 | **수용.** 명시적 완료 경계는 사후 검증과 마지막 출력 뒤 pending 확인이다. 그 이전 신호는 복원하며, 그 뒤는 이미 확정된 작업으로 본다. rename 직후를 완료로 잘못 간주하지 않는다. 무한히 늦은 신호까지 rollback을 약속하는 계약으로 확대하지 않음 |
| ③ 시험 pause가 pending 시 대기를 끝냄 | **수용.** 게시 후 handler가 기록만 하는 구조에서 fixture의 30초 인공 대기를 빨리 끝내는 selftest 동작이다. 생산 비활성 확인 |
| ④ 보호 공간 상위 backup-dir는 허용 | 기존 보호 트리 자체/하위/역할 교차는 종결했지만, **부모 디렉터리 mode 변경까지 안전하다는 판단은 수용하지 않는다.** 생산 고정 경로에는 해당하지 않는 비차단 selftest 경계이며 아래 minor로 기록 |

## 4. Minor 1 — selftest가 보호 공간의 조상 디렉터리를 backup-dir로 허용

Nano가 명시한 결정④를 fixture만으로 직접 확인했다. `HOME=<임시 fixture home>`으로 두고 backup-dir를 **그 HOME 자체**로 지정하면 보호 트리의 조상이지만 _inside 검사에 걸리지 않는다. make_backup이 기존 디렉터리에 chmod 700을 하므로 **fixture HOME mode 755→700**, 백업 생성, rc=0이었다. 실제 홈/운영 파일은 건드리지 않았다.

생산 모드는 경로 인자를 받지 않고 고정 backup leaf를 쓰므로, 이 문제로 정상 생산 경로의 major를 재개방하지 않는다. 다만 «보호 트리 안에 없으니 안전하다»는 설명은 부족하다. 사용자가 selftest backup-dir에 실제 홈·Library·.local/share 같은 조상을 넣으면 그 디렉터리의 mode를 바꿀 수 있다.

**보완:** chmod 대상인 backup-dir는 보호 공간 그 자체/하위뿐 아니라 그 **조상**인지도 거부하거나, selftest에서 검증된 전용 fixture 디렉터리만 생성·권한 설정하도록 제한할 수 있다. fixture HOME·Library·.local/share 조상 사례에서 mode/쓰기/조회 불변을 확인한다. 그 전까지 selftest는 전용 임시 fixture만 넣는다는 호출자 제약을 유지하고, 전체 홈을 격리하는 sandbox라고 표시하지 않는다. 이는 사용자의 실제 홈에 부정 시험을 실행하라는 요청이 아니다.

## 5. 변이·독립 검증

Nano의 `mutate_plist_r1.py`에서 **변이 선언 91개**와 두 동치의 정확한 치환을 읽어 확인했다. nested_keys_seen_as_top_level(depth==3→>=3), post_shape_skipped(post shape만 제거·sha/meta 유지)는 직전 DA가 조건부 수용한 단일 변이와 동일하다. root_unchecked는 별도 탐지 항목으로 재분류됐다. **89탐지/2동치 전체 실행 수치는 Nano 보고**이며 이 DA의 독립 실행으로 합산하지 않는다.

이 DA는 임시 소스 복사본 **9종**을 독립 대입했다. 게시 뒤 defer 해제·pending 종료코드 무력화·backup 역할 보호 제거·사이 주석 guard 제거·정상 경로 출력 복귀·root guard 제거·사후 오류 사유 누락의 **7종이 assertion 실패로 탐지**됐다. 나머지 2종은 위 동치와 같은 치환이며 선택한 기존 시험에서 통과했다. 수집/setup 오류 0, 원본 제품 파일 변경 0이다.

- 관련 직접 실행: `../rag/.venv/bin/python -B -m pytest tests/test_plist_edit.py tests/test_tick.py::test_plist_template_is_a_placeholder_only_five_minute_job -q -p no:cacheprovider` → **145 passed in 59.73s, rc=0**(plist 144+템플릿 1).
- 독립 이전 반례 재대입: `/tmp/airag-plist-da-r2-independent.py` → **rc=0**. 신호 2종×출력 2지점×복원 정상/실패 8건, 복원 중 신호 2건, 보호 경로 5건, 주석 거부·정상 경로 비출력·비-dict 5종·생산 훅을 확인. summary: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-plist-da-r2-independent-0_k19c66/summary.json`.
- 독립 변이: `/tmp/airag-plist-da-r2-mutations.py` → **rc=0**. 9종/7탐지/2기존 동치와 같은 선택 시험 생존. 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-plist-da-r2-mutations-ro928490/`.
- 부모 경계 fixture: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-plist-r2-parent-_4fvp08d/parent-summary.json`에 mode 변화 기록. 운영 접촉 0.

**note 1 — 전체 회귀는 Master 병행 실행과 분리한다.** 이 판정 작성 시 `regress-a07fe80-20261016.log`에는 완료 요약이 없고 전체 회귀가 진행 중이다. 관련 145개 통과를 전체 회귀 통과로 표시하지 않는다. Master 최종 결과가 도착하면 그 결과를 병기해 집행 전 판단에 사용해야 한다. 직전 9842d92의 N4 실패를 이번 HEAD의 실패로 옮겨 적거나, 부하 원인으로 확정하지 않는다.

기존 major의 종결로 후속 h 파일 준비를 진행할 수 있으나, 실제 집행은 여전히 별도 오빠 HIL이다. h 파일에서 생산 고정 경로·관련 시험/최종 회귀의 상태·값 비출력·신호/복원 코드 전달을 확인하고, selftest에는 전용 fixture만 사용한다. consumer 재개 R-4와 템플릿 동기화는 별개다.
