「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스에 tailscale 연결, cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영」(오빠 2026-10-21)
「DB 경로: 읽기 전용 검증부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 러너)» 의 남은 의존 하나 = mini 서버가 DB 에 닿는 길(지금은 이 맥의 역방향 포워딩 38309 에 걸려 있음) + 서버 묶음을 어떻게 mini 로 보내 운영하나.

# 발주 — 만료 열쇠 + 콜리마 도커 세트 «같이 기획» (aifp-multihost-master-claude#5 → aifp-multihost-arch-claude#2 · 2026-10-26)

## 오빠 지시 원문 (순서대로)
1. 「보안상 이맥이 없으면 mini는 아무것도 할수없는게 맞지않을까? 이맥이 키가되는거고. 트레이드오프는 느리고 절차가 복잡한거겠지」
2. 「반대로 리소스 효율이나 테스트 분리에는 이동하는게 좋겠고. 그렇다면 만료를 넣고 이 맥에서 받아서 적용해 부팅해주고 이작업을 하루에 한번 해주면되도록 하면 어떨까? 구조적으로 가능한지. fable arch 기동. 나이스한 설계」
3. 「사실 이거 콜리마 도커 세트로 박싱해서 보내면 되는거 아닌가」
4. 「로컬도 마찬가지로 운영하고」 · 「같이 기획하라고 요청」
5. 「arch가 sonnet 이고 왜 서브에이저트로 띄우냐 우리는 패블팀인데」 → 이 좌석은 Fable 5.1 팀 좌석이다.

## 할 일
만료가 붙은 DB 자격을 «이 맥이 하루 1회 발급·적용·mini 서버 재기동» 하는 구상이 구조적으로 가능한지 판정하고, 가능하면 «서버 묶음(redis·gateway·worker·web)을 콜리마 도커 세트로 박싱해 mini 와 이 맥(로컬)이 같은 세트로 운영» 하는 설계까지 한 파일로 만든다.
산출물(이 한 파일만 Write): `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/DESIGN-db-expiring-credential-colima-20261026.md` — 맨 앞 3줄은 위 골 원문 3줄. 커밋·push 는 하지 않는다(master 집행).

## 꼭 답할 것
1. 가능/불가/조건부 판정과 이유 1단락.
2. 만료를 «어디에» 거는지 후보 비교(정답을 정해 두지 않았다 — 직접 따져라): ① IAP 권한 바인딩의 IAM 조건 시간 만료(request.time)를 이 맥이 매일 갱신 ② 서비스 계정 단기 토큰/임퍼소네이션 ③ Cloud SQL 쪽 단기 자격(IAM DB 인증·비밀번호 회전) ④ 그 밖에 네가 찾은 안. 각 안: 만료 강제 주체(mini 가 어겨도 막히나) · 이 맥이 꺼져 있으면 · 하루 발급 실패 시 안전한 쪽으로 닫히나 · 필요한 권한·변경(추가만인가) · 되돌림.
3. 이전 안(새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1)과의 관계 — 그 3가지 위에 얹히나, 포워더 없이도 되나.
4. «이 맥이 열쇠» 보안 성질을 얼마나 지키나(mini 침해 시 피해 범위·유효 시간) vs 현재(역방향 포워딩) 표.
5. 도커 세트: ① 도커 박싱이 DB 길 문제를 풀어 주나, 별개인가(정직하게) ② 리소스 효율(콜리마 VM 상주 메모리 vs 현재 네이티브 약 600MB)·테스트 분리 이득 비교표 ③ 이 맥과 mini 가 같은 compose 를 쓰되 달라지는 값(레인·포트·열쇠)을 한곳에서 바꾸는 법 ④ 열쇠(터널·포워더)를 세트 안 사이드카로 둘지, 시크릿/env 주입일지, 만료 시 세트가 스스로 닫히는지.
6. 하루 1회 절차: 오빠 손(`! bash /tmp/h<N>` 한 줄) 몇 번, 자동화 가능(이 맥 launchd)/불가, 실패 알림.
7. 도입 순서 최소안(오빠 손 h 몇 번)과 오빠가 정할 결정 1~2개(쉬운 말).

