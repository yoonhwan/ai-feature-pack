골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

골의 어느 축인가: A03 — C12 권한 팝업/간헐 타임아웃 해결. P1(h92, 10-16 17:52 오빠 직접 실행 rc=0) 결과 해석 + r14 §2.4 후보 자격 충족에 따른 «운영 plist ProcessType 변경 설계» = 설계 r15. (산출: arch-20261016-opa-popup-design-r15.md · 작성: ft-airag-arch-claude#2 · 발주 #2648·#2650(Master#5) · 설계만, `op` 실행 0, 운영 plist·설치본은 읽기 전용 · r14 DA 가 수용한 사전 기준은 바꾸지 않는다)

# 0. 결론 (먼저 읽기)
1. **P1 은 r14 §2.3 의 호출 1 = A × 호출 2 = a → 쌍 판독 R1 — Master 판독에 동의.** 두 폴더를 직접 읽어 적격(a~g)·H0/H1 비해당을 대조했다. 후보 자격은 사전 기준대로 **충족**(위치 1 × 지정 안 함 적격 관측 2/2 기한 안: 360ms·1053ms). 이것은 «운영 plist 변경 설계를 시작할 자격»이고 **해결·원인 확정·효과 보증이 아니다.** 팝업은 h67·h87·h88·h92 4회 모두 «없음»(부재의 보장 아님).
2. **정정 1건(내 r13 문장):** r13 §2.2 의 「P4 도 두 집합이 겹치지 않는다」는 P1 로 **더 이상 성립하지 않는다**(지정 안 함 P4 최대 855ms > Background P4 605·707·790·834·847ms). P0 만 두 집합이 분리된 채다(지정 안 함 최대 1053ms < Background 최소 2449ms). 새 임계는 만들지 않는다.
3. **운영 plist 변경 설계(§2):** 현재 운영 plist 는 `ProcessType=Background`, 파일 수정 시각 10-02 15:22 이후 변경 기록은 확인하지 않았고, 그 plist 로 ok/degraded 틱과 key_error 틱이 **둘 다** 나왔다(§2.2) → 변경은 **효과 미보장의 가설 검증용 구성 변경**이다. 변경 대상 값 기본안 = **키 제거(= 측정한 「지정 안 함」과 같은 구성)**, 명시 `Standard`·`Adaptive`·`Interactive` 는 미측정이라 기본안이 아니다. plist 는 휠(런타임) 재설치와 **별개 산출물**이라 **재설치를 두 번 하지 않는다**: R-2(휠) → plist 편집(키 줄 제거) → R-4 의 bootstrap 때 처음 적용(현재 disabled·미적재). 집행은 오빠 HIL + 집행 스크립트 DA + 합성 시험 뒤이며 **이 설계는 집행·재개를 승인하지 않는다.**
4. **재개 조건 갱신(§3):** R-3 앞 가지 관측 6건(581·2449·360·3626·1053·5427ms)·기한 초과 3건 병기, R-3 문구 불변, 재개 미승인 이유는 R-2·R-4. plist 변경은 **새 재개 조건이 아니라** 선택 경로이며 R-4 고지에 «변경했는지 여부»를 적는다.

# 1. P1 결과 읽기 (질문 1)
## 1.1 직접 대조 (내가 폴더를 독립으로 읽은 값)
| 호출 | 폴더 | ProcessType(`profile.json` / `job.plist` 키) | P4 | P0 | tcc | 부하 전→후 |
|---|---|---|---|---|---|---|
| 1 (지정 안 함·위치 1) | `20261016-175215-56381-17170` | false / 키 0개 | success 855ms | **success 1053ms** rc 0 reaped | none_logged_ok | 10.42/10.73/10.60 → 9.67/10.56/10.55 |
| 2 (Background·위치 2) | `20261016-175221-64448-22831` | true / `Background` | success 605ms | **success 5427ms** rc 0 reaped | unknown_log_unavailable(`tcc_unknown=true`) | 9.67/10.56/10.55 → 9.09/10.41/10.49 |
- 두 폴더 모두 `complete=true`·`aborted_class=None`·`timed_out_wait=false`·`conclusion=cause_unconfirmed`·단계 배열 P4·P0·P2·P1·P1b 각 1회·P2/P1/P1b `skipped_not_applicable`·`profile.json` 닫힌 키 5개. 원장 `p1-attempts.log` 는 `ATTEMPT_START n=1`·`ATTEMPT_END call1_rc=0 … call2_rc=0` 와 두 폴더 경로가 일치(시도 1/2 소모, 2회째 없음).
- **판독:** 호출 1 = **A**(적격·P4 success·P0 success), 호출 2 = **a**(적격·P4 success) → 자격 **충족**, 쌍 판독 **R1**(호출 2 P0 success). 시스템 상태 병기(실행 직후 내 조회): `vm.swapusage` used 6163MB/7168MB(D2 때 5735MB), `pgrep -x op` 26 불변.
## 1.2 R1·자격이 말하는 것 / 말하지 않는 것
| 말하는 것 | 말하지 않는 것 |
|---|---|
| 이번 쌍에서도 두 호출의 `op --version` 이 기한(7초) 안에 끝났다 · 위치 1 × 지정 안 함 적격 관측이 2/2 기한 안 · 사전 기준(r14 §2.3 A 행)이 충족 · 팝업 «없음» 4회 | 해결됨 · 재현이 사라짐 · 지정 효과나 첫 작업 효과의 방향 확정 · 후보 자격=변경의 효과 보증 · P0 success=키 읽기 성공·팝업 방지 |
- **호출 2 의 5427ms:** 기한 7000ms 의 약 78%로 이번 표본에서 기한에 가장 가까운 success 다. R1 은 이를 읽는 행이 아니고 새 임계를 만들지 않는다. 같은 쌍의 호출 1 은 1053ms 였다(참고 수치).
- **부하·압박(연관 후보로만):** 이번 부하 10.4→9.1 은 이전 실행(N4 약 4.5~5.2, D2 약 5.8~6.2)보다 높았고 swap 사용도 컸다. 그 상태에서도 두 호출은 기한 안에 끝났다. 부하/압박과 지연의 관계는 이 표본으로 판정할 수 없다.
## 1.3 누적 표본표 9건 (r13 §2.1 갱신 · 보존 launchd 프로브 폴더)
| # | 보존 폴더 | 계획 안 위치 | ProcessType | P4 | P0 |
|---|---|---|---|---|---|
| 1 | `20261015-194459-69685-1145`(작성자 분류) | 1 | Background | success 707 | **timeout 7038** |
| 2 | `20261016-142318-12296-13417` | 1 | Background | success 847 | **timeout 7024** |
| 3 | `20261016-165901-46857-3571` | 1 | Background | **timeout 7035** | **timeout 7030** |
| 4 | `20261016-165921-59698-30085` | 2 | 지정 안 함 | success 561 | success 581 |
| 5 | `20261016-165926-61821-13809` | 3 | Background | success 834 | success 2449 |
| 6 | `20261016-172900-57073-11585` | 1 | 지정 안 함 | success 504 | success 360 |
| 7 | `20261016-172905-59849-28728` | 2 | Background | success 790 | success 3626 |
| 8 | `20261016-175215-56381-17170` | 1 | 지정 안 함 | success 855 | success 1053 |
| 9 | `20261016-175221-64448-22831` | 2 | Background | success 605 | success 5427 |
## 1.4 위치 × 지정 4칸 (P0 지표 · 9건)
| | Background 지정 | 지정 안 함(Standard) |
|---|---|---|
| 계획 안 위치 1 | **기한 초과 3/3**(그중 P4 timeout 1건) | **기한 안 2/2**(360 · 1053ms) |
| 위치 2 이상 | 기한 안 3/3(2449 · 3626 · 5427ms) | 기한 안 1/1(581ms) |
- 합계: Background 6건(초과 3·기한 안 3), 지정 안 함 3건(전부 기한 안, 최대 1053ms). **Background 의 기한 안 3건도 2449~5427ms 로 지정 안 함 3건(≤1053ms)보다 느리다**(P0 두 집합 분리).
- **순서 병기(통제 아님):** D2·P1 두 쌍은 모두 「지정 안 함 → Background」 순서라 이 두 쌍에서는 Background 가 항상 둘째였다. N4 는 A-B-A 였고 둘째(B)는 빠르고 셋째(A2)는 2449ms 였다. 순서 효과를 가를 쌍(Background → 지정 안 함)은 한 번도 측정하지 않았다 — 이 설계는 그 측정을 요구하지 않는다(사전 기준은 r14 §2.2 에서 상한 소진).
- **읽는 법(라벨):** 「**ProcessType 지정 여부와 연관된 관측**」. 사후 집계·다른 실행·6 대 3 불균형·Background 내부 변동(2.4초~7초 초과)·순서 미통제·다른 상태 후보가 열려 있다. **N4 association 행이 성립했다는 뜻이 아니며**(N4 는 해석 보류 그대로, D2·P1 은 R1) 원인·통계적 효과·우세/배제 판정이 아니다.

# 2. 운영 plist `ProcessType` 변경 설계 (질문 2 — 집행은 범위 밖)
## 2.1 읽기 전용으로 확인한 사실 (값 비출력: 환경 값·경로 값 미기록)
| 항목 | 사실 |
|---|---|
| 운영 plist | `~/Library/LaunchAgents/com.airag.consumer.plist`, 수정 시각 **10-02 15:22**. 키: `Label`·`ProgramArguments`(런타임 python `-m airag_consumer.tick --config … --credentials … --log-dir …`)·`StartInterval=300`·`RunAtLoad=true`·**`ProcessType=Background`**·`EnvironmentVariables`(이름 `PATH` 하나)·`StandardOutPath`·`StandardErrorPath`. `KeepAlive` 없음 |
| 상태 | launchd 에 **미적재**(`launchctl list` 0건), `launchctl print-disabled` 에 `com.airag.consumer => disabled` |
| 리포 템플릿 | `feature-pack/rag-consumer/ops/com.airag.consumer.plist.template` — 헤더에 「Template only … save as … and load it yourself」, 같은 키 구성이며 `ProcessType=Background` 포함. 템플릿 시험 `tests/test_tick.py::test_plist_template_is_a_placeholder_only_five_minute_job` 은 플레이스홀더 4개·Label·StartInterval·RunAtLoad·ProgramArguments[1:3]·`KeepAlive` 부재만 단언하고 **`ProcessType` 은 단언하지 않는다** |
| 설치 절차 | 운영 plist 를 만들거나 갱신하는 **설치 스크립트는 리포에 없다**(템플릿을 채워 사람이 두고 적재). 런타임은 휠 재설치 방식(`~/.local/share/airag/runtime` 비 editable 복사본; 과거 재설치 기록 `runtime.bak-*` 4개) |
| 설치본 대 소스 | `airag_consumer/*.py` 를 설치본과 바이트 비교하면 **`tick.py` 만 다르다**(설치본: `timeout=30` 호출 1곳 — 소스: `OP_ATTEMPT_TIMEOUT_S=7.0`·`OP_CALL_DEADLINE_S=14.0`). 즉 R-2 의 차이는 `tick.py` 한 파일 |
## 2.2 변경의 근거와 한계 (과장 금지)
- **근거(관측):** §1.4 — 지정 안 함 3건은 모두 기한 안·최대 1053ms, Background 6건은 3건 기한 초과·나머지도 ≥2449ms. 위치 1(첫 launchd 작업) 칸에서 Background 3/3 초과 대 지정 안 함 2/2 기한 안.
- **한계(관측):** 운영 틱 이력(`~/.local/share/airag/logs` 틱 로그, 날짜별 상태 건수만 읽음): 10-02 ok 6·key_error 1·runtime_error 1, 10-11 degraded 3·key_error 6, 10-12 degraded 40·key_error 212, 10-13 degraded 21·key_error 13. 운영 plist 의 수정 시각은 10-02 15:22 이므로(내용 동일 여부는 파일 수정 시각 이외로 확인하지 않음) **같은 `ProcessType=Background` 구성에서 ok/degraded 틱과 key_error 틱이 모두 관측됐다.** 따라서 `ProcessType` 하나가 운영 틱 실패를 결정한다는 자료는 없고, 이 변경은 **효과를 보증하지 않는 가설 검증용 구성 변경**이다. 프로브의 `op --version` 은 운영 틱의 키 읽기 명령과 다른 호출이다.
- **자격의 의미(r14 §2.4):** 설계를 시작할 자격. 변경 집행·재개·원인 확정을 허가하지 않는다.
## 2.3 변경 대상 값 후보 대조
| 후보 | 측정 근거 | 비고 | 판단 |
|---|---|---|---|
| **(a) 키 제거(「지정 안 함」)** | 프로브 `unset` 3건과 **같은 구성**(job.plist 에 키 없음, 독립 대조) | man `launchd.plist(5)` ProcessType: 「If left unspecified, the system will apply light resource limits … Standard jobs are equivalent to no ProcessType being set」 — **제한 해제가 아님** | **기본안** |
| (b) 명시 `Standard` | 측정 없음 | man 상 키 없음과 동치이나 이 구성은 측정한 적 없다 | 이득 없음 — 기본안 아님 |
| (c) `Adaptive` | 측정 없음 | XPC 활동에 따라 Background↔Interactive 이동(man) | 후보 아님 |
| (d) `Interactive` | 측정 없음 | man: 「앱과 같은 자원 제한, 즉 없음 … 앱의 응답성이 그에 의존할 때만」 — 백그라운드 5분 주기 작업의 용도가 아님 | 후보 아님 |
| (e) 유지(`Background`) | 운영 이력상 ok/degraded 시기 존재(§2.2) | 변경 0 — P3 경로(§3) | **병행 선택지**(변경 안 하고 재개 경로로) |
- **권고(설계 판단, 승인 아님):** 변경한다면 (a)만. 값은 측정한 구성과 동일해야 «측정 → 운영»의 해석이 이어진다.
## 2.4 변경 절차 설계 (집행 아님 · 순서가 핵심)
**재설치를 두 번 하지 않는 순서:** 휠(R-2)과 plist 는 **서로 다른 산출물**이다. plist 변경은 휠 재설치를 필요로 하지 않고, 휠 재설치는 plist 를 건드리지 않는다. plist 는 launchd 가 **적재 시점에** 읽으므로(현재 미적재·disabled) 파일 편집은 **R-4 의 bootstrap 때 처음 적용**된다 → 편집은 bootstrap 이전 어느 때든 가능하고, R-2 와 순서가 서로 바뀌어도 상관없다. 단 둘 다 R-4 이전에 끝나야 한다.
1. **S0 백업(파일 복사 + 해시):** 운영 plist 를 백업 위치에 복사하고 sha256 을 기록(값 비출력). 백업이 없으면 S2 로 가지 않는다.
2. **S1 R-2:** 기존 재설치 절차(HELM·사용자 확인)로 `tick.py` 7.0/14.0 반영, 설치 모듈 해시=HEAD 소스 확인. (plist 와 독립)
3. **S2 편집(오직 `ProcessType` 키·값 줄 제거):** 편집 전후 대조 — ① 키 이름 목록의 차이가 정확히 `ProcessType` 하나 ② 나머지 키의 값 해시 불변(`ProgramArguments`·`StartInterval`·`RunAtLoad`·`EnvironmentVariables`·`StandardOut/ErrPath`) ③ `plutil -lint` 통과 ④ 환경·경로 값은 화면·로그에 출력하지 않는다. 하나라도 어긋나면 백업으로 되돌리고 중단.
4. **S3 템플릿 동기화(별도 코드 승인 후속):** 리포 템플릿이 `Background` 인 채면 다음 재설치 때 값이 되돌아갈 수 있다(드리프트). 템플릿 수정과 시험 보강(`ProcessType` 키 부재 단언)은 **코드 변경**이라 별도 구현 승인 + DA + 시험 대상이며 이 설계가 하지 않는다. 집행 전에 템플릿을 같이 바꿀지 순서는 Master 가 정한다(설계상 권고: 운영 plist 집행 전 템플릿 커밋).
5. **S4 R-4 재개:** 오빠 재개 승인 뒤 기존 경로(enable→bootstrap)로 적재 → R-5 관찰.
**되돌림:** bootstrap 이전이면 백업 plist 파일 복원만으로 충분(적재된 적 없음). 적재 이후 되돌림은 bootout 이 필요해 **기존 HIL 경로**(HELM·planner → 오빠)다.
**변경 후 관찰(R-5 연결):** 24틱 전체 창·3틱 조기 확인·연속 6틱 exit 30=중단 «후보»·중단 집행은 기존 HIL(r10 §6 그대로, 숫자는 초안). **그 관찰을 «변경 효과»로 읽지 않는다** — 대조군이 없고 같은 계정·시스템 상태가 이전과 같다는 보장도 없다. 라벨은 「지정 안 함 구성에서의 틱 관측: 성공/degraded/exit 30 연속 길이/팝업 보고」까지.
## 2.5 집행 스크립트·오빠 고지·DA 심사 범위
- **집행 방식:** 운영 plist 는 리포 밖(`~/Library/LaunchAgents`)이므로 집행은 **오빠 HIL 1건**(`! bash /tmp/h<N>` — Master 가 `ft-hil.sh --add`, 넘기기 전 경로·전제 `test -f`·`bash -n`·대화형 프롬프트 0 실측)으로 한다. 스크립트 내용 = S0 백업·S2 편집·검증 출력(키 이름 목록·PASS/FAIL 만, 값 비출력).
- **DA 심사 범위(별도):** ① 이 설계 ② 집행 스크립트(코드): 편집이 정확히 한 키뿐인지·백업 선행·실패 시 복원·운영 파일 접촉이 의도한 한 파일뿐인지·`launchctl` 호출 0(적재·해제를 하지 않음) ③ 합성 시험(복사본 fixture plist 로 실행): 정상 편집 / 이미 키 없음(무변경·성공) / 키가 둘 이상·형 이상 / 백업 실패 → 편집 0 / lint 실패 → 복원 / 다른 키 값 변경 감지 / 운영 파일 경로 접촉 0(시험 모드) / 출력에 값 센티넬 0.
- **오빠 고지 초안(집행 시점에 확정):** 「운영 consumer 설정 파일에서 작업 종류 지정(Background) 한 줄을 지웁니다(시스템 기본으로 돌아가며 가벼운 제한은 남습니다). 지금은 꺼져 있고 적재되지 않아 바로 달라지는 것은 없고, 재개할 때 처음 적용됩니다. 원본은 백업해 둡니다. 효과가 있는지는 모르며 재개해도 팝업·지연이 생길 수 있습니다.」
## 2.6 승인표 (r14 §2.5 갱신 행)
| 항목 | 지금? | 필요한 승인 |
|---|---|---|
| P1 결과 읽기 | 완료(R1, 자격 충족) | 없음 |
| 운영 plist 변경 «설계» | 이 문서 | 설계 DA |
| 집행 스크립트 구현·합성 시험 | 설계 DA PASS 후 | 코드 승인(Master 발주) + 구현 DA |
| 운영 plist 편집 집행 | **불가** — DA·시험 뒤 | **오빠 HIL 1건** |
| 템플릿 동기화(S3) | 후속 | 코드 승인 + DA |
| R-2 휠 재설치 | 별도 절차(plist 와 독립) | HELM·사용자 확인 |
| 재개(enable/bootstrap) | **미승인** | R-4 오빠 HIL |

# 3. consumer 재개 조건 R-1~R-5 (질문 3)
| # | 조건(r10 §6 원문 유지) | 현재 | 비고 |
|---|---|---|---|
| R-1 | 서버 18703·18712 LISTEN + `/v1/models` 200 | Master 보고상 충족 | 이 설계는 운영 HTTP 를 확인하지 않음. 재개 직전 재확인 |
| R-2 | 설치본 I-1(7.0/14.0) 반영 + 설치 모듈 해시=HEAD 소스 | **미충족** | 설치본과 소스의 차이는 `tick.py` 한 파일(§2.1) |
| R-3 | launchd 컨텍스트 `op` 호출 기한 안 완료 관측 **또는** 오빠의 «막히는 상태로 재개해 위험 관찰» 판정 | **앞 가지 관측 6건 확보**, 기한 초과 3건 병기 | R-3 문구·충족 기준 변경 없음. 증거: 581·2449·360·3626·1053·5427ms(기한 안) / 7038·7024·7035+7030(초과). 대표성·안정성은 미해결, 충족 판정에 쓰지 않음. P0 success≠키 읽기 성공·팝업 방지 |
| R-4 | 팝업 가능성·범위 한정 고지를 받은 오빠의 재개 승인 | **미충족** | 고지에 «운영 plist 변경 여부(변경 시 §2.5 고지)» 포함 |
| R-5 | 24틱 전체 창·3틱 조기 확인·연속 6틱 exit 30=중단 후보·집행은 기존 HIL | 재개 후 적용 | 숫자는 초안 |
- **결정:** 재개 **미승인** — 이유 R-2·R-4. plist 변경은 새 재개 조건이 아니다.
- **다음 한 걸음(병렬 가능한 두 줄, 순서 무관):** ① **R-2** 휠 재설치 절차(HELM·사용자 확인) ② **plist 선택 경로**: (i) 설계 DA → 집행 스크립트 구현·시험·구현 DA → 오빠 HIL, 또는 (ii) 변경 없이 Background 유지로 R-4 로 진행(P3). 어느 쪽이든 R-4 오빠 판정은 별도. 오빠께 올릴 질문은 한 번에 1개이며, 지금 오빠 차례인 질문은 없다(Master 가 DA 결과에 따라 올림).
- **`op` 프로세스 수:** `pgrep -x op` 26 불변, `s0.op_process_count` 26 불변(정의=`op` 전체 프로세스 수, daemon 전용 아님). 별건 기록 유지(r14 §3).

# 4. 7초 룰 (변경 없음)
이 설계는 새 측정을 요구하지 않는다. 기존 상수(`OP_ATTEMPT_TIMEOUT_S=7.0`·`OP_CALL_DEADLINE_S=14.0`)를 바꾸지 않는다. 7초 밖 측정은 오빠 결정으로만 별도 상신.

# 5. 미확인 (r14 유지 + 추가)
r14 §6·r13 §7·r12 §5 전부 유지. 추가: 운영 plist 내용이 10-02 15:22 이후 바뀌지 않았는지(수정 시각 외 확인 없음) · 운영 틱이 launchd 에서 «첫 작업»과 같은 조건인지 · `ProcessType` 제거가 운영 틱에 미치는 효과 · 템플릿·운영 plist 드리프트 시 재설치 절차 · P1 호출 2 `tcc_observation` 이 unknown_log_unavailable 인 이유 · 팝업 «없음» 4회의 조건(10-13 11:44 팝업 재현 조건 미확인).

# 6. 상태 요약
| 항목 | 상태 |
|---|---|
| `op` 실행(이 설계 작업) | **0** (보존 폴더·소스·plist 키 구조·틱 로그 건수·man 읽기만 — 값·토큰 0) |
| 프로브·chain·E1·S2·tick 코드 | 변경 0 |
| 운영 plist · runtime.json · 설치본 · 운영 DB | 변경 0 (읽기만) |
| consumer | disabled·미적재 유지 · 재개 미승인(R-2·R-4) |
| P1 | R1 · 후보 자격 충족(설계 시작 자격) · 시도 1/2 소모, 2회째 없음 |
| 팝업 | h67·h87·h88·h92 4회 «없음»(부재의 보장 아님) · (가) 팝업과 (나) 타임아웃의 동일 원인 증거 없음 |

# 7. DA 패턴 선점검
| 패턴 | 점검 | 결과 |
|---|---|---|
| 마감 전파 | 새 시간·횟수 | 새 측정 없음. P1 시도 1/2 소모·2회째 없음 명시, 7초 룰 상수 불변 |
| 값 비출력 | 새로 읽은 것 | plist 는 **키 이름과 ProcessType 값**만 기록(환경·경로·인자 값 미기록), 틱 로그는 상태·exit 건수만, 프로브 폴더는 닫힌 스키마 필드. 토큰·키 값 0 |
| 고지 정확성 | plist 변경 고지 | 「제한 해제」가 아니라 「시스템 기본, 가벼운 제한 남음」, 현재 미적재라 재개 때 처음 적용, 효과 미보장·팝업/지연 가능, 효과 판정 아님 |
| 인과 과장 금지 | 누적 라벨·변경 근거 | N4 association 행 아님·원인/효과/우세 판정 아님, 같은 Background 구성에서 ok/degraded·key_error 병존, 순서 미통제, P4 분리 문장 정정, 「약화/배제/판명/우세」 표기 없음(부정문 인용 제외) |
