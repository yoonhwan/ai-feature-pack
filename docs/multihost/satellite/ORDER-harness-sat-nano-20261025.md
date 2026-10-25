「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
「이슈팀 전체 이동하지말고. 이슈팀 팀장이 나노워커를 mini에 열어서 위성으로 ssh로 열어 사용하고 닫는 실험부터 먼저하자. 지금 이슈별 나노가 많이 필요한건데 이것부터.」(오빠 2026-10-25) · 「ft 의 mbox ssh 지원부터 되야하는거 아님?」(오빠 2026-10-25) · 「하네스 팀장에 발주해서 도구사용해서 먼저 이슈팀에 전달 실험하고 최초 랜딩. 이후 확장은 멀티호스트팀과 협의.」(오빠 2026-10-25)
골의 어느 축: «팀이나 나노 작업을 분산 분해해서 운영하는 멀티 인스턴스 기능» 중 ★위성 나노(mini) 최초 1회 도구화 + 이슈팀 실사용 + 최초 랜딩★. 닫는 증거 = 이슈팀 팀장이 도구로 mini 나노를 열어 일을 시키고 결과를 쪽지로 받고 닫은 로그 1건 + main 착지 sha.

# 발주 — 위성 나노 도구 (하네스 팀장 → 이슈팀 실험 → 최초 랜딩)

발신 aifp-multihost-master-claude#4 · 수신 byz-harness-master-claude#110 · 협의 상대(이후 확장) = aifp-multihost-master-claude#4

## 이미 된 것 (멀티호스트 팀 실측 · 2026-10-25 · 가지 docs/multihost-plan-20261021 · 커밋 ba9de431)
| 항목 | 증거 |
|---|---|
| mini 에 fable-team 스킬·에이전트 정의 설치(추가만) | h12 rc=0 · 스모크 send→recv |
| 위성 나노 «열기→작업→회수→닫기» 1회 | h13 rc=0 · 55초 · 결과 `docs/multihost/satellite/test-2-out.md` · 닫힘 확인(세션 없음·pi 0) |
| 위성 쪽지 왕복(이 맥 push → mini 나노 recv·send → 이 맥 pull) | h16 rc=0 · 회신 12초 · 갇혀 있던 나노 보고 2건 배달 |
| 도구 원형 | `docs/multihost/satellite/sat-mbox.py`(push/pull/status · 새 키 0 · 이 맥이 ssh 로 pull+ack · dedupe) · `docs/multihost/h-plans/h-mini-satellite-nano-test.sh`(열기·작업·닫기 원형) · `h-mini-satellite-mbox-test.sh`(왕복 원형) |

## 모르는 것·한계 (숨기지 않음)
- 자동 가져오기 없음(사람이 호출할 때만 pull) · 알림 종소리(doorbell) 없음(h16 은 tmux send-keys 한 줄) · 위성 나노 앞 «지시 쪽지»는 mini 쪽지함 직접 push.
- 이슈팀 실작업(이슈 본문·코멘트 판정)은 mini 에서 BYZ 소스·`gh` 가 없어 «소스 없는 작업»만 가능. mini 에는 gh·git ssh 키 없음(BYZ 클론 막힘) — 이 발주 범위 밖(필요하면 별도 결정).
- tmux 창 대상은 `=이름:` (끝 콜론) 이어야 pane_pid 가 나온다(`=이름` 은 빈 값 — 실측).
- mini 메모리 16GB · 시험 서버·Chrome 상주 → 위성 나노 동시 3~4개 추정(실측 아님).

## 하네스 팀장이 할 일 (집행 순서)
1. 위 원형 3개를 읽고 ★하네스 도구 1개로 묶는다★: 열기(`open`) · 작업 전달(`task`) · 쪽지 가져오기(`pull` 자동 주기 포함) · 회수(`fetch`) · 닫기(`close` — 이 도구가 연 세션만 kill). 위치·이름·LIVE_BIN 반영은 하네스 규칙대로(하네스 소유 파일은 하네스 팀만 편집).
2. 닫기는 ★반드시 «도구가 연 세션 + 그 폴더에서 도는 pi 0 확인»★ — 못 닫으면 닫기 실패로 표시(강제 kill 0 · 남의 프로세스 0).
3. ★이슈팀 실험★: byz-issues-master-claude#30 이 도구로 mini 나노 1~2개를 열어 «소스 없이 되는 이슈 판정 1건»(이슈 본문·코멘트를 파일로 보내 판정 요약을 받는 일)을 시키고, 결과를 쪽지로 받고, 닫는다. 로그 1건을 증거로 남긴다.
4. ★최초 랜딩★: 도구 + 시험(닫기 확인·쪽지 중복 0 포함) + 이슈팀 실험 로그 → main 착지. 원격 쓰기(mini)는 오빠 `! bash /tmp/h<N>` 한 줄로만(이 팀 규칙).
5. 이후 확장(자동 주기·doorbell·gh/소스 클론·OCI·다른 팀) = ★멀티호스트 팀(aifp-multihost-master-claude#4)과 협의 후★. 설계 정본 = `docs/multihost/DESIGN-multihost-20261021.md`(허브 방식) — 이 도구는 그 설계를 대체하지 않는 «위성 1단계»이고 r673~r678 카드와 충돌하면 카드가 우선.

## 하지 말 것
- 이슈팀 전체를 mini 로 옮기기(오빠 지시 «전체 이동하지말고») · mini authorized_keys·settings 변경 · mini 쪽 BYZ 서버·Redis 접촉 · 약어로 골 부르기.
