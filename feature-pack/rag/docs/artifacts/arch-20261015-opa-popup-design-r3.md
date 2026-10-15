골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 · consumer 권한 팝업/타임아웃 해결. 이 문서는 설계 r3(DA r2 REJECT blocker 1·major 4·minor 3 반영).
작성: ft-airag-arch-claude#2 (architect, 2026-10-15) · 설계만 — 코드·운영 변경 0, op 실행 0, 값 열람 0 · 복사·커밋은 Master · 이전판 r1·r2 는 같은 폴더(r2 = arch-20261015-opa-popup-design-r2.md). 이 문서 하나로 읽히도록 전체를 다시 썼다.

# 0. 요약 (먼저 읽기)

1. **문제는 둘이다 — (가) 팝업이 뜬다 · (나) 키 읽기가 간헐적으로 타임아웃.** 같은 원인이라는 증거는 없다. 이 구분은 DA 가 독립 재현해 유지됐다 (타임아웃 `OP_READ_UNAVAILABLE` 231 · 재부팅 경계 이전 231 / 이후 0 · degraded 64).
2. **외부 호출 7초 룰 = «기준 요청 1회 CLI 호출은 프로세스 기동 포함 시도당 7초 · 재시도 최대 1회 · 전체 마감 14초».** r2 의 «기동비 3.5초 가산(10.5/21초)»은 **철회**했다 — 그 가산은 크기 아는 분할 불가 배치 공식이라 이번 호출에 해당 없다. **설계자는 잠정 상수를 만들지 않는다.** 실제 op 콜드 스타트가 7초를 넘는지는 **S2 측정으로 확인**하고, 넘으면 «규칙 예외를 둘지는 **오빠 결정**»으로 올린다 (§3).
3. 프로브(1회 승인)는 **계정 조회 경로의 후보 축소만** 한다. 단계마다 **별도 검증기**(§4.2)와 **단일 상태 전이표**(§4.3)를 둔다. 키 읽기 경로 검증은 **별도 승인 S2**.
4. 어떤 분기에서도 **consumer 는 서버 18712·18703 복구 통보 + HELM 재개 절차 전까지 disabled 유지.**
5. 현재 코드는 **여전히 `timeout=30`** (tick.py:103). I-1(7초 룰 구현)은 **미착수**이며 구현·시험이 끝난 것으로 보고하지 않는다.

# 1. 사실 (읽기 전용) — 서술 강도 조정 (DA M4)

## 1.1 틱 로그 (DA 독립 재현 완료: 세 파일 · `ts/status/code` 만)
| 사실 | 값 |
|---|---|
| `key_error` + `OP_READ_UNAVAILABLE` | **231건** (tick-20261011 6 · 12 → 212 · 13 → 13). 전부 `TimeoutExpired` 라는 연결은 checker 사실에 의존 |
| `degraded`(exit 0) | **64건** (3 · 40 · 21) |
| 첫 오류 / 마지막 오류 | 10-12 08:10:15 KST / 10-13 10:49:05 KST |
| 10-13 10:58(재부팅, 설계 입력값) 경계 | 오류 이전 231 / 이후 0 |
| 시간 패턴 | 10-12 낮 성공·실패 혼재 → 10-12 16시~10-13 09시 거의 전부 실패 → 10-13 10:54~12:05 `degraded` 연속 |

## 1.2 해석 — 확정하지 않는 것을 명시
- **`degraded` = `load_keys` 가 정상 반환하고 패스까지 진행했다**는 증거다. `load_keys` 는 환경에 이미 있는 키를 우선하고 키가 모두 있으면 op 를 부르지 않는다 (tick.py:69-74 · test_tick.py:127-133). 따라서 **상태 로그만으로 «그 틱에서 op read 가 성공했다»고 단정하지 않는다.** 조건부 근거만 있다: 설치 plist 는 10-02 이후 불변이고 `EnvironmentVariables` 에 PATH 만 있다(checker Q5) → launchd 틱 환경에 키가 있었다고 볼 근거는 없다. 직접 입증은 아니다.
- **TCC 요청(11:44:00)과 틱(시작 11:43:59.924, degraded)은 시각이 가깝다.** 근접일 뿐 **PID/요청 경로 귀속은 없다.** «팝업이 그 op 에서 났고 그 op 가 통과했다»는 확정이 아니라 **가설(op 실행의 비동기 곁가지)** 이다. 타임아웃 기간 중 TCC 요청 유무는 로그 보존 한계로 **미확인.**
- **회복 계기는 미확정.** 재부팅(10:58)은 «최초 회복에 반드시 필요했다»는 설명을 반박할 뿐 이후 지속 회복에 영향이 없었다고까지 말하지 못한다. 화면 상태는 `pmset` Display 이벤트 19개로 본 거친 관측이며 «켜짐 상태 실패»가 잠금/전환 영향을 모두 배제하지 않는다. → **«재부팅·화면 상태만으로 설명하는 단순 가설은 약화됨».** (r2 의 «데이터로 기각»은 철회.)
- (가) 와 (나) 를 별도 문제로 관리하는 방향은 유지한다.