## 확인된 사실 (다시 조사하지 말고 필요하면 문서를 읽어라)
- 읽을 것(모두 /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/): `VERIFY-db-path-20261025.md` · `RESEARCH-a2-db-path-20261022.md` · `DESIGN-host-iap-tunnels-20261022.md` · `KEY-LEDGER-iap-tunnel-20261022.md` · `h-plans/`(h-mini-byz-server-run.sh 계열 = 지금의 서버 기동 방식).
- 이 맥 DB 길: `gcloud compute ssh byz-agents-gce-stt-tts-dev --tunnel-through-iap -- -N -L 38309:10.2.0.10:5432` (launchd `com.byz.loom-pg-tunnel` · SA byz-local-dev). DB = Cloud SQL byz-agents-postgres-prod 사설 10.2.0.10(실제 dev 런타임). 중계 VM = g2-standard-8 COS 10.0.0.9(GPU STT/TTS 서빙).
- mini: SA `byz-mini-tunnel` 은 roles/iap.tunnelResourceAccessor «조건부»(IP+포트 쌍 8000번대만 · 22·DB 포트 없음). 방화벽 byz-agents-allow-iap-dev = 35.235.240.0/20 → 22·8000·8100. LLM·STT 는 mini 자체 IAP 터널로 이미 닿는다. DB 만 이 맥 역방향 포워딩(38309). DB 계정·비밀번호(DSN)는 mini 가 이미 갖고 있다 — 이번 일은 «길».
- mini: arm64 · RAM 16GB · colima·docker·docker-compose 미설치(설치 = 원격 쓰기 = 오빠 h). 지금은 uv·npm·brew redis 네이티브 기동(서버 4프로세스 RSS 합 약 600MB · 여유 메모리 60%대).
- 이 맥: colima 가동 중(Virtualization.Framework · aarch64 · docker context colima).
- BYZ 리포 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/` 에 docker-compose.yml(redis·gateway·worker 만 · web 없음)과 docker/{gateway,worker,web}.Dockerfile 이 있다. 읽기만 — BYZ 소유 파일 편집 0. aifp 쪽 compose 는 docs/multihost 아래 별도 파일로 «제안».
- 시험 서버 포트: 38301~38399(redis 38311 · gateway 38312 · worker 38313 · web 38314). 이 맥의 기본 포트 점유 금지.
- 도커 밖에 남아야 하는 것: 시험용 Chrome(CDP 9333·마이크 권한) · BlackHole 루프백 · tts-say · 러너(realtime_multi_e2e) — 컨테이너가 macOS 오디오·화면을 못 건드린다. «서버 묶음만 박싱, 러너·브라우저는 호스트 네이티브» 구분을 판정하라.
- 지금 서버 코드는 mini 가 rsync 로 받아 uv sync·next build(h-mini-byz-server-run.sh) — 이미지 빌드·배포(레지스트리 없이 docker save/load 로 보낼지, mini 에서 빌드할지)와 비교.
- 이 맥↔mini ssh 는 tailscale 로 된다(간헐적으로 DERP 중계 · `-o ConnectTimeout=20`). gcloud 계정은 `developer.ts@byourz.com`(owner) 고정.

## 제약
- 조사는 읽기 전용만(gcloud 읽기 명령·ssh mini 읽기 명령 가능 · 쓰기·원격 변경·키 값 출력 0). 원격 쓰기는 오빠 `! bash /tmp/h<N>` 로만.
- 모르는 것은 «[확인 필요: …]» 로 남기고 지어내지 않는다. 약어(A/B/C·4축 등)로 부르지 않는다 — 안은 이름으로. 한국어.
- 하위 좌석이라 AskUserQuestion 금지 — 오빠가 정할 것은 설계 파일 끝 «결정» 칸에 적고 master 에 mbox 로 «결론 1줄 · 파일 경로» 만 보낸다.
- 보낼 곳: `bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh` 가 아니라 aifp 쪽 `FT_MBOX_DIR=/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh send aifp-multihost-master-claude#5 aifp-multihost-arch-claude#2 "<본문>"` (본문에 백틱·$() 금지).
