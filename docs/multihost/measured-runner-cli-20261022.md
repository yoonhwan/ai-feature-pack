# 러너 CLI·동작 실측 — sha `33335c7a` (2026-10-22)

> 작성: `aifp-pi-master-pi#0` · 발주 #3148 ① · **읽기 전용**(`git show` · `.env` 열지 않음 · 값 0)
> 대상 sha: `33335c7a353e09f17cc9048e3989e4e8b5d9a05a` · 파일 `tests/e2e/realtime_multi_e2e.py`(이하 «러너») · `tests/e2e/cdp_helper.py` · `tests/e2e/multi_realtime_corpus/cli.py`
> 줄번호는 **그 sha 기준**(오늘 이전 문서의 줄번호와 다를 수 있다 — 실제로 4795→4873 처럼 밀렸다)

---

## 1. CLI 옵션 전체 (러너 `main()` argparse · 4873-4909)

| 줄 | 옵션 | 기본값 | 뜻 |
|---|---|---|---|
| 4874 | `--baseline` | False | 양방향(host A + guest B 발화) baseline |
| 4875 | `--json` | False | JSON 출력(`passed/total` 로 exit code 결정) |
| 4876 | `--all` | False | 전체 시나리오 자율주행 |
| 4877-4881 | `--check <name>` | 없음 | no-audio 단일 검증(`guest_join_error`·`room_expire`·`credit_gate`·`credit_multi_user`·`member_presence`·`self_echo`) |
| 4882-4887 | `--scenario <name>` | 없음 | `SCENARIOS` 중 1개 자율주행 |
| 4888-4893 | `--m6 <name|all>` | 없음 | M6 멀티게스트(host 1 + guest N) |
| 4894 | `--mr-corpus` | False | 멀티화자 코퍼스 전체 sweep |
| 4895 | `--mr-scenario <id>` | `""` | 코퍼스 시나리오 1개 |
| 4896 | `--mr-list` | False | 코퍼스 케이스 목록 |
| 4897 | `--engine say|sag` | **`say`** | 발화 엔진 |
| 4898 | `--mr-turn-limit N` | `0`(무제한) | 코퍼스 **첫 N턴만** |
| 4899 | `--mr-stop-on-error` | False | 첫 turn 실패에서 중단 |
| 4900-4905 | `--lst-toggle-mid-press-ms N` | `0`(끔) | press 중 LST 토글 trusted 클릭 1회 |
| 4906 | `--mic-pass N` | `0` | 마이크 건네기 시나리오(별 모듈) |
| 4907 | `--overlap` | False | 겹친 말(`--engine say` + 특정 시나리오만 허용: 4916-4920) |
| 4908 | `--speaker-devices` | `""` | 겹친말용 장치 표 |
| 4909 | `--speaker-profiles` | `""` | 겹친말용 크롬 프로필 표 |

분기 순서(4915-4990): `--overlap` 검증 → `--mic-pass` → `--mr-*`(코퍼스 CLI 위임) → `--m6` → `--all` → `--check` → `--scenario` → `--baseline` → 아무것도 없으면 **help 출력 후 rc=0**.

## 2. «가장 작게 한 번» 돌리는 조합

| 후보 | 발화 수 | 판정 |
|---|---|---|
| `--mr-scenario baseline-ko-en --mr-turn-limit 1 --engine say` | **1턴(1회 press)** | ★권장★ — `--mr-turn-limit`(4898)이 «첫 N턴만»(코퍼스 `cli.py:17·41` `turn_limit`)이라 정확히 1턴에서 끊는다 |
| `--scenario host_only --engine say` | host 2문장(203-207: `host` 2개 · `guest` 0) | 2회 press · guest 무발화라 «일방 통역» 만 본다 |
| `--scenario baseline` | 2회(host 1 + guest 1 · 136-140) | 최소 *양방향* — press 2회 |
| `--scenario toggle_nospeak` | 0회 | 발화 없음(무발화 검증) — STT 최종본 목적 아님 |

