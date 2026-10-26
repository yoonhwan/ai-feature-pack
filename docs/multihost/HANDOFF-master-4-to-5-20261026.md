「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」(오빠 2026-10-21) · 「이대로 끝이라고?」(오빠 2026-10-22 — 골 달성까지 계속) · 「이슈팀 전체 이동하지말고. 이슈팀 팀장이 나노워커를 mini에 열어서 위성으로 ssh로 열어 사용하고 닫는 실험부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 러너)» 의 말풍선 0 원인 가르기 · «나노 분산(위성 나노 도구)» r902 · OCI hermes 모델 전환 — 정본 골 표 = HANDOFF-master-3-to-4-20261024.md §1 + 아래 §1.

# aifp-multihost-master-claude#4 → #5 인계 (2026-10-26 · 컨텍스트 576k 증류)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 가지 docs/multihost-plan-20261021 (main 직접 커밋 0 · 병합은 오빠 `!` 한 줄) · 마지막 커밋 `git log -1`. 너는 aifp-multihost-master-claude#5 (멀티호스트 팀장). 오빠께 직접 보고(상위 좌석 없음). 앞 인계서 `HANDOFF-master-3-to-4-20261024.md` 의 함정 §2 는 그대로 유효.

## 0. 첫 일 순서
1. 골 대조 보고(위 골 3줄 ↔ §1 표) → 오빠께. 체크 크론 새로 건다(세션 종속·#4 의 `270ca3a7` 은 #4 와 함께 사라짐): CronCreate `17,47 * * * *` «무음 모드» = 쪽지 2곳 recv(aifp: `FT_MBOX_DIR=/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh recv aifp-multihost-master-claude#5` · BYZ: `bash /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh recv aifp-multihost-master-claude#5`) · mini CDP 9333 · git status. 변화 없으면 한 줄만. ★#4 가 보낸 쪽지의 회신처는 «#4» 로 적혀 있다 — 오는 회신이 #4 앞이면 #5 에 보이는지 `ft-harness-info.sh seats`/recv 로 확인.★
2. 오빠가 아직 안 친 `!` 줄 2개(§2). 먼저 `/tmp/h191` 진행 여부 확인(`ls /tmp/h191.ran`).
3. h 번호는 재사용된다(앞 인계서 §0-3). `/tmp/h<N>` 이 없으면 `ft-hil.sh --add <계획> --notify 'aifp-multihost-master-claude#5' --notify-comm /Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm` 로 새 번호.
4. ★내 컨텍스트는 증류 임계 때문에 끝났다 — 새 일 수락 전 이 인계서 §1~§3 을 읽고 시작.

## 1. 골 표 현재 상태 (2026-10-26 오전)
| 요소 | 상태 |
|---|---|
| Tailscale·CLI 운용·OCI headroom/cliproxy/pi·tmm | ✅ |
| hermes OCI·mini·이 맥 | ✅ (mini 슬랙 #talk-aina @aina 응답 오빠 확인 10-25) |
| mini 자체 IAP 터널(LLM·STT)·옛 키 폐기 | ✅ |
| 시험 이관 — 러너 1회차 | ✅ 오빠 «통과 인정»(10-25 16:29 · baseline-ko-en 1/1 · **개발 레인 우회** 로 통과) · ★그러나 v65 수정(main `3c250223d1` · M5 release legacy seam_store 배선)을 올리고 우회를 걷으면(flag-off) **말풍선 0(host_empty)** — v65 arch 가 «설계상 정상 아님» 판정 · FE 렌더/러너 판독 쪽 · 가르기 실험 중(아래 §2) |
| 위성 나노 «열기→작업→회수→닫기» + 쪽지 왕복 | ✅ h13 rc=0 · h16 rc=0 (sat-mbox.py · 새 키 0 · 이 맥이 ssh 로 pull) |
| 위성 나노 도구화(하네스) | ⏳ 카드 r902(이슈 3363) · 하네스 마스터 #112 · pi 나노 spawn 됨·진행 중(발주서 `docs/multihost/satellite/ORDER-harness-sat-nano-20261025.md`) · r673~r678 은 r902 착지 뒤 연속 |
| DB 경로(mini → dev DB) | ⏳ 읽기 전용 검증 끝(`VERIFY-db-path-20261025.md`) · 변경 3개(새 VM `byz-db-fwd`·방화벽 1·IAP 조건 1)는 ★오빠 승인 대기★(이 맥 터널도 옮길지 질문 미답) |
| OCI hermes 403(OpenRouter 뒤 GMICloud Cloudflare) | 🟡 오빠 요청 «opengateway deepseek ultrafast 넣어주자» → 계획 h 준비됨(§2) |
| 하네스 카드 r673~r678 | ⏳ |

## 2. 오빠 손 대기 — 순서대로 한 줄씩(겹쳐 치면 서로 막는다 · 10-26 실측)
1. **`! bash /tmp/h191`** — 러너 1회차(소리 1회). 지금 mini = BYZ main `3c250223d1` · worker **개발 레인**(h210 rc=0) · 웹 next dev(mock host) · 이번 회차가 «같은 코드 + 레인만 dev» 가르기 실험. h191 끝에 콘솔·SSE 요약(`console_rec.py` 기록기: 호스트·게스트 탭 전부, 필터 없음) + gateway live_forward 종류별 수가 자동 출력. 결과 판정: **통과 → 레인 쪽(flag-off 에서 FE 가 owner 이벤트를 안 그림)** · **dev 도 0 → 새 코드 FE 쪽**. 결과를 v65 arch(현역은 `tmux ls` 로 — 지금 `byz-v65-arch-claude#313`)에 mbox 로 보낸다(쪽지 168676 에 이미 계획 전달·168691 로 수락됨).
2. **`! bash /tmp/h211`** — OCI hermes 모델을 opengateway `deepseek/deepseek-v4.1-flash-ultrafast` 로(h-oci-hermes-opengateway.sh · OCI 직접 호출 시험 200 아니면 설정 0 변경 · 백업 2개 · providers 블록 · `systemctl --user restart hermes-gateway`). 끝나면 오빠가 jarvis 슬랙 봇에 말 걸어 확인.

## 3. 미결·함정(이번 세션 실측)
- **ssh mini 가 간헐적으로 `Operation timed out`**: 10-26 새벽 tailscale 이 직접 연결 → 중계(DERP 115~233ms)로 바뀜. 재시도 + `-o ConnectTimeout=20`, 결과는 파일로 받는다.
- 크론 중복: 크론을 지울 땐 `CronList` 로 전부 확인(#4 가 처음 건 것을 못 지워 점검이 2배로 돈 적 있음).
- v65 좌석은 자주 승계된다(arch #310→#311→#313 · master #245→#246→#247): 쪽지 보내기 전 `tmux ls | grep byz-v65` 로 현역 확인 — 옛 이름 앞 쪽지는 옛 세션에 쌓인다.
- 시험 서버 포트는 38301~38399 안만(worker 38313 · gateway 38312 · web 38314 · redis 38311). worker 상태 주소는 gateway 에 `WORKER_HEALTH_URL`(settings.worker_health_url)로 준다.
- 서버 h 레인 스위치: `WORKER_LANE=flagoff`(기본·우회 없음) / `dev`(c2c 개발 레인 · `h-mini-server-restart-lane-dev.sh` 가 dev 로 재기동). 다시 flag-off 로: `h-mini-server-restart-dev.sh`(현재 h189 번호).
- 러너 h 합격 판정 = `✅ host 단일 버블`(ptt_multi_utterance 전용) **또는** MR `scenario_done ok=N/N errors=0`(baseline) — 후자를 추가해 둠.
- mini worker 새 코드 시작 로그에 `NOTE_SUMMARY_VLLM_BASE_URL 가 비어 있다` 오류 줄 — 이번 시험엔 무관하나 새 버전이 요구하는 설정이 mini 에 없다는 신호(필요하면 KEYS 에 추가).
- mini 새벽 LLM keepalive 실패(`localhost:8000` 7초 timeout 연속) — mini 자체 IAP 터널(LLM 8000) 점검 필요(launchd `byz-mini-tunnel`).
- ★기다림 3가지: (a) v65 가르기 판정 (b) 하네스 r902 착지(하네스 마스터가 알림) (c) 오빠 DB 경로 승인·이 맥 터널 이관 여부 답.

## 4. 하지 말 것
원격 쓰기는 오빠 `! bash /tmp/h<N>` 로만 · 하네스·BYZ 소유 파일 편집 0 · main 직접 커밋 0 · 마감 질문 금지(골 표 🟡·⏳ 남은 동안) · 임의 Redis/말풍선 DOM 주입 0(하드 룰 11) · 약어로 골 부르기 0 · 삭제·덮어쓰기(브랜치 -D·VM·키 폐기)는 HIL · 키 값은 어디에도 출력 0(h 는 600 임시파일+stdin).
