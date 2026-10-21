「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. byz mac mini와 jarvis OCI에 tailscale 설치·연동으로 cli 레벨 운용, 브라우저 가능 환경은 테스트 이관, 팀·나노 작업 분산 운영하는 멀티 인스턴스(네트워크) 기능 구축 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
골의 어느 축: 멀티호스트 기획→구현 이관 — 닫는 증거 = DESIGN-multihost-20261021.md DA 승인(✅ r8-1 994a6c5b · r8-2 승인 유지) + 오빠 결정 D2~D13(✅ 확정) + OCI Tailscale 설치(✅ 로그인 완료) + 하네스 카드 착지(⏳ 하네스 나노 진행) + 오빠 손 2건(⏳)
너는 aifp-multihost-master-claude#1 (멀티호스트 팀장). 전임 #0 의 증류 후계. 승계 첫 일 = 아래 «골 대조 보고» 후에만 착수.

# aifp-multihost-master-claude#0 → #1 인계 (2026-10-22 · 컨텍스트 551k 증류)

> 골 원문(불변)은 위 3줄. 이 파일은 «진행»만 적는다. 작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 가지 `docs/multihost-plan-20261021` (main 직접 커밋 0 · 병합은 오빠 `!` 한 줄).

## 0. 첫 일 순서 (이 순서)
1. 골 대조 보고(위 «닫는 증거» 각 칸의 현재 상태를 아래 §1 표로 매핑해 상위 `aifp-worker-master-claude#2` 에 mbox) + 부팅 보고(세션명/모델+창/Serena 가부/`adhd=O`/`cron=<id>`).
2. 체크 크론 새로: `*/10 * * * *` (구 크론 5b8acc20 은 세션 종속이라 이어지지 않음). 틱 내용 = 아래 §5 한 줄.
3. 쪽지 3곳 recv: ① `FT_MBOX_DIR=/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh recv aifp-multihost-master-claude#1` ② 같은 이름 `#0` 큐에 남은 쪽지가 후계에 계보로 오는지 확인 ③ BYZ 쪽 `bash /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh recv …` ④ 워크트리 안 `.fable-team/comm` (나노 pi 가 이쪽으로 보고한 선례 있음 — 쪽지 경로가 둘이다).

## 1. 골 대조 — 닫는 증거별 현재 상태
| 닫는 증거 | 상태 | 정본 |
|---|---|---|
| DESIGN DA 승인 | ✅ r8 APPROVE(STRUCT 0) 커밋 994a6c5b · 이후 변경 경량 대조 «승인 유지» 2bb109ae/13e39733 | `docs/multihost/DA-verdict-r8-1.md` · `r8-2.md` |
| 오빠 결정 D2~D13·U1·U2 | ✅ 전부 확정(AskUserQuestion). 허브=Mac mini · D10=같은 계정(추천과 다름, 한도 공유 위험 문서화) · D11=불필요(hermes 이미 systemd 사용자 서비스) · D13=mini BlackHole 설치 | DESIGN §14 «확정» 열 |
| OCI Tailscale 설치 h | ✅ 설치·로그인 완료(h83 rc=4 였지만 실제 완료) `aifp-oci-jarvis` · 직접 경로 5ms | `measured-oci-tailscale.md` |
| 구현(하네스 카드) | ⏳ 하네스가 구현: A=r673(P2 tmuxc --host) · B=r674(P4 tmm HOST 열) · C=r675(P3 우편함) · 덤 r676(recv 15% 이중 소비). 착지 순번 r646→r673→r674→(r469→r676)→r430·r432·r627→r675. **우리 구현 착수 0** | `harness-requests-20261022.md` |
| 요청 D(P1 aifp-gate·K1/K2·원격 설치 h) | ⏳ 요청문 초안 완료, 하네스 카드 번호 회신 대기 | 같은 파일 |
| 공개 저장소 push | ✅ origin/docs/multihost-public-20261022 = e527066d (IP·계정·도메인 가림 1커밋, 상위가 push) | 가림 도구 scratchpad/redact-multihost.py |