## 1.3 기타 사실 (강도 유지)
F1 설치본은 이미 서비스 계정 토큰 방식(tick.py:79,92,98) · F2 10-02 launchd 틱 ok 6건 · F3 `1Password.app` 디렉터리 mtime 10-08 18:05 = 갱신 «정황» · F4 python 3.13 adhoc 서명, mtime 09-03 (정책 변화 완전 배제 불가) · F5 `op-daemon.sock` mtime 10-15 14:14 = 그 시점 생성/변경 정황, 공유 op 상태 존재 · F6 TCC 요청 주체 uv python3.13 까지만 관측 · F7 서비스 계정 모드의 컨테이너 접근 여부는 공식 문서 기술 없음, **토큰 방식만으로 팝업이 방지된다는 근거는 이 환경에서 입증되지 않았다** · F8 컨테이너 둘(`2BUA8C4S2C.com.1password` · `group.2BUA8C4S2C.com.1password`), op 팀 ID 2BUA8C4S2C · F9 consumer 는 `bootout+disable` 상태, 서버 18712·18703 기동 통보 대기.

# 2. 원인 후보

| 후보 | 문제 | 내용 | 가르는 관측 |
|---|---|---|---|
| A1 | (가) | op 또는 자식이 앱 컨테이너를 열어 TCC 요청 → 책임 프로세스가 팀 없는 adhoc python | TCC 속성(`accessing`/`responsible`) · P0 의 요청 발생 |
| A2 | (가) | op 가 시작 시 앱 통합(소켓/컨테이너)을 probe | P0(`op --version`)·P2(전용 경로)에서 요청이 사라지는가 |
| B1 | (나) | 공유 op 데몬/소켓 상태 경합 — 3개 `op read` 동시 기동, 다른 op 사용자와 상태 공유 | S2: 3 병렬 vs 직렬 vs 단일 반복의 실패율 차이 |
| B2 | (나) | 토큰/네트워크/서버 측 간헐 지연 | P4 + 계정 조회 오류 클래스 · S2 반복 |
| B3 | (나) | 시간대 의존 외부 요인(오빠 PC 사용 패턴, 다른 도구의 op 사용, 앱 실행 상태) | 시간 패턴 + S0 스냅샷 |
| 약화 | — | 재부팅·화면 상태 단독 설명(§1.2) · python 해시 변화(F4) · 틱 중첩(간격 균일) | — |

(나) 의 원인은 현재 데이터로 미확정이다.

# 3. 외부 호출 7초 룰 (DA B1 — DA 해석 채택)

## 3.1 규칙 적용
기준 요청 1회인 CLI 호출(`op --version` · `op user get --me` · `op read <참조>` 1개) = **프로세스 기동 포함 시도당 7초 · 재시도 최대 1회 · 전체 마감 14초.** 계정 조회·키 1개 읽기는 «크기 아는 분할 불가 배치»가 아니므로 기동비 가산·70초 조건부 확장을 쓰지 않는다. **예외를 원하면 사용자 규칙 변경이라는 명시적 결정이 필요**하고 설계자가 정하지 않는다.

