골 원문(GOAL-LEDGER-airag.md 복붙): 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
결론 1줄: **최선의 설계 후보는 R-N(공식 Python SDK의 서비스 계정 직접 읽기)이며, 검증된 무창 운영안은 아직 없다 — HOME 격리는 시험 후보이고, 번들 연결·서명 변경·터미널 로그 0건만으로 launchd 무창을 보증하면 안 된다.**
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. 발주 #2890 · 사람 클릭 0 / 권한 창 0의 최선안 독립 DA 재판정.

작성: ft-airag-da-astra#0 · 2026-10-18 · 기준 HEAD `f61bd73e590b07ac7d16f4537fc6d0677c0708e6`. 정확한 런타임 모델명·창 크기는 노출되지 않음. Serena 사용. 상대 Fable 좌석의 이번 산출물은 읽지 않았다. 아래는 설계 검토이며 실행 성공 보고가 아니다.

## 근거 1장

**추천 1개 = R-N.** 이미 있는 서비스 계정 토큰과 `op://` 참조를 그대로 사용하고, 공식 `onepassword-sdk`의 `Client.authenticate(auth=token)` → `client.secrets.resolve(ref)`로 읽는다. CLI 자식 프로세스를 없애고 틱 종료 때 SDK도 종료한다. 새 평문 키 파일·상주 중계 서버·TCC 권한 부여가 설계상 필요 없다. Python 3.13/macOS/arm64 배포 경로도 공식 소스에 있다[S3]. 단, 네이티브 라이브러리 내부의 파일 접근·캐시·피크 RSS·실제 7초 준수는 이 맥에서 아직 확인하지 않았다. **설계 1순위이지 설치/재개 GO가 아니다.**

공식 소스 `client.py:32–37`은 `DesktopAuth`일 때만 `DesktopCore`를 만들고, 토큰 문자열이면 `UniffiCore`를 선택한다. `defaults.py`는 그 토큰을 `serviceAccountToken`으로 넘긴다. `secrets.py:18–35`는 CLI 실행 없이 `SecretsResolve`를 호출한다[S3]. 따라서 기존 R-E처럼 CLI가 앱 설정을 읽지 않기를 기대하는 것보다 원인 경로를 분리하는 근거가 강하다. SDK 버전은 고정하고 네이티브 코드까지 검증해야 한다. `op read` 실행파일 유지가 불변 계약이라면 R-N은 범위 변경이므로 채택 불가이며, 그 제약 안에서는 무창 해법이 아직 입증되지 않았다. 이번 발주가 캐시·Connect까지 비교 대상으로 둔 점에 따라 읽기 수단 교체를 설계 후보로 평가했다.

