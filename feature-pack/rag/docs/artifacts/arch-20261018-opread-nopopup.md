골 원문(GOAL-LEDGER-airag.md 복붙): 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. planner 긴급 지시(#2871 · 오빠 «op도 계속 뜨는데» «아진짜... 머하냐고»): 사람 클릭 없이 도는 경로 — 권한 창 자체가 안 뜨는 방식.
(architect arch#6 · Opus 5.5 · 2026-10-18 · 기준 HEAD 4e7d616 · macOS 15.0.1 · 이전 처방 `arch-20261018-opread-prescription.md` 의 반증된 부분은 [반박] 표기)

# 사람 클릭 0 으로 키를 읽는 경로 — «권한을 묻지 않게» 만든다

## 0. 결론 (먼저)
1. **[반박 — 내 이전 처방] R-D(op 를 책임 주체로)는 불성립.** h39: O1 허용 → O2(새 프로세스) 다시 PROMPTING. h37/h39 S1(셸 책임)도 주체가 op 로 잡혀 PROMPTING → R-S 의 «플랫폼 바이너리라 조용히 거부» 기대도 **반증**. 결론: **launchd 아래에서는 누가 책임 주체든 «다른 앱 데이터» 허용이 다음 실행으로 안 이어진다**(python·op 둘 다 맨 실행 파일 · 창의 `aButtonAuth: 5` = 세션 한정 허용으로 읽힘 · 값 의미는 미확인).
2. **창의 출처를 좁혔다(새 사실)**: `op` 2.32.1 바이너리 안에 `Library/Group Containers/2BUA8C4S2C.com.1password` · `settings.json` · `OP_BIOMETRIC_UNLOCK_ENABLED` 문자열이 있다. → op 는 서비스 계정 토큰으로 읽을 때도 **1Password 데스크톱 앱 설정 파일(앱 연동 켜짐 여부)을 열어 보는 것**으로 보이고, sandboxd 가 붙잡는 «다른 앱 데이터»가 바로 그 폴더라는 읽기가 가장 잘 맞는다. 라벨: **지지(문자열 근거) · 실제 경로는 로그 `<private>` 라 미확인**.
3. **추천 1개 = R-E: op 자식 환경에 `OP_BIOMETRIC_UNLOCK_ENABLED=false` 를 넣어 «앱 설정을 보러 가지 않게» 한다.** 비밀 복제 0 · 상주 프로세스 0 · 메모리 0 · plist 변경 0(tick.py 상수 1줄 + 설치본 갱신). **시험은 터미널 안에서만**(터미널 경로는 h1 에서 창 없이 성공 — 창이 뜰 수 없는 자리) 로그의 AppData 요청 줄 수로 판정(§4).
4. **시험이 «효과 없음» 또는 «판정 불가»면 사전 약속대로 R-F(파일 캐시)로 간다** — 터미널에서 1회 읽어 0600 파일에 두고 launchd 틱은 op 를 아예 안 부름. 창 0 은 구조로 보장(틱이 0600 토큰 파일 읽는 것은 지금도 매 틱 성공 중)되지만 **새 평문 사본이 생기고 이 맥은 FileVault 꺼짐** → 2순위.
5. **오빠 손 = 터미널 한 줄 `! bash /tmp/h<N>` 1회 · 클릭 0 · 창 0.**

## 1. 사실 (관측만)
| # | 관측 | 근거 |
|---|---|---|
| F1 | 터미널(Ghostty 19:56:32 기동 → tmux 2585 → claude): `op read` 2회 창 없이 1.8~2.3초 성공 | h1(10-17 22:47) · `ps` 조상 사슬 |
| F2 | h37: O1(op 책임) PROMPTING 1·허용 못 함 → timeout / O2·S1 timeout(PROMPTING 0 — 앞 창 떠 있음) / P1(python) 허용 → 32초 성공 authValue=2 / P2 새 프로세스 PROMPTING 재출현 → timeout | `/tmp/opprobe-20261018-100516.txt` |
| F3 | h39: O1 허용 → 7.9초 성공 / **O2 새 프로세스 PROMPTING 다시 1건** → authValue=2 8.8초 / **S1 주체 = op 경로로 PROMPTING** → timeout | `/tmp/opprobe-20261018-101140.txt` |
| F4 | TCC 로그(3시간): AppData PROMPTING 은 전부 launchd 시험·틱 구간(09:45·10:05·10:06·10:07·10:11·10:11·10:12) · 주체 = python 또는 op | `log show --last 3h`(읽기) |
| F5 | op 바이너리 문자열: `Library/Group Containers/2BUA8C4S2C.com.1password` · `settings.json` · `OP_BIOMETRIC_UNLOCK_ENABLED` · `OP_CACHE` · `op-daemon.sock` | `strings`(읽기) |
| F6 | 틱은 이미 매 틱 `~/.config/airag/` 의 0600 토큰 파일을 창 없이 읽는다(실패 코드가 `OP_SERVICE_ACCOUNT_UNAVAILABLE` 이 아니라 그 뒤 단계 `OP_READ_UNAVAILABLE`) | tick.py 295~303행 · 틱 로그 |
| F7 | 메모리: swap 사용 10.97G / 12.29G · `op daemon` 지금 1개(RSS 4MB) | `sysctl vm.swapusage` · `ps` |
| F8 | FileVault **꺼짐** · 코드 서명 인증서 0개 | `fdesetup status` · `security find-identity` |
| F9 | tick.py: op 자식 환경 = `OP_ENV_ALLOWLIST`(PATH·HOME·USER·LOGNAME·LANG·LC_*·TMPDIR) + 토큰 · 3병렬 · 시도 10.5초/호출 21초 · 이미 환경에 키가 있으면 op 를 안 부름(«Existing environment keys win») | tick.py 4·43~48·268~344행 |

## 2. 왜 터미널은 되고 launchd 는 안 되나 (라벨)
| 읽기 | 라벨 | 근거 |
|---|---|---|
| launchd 아래 맨 실행 파일(python·op)은 «세션 한정 허용»만 받아 실행마다 다시 묻는다 | **지지** | F2·F3 · 이전 처방 F5(`-67062`·`Session scoped auth is invalid`) |
| 터미널은 책임 주체가 앱 번들(Ghostty)이라 허용이 이어지거나 이미 있다 | **지지(결과) · 저장 형태 미확인** | F1 · 이 좌석은 TCC.db 를 못 읽음(전체 디스크 접근 없음 → Ghostty 는 FDA 가 아니라 «다른 앱 데이터» 허용을 가진 쪽으로 읽힘) |
| 창의 원인 = op 가 1Password 앱 설정을 열어 봄(앱 연동 확인) | **지지(문자열) · 미확인(경로)** | F5 · 서비스 계정 읽기 자체엔 앱이 필요 없음 |

## 3. 후보 비교 — 비밀 읽기를 «창이 안 뜨는 자리»로
| 후보 | 방법 | 클릭 0 | 비밀 노출면 | 재부팅·로그아웃 | 부하·메모리(swap 11/12.3G) | 운영 파일 변경 | 되돌림 | 창 0 을 로그만으로 시험 | 판단 |
|---|---|---|---|---|---|---|---|---|---|
| **R-E 앱 연동 끄기** | op 자식 환경에 `OP_BIOMETRIC_UNLOCK_ENABLED=false` 추가 | **조건부**(op 가 이 값이면 앱 설정을 안 보는 경우) | **변화 0**(지금과 동일) | 영향 없음(launchd 그대로) | **0** | plist 0 · runtime.json 0 · tick.py 상수 1줄 + 설치본 | 상수 제거 | **가능** — 터미널에서 기준/변경 두 번 읽고 AppData 요청 줄 수 비교(§4) | **추천** |
| **R-F 파일 캐시** | 터미널에서 op 로 1회 읽어 `~/.config/airag/store-keys`(0600)에 저장 → 틱은 파일에서 환경으로 넣고 op 미호출(틱의 «기존 키 우선» 경로 재사용) | **예(구조 보장)** | **새 평문 사본 3키** · 같은 폴더에 이미 0600 평문 토큰(더 강한 비밀)이 있어 «종류»는 같지만 FileVault 꺼짐이라 디스크 분실 시 노출 | 생존(파일) | 0(오히려 틱당 op 3회 감소) | tick.py(파일 원천) + 새 파일 · plist 0 | 파일 삭제 → op 경로 복귀 | 가능 — launchd 틱이 op 를 안 부름 = PROMPTING 0 이 당연 · 시험은 «op 호출 0 · TCC 요청 0» 확인 | **2순위(R-E 실패 시)** · 키 교체 때 재실행 필요 |
| R-K 키체인 캐시 | 같은 구조, 저장소만 로그인 키체인(`security` CLI · `-T /usr/bin/security`) | **미확인** — 키체인 잠김·접근 목록이 어긋나면 키체인 창이 뜸 | 암호화 저장(로그인 키체인) | 로그인 중 생존 | 0 | tick.py + 키체인 항목 | 항목 삭제 | **불가** — 창이 안 뜨는지 확인하려면 launchd 에서 읽어 봐야 하고 그 실행이 창을 띄울 수 있음(오빠 금지 조건) | 보류 |
| R-T tmux 상주 루프 | Ghostty 아래 tmux 세션에서 `while; tick; sleep 300` | 예(F1 과 같은 자리) | 변화 0 | **죽음** — 재부팅·로그아웃·zombie-clean 의 tmux 정리(상시 자율 허용)에 걸림 · 사람이 다시 띄워야 함 | 셸 루프 수 MB · 틱 python 은 지금과 같음 | 기동 체계 교체(plist 비활성) | plist 복귀 | 가능 | **비추** — 조용히 멈추는 운영 |
| ③ op daemon/소켓 | op 캐시 데몬 경유 | 아니오 — 데몬도 launchd 틱이 띄우면 같은 신원 · 앱 설정 확인과 무관 | — | — | 데몬 1개 4MB | — | — | — | **반증 쪽(약)** |
| ⑤ cron/at | launchd 대신 cron | 아니오 — 책임이 플랫폼 바이너리(cron)여도 h39 S1 처럼 주체가 op 로 잡혀 창 | — | 생존 | 0 | crontab | 복귀 | — | **반증(S1 유추)** · cron 은 별도 FDA 필요 |
| 1Password Connect 서버 | `OP_CONNECT_HOST` 로 로컬 서버 경유 | 예 | 서버 토큰 | 상주 컨테이너 | **수백 MB 상주**(swap 여유 1.3G) | 큰 설계 변경 | — | — | **비추(메모리)** |
| 앱 번들 래퍼(.app) | 책임 주체를 번들로 | 미확인 | 0 | 생존 | 0 | 새 번들 + plist | 삭제 | **불가** — 허용이 이어지는지 보려면 한 번 «허용»을 눌러야 함(클릭 금지) | 제외 |
| FDA 부여 | 시스템 설정 | 설정 클릭 1회 필요 | 0 | 생존 | 0 | 시스템 권한 | 해제 | — | **제외(클릭 · 범위 과대)** |

**추천 1개: R-E.** 이유 ①비밀 노출 변화 0·메모리 0·plist 0 ②터미널 안에서 «창이 뜰 수 없는» 조건으로 효과를 로그 줄 수로 판정할 수 있는 유일한 후보 ③실패해도 R-F 로 바로 넘어갈 판정이 같은 시험에서 나온다. 구현 메모(Nano 몫): `OP_ENV_ALLOWLIST` 와 별개로 «고정 추가 환경» 상수 1개(`{"OP_BIOMETRIC_UNLOCK_ENABLED": "false"}`) · 7초 룰 상한 그대로 · 값 미기록 회귀 시험 그대로. `OP_CACHE=false`(데몬 억제)는 **이번에 섞지 않는다**(한 번에 하나 · 데몬은 지금 1개·4MB).

## 4. 시험 계획 — 터미널에서만 · 클릭 0 · 창 0 (사전 약속)
Nano 가 만들 것: 계획 파일 1개 → ft-hil 등록 → 오빠 `! bash /tmp/h<N>` 한 줄(Claude Code 의 `!` = h1 과 같은 Ghostty→tmux 자리). **launchd 시험 라벨 0 · launchctl 0 · 운영 파일 0.**

순서와 내용:
1. **T0 기준**: h1 과 똑같이 `op read <키 1개 참조>`(토큰은 파일에서 셸 변수로 · 값은 «64자 hex 여부» 1비트만 남기고 버림) · 상한 10.5초.
2. 2초 쉼.
3. **T1 변경**: 같은 호출에 `OP_BIOMETRIC_UNLOCK_ENABLED=false` 만 추가.
4. 각 run 구간(시작~끝+1초)의 `log show --predicate 'subsystem=="com.apple.TCC" AND eventMessage CONTAINS "SystemPolicy"'` 에서 **접근자 `com.1password.op` 인 AUTHREQ_CTX 줄을 서비스·preflight 별로 집계** + PROMPTING 줄 수 + 결과 authValue.
5. 출력 = run·rc·ms·형식 통과·{AppData preflight=no 줄 수, AllFiles preflight=yes 줄 수, PROMPTING 줄 수}.

| 결과 | 읽는 법 | 다음 |
|---|---|---|
| **T0: AppData 요청 ≥1(허용으로 통과·PROMPTING 0) · T1: AppData 요청 0 · 둘 다 rc 0·형식 통과** | 이 값이면 op 가 앱 데이터를 안 연다 → launchd 에서도 묻을 대상이 없다 | **채택 R-E** → Nano 구현 + DA → 설치본 갱신 승인 → 재개 관찰 |
| T0: AppData 요청 0 (터미널에선 기록 자체가 안 남음) | **판정 불가**(기준선 없음) — 이 시험으로는 R-E 를 못 가름 | **R-F 로 간다**(launchd 창 위험이 있는 확인 시험은 하지 않음) |
| T0 ≥1 · T1 도 ≥1 | 값이 효과 없음 | **R-F 로 간다** |
| T1 rc≠0 또는 형식 실패 (T0 성공) | 이 값이 서비스 계정 읽기를 깨뜨림 | **R-F 로 간다** |
| 어느 run 에서든 PROMPTING ≥1 | 터미널 자리도 창이 뜸 — 전제(F1) 깨짐 | 즉시 중단 · Master 보고 · 후보 전부 재검토 |

**R-F 로 갈 때의 확인(역시 클릭 0)**: 쓰기는 터미널에서(R-E 시험과 같은 자리) · 파일 0600·소유자 본인·값 디스크 외 출력 0 확인 → 재개 뒤 첫 틱 로그에서 «op 호출 0»(probe 필드 비어 있음)·TCC 로그 해당 구간 op 요청 0 확인.

## 5. 운영 재개 (이번이 아니라 «다음 승인 건»)
- **재개 합격선(사전 약속)**: 재개 후 **연속 3틱 `status=ok`** · 그 3틱 구간 TCC 로그 AppData PROMPTING **0** · 오빠 클릭 0. **첫 틱에 PROMPTING 1줄이라도 나오면 즉시 `bootout`(오빠 HIL 도구) · 재시도 0** · Master 보고.
- R-E 는 launchd 첫 틱 자체가 «창이 안 뜬다»는 마지막 확인이다 — §4 T1 에서 AppData 요청 0 이 나온 경우에만 재개를 올린다(같은 바이너리·같은 환경이면 파일 접근은 책임 주체와 무관하게 같음).
- R-F 는 키 교체(`master_replaces_store_keys` 같은 사건) 때 터미널에서 다시 써야 한다 → 설치 문서·틱 실패 코드에 «캐시 없음/형식 불일치 → 터미널 재기록» 안내 1줄.

## 6. 하지 않을 것 / 하지 않은 것
- **하지 않을 것**: ①launchd 안에서 창이 뜰 수 있는 확인 시험(오빠 금지) ②허용 클릭을 요구하는 설계(R-D·R-S·앱 번들·FDA) ③상한·재시도 늘리기 ④tmux 상주 루프로 운영 이전 ⑤키체인 캐시를 launchd 에서 시험 ⑥`OP_CACHE` 등 다른 환경 값을 R-E 와 섞기 ⑦TCC.db 직접 수정·`tccutil reset`.
- **하지 않은 것**: `op` 실행 0 · launchctl 변경 0 · plist·runtime.json·설치본·DB 변경 0 · 비밀 값 출력 0 · push 0 · AskUserQuestion 0 · 서브에이전트 0. 실행한 것은 읽기뿐: 시험 결과 파일 2개 · `log show`(최근 3시간 TCC) · `strings`(op 바이너리) · `ps`·`sysctl`·`fdesetup status`. 쓴 파일 = 이 문서 1개(+ 스크래치 로그 사본).

## 7. 확인하지 못한 것
op 가 여는 실제 경로(`<private>`) · `OP_BIOMETRIC_UNLOCK_ENABLED=false` 가 서비스 계정 모드에서 앱 설정 확인을 건너뛰는지(§4 가 가름) · 터미널 자리에서 허용된 AppData 요청이 로그에 남는지(§4 T0 가 가름) · `aButtonAuth 5` 의 뜻 · Ghostty 의 허용 저장 형태.
