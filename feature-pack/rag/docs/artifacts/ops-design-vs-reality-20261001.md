# AIRAG 운영·백업: 설계 vs 실재 · 사용자 승인 필요 운영 변경 (2026-10-01, A02 5순위 1단계)

골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위(후보 C12, C07 은 운영 결정 뒤). 이 문서는 «조사·준비»이며 집행(launchd 등록·서비스 기동·상시 수집 시작)은 하지 않았다.

조사는 전부 읽기 전용: 문서·코드 읽기, `launchctl list`·`ls`·포트 listen 조회. 운영 DB·백업·키·launchd 는 접촉하지 않았다.

## 1. 설계가 정의한 «운영 상태» vs 지금 실재

| 항목 | 설계가 정한 것 (근거) | 설계가 «무엇으로 실행되게» 했나 | 지금 실재 | 판정 |
|---|---|---|---|---|
| 일일 백업 시각·보충 | 매일 Asia/Seoul 03:00, 놓치면 다음 실행에 현재 상태 1회 보충 (`DECISIONS.md:456-463` · `PLAN.md` P08A-10) | **코어 안**: `runtime.run_once()` 가 매 패스 끝에서 `backup_due()` 로 슬롯 판정 후 `_backup()` 실행 (`runtime.py` run_once → `operations.py:backup_due`). 별도 «백업 스케줄러» 코드는 없다. «예약 실행은 core 밖의 운영 계층 책임» (`DECISIONS.md:455-457`) = **run_once 를 주기 호출하는 계층** | 실행하는 계층 **없음**. `launchctl list` 의 airag 항목은 하네스 틱 2개(`com.airag.ft-goal-tick`·`ft-news-tick`)뿐, `~/Library/LaunchAgents/com.airag.notify-master-20260928-2200.plist` 는 일회성 잔재(로드 안 됨) | 설계 있음 / 실행 계층 **없음** |
| 백업 세트·검증 | 소비자 원장·발행 DB·아카이브를 일관 세트로, 격리 임시 복원에서 DB 무결성·연결 검증 (P08A-10) | `create_backup_set` + 복원 링크검사 (`runtime.py _backup`, `operations.py`) — 2026-10-01 DA r1~r3 로 다중 아카이브·구버전 verify 보강 PASS | 운영 백업 2세트: `airag-set-20260928T143628…`(투어07) · `airag-set-20261001T141910…`(투어14, 검증 통과). **일일 자동 생성분 0** | 기능 있음 / 자동 가동 증거 없음 |
| 30일 보존·정리 | 최근 30일 보관, 새 세트 **검증 성공 후에만** 만료 AIRAG 소유 백업 자동 정리 · 사용자 승인은 «지정 백업 경로의 AIRAG 소유 만료 백업»으로 한정 (`DECISIONS.md:464-468`) | `prune_backup_sets` 가 `_backup` 안에서 호출 | 2세트뿐이라 정리 대상 없음. 「실제 자동 정리는 아직 비활성」(DECISIONS 문구) | 승인 범위 있음 / 미관찰 |
| 아카이브(90일 만료) | 90일 후 일반 검색에서 제외, 암호화 파일 아카이브로 보존 (P08A-09) | `run_once` 의 `_archive_pending` | `archives/` 디렉터리 **비어 있음** — 현 수집분이 90일 미만이라 아직 만료 대상 없음(사실 확인만) | 정상(해당 없음) |
| 상시 수집 | core 에 워처·폴링을 넣지 않음, 소비 프로젝트가 소유 (`PLAN.md:159`, `DECISIONS.md:34`) | **소비 쪽 CLI**: `airag-consumer --config … run` (옵션 없음) = `poll_seconds`(기본 30, 1~3600) 간격 무한 루프, `run --once` = 1패스 (`cli.py:105-118`). 1패스 = 수집→발행→**기억 추출(LLM 호출)**→아카이브→백업(예정 시) | 상시 프로세스 **없음**. 등록 소스는 `runtime.json` 의 **1개**(`airag-main-session`, 2026-09-09 rollout) — 유한 snapshot(`captured_byte_limit=28,156,963`)·감사 gap 1건·`coverage_complete=false` (A01 C07) | 설계 있음 / 가동 **없음** |
| 서비스 활성화 | 「운영 환경키 기반 상시 서비스는 미활성」 (`PLAN.md:159,177`) | 위 `run` + 환경변수 키 3개 `AIRAG_CONSUMER/PROJECTION/ARCHIVE_KEY_HEX` (`operations.py KEY_NAMES`) | 미활성 그대로 | 설계 있음 / 가동 **없음** |
| 키 주입 | «에이전트 없이 실행되도록 시작 시 환경변수로 주입», 1Password 직접 연동은 필수 범위 제외 (`DECISIONS.md:450-452`) | 설계상 «시작 시 환경변수» — **주입 방법 코드 없음**. 투어는 `credentials.py` 가 1Password 서비스 계정(`op read`, 토큰 파일 `~/.config/krb/op-sa-token`)으로 자식 프로세스 env 에만 채움 | launchd 가 `airag-consumer` 를 직접 띄우면 키가 없어 `MISSING_OR_INVALID_STORE_KEY` 로 즉시 실패(투어 외 경로 실측: 키 없는 `inspect` 가 같은 오류) | **빈칸**(래퍼 필요) |
| LLM·임베딩 엔드포인트 | `runtime.json` `memory_endpoint=http://127.0.0.1:18703/v1`(byz-llm) · 임베딩 `127.0.0.1:18712/v1`(byz-embed) | 상시 서비스가 매 패스 호출(새 배치만) | 두 포트 모두 listen 중(Python 프로세스). 서비스 수명 동안 항상 떠 있을지는 인프라 사항 | 의존성(사용자 인프라) |