## 3.2 `tick.py` op 호출 (구현 I-1 — 현재 미착수, 코드는 아직 `timeout=30`)
| 항목 | 값 |
|---|---|
| 시도당 상한 | **7.0초** (`OP_ATTEMPT_TIMEOUT_S = 7.0`) |
| 전체 마감 | 호출(키 1개)당 **14.0초** (`OP_CALL_DEADLINE_S = 14.0`). 호출 시작 시 `deadline = monotonic() + 14` 고정, 2차 시도 timeout = `min(7.0, deadline − monotonic())`, 남은 시간 ≤ 0 이면 재시도 안 함 |
| 재시도 대상 | `TimeoutExpired` 이면서 **첫 출력 전**(부분 `stdout`·`stderr` 모두 비어 있음 — 내용은 읽지 않고 비어 있는지만 판정, 읽은 객체는 즉시 폐기) 만 |
| 재시도 금지 | 첫 출력 이후 timeout · `OSError`(스폰 실패) · `returncode≠0` · 형식 오류 |
| 이유 코드 | 기존 `OP_READ_UNAVAILABLE` / `OP_KEY_READ_OR_FORMAT_FAILED` 재사용 → **레지스트리 528 불변.** 재시도 횟수는 로그에 새 코드를 만들지 않는다 |
| 틱 전체 | 키 3개 병렬이므로 op 단계 최대 ≈14초 + 로컬 처리 |
| 시험 (합성 stub op) | ① 출력 없이 sleep → 시도 2회·`OP_READ_UNAVAILABLE`·type=TimeoutExpired ② **부분 출력(`printf x` 후 sleep) timeout → 시도 1회(첫 출력 이후 재시도 금지)** ③ `returncode≠0` → 시도 1회 ④ `OSError` → 시도 1회 ⑤ 2차 시도 timeout ≤ 남은 마감(상수는 monkeypatch 로 0.2/0.4초) ⑥ `test_op_child_environment_is_an_allowlist` 불변 통과 |
| 위험(기록) | op 콜드 스타트가 7초를 넘으면 정상인데도 첫 시도가 실패로 보일 수 있다 → **I-1 적용 뒤 첫 시도 실패율이 오르면 즉시 S2 측정을 앞당기고, 규칙 예외 여부를 오빠께 올린다.** 설계자가 상수를 키우지 않는다 |
| 부작용 | 재시도는 팝업 대기 중 환경에서 키당 op 요청을 최대 2회로 늘린다(복수 팝업 가능) — 룰 기본값 수용 |

## 3.3 일 호출량 3단계 구분 (DA m3)
| 층 | 값 |
|---|---|
| 기본 **논리 읽기** | 288 틱/일 × 키 3 = **864회/일** (키 3개 모두 환경에 없을 때) |
| 재시도 포함 **CLI 시도** 최대 | 864 × 2 = **1,728회/일** |
| **실제 서비스 API 요청** 수 | CLI 시도 1회가 몇 번의 요청을 만드는지 **미확인** — rate-limit 수치도 문서 미확인. S2 예산·채택 전에 문서 확인 선행 |

# 4. 증거 수집 프로브 (1회 승인) — 결론은 «후보 축소»

## 4.1 한계
- 말할 수 있음: 계정 조회 경로에서의 기본 경로 vs 전용 경로 차이, `op` 기동의 지연/요청, 도달성, TCC 요청 상관.
- **말할 수 없음:** 키 읽기(`op read`) 경로 성공/실패, vault 접근, 3 병렬 동시성, 간헐 타임아웃의 원인. 프로브 통과 = 정상 가동 아님. 단일 시행 «성공»은 «문제 없음»이 아니다(간헐 현상).

## 4.2 단계와 단계별 검증기 (DA M1)
외부 호출 합계 최대 **35초** = P4 7 + P0 7 + P2 7 + P1 7 + P1b 7 (모두 단일 시도, 재시도 0).

| 단계 | 호출 | 마감 | **성공 검증기** (그 외는 아래 매핑) |
|---|---|---|---|
| S0 | 로컬 스냅샷: `launchctl print-disabled gui/$UID` 에서 `com.airag.consumer` 항목의 `disabled` 값 · `launchctl print gui/$UID/com.airag.consumer` 는 **로드 여부만 별도 기록** · `pgrep -x op` 개수 · 소켓 mtime | 로컬 | 조회 실패는 `unknown` — **disabled 로 취급하지 않는다** (DA m1) |
| P4 | Python `socket.create_connection` + TLS 핸드셰이크, `my.1password.com:443`, **하나의 7초 마감 공유** | 7초 | **TCP 연결 + TLS 핸드셰이크 완료** = success. `socket.timeout` → timeout · `gaierror`/`ConnectionError`/`ssl.SSLError` → network_error (예외 클래스 이름만 기록). 고정 호스트 도달성은 실제 계정 지역·API 정상을 입증하지 않는다 |
| P0 | `op --version` (토큰 없음, 실제 HOME) | 7초 | rc=0 **그리고** stdout.strip() 이 정규식 `^\d+\.\d+\.\d+` 로 시작 = success (버전 문자열은 비밀 아님, 일치 여부 bool 만 기록) · rc=0 불일치 = unsupported · rc≠0 = observation_unknown |
| P2 | `op user get --me --format json` (전용 경로 §5.1) | 7초 | 계정 검증기 V-acct |
| P1 | 같은 호출 (실제 HOME = tick 조건) | 7초 | V-acct |
| P1b | P1 한 번 더 | 7초 | V-acct (실행 조건 §4.3) |

