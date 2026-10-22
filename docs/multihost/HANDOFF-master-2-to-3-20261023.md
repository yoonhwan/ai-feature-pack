「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21) · 「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」 · 「이대로 끝이라고?」(오빠 2026-10-22 — 기획 마감은 잘못, 골 달성까지 계속)
골의 어느 축: «두 곳 CLI 운용» + «시험 이관» + «분산 운영 기능» + «hermes 업데이트 지원» — 지금 «시험 이관(mini 자체 IAP 터널로 이 맥 의존 걷어내기 → 러너 1회차)» 과 «hermes 업데이트(OCI ✅ · mini·이 맥 대기)» 단계. 정본 표 = docs/multihost/BRIEF-phase2-operate-20261022.md 의 골 표.
너는 aifp-multihost-master-claude#3 (멀티호스트 팀장). 전임 #2 의 증류 후계. 승계 첫 일 = 골 대조 보고(위 표 매핑) 후에만 착수. 상위 = aifp-worker-master-claude#4 (쪽지 주소 #4 — #3 아님).

# aifp-multihost-master-claude#2 → #3 인계 (2026-10-23 · 컨텍스트 564k 증류)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 가지 docs/multihost-plan-20261021 (main 직접 커밋 0 · 병합은 오빠 `!` 한 줄 · 마지막 커밋은 git log 로).
쪽지(2곳): ①`FT_MBOX_DIR=/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh recv|send aifp-multihost-master-claude#3 …` ②BYZ 쪽 `bash /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh recv aifp-multihost-master-claude#3` (BYZ planner#109 가 가끔 보냄).

## 0. 첫 일 순서
1. 골 대조 보고 + 부팅 보고(세션명/모델+창/code-intel `ci` 가부(Serena 은퇴)/adhd=O/cron=id) → 상위 aifp-worker-master-claude#4 에 mbox.
2. 체크 크론 새로(CronCreate 10분 조용 모드): 쪽지 2곳 recv · /tmp/h39·h40·h64·h68·h19 .ran · git status. ★상위에 «변화 없음» 쪽지 금지★ — 오빠 h 결과·결정 필요·막힘만 1통. (전임 크론 51ea5b38 은 세션 종속이라 옮겨지지 않음.)
3. git status 확인(전임은 모두 커밋함) → BRIEF 골 표 갱신(아래 §1 반영 · 마지막 갱신은 재부팅 지점 줄에 머물러 있음).
4. 오빠 h 대기 목록(§2)을 매 틱 .ran 으로 대조. 오빠 화면에만 출력이 있는 건 상위가 받아 줌.

## 1. 골 표 현재 상태
| 요소 | 상태 |
|---|---|
| Tailscale 두 곳 · mini/OCI CLI 운용 · OCI headroom·cliproxy·pi · tmm 접속 | ✅ |
| hermes 업데이트 — OCI | ✅ v0.15.1→v0.22.4(@81a55437) h5(rc=4 표시는 ssh 채널 버그 — 실제 성공) + h8 로 em-dash-filter 플러그인·AGENTS.md 규칙 복원 rc=0 |
| 시험 이관 — mini 서버 | ✅ h2 rc=0 (서버 4개 · gateway 38312·web 38314 · sha 4c876d7f · 포워딩 h18 로 재개설 38309·8000←18703·8001) |
| 시험 이관 — mini 자체 IAP 터널(이 맥 의존 제거) | 🟡 h7 ✅(새 SA 2개·IAP 조건부·키 배치·시험 T1~T4 통과) · **h40 = h-B 대기** → h-B2 |
| 시험 이관 — 러너 1회차 | 🟡 h19 첫 실행 rc=2: preflight 가 CDP 9333(시험용 Chrome)만 «없음» 으로 잡음 → 오빠 mini 앞 체크리스트 4번 후 재실행 |
| hermes — mini | 🟡 h64 대기(계획 h-mini-hermes-update.sh · DRY 3회 rc=0) |
| hermes — 이 맥 | 🟡 h68 대기(h-mac-hermes-swap.sh · 사본 브랜치로 교체 · «한가한 창» 자동 대기 25분) |
| DB 경로(mini → dev DB 10.2.0.10) | ⏳ 아직 이 맥 역방향 포워딩 38309 의존. A2(ssh 권한 구조 문제) = RESEARCH-a2-db-path-20261022.md 참고, 대안 «VM 에 DB 포워더 1개 + IAP destination.port 한정(ssh 불필요)» 가 유력 — VM 변경 1회라 오빠 승인 필요 |
| 하네스 카드 r673~r678 | ⏳ 하네스 정지 중 |

## 2. 오빠 `h` 대기 (번호는 오빠 화면 기준 · 발급은 상위가 등록)
- **h39** = h-iap-old-keys-delete.sh — 옛 키 2개(mini 42ec5f53… · oci 36bea09d…)만 폐기(사용 중 키 e07046b7…·d9db6b34… 가 호스트 sa.json 과 같을 때만). 키 장부 `docs/multihost/KEY-LEDGER-iap-tunnel-20261022.md`.
- **h40** = h-mini-iap-tunnels.sh (h-B) — mini 에 gcloud 587.0.0(sha256 088d923d…) 사용자 설치 → byz-mini-tunnel 활성화 → launchd 2개(시험 포트 18703 llm · 18708 stt) → 증거+STT 동등성. rc=0 이 나오면 **h-B2**(h-mini-iap-swap.sh · 커밋 c70dbe84: 8000/8001 포트 주인을 자체 터널로 교체, 서버 env·재시작 0, DB 38309 만 이 맥 포워딩 남김) DRY 재확인 → «발급 전 상위에 1통».
- **h64** = h-mini-hermes-update.sh · **h68** = h-mac-hermes-swap.sh (지금 e73b3c86 이후 판. 사본 ~/.hermes-port/hermes-agent-port 브랜치 local/cliproxy-loopback-v2@906227f14f).
- **h19** = h-mini-e2e-round1-run.sh (NEW=1 로 새 회차 · 같은 h 재실행은 press 안 함 · 정지 ACTION=stop). 성공 줄 `✅ host 단일 버블 (delta=1, polished Nchars)`.
- 이미 끝: h2 h7 h8 h18 · 끝난 뒤 정리: BRIEF·KEY-LEDGER 갱신.

## 3. 이 맥 hermes 재이식 사실(오빠 결정 2026-10-23)
기본 update 는 main 으로 갈아타 직접 만든 loopback 패치가 사라지고, update_in_place 는 3파일 병합 충돌. 오빠 결정 «재이식 GO · 침묵 접두사는 동작 같을 때만 플러그인» → 플러그인은 동등 아님으로 판정(훅이 어댑터 게이팅 뒤 · «@봇 — x» 엣지 · 전 플랫폼) → 32줄 그대로 이식. 나노(pi) 2회 투입·종료 확인(pi 0). 나노 보고서 `~/.hermes-port/REPORT.md`·`REPORT2.md`(이 폴더는 repo 밖). 시험 117 passed(내가 재실행). h68 의 진행 중 판정: gateway_state.json active_agents 는 cron 시작·끝에 안 갱신돼 낡음 → agent.log(Running job ↔ completed/failed 짝)+최근 대화 활동+jobs.json 다음 cron ≥10분.

## 4. 함정(오늘 실측)
- **훅 오탐**: 명령 본문에 `rm`·`-rf`·`git add -A`·키 삭제 명령 글자·heredoc 안 파괴 명령 글자가 있으면 차단 → 파일은 Write/Edit 도구로, 스크립트 안 롤백 명령은 «출력만» 하게. ft-hil.sh 로 만든 /tmp/h<N> 는 자율 파일 읽기 훅에 걸림(h4 사례).
- mini ssh 비대화형 PATH 에 /opt/homebrew/bin·~/.local/bin 접두 필수 · mini 에는 `setsid`·`pgrep -c`·GNU stat 없음 · 분리 실행은 `nohup bash -c '…' >log 2>&1 </dev/null &` · 외부 호출 1회 ≤ 7초(+기동 고정비) · 분리 실행+폴링은 7초 룰 위반 아님(상위 확인).
- bash 가 `$변수` 바로 뒤 한글·화살표(→·…)를 변수명으로 읽어 unbound variable → 반드시 `${변수}`. (스크립트마다 한 번씩 일괄 치환하는 python 한 줄을 써 왔다.)
- 이 맥 gcloud «활성 계정» 이 다른 세션 때문에 byz-local-dev(권한 약함)로 바뀐 적 있음 → 관리 작업은 ADMIN=developer.ts@byourz.com 명시. launchd 터널은 --account 명시라 영향 없음.
- 조건부 IAM 은 반영에 최대 ~1분 → 시험은 재시도(6회·20초). IAP 허용 밖 연결은 SDK 가 compute.instances.get 진단 조회 오류로 보임(대조군 T1~T3 통과 시 «거부» 로 인정하도록 해 둠).
- 이 맥 mini 포워딩 ssh(`-R`) 는 nohup 이라 또 죽을 수 있음(근본 = h-B2). 죽으면 h18 재실행(h-mini-byz-fwd-run.sh). FWD_EXTRA 는 빈값 허용(`${FWD_EXTRA-…}`).
- 10.2.0.10 = byz-agents-postgres-prod «이름만 prod», 실제 dev 런타임 DB(오빠 결정 «그대로 둠»).
- 컨텍스트 550k 경고에 즉시 증류(전임은 564k). 후계 도달 전엔 새 일 수락 0(게이트).

## 5. 열린 요청·주의
- 하네스 요청 후보(상위 경유): tmuxc open 신뢰 질문 Enter 결함(harness-requests-20261022.md 말미) · tmm 295행 GNU stat(BYZ #140818).
- 키 교체 권장 2027-01-20(KEY-LEDGER). 옛 키 폐기는 삭제 = 오빠 승인(h39).
- 보고 방침: 오빠께 직접(BYZ desk·planner 중계 0 · BYZ planner#109 #141434). h 발급 전 상위에 1통(점검 후 상위가 등록·오빠께 올림). 나노는 pi(deepseek flash) 쓰고 바로 닫기(하드 룰 14 — 막힌 문제는 재설계+리서치 나노). 코드 탐색은 `ci`(grep 은 문자열·설정 확인에만 · 하드 룰 16).
- 좌석: aifp-pi-master-pi#0(닫지 말 것) · aifp-worker-master-claude#4(상위) · mini·OCI 대기 좌석 2개(aifp-mini-worker-claude#0·aifp-oci-worker-claude#0) 오빠가 닫으라 할 때까지.

## 6. 하지 말 것
원격 쓰기는 오빠 `! bash /tmp/h<N>` 로만 · 하네스 소유 파일(feature-pack/fable-team·tmuxc·tmm 코드) 편집 0 · main 직접 커밋 0 · 마감 질문 금지(골 표 ❌/🟡 가 남아 있는 동안) · 임의 Redis/DOM 주입 0(하드 룰 11) · 약어로 골 부르기 0 · 삭제·덮어쓰기(브랜치 -D·stash drop·키 폐기)는 HIL.