| 후보 | 클릭 0 / 창 0 | 비밀 노출면 | 재부팅 생존 | 부하·메모리 | 운영 파일 변경 | 되돌림 | 로그만으로 창 0 시험 |
|---|---|---|---|---|---|---|---|
| **R-N 공식 SDK / 추천** | 자동화 인증 지원, 이 맥 미검증 | 기존 토큰 + 틱 메모리; CLI용 환경 전달 감소, 새 의존성·코어 검증 필요 | 기존 LaunchAgent 유지; 로그인 후 자동 기동 설계 | 상주 추가 0; native/Pydantic 피크 미측정 | 키 로더·의존성 고정·설치본; plist/runtime 원칙상 유지 | 이전 설치 세트 복원; CLI 실패 경로를 자동 fallback하지 않음 | 터미널에서 가능; launchd 보증과 구분 |
| **R-H HOME + CLI 설정 격리 / 신규 구체화** | 조건부; 미시험 | 키 복제 없음; 격리 디렉터리의 CLI 캐시 생성 여부 확인 필요 | LaunchAgent 유지 | 상주 0; 기존 op 3개 | op 자식 env + 전용 빈 디렉터리 + 설치본 | env 제거; 디렉터리 정리는 별도 절차 | 터미널 A/B 가능; 요청 0만으로 무창 확정 불가 |
| R-C `OP_CONFIG_DIR`/`--config`만 | 조건부; desktop 설정까지 바뀐다는 보장 없음 | 위와 같음 | 유지 | 상주 0 | 자식 env/인자 | 원복 | 터미널 A/B 가능 |
| R-D 책임 해제 · R-S 셸 · R-E biometric=false | **기존 조합 불합격**: h39 재질문 / R-E 요청 동일 | 기존과 같음 | 기동은 생존, 읽기는 실패 | 상주 0 | spawn/env/plist | 기존 세트 복원 | 기존 증거로 탈락; 재실행 불필요 |
| R-L 임시 서명 런처 · R-P python 사본 서명 | 창 0 근거 없음; 정식 인증서도 신규 동의 면제 아님 | 비밀 복제 없음; 권한 귀속 범위 검토 | 파일은 생존 | 런처 소량 / Python 디스크 사본 | 새 실행물·서명·plist | 이전 경로 복원 | 터미널에서 실행해도 launchd 귀속 시험 대체 불가 |
| R-B `AssociatedBundleIdentifiers` | **권한 부여 키라는 근거 없음** | 기존과 같음 | plist 생존 | 상주 0 | plist | 키 제거 | 터미널로 launchd plist 효력 시험 불가 |
| R-A 앱 번들·SMAppService 로그인 항목 | 신원/관리 체계 개선 후보, 최초 동의 0 보장 없음 | 비밀 복제 없음 | 로그인 시 기동 가능; 등록·승인 상태 의존 | 작은 helper 가능; 앱 선택에 따라 상주 | 번들·등록·기동 체계 | 등록 해제·기동 복원 | 등록/TCC의 실제 귀속은 터미널 로그만으로 불충분 |
| R-Q Aqua/Background·SessionCreate·ProcessType·cron/Daemon | 세션/자원 변경 ≠ TCC grant; 클릭 0 성공 근거 없음 | Daemon/root는 오히려 권한 범위 확대 | 방식별 상이; daemon은 부팅 가능 | 상주 증분 작을 수 있음 | plist/기동 체계 | 기존 agent 복원 | 금지된 별도 기동 시험 없이는 입증 불가 |
| **R-F 0600 평문 캐시** | op 제거로 해당 원인 제거; 일반 파일 읽기는 기존 성공 | **새 평문 3키; FileVault 꺼짐; 회전·폐기 문제** | 파일 생존; 로그인 후 틱 | 추가 상주 0; 가장 가벼움 | 캐시·로더·설치본 | 캐시 비선택; 삭제는 승인 절차 | op 미호출·일반 파일 경로 확인 가능. 모든 종류의 창 0 보장은 아님 |
| R-K 키체인 / R-K0 UI 금지 API helper | 기본 security CLI는 창 가능; UI 금지는 오류 반환일 수도 있음 | 암호화 저장; ACL·잠금·새 항목 등록 검토 | 로그인 키체인 잠금 상태 의존 | 상주 0; helper 소량 | 항목·로더/helper | 이전 로더; 항목 삭제 별도 | 터미널 성공은 daemon ACL 증거 아님; 성공+무창을 함께 입증해야 함 |
| R-T/R-X Ghostty→tmux 루프 | 기존 자리 성공; 미래의 무창 보장은 아님 | 기존과 같음; 권한 귀속이 Ghostty에 의존 | **재부팅·로그아웃·tmux 정리에 취약** | 셸 소량; 터미널까지 유지하면 증가 | 스케줄러 교체 | LaunchAgent 복귀 | 현재 자리 성공 확인만 가능 |
| R-O `OP_CACHE=false`·1Password 앱 연동 설정 변경·CLI 버전 교체 | 데몬/연동 변경 ≠ 설정 파일 접근 제거; 후보별 미검증 | 변화 가능; 최신 CLI도 새 의존성 검토 | 대체로 유지 | 데몬은 기존 관측 약 4MB | env/앱 설정/CLI·설치본 | 이전 설정·버전 | env/버전은 터미널 비교 가능; 앱 설정 클릭은 금지 |
| R-V Linux 격리/원격 op·Connect | Linux 측 macOS TCC 없음; 원격 연결 인증의 무창은 별도 | 원격 토큰·통신·추가 비밀/운영면 | 외부 서비스 가용성 의존 | 로컬 VM/Connect 상주 비용 큼; 원격은 로컬 상주 작음 | 배포·네트워크·키 로더 | 기존 경로 | 호출 결과·원격 로그 가능; 새 운영 범위 커서 후순위 |
| R-Z 기존 토큰으로 암호화한 키 캐시 | op 제거 가능; 복호화 파일 I/O만 사용 | 같은 디스크에 토큰+암호문이면 탈취 방어 제한; 토큰 폐기 후에도 사본 복호화 가능 | 파일 생존 | 상주 0 | 암호 포맷·회전·로더 | 기존 경로 | 가능하나 R-F 보류를 우회할 근거로 쓰면 안 됨 |
| FDA/MDM PPPC·TCC DB 조작·앱 컨테이너 권한 변경 | 설정 승인/관리 배포 필요; 지금 클릭 0 해법 아님 | 과도한 접근권·시스템 정책 변경 | 방식별 상이 | 작음 | 시스템 권한/관리 프로필 | 정책 복원; DB 직접조작 제외 | 이번 권한 변경 금지에 따라 제외 |