**V-acct (P1/P2/P1b):** rc=0 이고 stdout 이 JSON 객체로 파싱되고 `type == "SERVICE_ACCOUNT"` = success · rc=0 이나 파싱 불가/타입 불일치 = unsupported · rc≠0 → stderr 를 **고정 부분문자열 허용목록**으로 분류(인증 계열 → auth_error · 네트워크 계열 → network_error · 그 외 → observation_unknown) 후 stderr 즉시 폐기. (`type` 필드명은 실제 스키마 미확인 — 구현 DA 에서 검증, 불일치 시 unsupported.)
**CLI 공통:** `TimeoutExpired` → timeout(부분 출력 폐기) · `OSError` → spawn_error.

단계 상태(유한 8종): `success / auth_error / network_error / timeout / spawn_error / unsupported / observation_unknown / skipped_prior_unresolved`.

`tcc_observation`(유한 4종): `seen_attributed` · `seen_unattributed` · `none_logged_ok` · `unknown_log_unavailable`. 단계 시간창 = [시작 −0.5초, 종료 +2초]. `none_logged_ok` 는 **«로그 검사에서 미관측»일 뿐 팝업 부재의 보증이 아니다** — 같은 범위에 다른 TCC 줄이 ≥1 있을 때만 쓰고(양성 대조), 그것조차 AppData 수집 완전성을 보증하지 않는다. 0줄이면 `unknown_log_unavailable`.

## 4.3 단일 상태 전이표 (실행 중지·결과 분류 통일)
각 단계가 끝나면 **(상태, tcc) 한 쌍**으로 다음 행동을 정한다. 이 표 밖의 규칙은 없다.

| 단계 | 상태 | tcc | 다음 행동 |
|---|---|---|---|
| P4 | 어떤 상태든 | (해당 없음, 기록만) | **계속** (독립 단계; 실패는 결론만 약화) |
| P0 · P2 · P1 | `timeout` | 무엇이든 | **중지** → 남은 CLI 단계 `skipped_prior_unresolved` (팝업 미해결 가능) |
| P0 · P2 · P1 | 어떤 상태든 | `seen_attributed` / `seen_unattributed` | **중지** (같은 이유) |
| P0 · P2 · P1 | `success` | `none_logged_ok` | 계속 |
| P0 · P2 · P1 | `success` | `unknown_log_unavailable` | 계속 (결과에 `tcc_unknown` 표시; **P1b 는 실행하지 않음**) |
| P0 · P2 · P1 | `auth_error` | 무엇이든 | **중지(완료)** — 같은 토큰으로 반복해도 정보 없음 |
| P0 · P2 · P1 | `network_error` · `spawn_error` · `unsupported` · `observation_unknown` | 무엇이든 | **중지(완료)** → 결론은 «원인 미확정» |
| P1b | (실행 전) | P1 이 `success` + `none_logged_ok` 이고 P0·P2 도 `success` 일 때만 | 그 외는 `skipped_prior_unresolved` 아닌 **`skipped_not_applicable`** (사유: 앞 단계 비성공 또는 tcc 보류) — 가능한 사전 TCC 상태는 **`none_logged_ok` 하나뿐**이다 |
| P1b | 실행 후 어떤 상태든 | 무엇이든 | 완료 (더 이상 단계 없음) |

결론 분류 (모두 후보 축소이며 **변경 보류가 기본**):
| 관측 | 해석 | 다음 후보 (실행 아님) |
|---|---|---|
| P0 가 중지 조건 | 자격 없는 `op` 기동에서 이미 막힘/요청 → 후보 A2 | 원인 미확정 · 별도 결정(DA 포함) |
| P0 success, P2 success, P1 중지 조건 (timeout 또는 seen_*) | 기본 경로에서만 막힘, 전용 경로 통과 (단일 시행·순서 효과 한계) | ⑤ 후보 유지 → **S2 승인 요청** |
| P0 success, P2 중지 조건 | 전용 경로도 재현 → ⑤ 근거 약화 | 원인 미확정 · ⑦/① 별도 DA 후 결정 |
| P0·P2·P1 success + 전부 `none_logged_ok`, P1b success + `none_logged_ok` | 이번 시점 재현 없음(2회) — **팝업 부재 보증 아님** | 원인 미확정 · 변경 보류 · S2 |
| P0·P2·P1 success + 전부 `none_logged_ok`, P1b 중지 조건 | 간헐 재현 확인 (P2 는 통과한 단일 시행) | ⑤ 후보 약하게 유지 → S2 |
| P0·P2·P1 success 이나 어느 한 단계 `unknown_log_unavailable` | 재현 없음 + 팝업 관측 불가 → P1b 보류 | 원인 미확정 · 변경 보류 |
| 어느 단계든 `auth_error` | 토큰 폐기/만료/권한 후보 (B2) | 팝업 해결안 보류 · 토큰 재발급 후보(오빠 손) |
| P4 `network_error` 이고 CLI 단계 `timeout` | 도달성 후보 (B2) | 네트워크 점검 후보 |
| 위에 없는 조합 · `spawn_error`/`unsupported`/`observation_unknown` | **원인 미확정 — 변경 보류** | 필요한 관측을 정해 별도 결정 |

