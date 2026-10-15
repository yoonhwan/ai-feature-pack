골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰. 이 문서는 «consumer 가 팝업 없이 상시 가동되게 하는 길» 의 원인 규명 계획과 해결안 비교다.
작성: ft-airag-arch-claude#2 (architect, 2026-10-15) · 설계만 — 코드·운영 변경 0, op 실행 0, 값 열람 0. DA 미경유(Master 가 소환). ※ 브리프가 정한 경로 feature-pack/rag/docs/artifacts/arch-20261015-opa-popup-design.md 는 architect 쓰기 훅(ft-worker-guard)이 막아, 허용 경로인 이 위치에 썼다 — Master 가 복사.

# 0. Master 권장 전제 오류 (사실)

Master 가 오빠께 «서비스 계정 토큰 방식으로 바꾸면 팝업이 구조적으로 사라진다» 고 권했고 오빠가 «권장으로» 라 답했다. **이 권장의 전제는 틀렸다.**

- 설치본은 **이미** 서비스 계정 토큰 방식이다: `tick.py:79,92,98` (token_file 읽어 `OP_SERVICE_ACCOUNT_TOKEN` 을 op 자식 env 에 주입) · 자격 파일 `~/.config/airag/credential-source.json` 은 `token_file` 키를 가지고 `~/.config/krb/op-sa-token`(0600) 을 가리킴 (checker Q2).
- 팝업·타임아웃 틱은 그 방식 **그대로** 도는 중에 났다 (checker ROOT_OBSERVATION · Q3 key_fact_for_architect). «방식을 바꾼다» 에 해당하는 코드·자격 변경은 현재 트리에 없다.
- 따라서 오빠의 «권장으로» 는 **방식 이름에 대한 승인이 아니라 목표에 대한 승인으로만 유효**하다. 오빠 의도 = «팝업이 영구히 안 뜨고 consumer 가 상시 안정 가동». 결정 대상은 이 목표이고, 방식은 아래 증거로 정한다.
- 이 전제 오류의 정정은 Master 가 오빠께 한 줄로 알린다 (질문 1개와 같은 메시지, §6).

# 1. 지금까지 확인된 사실 (이번에 새로 본 것 포함, 전부 읽기 전용)

| # | 사실 | 근거 |
|---|---|---|
| F1 | 같은 plist(10-02 15:22)·같은 서비스 계정 방식으로 **10-02 launchd 틱 ok 6건** — 그때는 op 가 막히지 않았다 | `~/.local/share/airag/logs/tick-20261002.log` 상태 집계 (ok 6 · key_error 1 · runtime_error 1) |
| F2 | 10-02 15:53 이후 10-11/12 로그 전까지 틱 로그 없음 (이유 미확인 — 정지 상태였던 것으로 보이나 기록 못 봄) | 로그 디렉터리 파일 목록 (tick-20261002 → tick-20261011) |
| F3 | **1Password.app 이 10-08 18:05 에 갱신**됨 (`/Applications/1Password.app` mtime). op 바이너리는 02-05 그대로 (2.32.1) | `stat` |
| F4 | 첫 `TimeoutExpired` 는 10-12 08:10 대 (launchd RunAtLoad 자동 재가동). 로그 파일 `tick-20261011`(UTC 날짜, 6건)→`12`(212)→`13`(13). **10-13 10:58 재부팅 전에 이미 225건** 났다 | 로그 집계 · `last reboot` (10-12 02:12 · 10-13 10:58 · 10-14 03:30) |
| F5 | TCC `kTCCServiceSystemPolicyAppData` AUTHREQ 3건(요청 주체 uv python3.13)은 **10-13 11:44 한 시점뿐** — 재부팅 *뒤*. 10-12 08:10~10-13 10:57 사이 225건 타임아웃이 같은 팝업 때문이었다는 증거는 **없다** | master-progress.md:172 · 이번에 같은 구간(11:43~11:46) `log show` 재조회 = 0줄 (통합 로그 보존기간/권한 한계, 속성 필드 재확인 못 함) |
| F6 | 런타임 python = `~/.local/share/uv/python/cpython-3.13.12-…/bin/python3.13`, **adhoc 서명·TeamIdentifier 없음**, mtime 09-03 (변경 없음). 서명 해시가 바뀌어서 허용이 풀렸을 가능성은 낮다 | `codesign -dv` · `stat` |
| F7 | 1Password 컨테이너가 **둘**: `2BUA8C4S2C.com.1password`(구형 이름, mtime 작년 11-20) · `group.2BUA8C4S2C.com.1password`(09-28). op 는 TeamIdentifier=2BUA8C4S2C (앱과 같은 팀) | checker Q3 · `stat` |
| F8 | `~/.config/op/op-daemon.sock` mtime 10-15 14:14 = 지금도 누군가 op 를 쓰는 중 (주체 미확인) | `stat` |
| F9 | op 호출 지점은 `tick.py:100-113` 한 곳. `ThreadPoolExecutor(3)`, `timeout=30`, env 허용목록 + 토큰. 설치된 plist 에는 PATH 만 있음 | checker Q1·Q4·Q5 |
| F10 | consumer 는 지금 `bootout+disable` (10-13 planner). 18712·18703 서버 기동 통보 대기라 **지금 consumer 가 꺼져 있는 것 자체는 손실이 아니다** | master-progress.md:174 |

