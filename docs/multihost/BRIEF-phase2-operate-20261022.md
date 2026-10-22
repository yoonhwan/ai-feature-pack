「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」 (오빠 2026-10-21) · 「이대로 끝이라고?」 (오빠 2026-10-22 — 기획 마감은 잘못, 골 달성까지 계속)
골의 어느 축: «두 곳에서 CLI 로 실제 운용» + «시험 이관» + «분산 운영 기능» — 기획(설계 DA 승인)은 끝났고 이 문서는 «운용» 단계의 발주서다.

# 2단계 발주 — 멀티 호스트를 «실제로 운용» 하기 (2026-10-22)

## 골 대조 — 됨 / 안 됨 (실측 기준)

| 골 요소 | 상태 | 근거 |
|---|---|---|
| mini·OCI Tailscale + 계정 연동 | ✅ 됨 | `measured-oci-tailscale.md` · mini 는 원래 tailnet |
| mini 에서 **CLI 로 운용** | ✅ 됨 | 오빠 확인(2026-10-22 16:1x «둘다 봤다»): 대기 좌석 `aifp-mini-worker-claude#0`(mini · ANTHROPIC_BASE_URL=localhost:8790 헤드룸 경유)을 `tmuxc open` 으로 띄우고 오빠가 Termius tmm 에서 확인. 선행: h375 rc=0 설치(tmuxc 0.4.4·tmm 0.9.4·pi 1.3.0·fzf). 원인 확정 이력: 처음 `tmuxc open` 실패는 홈 폴더 신뢰 질문에서 Enter 가 «No, exit» 를 눌러서였고, 상위가 mini `~/.claude.json` 홈 폴더 신뢰 표식을 백업 후 켜서 해결. 좌석은 오빠가 닫으라 할 때까지 유지 |
| OCI 에서 **CLI 로 운용** | ✅ 됨 | **닫는 증거 3줄(h377 rc=0 · 2026-10-22 14:09)**: ① `claude-aifp -p ping` → ping_rc=0(pong, OCI 로컬 cliproxy 8317 경유) ② `tmuxc probe` agent=claude · model=claude-sonnet-5-5 (좌석 oci-cli-proof-140956 · bypass on 화면) ③ seat=closed. 설치: claude·pi·codex(npm ~/.npm-global) · tmuxc 0.4.4 · tmm 0.9.4. (선행 h376 rc=0: cliproxy·headroom active, 모델 3종·health 200.) 대기 좌석 `aifp-oci-worker-claude#0`(OCI · 127.0.0.1:8317)도 오빠가 Termius tmm 에서 확인(2026-10-22 16:1x), 닫으라 할 때까지 유지 |
| OCI 에서 **pi(deepseek)** | ✅ 됨 | h400 rc=0(2026-10-22): OCI pi 1.3.0 · opengateway deepseek 설정(이 맥 models/settings 동일 · 키 `~/.pi/agent/opengateway.key` 0600 · 값 출력 0) · 증거 `pi -p` → pong · pi_rc=0. 계획 `h-pi-opengateway.sh`(상위 커밋 37f68d79·79fcf2e2). mini 판 = 같은 스크립트 R=mini(미실행) |
| **tmm 호스트 접속(Termius)** | ✅ 됨 | 오빠 확인(2026-10-22 16:1x «tmm 뜬것 확인»): Termius → OCI(100.115.169.113 ubuntu) · mini(100.71.41.107 byz) 접속에서 tmm 동작. OCI 는 apt fzf 0.29(`--track` 미지원 → 피커 rc=2 반복)였으나 `~/.local/bin/fzf` 0.74.3(공식 arm64 · sha 일치)로 해결. 재현성: `h-oci-cli-tools.sh` 2b 단계(fzf ≥0.36 점검·설치). 남은 표시 결함: tmm 295행 GNU stat → 하네스 요청(BYZ #140818) |
| mini 에서 **pi(deepseek)** | ✅ 됨 | **h401 rc=0**(2026-10-22): mini pi opengateway deepseek 설정 · 증거 `pi -p` pong · pi_rc=0 (같은 스크립트 R=mini) |
| OCI headroom·cliproxy 연결 | ✅ 됨 | h376 rc=0 — 위 표 참조(두 유닛 active · 모델 3종 · health 200) |
| OCI cliproxy 계정(claude 1 · codex 2) | ✅ 됨 | 오빠 결정 변경(2026-10-22 «일단 하나만»): claude 5→1. **h404 rc=0**(h399 대체): claude=1/1 · codex=2/2 · /v1/models 32개. BYZ 인증 파일 복사 0 |
| hermes 업데이트 지원 | ⚠️ 절차만 앎 | 이미 systemd 사용자 서비스 · `hermes update --check→backup→update→restart→doctor` |
| 브라우저 시험 이관 | 🟡 진행 | mini: Chrome·BlackHole·마이크 사전 점검 통과(-37.3 dB). h378 rc=0(러너 폐쇄 16파일 배치 · venv websockets/jwt import OK · sha 16/16). **h379 rc=0**(tts-say 설치: sha 일치 · shebang python3.13 · ko_KR 9 · Yuna 1 · help_rc=0). 남음: 서버(h381) · mini 앞 오빠 손 7단계 · 러너 1회차(h382) |
| tmm·tmuxc·fable-team 멀티 인스턴스 기능 | ⏳ 하네스 카드 대기 | r673(P2)·r678(P1)·r674(P4)·r676·r675(P3) — 하네스 순번 뒤쪽 |
| 운영 UX(슬랙·tmm 호스트 판) | ⏳ 설계만 | `DESIGN-multihost-ops-ux-20261021.md` |

## 지금 할 트랙 (하네스 카드와 무관하게 진행 가능 — 하네스 소유 파일 편집 0)

### 트랙 1 — OCI 를 «CLI 운용 노드» 로 (최우선)
1. 이 맥 /tmp 에서 cliproxy 패치 빌드 linux/arm64 교차 빌드 시험(원격 영향 0) → 결과 바이너리 버전·카탈로그(sonnet-5-5·haiku-5-5·gpt-6.1-sol) 확인.
2. OCI 설치 h 1장: headroom 0.33.0(pip, 버전 고정) + cliproxy 바이너리 + systemd 사용자 유닛 2개(127.0.0.1 바인드) + 인증 파일(D10=같은 계정 · op develop 볼트에서만 · 값 출력 0).
3. OCI 설치 h 1장: claude CLI·pi·codex(npm) + tmuxc·tmm(이 리포 파일 복사 · 버전 대조) · claude 는 `ANTHROPIC_BASE_URL=http://127.0.0.1:8317`(OCI 로컬 cliproxy) 경유.
4. 닫는 증거: OCI 에서 `claude -p "ping"`(7초 상한) rc=0 원문 + `tmuxc open` 으로 OCI 에 좌석 1개를 열고 probe → 닫기 원문.
- 주의: ufw 22번 새 연결 30초 6회 상한 → ssh ControlMaster 1개 재사용 · tailnet 주소로만.

### 트랙 2 — mini 를 «운용·시험 노드» 로
1. mini 설치 h: tmm·pi(이 맥과 같은 버전) — mini sudo 는 암호 필요하니 brew/npm 사용자 설치로.
2. 실제 운용 1회: 이 맥에서 ssh 로 mini 의 기존 tmuxc 를 불러 좌석 1개 열기 → probe(모델·헤드룸 경유) → 닫기. «기능 구축 전에도 ssh+tmuxc 로 지금 운용 가능» 을 증명.
3. 브라우저 시험 이관 준비: mini 에서 기존 e2e 러너가 돌 조건(리포·러너·Chrome CDP·BlackHole) 목록 + 첫 회차 계획.

### 트랙 3 — 하네스 순번 당기기 (상위 worker-master 가 함)
- r673(P2)·r678(P1) 을 앞당겨 달라는 요청 — 오빠 골 우선.

## 노드 접속 (오빠 2026-10-22 고정)
- **Mac mini 사용자 = `byz`**(yoonhwan 아님). 부를 땐 `ssh mini`(`~/.ssh/config` 에 `User byz`·키 `id_ed25519_aifp_op` 고정). 스크립트의 mini 사용자 기본값은 `byz` · `yoonhwan@` 로 접속해 «ssh 안 됨» 보고 금지.
- OCI = `ssh oci`(ubuntu@) · tailnet 은 `aifp-oci-jarvis`.

## 하지 말 것
- 하네스 소유 파일(feature-pack/fable-team·tmuxc·tmm 코드) 편집 0 — 카드 경유.
- 원격 쓰기는 오빠가 치는 `! bash /tmp/h<N>` 로만 · 비밀은 op develop 볼트만 · 값 출력 0.
- 승계 도구가 `mbox_doorbell.sh` 누락으로 막힌다(정본 5-1) — 컨텍스트 70% 에 인계서를 미리.
- 마감 질문 금지 — 위 표의 ❌ 가 남아 있는 동안은 «끝» 이 없다.
