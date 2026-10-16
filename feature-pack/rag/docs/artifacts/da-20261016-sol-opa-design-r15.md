골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 3 / note 1**

`ft-airag-da-codex#1` · 2026-10-16 · 발주 #2653. 대상 `arch-20261016-opa-popup-design-r15.md`, 기준 HEAD **`ab508b30d650f46f6e3da0d041ae89dc784be28b`**. **P1의 R1·후보 자격 충족 판독과 키 제거를 기본안으로 삼는 변경 설계는 수용한다.** 아래 minor는 사실 문장의 범위 보완이며 설계 PASS를 막지 않는다. 집행 스크립트는 아직 없으므로 코드·합성 시험·구현 DA가 따로 필요하다. **이 판정은 운영 plist/설치본 변경·적재/해제·재개 승인이 아니다.** 이하 R15:N은 대상 문서의 1-based 줄 번호다.

r14에서 종결된 사전 기준·시도 상한·16칸·daemon 한정·누적 라벨 범위는 재개방하지 않았다. Serena 정의·검색, 보존 JSON/plist, 설치본 바이트/AST 비교, 로그의 상태/exit 집계, 로컬 launchd.plist(5) man만 읽었다. 실제 op 실행·운영 파일 수정·설치본/runtime.json 변경·launchctl 호출·HTTP/DB·서브에이전트 사용 0. 운영 plist의 환경·경로·인자 값은 출력하지 않았다.

## 1. P1 및 9건 표본 대조

`~/.local/share/airag-probe/20261016-175215-56381-17170`과 `20261016-175221-64448-22831`을 독립 파싱했다. 두 문서는 validate_result=true·gate_n4=None(main 미호출), complete=true·중단/대기초과 없음·계정 단계 skipped/null이며 profile 기대값(false/true)과 plist 키 없음/값 Background가 맞는다.

| P1 호출 | P4 | P0 | TCC | 부하 전→후 |
|---|---|---|---|---|
| unset·위치 1 | success 855ms | success 1053ms, rc=0, reaped=true | none_logged_ok | 10.42/10.73/10.60 → 9.67/10.56/10.55 |
| Background·위치 2 | success 605ms | success 5427ms, rc=0, reaped=true | unknown_log_unavailable | 9.67/10.56/10.55 → 9.09/10.41/10.49 |

원장 p1-attempts.log는 ATTEMPT_START n=1 한 건, 두 호출 rc=0 및 폴더 대응이 일치한다. **A×a→R1, 후보 자격 충족**은 사전 기준대로다. 위치 1×unset의 적격 관측은 360/1053ms의 2/2다. 두 번째 TCC unknown은 기존 적격성 규칙상 이 결과를 H0로 바꾸지 않는다. 키 읽기 성공·팝업 방지·해결·원인 확정으로 확대하지 않은 점을 수용한다.

이전 7개를 포함한 **설계 표 9행의 P4/P0 상태·숫자 전부 일치**했다. Background 6건(P0 timeout 3/success 3), unset 3건(success 3), R-3 기한 내 관측 **6건**(581/2449/360/3626/1053/5427ms)·P0 timeout **3건**(7038/7024/7030ms)이 맞는다. A1의 P4 7035ms는 같은 폴더의 별도 단계이며 P0 표본을 하나 더 늘리는 값이 아니다.

P0는 unset 최대 1053ms < Background의 success 최소 2449ms로 관측 집합이 분리되어 있다. **P4는 이제 겹친다**(unset 855ms가 Background 605/707/790/834/847ms보다 큼). r13 문장 정정이 정확하다. 5427ms를 timeout으로 바꾸거나 새 속도 임계를 만들지 않았고, 부하·swap을 시점이 다른 연관 후보로만 남긴 점도 수용한다. swap 수치는 작성자의 직후 조회 보고이며 이 DA에서 재측정하지 않았다.

## 2. 운영 구성·설치본·로그·man 대조

