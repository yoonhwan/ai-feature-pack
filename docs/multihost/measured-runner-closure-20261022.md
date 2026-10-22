# 러너 import·파일 폐쇄 실측 (2026-10-22)

> 작성: `aifp-pi-master-pi#0` · 발주 #3118 · 이 맥 **읽기만**(원본 BYZ repo 수정 0)
> 대상 러너: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/tests/e2e/realtime_multi_e2e.py` (213,179 bytes)
> 방법: AST 정적 분석(import·`sys.path.insert`·`Path(__file__)` 상대경로·`subprocess` 호출) + 실제 파일 존재 확인. **동적 실행 아님**(러너는 Chrome/오디오가 필요해 이 단계에서 돌리지 않는다).

## 1. 폐쇄 파일 목록 (이것만 옮기면 import 는 닫힌다)

| # | 경로 (repo 기준) | 크기 | 왜 필요한가 |
|---|---|---|---|
| 1 | `tests/e2e/realtime_multi_e2e.py` | 213,179 B | 러너 본체 |
| 2 | `tests/e2e/cdp_helper.py` | 40,314 B | `from cdp_helper import …` (line 66) — CDP WebSocket 직접 연결 |
| 3 | `tests/e2e/tts_rms_gate.py` | 9,291 B | `from tts_rms_gate import verify_tts_audio` (line 78) |
| 4 | `tests/e2e/multi_realtime_corpus/__init__.py` | 521 B | lazy import 대상 패키지 (`from tests.e2e.multi_realtime_corpus import cli as mr_cli`, line 4805) |
| 5 | `tests/e2e/multi_realtime_corpus/cli.py` | 1,743 B | `mr_cli` 진입 |
| 6 | `tests/e2e/multi_realtime_corpus/lib/__init__.py` · `loader.py` · `dialogue_runner.py` · **`loom_domain.py`** (`lib/` 전체) | (합 ~196K 중) | `cli.py` 가 `.lib.loader`·`.lib.dialogue_runner` 를 상대 import · `dialogue_runner.py:3` 이 **`.loom_domain` 을 import**(도메인 선택 UI 드라이버 — 처음 목록에서 빠져 있어 추가함) |
| 7 | `tests/e2e/multi_realtime_corpus/scenarios/multi_realtime_corpus.jsonl` | 61,612 B | `__init__.py:4` · `cli.py:6` 가 **`Path(__file__).parent/"scenarios"/…`** 로 직접 연다(데이터) |
| 8 | `tests/__init__.py` · `tests/e2e/__init__.py` | 소 | `from tests.e2e…` 패키지 import 전제(`_repo_root` 를 `sys.path` 에 넣는 코드 4802-4804) |

- 실측 확인: `tests/__init__.py` 있음 True · `tests/e2e/__init__.py` 있음 True.
- `multi_realtime_corpus/lib/` 실측 파일 10개 내외(turn_execution·voices·transcript_quality·turn_validation·test_* 등) — **폴더 통째(196K)** 를 옮기는 게 안전(내부 상대 import 가 얽혀 있다).

## 2. 3rd-party 의존 (설치 필요)

| 모듈 | 쓰는 곳 | mini 상태(실측) | 비고 |
|---|---|---|---|
| **websockets** | `cdp_helper.py:100·118`, `cdp_console.py:14` | ❌ **없음** | `python3 -m pip install --user websockets` |
| **jwt** (PyJWT) | `realtime_multi_e2e.py:3713` (지연 import, E2E 토큰 생성) | ❓ 미확인(import 시점이 토큰 필요 경로) | 필요 시 `pip install --user pyjwt` |
| 그 밖 | — | — | 나머지는 표준 라이브러리만(asyncio·urllib·json…) |

## 3. 외부 실행 파일 (러너가 subprocess 로 부른다 — 파일 복사로 안 됨)

| 명령 | 쓰는 곳 | 이 맥 | mini(실측) |
|---|---|---|---|
| `sag` (ElevenLabs TTS) | 1353 `sag speak -v … -o … --play …` | `/opt/homebrew/bin/sag` | ❌ absent |
| `tts-say` | 1370 `tts-say speak --engine say …` | `~/.local/bin/tts-say` | ❌ absent |
| `say` | 4795 | `/usr/bin/say` | ✅ `/usr/bin/say` |
| `sox` | `tts_rms_gate.py:136` (RMS 측정) | (이 맥 있음) | ❌ **absent** |
| `afplay` | `tts_rms_gate.py:188·190` | 있음 | ✅ `/usr/bin/afplay` |
| `tail`·`wc` | 1442 · `_log_tail_since` | 있음 | ✅ |

→ **TTS 엔진 경로(sag·tts-say)와 sox 는 mini 에 없다.** 첫 회차에서 «발화 주입» 경로를 쓰려면 이 3종 설치가 필요하고, 이는 **원격 쓰기 = 오빠 승인 h** 다.

## 4. 비밀 파일 — 복사 금지(중요)

- `_load_e2e_jwt_secret()` (3697-3708) 는 **`REPO/.env` 또는 `REPO/.env.local` 에서 `BYZ_E2E_JWT_SECRET=` 를 직접 파싱**한다.
- 따라서 폐쇄에 `.env` 가 «들어올 수 있는 구조» 다 → **h 는 `.env*` 를 명시적으로 제외**하고, 비밀은 `BYZ_E2E_JWT_SECRET` **환경변수로만** 주입한다(값 보관 = op develop 볼트 · 하드 룰 15 · 이 문서·스크립트에 값 0).
- `.env` 를 옮기면 mini 디스크에 비밀이 상주하게 되므로 **의도적으로 옮기지 않는다.**

## 4b. 폐쇄 «밖» 이지만 러너가 기대는 것 (실측)

- `loom_domain.py:73` 의 도메인 선택은 **UI 드롭다운 옵션**을 클릭한다 → 도메인 풀이 서버 쪽에 등록돼 있어야 한다(`shared/prompts/composable/domains` = **312K · 폴더 5개+**). 러너 코드에는 이 경로 문자열이 없어 «코드 폐쇄» 밖이지만, **실행 조건**으로는 서버(FE) 쪽 자산이다 → 서버를 이 맥에 두는 후보 1이면 자동 해결, mini 로컬 기동(후보 2)이면 이 폴더도 필요.
- `mr_preflight.sh` 주석이 경고하는 «함정 B» 와 같은 지점(도메인 미등록 → `loom_domain_select` RuntimeError).

## 5. repo 구조를 «가정» 하는 곳 (⚠ 위치 가정)

| 위치 | 가정 | 영향 |
|---|---|---|
| `REPO = _THIS_DIR.parent.parent` (80) | `tests/e2e/` 두 단계 위가 repo 루트 | `~/Project/BYZ-e2e/tests/e2e/…` 로 배치하면 `REPO=~/Project/BYZ-e2e` 가 되고 `.env` 탐색도 그 아래를 본다 |
| `sys.path.insert(0, str(_THIS_DIR))` (65) | `cdp_helper`·`tts_rms_gate` 가 **같은 폴더** | 두 파일을 반드시 같은 폴더에 |
| `sys.path.insert(0, _repo_root)` (4802-4804) | `tests` 패키지가 repo 루트 아래 | `tests/__init__.py`·`tests/e2e/__init__.py` 필요 |
| `mr_preflight.sh:WT="…/.worktrees/v6-realtime-live"` | **워크트리 경로 하드코딩** | preflight 래퍼로 돌릴 땐 워크트리까지 필요 · 이 h 는 «러너 단독» 만 배치 |
| `BYZ_WORKER_LOG` 기본 `/tmp/byz-worker.log` | 워커 로그가 **로컬 /tmp** | mini 에서 서버를 이 맥에 두면 로그도 이 맥에 있어 `LOG_FILE` 경로를 맞춰야 한다(후보 1 의 숙제) |
| `CDP_PORT=9333` · Chrome `--user-data-dir=/tmp/chrome-byz-debug` | 로컬 Chrome | mini 에서 그대로 유효 |

## 6. 결론 (h 에 반영한 것)

1. 옮길 것 = 위 §1 의 8항목(= 파일 7 + `lib/`·`scenarios/` 폴더) → `~/Project/BYZ-e2e/` 에 **repo 와 같은 상대 구조**로.
2. 옮기지 않을 것 = `.env*` · `.git` · 나머지 repo(수백 MB) · 워크트리.
3. 설치 = `websockets`(+필요 시 pyjwt) `pip --user` · **TTS 3종(sag·tts-say·sox)은 이번 h 에서 제외**(별도 승인 · 첫 회차 발화 필요 여부 확정 뒤).
4. 검증 = 배치 후 `python3 -c "import cdp_helper, tts_rms_gate; import tests.e2e.multi_realtime_corpus"` + 파일 수·sha256 목록 대조.