- 시나리오 문장 수 실측(파싱): 1문장/1문장 = `baseline`·`long_speech`·`short_burst`·`numbers_proper`·`formal_business`·`question_answer`·`simultaneous_speak`·`mixed_lang`·`emotional_exclaim`·`nickname_duplicate`·`cross_lang_3way`·`ptt_independence`… / `host_only`=2,0 / `short_burst` 는 **xfail**(VAD 500ms — 짧은 발화 필터).
- ★`short_burst` 는 xfail★(157-159) → 성공 판정에 쓰지 말 것.
- 코퍼스 jsonl 의 가장 짧은 항목 = `baseline-ko-en`(첫 줄 · 카테고리 baseline · 호스트 ko / 게스트 en).

## 3. Chrome — **러너가 직접 열지 않는다**(CDP 9333 에 붙어 탭을 «만든다»)

- 러너에 `Google Chrome` 기동 코드 **없음**(grep 0). 전제는 «headed Chrome 이 `--remote-debugging-port=9333` 으로 이미 떠 있음».
- 탭 생성: 홈 탭이 없으면 `cdp_new_tab(HOME_URL)` (**2015**), 룸/게스트 탭도 `cdp_new_tab(...)` (**2063**, **3661**, **4812**). 즉 **빈 Chrome 만 있으면 러너가 탭을 연다**.
- 홈 탭 식별은 URL 비교: **850** — `url.split("?")[0].rstrip("/") == HOME_URL.rstrip("/")` (쿼리 무시).
- 클릭은 **trusted 마우스**(`_mouse_click_async` 909·1037) — «실제 UI» 경로.
- 로그인/토큰: host 는 **로그인 없이**(파일 헤더 12 «host=로그인(token 無)»), guest 는 `?token=…`(QR 공유 토큰). `BYZ_E2E_JWT_SECRET` 은 **크레딧/유저 API 호출용 HS256 폴백**(`gateway/infrastructure/middleware/auth.py:19-25·109`) + `_get_credits_balance`(러너 3720 부근) — 즉 **인증 UI 가 아니라 API 토큰**이다.

## 4. 서버 주소 우선순위 (84-94)

| env | 줄 | 기본 | 비고 |
|---|---|---|---|
| `BYZ_WORKER_LOG` | **84** | `/tmp/byz-worker.log` | 로그 tail 경로 |
| `BYZ_WEB_PORT` | **87** | `3015` | |
| `BYZ_GATEWAY_PORT` | **88** | `8080` | |
| `BYZ_WEB_BASE` | **92** | `""` → `http://localhost:{WEB_PORT}` | **있으면 우선**(`.rstrip("/")`) |
| `BYZ_GATEWAY_BASE` | **93** | `""` → `http://localhost:{GATEWAY_PORT}` | 있으면 우선 |
| `HOME_URL` | **94** | `f"{WEB_BASE}/"` | 홈 탭 매칭에 쓰임 |
| `CDP_PORT` | `cdp_helper.py:21` | `9333` | |

- **ws/sse 주소는 BASE 에서 파생되지 않는다** — 러너는 HTTP 로 `WEB_BASE`/`GATEWAY_BASE` 만 쓰고(예: `/api/v1/credits/me`), 브라우저 안의 ws/sse 는 **웹앱이 빌드 타임에 박은 `NEXT_PUBLIC_*`** 를 쓴다 → **서버 h 에서 `NEXT_PUBLIC_WS_URL`·`SSE_URL`·`API_URL`·`BASE_URL` 을 38312/38314 로 박아 빌드**해야 한다(이미 h-mini-byz-server.sh 가 그렇게 한다).
- 기능적 하드코딩은 **기본값뿐**(87·88) — grep 상 `8080`/`3001`/`3015` 는 **주석·help**(41·86·3459)에만 나온다.

## 5. 결과·로그·성공 판정