## 1.1 사실이 말하는 것 / 말하지 않는 것

- «서비스 계정 모드면 앱 컨테이너를 안 건드린다» 는 이 환경 실측과 맞지 않는다 (F5 의 AUTHREQ 는 이미 토큰이 주입된 틱에서 났다). 단 그 AUTHREQ 의 **접근 주체(op 인지 python 인지)** 와 **대상 경로** 는 로그가 없어 아직 모른다.
- **타임아웃과 팝업은 별개 사건일 수 있다 (F4+F5).** 225건은 팝업 증거가 없는 구간이다. 팝업이 원인이라는 가설은 11:44 의 3건만 설명한다. 나머지는 (a) 같은 팝업이 재부팅 전에도 뜬 채 쌓여 있었거나 (b) 토큰 만료·폐기 (c) 네트워크 미도달 (d) op 데몬 대기 중 하나일 수 있다. **타임아웃만으로는 원인을 가르지 못한다.**
- F1+F3: 정상 → 실패 사이에 **앱 갱신(10-08)** 이 끼어 있다. 가장 싼 설명 후보는 «앱 갱신으로 컨테이너 접근 정책/경로 동작이 바뀌었다» 이다. 가설일 뿐 검증 전.

# 2. 원인 후보와 가르는 관측

| 후보 | 내용 | 가르는 관측 (어느 프로브에서) | 맞다면 |
|---|---|---|---|
| H1 책임 프로세스 귀속 | op(같은 팀)가 컨테이너를 여는데 launchd 작업의 책임 프로세스가 팀 없는 adhoc python 이라 «다른 앱 데이터 접근» 으로 판정 | TCC 로그 속성: `accessing=op` · `responsible=python3.13` (프로브 로그 추출) · P3(disclaim 스폰)에서만 통과 | ⑦ 후보 |
| H2 op 의 앱 통합 탐색 | 서비스 계정 모드여도 op 가 시작 시 데스크톱 앱 컨테이너/소켓을 probe | P0(`op --version`, 자격·네트워크 없음)에서도 지연/AUTHREQ · P2(격리 HOME)에서 사라짐 | ⑤ 후보 |
| H3 앱 갱신이 허용/경로를 바꿈 | 10-08 갱신 후 이전 허용이 무효이거나 구형 컨테이너 접근이 새로 보호 대상이 됨 | 단독 증명 어려움 — H1/H2 가 맞고 F1 과 시기가 맞으면 정황으로 채택 | 해결안은 H1/H2 와 동일 |
| H4 허용 해시 불일치 | python 변경으로 허용 무효 | **F6 로 기각에 가깝다** (python mtime 09-03) | — |
| H5 팝업과 무관한 지연 | 토큰 폐기/만료, 1Password 서버 도달 불가, op 데몬 대기 | P4(도달성) · P0 가 즉시 통과인데 P1 만 지연/비0 rc · P1 의 rc/출력 분류(값 아닌 에러 클래스) | 팝업 해결안은 무효 → 토큰 재발급(오빠) 또는 네트워크 조치 |
| H6 틱 간 중첩 | 틱이 30초 넘게 걸려 쌓임 | 틱 로그 간격은 이미 5분 균일 (낮은 가능성) | — |