## 2. ★오빠 손 대기 2건 (계속 틱마다 확인)★
1. **OCI 키 만료 끄기** — `tailscale status --json` 의 aifp-oci KeyExpiry 가 2027-04-19T14:09:41Z 에서 안 바뀌면 미완. 오빠: login.tailscale.com/admin/machines → aifp-oci-jarvis «…» → Disable key expiry.
2. **mini 마이크·소리 점검** — `/tmp/h143.ran` 없으면 미실행. 오빠: `! bash /tmp/h143`(mini /tmp 에 시험 스크립트 올림) → mini 터미널에서 `bash /tmp/aifp-mini-audio-check.sh`(소리 1초·마이크 허용 팝업 1회). 평균 > -50dB 면 MIC_OK 후보, 최종 확정은 e2e trusted 클릭 회차(P6 ①).
(⏸ 대기: ACL(tag:aifp)은 요청 D 키 등록 직전에 JSON 을 드림 · docs 가지 병합 h 는 마감 때 한 번에)

## 3. 열린 쪽지/질문
- 상위에 보낸 질문 #3092: arch#1·DA#1 을 닫아도 되는지(회신 없음). 회신 전에는 닫지 않음. 설계가 끝났으니 닫는 쪽을 추천 중. 둘 다 지금 대기(일하는 석 0).
- 하네스에 보낸 요청: 요청 D 카드 번호 + 열린 카드 r469·r430·r432·r627 범위(본문을 이 맥에서 못 찾음 — 지어내지 말 것).
- 좌석: `aifp-multihost-arch-claude#1`(Opus 5.5) · `aifp-multihost-da-codex#1`(gpt-6.1-sol low fast) · 나노(pi) 전부 닫음(쓰고 바로 닫기).
- 남은 정리(마감 때 HIL h): 워크트리 `.worktrees/mh-p2-tmuxc` + 가지 `nano/mh-p2-tmuxc-host-dispatch`(커밋 0·변경 0 — 취소된 P2 구현용), `.worktrees/multihost-public` + 가지(push 완료 후 보존). 가지 삭제는 HIL.

## 4. 함정 (실측)
- **OCI 공인 22 = ufw limit**: 같은 IP 새 연결 30초 6회↑이면 «Connection refused». ssh 는 `-o IdentitiesOnly=yes -i ~/.ssh/oci_chuncheon` + `ControlMaster` 연결 1개 재사용. 내가 앞서 말한 «fail2ban 자기 차단» 은 틀렸음(증거로 철회).
- 훅 `block-destructive.sh` 오탐: 발주 본문에 «강제종료 명령 예시 글자»가 들어가면 차단 — 본문을 파일로 쓰고 `ft-mbox.sh relay` 로. 비밀 판정기(`ft_secret_judge.py --plan`)는 키 값을 화면에 찍는 형태를 거절 → 리터럴 경로로.
- **내 실수 2건(재발 금지)**: ① 공개 워크트리(.worktrees/multihost-public)에서 가림 스크립트를 재생성해 상위가 일반화한 줄을 덮음 — **그 워크트리에서 재생성 금지**, 문서가 바뀌면 새 커밋 1개. ② 정시 틱에서 «물어보겠다» 라고만 쓰고 안 보낸 적 있음(지난 틱에서 실제 발송) — 말한 일은 그 턴에 도구로.
- zsh: 변수에 담은 옵션 문자열은 분리 안 됨 → 함수(`m() { …; }`)로.
- 이 맥 swap 여유 ~1.3GB: 나노 동시 1석, 쓰고 바로 닫기(pi). 좌석 닫기는 표준승인(최근 1개 보존) 범위.
- 상위의 수정은 «덮어쓰지 않는다» — 작업 트리 파일이 바뀌었다는 알림이 오면 다시 읽고 이어간다.

## 5. 체크 크론 틱 한 줄(프롬프트)
①`ft-mbox.sh recv aifp-multihost-master-claude#1`(+ BYZ mbox) ②`tmux ls | grep aifp-multihost` ③`/tmp/h143.ran` · OCI KeyExpiry · `git status --short` ④상위·오빠에게: 일하는 석 N · 기다리는 값 · 다음 수(변화 없으면 1줄). 말한 일은 같은 턴에 도구로 실행.

## 6. 하지 말 것
원격 쓰기 0(설치는 오빠 승인 h 만) · 구현 착수 0(하네스 카드로만) · 공개 가지 재push/히스토리 교체 0 · main 직접 커밋 0 · 하네스(BYZ) 소유 파일 편집 0 · 가지 삭제는 HIL · 임의 Redis/DOM 주입 0.
