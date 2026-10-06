# REQ — 마이크 입력 vs 소리 직접 입력 · «머신당 1» 자원 실측 (ft-harness-arch#2 → ft-harness-nano#1 · 2026-10-05 · 조각 P9)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
>
> 골의 축: 원문 7 「시험 병렬」. 발주 = ops#3 ORDER-mic-vs-sound-input(#57059). 오빠 원문: 「테스터가 하나로 줄을 세워야 되잖아요 … 마이크를 쓰는 것과 그냥 사운드를 입력하는 것을 비교 … CCU 테스트할 때 사운드 입력으로 진행해서 마이크가 필요 없었거든요 … 프로세스에 제한이 없으면 병렬로 테스트까지」 — ★오빠 가정은 검증 대상★: «머신당 1» 자원이 하나라도 남으면 그것이 상한이다.

읽기 전용 · 수정 0 · 커밋 0 · **press·러너 실행 금지**(grep·Read·ls·git log 만). 산출 `design/harness/issue-improvement/FACTS-test-input-parallel-20261005.md` + 원본 `facts-raw/H*.txt`. 측정 시각 1줄 · [사실]/[추측] · 「파일:줄」. 숫자에는 출처.

## H1. v65 press 가 소리를 넣는 경로 — 구성요소 사슬과 «머신당 1»
- `tests/e2e/realtime_multi_e2e.py`·`tcc8_completion_press.py` 에서: 음원 재생 방식(어느 명령·어느 출력 장치 — BlackHole 장치명 grep) · Chrome 이 소리를 받는 길(`getUserMedia` · 입력 장치 선택 코드 줄) · PTT/mic 클릭(`Input.dispatchMouseEvent` 줄 · `_real_click`) · CDP 접속 포트(`9333` 등) · 탭 개폐 규칙(「press 중 탭 개폐 0」 줄).
- 장치 수: `system_profiler SPAudioDataType` 또는 `SwitchAudioSource -a`(있으면) 로 BlackHole 장치 **개수·채널**(2ch/16ch) · Aggregate/Multi-Output 장치 유무.
- 러너 안 «머신당 1» 가드: 포트·탭·장치·락파일 grep(`lock`·`BlackHole`·`9333`·`Multi-Output`) — 줄 인용.
- 글로벌 규칙 원문 1줄 복붙: `~/.claude/CLAUDE.md` 「오디오 E2E는 동시 실행 불가」 항 + `docs/rules/e2e_testing.md` trusted 클릭 항.

## H2. CCU 가 소리를 넣는 경로 — 어디로 · 어떤 형식 · 어느 계층부터 · 실제 증거
- CCU 러너 실체(경로: `tests/ccu*`·`scripts/ccu*`·`.worktrees/ccu-stress*`·`design/ccu/` 에서 러너 파일명) · 입력 형식(PCM/wav/opus · 샘플레이트 · chunk 크기) · 보내는 곳(gateway WS/SSE 엔드포인트 or worker 직결 · URL/경로 줄) · FE/Chrome 을 거치나(0/1).
- 실제로 돌린 증거: `CLOSEOUT-ccu-*.md`·`DESIGN-ccu-stress-infra.md` 에서 N(동시 사용자 수)·회차·결과 1~2줄 인용 + 날짜.
- CCU 러너가 쓴 «머신당 1» 자원(있으면): 포트·Redis 키 접두·vLLM/GPU 엔드포인트 — 줄 인용.

## H3. 두 경로가 시험하는 계층 차이
- 표: 계층(FE 마이크 캡처 getUserMedia / VAD·PTT 버튼 / FE→gateway 전송 형식 / gateway / worker STT·LLM·TTS / FE 렌더·말풍선 DOM / poller 화면 축) × (마이크 경로 통과? / CCU 소리 직접 경로 통과?) — 각 셀 Y/N + 근거 줄.
- 마이크 경로에서만 잡힌 사고 이력 2~3건(troubleshoot·archives grep: `isTrusted`·`speech_ms=0`·`0B`·`무음`·`hidden`) — 날짜·파일.
- CCU 경로가 잡지 못한 것 1~2건(DESIGN-ccu 「FE 없음 → 대체」 류 줄).

## H4. 마이크 없이도 «머신당 1»로 남는 자원 목록(= 병렬 상한 후보)
- 포트 슬롯(`38301~38399` · 워크트리당 3 → 최대 몇 세트) · Redis(컨테이너 수 · 키 네임스페이스 분리 여부) · 공유 vLLM/GPU(엔드포인트 수 · 동시 요청 한계 문서 줄) · Chrome CDP(`9333` 하나? 프로필 수) · STT 외부 API 요금·rate limit(COST_BASE_TABLE 줄) · `single_set_testing`(같은 HEAD 세트 조건) — 각 항목: 지금 수 · 늘릴 수 있나(코드/문서 근거) · 「머신당 1」 여부.

## H5. 3번째 후보 「디버그 재생 주입」 — FE 캡처 입구 사실 (오빠 보강 #57060)
- FE 마이크 캡처 코드(Next.js `web/`·`realtime` 쪽: `getUserMedia` grep): 호출 파일:줄 · 그 뒤 오디오 그래프 사슬(`AudioContext`·`MediaStreamSource`·`AudioWorklet`/`ScriptProcessor`·VAD·인코더·WS 전송) — **어느 노드부터 «마이크와 공통»인가** 파일:줄 사슬 5줄 이내.
- 주입 지점 후보 3 각각 코드 변경 범위: ⓐ MediaStream 대체(`getUserMedia` 결과를 재생 스트림으로 교체) ⓑ 오디오 그래프 입력 노드 교체(`MediaElementSource`/`BufferSource` 연결) ⓒ 브라우저 가짜 장치(Chrome `--use-fake-device-for-media-stream --use-file-for-fake-audio-capture` · 러너 launch 인자에 지금 있나 grep) — 각각 「건드리는 파일 수 · 기존 코드 재사용 가능 여부」 [사실] · 가장 작은 곳 [추측 표기].
- 디버그 전용 격리 수단 실재: `NEXT_PUBLIC_*DEBUG*`·`NODE_ENV`·feature flag·`?debug=` 쿼리 grep — 있으면 파일:줄 · 없으면 「0」.
- 마이크 경로에만 있고 주입에서 빠지는 것: 실제 장치 샘플레이트(코드가 가정하는 Hz) · `echoCancellation`/`autoGainControl`/`noiseSuppression` 제약 값(getUserMedia constraints 줄) · 권한 프롬프트 · 장치 전환 이벤트 — 코드 줄 인용.
- 기존 전례: 레포에 이미 「재생 주입」·「fake audio」·「mock mic」 류 코드·문서가 있나(grep `fake-device`·`fake_audio`·`inject`·`mock.*mic`) — 파일명.

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율.