| 무엇 | 어디 | 줄 |
|---|---|---|
| 진행 로그 | **stdout/stderr** (`print`) — 파일 저장은 h 가 한다 | — |
| 워커 로그 tail | `LOG_FILE`=`BYZ_WORKER_LOG` (기본 `/tmp/byz-worker.log`) — `_log_tail_since` (**1442** 부근) | 84 |
| 판정 단위(방향별) | `_finish(out, json_mode)` 반환 dict 의 `passed/total` | 4971·4985 |
| **«STT 최종본 1건» 성공 문자열** | **`  ✅ host 단일 버블 (delta=1, polished {N}chars)`** (2891) · guest 쪽은 **2912** `✅ guest 단일 버블 (delta=1, polished …)` | 2884-2912 |
| 실패 문자열 | `  ❌ host 버블 delta={d}`(2885) · `polished_too_short`(2896) | — |
| exit code | `--scenario`/`--baseline` + `--json` 이면 **`passed == total` → 0**, 아니면 1 (4971·4985) · 코퍼스 경로는 `all(not r["errors"])` → 0 (cli.py:47) | — |

## 6. 선행조건 자기검사 — **러너에 없다**

- 오디오 장치(BlackHole)·CDP·서버 health 를 **미리 검사하는 코드가 러너에 없다**(grep: `BlackHole` 은 주석·xfail 이유 설명뿐 8·181).
- 즉 **h 가 preflight 를 해야 한다**(서버 health·CDP LISTEN·홈 탭 유무·BlackHole 장치·tts-say·«다른 오디오 회차 없음»).
- 「러너가 오디오 장치를 확인하나?」 → **아니오**. 장치가 틀리면 그냥 STT 가 비어 실패한다(무음 통과 아님 — RMS 게이트가 잡는다).

## 7. ★하드 룰 11(치트 금지) 위반 가능 경로★ — «쓰지 말 것» 목록

| 종류 | 위치 | 판정 |
|---|---|---|
| **Redis 직접 쓰기** | 러너 전체 grep `redis-cli`·`redis.` **0건** | ✅ 없음 — 러너는 Redis 를 직접 만지지 않는다(서버 경유만) |
| **DOM 이벤트 주입** | **1091-1094** `document.dispatchEvent(new KeyboardEvent("Escape"…))` (SettingsSheet 닫기) · **1542-1546** 닉네임 입력: `HTMLInputElement.prototype.value` setter 직접 호출 + `dispatchEvent(new Event("input"/"change"))` | ⚠ **있다** — 단 «말풍선 주입» 이 아니라 «입력 필드 채우기·오버레이 닫기» 용. **새로 추가 금지**(기존 러너 그대로 쓰라는 발주 조건과 일치) |
| **페이지 전역 플래그 설정** | **1934** `window.__v5TtsLedger=true; window.__v5TtsPlays=[]` (TTS 재생 원장 계측) · 1941 읽기 | ⚠ **있다** — 계측용. 새 코드에서 쓰지 말 것 |
| **trusted 클릭** | `_mouse_click_async`(909·1037) · `--lst-toggle-mid-press-ms`(4900) | ✅ 허용 경로(이게 «정공법») |
| **옵션 중 쓰지 말 것** | `--all`(4876, 전체 순회 — 1회차에 과함) · `--overlap`(4907) · `--speaker-devices/profiles`(4908-4909) · `--lst-toggle-mid-press-ms`(4900, 기본 0 유지) · `--mic-pass`(4906, 별 모듈) | 1회차엔 **미사용** |

**결론**: 1회차 명령은 **`--mr-scenario baseline-ko-en --mr-turn-limit 1 --engine say`** 하나로 충분하고, 위 ⚠ 항목은 «러너 내부에 이미 있는 계측·입력 보조» 이므로 **우리가 새로 만들지 않는다**(발주 조건 «기존 러너 그대로» 준수).

## 이 문서가 하지 않은 것
- 코드 수정 0 · 원격 쓰기 0 · 앱 실행 0 · `.env` 열지 않음(값 0) · 시험 실행 0
