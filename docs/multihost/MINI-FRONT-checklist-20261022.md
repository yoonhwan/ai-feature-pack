골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 첫 회차 전 mini 앞 오빠 손(원격으로 못 하는 것) 한 장. 정본 계획 `PLAN-mini-e2e-round1-20261022.md` §4-3.

# mini 앞 오빠 손 — 한 장 (약 8분 · mini 키보드 앞에서 한 번에)

> ★Chrome 정리는 필요 없다★ (2026-10-22 mini 실측): 지금 Chrome 은 17프로세스·약 2.1GB 로 줄어 있고 두 종류뿐이다 — ①오빠 평소 Chrome(`--no-startup-window`, 프로필 Default·1·3·4) ②agent-browser 의 헤드리스 Chrome(`--headless=new`, 도구용). 시험용 Chrome 은 **별도 프로필(`/tmp/chrome-byz-debug`)·별도 포트(9333)로 «추가로» 띄우므로** 위 둘을 닫을 이유가 없다. 오빠 개인 창·프로필은 건드리지 않는다.

## 먼저 (원격 `h` 로 끝나 있어야 하는 것)
`h378`(러너 venv) → `h379`(tts-say) → `h381`(서버: 이 h 가 38312·38314 에 서버를 띄움). 서버가 떠 있어야 6번 마이크 허용을 할 수 있다. (`h376`·`h377` 은 OCI 용이라 mini 앞 작업과 무관.)

> ★서버가 도는 동안 이 맥이 켜져 있어야 한다★ (결정 2026-10-22: 서버는 mini, DB 는 이 맥과 같은 dev DB). mini 서버의 DB 길 = 이 맥 loom 터널(127.0.0.1:38309)을 mini 로 되돌려 주는 ssh 포워딩 — 이 맥이 잠들거나 꺼지면 mini 서버는 DB 를 잃는다. 시험하는 동안 이 맥 잠자기 방지.

## 순서 (번호대로 · 각 줄 끝 = 확인 방법)
1. **[1분] 폴더 신뢰 «Yes»** — mini 터미널에서 폴더마다 한 번씩:
   `cd ~ && claude` → «Quick safety check: trust this folder?» 가 뜨면 **1. Yes, I trust** → `/exit`.
   같은 방식으로 `~/Project/BYZ-Agents` · `~/Project/ai-feature-pack` · `~/packs` (tmuxc 좌석을 여는 폴더들).
   확인: 같은 폴더에서 `claude` 를 다시 열면 질문 없이 바로 입력창이 뜬다.
   (왜: `tmuxc open` 이 열자마자 Enter 를 보내 기본값 «No, exit» 가 눌려 claude 가 꺼졌다 — 실측.)
2. **[1분] 출력 기본값** — 시스템 설정 → 소리 → **출력 = Multi-Output Device**(BlackHole 2ch + Mac mini 스피커) · **입력 = BlackHole 2ch**.
   확인(터미널): `system_profiler SPAudioDataType | grep -B6 "Default Output Device: Yes" | grep -E "^\s+[A-Za-z].*:$"` → Multi-Output Device 가 나오면 OK · `system_profiler SPAudioDataType | grep -B6 "Default Input Device: Yes" | grep -E "^\s+[A-Za-z].*:$"` → BlackHole 2ch.
   (왜: 러너가 `afplay` 로 말을 재생하면 «시스템 기본 출력장치» 로 나간다 — 장치 지정 인자 없음. 기본값이 BlackHole 쪽이어야 Chrome 마이크로 되돌아 들어온다.)
3. **[30초] Chrome 마이크 권한(macOS)** — 시스템 설정 → 개인정보 보호 및 보안 → 마이크 → **Google Chrome 켜짐**.
   확인: 목록에 Google Chrome 이 켜져 있다. (없으면 6번에서 팝업이 뜨며 생긴다.)
4. **[30초] 시험용 Chrome 띄우기** — mini 터미널에 한 줄:
   `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9333 --no-first-run --no-default-browser-check --user-data-dir=/tmp/chrome-byz-debug about:blank &`
   (headed 필수 · `--headless` 금지 — 정본 README §1.2. 시작 URL 은 `about:blank` 으로 충분 — 러너가 Chrome 을 직접 열지 않고 CDP 9333 에 붙어 필요한 탭을 직접 만든다(pi 실측 measured-runner-cli §3).)
   확인: `curl -s http://127.0.0.1:9333/json/version | head -c 100` → `Browser` 줄이 나온다.
5. **[30초] 서버가 떠 있는지 눈으로** — 새로 뜬 시험용 Chrome 주소창에 `http://127.0.0.1:38314/` → 로그인/홈 화면이 보이면 OK (h381 이 끝난 뒤).
6. **[1분] 마이크 허용 팝업 «허용» 1회** — 같은 창에서 실시간 통역 페이지(`/realtime` 계열)를 열고 마이크 권한 팝업이 뜨면 **허용**. 이 클릭은 «권한을 미리 주는 것» 이고 시험 증거가 아니다 — 증거는 러너의 trusted 클릭만.
   확인: 주소창 왼쪽 자물쇠 → 마이크 «허용».
7. **[30초] 마이크 신호 재확인(선택)** — `bash /tmp/aifp-mini-audio-check.sh` 또는 `docs/multihost/h-plans/mini-audio-check.sh` → 평균 > -50 dB (지난번 -37.3 dB).

## 끝나면
오빠는 상위(planner/desk)에 «mini 앞 끝» 한 줄만. 그 뒤 러너 실행 `h`(`h-mini-e2e-round1-run.sh`, pi 초안 중)를 발급받아 `! bash /tmp/h<N>` 한 줄.

## 막히면 (증상 → 말할 것)
| 증상 | 말할 한 줄 |
|---|---|
| 1번에서 질문이 안 뜨고 바로 입력창 | 이미 신뢰된 폴더 — 다음 폴더로 |
| 2번 목록에 Multi-Output Device 가 없음 | «Multi-Output 없음» (오디오 MIDI 설정에서 만들어야 함 — 알려 주면 순서 안내) |
| 4번 후 `curl` 이 비어 있음 | Chrome 이 안 떴거나 포트 충돌 — 터미널 출력 그대로 붙이기 |
| 5번에서 안 열림 | 서버 h381 이 안 끝남 — `bash /tmp/h381`(같은 인자)로 재확인 요청 |