※ R-F 표기는 **이번 재설계의 평문 파일 캐시**다. 이전 처방의 R-F는 FDA여서 이름이 충돌한다. 둘을 섞지 않는다. R-F는 사용자 보류이며 R-E 실패를 이유로 자동 채택할 수 없다. LaunchAgent의 재부팅 생존은 **사용자 로그인 뒤**를 뜻하며, 로그아웃 중 계속 도는 LaunchDaemon과 다르다.

## 추가 조사에서 확정된 것과 아직 모르는 것

1. **plist 번들 연결은 만능 권한 처방이 아니다.** 이 맥 `man launchd.plist`의 `AssociatedBundleIdentifiers` 설명은 정확히 “which bundles are associated with this job in the System Settings Login Items UI”다. 등록된 앱 ID를 써도 TCC grant를 생성·상속한다는 계약은 없다. 기존 Ghostty ID를 임의로 적는 방안은 타 앱 신원 차용이며 추천하지 않는다. `LimitLoadToSessionType`은 agent가 로드되는 세션 필터, `SessionCreate`는 새 audit session, `ProcessType`은 자원 제한 분류다. 현재 consumer plist는 네 키 모두 없고 환경 키는 PATH뿐이다. Apple `SMAppService` 문서는 앱 번들 안 helper의 등록·제어 기능을 설명한다[S4]. **등록/표시/세션/TCC 동의는 서로 다른 문제다.**
2. **HOME 격리를 단지 미확인이라는 이유로 버릴 필요는 없지만, 작동한다고 단정할 수도 없다.** 공식 CLI 문서는 `--config` → `OP_CONFIG_DIR` 등 우선순위를 명시하고, 홈 탐색에 go-homedir를 쓴다고 설명한다[S1]. 설치된 op 바이너리에는 `desktopsettings.Load`, `desktopAppUserDataDir`, `desktopAppSettingsPath`, `desktopAppPoliciesPath`, `os.UserHomeDir`, `go-homedir.dirUnix`와 Group Containers 문자열이 있다. 그러나 이 심볼들만으로 desktop 경로가 HOME을 따르는지, passwd/시스템 API를 쓰는지는 알 수 없다. **CLI config와 desktop config는 구분해야 한다.** 이후 승인된 시험에서는 **op 자식에만** HOME=전용 0700 일반 디렉터리, OP_CONFIG_DIR=그 아래 config를 주고 심링크 없이 비교한다. 전역 HOME이나 틱 전체 HOME을 바꾸지 않는다. 서비스 토큰/참조는 원래 절대경로에서 먼저 읽고 stdin/메모리로 넘긴다. 빈 폴더에 실제 앱 데이터를 복사하지 않는다.
3. **정식 서명 하나로 해결된다는 이전 인과 설명은 과했다.** 이미 Developer ID로 서명된 op 책임 주체에서도 h39 재질문이 있었다. python의 `-67062`·session-scoped 오류는 해당 실행의 증거이지 “인증서만 있으면 영구 허용”의 증명이 아니다. R-S의 특정 시험 실패 역시 모든 플랫폼 바이너리·cron 동작을 실측 반증한 것은 아니다. 지금은 성공 근거가 없어서 제외한다.
4. **PROMPTING 0 ≠ AppData 접근 0 ≠ 보호 경로 접근 0.** R-E의 T0/T1은 둘 다 AppData `preflight=no` 1, `authValue=2`, PROMPTING 0이었다[E2]. 터미널에 저장된 허용이 결함을 가린다. h37에서 앞 창이 떠 있을 때 뒤 호출은 요청 줄 없이 timeout했다는 관측도 있다. unified log의 누락/캐시/요청 병합/PID 귀속 차이를 배제하지 않은 “줄 수 0”은 launchd로 일반화할 수 없다. 보호 경로 접근 추적도 로그 수집 권한이 없으면 **미확인**으로 남기고, 그 권한을 얻으려고 창을 띄우지 않는다.

