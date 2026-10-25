「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」(오빠 2026-10-21) · 「이대로 끝이라고?」(오빠 2026-10-22 — 기획 마감은 잘못, 골 달성까지 계속)
골의 어느 축: «시험 이관(러너 1회차 → 성공 줄 확인)» 과 «hermes 업데이트 지원(마무리 확인)» — 정본 표 = docs/multihost/BRIEF-phase2-operate-20261022.md 의 골 표.

# aifp-multihost-master-claude#3 → #4 인계 (2026-10-24 · 컨텍스트 551k 증류)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 가지 docs/multihost-plan-20261021 (main 직접 커밋 0 · 병합은 오빠 `!` 한 줄 · 마지막 커밋은 git log). 너는 aifp-multihost-master-claude#4 (멀티호스트 팀장). 상위 aifp-worker-master-claude#4 좌석은 **없음**(재개 기록 0) — 오빠께 직접 보고(planner·desk 중계 0 · BYZ planner#123 회신 #156622: «aifp 그룹 h 줄은 aifp 팀장이 오빠께 직접»).

## 0. 첫 일 순서
1. 골 대조 보고(위 골 표 매핑) → 오빠께 직접. 쪽지는 보낼 곳이 없으면 생략(상위 없음). 체크 크론 새로 걸 것(세션 종속이라 안 옮겨짐 — 전임 `ab88919a` 는 이 세션과 같이 사라짐): CronCreate 30분 «무음 모드» = 쪽지 2곳 recv · mini CDP 9333 · git status · 변화 없으면 한 줄 «변화 없음 HH:MM» 만(오빠 화면이 틱 보고로 덮여 «볼게 없다» 문책받음 — 반복 보고 금지).
2. **다음 오빠 한 줄 = `! bash /tmp/h313`** (러너 1회차, NEW=1 진입점 h-mini-e2e-round1-new.sh). 오빠께 이미 안내함 — 아직 안 쳤으면 재안내. 결과의 성공 줄 `✅ host 단일 버블 (delta=1, polished Nchars)` 확인이 이 골 축의 «닫는 증거».
3. h 번호는 **재사용된다**(오빠 h39·h40·h64·h68 이 다른 계획으로 덮여 내 계획이 사라진 사고) — 내 계획 등록·확인은 항상 `bash /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-hil.sh --add <계획 파일> --notify 'aifp-multihost-master-claude#4' --notify-comm /Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm` 로 새 번호를 받고, 쪽지·.ran 은 새 번호로만 대조.

## 1. 골 표 현재 상태 (2026-10-24 밤)
| 요소 | 상태 |
|---|---|
| Tailscale 두 곳 · mini/OCI CLI 운용 · OCI headroom·cliproxy·pi · tmm 접속 | ✅ |
| hermes — OCI | ✅ v0.22.4 |
| hermes — mini | ✅ h216 rc=0 (v0.22.5) · ✅ 슬랙 응답 확인 2026-10-25: #talk-aina 에서 @aina 가 «BYZs-Mac-mini.local · user byz · Darwin 25.5.0 arm64» 로 답함(오빠가 붙여 주신 답 원문) |
| hermes — 이 맥 | ✅ h217 (rc=5 는 증거 단계 코드 버그 — 브랜치 local/cliproxy-loopback-v2@906227f14f 유지·두 게이트웨이 running · 스크립트 수정 커밋) |
| mini 자체 IAP 터널(LLM·STT, 이 맥 의존 제거) | ✅ h101 rc=0 + h215 rc=0 (8000·8001 자체 터널 · STT 동등성 sha 9dcd4d56ced08621) |
| 옛 키 폐기 | ✅ h297 rc=0 (남은 키 mini e07046b7… · OCI d9db6b34…) |
| 시험 이관 — mini 서버 | ✅ h321 rc=0: BYZ main **c34fc47f24c89e16c60cbe94bb54e45445aa1a31**(오빠 «v65 가 최신» — 4c876d7f 는 473커밋 뒤처졌음) · /v5 라우터 장착(POST /v5/sessions/init 404→422) · 웹 = next dev + mock host + E2E 토큰 |
| 시험 이관 — mini 시험용 Chrome | ✅ h315 rc=0 (open 으로 launchd 부모 · 9333) · 마이크 권한 = h317 세션 권한(Chrome 다시 띄우면 사라짐) + 오빠가 팝업 «허용» 눌러 줌 |
| 시험 이관 — 러너 1회차 | 🟡 h313 5번 실패 후 6번째 대기: ①프로덕션 웹(mock host 우회 불가) ②웹에 NEXT_PUBLIC_BYZ_E2E_JWT_SECRET 없음→qr/ensure 401 ③녹음 안 켜짐(마이크 허용) ④host_empty ⑤chunk_post_failed audio_event 404(V5_BACKEND_ENABLED 미주입) — 전부 원인 확정·수정 완료 · 이번이 새 코드 첫 회차 |
| DB 경로(mini → dev DB 10.2.0.10) | ⏳ 아직 이 맥 역방향 포워딩 38309 의존 — 대안 «VM DB 포워더 1개 + IAP 포트 한정» 은 VM 변경 1회라 오빠 승인 필요(RESEARCH-a2-db-path-20261022.md) |
| 하네스 카드 r673~r678 | ⏳ 하네스 정지 중 |