# 3. 증거 수집 계획 (op 직접 실행 금지 — 오빠가 한 번 실행하는 `! bash /tmp/h<N>` 한 줄 내용)

Master 가 `ft-hil.sh --add <계획 파일>` 로 `/tmp/h<N>` 을 만든다. 계획 파일 내용(아래)은 **읽기 전용·값 비출력·종료 후 정리**다. 시크릿 항목을 읽는 `op read` 는 **쓰지 않는다** (프로브는 `op --version` 과 `op user get --me` 뿐 — 후자는 계정 타입만 알려 준다).

## 3.0 선행(사람 손 0, Master/checker 가 이미 할 수 있는 것)
1. `log show --info --debug --start '2026-10-12 08:00' --end '2026-10-13 11:50' --predicate 'subsystem == "com.apple.TCC"'` 를 `eventMessage CONTAINS "AppData"` 로 좁혀 재시도 — 보존기간 밖이면 0줄(이번 시도 0줄). 0줄이면 프로브(3.2)가 현재 시점 속성을 잡는다.
2. `codesign -dv` 로 op·python 서명(이미 함: F6)·`launchctl print-disabled` (`com.airag.consumer` => disabled 확인됨).

## 3.1 프로브 환경 (운영 접촉 0)
- 임시 디렉터리 `PROBE=$HOME/.local/share/airag/probe-opa-$(date +%Y%m%d-%H%M%S)` (0700). 임시 LaunchAgent 라벨 `com.airag.probe-opa-<ts>` — **운영 `com.airag.consumer` plist·runtime.json·DB·credential-source.json 은 읽기(토큰 경로 얻기)만, 쓰기 0.**
- **launchd 컨텍스트에서 돌려야 한다.** 터미널에서 직접 돌리면 책임 프로세스가 Terminal(이미 허용 상태일 수 있음)이라 재현이 안 된다. 그래서 임시 plist 가 `~/.local/share/airag/runtime/bin/python -I $PROBE/probe.py` 를 RunAtLoad 로 실행하고(실제 consumer 와 같은 python·같은 PATH `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`), 스크립트는 결과 JSON(`$PROBE/result.json`)이 생길 때까지 최대 150초 대기한다.
- 종료 후 정리: 스크립트 마지막에 `launchctl bootout gui/$UID/com.airag.probe-opa-<ts>` → 임시 plist 삭제 (자기 임시 라벨만). `$PROBE` 의 결과 파일은 값 없는 요약이라 보존.

## 3.2 `probe.py` 가 하는 일 (순서 고정, 각 단계 별도 자식 프로세스 · timeout 20초 · 값 비출력)
child env = tick 과 동일 규칙(`OP_ENV_ALLOWLIST` 이름 + P1·P2·P3 만 토큰). 출력은 `{step, rc, elapsed_s, timed_out, err_class}` 뿐. stdout/stderr 본문은 저장하지 않고 «`SERVICE_ACCOUNT` 문자열 포함 여부(bool)» 만 기록한다.

| 단계 | 호출 | HOME / 스폰 | 보는 것 |
|---|---|---|---|
| P4 | python `socket.create_connection(("my.1password.com",443),5)` + TLS 핸드셰이크 (자격 없음) | — | 네트워크 도달성 (H5) |
| P0 | `op --version` (토큰 없음) | 실제 HOME | op 가 자격 없이도 지연/팝업을 내는가 (H2) |
| P2 | `op user get --me` | `HOME=$PROBE/home` · `OP_CONFIG_DIR=$PROBE/home/.config/op` (실제 앱 컨테이너 경로 도달 불가) | 격리하면 통과하는가 (H2 → ⑤) |
| P3 | `op user get --me` | 실제 HOME + **disclaim 스폰**(`ctypes` 로 `responsibility_spawnattrs_setdisclaim`; 불가하면 `unavailable` 기록) | 책임 프로세스를 분리하면 통과하는가 (H1 → ⑦) |
| P1 | `op user get --me` | 실제 HOME (= tick 과 동일 조건) | 현재 재현 여부 (기준선) · 토큰 유효성 단서(rc/err_class) (H5) |