핵심 발견 3가지:
1. **일일 백업용 별도 스케줄러는 필요 없다** — 서비스 한 개가 주기적으로 `run_once` 를 돌면 03:00 슬롯 판정·보충·검증·정리가 코어 안에서 일어난다. 즉 C12(백업 스케줄러 증거)와 C07(상시 수집)·서비스 활성화는 **같은 launchd 작업 하나**로 닫힌다.
2. 키 주입 **래퍼가 없다**(설계 빈칸). 이것이 서비스 활성화의 유일한 «코드 필요» 항목이다.
3. 무한 루프 `run`(옵션 없음)은 오류 처리가 없다 — 한 패스에서 예외가 나면 프로세스가 종료한다(`cli.py:111-118`). launchd 로 상시 운영한다면 `run --once` 를 `StartInterval` 로 부르는 편이 실패가 틱 단위로 격리된다(설계 판단 근거, 확정은 사용자·후속 DA).

## 2. 사용자 승인이 필요한 운영 변경 목록 (집행은 2단계 — HELM 이 승인받아 따로 발주)

| # | 변경 | 무엇을 설치·등록하나 | 되돌리는 방법 | 첫 실행 관찰(라이브 1회) |
|---|---|---|---|---|
| U1 | **키 주입 래퍼 구현**(코드, 등록 아님) | 1Password 서비스 계정으로 키 3개를 프로세스 env 에만 채우고 `airag-consumer --config <runtime.json> run --once` 를 exec 하는 래퍼 스크립트. 키를 파일·로그·plist 에 쓰지 않는다. Nano 구현 → Sol DA 필요 | 래퍼 파일 제거(설치 전이라 영향 없음) | 래퍼를 사용자 터미널에서 1회 수동 실행: `run --once` 결과 JSON(수집·발행·기억·백업 필드)과 키 비노출 확인 |
| U2 | **launchd 작업 등록** `com.airag.consumer` | `~/Library/LaunchAgents/com.airag.consumer.plist`: 래퍼를 `StartInterval`(예: 60초)로 실행(권장), `RunAtLoad`, 로그 `~/.local/share/airag/logs/…`. 로드는 `launchctl bootstrap gui/$UID …` | `launchctl bootout gui/$UID/com.airag.consumer` 후 plist 제거(파일 삭제는 사용자). 수집·기억 데이터 자체의 되돌리기 = 직전 검증 백업 복원(투어14 안내와 동일) | ①로드 직후 1틱: `launchctl print` 상태·로그 한 줄·`status` 의 창/기억 수·`backup_count` 대조 ②**다음 날 03:00 이후 첫 틱**: 새 백업 세트 생성+verify 통과·`last_verified_backup` 갱신 확인(= C12 닫는 증거) |
| U3 | **상시 수집 대상 결정** | 지금 등록된 소스는 1개(09-09 rollout 유한 snapshot, gap 1건). 현재·향후 세션의 어떤 rollout 을 `runtime.json` `sources` 에 등록할지, `allow_gaps` 정책(현재 `false`)을 사용자가 정해야 한다 | `runtime.json` 변경 전 파일 백업 필수. 투어 설치 도구(`deployment_setup.py write_json`)는 기존값과 다르면 `EXISTING_CONFIGURATION_DIFFERS` 로 거부하므로 갱신은 별도 절차가 필요하다. 소스 제거는 사용자 판정 | 등록 후 첫 `run --once`: 소스별 `committed_native_offset` 증가·`coverage_complete`·gap 수 |
| U4 | **상시 LLM 사용 수락** | 서비스가 매 패스 `127.0.0.1:18703` 로 기억 추출 요청(새 배치만). GPU·공유 vLLM 에 상시 부하(부하 시험은 보류 중 — 이 부하는 «운영 부하») | U2 의 bootout 으로 중단. `memory_enabled=false` 설정으로 추출만 끄기도 가능(config 변경 = U3 와 같은 절차) | 첫 패스의 기억 `provider_requests`·지연, 서버 상태 |
| U5 | **자동 백업 정리 활성** | 새 세트 검증 후 30일 초과 AIRAG 소유 백업만 정리(`DECISIONS.md:464-468` 승인 범위). 첫 정리는 30일 뒤에야 발생 — 지금은 관찰 불가 | 정리는 되돌릴 수 없으므로 **외부 복제는 사용자 책임**(설계 확정사항). 그 전 단계에서 `prune` 대상 목록을 보고만 하도록 먼저 관찰 가능 | 31일째 이후 정리 로그 — 1단계에서 확인 불가 |
| U6 | **로그 위치·보존** | `~/.local/share/airag/logs/` 신설, 크기 상한 정책 | 디렉터리 제거 | 첫 틱 로그 |

권장 순서(2단계 발주 초안): U1(구현·DA) → 사용자가 U3 결정 → U1 래퍼 수동 1회 → U2 등록 + 1틱 관찰 → 다음 날 03:00 슬롯 관찰(C12 닫힘). U4·U5 는 U2 승인에 포함해 확인받는다.

## 3. 이번 단계에서 하지 않은 것
launchd 등록·서비스 기동·상시 수집 시작 · 운영 DB 쓰기 · 운영 백업 삭제 · 잔여 확인대기 51·검증대기 25 처리 · 키 값 출력/기록 · push.

## 4. 근거 파일
`feature-pack/rag/docs/DECISIONS.md:450-468` · `PLAN.md:159,175,177` · `rag-consumer/src/airag_consumer/{cli.py:28-60,96-140, runtime.py run_once/_collection_pass/_backup, operations.py backup_due·KEY_NAMES}` · `~/.local/share/airag/projects/ai-feature-pack/runtime.json`(설정값만 확인) · `launchctl list` · `~/Library/LaunchAgents/com.airag.*` · A01 증거 보드 C07·C12.
