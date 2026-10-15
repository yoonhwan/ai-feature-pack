골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 · consumer 권한 팝업/타임아웃 해결. 이 문서는 설계 r5(발주 #2526 — 프로브 1회 결과 해석 + 다음 증거 단계).
작성: ft-airag-arch-claude#2 (architect, 2026-10-15) · 설계만 — 코드·운영 변경 0, **op 실행 0**, 키·토큰 값 열람 0(환경 변수는 «이름»만 확인) · 복사·커밋은 Master · r4(arch-20261015-opa-popup-design-r4.md)는 DA r3 재심 범위가 닫힌 자기완결본이며 **r4 에서 닫힌 항목(7초 룰 해석·전이표·회수 계약·합성 시험 (a)~(m)·S2·I-1)은 이 문서에서 다시 다루지 않는다.** 이 문서는 «새 사실 → 후보 → 다음 증거 한 단계»만 담은 자기완결본이다.

# 0. 요약 (먼저 읽기)

1. **결론:** 토큰도 네트워크도 필요 없는 `op --version`이 launchd 안에서 7초 안에 끝나지 않았다 → **(나) 간헐 타임아웃의 원인은 서비스 계정·키 읽기·네트워크 이전, 즉 «op 가 시작해서 초기화하는 구간»으로 좁혀진다**(이번 1회 한정). 같은 7초 구간에 **1Password 팝업을 만드는 종류의 TCC 요청(AppData)은 0건**이었으므로 이번 정지는 (가) 팝업과 «같은 사건»이라는 증거가 없다. 두 문제를 분리해 관리하는 방향은 유지한다.
2. **새 사실(읽기 전용으로 내가 다시 확인):** `op`(PID 70485)는 시작 0.1초 뒤 첫 로그를 남겼으니 **실행 자체는 시작됐고 그 뒤에 무언가를 기다렸다**(exec 단계에서 막혔다는 설명은 약화). 기존 `op` 프로세스 2개는 **둘 다 `op daemon`**이고, **같은 소켓 경로 하나를 놓고 pid 파일은 서로 다른 두 폴더에 갈라져 있다**(§2). TCC 로그는 **«없어서»가 아니라 프로브 안의 `log show` 호출이 실패해서 «관측 불가»가 됐다**(§3).
3. **후보를 좁힌다(§4):** 데몬·소켓·pid 파일 분열(H5) ↑ · op 내부 대기(H7) 미정 · 시스템 부하·exec 평가(H6) 약 · 책임 프로세스 귀속(H1) «관측은 되나 정지 원인 증거 없음» · 앱 통합 AppData(H2) 이번 구간에선 증거 없음.
4. **권고 1안 = 오빠 터미널에서 `op --version`만 3가지 조건으로 6번 재는 «대조 측정 1회»**(§6). 토큰 없음·네트워크 없음·launchd 작업 없음·팝업 위험 낮음. 결과 하나로 «launchd 고유 / 환경 변수 / 공유 상태(데몬·설정) / op 자체·머신 / 간헐·콜드»를 가른다. **기존 프로브는 한 줄도 바꾸지 않는다**(신규 파일 1 + 시험 1). 후퇴안 = 기존 프로브를 수정 없이 한 번 더 실행(§7).
5. **오빠께 드릴 질문은 1개**(§8): 대조 측정 스크립트 `! bash /tmp/h<N>` 1회 실행 승인. 실제 질문은 구현·가벼운 DA 확인 뒤 Master 가 올린다.
6. **변하지 않는 것:** consumer 는 계속 disabled · tick.py 는 아직 `timeout=30`(I-1 미착수) · 서버 18712·18703 복구 통보와 HELM 재개 전에는 켜지 않는다.

# 1. 프로브 결과 사실 (result.json — 값 없는 요약)

| 항목 | 값 |
|---|---|
| 실행 | 2026-10-15 19:44:59 KST 시작(UTC 10:44:59) · mode=production · 완료(complete=true) · 결론 `p0_blocked` |
| S0 | consumer disabled=true · loaded=false · `op` 프로세스 2개 · 소켓 mtime 10-15 14:14:26 KST |
| P4 (my.1password.com TCP+TLS) | success **707 ms** |
| P0 (`op --version`, 토큰 없음, 실제 HOME, launchd 작업) | **timeout 7038 ms** · rc=-9(프로브가 종료) · reaped=true · tcc=`unknown_log_unavailable` |
| P2·P1·P1b | `skipped_prior_unresolved` (전이표대로 실행 안 됨 → **서비스 계정 토큰 파일은 한 번도 읽히지 않았다**) |
| 정리 | 라벨·plist·pids 잔존 0 |

- P4 는 같은 launchd 작업 안에서 python 자식 프로세스를 띄워 707 ms 에 끝났다 → **«launchd 에서 자식 프로세스가 느리다»는 일반 가설은 약화.** 막힌 것은 `op` 한정이다(1회 관측).
- P0 의 env 는 `PATH·HOME·USER·LOGNAME·LANG·LC_ALL·LC_CTYPE·TMPDIR` 허용 목록(probe.py:102) — 토큰·`OP_*` 없음.

# 2. 읽기 전용 신규 사실 (내가 이번 턴에 확인 — `op` 실행 0)

## 2.1 `op` 프로세스 2개 = 둘 다 `op daemon`
| | 데몬 A (PID 41014) | 데몬 B (PID 63620) |
|---|---|---|
| 시작 | 10-15 13:08:20 | 10-15 14:14:26 |
| 부모 | launchd(1) | launchd(1) |
| 환경 «이름»만 확인 | tmux/Ghostty 셸 환경 전체(TERM_PROGRAM=tmux, `OP_SERVICE_ACCOUNT_TOKEN` 등 서비스 계정 변수 이름 존재, `TMPDIR` 있음, PWD=BYZ 하네스 작업 폴더) | **`HOME`·`OP_SERVICE_ACCOUNT_TOKEN`·`PATH` 세 개뿐**(`TMPDIR` 없음) |
| 열린 소켓(lsof) | `~/.config/op/op-daemon.sock` | `~/.config/op/op-daemon.sock` (같은 경로) |
| pid 파일 | `/var/folders/…/T/com.agilebits.op.501/op-daemon.pid` → 41014 | `/private/tmp/com.agilebits.op.501/op-daemon.pid` → 63620 |
| 상태 | S(대기) · CPU 0.76초 | S(대기) · CPU 0.56초 |
| 바이너리 | `/opt/homebrew/Caskroom/1password-cli/2.32.1/op` | 같음 |

- **사실:** 두 데몬이 **소켓 경로는 하나(HOME 기반)**, **pid 파일 위치는 `TMPDIR` 유무로 둘로 갈렸다.** 소켓 mtime(14:14:26)이 데몬 B 시작 시각과 같으므로 **현재 소켓은 B 가 만든 것**이다(추론: A 는 이름이 지워진 소켓을 쥔 채 남은 상태 가능).
- **둘 다 우리 consumer 가 만든 것이 아니다:** consumer 로그(`launchd.out.log`)의 마지막 기록이 10-13 12:06 이고, A 의 부모 환경은 BYZ 하네스 셸, B 는 최소 환경 + 서비스 계정 변수만 가진 다른 호출(출처 미확인). Master 의 «다른 사용 중» 판단과 일치.
- **미확인:** `op --version`이 데몬에 접속하는지(아마 아님 — 모름), pid 파일을 먼저 읽는지, 소켓이 어긋나면 어떻게 행동하는지 → §6 대조 측정 C 가 가른다.
- 1Password.app 은 10-14 10:09 부터 실행 중(PID 2063). `op` 바이너리: 서명 identifier `com.1password.op`, TeamIdentifier `2BUA8C4S2C`(앱과 같은 팀), hardened runtime, **`com.apple.quarantine`(값 `0381;6989e0f1;;…`)·`com.apple.provenance` 속성 존재**(quarantine 비트 의미는 미확정 — 단정하지 않는다).

## 2.2 같은 7초 구간의 시스템 로그(사후 조회 · 읽기 전용)
- 구간 19:44:58~19:45:10, `subsystem == "com.apple.TCC"` → **0.45초·41줄 정상 조회됨.** 요청은 **1건뿐**:
  - 19:45:06.508 `syspolicyd` → `tccd`: `kTCCServiceDeveloperTool`, **preflight(조회 전용)**, 대상 = 프로브의 python(uv python3.13, **PID 69892 = result 의 프로브 자신**) → 결과 **`Service … does not allow prompting; returning denied`**(= 팝업 없음).
  - **AppData(`kTCCServiceSystemPolicyAppData`) 요청 0건**, 프롬프트 0건.
- `op`(PID 70485)의 로그는 **19:45:00.487 한 줄**(`libsystem_info … Retrieve User by ID`, 시작 0.1초 뒤)뿐 — Go 바이너리라 os_log 가 적어 «그 뒤 아무것도 안 했다»는 뜻은 아니다. **다만 프로세스가 시작 0.1초에 이미 코드를 실행 중이었으므로 «exec 평가에서 7초 막힘»은 약화.**
- 같은 시각 `syspolicyd` 가 초당 수십 건 프로세스를 추적(`provenance`·`qtn_proc` 오류 다수) — 머신이 바쁜 상태(현재 load average 10.3 / 14코어, `syspolicyd`·`XprotectService` 가 CPU 상위). **원인 귀속은 없음.**

# 3. TCC 로그가 `unknown_log_unavailable` 이었던 이유 (코드 대조)

| 가능한 사유 | 이번 증거 |
|---|---|
| (a) 그 구간에 TCC 로그가 «0줄» | **아님** — 같은 창에 41줄 존재(§2.2) |
| (b) 분류기가 «우리 것 PID 인데 service 줄 없음»으로 부분 → unknown | **아님으로 보임** — 해당 그룹(msgID 295.634)에 `service=` 줄이 있고, AppData 가 아님 → 분류기대로면 `none_logged_ok` 가 나왔을 것 |
| (c) 프로브 안의 `log show` 호출이 **rc≠0 / 3초 한도 초과 / 예산 부족 / 실행 오류** | **남는 후보**(probe.py:431-456 `observe_tcc` — 이 네 경우 모두 같은 `unknown_log_unavailable` 한 값) |
- 결론: **«로그가 보존·권한 한계로 비어 있다»가 아니라 «launchd 작업 안에서 우리가 부른 `log show` 가 성공하지 못했다»**가 가장 가깝다. 어느 하위 사유인지는 **프로브가 구분해 기록하지 않아 미확정**(내 셸에서는 0.45초 성공).
- **재채집 방법(오늘 방식):** 프로브가 끝난 뒤 **셸에서 사후 조회**(`/usr/bin/log show … --predicate 'subsystem == "com.apple.TCC"'`, 7초 한도, 결과 창 [시작−0.5초, 끝+2초]) — 내가 이미 이 방식으로 재채집했다. 로그가 살아 있는 동안(보존 길이 미확인, 오늘 구간은 조회됨) 언제든 가능하며 **프로브를 고치지 않고도** 쓸 수 있다.
- **프로브 최소 보강(선택·§7):** `observe_tcc` 가 사유를 값 없는 열거형 한 필드(`log_rc_nonzero / log_timeout / spawn_error / budget_short / zero_lines`)로 남기게 한다.

# 4. 후보 좁히기 — 새 사실로 본 서열 (판정이 아니라 «다음에 무엇을 재야 하나»)

| 후보 | 내용 | 이번 증거 | 서열 |
|---|---|---|---|
| **H5 데몬·소켓·pid 파일 분열** | 소켓은 HOME 기준 1개, pid 파일은 TMPDIR 기준 → 두 데몬이 서로 다른 pid 파일을 가짐. `op` 가 pid 파일로 «데몬 있음»을 보고 소켓에서 응답을 기다릴 수 있음 | **분열은 사실**(§2.1). 영향은 가설 — `--version`이 데몬에 닿는지 자체가 미확인 | **높음(재볼 가치 최대)** |
| **H7 op 내부 대기** (업데이트 확인·키체인·설정 읽기 등 op 가 시작 때 하는 다른 일) | 토큰·계정 조회 이전 | 네트워크 일반 도달은 정상(P4 707 ms) — 단 `op` 가 쓰는 다른 호스트는 미확인. 시작 0.1초 뒤 코드 실행 확인 | 중(미정) |
| **H1 책임 프로세스 귀속** | launchd 작업의 python 이 «책임 프로세스»로 평가됨 | **관측됨**: syspolicyd 가 python(69892)에 대해 DeveloperTool preflight → denied, **프롬프트 없음**. 다만 이는 정지 «원인»이라는 증거가 아님(op 는 이미 실행 중) | 낮음~중 |
| **H6 시스템 부하·exec 평가** | 바쁜 syspolicyd/XProtect 가 `op`(quarantine 속성 있음)를 지연 | load 10~14 / 14코어, 상위 CPU 에 syspolicyd·XprotectService. 그러나 op 코드가 0.1초에 실행 중 → exec 평가 정체는 약화 | 낮음 |
| **H2 앱 통합(AppData)** | op 가 1Password.app 컨테이너를 만지다 TCC 대기 | **이번 구간 AppData 요청 0건** → 이번 정지의 설명으로는 증거 없음. (팝업(가)의 후보로는 r4 §2 그대로 유지) | 낮음(이번 정지 한정) |

- **팝업(가)에 대한 새 정보:** 이번 구간엔 팝업이 없었다. 이전 TCC AppData AUTHREQ 3건(10-13 11:44:00, 주체 uv python3.13)은 «다른 시점의 다른 사건»으로 남는다. **(가)·(나)가 같은 사건이라는 증거는 여전히 없다** — 단 (나)의 범위가 «키 읽기»에서 «op 시작 구간»으로 이동했으므로 r4 의 S2(키 읽기 경로 검증)는 **P0 가 풀리기 전까지 보류**한다(P0 가 7초에 안 끝나는 op 로 키 읽기를 재도 의미가 없다).
- **n=1 한계:** 프로브 P0 는 1회 관측이다. 간헐일 수 있다 → §6 의 «같은 조건 2회» 설계가 이를 함께 본다.

# 5. 무엇을 가르는지 — 후보별 «다음 한 번»의 선택지 비교

| 선택지 | 가르는 것 | 오빠 부담 | 위험 | 되돌림 | 기존 프로브 |
|---|---|---|---|---|---|
| **E1 오빠 터미널 대조 측정**(A/B/C, §6) | launchd 고유 vs 환경 변수 vs 공유 상태(데몬·설정) vs op 자체·머신 vs 간헐 | `! bash /tmp/h<N>` 한 줄 · 약 50초 이내 | 토큰 없음. 팝업 가능성 낮음(있으면 누르지 말 것). `op --version`이 데몬을 새로 띄울 가능성(전후 개수 기록) | 임시 폴더 자동 삭제 · 데몬은 건드리지 않음 | **무수정**(신규 파일) |
| E2 같은 launchd 프로브 재실행 | P0 가 **간헐인지 고정인지** 만 | 한 줄 · 최대 75초 · 프로브 팝업 고지 그대로 | r4 §7 고지 그대로 | 자동 정리 | **무수정 재사용 가능** |
| E3 launchd 에서 `op` 대신 다른 대조 바이너리 | launchd·python 책임 프로세스 효과 | 한 줄 | 낮음 | 자동 정리 | **변경 필요**(프로브에 대조 단계 추가 → DA 재심). P4(python 자식 707 ms)가 이미 일반 launchd 자식 대조군 역할을 해 **새 정보 한계 작음** |
| E4 격리 HOME 하의 launchd P0' | 공유 상태(H5) | 한 줄 | 낮음 | 자동 정리 | **변경 필요**(전이표가 P0 막히면 P2 를 건너뜀 — 건너뛰지 않게 바꾸면 r4 닫힌 항목 재개) |
| E5 `op` 정지 중 상태 스냅샷(`ps` 상태·`lsof` 범주 불리언) | **어디서 기다리는지**(소켓? 파일? 네트워크?) | 한 줄 | 낮음(읽기 전용) | 없음 | **변경 필요**(약 40줄 + 시험 + DA) |
| E6 `op` 프로세스 2개의 정체 읽기 전용 확인 | 데몬 출처 | 0 | 0 | — | **완료**(§2.1, 내가 수행) |

- E3·E4 는 launchd 를 거치므로 **프로브 전이표(r4 §4.3)를 건드리는 변경이 필요**해 비용이 크고, E1 이 같은 질문을 «launchd 없이» 더 싸게 갈라서 **E1 → 필요 시 E5** 순서를 권한다.
- **«op 프로세스 2개와 소켓 mtime 10-15 의 의미»:** 둘은 `op` CLI 가 자동으로 띄운 **데몬**이고(CLI 일회성 호출이 아님), 소켓 mtime = 데몬 B 가 소켓을 새로 만든 시각이다. 현재 소켓은 B 쪽이며, 그 이전에 시작한 A 는 pid 파일만 남은 별도 위치에 있다.

# 6. 권고 1안 — E1 «오빠 터미널 대조 측정» 설계

## 6.1 측정 조건 3가지 × 2회 (순서 A,B,C,A,B,C)
| 조건 | 환경 | 무엇을 바꾸나 |
|---|---|---|
| **A** 오빠 터미널 평소 환경 | 현재 환경에서 **`OP_*` 변수만 모두 제거**(토큰·`OP_CONFIG_DIR` 등 제거) | 기준선. «평소 터미널에서는 빠른가» |
| **B** 프로브와 같은 최소 환경 | `env -i` 와 동등: `PATH·HOME·USER·LOGNAME·LANG·LC_ALL·LC_CTYPE·TMPDIR` 허용 목록만(probe.py:102 와 같은 목록) | A 와 B 의 차이 = **환경 변수 효과**(launchd 효과와 분리) |
| **C** B + 격리 설정 | B + `HOME`=새 임시 폴더(0700), `OP_CONFIG_DIR`=`<임시>/.config/op` | B 와 C 의 차이 = **공유 상태(`~/.config/op` 소켓·데몬·설정) 효과** |

- 모든 실행은 같은 명령: 절대 경로의 `op --version`(프로브와 같은 해석: PATH 로 찾은 `op`). **토큰·계정 조회·네트워크 호출 없음**(`--version`).
- 각 실행: **시도 1회 7.0초 · 재시도 0**(2회차는 «재시도»가 아니라 별도 측정 라운드. 7초 룰 준수 — 7초 밖 관측은 하지 않는다) · 전체 마감 60초.
- 종료 계약: **r4 §4.6 «자식 프로세스 회수 계약» 그대로** — 시간 초과 시 **직접 자식만** 종료 → 유한 대기 2초 → 파이프 회수 ≤1초 → 확인 전 `reaped` 미기록. 공유 데몬·미식별 후손·광역 종료·프로세스 그룹 종료 금지. SIGINT/TERM/HUP 는 정리 후 명시 종료(130/143/129).
- 전후 측정(읽기 전용, PID·시작 시각은 비기록): `op` 데몬 개수(전·후) · `~/.config/op/op-daemon.sock` mtime 변화 여부(불리언) → **`op --version`이 데몬에 닿는지 부수 증거**.

## 6.2 기록 필드 (값 없음)
실행마다: `variant(A/B/C) · round(1/2) · status(success/timeout/spawn_error/bad_output) · elapsed_ms(monotonic) · rc · reaped · child_exit_unconfirmed`. `success` = rc 0 이고 stdout 첫 줄이 버전 정규식 `^\d+\.\d+\.\d+` 에 맞음(내용 비기록, 맞음/아님 불리언만). 전체: `daemon_count_before/after · sock_mtime_changed · conclusion`.

## 6.3 결론 열거형 (구현 가능한 단일 우선순위표)
조건별 요약: 각 조건 V 는 두 라운드가 모두 success=`fast` · 모두 timeout=`slow` · 그 밖(섞임 포함)=`mixed`.

| 우선순위 | 조건 | `conclusion` | 다음 증거 단계 |
|---|---|---|---|
| 1 | 실행 중 `spawn_error`/`bad_output` 하나라도 | `inconclusive_error` | 원인 먼저(스크립트·경로) |
| 2 | 어느 조건이든 `mixed` | `intermittent_or_cold_start` | 같은 측정 1회 더 · 첫 호출만 느린지(콜드) 확인 → 콜드면 **I-1 의 7초 룰 예외 여부를 오빠 결정으로 상신** |
| 3 | A·B·C 모두 `fast` | `terminal_fast` | **launchd 컨텍스트 고유** — 책임 프로세스·세션 후보(H1) 상승, 다음 = E5 스냅샷 또는 launchd 변형 |
| 4 | A·B·C 모두 `slow` | `slow_everywhere` | **op 바이너리·머신 상태** 문제(컨텍스트 무관) — 다음 = E5 스냅샷(어디서 기다리나) |
| 5 | A=`fast` 이고 B=`slow` | `env_dependent` | **환경 변수 허용 목록**에 빠졌거나 방해하는 변수 → 변수 이분 탐색 |
| 6 | A=`slow`, B=`slow`, C=`fast` | `shared_state_dependent` | **데몬·소켓·설정 공유(H5)** — ⑤ 격리 가치 상승, 기존 데몬 정리는 **별도 HIL**(다른 사용 중이라 건드리지 않음) |
| 7 | A=`fast`, B=`fast`, C=`slow` | `isolated_only_slow` | 빈 설정 첫 초기화가 느림 — 격리 경로(⑤) 설계 재검토 |
| 8 | 그 밖 | `mixed_unexpected` | 원시 값 공유 후 판정 |
- 표는 위에서 아래로 처음 맞는 줄 하나만 적용한다(합성 시험으로 전 조합 고정).

## 6.4 구현 범위 (최소 변경 — 신규 2파일, 기존 파일 0줄 변경)
- 신규 `feature-pack/rag-consumer/ops/probe-opa/compare.py`(약 100줄, python `-I`, 단일 파일, `probe.py` import 없음 — 결합 방지) + `compare.sh`(진입 한 줄, 75초 상한 아님 → **전체 60초 상한**, probe.sh 의 시그널 정리 패턴 차용) + `tests/test_compare_opa.py`.
- `probe.py`·`probe.sh`·`tick.py` **변경 0**. 레지스트리 528 불변.
- 합성 시험(가짜 `op` 스크립트로, 실제 `op` 호출 0): ① 전 조합의 결론 표(우선순위 1~8) ② 시간 초과 시 직접 자식만 종료·회수 ③ 후손이 파이프를 쥐고 있어도 마감 불변(r4 (k) 동치) ④ `OP_*` 변수가 A 에서 제거됨·B/C 에서 허용 목록 외 전부 없음 ⑤ 출력·결과 파일에 환경 값·stdout 내용 0 ⑥ SIGINT 후 임시 폴더 정리 ⑦ 임시 폴더 0700·종료 시 삭제 ⑧ 전체 60초 초과 불가.
- `op` 실행은 **오빠가 한다**(HIL, 프로브 선례와 같은 `! bash /tmp/h<N>` 한 줄). 구현자·Master·나는 `op` 를 실행하지 않는다. **구현 DA(가벼운 1회 — 오빠 손에 가는 스크립트이므로)는 Master 가 소환.**

# 7. 후퇴안 · 보강안

- **후퇴안(코드 변경 0):** 기존 프로브를 **수정 없이 한 번 더 실행**(E2). 장점: 구현·DA 0, r4 고지·승인 문구 그대로. 한계: **launchd 고정 조건이라 «고정 vs 간헐»만 가르고 환경·공유 상태·컨텍스트 분리는 못 한다.** P0 가 또 막히면 P2·P1·P1b 는 다시 건너뛴다(§1) — 새 정보가 작다.
- **보강안(E1 결과가 `terminal_fast`·`slow_everywhere` 일 때만):** ① 프로브 `observe_tcc` 사유 열거형 1필드 추가(§3) ② P0 정지 중 상태 스냅샷(`ps` 상태·CPU 시간·`lsof` 범주 불리언: 소켓/Group Containers/`.config/op`/`com.agilebits`) — 변경 범위 `probe.py` 약 40줄 + 시험 + DA 재심(r4 전이표·회수 계약은 불변, 관측 필드만 추가). **지금은 만들지 않는다**(E1 이 필요성을 가른다).
- **사후 TCC 재채집은 프로브 수정 없이:** E1·E2 어느 쪽이든 끝난 뒤 내가(또는 checker 가) 셸에서 해당 창의 `log show` 를 읽기 전용으로 조회한다.

# 8. 오빠께 드릴 질문 1개 (Master 가 구현·DA 확인 뒤 올림)

> **정정 한 줄:** 지난 프로브 1회 결과, 토큰 없이도 `op --version`이 launchd 안에서 7초 안에 안 끝났습니다. 서비스 계정 방식은 이미 쓰는 중이고, 지금 막힌 곳은 키 읽기보다 이전(op 시작 구간)으로 보입니다. 팝업과 타임아웃이 같은 원인인지는 아직 모릅니다.
>
> **질문:** 오빠 터미널에서 `! bash /tmp/h<N>` 한 줄을 1회 실행해 주세요. `op --version`만 6번 재는 스크립트입니다(토큰·네트워크·계정 조회 없음, 각 7초 이내, 전체 60초 이내, 임시 폴더는 끝나면 지워짐, 기존 1Password 데몬은 건드리지 않음). 혹시 1Password 창이 뜨면 누르지 말고 그대로 두세요. consumer 는 계속 꺼 둡니다.

# 9. 미확인 (이 문서가 채우지 않는 것)

- `op --version`이 데몬·소켓·pid 파일을 실제로 건드리는지 · 데몬 B(최소 환경 + 서비스 계정 변수만)를 만든 호출의 출처 · 데몬 A·B 가 공존하게 된 경위.
- 프로브 안 `log show` 가 실패한 하위 사유(rc/시간 초과/예산) · 7초를 넘겨서 `op --version` 이 정상 종료하는지, 넘긴다면 얼마인지(7초 룰 때문에 이번 설계는 7초 밖을 재지 않는다 — 필요하면 «측정용 상한 확장은 규칙 예외라 오빠 결정»으로 별도 상신).
- 10-12~10-13 타임아웃 기간에 데몬·소켓 분열이 있었는지(로그 보존 한계로 사후 확인 불가).
- quarantine 속성 값 `0381` 의 비트 의미 · 이것이 실행 평가 지연에 관여하는지.
- (가) 팝업의 재현 조건 — 이번 프로브 구간에는 팝업이 없었다.

# 10. 변경·보류 요약

| 항목 | 상태 |
|---|---|
| 프로브 코드(`probe.py`·`probe.sh`) | **변경 0**, 구현 DA PASS 상태 유지 |
| 신규 | `compare.py`·`compare.sh`·`tests/test_compare_opa.py` — **구현은 Master 발주 뒤** |
| 7초 룰 구현(I-1, tick.py:103 `timeout=30`) | 미착수 · 콜드 스타트 7초 초과 가능성은 E1 결과로 가늠 |
| S2(키 읽기 경로 검증) | **P0 가 풀릴 때까지 보류** |
| consumer | disabled 유지 |