공통: **어떤 분기에서도 consumer 는 disabled 유지.** 진단 성공은 운영 재개 승인이 아니다.

## 4.4 결과 스키마
`schema_version`, 단계 배열(`step, status, rc, elapsed_ms(단조 시계), started_utc_ms, ended_utc_ms, child_pid, account_type_confirmed(bool|null), tcc_observation`), `complete: true`. **원자 기록**(임시 파일 → rename). 읽는 쪽은 부재/`complete != true` 를 `observation_unknown` 으로 읽는다. 오류 클래스·예외 이름은 유한 목록만. **원문 메시지·traceback·stdout/stderr 본문은 어디에도 쓰지 않는다.**

## 4.5 약속의 정확한 문구와 값 경계
- **하는 약속:** 운영 consumer 의 **파일/DB 쓰기 0** — `com.airag.consumer` plist · `runtime.json` · `credential-source.json` · 토큰 파일(읽기만) · 운영 DB · `~/.local/share/airag/logs` · `~/Library/LaunchAgents` 에 쓰지 않는다.
- **하지 않는 약속(고지):** **공유 op 상태 접촉 가능** — 실제 HOME 의 P0/P1/P1b 는 `~/.config/op`(설정·소켓·데몬)·컨테이너 접근 시도·로컬 캐시에 접촉하거나 변경을 일으킬 수 있다. 다른 터미널/도구의 op 사용과 간섭할 수 있다.
- 토큰 흐름 = 기존 파일 → 부모 파이썬 메모리(불가피) → 필요한 op 자식 env 만(P2·P1·P1b; P0 은 토큰 없음). argv·plist·결과·traceback·스트림에 쓰지 않는다. launchd `StandardOutPath`/`StandardErrorPath` = `/dev/null`. 최상위 핸들러는 예외 **클래스 이름(허용목록)** 만 남긴다. 공유 op 데몬은 **임의 종료하지 않는다.**

## 4.6 스크립트 구조 · 정리 계약 (DA M2)
**전용 경로·충돌:** `PROBE_BASE=$HOME/.local/share/airag-probe`(운영 `airag` 와 분리) · 부모가 심링크면 거부 · `ID=$(date +%Y%m%d-%H%M%S)-$$-$RANDOM` · `mkdir -m 700 "$PROBE_BASE/$ID"`(이미 있으면 실패 = 원자적 충돌 검출) · 임시 plist 는 `$PROBE_DIR/job.plist`(LaunchAgents 에 두지 않음) · 라벨 `com.airag.probe-opa-$ID` · `RunAtLoad` 1회, `KeepAlive`/`StartInterval` 없음 · bootstrap 전 `launchctl print gui/$UID/$LABEL` 이 «없음»임을 확인.

**신호별 종료:** `trap 'cleanup; exit 130' INT` · `trap 'cleanup; exit 143' TERM` · `trap 'cleanup; exit 129' HUP` · `trap 'cleanup' EXIT`. `cleanup` 은 멱등(`CLEANED` 가드)이며 **반환 뒤 반드시 명시적으로 종료**한다 — 신호 처리 후 다음 셸 명령으로 흘러가지 않는다. 트랩은 어떤 라벨·디렉터리 생성보다 앞에 설치.

**자기 라벨 대조(플래그 비의존):** `cleanup` 은 `LABEL_LOADED` 플래그와 무관하게 **자기 고유 라벨을 `launchctl print` 로 직접 조회**한다 — bootstrap 성공 직후 플래그 기록 전에 중단돼도 놓치지 않는다.
- `print` rc=0 → 로드됨 → `bootout gui/$UID/$LABEL` 후 재조회.
- `print` 가 «서비스 없음»(고정 부분문자열 `Could not find service`)으로 실패 → **absent**.
- 그 외 실패(권한·타임아웃·다른 오류) 또는 `launchctl` 명령 자체 없음(`command -v` 실패) → **`unknown_check_required`** (없음으로 취급 금지).
- bootout 뒤에도 로드돼 있거나 unknown 이면 **«잔존 확인 필요: <라벨>»** 을 출력하고 **자동 재시도하지 않고** 종료 코드 비0.