| 항목 | 직접 확인한 범위와 결과 |
|---|---|
| 운영 plist | 현재 최상위 키 8개·ProcessType=Background·환경 키 PATH 하나. StartInterval=300/RunAtLoad=true/KeepAlive 없음은 일치 여부로만 확인. mtime **2026-10-02 15:22:54**. launchd의 현재 미적재/disabled는 설계 작성자·Master 보고이며 이 DA는 운영 launchctl을 호출하지 않음 |
| 템플릿·시험 | 같은 키 구성·ProcessType=Background. 헤더는 사람이 플레이스홀더를 채워 저장/적재하는 template only. test_tick.py의 해당 시험은 ProcessType을 단언하지 않음 |
| 설치본 | 설치 airag_consumer와 소스의 최상위 .py 이름 집합 **19개 일치**, 바이트 차이는 **tick.py 1개**. installed의 timeout=30 한 곳, 소스 OP_ATTEMPT_TIMEOUT_S=7.0/OP_CALL_DEADLINE_S=14.0 확인. 패키지 메타데이터 editable=false, 설치 패키지 디렉터리 symlink 아님. runtime.bak-* 4개 존재 |
| 설치 경로 역할 | 이 패키지의 wheel 설정은 src/airag_consumer를 패키징하며 운영 LaunchAgents plist 생성/갱신 훅은 발견하지 못함. 관련 ops 셸에서 확인된 plist 생성은 임시 프로브/S2용. 현재 확인 범위에서는 **휠 재설치와 운영 plist 편집은 별개 산출물** |
| 틱 집계 | 10-02 runtime_error 1/ok 6/key_error 1; 10-11 degraded 3/key_error 6; 10-12 degraded 40/key_error 212; 10-13 degraded 21/key_error 13 모두 일치. 상태/exit/시각만 사용하고 summary·오류 원문 값은 출력하지 않음 |
| launchd.plist(5) | unspecified는 light CPU/I/O limits, Standard는 키 없음과 동치, Adaptive는 XPC 활동에 따른 Background/Interactive 이동, Interactive는 앱과 같은 제한 수준이며 앱 응답성이 의존하는 경우에 쓰라는 설명이 설계와 일치 |

따라서 변경 시 **측정한 구성과 같은 키 제거**를 기본안으로 택하는 근거는 있다. man상의 동치가 명시 Standard의 실측을 대신하는 것은 아니고, Adaptive/Interactive의 효과를 추정하지 않은 것도 적절하다. 운영 틱은 키 읽기·실제 업무 경로이며 op --version 프로브와 같지 않다. 변경은 효과 미보장의 가설 검증용 구성 변경으로만 읽는다.

설치본 timeout=30은 알려진 **R-2 미반영 상태**이며 통과시킬 시간 규칙이 아니다. 이 DA는 설치본을 수정하지 않았고, 후속 R-2에서 기존 7.0/14.0 소스 반영·설치 모듈 검증을 끝내야 한다. 소스의 시간 상수 확대는 없다.

## 3. Minor 3건

**m1 — 역순 관측과 시도 종료 이유를 정확히 적는다(R15:45).** «Background→지정 안 함은 한 번도 측정하지 않았다»는 원본과 다르다. N4의 **A1(Background·위치 1)→B(unset·위치 2)**가 그 순서다. 다만 A1의 P4 timeout 때문에 **양쪽 P4 success인 적격 역순 대조를 얻지 못했다**고 쓰면 정확하다. 이를 이유로 새 측정을 요구할 필요는 없다.

같은 줄의 «r14 §2.2에서 상한 소진»도 실제 계수와 다르다. P1은 **1/2시도 소모**이고, 호출 1이 A여서 **두 번째 재시도 자격(H0c)이 없으므로 종료**한 것이다. 2회 상한을 소진했다고 쓰지 않는다. §1.1·상태표의 1/2 표기는 맞으며, 다음 실행을 열라는 뜻이 아니다.

**m2 — 과거 동일 구성은 파일 mtime을 전제로 한 추정이다(R15:59).** 로그의 ok/degraded·key_error 병존은 사실이다. 그러나 현재 파일 mtime과 현재 ProcessType만으로 과거에 적재된 plist의 내용·구성 연속성을 확정하지는 못한다. 문서가 §5에서 내용 불변을 미확인으로 둔 것은 적절하지만, §2.2는 곧바로 «같은 Background 구성에서 모두 관측»이라고 단정한다. **«현재 파일과 mtime으로 같은 구성으로 추정하나 당시 적재본/내용 이력은 미확인»**으로 한정한다. 같은 구성에서도 실패가 가능하다는 일반론은 타당하며, 이 변경의 효과 미보장 결론은 유지한다.

