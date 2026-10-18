골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. planner 긴급 #2887(오빠 원문 «이게 베스트맞아? 겨우 권한때문에 이렇게 길게 해결못해? 패블아키랑 아스트라 들어갔냐?»): «사람 클릭 0·권한 창 0» 최선안 재판정.

**결론 1줄: 창의 원인은 «op 가 `$HOME/Library/Group Containers/2BUA8C4S2C.com.1password` 를 열어 보는 것»이므로, op 자식의 `HOME` 을 빈 0700 폴더로 바꿔(R-H) op 가 그 경로를 «아예 못 찾게» 하는 것이 최선이다 — 코드 1줄·비밀 사본 0·메모리 0·plist 0·터미널 로그만으로 판정 가능. 실패하면 R-F(평문 사본)가 아니라 R-SDK(1Password Python SDK · op 바이너리 자체를 안 씀)로 간다.**

(escalation · Fable architect arch#7 · 2026-10-18 · 기준 HEAD 3b9f1fd · macOS 15.0.1 · 상대(astra) 산출 미열람 · 조사는 읽기 전용 — `strings`·`codesign -d -r-`·`codesign -d --entitlements`·`ls`·`sysctl`·공식 문서 검색. `op` 실행 0 · launchctl 0 · 운영 파일 변경 0)

# «사람 클릭 0 · 권한 창 0» 최선안 — 창을 «허용받는» 게 아니라 «요청 자체가 안 나가게» 한다

## 0. 결론 (먼저)
1. **발생 위치(이번 조사로 한 단계 더 좁힘)**: `op` 2.32.1 은 Go 바이너리이고 홈 경로를 **`$HOME` 환경변수로만** 구한다(`github.com/mitchellh/go-homedir` + `os.UserHomeDir` 심볼 · 둘 다 유닉스에서 `$HOME`). 바이너리에 `Library/Group Containers/2BUA8C4S2C.com.1password` 문자열이 «Unable to determine location of config directory» 와 같은 묶음으로 있다 → 앱 연동 설정 조회 경로 = `$HOME` + 그 상수. **op 에는 엔타이틀먼트가 0개**(`codesign -d --entitlements` 빈 출력) → 같은 팀(2BUA8C4S2C)이어도 앱 그룹 권한이 없어서 그 폴더 접근은 «다른 앱 데이터»(TCC AppData) 로 잡힌다. 이것이 h39 O1(op 가 책임 주체여도 PROMPTING)의 설명이다. 라벨: **지지(문자열·서명·h39) · op 가 그 폴더 «안의 어느 파일»을 여는지는 `<private>` 라 미확인**.
2. **왜 R-E 가 효과 없었나**: `OP_BIOMETRIC_UNLOCK_ENABLED` 는 «앱 연동 on/off 토글»이지 «설정 파일을 읽지 말라»가 아니다 — op 는 토글 값과 무관하게 앱 설정 위치를 먼저 확인한다(opre T0=T1=AppData 1건이 그 증거). 같은 이유로 **1Password 앱 쪽 설정(«CLI 연동» 끄기)도 효과 0**(파일을 읽어야 끈 줄 안다).
3. **추천 1 = R-H(op 자식 `HOME` 격리)**: tick.py 의 op 자식 환경에서 `HOME` 을 `~/.config/airag/op-home/`(0700 · 빈 폴더 · 설치 때 1회 생성) 로 바꾼다. 그러면 op 가 찾는 Group Containers 경로는 «빈 폴더 밑의 없는 경로» → sandboxd 가 붙잡을 보호 경로 접근 자체가 0 → TCC 요청 0 → 창 0. 책임 주체가 누구든(python·op·sh) 요청이 없으니 launchd 아래서도 같다. **시험은 터미널에서 R-E 시험과 똑같은 집계(AppData/AllFiles/PROMPTING 줄 수)로 T0(기준)·T1(HOME 격리) 2회** — 오늘 opre 가 «터미널에서도 AppData 요청이 기록된다»(T0=1)를 이미 확인해 줬으므로 **기준선이 있고 판정이 가능**하다.
4. **사전 약속 폴백 = R-SDK**(R-F 아님): `onepassword-sdk` 0.4.1(PyPI · cp313 macosx_11_0_arm64 휠 7MB · python ≥3.9 · 런타임 python 3.13.12 arm64 확인) 로 서비스 계정 토큰만으로 `op://` 참조를 in-process 로 해석한다. **op 바이너리·앱 설정 조회·Group Containers 가 설계상 없다.** 비밀 평문 사본 0. 비용 = 의존성 1개 + 틱 코드 재작성(비동기·7초 룰) + 설치본 재설치. R-H 가 «1줄로 되는지» 먼저 보고, 안 되면 이쪽.
5. **R-F(0600 평문 사본)는 3순위로 내린다** — 창 0 은 보장되지만 FileVault 꺼짐 맥에 새 평문 키 3개가 생기고 키 교체 때마다 사람 손이 든다. 참고: 미커밋 tick.py(63줄 +)에 `store_keys_file` 경로가 이미 구현돼 있다(Nano WIP · 이 문서는 건드리지 않음) — 채택 여부와 무관하게 «op 폴백 없음» 설계는 적절하다.
6. **오빠 손 = 터미널 한 줄 `! bash /tmp/h<N>` 1회 · 클릭 0 · 창 0.** 계획 파일은 Nano 가 만들고 Master 승인 뒤 등록(이 문서는 계획만).

## 1. 새 사실 (이번 조사 · 읽기만)
| # | 관측 | 근거 |
|---|---|---|
| N1 | op 는 Go · 홈 경로 = `$HOME`(`mitchellh/go-homedir.dirUnix` · `os.UserHomeDir` 심볼) · `XDG_CONFIG_HOME`·`OP_CONFIG_DIR` 문자열도 있음(설정 폴더는 따로 바꿀 수 있음) | `strings op` |
| N2 | `Library/Group Containers/2BUA8C4S2C.com.1password` 가 «Unable to determine location of config directory» 와 같은 문자열 묶음 → 앱 연동 설정 위치 조회 코드 | `strings op` |
| N3 | op 엔타이틀먼트 0개 · 지정 요건 = `identifier "com.1password.op" and anchor apple generic … subject.OU = "2BUA8C4S2C"`(Developer ID) | `codesign -d --entitlements -`·`codesign -d -r-` |
| N4 | `~/Library/Group Containers/2BUA8C4S2C.com.1password` 는 0700·본인 소유·2024-11-20 생성(1Password 앱 데이터) · op 의 캐시 데몬 소켓은 **여기가 아니라** `~/.config/op/op-daemon.sock`(10-17 22:47 · h1 때 생성) | `ls -ld`·`ls -la ~/.config/op` |
| N5 | opre(10:21 터미널): T0·T1 모두 `AppData(preflight=no)=1 · AllFiles(preflight=yes)=1 · PROMPTING=0 · authValue 2` → 터미널에서도 AppData 요청이 **기록된다**(기준선 확보) · R-E 효과 0 | `opre-20261018-102136.txt` |
| N6 | 런타임 python = 3.13.12 arm64 · `onepassword` 모듈 미설치 · PyPI `onepassword-sdk` 0.4.1 에 cp313 macOS arm64 휠 있음(python ≥3.9) | `runtime/bin/python -c` · 공식 문서·PyPI 검색 |
| N7 | 운영 plist: `ProgramArguments[0]`=`runtime/bin/python` · `EnvironmentVariables`=PATH 만 · HOME 은 launchd 가 사용자 홈으로 채움 → tick 은 허용목록(`OP_ENV_ALLOWLIST` 에 HOME 포함)으로 그 HOME 을 op 에 그대로 넘긴다 | plist · tick.py 45행·361행 |
| N8 | swap 8.9G/10.0G 사용(여유 1.3G) · 1Password Connect·상주 데몬 계열은 비용 | `sysctl vm.swapusage` |
| N9 | 미커밋 tick.py 에 `store_keys_file`(0600·본인 소유·심링크 금지·3키 64hex·op 폴백 없음) 경로가 이미 있음 — R-F 구현 WIP | `git diff` |

## 2. 창이 뜨는 기제 (한 문단)
macOS 14+ 의 «앱 데이터 보호»는 `~/Library/Containers`·`~/Library/Group Containers` 아래 **다른 앱의 데이터**를 비(非)앱 프로세스가 열 때 sandboxd 가 커널에서 붙잡아 tccd 에 AppData 요청을 보내고, 책임 주체 이름으로 창을 띄운다. 터미널(Ghostty)은 이미 허용돼 조용히 통과(authValue 2)하고, launchd 아래 맨 실행 파일은 영구 신원이 없어 매번 묻는다(h37·h39). **지금까지의 후보(R-D·R-S·R-L·R-P·앱 번들·FDA)는 전부 «누가 허용받느냐»를 바꾸는 쪽**이었고 전부 클릭이 필요하거나 반증됐다. **이 문서의 축은 «요청이 안 나가게»** — op 가 보호 경로를 열지 않으면 책임 주체는 상관없다. 그 방법이 둘: ①op 에게 다른 HOME 을 줘서 경로를 못 찾게(R-H) ②op 를 안 쓰기(R-SDK · R-F).

## 3. 후보 비교표 (기존 전부 + 새 후보 ★)
| 후보 | 방법 | 클릭 0 | 비밀 노출면 | 재부팅 생존 | 부하·메모리 | 운영 파일 변경 | 되돌림 | **창 0 을 로그만으로 시험** | 판단 |
|---|---|---|---|---|---|---|---|---|---|
| **★R-H HOME 격리** | tick.py: op 자식 env `HOME=~/.config/airag/op-home`(0700 · 빈 폴더 · 설치 1회 생성) · 허용목록은 그대로(HOME 만 덮어씀) | **예(구조)** — 보호 경로 접근 0 이면 요청 0 | **변화 0**(토큰 환경변수 그대로 · op 설정 폴더만 격리 폴더 밑으로 이동) | 생존(launchd 그대로) | **0**(op 는 지금과 동일 · 캐시 데몬이 격리 폴더 밑에 하나 더 뜰 수 있음 · 4MB · 틱 종료 시 launchd 가 같이 거둠) | tick.py 1~3줄 + 설치본 갱신 + 폴더 1개 · **plist 0 · runtime.json 0** | 줄 삭제·폴더 삭제 | **가능** — 터미널 T0/T1 비교 · 오늘 opre 로 기준선(T0 AppData=1) 확보됨 | **추천 1** |
| **★R-SDK 1Password Python SDK** | `onepassword-sdk` 0.4.1 · `Client.authenticate(auth=token)` → `secrets.resolve_all([3 참조])` in-process · op 바이너리 미사용 | **예(구조)** — 앱 설정·Group Containers 코드 자체가 없음 | 변화 0(토큰은 메모리 · 평문 사본 0) | 생존 | op 프로세스 3개 → 0 · 네이티브 라이브러리 7MB 적재(수십 MB RSS · 틱 중에만) | tick.py 키 읽기 함수 교체 + 의존성 1개 + 런타임 재설치(네트워크) · **plist 0** | 의존성 제거·함수 복귀 | **가능** — 터미널에서 SDK 로 1회 해석 → AppData 요청 0 · `op` 프로세스 0 확인 | **2순위(사전 약속 폴백)** · 변경량이 큼 |
| R-F 0600 평문 캐시 | 터미널에서 1회 읽어 파일에 두고 틱은 op 미호출(N9 WIP 경로) | 예(구조) | **새 평문 키 3개** · FileVault 꺼짐 | 생존 | 0(op 3회 감소) | tick.py(WIP) + 파일 | 파일 삭제 | 가능(op 호출 0) | **3순위** · 오빠 보류 · 키 교체마다 사람 손 |
| ★R-C `OP_CONFIG_DIR`/`XDG_CONFIG_HOME` 만 | op 설정 폴더만 바꿈 | 미확인 — 설정 폴더 ≠ Group Containers 경로(N2 는 HOME 기준) | 변화 0 | 생존 | 0 | tick.py 1줄 | 삭제 | 가능(같은 집계) | **R-H 에 흡수** — HOME 격리는 설정 폴더도 같이 옮기므로 따로 둘 이유 없음 · R-H T1 이 «설정 폴더 못 찾음» 류로 실패할 때만 보조 팔(T2) |
| ★R-A launchd `AssociatedBundleIdentifiers` | plist 키로 «연관 앱» 지정 | 아니오 — 이 키는 «로그인 항목» 표시용(설정 앱에 앱 이름으로 보이게)이지 TCC 귀속을 바꾸지 않는다(공식 문서 기준) | — | — | — | plist | — | 불가(launchd 시험 금지) | **제외** |
| ★R-B 앱 번들 래퍼(.app · 임시 서명) | 책임 주체를 번들로 | 미확인 — 인증서 0개라 임시 서명 → python 과 같은 «영구 신원 없음» 부류 가능성 | 0 | 생존 | 0 | 새 번들+plist | 삭제 | **불가**(허용이 이어지는지 보려면 클릭 1회) | **제외** |
| ★R-LS `LimitLoadToSessionType=Background` | 비Aqua 세션이면 tccd 가 창 대신 조용히 거부 | 미확인 — 거부된 op 가 계속 진행하는지(S1 유추 timeout) 모름 | 0 | 생존 | 0 | plist 1키 | 복귀 | **불가**(launchd 에서만 시험 가능) | **제외** |
| ★R-SX `sandbox-exec` 로 op 감싸 Group Containers 읽기 거부 | 자체 프로파일 deny | 미확인 — 앱 데이터 검사(sandboxd)와 자체 프로파일 중 무엇이 먼저인지 모름 · API 폐기 예정 | 0 | 생존 | 0 | tick.py + 프로파일 파일 | 삭제 | 가능(터미널 집계) | **보류** — R-H 가 같은 효과를 더 단순하게 냄 |
| ★R-1P 1Password 앱에서 «CLI 연동» 끄기 | 앱 설정 | 아니오 — op 는 끈 줄 알려고 그 파일을 읽는다(R-E 와 같은 결과 예상) | 0 | 생존 | 0 | 앱 설정(오빠 클릭) | 복귀 | 가능이나 무의미 | **제외** |
| R-E `OP_BIOMETRIC_UNLOCK_ENABLED=false` | 앱 연동 토글 | 아니오 | — | — | — | — | — | 시험 완료 | **반증(opre T1=1)** |
| R-D op 책임 해제 / R-S 셸 책임 | 책임 주체 교체 | 아니오(h39 O2·S1 PROMPTING/timeout) | — | — | — | — | — | — | **반증** |
| R-L/R-P 임시 서명 런처·python 사본 | 임시 서명 | 아니오(인증서 0개 · 세션 한정) | — | — | — | — | — | 불가 | **제외** |
| R-K 키체인 캐시 | `security` CLI | 미확인(키체인 창 가능) | 암호화 | 로그인 중 | 0 | tick.py+항목 | 삭제 | **불가** | 보류 |
| R-T tmux 상주 루프 | Ghostty 아래 루프 | 예 | 0 | **죽음**(재부팅·zombie-clean) | 소 | 기동 체계 교체 | 복귀 | 가능 | 비추 |
| FDA(전체 디스크 접근) | 시스템 설정 | 클릭 1 | 0 | 생존 | 0 | 시스템 권한 | 해제 | — | 제외 |
| 1Password Connect | 로컬 서버 | 예 | 서버 토큰 | 상주 | **수백 MB**(swap 여유 1.3G) | 큰 설계 | — | — | 비추 |
| cron | launchd 대신 | 아니오(S1 유추) | — | 생존 | 0 | crontab | 복귀 | — | 반증 |

## 4. 추천 R-H — 구현 메모 (Nano 몫 · 이 문서는 지시만)
- tick.py `_read…` 의 자식 환경 조립(361~362행) 뒤에 **고정 덮어쓰기 1건**: `child["HOME"] = str(OP_HOME_DIR)` · `OP_HOME_DIR = Path("~/.config/airag/op-home").expanduser()` 상수 1개. 폴더가 없거나 0700·본인 소유가 아니면 기존 실패 코드 체계대로 값 없는 실패 1건(예: `OP_HOME_INVALID`) — **op 를 부르지 않는다**(잘못된 HOME 으로 op 가 진짜 홈으로 되돌아갈 여지 0 · go-homedir 는 `HOME` 이 비면 `sh -c 'cd && pwd'` 로 진짜 홈을 찾으므로 «비우기»는 금지, 반드시 «다른 폴더로 채우기»).
- 폴더 생성은 설치 절차(1회 · 터미널) — 틱은 만들지 않고 검사만.
- `TMPDIR`·`PATH` 등 허용목록 나머지 그대로 · `OP_CACHE`·`OP_CONFIG_DIR` 은 **섞지 않는다**(한 번에 하나). 7초 룰 상한(시도 10.5초·호출 21초)·값 미기록·3병렬 그대로.
- 회귀 시험(유닛): 자식 env 의 HOME 이 격리 폴더인지 · 폴더 조건 위반 시 op 미호출인지 · 로그에 값 0.

## 5. 시험 계획 — 터미널만 · 클릭 0 · 창 0 · 로그로만 판정 (사전 약속)
전제: 터미널 자리(Ghostty→tmux→claude `!`)는 h1·opre 에서 창 없이 통과한 자리. **launchd 라벨 0 · launchctl 0 · 운영 파일 0 · op 실행은 Master 승인 뒤 오빠 `!` 한 줄로만.**
1. 준비(스크립트 안 · 0700): `mkdir -m 700 ~/.config/airag/op-home`(없을 때만). 토큰은 파일에서 셸 변수로만 · 값은 «64자 hex 여부 1비트»만 남기고 버림 · 상한 10.5초.
2. **T0 기준**: opre T0 과 동일 호출(`op read <키 1개 참조>` · 허용목록 환경).
3. 2초 쉼.
4. **T1 격리**: 같은 호출에 `HOME=~/.config/airag/op-home` 만 바꿈.
5. 집계(opre 와 동일): 각 run 구간의 TCC 로그에서 접근자 `com.1password.op` 의 `AppData(preflight=no)`·`AllFiles(preflight=yes)` 줄 수 · PROMPTING 줄 수 · authValue. 추가 1비트: T1 뒤 `~/.config/airag/op-home/.config/op/` 존재 여부(op 가 격리 HOME 을 실제로 썼다는 증거).
6. 출력 = run·rc·ms·형식통과·집계 3개·격리폴더 사용 1비트. 값 출력 0.

| 결과 | 읽는 법 | 다음 |
|---|---|---|
| **T0: AppData ≥1(PROMPTING 0) · T1: AppData 0 · 둘 다 rc 0·형식 통과 · 격리 폴더 사용=1** | op 가 보호 경로를 안 연다 → launchd 에서도 묻을 대상 없음 | **채택 R-H** → Nano 구현 + DA → 설치본 갱신 승인 → 재개(§6 합격선) |
| T1: AppData 0 이지만 격리 폴더 사용=0 | op 가 HOME 을 안 썼는데 요청도 없음 — 설명 불일치 | 판정 보류 · T1 1회 재실행(같은 턴) · 그래도 같으면 Master 보고 |
| T0: AppData 0 | 오늘 opre 와 다름 — 기준선 흔들림 | 판정 불가 → **R-SDK 로** (launchd 시험은 하지 않음) |
| T1: AppData ≥1 | HOME 격리로 경로를 못 돌림(홈을 다른 방법으로 찾음) | **R-SDK 로** |
| T1: rc≠0 · stderr 가 «config directory» 류(값 0 · 문구 분류만) | 설정 폴더 쓰기 문제 | **T2 1회**: T1 + `OP_CONFIG_DIR=~/.config/airag/op-home/op` → 같은 표로 재판정 · T2 도 실패면 R-SDK |
| T1: rc≠0 · 그 밖 | 격리 HOME 이 서비스 계정 읽기를 깨뜨림 | **R-SDK 로** |
| 어느 run 에서든 PROMPTING ≥1 | 터미널 자리도 창 — 전제 깨짐 | 즉시 중단 · Master 보고 |

**R-SDK 로 갈 때의 시험(역시 터미널·로그만)**: 격리 venv 에 `onepassword-sdk==0.4.1` 설치(네트워크) → 참조 1개 `resolve` 를 `asyncio.wait_for(…, 7)` 로 1회 → 집계 동일(AppData 0 · PROMPTING 0 · `op` 프로세스 0 · 형식 1비트). 통과면 Nano 가 틱 키 읽기 함수를 SDK 로 교체(3키 `resolve_all` 1회 · 7초 + 재시도 1회 · 값 미기록) + DA + 런타임 재설치 승인.

## 6. 운영 재개 (다음 승인 건)
- 합격선(사전 약속): 재개 후 **연속 3틱 `status=ok`** · 그 구간 TCC 로그 AppData PROMPTING **0** · 오빠 클릭 0. 첫 틱에 PROMPTING 1줄이라도 → 즉시 `bootout`(오빠 HIL) · 재시도 0 · Master 보고.
- R-H 는 «같은 바이너리·같은 환경이면 파일 접근 집합이 같다»에 기대므로 §5 T1 통과가 launchd 첫 틱의 사전 증거다. op 업데이트(경로 상수가 바뀔 수 있음)는 재개 뒤 첫 틱 PROMPTING 0 으로 재확인(설치 문서 1줄).

## 7. 하지 않을 것 / 하지 않은 것
- **하지 않을 것**: ①launchd 안에서 창이 뜰 수 있는 시험 ②허용 클릭을 요구하는 설계(R-D·R-S·R-B·FDA) ③`HOME` 비우기(진짜 홈으로 되돌아감) ④`OP_CACHE`·`OP_CONFIG_DIR` 을 R-H T1 에 섞기(T2 는 T1 실패 시에만) ⑤R-F 를 기본 폴백으로 두기 ⑥상한·재시도 늘리기 ⑦TCC.db·`tccutil`.
- **하지 않은 것**: `op` 실행 0 · launchctl 0 · plist·runtime.json·설치본·DB 변경 0 · 미커밋 WIP(tick.py 등) 변경 0 · 비밀 값 출력 0(자격 파일은 키 «이름»만) · push 0 · AskUserQuestion 0 · 서브에이전트 0 · 상대 산출 미열람. 쓴 파일 = 이 문서 1개.

## 8. 확인하지 못한 것
op 가 Group Containers «안의 어느 파일»을 여는지(`<private>`) · op 가 HOME 외 경로로 홈을 구하는 코드가 있는지(§5 T1 이 가름) · SDK 네이티브 라이브러리의 RSS 실측 · SDK 설치 가능 여부(네트워크·uv 캐시 미확인) · `aButtonAuth 5` 의 뜻 · 1Password 앱 설정 파일 실제 경로.