## 2. 함정 (오늘 실측)
- **DRY 처리 없던 h 가 실제로 돌아 버림**: h-mini-e2e-round1-run.sh 에 DRY 분기가 없어 `DRY=1` 이 무시되고 러너가 실제 실행됨(22:10 · 마이크 press 없이 실패라 피해 없음) → preflight 뒤 `exit 0` 분기 추가 커밋. 새 h 를 만들면 DRY 분기부터.
- ft-hil `--add` 가드: ①`printf '%s' "$SECRET" | …` 같은 비밀 변수 인자 REJECT → 600 임시 파일 + `< "$ENVF"`(h-mini-web-dev.sh 참고) ②**BYZ .env 를 grep 하는 명령은 훅이 REJECT** → 값은 `V="$(…)"` 변수에만·`${#V}`/`case` 로 판정·echo 금지(오탐도 같음 — 시험 코드에 `KEYS` 같은 이름만 있어도 걸림).
- mini: ssh 비대화형 PATH 접두 필수 · `ps eww` 로는 next 자식 환경이 안 보일 때가 있음(mock 플래그는 보였음) · 7초 룰(분리 실행+폴링은 허용).
- 마이크: mac 팝업이 떠 있는 동안은 녹음이 소리를 못 받음(오빠가 «허용») · CDP Browser.grantPermissions(h317)는 세션 권한 · 클릭·DOM·Redis 주입 0(하드 룰 5·11).
- 서버 h(h-mini-byz-server.sh): KEYS 화이트리스트에 이름이 없으면 mini 로 안 넘어감(V5_BACKEND_ENABLED 가 그 사례) · `FWD_EXTRA=""`(8000/8001 은 자체 IAP 터널이 소유) — run.sh 에 고정됨 · 코드(sha)가 바뀌면 설치·빌드 몇 분(restart-dev 가 45초마다 최대 10회 이어서 확인).
- 보류한 보정: **h320 = mini 8081→8080 worker 상태 중계**(gateway pulse health 가 localhost:8081 을 보는데 worker 는 8080 — 503 worker_unreachable). 이번 회차에서 STT 결과가 또 비면 그때 쓴다(근본은 worker 에 PORT=8081 또는 gateway 에 WORKER_HEALTH_URL — 서버 재시작 필요).
- gcloud: 오빠 계정은 **developer.ts@byourz.com** 고정(yoonhwan.ko 아님). h-iap-old-keys-delete 로 확인 끝.
- 상위 aifp-worker-master-claude#4 좌석 없음 · planner = byz-planner-master-claude#123(옛 #120 은퇴) · 쪽지 머리는 [결정]·[HIL]·[긴급] 만 허용.
- 오빠 반응: 틱 보고가 길면 화면이 덮임 → 변화 없으면 한 줄. 마감 질문 금지(골 표 🟡·⏳ 가 남아 있는 동안).

## 3. 오빠 손 대기
- `! bash /tmp/h313` (러너 1회차 · 소리 한 번 남).
- mini 슬랙 봇이 답하는지 1회 확인(h216 뒤).
- (별건) DB 경로 VM 포워더 승인 — 러너 성공 뒤에 여쭐 것.

## 4. 하지 말 것
원격 쓰기는 오빠 `! bash /tmp/h<N>` 로만 · 하네스 소유 파일 편집 0 · main 직접 커밋 0 · 마감 질문 금지 · 임의 Redis/DOM 주입 0 · 약어로 골 부르기 0 · 삭제·덮어쓰기(브랜치 -D·키 폐기)는 HIL.

## 5. 인계 직후 발견 (2026-10-24 23:50 · h313 6번째 = 새 코드 첫 회차 결과)
- 결과: 러너 rc=2 · host_empty (STT 결과 빔). **앞 5가지 실패는 해소됨**: 호스트 입장·QR·게스트 입장·녹음 시작·오디오 조각 전송(`chunk_post seq=1,2` 성공)까지 통과.
- 새 원인(확정): mini worker 가 조각을 받아(`V6-PULSE-CONSUMER consume_start`) 곧바로 **버림** — `[V6-B:ingress:DEAD_LETTERED] reason=backend_not_configured` + 이벤트 `stt_backend_unavailable`(notice) + terminal error. 코드 = `worker/graph/speech/pulse/v6/drain_contiguous.py:82` `FatalHoleReason.BACKEND_NOT_CONFIGURED` — 주석: «게이트 차단(provider 미호출)». 즉 STT provider 를 부르기 전 «게이트»가 막음.
- 다음 첫 일(읽기 전용): 그 게이트가 어떤 설정을 보는지(`git grep` 새 main c34fc47f · worker/graph/speech/pulse/v6/lifecycle.py·drain 호출부·`worker/services/stt`)를 찾아, mini worker 에 그 env 이름이 있는지(이름만 · 값 출력 0 · BYZ .env 를 grep 하면 훅 REJECT — 변수에만 받고 길이/존재로 판정) 이 맥 로컬 worker 기동 세트(`scripts/server/ready-check.sh` 의 WORKER_ENV_SPEC·`server.sh`)와 대조. 유력 가설: 새 main 이 요구하는 env 이름이 늘었는데 서버 h 의 KEYS 화이트리스트(h-mini-byz-server.sh)에 없음(V5_BACKEND_ENABLED 와 같은 유형).
- 고치면 `h-mini-server-restart-dev.sh` 로 한 줄 재시작(정지→기동→웹 dev→v5 증거) 뒤 `! bash /tmp/h313`.
- 보류: h320(8081→8080 worker 상태 중계) — gateway pulse health 는 여전히 503(worker 는 8080). STT 가 정상이 된 뒤에도 FE 가 막으면 그때.
- 사실 참고: gpu status 는 COLD(auto_warmup=false)인데 STT 터널 8001 /health 는 200·pool.stt=vllm. STT 서비스 자체는 살아 있음.