**프로세스(PID 기준; `pgrep -f 디렉터리` 폐기):** `probe.py` 는 **자기 PID** 와 **직접 생성한 자식(P0/P2/P1/P1b 의 op) PID + 시작 시각**을 자식 생성 **직전·직후** `$PROBE_DIR/pids.json` 에 원자 기록한다. 자식은 `Popen` + `communicate(timeout)`, 타임아웃 시 `kill()` 후 `communicate()` 로 **즉시 재수거**하고 `reaped=true` 기록. `cleanup`(셸)은 bootout 후 **기록된 PID 각각**에 대해 `ps -o lstart=,comm= -p <pid>` 로 **기록된 시작 시각·실행명과 일치할 때만** 살아 있음으로 판정 — 일치하면 해당 PID 만 `TERM` → 2초 → 살아 있으면 `KILL`(자기가 만든 프로세스 한정) → 재확인. 일치하지 않으면(PID 재사용) 건드리지 않는다. 잔존이면 **«잔존 확인 필요: pid …»**. op 가 띄운 공유 데몬은 기록 PID 에 없고 임의 종료 대상이 아니다 — 보고만(`공유 데몬은 종료하지 않음`).

**상한(단일 전체 마감):** 시작 대기 ≤10초 + 외부 호출 합계 ≤35초 + 로그 채집/로컬 처리 ≤15초 = 결과 대기 상한 60초, 정리 ≤15초 → **전체 하드 상한 75초.** 상한 도달 시 결과를 `observation_unknown`(+`timed_out_wait=true`)로 닫고 정리.

**합성 토큰 시험 (`--selftest`, 운영 실행 경로와 분리):** `PROBE_OP_BIN`·`PROBE_TOKEN_FILE`·`PROBE_LAUNCHCTL` 오버라이드는 `--selftest` 에서만 허용. 시나리오:
(a) 정상 stub · (b) `sleep` 타임아웃 · (c) 실행 중 SIGINT · (d) 가짜 `launchctl` bootout 실패 · (e) stub 이 stderr 에 «토큰처럼 보이는 합성 문자열» 출력 → 결과·launchd 스트림·프로브 디렉터리 전체에서 합성 토큰·stdout/stderr 문자열 grep 0건 · (f) `complete` 없는 부분 결과 처리 · **(g) bootstrap 직후 중단**(가짜 `launchctl` 이 bootstrap 성공 후 플래그 기록 전에 신호) → 라벨 직접 조회로 bootout 되고 exit 130 · **(h) bootout 실패 뒤 직접 생성 op(stub sleep) 잔존** → 기록 PID 로 TERM/KILL·재확인, 실패 시 «잔존 확인 필요» · (i) `launchctl` 조회 오류(다른 오류 문자열) → `unknown_check_required` · (j) `launchctl` 부재 → 같은 처리. 구현 DA 에 통과 결과를 제출한다. 운영 op 실행은 Master HIL 이후에만.

# 5. 해결 후보 비교

| 안 | 상태 | 요지 |
|---|---|---|
| **I-1: 7초 룰 적용** | **승인 후보 — 원인과 무관, 즉시 진행 가능** | §3.2. `tick.py:100-110` + 신규 시험 6개. 528 불변. 틱의 op 점유 시간을 호출당 최대 14초로 제한. **현재 미착수.** 휠 재설치(HIL)는 서버 복구 뒤 HELM |
| ⑤ 전용 설정 경로 «후보» | S2 이후 | §5.1 |
| ⑦ 책임 프로세스 분리(disclaim) | **이번 승인 제외 · 실험 후보** | §5.2 |
| ① 고정 경로 python + 허용 1회 | 후퇴안 | 허용 클릭이 launchd 에서 유지되는지 미검증, uv 갱신 시 재팝업 위험 |
| ④ Settings/FDA 허용 | 비권고 | adhoc python 에 광범위 권한 |
| ② op 비경유(SDK) | 후순위 | PUBLIC 패키지 제3자 의존성 · 테스트 전면 교체 · 컨테이너 비접촉 보장 미확인 |
| ③ 호출 축소(직렬/`op inject` 1회) | 보조 | 원인 해결 아님. (나) B1 후보를 S2 가 지지하면 가치 상승 |
| 토큰을 plist 로 이동 | 기각 | 팝업 무관, 노출면 확대 |