## 로그만으로 확인하는 시험 계획 — Master 승인 후 집행, 이 좌석은 실행 0

**공통 계약.** 기존 성공이 확인된 Ghostty→tmux 터미널 계보만 사용한다. 새 launchd 라벨·launchctl·재부팅·권한 설정·GUI 클릭은 없다. 기존 허용이 사라졌거나 실행 계보가 다르면 시작하지 않는다. 로그/프로세스 계보를 조회할 권한이 부족하면 판정 불가다. 시스템 전체 `PROMPTING` 개수를 세지 않고 실행 시작/끝 시각, PID와 자식 PID, TCC `msgID`의 ATTRIBUTION→CTX→RESULT를 연결한다. 키·토큰·stdout/stderr 원문·환경 덤프·키 해시는 기록하지 않는다. 로그에는 키 이름, 성공 여부, 형식/서로 다름 여부, 소요시간, 호출 수, RSS, 요청 수와 판정만 남긴다. 원시 TCC 경로가 `<private>`면 역으로 추측해 확정하지 않는다.

1. **정적 준비(네트워크 읽기 외 외부 인증 0).** 고정 SDK 패키지의 macOS arm64/Python 3.13 호환성, 토큰 인증 분기, import 부작용, 디스크 캐시·로그·예외 처리, native timeout/cancel을 먼저 확인한다. 의존성은 운영 runtime과 분리된 시험 환경에만 설치하도록 계획한다. 전용 결과 파일에는 비밀을 담지 않는다. 알려진 터미널 허용은 SDK 내부 모든 경로의 허용 증거가 아니므로, 새 보호 경로 접근 가능성이 남으면 실행 전 단계에서 멈춘다.
2. **관측기 교정 C0.** Master가 허용한 경우에만 기존 `op read` 한 키를 기존 터미널 자리에서 읽고 값을 버린다. rc=0·형식=참·AppData 요청≥1·authValue=2·PROMPTING=0이 기준이다. 기존 E2만으로 새 수집기의 정상 동작을 대체하지 않는다. SDK 실행 전/후의 기준 관측으로 로그 누락을 점검한다. 이 단계가 금지되거나 정상 로그가 없으면 “요청 0” 판정을 하지 않는다.
3. **R-N 자격 시험 N1/N2.** 별개의 새 프로세스에서 토큰 인증과 동일한 3개 참조 읽기만 수행한다. 기존 틱의 DB/소비/발행 코드를 실행하지 않는다. SDK가 읽은 키는 메모리에서 형식·상호 구별 여부만 검사하고 폐기한다. 첫 실행/새 실행 각각 클라이언트 1개, 해석 요청은 키당 분리한다. 인증과 각 읽기 모두 **시도당 7초, 첫 출력 전 재시도 최대 1회**; 각 요청 총 마감 14초. SDK 내부 재시도와 중첩해 횟수를 늘리지 않는다. 인증과 3개 병렬 읽기 두 단계의 벽시계 상한은 28초이며, 이는 7초 요청 상한을 늘린 것이 아니다. 네이티브 작업이 coroutine 취소 뒤 살아남으면 이 세션이 띄운 시험 helper만 종료·회수하도록 설계한다. 현재 코드의 10.5초/21초를 새 시험에 복사하지 않는다.
4. **제약 판정.** N1/N2 후 남은 SDK 상주 프로세스 0, 새 키 평문 파일 0, op 자식 0을 확인한다. 현재 swap 압박 때문에 피크 RSS를 기존 3개 op 읽기 경로와 같은 방식으로 비교하고, 증가/미측정이면 자원 항목은 보류한다. 보호 경로 파일-open 로그를 안전하게 수집할 수 있을 때만 AppData 요청과 교차 확인한다. 실패/정보 부족이면 파일 캐시나 기존 CLI로 자동 전환하지 않는다. R-H 비교는 별도 후보 조사로만 Master가 발주할 수 있고 이 시험에 자동 추가하지 않는다.