P1 을 **마지막**에 둔다 (팝업이 뜨면 앞 단계 판정을 방해하지 않게). P2·P3 는 P1 보다 먼저 가서 «팝업이 아직 안 뜬 상태» 에서 격리/분리 효과를 본다. 단, P0 에서 이미 팝업이 뜨면 P0 결과가 H2 의 직접 증거다.

## 3.3 TCC 속성 채집
프로브 종료 직후 `log show --last 3m --info --debug --predicate 'subsystem == "com.apple.TCC"'` 중 `AppData` 줄에서 `accessing` · `responsible` · `requesting` · `service` · 결과(`auth_value`/`reason`) **필드만** 추출해 `$PROBE/tcc.txt` 에 저장(경로 문자열이 있으면 그대로 — 경로는 시크릿이 아님). 요약: AUTHREQ 개수·`responsible` 값·`accessing` 값.

## 3.4 오빠가 하는 일
- 1차: `! bash /tmp/h<N>` 한 줄. **화면에 1Password/데이터 접근 팝업이 뜰 수 있다 — 아무것도 누르지 않으면 된다 (프로브가 20초×최대 5단계 뒤 자동 종료, 대기 중 팝업은 그 프로세스가 끝나면 사라진다).** 터미널에 값 없는 요약 표(단계·rc·소요·AUTHREQ 개수)가 찍힌다.
- 2차(선택, 1차 결과가 H1/H2 이고 팝업 영구 허용 안도 검토할 때만): 같은 스크립트를 `--allow-test` 로 한 번 더. P1 두 번을 연달아 돌려 «허용 1회 클릭이 launchd 작업에서 유지되는가» 를 본다 — 이때만 팝업에서 «허용» 을 누른다. **이 2차는 권고 1안이 막힐 때의 후퇴 경로 검증용이다. 1안이 통과하면 필요 없다.**

# 4. 해결 후보 비교

