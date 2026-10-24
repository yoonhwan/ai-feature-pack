「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」(오빠 2026-10-21)
「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」(오빠 2026-10-21) · 「이대로 끝이라고?」(오빠 2026-10-22 — 골 달성까지 계속) · 「이거 pi 나노워커 투입해서 이어가라」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 에서 러너 1회차 → 성공 줄 `✅ host 단일 버블 (delta=1, polished Nchars)`)» — 이 일은 그 축의 다음 실패를 «미리» 줄이는 읽기 전용 조사다.

# 나노 발주 — mini worker env 이름 차집합 (읽기 전용)

너 = aifp-multihost-nano-pi#0 (pi · 일회성 조사 워커). 상위 = aifp-multihost-master-claude#4. 작업 폴더 = 이 워크트리(`/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan`).

## 배경 (확정된 사실)
- mini 에서 BYZ main `c34fc47f` 서버를 띄워 러너 1회차(마이크 press 1회 → STT 최종본)를 돌린다. 6번째 실패 원인 = worker 환경 변수 `DEV_GPU_STATUS_URL` 이 mini 로 안 넘어가 STT 게이트가 «GPU offline» 으로 판정(이미 고침 · 커밋 3c7f0135).
- 같은 유형(이 맥 `.env` 에는 있는데 서버 h 의 `KEYS` 화이트리스트에 이름이 없어 mini 로 안 넘어감)이 또 있는지 «이름만» 찾는 것이 이 일이다. V5_BACKEND_ENABLED · DEV_GPU_STATUS_URL 이 같은 유형 사례.

## 할 일 (순서)
1. 이 맥 BYZ 로컬 worker·gateway 기동 세트의 «필수 env 이름 목록» 을 찾는다: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/scripts/server/ready-check.sh` 의 `WORKER_ENV_SPEC` · `server.sh` (코드 읽기만).
2. 현재 서버 h 의 `KEYS`: `docs/multihost/h-plans/h-mini-byz-server.sh` 의 `KEYS=(…)` 와 그 아래 «고정값 채우기» 로직(WORKER_ENV_SPEC 에서 .env 에 없던 고정값을 채운다고 로그에 나옴 — 어떤 이름을 채우는지)을 읽는다.
3. 러너 경로(STT → 말풍선 polished)에서 코드가 읽는 env 이름을 mini 의 BYZ 체크아웃(`ssh mini` · `~/Project/BYZ-Agents` · rg 는 `export PATH=/opt/homebrew/bin:$PATH` 필요)에서 `rg -n 'os.getenv|os.environ' worker/graph/speech worker/services/gpu worker/services/stt shared/config gateway/routes/compat/speech.py` 로 모으고, 1·2 와 비교해 «이 맥엔 있고 mini 로 안 가는 이름» 후보를 뽑는다.
4. 결과를 `docs/multihost/NANO-result-env-diff-20261025.md` 한 장에 쓴다: 표 = 이름 · 코드 위치(파일:줄) · 없으면 생기는 증상 1줄 · 확신도(확정/추정). 상위 10개 이내. 확정/추정을 섞지 않는다.
5. 끝나면 mbox 로 상위에 3줄 보고(`[결과]` 머리 아님 — 본문 첫머리에 «완료»): 파일 경로 + 후보 개수 + 가장 유력 1개. 그리고 «쓰고 바로 닫는다» — 보고 뒤 더 하지 않는다.

## 금지 (하드)
- 원격 쓰기 0 · mini 에서 읽기 전용 명령만(rg·cat·sed·ps). Redis 쓰기 0 · 말풍선 DOM 주입 0 · 서버 재시작 0.
- BYZ `.env` 를 grep/cat 하지 않는다(훅 REJECT). env «이름»만 코드에서 모은다. 값은 어디에도 출력하지 않는다.
- `docs/multihost/h-plans/` 편집 0(상위가 한다). 이 브리프·결과 파일 외 편집 0 · 커밋 0(상위가 한다).
- 외부 호출 7초 룰: 명령 1개 7~20초 안에 끝나게(rg 범위를 좁힌다).
