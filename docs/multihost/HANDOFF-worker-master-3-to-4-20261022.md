「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」 (오빠 10-21) · 「이대로 끝이라고?」 (오빠 10-22 — 골 달성까지 계속 · 마감 질문 금지)
골의 어느 축: «두 곳에서 CLI 로 실제 운용» + «시험 이관» + «분산 운영 기능» — BRIEF-phase2-operate-20261022.md 의 ❌ 가 남으면 «끝» 없음.

# aifp-worker-master-claude#3 → #4 인계 (2026-10-22 23:4x · 컨텍스트 551k 증류)

## 골 축별 지금 (닫는 증거는 BRIEF)
| 축 | 상태 | 남은 것 |
|---|---|---|
| 두 곳 CLI 운용 | ✅ OCI·mini 모두 CLI 5종 + 대기 좌석(aifp-mini-worker-claude#0 · aifp-oci-worker-claude#0) 오빠 Termius tmm 확인 · OCI fzf 0.74.3 · 한글 폰트 Jetendard | — |
| OCI headroom·cliproxy | ✅ h376 · 계정 claude1·codex2(h404 · 오빠 «claude 1개만») | — |
| hermes 업데이트 | ✅ OCI v0.22.4@81a55437(h5) + 오빠 로컬 수정 복원(h8: ~/.hermes/plugins/em-dash-filter · AGENTS.md 172행) | 이 맥·mini hermes 는 «OCI 결과 본 뒤 별도 h» — 미착수 |
| 시험 이관 | 🟡 mini BYZ 서버 4개 생존(h2 · BYZ main 4c876d7f · gateway 38312 · web 38314 · DB=10.2.0.10 «이름만 prod, 실제 dev 런타임» BYZ #141206 · 오빠 «그대로») · 터널은 이 맥 역방향 포워딩(h18 · 이 맥 켜져 있어야 함) | **오빠: mini 앞 체크리스트 4번(시험용 Chrome·CDP 9333) → `! bash /tmp/h19`(e2e 1회차)** — h19 첫 실행은 CDP 9333 없음만 rc=2 |
| mini 자체 IAP 터널 | 🟡 h7 ✅(SA byz-mini-tunnel·byz-oci-tunnel · IAP 조건부 · 키 mini·OCI ~/.config/byz-tunnel/sa.json 0600) | **오빠: `! bash /tmp/h40`(h-B mini gcloud 587+launchd 터널 18703·18708 · 내가 DRY 통과 확인)** → 그 뒤 h-B2(포워딩 8000/8001 끄기+포트 교체) → h-C(OCI) · A2(DB 경로)는 RESEARCH-a2(포워더 VM안 · 오빠 승인 필요 · 대상 10.2.0.10) |
| 옛 키 폐기 | 오빠 승인(«h7 뒤 삭제») | **오빠: `! bash /tmp/h39`** (KEY-LEDGER 대조 · 내가 DRY 통과 확인) |
| 분산 운영 기능 | ⏳ 하네스 카드 r673(P2)·r674(P4)·r675(P3)·r676·r678(P1) 착지 0 — 하네스 그레이스풀 정지 · 오빠 «tmm 한 화면은 당분간 호스트별» | 하네스 요청: tmm Linux stat 결함(BYZ #140818) |

## 좌석
- 팀장 `aifp-multihost-master-claude#2`(Sonnet 5.5 · multihost-plan 워크트리) — h 발급 전 오케에 1통 규칙 합의. 지금 h-B 다음 단계 대기.
- `aifp-pi-master-pi#0` 유지(오빠 «닫지 말라»).
- 옛 세대 #2·multihost#1 은 오빠 «둘 다 닫기» → 재개 기록 후 닫음(verdict 20261022-aifp3-close).
- 이 좌석 체크 크론 `ac0f323b` 는 세션 종속 — 후계가 새로 건다(두 쪽지함 recv · pane 은 list-panes 로 id 찾아 capture · `#` 든 이름은 `-t =이름` 이 비어 나옴).

## 오늘 배운 함정
- h 발급: `ft-hil.sh --add <계획> --notify 'aifp-worker-master-claude#N'` (feature-pack/fable-team/harness/bin) · 재부팅하면 /tmp/h* 번호 리셋 · 비밀 가드가 `env` 배열·변수 printf 를 거부 → 함수꼴/파일 stdin 꼴로.
- 원격 nohup 기동은 `( … & )` 꼴이 아니면 ssh 채널을 붙잡아 timeout(h381·h5 rc=4 원인) · mini 에 setsid 없음.
- 이 맥 gcloud 기본 계정이 byz-local-dev 로 바뀌어 있음(누가 바꿨는지 미확인) → 관리 h 는 ADMIN=developer.ts@byourz.com 고정.
- 코드 탐색은 `ci` 우선(하드 룰 16 · 2026-10-22) — `ci search` 가 tmm 폴더 .md 에서 패닉(markdown.rs:240 · pi-ops#0 에 보고).
  ci doctor / ci search "<q>" <path> --max 5 / ci sym <sym> --callers --scope . / ci outline <file> / ci refs "<file>#<sym>" (사전 활성화 없음 · 부재 시 rg+Read 후 1줄 보고)
- 결정은 AskUserQuestion · 마감 질문 금지 · 좌석 닫기 전 오빠 의견.