| 안 | 내용 | 변경 파일 | 테스트·경계 영향 | 오빠 손 작업 | 되돌리기 | 평가 |
|---|---|---|---|---|---|---|
| **⑤ op 자식 HOME·설정 격리 (신규 후보)** | op 자식에게 전용 `HOME=~/.local/share/airag/op-home`(0700) + `OP_CONFIG_DIR=<그 아래>/.config/op` 를 줘서, 실제 `~/Library/Group Containers/…` 경로가 op 에게 보이지 않게 한다. 서비스 계정 모드는 앱이 필요 없다 | `tick.py:97-98` (child env 2줄 + mkdir 0700). 설정 키 없이 고정 경로 | 레지스트리 **528 불변** (신규 코드 없음; mkdir 실패는 기존 `OP_SERVICE_ACCOUNT_UNAVAILABLE` 재사용). 허용목록에 `OP_CONFIG_DIR` 이름 추가 시 `test_op_child_environment_is_an_allowlist`(test_tick.py:351-363)는 이름 포함/배제 단언이라 통과, 값 단언 신규 테스트 1개 필요(자식 HOME ≠ 부모 HOME). 값 비노출 R8 경계 불변 | 휠 재설치(U2 §2 와 같은 절차, HIL) + `launchctl enable`·bootstrap(서버 복구 뒤 HELM) | 코드 되돌리기 + 휠 재설치 (런타임 백업 있음) | **권고 1안.** 단 프로브 P2 통과 + P2 소요가 정상 범위(op 데몬 신규 기동 비용)일 때 |
| ⑦ 책임 프로세스 분리(disclaim) | `ctypes` 로 `posix_spawn` + `responsibility_spawnattrs_setdisclaim` 로 op 를 자기 책임 프로세스로 분리 → op(같은 팀)의 컨테이너 접근이 앱 팀 자격으로 판정 | `tick.py:100-110` 를 자체 스폰으로 교체(~30줄: 파이프·타임아웃·종료 직접 처리), 비-Darwin/실패 시 기존 `subprocess.run` 폴백 | stub_op 기반 테스트는 폴백 경로로 통과, 신규 테스트 필요. **사설(private) API** — macOS 갱신으로 깨질 수 있음, PUBLIC 리포 코드에 들어감 | 휠 재설치 + enable | 코드 되돌리기 | 후퇴안 A (⑤ 불통 + H1 확정 시) |
| ① 고정 경로 서명 러너 + 허용 고정 | 안정 경로에 python 사본(또는 래퍼)을 두고 그 경로에 «허용» 을 한 번 준다. 서명 정체성은 여전히 adhoc 이라 해시 고정에 의존 | 코드 0 (plist `__PYTHON__` 값만 변경) | 영향 없음 | 허용 클릭 1회 + plist 변경(HIL) | plist 복구 | 후퇴안 B. uv python 갱신 때마다 재팝업 위험. **2차 프로브로 «허용이 launchd 에서 유지되는지» 확인 전에는 채택 금지** |
| ④ System Settings 로 허용 (Full Disk Access 등) | 해당 python 에 «다른 앱 데이터»/FDA 부여 | 코드 0 | 영향 없음 | Settings 조작 | Settings 해제 | **비권고** — adhoc python 에 광범위 권한 부여 (보안 경계 확대). 개별 «다른 앱 데이터» 허용 UI 가 해당 환경에 있는지도 미확인 |
| ② op 비경유 (1Password SDK 등) | 서비스 계정을 SDK 로 직접 읽어 op CLI·컨테이너 경로를 거치지 않음 | `tick.py` read() 교체 + 의존성 추가(pyproject·휠·constraints) | **PUBLIC 패키지에 제3자 의존성 추가**, stub_op 기반 테스트 전면 교체, 토큰이 프로세스 내부에 상주. SDK 가 컨테이너를 안 건드린다는 보장도 **미확인** | 휠 재설치(+의존성) | 휠 되돌리기 | 비용 대비 이득 불확실 — H2 가 확인되고 ⑤⑦ 이 모두 막힐 때만 |
| ③ 호출 횟수·동시성 축소 | ThreadPool 3→직렬, 또는 `op inject` 단일 호출로 3키 한 번에 | `tick.py:112-113` (+ `op inject` 시 템플릿·파싱 ~15줄) | stub_op 가 `inject` 를 지원하도록 변경 필요. 레지스트리 불변 | 휠 재설치 | 코드 되돌리기 | **원인 해결 아님** — 팝업 개수 3→1, 토큰 사용량 3→1 일 뿐. ⑤/⑦ 과 병행 시에만 가치 |
| (참고) 토큰을 plist EnvironmentVariables 로 이동 | — | plist | `test_plist_template…`(test_tick.py:260-272)가 깨짐, 평문 노출면 확대(plist 0644) | — | — | **기각** — 팝업과 무관(F9: 토큰 주입 방식은 이미 서비스 계정). 노출만 늘린다 |

주석 — 외부 호출 시간 상한(하드 룰 12): `tick.py:103` 의 `timeout=30` 은 70초 천장 안이라 강제 변경 대상은 아니다. 다만 팝업 대기 중 틱 점유를 줄이려면 7초+기동비 규칙으로 줄이는 것이 맞는 방향이다 — 이번 범위(원인 해결) 밖이므로 **별도 건으로 기록만** 한다.

# 5. 권고

## 5.1 권고 1안: ⑤ op 자식 HOME·설정 격리 — 단 **프로브가 먼저**
- 이유: 코드 3줄 규모, 사설 API 없음, 권한 확대 없음, 레지스트리 528·값 비노출 R8 경계 불변, 오빠 클릭 0(영구). «팝업이 영구히 안 뜸» 이라는 오빠 목표에 가장 직접 대응한다 — 허용을 얻는 것이 아니라 **접근 자체를 없앤다**.
- 전제 검증: 프로브 P2 가 통과하고(`rc=0`, `SERVICE_ACCOUNT=True`, AUTHREQ 0) P1 은 재현(지연/AUTHREQ)될 때. 이 두 조건이 겹쳐야 «격리가 효과 있다» 가 증명된다.
- 한계(솔직): 이것은 가설이다. op 가 `$HOME` 이 아니라 `getpwuid` 의 홈을 쓰면 격리가 무력하다 — 그 경우 P2 가 P1 과 같이 막혀 **프로브가 바로 알려 준다.** 구현 전에 반드시 프로브.

