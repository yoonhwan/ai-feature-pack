골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 발주서 트랙 2-3 (mini 에서 기존 e2e 러너가 돌 조건 목록). 이 발주는 «읽기 전용 실측» 이다.

# 발주 — pi: mini 읽기 전용 실측 (결과 파일 1개 · 원격 쓰기 0)

접속은 `ssh mini` 만(사용자 이름·IP 쓰지 않음). 모든 원격 명령은 읽기 전용 · 상한 70초 · 앱 실행 0(Chrome 을 띄우지 않는다 · 경로·버전만) · 비밀 값 출력 0.
산출: `docs/multihost/measured-mini-e2e-prereq-20261022.md` (표 하나 + 명령 원문 + 결과 원문 줄). 모르는 칸은 «못 봄 + 이유» — 지어내지 않는다.

## 확인할 8가지 (각 줄 = 항목 · 명령 · 결과 원문)
1. BYZ 리포 유무: `~/Project` 아래 `BYZ-Agents` 또는 `tests/e2e/realtime_multi_e2e.py` 가 있는 폴더 (`find ~ -maxdepth 4 -name realtime_multi_e2e.py 2>/dev/null`). 없으면 «없음» (이 맥 경로: /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents — 러너 진입점 `tests/e2e/realtime_multi_e2e.py`).
2. Chrome: 실행 파일 경로·버전(`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version`) · 현재 떠 있는 Chrome 프로세스 수 · `--remote-debugging-port` 로 뜬 것 유무 · 9222 포트 LISTEN 유무.
3. BlackHole 2ch · Multi-Output 현재값: `SwitchAudioSource -c -t input`, `-c -t output`, `-a`.
4. 런타임 버전: python3 · node · uv · pip(pytest·websockets·aiohttp 등 러너가 import 하는 모듈 유무는 `python3 -c "import …"` 로).
5. 디스크 여유 `df -h ~` · 메모리 `vm_stat | head -5` · swap.
6. 러너가 붙는 서비스 주소: 러너 소스(이 맥 파일, 읽기)에서 FE·gateway·worker URL 을 어떻게 받는지(환경변수 이름·기본 포트)만 뽑아 적는다. mini 에서 그 주소에 닿으려면 어디로 터널/접속해야 하는지 후보 2개(예: 이 맥 tailnet 주소 직접 · mini 로컬 기동).
7. 마이크 권한: `tccutil` 은 쓰지 말고 읽기만 — 못 보면 «MIC_UNVERIFIED 유지(mini 터미널 앞 확인)».
8. 화면 상태: 로그인 세션(콘솔 사용자 = byz)·화면 잠금·디스플레이 sleep 여부(`pmset -g | grep -E "sleep|displaysleep"`, `stat -f%Su /dev/console`).

## 끝
`bash` 로 새 파일을 쓰는 것은 이 맥 워크트리의 위 산출 파일 1개뿐. 끝나면 파일 경로 + 막힌 항목 수를 `aifp-multihost-master-claude#1` 에 mbox 로 보고 (좌석은 닫지 말고 대기 — 상위 지시).
