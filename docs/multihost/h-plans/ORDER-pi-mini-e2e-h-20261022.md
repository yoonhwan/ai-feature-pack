골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 첫 회차 계획 `PLAN-mini-e2e-round1-20261022.md` 의 ① «mini 에 러너 코드 배치» h 초안.

# 발주 — pi: h-mini-e2e-setup.sh 초안 (쓰고 bash -n 후 보고 · 실행 0)

작업 폴더: `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 산출 `docs/multihost/h-plans/h-mini-e2e-setup.sh` + 러너 import 폐쇄 목록 `docs/multihost/measured-runner-closure-20261022.md`. 틀은 `h-mini-ops.sh` 를 그대로(ssh mini 별칭 · rc 규칙 · 대화형 0 · 비밀값 출력 0 · 외부 호출 단건 70초 천장).

## 할 일
1. **import 폐쇄 실측(이 맥 읽기)**: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/tests/e2e/realtime_multi_e2e.py` 가 import·`sys.path`·`subprocess`·상대경로로 부르는 파일 전부(cdp_helper.py 등 · 데이터·음원 파일 포함)를 목록으로. 러너가 repo 루트 구조(`.worktrees/…`·`mr_preflight.sh` 상대경로)를 가정하는 곳은 «가정 위치»로 표시.
2. **h 초안**: 위 폐쇄 파일만 `rsync -a --files-from` 으로 mini `~/Project/BYZ-e2e/`(repo 와 같은 상대 구조)에 배치 + `python3 -m pip install --user websockets` (mini python 3.9.6) + 배치 후 `python3 -c "import …"` 로 러너 import 확인 + 사후 점검(파일 수·sha 목록). 원본 BYZ repo 는 건드리지 않는다(읽기만). 비밀 파일(.env·키)은 폐쇄에 들어와도 «복사 제외 + 경고 줄» — JWT 비밀은 별도 경로(op develop)이므로 이 h 가 옮기지 않는다.
3. 검증: `bash -n` · 참조 경로 `test -e` · `grep -nE 'read |sudo |\[Y/n\]'` 0 · 비밀 echo 0.

## 끝
산출 파일 2개 경로 + 검증 3줄을 `aifp-multihost-master-claude#1` 에 mbox. 좌석은 닫지 말고 대기.