## 5.1 ⑤ «전용 설정 경로 사용 후보»
파일시스템 **격리·차단이 아니다** — HOME/`OP_CONFIG_DIR` 은 경로 선택 힌트이고 같은 UID 의 접근 능력을 제한하지 않는다. 후보의 주장은 «op 가 앱 컨테이너/설정을 찾는 **기본 경로를 바꿨을 때** 요청/지연이 사라지는가» 뿐이다. 서비스 계정 모드에서 필수인 상태(지역/계정·CLI 통합·캐시)는 **미확인.**
- 경로: 부모 `OP_CONFIG_DIR` 은 **자식으로 전달하지 않는다**(허용목록에 넣지 않음, 시험 추가). 코드가 계산한 **전용 절대경로** `<HOME>/.local/share/airag/op-home` 를 자식 env 에 `HOME=<그 경로>`, `OP_CONFIG_DIR=<그 경로>/.config/op` 로 직접 설정.
- 경로 정책: `os.makedirs(mode=0o700)` 후 `lstat` — 디렉터리·심링크 아님·소유 uid == euid·`mode & 0o077 == 0`·`realpath` == 기대 경로. 위반/실패 → 기존 `OP_SERVICE_ACCOUNT_UNAVAILABLE`(신규 코드 0). 매 틱 삭제·공유 데몬 종료는 비용 해법으로 쓰지 않는다.

## 5.2 ⑦
이번 구현 승인에서 제외, 프로브에서도 P3 제거. 채택하려면 별도 DA 로 지원 OS/아키텍처·심볼/ABI·실제 `accessing`/`responsible` 변화·마감/파이프/재수거·값 억제·OS 갱신 후 실패 동작을 검증. **폴백 계약:** 사용 불가 시 값 없는 오류(`OP_READ_UNAVAILABLE`)로 틱 보류가 기본 — 원래 `subprocess.run` 으로의 자동 폴백은 «팝업 재발 수용» 명시 선택 없이 금지.

# 6. 단계 계획

| 단계 | 내용 | 승인 | 선행 |
|---|---|---|---|
| I-1 | 7초 룰 구현(7.0/14.0) + 시험 6개 + 구현 DA | 코드 승인(Master 발주) | 이 문서 DA r3 |
| P | 프로브 1회 (§4) — 스크립트 + 합성 시험 (a)~(j) + 구현 DA 통과 뒤 | **오빠 HIL**(§7) | I-1 과 독립 |
| S2 | 키 읽기 경로 검증(실제 `op read` 3 병렬, 값 비출력) — **op 호출 전후 단조 시계 차이**를 값 없는 결과로 측정 | **별도 오빠 HIL** | P 결과 + 스크립트 DA |
| I-2 | ⑤ 구현(S2 가 지지할 때) | 코드 승인 + 구현 DA | S2 |
| 재개 | 서버 18712·18703 복구 통보 → HELM enable/bootstrap → 24틱 관찰 | 기존 정지 해제 절차 | 위 전부 |

## 6.1 S2 측정 계약 (DA M3)
- **`pass_elapsed_s` 는 사용하지 않는다** — 코드상 `load_keys` 종료 **뒤**에 시작되는 패스 시간이라 op 시간이 포함되지 않는다 (tick.py:231-242). 로그 `ts` 도 틱 **시작** 시각이다.
- 측정: 각 op 시도 직전·직후 `time.monotonic()` 차이(ms)를 키 인덱스(0..2)·시도 번호·상태 클래스·재시도 여부와 함께 기록. 값·참조 문자열·출력은 기록하지 않는다.
- 라운드 = 키 3개 병렬 1세트. **콜드 1라운드**(전용 경로 새로 생성 직후) + **웜 5라운드**(≥60초 간격) = 6라운드, 호출 18회.
- **채택 기준(사전 고정):** 18/18 첫 시도 성공 · 각 시도 ≤ 7.0초 · 재시도 사용 0(재시도는 안전망이지 예산이 아니다) · 전체 호출 ≤ 14초 · 라운드 뒤 잔존 op 프로세스/데몬 수 비증가 · 전용 경로 디스크 바이트 비증가(허용 오차는 구현 DA 에서 확정).
- **콜드 스타트가 7초를 넘으면:** 설계자가 상수를 키우지 않는다. 측정 분포(최소/중앙/최대 ms)를 값 없이 보고하고 **«규칙 예외를 둘지는 오빠 결정»** 으로 올린다. 그동안 ⑤ 채택·운영 재개 판정은 보류.
- 일 호출량(§3.3) 3단계 구분을 S2 보고에 그대로 적는다.

# 7. 오빠께 드릴 질문 — 프로브 1회 승인 (DA M6·m2 반영, 수치 통일)

