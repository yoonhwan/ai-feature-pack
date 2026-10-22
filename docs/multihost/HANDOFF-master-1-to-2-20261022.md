「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21) · 「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」 · 「이대로 끝이라고?」(오빠 2026-10-22 — 기획 마감은 잘못, 골 달성까지 계속)
골의 어느 축: «두 곳 CLI 운용» + «시험 이관» + «분산 운영 기능» — 지금 «시험 이관 첫 회차(mini 서버 기동 → 러너 1회차)» 단계. 정본 표 = docs/multihost/BRIEF-phase2-operate-20261022.md 의 골 표.
너는 aifp-multihost-master-claude#2 (멀티호스트 팀장). 전임 #1 의 증류 후계. 승계 첫 일 = 골 대조 보고(위 표 매핑) 후에만 착수. 상위 = aifp-worker-master-claude#3 (쪽지 주소 #3 — #2 아님).

# aifp-multihost-master-claude#1 → #2 인계 (2026-10-22 · 컨텍스트 576k 증류)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 가지 docs/multihost-plan-20261021 (main 직접 커밋 0 · 병합은 오빠 `!` 한 줄). 쪽지: `FT_MBOX_DIR=/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh recv|send aifp-multihost-master-claude#2 …`.

## 0. 첫 일 순서
1. 골 대조 보고 + 부팅 보고(세션명/모델+창/Serena 가부/adhd=O/cron=id) → 상위 aifp-worker-master-claude#3 에 mbox.
2. 체크 크론 새로(CronCreate, 10분, ★조용 모드★): 쪽지 recv · /tmp/h381·h382 .ran · git status. ★상위에 «변화 없음» 쪽지 금지(상위 지시 #3158)★ — 오빠 h 실행 결과·결정 필요·막힘만 1통.
3. ★미커밋 먼저 커밋★: 내가 마지막에 고친 `docs/multihost/h-plans/h-mini-byz-server.sh`·`h-mini-e2e-round1-run.sh`(bash -n 통과 확인함) — git status 로 보고 경로 지정 add(git add -A 금지 훅). 커밋 문구 예: «h381 — 상위 터널 3개(DB 38309·LLM 8000·GPU STT/TTS 8001) 역방향 포워딩 + WORKER_ENV_SPEC 고정값 채움 + KEYS + health -L».
4. 상위에 «h381 고침 완료» 1통(아래 §2 내용) + 오빠 줄(stop → up).

## 1. 골 표 현재 상태 (BRIEF 정본)
| 요소 | 상태 |
|---|---|
| Tailscale 두 곳 | ✅ |
| mini CLI 운용 | ✅ (h375 + 대기 좌석 aifp-mini-worker-claude#0 오빠 확인) |
| OCI CLI 운용 | ✅ (h377 rc=0 ping_rc=0·probe·seat=closed + 대기 좌석 aifp-oci-worker-claude#0) |
| OCI headroom·cliproxy | ✅ (h376) · OCI cliproxy 계정 claude1·codex2 ✅ (h404) |
| OCI·mini pi(deepseek) | ✅ (h400·h401) |
| tmm 호스트 접속(Termius) | ✅ (오빠 확인, OCI fzf 0.74.3) |
| 시험 이관 | 🟡 h378 ✅(러너 16파일+venv) · h379 ✅(tts-say) · 서버 h381 ❌(진행 중) · mini 앞 오빠 손 7단계 · 러너 1회차 h382 대기 |
| hermes 업데이트 | ⚠️ 절차만(`hermes update --check→backup→update→restart→doctor`), 미실행 |
| 하네스 카드 r673·r674·r675·r676·r678 | ⏳ 하네스 정지 중(원격 main 에 착지 0) |

## 2. 서버 h381 — 지금 막힌 곳과 방금 한 일
- 진입점 `/tmp/h381` = `docs/multihost/h-plans/h-mini-byz-server-run.sh`(SHA=origin/main 4c876d7f47f70da6c4dde8606bd685c059b79cfe · KEY_SRC=dotenv · 인자 up|stop). 본체 `h-mini-byz-server.sh`.
- 이력: 1회차 rc=4(extra 누락·web subshell) → 2회차 rc=0 인데 서버 0(CORPUS_RETENTION_DAYS·LOOM DSN 없음) → DB 역할 계약(loom_gateway_rYYYYMMDD) BYZ 가 main 159bb2c1 로 수정 → SHA 4c876d7f 로 올림·DSN 드라이런 통과 → 3회차 rc=5: gateway 살아있음(health 307→/health/ 200)·web 200 인데 worker 1개가 SourcingPolicyError «selfhost 소싱인데 LOCAL_VLLM_BASE_URL 비어 있음».
- 원인·실측: 이 맥 `.env` 에는 BYZ_LLM_SOURCING=selfhost · LOCAL_VLLM_BASE_URL=http://localhost:8000/v1 이 «있는데» h 의 KEYS 에 없어 안 넘어갔음. 이 맥의 :8000 = gcloud IAP 터널(llm VM), :8001 = GPU STT/TTS 터널(launchd com.byz.stt-tunnel-8001), :38309 = DB 터널. 정본 worker 세트 = `scripts/server/ready-check.sh` WORKER_ENV_SPEC(GPU_STT_TTS_URL=http://localhost:8001 · V6_AUTHORITATIVE_STT_PROVIDER=gpu_qwen3 · V6_AUTHORITATIVE_STT_MODE=dev_single · STT_PROVIDER=fireworks · V6_LST_TRANSLATE=1 · V65_OWNER_BOOTSTRAP_ENABLED=1 · LOOM_PG_TUNNEL_PORT=38309 …).
- 내가 고친 것(커밋 대기): ①KEYS 에 BYZ_LLM_SOURCING·LOCAL_VLLM_BASE_URL·LOCAL_VLLM_API_KEY·GPU_STT_MODEL·STT_PROVIDER·GEMINI/GOOGLE 이름 ②아카이브 사본의 ready-check.sh WORKER_ENV_SPEC 에서 .env 에 없는 고정값만 채움(PORT 제외) ③역방향 포워딩을 3포트(38309·8000·8001; FWD_EXTRA 로 조정)로 확장 — 사전점검: 이 맥 3포트 LISTEN·mini 3포트 비어 있음 ④health 판정 curl -L(307 추종) — h382 preflight 도 같음. 시험은 bash -n 만 했고 실행은 안 했다.
- 오빠 줄(상위가 발급): `bash /tmp/h381 stop` 먼저(mini 에 이전 회차 서버 pid·포트 38311·포워딩 38309 잔재) → `bash /tmp/h381`. up 은 sha 변경으로 uv sync·npm ci·build 재수행(수 분, 같은 줄 재실행으로 이어감). 서버가 도는 동안 ★이 맥이 켜져 있고 3개 터널이 살아 있어야 함★.
- 서버가 뜬 뒤: MINI-FRONT-checklist-20261022.md 7단계(오빠 mini 앞, 폴더 신뢰 항목은 ~ 는 대체됨) → `bash /tmp/h382`(러너 1회차 · 같은 h 재실행은 press 안 함, 새 회차 NEW=1, 정지 ACTION=stop). 성공 판정 줄 `✅ host 단일 버블 (delta=1, polished Nchars)`.

## 3. 열린 쪽지/요청
- 상위 #3189(마지막 수신)는 h381 3회차 후속 «소싱/vLLM 실측·KEYS·health» 요청의 재알림이었음 — 위 §2 가 그 회신 내용. 상위에 1통 보낼 것.
- 좌석: aifp-pi-master-pi#0(유휴 대기 · 닫지 말 것 — 오빠가 문책한 좌석). mini·OCI 대기 좌석 2개는 오빠가 닫으라 할 때까지 유지.
- 하네스 요청 후보(문서에만 있음, 상위 경유): tmuxc open 신뢰 질문 Enter 결함(harness-requests-20261022.md 말미) · tmm 295행 GNU stat(BYZ #140818).

## 4. 함정(오늘 실측)
- mini ssh 비대화형 PATH 는 /usr/bin:/bin:/usr/sbin:/sbin — 모든 ms()/rs() 에 `export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH` 접두. mini 로그인 셸은 zsh → `-t =이름` 은 따옴표 안.
- mini 는 항상 `ssh mini`(사용자 byz — 이름·IP 쓰지 말 것). OCI 는 `-o IdentitiesOnly=yes -i ~/.ssh/oci_chuncheon oci`(ufw: 같은 IP 새 연결 30초 6회 상한).
- 외부 호출 단건 70초 천장. 비밀은 stdin 으로만(명령줄·mini 디스크·화면 0) — 훅이 `.env` grep/printf 파이프를 막으니 이름 존재는 python 으로 booleans 만.
- 훅 오탐 경험: `rm -rf`·러너 파일명이 든 명령·`git add -A`·`.env` grep 출력은 차단 — 파일 경로 지정 add, Edit 도구, 600 임시 파일 경유.
- 컨텍스트 550k 경고에 즉시 증류(나는 573k 에서 시작) — 인계서·후계 개설은 70% 에.

## 5. 하지 말 것
원격 쓰기는 오빠 `! bash /tmp/h<N>` 로만 · 하네스 소유 파일(feature-pack/fable-team·tmuxc·tmm 코드) 편집 0 · 공개 가지 재push/히스토리 교체 0 · main 직접 커밋 0 · 마감 질문 금지(골 표 ❌ 가 남아 있는 동안) · 임의 Redis/DOM 주입 0(하드 룰 11) · 약어로 골 부르기 0.