### 사전 약속 판정표

| 관측 | 고정 판정 | 다음 값 |
|---|---|---|
| C0가 성공하고 AppData 요청≥1 / authValue=2 / PROMPTING=0; N1/N2는 3키 성공·7초 계약 준수·op/desktop IPC/새 평문 파일 0·AppData 요청 0·귀속 가능한 PROMPTING 0 | **터미널 자격 시험 합격**. 보호 경로 미접근도 별도 확인되면 원인 제거 가설 강하게 지지 | R-N 구현 검토로 제출. **launchd 재개 GO와 C12 완료는 아님** |
| N1/N2 성공이나 AppData 요청≥1, 또는 desktop IPC/CLI 호출 존재 | 목적 불합격; 기존 터미널 허용에 의존하거나 설계 가정 위반 | R-N 원인 분기 재검토. 다른 실행 주체 시험 금지 |
| C0 요청 0, msgID/PID 연결 실패, 수집 누락/권한 부족 | **판정 불가**. 0건을 무창 증거로 사용 금지 | 기록만 보고; launchd 실행으로 가르지 않음 |
| timeout/비정상 종료/형식 실패/새 평문 파일/상주 잔류 | 기능·비밀·회수 계약 불합격 | 해당 시험 종료. R-F 자동 채택 금지 |
| 귀속 가능한 PROMPTING 발생 또는 기존 창이 이미 열려 있음 | 전제 위반; 무창 실패, 기존 창은 요청 병합 위험 | 더 실행하지 않고 Master 보고. 클릭/재시도 없음 |
| R-H를 별도 발주한 뒤 성공·AppData 요청 0 | HOME 격리 가설 지지일 뿐, 로그 부재만으로 완전 보증하지 않음 | 실제 보호 경로 미접근·환경 동일성 확인 전 배포 보류 |

**증명 한계:** 터미널만 허용된 현재 조건에서 launchd의 실제 TCC 귀속·재부팅 뒤 실행까지 실측 완료라고 말할 수 없다. 현재의 안전한 종착점은 “원인 경로를 제거하는 설계와 터미널 자격 증거”다. 배포는 별도 단계이고, 무창 근거가 부족하면 기존 disabled/미적재 상태를 유지한다. 클릭 0은 실패를 조용히 내는 것만으로 충족하지 않으므로 **키 3개 성공과 무창을 동시에** 판정해야 한다.

## 출처·검토 범위

