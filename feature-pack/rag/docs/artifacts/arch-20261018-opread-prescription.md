골 원문(GOAL-LEDGER-airag.md 복붙): 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12(launchd com.airag.consumer 회복 관찰). planner 판정(10-18): «같은 증상 5회 = 재시도 0 — 다음 오빠 맥 앞 회차는 설계가 바뀐 뒤에만» · 처방은 arch 몫.
(최종본 · architect arch#6 · Opus 5.5 · 2026-10-18 · 기준 HEAD 4e7d616 · macOS 15.0.1 24A348. 전임 arch#5(Sonnet 5.5) 초안을 읽고 TCC 로그 원문·바이너리 서명으로 독립 재검증했다. 각 절에 **[동의]·[반박]·[추가]** 를 표기한다.)

# 키 읽기(OP_READ_UNAVAILABLE) 처방 — «권한을 묻는 주체»를 `op` 자신으로 바꾼다

## 0. 결론 (먼저)
1. **발생 위치 = 맥 «다른 앱 데이터» 권한(TCC) 응답 대기다 — 지지는 강하지만 «확정»은 아니다(재현 시험 0회).** [동의] 이번 로그(09:45)는 «sandboxd 가 `op` 의 파일 접근을 붙잡고, 책임 주체인 틱 python 이름으로 사람 동의 창을 띄운 뒤, 응답이 없는 채로 op 3개가 전부 멈춘» 모양이다.
2. **새로 굳은 사실(초안보다 한 걸음 더)**: 책임 주체 python 은 «링커가 붙인 임시 서명»뿐이라 TCC 가 **영구 신원(지정 요건)을 만들지 못한다**(로그 `MacOS error: -67062` = 서명 없음 · 바로 뒤 `Session scoped auth is invalid for client`). → **허용을 눌러도 «그 프로세스 세션 한정»으로만 남고, 5분마다 새로 뜨는 틱에는 이어지지 않는다는 읽기가 가장 잘 맞는다**(10-17 허용 뒤에도 재발 · 오늘 currentAuth 1 과 일치). 라벨: **지지(로그 문구) · 저장 형태 자체는 미확인**.
3. **[반박] 초안의 2순위 R-L(임시 서명 런처)은 같은 함정에 빠진다.** 이 맥에는 코드 서명 인증서가 0개(`security find-identity` → 0 valid)라 런처도 임시 서명밖에 못 한다 → python 과 같은 «영구 신원 없음» 부류. 후순위로 내린다.
4. **추천 = R-D: `op` 를 «스스로 책임지는 프로세스»로 띄운다**(posix_spawn 의 책임 해제 — 이 맥 libSystem 에 `responsibility_spawnattrs_setdisclaim` 있음 확인). 그러면 동의를 묻는 주체가 **1Password 정식 서명(Developer ID · 팀 2BUA8C4S2C) 의 `op`** 가 된다 — ①1Password 자기 그룹 컨테이너(같은 팀)면 창 자체가 안 뜰 가능성 ②떠도 영구 신원이 있어 «한 번 허용»이 이어짐. **운영 plist 변경 0**(tick.py 코드 변경 → Nano+DA · 설치본 갱신만 승인 항목). 초안의 R-S(셸을 책임 주체로)는 **보조 팔**로 같은 시험에 남긴다.
5. **시험 = 오빠 맥 앞 1회**(`! bash /tmp/h<N>` 한 줄 · 클릭 최대 1회) — O 팔(op 책임) · S 팔(셸 책임) · P 팔(지금 신원 재현) · 판정표 사전 약속(§4). 통과 전 운영 재개 0.

## 1. 사실 — 이번 구간 (라벨은 관측만)
| # | 관측 | 근거 | 초안 대비 |
|---|---|---|---|
| F1 | 터미널: 한도 1000/1000 · `op --version` 2.32.1 · `op read` 1건 성공 — 틱 최소환경 2.3초 / 전체환경 1.8초 | h1(오빠 10-17 22:47) | [동의] |
| F2 | launchd 5회차(10-18 09:45:14 → 09:45:38 exit 30): 키 3 × 시도 2 = 6/6 timeout · 상한(10.5초) 근처 종료 · 부분 출력 0 | 계약 입력 · `tick-20261018.log` | [동의] |
| F3 | «01:32 통과 틱»은 틱 로그에 없다 → 출처 미확인 | `tick-2026101{6,7,8}.log` | [동의] (전 문서 E9 와 같음) |
| F4 | 09:45:18.076~.082 — **요청자 = `com.apple.sandboxd`(pid 57343, root)**, 접근자 = `com.1password.op`(pid **49815·49817·49818** — 키 3개 병렬), 책임·주체 = 틱 python `…/cpython-3.13.12-macos-aarch64-none/bin/python3.13`(pid 46481). AllFiles 사전조회(preflight=yes) 3건은 즉시 거부(창 아님). **AppData(preflight=no) 요청은 49818 하나뿐** → `Session scoped auth is invalid for client` → **AUTHREQ_PROMPTING** · `currentAuth: 1 desiredAuth: 2` · `aButtonAuth: 5 bButtonAuth: 0 cButtonAuth: 1` · 결과 줄은 구간(~09:46:00) 안에 없음 | `tcc-log-20261018-0945.txt` 12~52행 | [추가] 요청자가 sandboxd(=파일 열기가 커널·샌드박스에서 붙잡힘) · op 3개 중 AppData 요청은 1건 |
| F5 | python 신원 조회 때마다 **`MacOS error: -67062`**(서명 없음 계열) 직후 신원 type 1(경로 기반) | 같은 파일 17·36·45·49행 | [추가] |
| F6 | 09:45:28.39 sandboxd 가 AllFiles 사전조회 3건만 더 보냄(= 2회차 시도들) · **두 번째 AppData 요청·PROMPTING 줄은 없음** · 그래도 2회차 3개 모두 무응답 | 같은 파일 206~233행 | [추가] **«TCC 요청 0건 = TCC 무관»은 안전한 추론이 아니다** — 같은 주체의 창이 떠 있는 동안 뒤 요청은 따로 기록되지 않는 모양 |
| F7 | python 서명: `Signature=adhoc` · `flags=adhoc,linker-signed` · `Identifier=-` · TeamIdentifier 없음 · 파일 날짜 09-03(10-17~18 사이 바뀌지 않음) | `codesign -dv` · `stat` | [동의]+날짜 추가 → 10-17 허용 뒤 «경로·해시가 바뀌어서» 가설(초안 E3 ③)은 **반증** |
| F8 | `op` = `/opt/homebrew/Caskroom/1password-cli/2.32.1/op` · Identifier `com.1password.op` · TeamIdentifier `2BUA8C4S2C` · `~/Library/Group Containers/2BUA8C4S2C.com.1password` 존재(같은 팀 접두) | `codesign -dv` · `ls -d` | [동의] |
| F9 | 이 맥 코드 서명 인증서 **0개** · `/usr/bin/clang` 있음 · libSystem 에 `responsibility_spawnattrs_setdisclaim`·`posix_spawnattr_init` 심볼 **있음** | `security find-identity -v -p codesigning` · 시스템 python ctypes 심볼 조회(호출 0) | [추가] |
| F10 | 운영 plist `ProgramArguments[0]` = `runtime/bin/python`(→ `cpython-3.13-…` 심링크 → 3.13.12 실체) · EnvironmentVariables = PATH 만 · ProcessType 없음 · tick.py 는 `subprocess.run([op,"read",ref], env=허용목록+토큰)` 3병렬 | plist·`pyvenv.cfg`·tick.py 302~341행 읽기 | [동의] |
| F11 | 10-17 12:53~13:33 TCC 로그는 맥에서 이미 사라짐 → 그때 결과 `authValue=2` 가 «영구»였는지 «세션»이었는지 재확인 불가 | 초안 F8 | [동의] |

## 2. 발생 위치 — (a) TCC / (b) 키체인·1Password 앱 / (c) launchd 환경
| 후보 | 라벨 | 근거 |
|---|---|---|
| **(a) TCC «다른 앱 데이터» 동의 대기** | **지지(직접 관측) · 재현 없음** | F4: sandboxd 가 op 파일 접근을 붙잡고 창을 띄움 · F2 무응답 모양 · F6 2회차도 같은 대기 · 10-17 12:53 같은 모양(전 문서 E2) |
| (b) 1Password 앱·키체인 응답 | **반증 쪽(약)** | 서비스 계정 토큰 경로 · 붙잡힌 곳이 앱 연동 소켓 응답이 아니라 sandboxd 의 파일 접근 판정(F4) · 단, op 가 **어느 파일**을 열려 했는지는 미확인(로그 `<private>`) |
| **(c) launchd 실행 신원** | **지지 — (a) 를 일으키는 층** | 책임 주체 = launchd 가 직접 띄운 임시 서명 python(F4·F7) · 터미널은 책임 주체가 Ghostty 등 정식 앱이라 통과(F1). 환경 변수 차이는 h1 최소환경 성공으로 **반증** |
| 허용이 이어지지 않는 이유 = 영구 신원 부재 | **지지(로그 문구) · 저장 형태 미확인** | F5 `-67062` + `Session scoped auth is invalid` + 10-17 허용 뒤 재발 + 오늘 currentAuth 1 · 바이너리 불변(F7) |
| 한도·원격 지연 · 7초 상한 · 부하 · ProcessType · 토큰 만료 | **반증(우세)** | F1 · F2 · 전 문서 H1~H6 그대로 [동의] |

**설명 안 된 것 (정직)**: ①10-17 13:27·13:32 틱(허용 직후)에 PROMPTING 줄이 없었던 이유 — F6 대로 «이전 창이 아직 떠 있어 줄 서기»면 맞지만 13:26:23 에 허용이 찍혔으므로 완전한 설명은 아니다. P 팔이 가른다. ②`aButtonAuth: 5` 가 «세션 허용»을 뜻하는지 — 값 의미 미확인(10-17 결과는 authValue 2 로 찍힘). ③op 가 서비스 계정 읽기에 왜 «다른 앱 데이터»를 건드리는지.

## 3. 후보 비교 — «실행 신원이 고정되고 권한이 이어지는 경로»
| 후보 | 방법 | 동의를 묻는 주체 | 운영 파일 변경 | 오빠 승인 | 되돌림 | 맥 앞 1회 판별 | 판단 |
|---|---|---|---|---|---|---|---|
| **R-D op 책임 해제** [추가·추천] | tick.py 가 op 를 `posix_spawn` + `responsibility_spawnattrs_setdisclaim(attr,1)` 로 띄움(ctypes · 표준 subprocess 는 이 옵션 없음). 상한·재시도·환경 허용목록·출력 버림 규칙은 지금과 동일 | **`op`(Developer ID · 팀 2BUA8C4S2C · 영구 신원 있음)** | **plist 0 · runtime.json 0** · 코드(tick.py) + 설치본 갱신 | 설치본 갱신만 | 이전 설치본 복원 | **O 팔**(launchd 가 op 를 직접 책임 주체로 띄움 = R-D 와 같은 신원 결과) · 클릭 0~1 | **1순위** — 주체가 정식 서명이라 «한 번 허용이 이어짐»이 구조적으로 가능한 유일한 경로 · 같은 팀 컨테이너면 창 0 기대(미확인) · uv python 경로 변동과 무관 |
| **R-S 셸 책임** [동의·보조로 강등] | plist `ProgramArguments` = `/bin/sh -c '<python> -m … ; exit $?'`(exec 금지) | `/bin/sh`(플랫폼 바이너리) — 창 대신 조용한 거부 기대(로그의 `Platform binary prompting is 'Deny'` 는 다른 서비스 관측) | plist 1개 | plist 변경 승인 | 원본 복원 | S 팔 · 클릭 0 | **2순위** — 성공해도 «op 가 거부당하고도 우연히 버팀»에 기대는 것이라 op 업데이트에 취약 · 셸이 TCC 주체가 되는 구조라 누가 셸에 권한을 주면 범위가 넓다 |
| R-L 임시 서명 런처 | C 런처 `codesign -s - -i …` → python 자식 | 런처(임시 서명) | plist + 새 파일 | 둘 다 | 삭제·복원 | L 팔 | **[반박] 후순위** — 인증서 0개(F9)라 임시 서명뿐 → python 과 같은 «영구 신원 없음»(F5) 부류일 가능성. 시험 대상에서 뺀다 |
| R-P python 고정 사본+서명 | 사본 재서명 | 사본(임시 서명) | plist + 큰 사본 | 승인 | 삭제 | — | **[동의] 후순위** · R-L 과 같은 이유 |
| R-F 전체 디스크 접근(FDA) | 시스템 설정에서 부여 | python | 0(시스템 권한) | 오빠 직접 | 설정 해제 | 가능 | **[동의] 비추·최후** — 모든 python 에 디스크 전체 · 임시 서명이라 지속성도 미확인 |
| R-X 터미널·tmux 아래 기동 | 터미널 신원 차용 | Ghostty | 기동 체계 교체 | 승인 | — | — | **[동의] 비추** — 재부팅·로그아웃에 약함 |
| R-K 키체인 중계 | 사람 있을 때 1회 읽어 저장 | — | 코드+plist | 설계 변경 | — | — | **[동의] 보류** — 비밀 복제 · 서비스 계정 설계 변경 |
| R-H op 용 HOME 격리 | op 자식 HOME 을 빈 폴더로 | python(그대로) | 코드 | 승인 | — | 가능 | **[동의] 이번 제외** — 어느 경로인지 모름 · 효과 불명 |

**추천 1개: R-D.** 이유 ①동의 주체가 영구 신원을 가진 유일한 후보(F8·F9) ②운영 plist·runtime.json 그대로 ③uv python 업그레이드(경로 `cpython-3.13.12` → 다음 패치)에 영향 없음 ④op 가 정말 1Password 컨테이너를 읽는 것이면 «정당한 주인»이 묻는 모양이 된다. 구현 형태(ctypes 직접 vs 작은 C 도우미)는 Nano+DA 몫 — architect 기준: **설치물 추가 0 인 ctypes 쪽을 우선**(도우미는 또 하나의 임시 서명 파일·설치 경로가 생김), 7초 룰 상한(시도 10.5초·호출 21초)·시간 초과 시 자식 kill+회수·값 미기록은 지금 테스트 그대로 통과해야 한다.

## 4. 시험 계획 — 오빠 맥 앞 «1회» (값 출력 0 · 클릭 최대 1회)
Nano 가 만들 것(이 문서는 지시만): 계획 파일 1개 → ft-hil 등록 → 오빠는 `! bash /tmp/h<N>` 한 줄. **운영 plist·runtime.json·설치본·DB·운영 라벨 `com.airag.consumer` 변경 0.** 시험 라벨 `com.airag.opprobe.<팔>` · plist 는 `~/.local/share/airag/probe/` · 끝나면 시험 라벨만 `bootout`.

공통: 같은 사용자 `gui/<uid>` 도메인 · 같은 PATH · 토큰은 파일에서 셸 변수로만(`OP_SERVICE_ACCOUNT_TOKEN="$(cat <token_file>)"`, 화면·로그 기록 0) · `op read <키 1개 참조>` 출력은 «64자 hex 형식 통과 여부» 1비트로만 남기고 버림 · 기록 = 팔·rc·소요 ms·형식 통과 여부. 매 run 직후 `log show --predicate 'subsystem=="com.apple.TCC" AND (eventMessage CONTAINS "SystemPolicyAppData" OR eventMessage CONTAINS "PROMPTING")'` 로 그 구간의 **PROMPTING 줄 수·주체 경로·결과 authValue** 만 수집. 상한 = 틱과 같은 10.5초 · 단 **사람 클릭을 기다릴 수 있는 run(O1·P1)만 40초**(사람 응답 대기 · 70초 천장 안).

**순서 = O → S → P (P 를 마지막에** — P 는 python 이름의 창을 띄워 둘 수 있어서 다른 팔과 섞이지 않게).

| 팔 | 책임 주체(launchd 가 띄운 첫 프로세스의 실행 이미지) | run | 오빠 할 일 |
|---|---|---|---|
| **O** [추가] | `/bin/sh -c '<0700 임시 폴더에 fifo>; (형식 판정 1비트만 쓰는 읽기 쪽) & exec <op 절대경로> read <참조> > <fifo>'` — **여기서는 exec 가 핵심**(launchd 가 띄운 같은 pid 가 op 로 바뀌어 책임 주체 이미지 = op). ★op stdout 이 launchd `StandardOutPath` 로 가면 값이 디스크에 남으므로 반드시 fifo → 판정 쪽(`^[0-9a-f]{64}$` 여부만 기록)으로만 흘린다 · 값의 디스크 기록 0 이 시험 조건★ | O1 → O2(새 프로세스) | O1 에 창이 뜨면(주체 = op 로 표시) «허용» |
| **S** [동의] | `/bin/sh -c '<op> read <참조> …; rc=$?; exit $rc'` (exec 금지 — sh 가 책임 주체로 남아야 함) | S1 | 없음 |
| **P** [동의] | 운영과 같은 `runtime/bin/python` 이 subprocess 로 op 호출(지금 신원 재현) | P1 → P2(새 프로세스) | P1 에 창이 뜨면 «허용»(10-17 과 같은 선택) |

### 사전 약속 판정표 (결과 보기 «전에» 고정)
| 결과 | 읽는 법 | 다음 |
|---|---|---|
| **P1: 상한까지 무응답 + 같은 구간 AppData PROMPTING ≥1 (주체 = python3.13)** | 원인 재현 → **(a)+(c) 확정** | O·S 결과로 처방 선택 |
| P1: 10.5초 안 성공 · PROMPTING 0 | (a)(c) **반증** → 틱 고유(3병렬·스레드 등) | R-D/R-S 보류 · 새 설계 · Master 보고 |
| **P2: timeout 또는 PROMPTING 재출현** (P1 허용 직후) | 허용이 임시 서명 주체에 **안 이어짐 확정** | R-D 또는 R-S 필수 · R-L/R-P/R-F 폐기 |
| P2: 성공 · PROMPTING 0 | 허용이 이어진다 → 운영 재발은 다른 이유(줄 서기·창 놓침) | R-D 는 여전히 유효(클릭 0 목표)이나 긴급도 낮춤 · Master 판단 |
| **O1: ≤10.5초 rc 0 · 형식 통과 · PROMPTING 0** | op 가 책임 주체면 창 자체가 안 뜸(같은 팀 컨테이너 읽기로 추정) | **채택 R-D** → Nano 구현 + DA → 설치본 갱신 승인 → 재개 관찰 |
| O1: 창이 뜸(주체 = op) → 허용 → **O2: ≤10.5초 성공 · PROMPTING 0** | 정식 서명 주체에 허용이 이어짐 | **채택 R-D**(오빠 1회 허용이 이미 끝난 상태로 운영 시작) |
| O2: 다시 창 또는 timeout | op 신원으로도 안 이어짐 | R-D 폐기 → S 결과 확인 |
| **S1: ≤10.5초 rc 0 · 형식 통과 · PROMPTING 0** (O 실패 시에만 채택 근거) | 조용한 거부를 op 가 견딤 | **채택 R-S**(보조) → plist 변경 승인 → 재개 관찰 |
| S1: 빠른 비정상 종료 | 접근이 op 에 필요 | R-S 폐기 |
| O·S 모두 실패 | 신원 바꾸기로 안 풀림 | 중단 · Master 보고 · R-F 는 오빠 «결정 질문»으로만(자동 진행 0) |

## 5. 채택 뒤 운영 재개 (이번 시험이 아니라 «다음 승인 건»)
- R-D: Nano 가 tick.py 수정(책임 해제 spawn) + 시험(상한·kill·값 미기록 회귀) → DA → 설치본 갱신은 오빠 승인. **plist 그대로**라 재개 = 기존 enable+bootstrap 승인 1건.
- **재개 합격선(사전 약속)**: 연속 3틱 `status=ok`(exit 0) · 그 3틱 동안 AppData PROMPTING 0 · 오빠 클릭 0. **첫 틱 timeout 이면 즉시 중단**(재시도 0 · «설계가 다시 틀림»으로 Master 보고).
- 설치 고지: R-D 는 op 업데이트(같은 팀 서명)에도 신원이 이어질 것으로 기대(정식 서명의 지정 요건 기반 — 미실측). uv python 변경은 무관.

## 6. 하지 않을 것 / 하지 않은 것
- **하지 않을 것** [동의]: ①시도 상한·재시도 늘리기(사람 응답 대기 모양 · 7초 룰 70초 천장) ②python 에 FDA ③`StartInterval` 변경 ④통과 전 `com.airag.consumer` enable/bootstrap ⑤`op daemon`·소켓 임의 kill ⑥HOME 격리를 이번 시험에 섞기 [추가] ⑦임시 서명 런처(R-L) 설치 — 인증서 없는 상태에선 시험 가치 낮음 ⑧TCC.db 직접 수정·`tccutil reset`(시스템 권한 · 오빠 결정 사항).
- **하지 않은 것**: `op` 실행 0 · launchctl 변경 동사 0 · plist·runtime.json·설치본·DB 변경 0 · 비밀 값 출력 0(credential 설정은 키 이름만) · push 0 · 서브에이전트 0 · AskUserQuestion 0. 실행한 것은 읽기뿐 — `codesign -dv`·`stat`·`readlink`·`security find-identity`(인증서 개수)·시스템 python ctypes 심볼 존재 확인(함수 호출 0)·로그 파일 grep. 쓴 파일 = 이 문서 1개(전임 초안을 읽은 뒤 같은 경로에 최종본으로 갱신).

## 7. 확인하지 못한 것
op 가 여는 «다른 앱 데이터»의 실제 경로(로그 `<private>`) · 같은 팀 컨테이너면 op 책임 주체일 때 창이 안 뜨는지(O1 이 가름) · `aButtonAuth 5` 의 뜻과 허용의 저장 형태(P2 가 가름) · 책임 해제가 이 맥 15.0.1 에서 TCC 귀속을 실제로 op 로 옮기는지(O 팔은 «op 가 책임 주체»인 결과 상태를 시험하는 것이고, ctypes 책임 해제 경로 자체는 구현 후 시험에서 확인) · 10-17 13:27·13:32 PROMPTING 0 의 완전한 설명 · 오빠가 09:45 창을 보셨는지(desk 질문 중) · «01:32 통과» 출처.
