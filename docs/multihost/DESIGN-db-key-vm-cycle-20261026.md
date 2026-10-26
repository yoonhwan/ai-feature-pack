「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스에 tailscale 연결, cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영」(오빠 2026-10-21)
「DB 경로: 읽기 전용 검증부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 러너)» 의 남은 의존 하나 = mini 서버가 DB 에 닿는 길(지금은 이 맥의 역방향 포워딩 38309 에 걸려 있음).

# 카드 하나 — DB 길 열쇠: 포워더 VM 을 이 맥이 하루 2회 끄고 켜고, Google 이 14시간 뒤 스스로 끈다

작성: aifp-multihost-arch-claude#2 (Fable 5.1 팀 좌석) · 2026-10-26 · 발주 #3305 → master #3311 지시로 **두 카드로 분할**(이 파일 = 카드 하나 · DA 승인 대상). 카드 둘(콜리마 도커 세트 h4~h5)은 `DESIGN-colima-docker-set-20261026.md` — DB 길이 승인·설치된 뒤 별도 설계+DA.
분할 전 원본(r1~r3 심사본·반영표 전부) = `DESIGN-db-expiring-credential-colima-20261026.md`.
오빠 결정(#3309): 열쇠 창 **14시간 · 하루 2회 끄고 다시 켜기**(하루 두 번 ≤ 120초 DB 단절 수용) · 이 맥 자신의 DB 터널은 **그대로**.
조사 = 읽기 전용만. 쓰기·원격 변경·키 값 출력 0. 커밋·push 는 master 집행.

## 0. 결론

**가능하다.** mini 가 dev DB(Cloud SQL 사설 10.2.0.10:5432)에 닿는 길을 포워더 VM `byz-db-fwd` 하나에 걸고, 그 VM 을 이 맥 launchd 가 **08:07·20:07 에 끄고 다시 켠다**(새 가동 주기). VM 은 `--max-run-duration=14h` + `--instance-termination-action=STOP` 으로 **Google 이 스스로 끈다**. 이 맥이 안 켜 주면 다음 창은 없다(닫힘 쪽 실패). 요구를 정확히 적으면 「이 맥의 최근 재기동에 따라 **DB 길만** 최대 14시간 허용」이다 — 「이 맥이 없으면 즉시 아무것도 못 함」은 아니다(오빠 수용).

## 1. 가능 판정 근거 3개 (오늘 읽기 전용 실측)

- 열쇠를 걸 자리: 이전 안 «새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1»(`VERIFY-db-path-20261025.md`)에서 mini 의 DB 길은 **포워더 VM 하나에만** 걸린다(단, 지금의 역방향 포워딩을 걷어야 유일해진다 — §3).
- Google 이 만료를 강제하는 수단: `instances create` 의 `--max-run-duration`(«마지막으로 켜진 때부터 상대 시간» · 도움말 658행) + `--instance-termination-action=STOP`(546행). ★`instances update` 에는 이 플래그가 **없다**(도움말 확인) → 가동 중 갱신 불가 → 절차는 «끄고 켜기» 다.★ mini 의 SA `byz-mini-tunnel` 은 프로젝트 IAM 에 `roles/iap.tunnelResourceAccessor` 조건부 바인딩 1개뿐 → 이 시계를 못 만진다. 그 바인딩만으로 mini 는 인스턴스 이름으로 IAP 터널을 이미 열고 있다(launchd `com.byz.iap-tunnel-llm` 가동 중 실측).
- 이 맥이 끄고 켤 권한: SA `byz-local-dev` 에 `roles/compute.instanceAdmin.v1`(실측). 새 권한 추가 0.

## 2. 만료를 «어디에» 거는지 — 5안 비교

| 안 | 매일 하는 일 | 만료 강제 주체(mini 가 어겨도 막히나) | 이 맥 꺼짐 | 절차 실패 시 | 권한·변경(추가만?) | 되돌림 |
|---|---|---|---|---|---|---|
| **VM 하루 2회 재기동**(채택) | `instances stop` → `start` | **Google(Compute)**. TERMINATED 뒤 그 VM 경유 전달 불가 | 창(≤14시간) 끝나면 닫힘 | 닫힘 | 이전 안 3 + 생성 플래그 2 + 고정 IP 1 · 이 맥 새 IAM 0 | VM·방화벽·고정 IP 삭제(HIL) · 조건식 복원 |
| IAM 시간 조건 | 조건식 `request.time < …` 갱신 | Google(IAM) · 열린 IAP 세션 잔존 [확인 필요] | 새 연결 거부 | 닫힘 | 이 맥에 **프로젝트 IAM 쓰기** 추가(없음) | 조건식 복원 |
| 단기 토큰 전달 | 1~12시간 토큰 전달 | Google(토큰) | 닫힘 | 닫힘 | TokenCreator · 12시간 상한 → 하루 1~2회 불가 | 만료 |
| 하루 키 교체 | 만료 인증서 키 업로드·전달 | Google(키) [확인 필요] | LLM·STT 까지 닫힘(범위 넓음) | 닫힘 | KeyAdmin · mini 원격 쓰기 매일 | 환원 |
| DB 자격 자체 만료 | IAM DB 인증·비번 회전 | Google(Cloud SQL) | 닫힘 | 닫힘 | ★DB 변경★ `cloudsql.iam_authentication` 미설정 · 사용자 4명 BUILT_IN(실측) · DSN·Secret Manager·`loom_dsn.sh` 롤 계약 변경 → 오빠 원문 «이번 일은 길» 과 어긋남 | 플래그 끄기 |

## 3. 이전 안과의 관계 · 포워더가 유일한 길이 되는 조건

- **이전 안 3가지 위에 얹힌다. 포워더 없이는 안 된다**: Cloud SQL 은 사설 IP 뿐(`ipv4Enabled: false` 실측) · IAP 는 VPC 안 VM 포트로만 · 끌 수 있는 전용 VM 이 곧 열쇠 구멍(GPU VM 은 끌 수 없음).
- 더해지는 것: 생성 플래그 `--max-run-duration=14h --instance-termination-action=STOP --no-restart-on-failure`(자동 재시작이 새 주기를 만들지 않게) · **내부 고정 IP 예약**(`byz-agents-subnet-dev` 10.0.0.0/24) → IAP 조건식 `destination.ip` 고정. 방화벽 1줄(35.235.240.0/20 → tcp:38309 · 태그 `db-fwd`)·IAP 조건 1줄(`destination.ip == <고정 IP> && destination.port == 38309` 추가)은 이전 안 그대로.
- 포워더 구현: e2-micro · COS · `create-with-container` `alpine/socat` `TCP-LISTEN:38309,fork,reuseaddr TCP:10.2.0.10:5432` · ssh 불필요. ★조합이 안 먹으면 **도입 중단**(게스트 `shutdown` 타이머로 대체하지 않는다).★ h1 합격 = `describe` 의 `scheduling.maxRunDuration.seconds == 50400` ∧ `instanceTerminationAction == STOP`. `terminationTime` 은 상대 시간 설정에서 반환 보장을 모르므로 **있으면 기록, 필수 아님**. 만료 강제는 **첫날 실측(격리 관찰 · DA r3 조건 5)**: h1 이 VM 을 만들어 켠 시각 `lastStartTimestamp`(실제 값으로 계산 · 08:07 가정 금지)부터 **14시간 동안 어떤 재기동도 금지**(h3 launchd 는 이 관찰이 끝난 뒤 설치 · h2 의 stop/start 시험도 관찰 뒤) → 예상 시각 ±10분에 손 없이 TERMINATED 가 되면 합격 → 그 뒤 `instances start` 1회로 길을 복구하고 h2·h3 로 간다. 이 관찰 회차는 운영 합격 집계(§5 · 정상 예약 4회)에 넣지 않는다.
- **유일한 길 조건**: ⓐ 역방향 포워딩 제거 — 정본 `h-plans/h-mini-byz-server.sh` 29행 `FWD_PORTS=("$TUN_PORT" $FWD_EXTRA)` 가 DB 38309 를 **항상** 넣으므로 `FWD_DB=0`(기본) 스위치를 넣고 진입점 `h-mini-byz-server-run.sh` 에 고정 · h2 첫 단계에서 **살아 있는 `ssh -R` pid 를 `ACTION=stop` 경로로 종료**(목록만 바꾸면 열린 포워딩은 남는다) ⓑ mini 의 GCP 자격은 `~/.config/byz-tunnel/sa.json` 1개(ls 실측) · 프로젝트 IAM 의 mini 주체도 그 SA 1개 ⓒ 합격 시험 = VM TERMINATED 상태에서 mini 의 **기존 DB 세션**과 **신규 DB 연결** 모두 실패.

## 4. «이 맥이 열쇠» 보안 성질 — 현재 vs 설계

| 항목 | 현재(이 맥 역방향 포워딩) | 설계(VM 하루 2회 재기동) |
|---|---|---|
| mini 가 DB 에 닿는 조건 | 이 맥 켜짐 + h 가 연 `ssh -R` 생존(며칠이고 산다) | 포워더 RUNNING = 마지막 기동 뒤 14시간 안 |
| mini 침해 시 | 127.0.0.1:38309 + DSN → DB(롤 권한만큼) · 상한 없음 | SA 키 + DSN → 같은 권한 · **상한 = 남은 창 ≤ 14시간** |
| 즉시 차단 | ssh pid kill | `instances stop byz-db-fwd` 1줄 → **TERMINATED**(Compute 정지 완료 상태명) 뒤 신규·기존 전달 불가. 정지 요청→TERMINATED 는 비동기(목표 ≤ 60초 [확인 필요]) · DB 안에서 도는 쿼리가 즉시 취소되는 건 아님 |
| 이 맥 꺼짐 | 즉시 닫힘 | 남은 창 끝나면 닫힘(최대 14시간) ← 오빠 수용 트레이드오프 |
| 이 맥 새 권한 | 0 | 0(후속: VM 단위 커스텀 역할 start·stop·get) |
| mini → 이 맥 길 | 0 | 0 |
| DSN 자체 | mini 디스크 상시 | 같다 → 후속 «DB 자격 자체 만료» |
| LLM·STT 길 | mini 자체 IAP 상시 | 범위 밖 · 상시(변화 0) |

스케줄 산술: 08:07 기동 → 만료 22:07 · 20:07 기동 → 만료 익일 10:07. 간격 12시간 · 여유 2시간. 예약 1회를 놓치면 만료 뒤 다음 예약까지 약 10시간 닫힘 = 의도.

## 5. 하루 절차 (오빠 손 = 매일 0회)

이 맥 launchd `com.byz.db-key-daily`(08:07 · 20:07 · SA byz-local-dev · 전용 `CLOUDSDK_CONFIG` · gcloud 587 고정):
0. 잠금(DA r3 조건 4): `mkdir ~/.byz-db-key.lock`(원자) 안에 `pid`·`started`·`round`·`op_id` 파일을 쓴다. 다른 실행이 잠금을 만나면 ⓐ 기록된 pid 가 살아 있으면 «진행 중» 으로 즉시 종료 ⓑ pid 가 죽었으면 `op_id` 의 Compute 작업이 DONE 인지 확인한 뒤에만 회수. 해제는 자기 pid 가 쓴 잠금만. 경과 시간만으로 회수하지 않는다.
1. 단조 시계 시작(`T0` · DA r3 조건 1 — 단절 측정 시작점 = stop 요청 시각) → `instances stop --async` 로 **작업 ID 를 먼저 받아 잠금에 저장**(DA r3 조건 3) → `operations wait <op>`(`timeout 50`) → `describe` 상태 **TERMINATED** 확인(아니면 작업 오류 원문을 로그에 남기고 start 하지 않고 FAIL) → `instances start --async` → 작업 ID 저장 → `operations wait`(`timeout 35`) → RUNNING 확인. ★RUNNING 이어도 건너뛰지 않는다 — 새 주기가 목적.★ 모든 대기·폴링은 `T0+120초` 전체 마감 안에서만 돈다(남은 예산을 각 단계 timeout 으로 쓴다).
2. `describe` 로 `maxRunDuration`·`lastStartTimestamp`·(있으면) `terminationTime` 기록 — `lastStartTimestamp` = 이번 회차 가 갱신 증거 · 만료 예상 = `lastStartTimestamp + 14h`.
3. mini 복구: `ssh mini '<venv python> -c "psycopg SELECT 1"'`(DSN 은 mini 0600 파일에서 · 값 출력 0) 를 5초 간격으로 **`T0+120초` 까지** 반복. 그 안에 성공 = 회차 OK(단절 초 = 첫 성공 − T0). 실패로 마감이 지나면 **별도 장애 절차**: `launchctl kickstart -k gui/<uid>/com.byz.iap-tunnel-db` 1회 → 60초 더 시도 → 그래도 실패면 FAIL(회차 집계에는 «예산 초과» 로 들어간다 · 복구는 돼도 합격은 아니다).
4. 로그 `~/Library/Logs/byz-db-key.log` 1줄(회차·단절 초·상태·op_id) · FAIL 시 알림센터 + tts-say + mbox `[FAIL]` 1통(슬랙 경로 [확인 필요]).

단절 예산(오빠 수용 «회당 1~2분» = **T0 기준 전체 마감 120초**): 안내용 배분은 정지 ≤ 50 + 기동 ≤ 35 + 첫 `SELECT 1` ≤ 35 이나, 합격 판정은 배분이 아니라 **마감 하나**로 한다. [확인 필요: e2-micro COS 의 정지·기동 실측 — h2 ③ 에서 재면 그 값으로 배분을 고친다.]
mini 터널의 복구 경로 2개(DA r3 조건 2): ⓐ **정상 경로** — `start-iap-tunnel` 로컬 리스너는 들어오는 연결마다 IAP 세션을 새로 만들므로 VM 이 돌아오면 **새 연결**은 재시작 없이 통한다(SDK 587 구현 원문 대조는 하지 않았다 · h2 ③ 실측으로 확인). 서버의 연결 풀에 남은 «정체된 기존 연결» 은 서버가 끊김을 감지해 다시 열어야 한다 — 러너 1회차로 확인. ⓑ **감독 재시작 경로** — 감독 루프는 «검사 시작 간격 30초 · `pg_isready -t 5` · 연속 5회 실패(첫 실패부터 다섯째 실패 시작까지 120초)» 로 정의하고, 5회째 실패에 터널을 종료 → launchd(ThrottleInterval 30)가 다시 올린다. 이 경로는 계획 단절(≤120초) 안에서는 발동하지 않도록 문턱이 더 길다. 두 경로의 `SELECT 1` 복구 시간을 h2 ④ 에서 **각각** 잰다(ⓑ 는 터널 프로세스를 강제로 멈춰 만든다).
**복구 합격은 `pg_isready` 가 아니라 실제 DSN `SELECT 1`**.
합격 조건: **이틀 동안 정상 예약 4회** 모두 «단절 ≤ 120초(T0 기준) · 매회 `SELECT 1` 복구». ★첫날 만료 관찰 회차는 이 집계에 넣지 않는다(§3 · DA r3 조건 5).★

## 6. 도입 순서 (오빠 손 3번 · 각 h = DRY + 되돌림 + 만든 자원 원장 줄)

| # | 어디서 | 하는 일 | 닫는 증거 | 되돌림 |
|---|---|---|---|---|
| h1 | 이 맥 gcloud | 고정 IP 예약(`byz-db-fwd-ip`) → `byz-db-fwd` 생성(플래그 위) → 방화벽 1줄 → IAP 조건식 1줄 확장(원본 조건식 파일 보존) · 자원 4개 원장 출력 · `lastStartTimestamp` 기록 → **14시간 격리 관찰 시작(재기동 금지)** | `maxRunDuration.seconds=50400`·`STOP`(비면 중단·되돌림) · 조건식 diff · `lastStartTimestamp+14h` ±10분에 자동 TERMINATED | VM·방화벽·예약 IP 삭제(HIL) · 조건식 원본 복원 |
| h1b | 이 맥 gcloud | 관찰 합격 뒤 `instances start` 1회(길 복구) | RUNNING · 새 `lastStartTimestamp` | — |
| h2 | mini | ① 살아 있는 `ssh -R` 종료 + 정본 h `FWD_DB=0` ② launchd `com.byz.iap-tunnel-db`(기존 `run-tunnel.sh byz-db-fwd 38309 38309` 재사용 · KeepAlive true · ThrottleInterval 30 · LaunchAgent 라 byz 로그인 세션 필요 = 기존 LLM·STT 터널과 같은 의존) + 감독 루프(§5 ⓑ 정의) ③ fail-closed: 이 맥 stop → mini 기존 세션·신규 연결 모두 실패 → start → 손 없이 `SELECT 1`(정지·기동 초 실측 → §5 배분 갱신) ④ 복구 시험: 유휴 1시간 · VM 재기동(정상 경로 ⓐ) · 터널 강제 종료(감독 경로 ⓑ) · mini 재부팅 — 각각 `SELECT 1` 복구 초 기록 · 손 0 ⑤ 러너 1회차(연결 풀 회복 확인) | 38309 소유 pid = mini gcloud · 시험 4종 + fail-closed 두 방향 · 복구 초 표 | plist 제거 · `FWD_DB` 복원 · 네이티브 서버 재기동으로 원래 연결 복원 |
| h3 | 이 맥 | launchd `com.byz.db-key-daily`(§5 · 잠금·op_id·T0 마감) · 1회 수동 · 이틀 로그 | 정상 예약 4회 통과(관찰 회차 제외) | plist 제거 |

h1~h3 로 골 축(시험 이관)의 남은 의존이 닫힌다.

## 7. 오빠 결정 (#3309 · 확정)
1. 열쇠 창 = 14시간 · 하루 2회 끄고 켜기(08:07 · 20:07). 2. 이 맥 자신의 DB 터널(`com.byz.loom-pg-tunnel`)은 그대로.

## 8. 확인 필요
- `create-with-container` + `--max-run-duration` + `STOP` 생성 통과 · `maxRunDuration.seconds=50400` 반환 · 첫날 자동 TERMINATED — h1. 안 되면 중단.
- 정지→TERMINATED 지연(≤60초) · 기동→첫 `SELECT 1`(≤60초) · TERMINATED 뒤 기존 세션 실패 — h2 ③.
- 실패 알림 슬랙 경로.

## 9. DA 이력
r1 HOLD(차단 4 · 중요 9) → r2 HOLD(r1 차단 4 전부 해소 확인 · 새 차단 2 는 **도커 카드** 소속) → **r3 APPROVE(조건부)**(`docs/multihost/da/da-20261026-134727-39193.out` · 차단 0 · 중요 7 · 경미 1). r3 조건 중 이 카드 소속 5건을 반영했다:

| r3 조건 | 반영 |
|---|---|
| 1 120초 예산이 실행 경로를 덮지 않음 | T0(단조 시계) 기준 **전체 마감 120초** 하나로 판정 · 각 단계 timeout 은 남은 예산 · 초과 복구는 별도 장애 절차(§5) |
| 2 감독 5회=150초 산술 · 두 복구 경로 | «검사 시작 간격 30초 · 연속 5회(첫 실패→다섯째 120초)» 정의 · 정상 경로 ⓐ / 감독 재시작 경로 ⓑ 분리 · h2 ④ 에서 각각 실측 · SDK 구현 원문은 미대조로 표기(§5) |
| 3 작업 ID 확보 계약 없음 | `--async` 로 작업 ID 를 먼저 받아 잠금에 저장 → `operations wait` → 상태 확인 뒤에만 start(§5) |
| 4 잠금 경과 시간 회수 | 잠금에 pid·시작·회차·op_id · 살아 있는 pid 면 종료 · 죽었으면 작업 DONE 확인 뒤 회수 · 자기 잠금만 해제(§5) |
| 5 첫날 만료 관찰 경계 | `lastStartTimestamp+14h` 실제 값 · 관찰 14시간 재기동 금지(h3 설치는 관찰 뒤) · h1b 로 복구 · 집계 분리(§3·§6) |

r3 조건 6(로컬 전환 절차)·7(curl 2xx)·8(원본 파일 잔재)은 도커 카드와 원본 파일에 반영. 다음 DA 는 h1~h3 스크립트(구현물) 단계에서.
