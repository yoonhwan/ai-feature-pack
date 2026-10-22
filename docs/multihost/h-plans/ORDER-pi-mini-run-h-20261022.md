골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 첫 회차 «마이크 trusted 클릭 → 녹음 시작 → STT 최종본 1건» 을 mini 에서 돌리는 러너 실행 h. 정본 계획 `docs/multihost/PLAN-mini-e2e-round1-20261022.md` §4-4~5.

# 발주 — pi: ① 러너 진입점·인자 실측(읽기) ② h-mini-e2e-round1-run.sh 초안 (실행 0)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · BYZ 원본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`(읽기만 · `.env` 열지 않음) · 시험 sha `33335c7a353e09f17cc9048e3989e4e8b5d9a05a` 기준 파일을 읽을 것(`git -C … show 33335c7a:tests/e2e/realtime_multi_e2e.py`).
산출: `docs/multihost/measured-runner-cli-20261022.md` + `docs/multihost/h-plans/h-mini-e2e-round1-run.sh`.

## ① 실측(줄번호 인용, 추측 금지)
1. 러너 CLI: `realtime_multi_e2e.py` 의 argparse(≈4795 부근) 전체 옵션·기본값. «1회차(마이크 한 번 눌러 STT 최종본 1건)» 를 가장 작게 돌리는 옵션 조합(시나리오 이름·턴 수·`--engine say`·`--play` 등)을 찾아라. 시나리오는 `multi_realtime_corpus/scenarios/*.jsonl` 에서 가장 짧은 것 1개.
2. 러너가 Chrome 을 직접 여나, 이미 열린 탭(`realtime.html?debug`)을 기대하나. CDP 9333 에 붙은 뒤 어떤 URL 을 이동·클릭하나. 로그인/토큰 흐름(host=로그인 token 無 · guest=?token) 과 `BYZ_E2E_JWT_SECRET` 쓰임.
3. 서버 주소 지정: `BYZ_WEB_BASE`·`BYZ_GATEWAY_BASE`·`BYZ_WEB_PORT`·`BYZ_GATEWAY_PORT`·`CDP_PORT` 의 우선순위. mini 서버 h(h381)는 gateway=127.0.0.1:38312, web=127.0.0.1:38314 로 뜬다. 러너가 ws/sse 주소를 BASE 에서 파생하는지, 따로 하드코딩한 곳(8080·3001 등)이 있는지 grep 해서 줄번호로.
4. 결과/로그가 어디에 남나(stdout·파일·`BYZ_WORKER_LOG` 기본 `/tmp/byz-worker.log` — mini 에서는 worker 로그가 `/tmp/h-byz-worker.log` 이므로 경로 맞추는 방법). 성공 판정 줄(어떤 문자열이 «STT 최종본 1건» 이고 exit code 가 무엇).
5. 선행 조건 자체 검사(ready-check·preflight)가 러너에 내장돼 있나. 오디오 장치 확인을 러너가 하나.
6. **하드 룰 11 위반 가능 경로 표시**: 러너 옵션 중 Redis 에 직접 쓰거나 DOM 에 말풍선을 주입하는 옵션/모드가 있으면 이름과 줄번호를 «쓰지 말 것» 으로 따로 적는다.

## ② h-mini-e2e-round1-run.sh (이 맥에서 오빠가 `! bash /tmp/h<N>` 로 실행하는 단일 스크립트 초안)
틀 = `h-mini-byz-server.sh`(ssh mini 별칭 · `ms()` 는 PATH 접두 · rc 규칙 · 외부 호출 단건 70초 천장 · 비밀 값 출력 0). **zsh 함정**: mini 원격 문자열에서 `-t =이름` 은 반드시 따옴표 안, 변수명 `status`·`path` 금지.
1. 사전점검(전부 읽기): mini 서버 3개 health(gateway 38312 `/health`, web 38314 `/`) · CDP 9333 LISTEN · Chrome 에 `realtime.html` 탭이 있는지(`curl 127.0.0.1:9333/json`) · BlackHole 장치 보임 · `tts-say` 존재 · 러너 venv python(`~/Project/BYZ-e2e/.venv/bin/python` 또는 서버 h 가 만든 `~/Project/BYZ-Agents/.venv` — 어느 쪽이 맞는지 ①의 import 요구와 비교해 결정) · **다른 오디오 회차가 돌고 있지 않은지**(러너/`afplay`/`say` 프로세스 0 — 오디오 press 는 한 번에 하나). 하나라도 틀리면 rc=2 + 오빠가 할 일 1줄.
2. 실행: 러너 진입점은 ①의 결론. `BYZ_E2E_JWT_SECRET` 은 이 맥 BYZ `.env` 에서 이름만 골라 ssh **stdin** 으로 주입(명령줄·mini 디스크 0 — 방식은 h-mini-byz-server.sh 4단계와 같게). 로그인 셸 + `PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"`. 러너는 ★기존 러너 그대로(trusted `Input.dispatchMouseEvent`)★ — 클릭 대체·DOM/Redis 주입 코드를 새로 쓰지 않는다. 총 실행 상한은 러너가 정한 시간 + 여유(상한을 스크립트에 명시, 넘으면 러너만 종료 — 러너가 연 프로세스 pid 만).
3. 결과: stdout 을 mini `~/Project/BYZ-Agents/.h-run-<ts>.log` 에 저장(0600) 하고 끝 40줄 + ①-4 의 성공 판정 줄을 화면에 출력. 판정: 성공 문자열 있음 → rc=0 / 러너 실패 → rc=5 + 로그 경로.
4. 증거 3줄(보고용): 성공 판정 줄 원문 · `hostname`=BYZs-Mac-mini 줄 · 서버 RSS 한 번 더(h381 의 표 방식).

## 검증 (네가 하는 것까지)
`bash -n` · 참조 경로 `test -e` · `grep -nE 'Redis|redis-cli|appendChild|innerHTML|dispatchEvent' h-mini-e2e-round1-run.sh` 0 (하드 룰 11) · 비밀 echo 0 · 포트 38312/38314 외 기본 포트 0 · `-t =` 가 따옴표 밖에 0.

## 끝
산출 2개 경로 + 검증 4줄을 `aifp-multihost-master-claude#1` 에 mbox. 좌석은 닫지 말고 대기.