> **«1Password 연결 상태를 점검하는 1회 스크립트(`! bash /tmp/h<N>`)를 실행해도 될까요?** 실제로 하는 일은 이렇습니다.
> ① 임시 점검 작업을 launchd 에 잠깐 등록했다가 끝나면 스스로 내립니다.
> ② **서비스 계정 토큰 파일(`~/.config/krb/op-sa-token`)을 읽어서** 1Password 에 **계정 종류 조회를 최대 3번**, **버전 조회를 1번**(토큰 없음), **네트워크 도달 확인을 1번** 합니다. 금고 안의 항목 값은 읽지 않고, 어떤 출력도 저장하지 않습니다.
> ③ 오빠 PC 에서 쓰는 1Password CLI 설정·백그라운드 프로그램(`~/.config/op`)을 건드릴 수 있어서, 다른 터미널의 1Password 사용과 겹칠 수 있습니다.
> ④ **1Password 관련 macOS 팝업이 여러 번 뜰 수 있고, 몇 번인지는 보장할 수 없습니다. 누르지 마세요**(«허용 안 함»도 설정으로 저장될 수 있습니다). 스크립트가 끝나도 팝업이 남아 있을 수 있는데, 그대로 두고 저에게 알려 주세요.
> ⑤ **전체 최대 75초**이며, 도중에 멈추려면 Ctrl-C (정리 후 종료됩니다). 정리가 실패하면 «잔존 확인 필요» 라고 표시하고 **자동으로 더 시도하지 않고 멈춥니다** — 그때는 저에게 알려 주세요.
> ⑥ 운영 consumer 는 **계속 꺼진 채로 둡니다.** 서버(18712·18703)가 복구됐다는 연락과 HELM 의 재개 절차가 있기 전에는 켜지 않습니다.»

같은 메시지에 정정 한 줄: «서비스 계정 방식은 이미 쓰는 중이었습니다 — 권장의 전제가 달랐습니다. 로그를 다시 보니 키 읽기는 항상 막힌 게 아니라 간헐적으로 실패했고, 팝업 요청과 타임아웃이 같은 원인인지는 아직 모릅니다.»

보고(결정 아님): 7초 룰 수정(I-1)은 오빠 승인 없이 Master 가 진행할 수 있습니다. 다만 1Password 호출의 콜드 스타트가 7초를 넘는 것으로 측정되면 **규칙 예외 여부를 오빠께 따로 여쭙겠습니다.**

# 8. 구현 DA 에 요청할 점검
1. §3.2 재시도·마감 전파와 시험 6개 — 특히 부분 출력 timeout 무재시도, 읽은 부분 출력 객체 폐기.
2. §4.6 스크립트: 트랩 명시 종료, 자기 라벨 직접 대조, PID 기록·시작 시각 대조 종료/재수거, 합성 시험 (a)~(j) 실제 통과.
3. `op user get --me --format json` 의 `type` 실제 스키마 (불일치 시 `unsupported`).
4. §4.3 전이표의 누락 조합.
5. P0 버전 정규식이 실제 `op --version` 출력과 맞는지.

# 9. DA r2 반영 표
| r2 항목 | r3 위치 |
|---|---|
| B1 (3.5초 가산 철회 · 7초/재시도 1/14초 · S2 측정 · 예외는 오빠 결정) | §0-2 · §3 · §4.2(P0~P1b 7초) · §6.1 |
| M1 (단계별 검증기 · 단일 전이표 · P1b 상태 열거) | §4.2 · §4.3 |
| M2 (신호별 명시 종료 · 라벨 대조 · PID 기준 · launchctl 구분 · 합성 시험 추가) | §4.6 (g)(h)(i)(j) |
| M3 (`pass_elapsed_s` 폐기 · 단조 시계 측정) | §6.1 |
| M4 (서술 약화) | §1.2 |
| m1 (S0 disabled 확인) | §4.2 S0 |
| m2 (고지 수치 통일) | §7 · §4.6 상한 75초 |
| m3 (일 호출량 3단계) | §3.3 |

# 10. 미확인·한계
- (나) 간헐 타임아웃의 원인과 회복 계기 (10-13 10:40 전후) 미확정.
- 타임아웃 기간의 TCC 요청 유무 미확인. TCC 시각-틱 귀속 미확인.
- `op user get --me --format json` 스키마 · `op --version` 출력 형식 · rate-limit 수치 · CLI 시도당 실제 API 요청 수 · op 콜드 스타트 분포 미확인 (S2 가 측정).
- I-1 은 미구현 — 코드는 아직 `timeout=30`.