**m3 — 드리프트가 생기는 경로를 휠 재설치와 구분한다(R15:75).** §2.1/§2.4는 휠 재설치가 plist를 건드리지 않는다고 했는데 S3는 «다음 재설치 때 값이 되돌아갈 수 있다»고 쓴다. 현재 확인한 경로에서 휠만 다시 설치한다고 템플릿이 운영 plist를 자동 덮어쓰지는 않는다. 위험은 **나중에 이 템플릿을 재사용해 plist를 수동 재생성/재배치할 때**다. 그렇게 표현하면 S3 동기화 필요성과 R-2 독립성이 함께 성립한다. 템플릿 동기화·ProcessType 부재 시험을 별도 코드 승인·구현 DA로 다루는 경계는 수용한다.

## 4. S0~S4·되돌림·집행 범위 판단

R-2 휠과 plist는 별개라 ProcessType 제거 때문에 휠을 두 번 재설치할 이유는 없다. S0 백업 선행, S2의 정확히 한 키 제거·나머지 값 불변·lint·값 비출력, S3의 후속 템플릿 동기화, S4의 별도 R-4 enable/bootstrap이라는 구분을 수용한다. 두 경로를 택하면 둘 다 bootstrap 전에 끝내는 순서도 일관한다. 변경 없이 Background를 유지하는 선택지와 R-3 관측 확보/R-2·R-4 미충족의 병기는 유지된다.

**note 1 — 실제 집행 코드의 인수 조건은 설계 PASS와 별개다.** 집행 직전의 정지·미적재 전제를 별도 확인하고 그 확인이 없거나 상태가 달라졌으면 S2에 들어가지 않아야 한다. 집행 스크립트의 launchctl 0 계약은 유지하고, 적재된 job의 bootout/reload를 자동 추가하지 않는다. 이미 적재된 경우의 되돌림은 별도 기존 HIL 경로다. «재개 때 처음 적용» 고지는 이 전제가 유지될 때의 설명이다.

후속 구현 DA에서는 다음을 현재 명시된 fixture 시험과 함께 확인하면 된다.

- 편집 입력은 기대한 Background 또는 이미 키 없음인 정상 파일로 한정하고, 예상 밖 ProcessType 값/형·중복 키·루트 형 이상은 거부한다. 중첩된 다른 키를 제거하지 않는다.
- 원본 백업의 실제 복사·해시 일치를 확인한 뒤, 후보 파일에서 한 키 차이·나머지 값 불변·lint를 검증하고 원자적으로 게시해 중단 중 잘린 운영 파일이 남지 않게 한다. 파일 메타데이터와 실패/복원 확인도 인수 범위에 둔다.
- 정상·이미 없음·백업/lint/쓰기 실패뿐 아니라 중단·복원 실패·상태 전제 불일치·다른 키/센티넬 누출을 합성 파일로 확인한다. 운영 경로·운영 launchctl·실제 op를 fixture 시험에 사용하지 않는다.

이 항목들은 아직 존재하지 않는 코드의 결함 판정이 아니라, 예정된 구현 DA에서 구체화할 인수 사항이다. 구현·시험을 완료하기 전에 운영 편집을 승인했다는 뜻으로 이 PASS를 사용하지 않는다.

고지 초안의 «시스템 기본·가벼운 제한 남음·백업·효과 미보장·재개 시 팝업/지연 가능»은 정확하다. «한 줄»은 실제 XML의 키·값 줄 수가 아니라 **ProcessType 항목 하나**라고 표현하면 오해가 없다. 실제 h 파일은 기존 한 줄 진입로와 값 비출력·프롬프트 0 검증을 유지하고, plist 편집 HIL과 재개 R-4는 분리한다.

## 5. 증거

독립 검사 `/tmp/airag-opa-design-r15-check.py` → **rc=0**. 9행 상태·수치, P1 적격/R1, 원장 1시도, 성공 6/timeout 3, P0 분리/P4 겹침, 운영/템플릿 키 구성, 설치 모듈 19개 중 tick.py 한 파일 차이 및 시간 상수, 날짜별 틱 상태 집계를 확인했다. 운영 plist의 검사 전후 해시는 동일했다. summary: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-opa-design-r15-niu6e653/summary.json`.

문서·소스 읽기와 합성 판독만 했으며 제품 코드나 운영 파일은 바꾸지 않았다. 새 제품 회귀를 실행할 코드 변경은 없었다. 다음 구현 검토에서는 집행 스크립트·합성 시험과 위 인수 사항을 보면 되고, 종결된 P1 기준·자격 판독·R-3 문구는 다시 열 필요가 없다.