## 5.2 후퇴안
- A: ⑦ disclaim 스폰 — P3 만 통과하고 P2 는 막힐 때(= H1).
- B: ① 고정 경로 + 허용 1회 — P2·P3 모두 막히고 2차 프로브에서 «허용이 launchd 에서 유지됨» 이 확인될 때만. ③ 병행.
- C(최종): consumer 를 계속 비활성으로 두고 **서버 복구·수집 필요 시점에 다시 판단.** 지금은 서버가 꺼져 있어 손실 0 (F10).
- D(원인이 H5로 판명): 팝업 해결안 전부 무효 — 토큰 재발급(오빠 손 1회) 또는 네트워크 조치로 전환. 그 경우 이 문서의 ⑤⑦①④ 는 보류.

## 5.3 판단 분기표 (프로브 결과 → 다음 일)
| P4 | P0 | P2 | P3 | P1 | 판정 | 다음 |
|---|---|---|---|---|---|---|
| 실패 | — | — | — | — | H5 네트워크 | 팝업 해결 보류, 네트워크 조치 |
| 통과 | 통과 | 통과 | — | **재현(지연/AUTHREQ)** | H2 | ⑤ 구현 발주 |
| 통과 | 통과 | 막힘 | 통과 | 재현 | H1 | ⑦ (후퇴안 A) |
| 통과 | 통과 | 막힘 | 막힘 | 재현 | 컨테이너 접근을 격리·분리 모두로 못 피함 | 2차 프로브 → ① (후퇴안 B) |
| 통과 | 통과 | 통과 | 통과 | **재현 안 됨 + rc≠0(토큰류)** | H5 토큰 | 토큰 재발급 (오빠 1회) |
| 통과 | 통과 | 통과 | 통과 | 재현 안 됨 + rc=0 | 현재는 문제 없음(앱·재부팅 이후 상태 변화) | 정상 가동 재개 + 관찰 |

# 6. 오빠께 드릴 질문 (1개)

> **«팝업 원인을 가르는 1회 점검 스크립트(`! bash /tmp/h<N>`)를 실행해도 될까요?** 시크릿은 읽지 않고(계정 종류만 조회), 임시 작업을 만들었다가 스스로 지웁니다. 실행 중 1Password 관련 팝업이 한 번 뜰 수 있는데, **아무것도 누르지 않으면** 20초 안에 자동 종료됩니다.»

같은 메시지에 «서비스 계정 방식은 이미 쓰는 중이었습니다 — 권장 전제가 달랐습니다» 를 한 줄로 정정한다.

# 7. DA 에 요청할 점검 (Master 가 소환)
1. 프로브 스크립트의 «값 비출력·운영 접촉 0» — 토큰이 child env 외 어디에도 안 남는지, 임시 plist/라벨 정리가 실패해도 안전한지.
2. disclaim 사설 API(⑦)를 PUBLIC 리포 코드에 넣어도 되는가(채택 시).
3. ⑤ 의 격리 HOME 이 op 의 서비스 계정 인증 캐시/데몬 비용을 틱마다 새로 만들어 5분 간격에 부담이 되지 않는가 (P2 소요로 검증).
4. 판단 분기표 5.3 의 누락 케이스.

# 8. 미확인·한계
- TCC AUTHREQ 의 `accessing`/`responsible` 필드, 대상 경로: 이번에 로그 0줄이라 **미확인** (프로브 3.3 이 채집).
- 현 서비스 계정 토큰의 유효성 (폐기/만료): op 실행 금지로 미확인 (프로브 P1 의 rc/에러 클래스가 단서).
- 10-02 15:53~10-11 사이 틱 공백의 이유, F8 의 op 데몬 소켓 갱신 주체: 미확인.
- 서비스 계정 모드의 컨테이너 접근 여부: 공식 문서에 기술 없음 (checker Q3 item1).
- «1Password.app 갱신(10-08)이 원인» 은 시기 일치(F1·F3)일 뿐 증명되지 않았다.
