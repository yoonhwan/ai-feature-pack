「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」 (오빠 10-21) · 「이대로 끝이라고?」 (오빠 10-22 — 골 달성까지 계속)
골의 어느 축: «두 곳에서 CLI 로 실제 운용» + «시험 이관» + «분산 운영 기능» — BRIEF-phase2-operate-20261022.md 의 ❌ 가 남으면 «끝» 없음.

# 재부팅 뒤 이어가기 (2026-10-22 17:1x · aifp-worker-master-claude#3 작성)

## 된 것 (닫는 증거는 BRIEF)
- OCI: cliproxy·headroom(h376) · claude/pi/codex/tmuxc/tmm(h377) · pi opengateway(h400) · 계정 claude1·codex2(h404) · fzf 0.74.3(~/.local/bin) · 한글 폰트 Jetendard(/usr/local/share/fonts/jetendard)
- mini: pi opengateway(h401) · tts-say(h379) · 러너(h378) · 홈 폴더 신뢰 표식
- 대기 좌석: aifp-mini-worker-claude#0 · aifp-oci-worker-claude#0 (원격이라 이 맥 재부팅과 무관 · 오빠가 Termius tmm 으로 확인)

## 오빠 판정 (오늘)
- mini 서버 DB = dev DB · 서버는 mini (이 맥 아님)
- mini·OCI 자체 IAP 터널 · 호스트별 새 SA · 최소권한 (byz-local-dev 복사 금지)
- 이 맥 loom-pg-tunnel 38309 → 10.2.0.10 = postgres-PROD 는 «의도 아님, dev(10.2.0.3)로» → BYZ planner#107 에 [급] (BYZ 쪽지 #141122) · mini 시험 서버 정지함(h381 stop rc=0)
- A1(SA·IAP·LLM/STT/TTS 터널, ssh 0) 먼저 + A2(DB ssh 경로) 리서치 나노 — 둘 다 진행 (하드룰 14: DA 보류 2회)
- OCI claude 계정은 1개만 · tmm 멀티 호스트 한 화면(r673→r674)은 당분간 호스트별(하네스 정지 유지)

## 다음
1. 팀장(aifp-multihost-master-claude#2) 이 h-A1 작성 → DA r3(작은 범위) → 나(오케) 점검 → 오빠 h
2. A2 리서치 나노 결과 → DB 경로 재설계 (dev 10.2.0.3 만)
3. BYZ 가 38309 터널 목적지 교체 확인 전엔 mini DB 연결 0
4. h381 재실행 → mini 앞 체크리스트 → h382(e2e 1회차)
5. hermes 업데이트(오빠 10-21 요청 · 미실행)
6. 하네스 요청: tmm Linux stat 결함(BYZ #140818)

## 재부팅 뒤 이 맥에서 확인할 것
- launchd 터널 4개 재기동(com.byz.iap-tunnel-18703/18712 · stt-tunnel-8001 · loom-pg-tunnel) — 8000 은 launchd 아님(수동 start-iap-tunnel) · 재부팅 뒤 사라짐
- 오케 좌석 재개: 체크 크론 새로 걸기(세션 종속)