- [E1] `feature-pack/rag/docs/artifacts/arch-20261018-opread-prescription.md`, `arch-20261018-opread-nopopup.md`: 과거 처방과 h37/h39 관측. 이번 상대 좌석 산출물 아님. h37/h39의 사실은 발주와 기존 보고에 따른 인용이며 이번 재실행은 없다.
- [E2] `feature-pack/rag/docs/artifacts/opre-20261018-102136.txt`: 직접 읽음. T0 2025ms / T1 1862ms, 양쪽 AppData 1·PROMPTING 0. R-E 효과 없음.
- [E3] `feature-pack/rag/docs/artifacts/tcc-log-20261018-0945.txt`: AppData msgID `57343.6`, 접근 op PID 49818, 책임 python PID 46481, `Session scoped auth is invalid` 확인. 실제 보호 파일 경로는 미확인.
- [E4] `tick.py`의 `load_keys`를 Serena로 읽음. 현재 작업 트리에 타 좌석의 `store_keys` 수정이 이미 있고, 기존 op 환경 허용목록/3병렬/10.5초·21초 상수가 남아 있음. **그 변경은 승인 증거가 아니며 이 좌석은 수정하지 않았다.** 새 설계의 외부 호출은 7초 계약을 쓴다. 운영 plist는 허용된 키만 읽었고 credential-source/token 내용은 읽지 않았다.
- [S1] 1Password 공식 CLI [환경 변수](https://developer.1password.com/docs/cli/environment-variables/), [설정 디렉터리](https://developer.1password.com/docs/cli/config-directories/): OP_CONFIG_DIR/--config 우선순위와 HOME/XDG 처리. desktop 설정까지 격리한다는 보장은 없음.
- [S2] 1Password 공식 [SDK 개요](https://developer.1password.com/docs/sdks/), [튜토리얼](https://developer.1password.com/docs/sdks/setup-tutorial/), [개념](https://developer.1password.com/docs/sdks/concepts/): 서비스 계정 자동화 인증, secret reference, 계정별 rate limit, 버전 고정 필요. 응답은 공식 `www.1password.dev`로 리디렉션됨.
- [S3] 공식 Python SDK 소스 기준 `f30175110d3fd0edaaa332d4ebedf75aa02f71be`(GitHub API 확인): [client.py](https://github.com/1Password/onepassword-sdk-python/blob/f30175110d3fd0edaaa332d4ebedf75aa02f71be/src/onepassword/client.py), [core.py](https://github.com/1Password/onepassword-sdk-python/blob/f30175110d3fd0edaaa332d4ebedf75aa02f71be/src/onepassword/core.py), [defaults.py](https://github.com/1Password/onepassword-sdk-python/blob/f30175110d3fd0edaaa332d4ebedf75aa02f71be/src/onepassword/defaults.py), [secrets.py](https://github.com/1Password/onepassword-sdk-python/blob/f30175110d3fd0edaaa332d4ebedf75aa02f71be/src/onepassword/secrets.py), [setup.py](https://github.com/1Password/onepassword-sdk-python/blob/f30175110d3fd0edaaa332d4ebedf75aa02f71be/setup.py). 조회는 main 원문과 직후 HEAD 대조; SDK 설치·실행·native 내부 검증은 하지 않음.
- [S4] 이 맥 `man launchd.plist`: AssociatedBundleIdentifiers·LimitLoadToSessionType·SessionCreate·ProcessType·CAVEATS. Apple [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) 및 해당 documentation JSON. 번들/로그인 항목 연관과 TCC grant를 구별하는 근거.

실행 경계: op 실행 0 · launchctl 상태 변경 0 · 운영 plist/runtime/설치본/DB 변경 0 · 비밀 값 읽기/출력 0 · 상대 산출물 열람 0 · push 0 · 하위 에이전트 0 · 사용자 인터뷰 0. 쓴 파일은 이 보고서 1개다. HTTP 읽기는 요청당 timeout=7초·실패 시 최대 재시도 1회로 수행했다. 문서 검토를 완료했으며 C12 운영 회복은 완료로 판정하지 않는다.
