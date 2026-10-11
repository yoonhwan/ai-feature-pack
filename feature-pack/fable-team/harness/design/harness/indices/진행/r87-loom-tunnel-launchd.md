# 인덱스: LOOM DB 터널(38309 → 10.2.0.10:5432)을 세션 밖 launchd 상시 소유로 (R87 · v65 master#162 요청)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R87(v65 master#162 쪽지 #72941 · 하네스 이관 #72943 · master#27 발주 #72948)
- 상태: 대기
- 선행: 제안 Issue 등록 → 오빠 컨펌(①launchd 추천 · ②세션 밖 1회 · ③닫기 전 이관) → 이 머리 「- 제안서:」 를 #번호로 교체 + 구현 범위 확정 뒤 spawn · 그 전엔 spawn 0
- 제안서: #1213 (승인 — 오빠 ① launchd 상시 · 판정 913)
- 시험 입력: launchctl·gcloud·ssh·lsof 셸 스텁 · 임시 LaunchAgents 폴더 — 실 터널·실 launchd·실 DB 0
- 기준값: 10-10 실측 — 38309 LISTEN = ssh(pid 85243) ← gcloud compute ssh(83409) ← claude byz-v65-master-claude#162(7684) · 15:22 앞 세션(#160) 닫힘과 함께 터널 사망 → 게이트웨이 PoolTimeout · prefix_seed 실패 96건 · 다른 IAP 터널 4개(8000·8001·8100·38311)는 ppid 1 로 생존

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. v65 master#162 요청(R87).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
로컬 게이트웨이(8080 · v6-realtime-live)는 `LOOM_PG_TUNNEL_PORT=38309` 로 떠서 LOOM DB(10.2.0.10:5432 · 라이브 DB · 판정 161)에 터널로 붙는다. 이 터널은 `gcloud compute ssh byz-agents-gce-stt-tts-dev --zone=asia-northeast3-a --account=byz-local-dev@byz-agents-484214.iam.gserviceaccount.com --tunnel-through-iap -- -N -L 38309:10.2.0.10:5432` 로 열리는데, 마지막으로 연 세션(claude)의 자식이라 그 세션이 닫히면 같이 죽는다(10-10 15:22 · 10-03 에도 사망). `scripts/server/loom_dsn.sh` 는 LISTEN 이 없으면 실패만 하고 자동 개설하지 않는다. 제안 ①(추천): 같은 명령을 launchd LaunchAgent(RunAtLoad·KeepAlive·ThrottleInterval 30 · ssh 생존 확인 옵션 · 포트 실패 즉시 종료)가 상시 소유한다.

## 사전검증
- 소환: 컨펌 뒤 결정

## 조사 근거 (기준 = origin/main 178bde6c9c · 2026-10-10 실측)
- `scripts/server/loom_dsn.sh:89`~`:90` — 터널 LISTEN 검사·안내 문구(자동 개설 안 함).
- `scripts/harness-install/slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template:23`~`:25` — launchd 틀 선례(RunAtLoad·KeepAlive·ThrottleInterval 30).
- `.claude/archives/troubleshoot/20261003-restart-worker-c2c-entrypoint-loom-tunnel.md` — 같은 터널 10-03 사망·수동 재개 명령.
- 판정 799(죽은 터널 그 pid 만 + 같은 포트 서비스 계정 재개 표준승인) · 판정 909(일회성 터널 38309 금지).

## 구현 범위 (★컨펌 뒤 확정 — 아래는 제안 ① 기준 후보 · 지금 spawn 0★)
1. 새 틀 `scripts/harness-install/loom-tunnel/com.byz.loom-pg-tunnel.plist.template` — 위 명령 + ssh 옵션 `-o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes` · RunAtLoad·KeepAlive·ThrottleInterval 30 · 로그 `/tmp/byz-loom-pg-tunnel.log`.
2. 새 설치 도구 `scripts/harness-install/loom-tunnel/install.sh` — 머신별 설치 · 38309 를 쥔 기존 세션 터널이 «같은 명령»이면 그 pid 만 넘겨받기(판정 799 원칙) · 다른 프로세스면 REJECT(덮기 0) · `status`(launchctl print + LISTEN + `select 1`).
3. `scripts/server/loom_dsn.sh:90` 안내 문구: «gcloud compute ssh … 로 연다» → «launchd 터널 상태 확인: `bash scripts/harness-install/loom-tunnel/install.sh status` · 세션에서 열지 않는다(판정 909)» (검사 로직 변경 0).
3b. ★전환 순서(오빠 판정 913)★: gateway 다운 최소화 — 같은 포트(38309)는 두 터널이 동시에 못 잡으므로 «먼저 새 터널 준비(plist 설치·검증·launchctl 로드 직전까지) → 옛 pid 종료와 새 터널 기동을 연달아 → LISTEN+`select 1` 확인» 순서로 끊김을 수 초로 줄이고, 새 터널이 안 뜨면 같은 명령으로 옛 터널을 즉시 복구(롤백)한다. 옛 pid 를 먼저 정리하지 않는다(준비 전 종료 0). install.sh 에 이 순서·롤백을 넣고 시험에 포함.
4. 시험 `tests/harness/test_loom_tunnel_install.sh`(스텁): 같은 명령 세션 터널 → 넘겨받기 · 다른 프로세스가 38309 → REJECT · 설치 뒤 plist 내용 검사 · status 3칸.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 컨펌 뒤 확정. 지금 확정된 것: 증거 줄 형식 `세트: <40hex> · 시험: <명령 1개> rc=0 · 이슈: #<제안 Issue>`.

## 상태
- base_sha: 51aae071e2c3a8e40ddad37b09110a91fe12ed68 (spawn 2026-10-10)
대기 — 제안 Issue · 오빠 컨펌 대기(초안 · spawn 0)
- 슬랙: C0C6MJGRR89 1791614216.220439

## 결과
세트: 8709bfd54366778b6d7d063b948b877dc50cfc64 · 시험: bash tests/harness/test_loom_tunnel_install.sh rc=0 · 이슈: 0
- 2026-10-10 15:49 — 대기→진행 · 좌석 byz-harness-nano-r87-loom-tunnel-launchd#0
