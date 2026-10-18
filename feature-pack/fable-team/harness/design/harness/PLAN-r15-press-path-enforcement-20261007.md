# PLAN — R15 press 경로 강제 (arch#6 안 · 2026-10-07 · 미커밋)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(v65 master#145 #59389 · 보강 #59404 · 오빠 원문 「bts 와 poller 없이 press 하는 tester·checker 세션은 없어야 한다」 · 나노 press 금지 = single_set_testing).

## 결론
승인 — 강제 지점은 ★Bash 훅이 아니라 press «라이브러리» 안★(tests/e2e/cdp_helper.py 의 PTT 누름) + press 게이트 허가 파일 + 직전 회차 BTS 표 검사. 이유 한 줄: 사고 좌석이 codex 라 Claude PreToolUse 훅은 애초에 안 돌았고(codex 는 pre-tool 훅 자체가 없음), ad-hoc 스크립트도 결국 같은 cdp_helper.cdp_mouse_press 를 import 해서 눌렀다 — 두 에이전트·두 경로가 모두 지나가는 자리는 거기 하나다.

## 실측 (전제 — 바이트로 확인)
1. 사고 스크립트 = .worktrees/v65-m5-spectrum-v14-live-bands-vad-visible/scratchpad/qa-water-v15/press.py(45행 · gitignore 된 scratchpad): CDP_PORT=9348(기본 9333 아님) · sys.path 에 tests/e2e · cdp_helper 의 cdp_mouse_press/cdp_mouse_release/cdp_eval + tts_rms_gate.verify_tts_audio(afplay) import · ptt-control-left 누름 · poller 0 · 증거는 /tmp. (증거 커밋 249c8a0046 은 스크린샷 1장뿐.)
2. cdp_helper.py 894행 `def cdp_mouse_press(selector, url_match=…)` → _dispatch_mouse → Input.dispatchMouseEvent. 셀렉터를 받는다(PTT 판별 가능). 호출 러너: realtime_e2e · lecture_baseline/multi · s4_typing_churn · bts_strong_harness · test_press15_recording_admission(pytest) 등.
3. poller_dom 을 띄우는 러너는 tcc8_completion_press.py 하나뿐(4483~4504행 Popen · OUT=EVID/poller_dom.jsonl). ★realtime_multi_e2e.py 는 poller_dom 을 안 띄운다★(BYZ_BTS_DOM_JSONL 이 있을 때 스냅 append 만 · 1758행).
4. ft-press-gate.sh: 통과 0/막힘 1 · 파일 안 씀 · ①~⑥ 검사 · ★러너도 다른 코드도 게이트를 부르지 않는다★(tcc8·multi 에 ft-press/permit grep 0). ft-press-permit.sh 는 허가 파일 조작만 · 호출자 0. 라이브 RT(v6-realtime-live/.fable-team/bin) 게이트는 ⑥ 없음 · baseline-check·permit 스크립트 없음 = R9 미동기.
5. 「press 진행 중」 표지 0(lock·env·permit id 없음). 보이는 건 poller_dom.py 프로세스(env PTT_WS·OUT)와 EVID 폴더뿐.
6. 정본 충돌: SEATBELT-README 211행 규칙 15 「press 를 쏜 나노가 그 회차의 tester·checker」 ↔ TESTER-BRIEF-TEMPLATE 43행 「오케·나노는 press 하지 않는다」 ↔ 오빠 10-02 single_set_testing(나노 press 금지). 211행이 stale.
7. ft-nano-spawn.sh 209행 BODY 에 press·러너·poller 문구 0.

## ① 강제 지점 비교
| 후보 | codex 좌석 | ad-hoc 스크립트 | 거짓 차단 | 판정 |
|---|---|---|---|---|
| PreToolUse Bash 훅(cdp·dispatchMouseEvent·9333 패턴) | ✗ 안 돈다(codex pre-tool 훅 없음) | 명령줄에 패턴이 안 보인다(python press.py) | 러너 실행도 걸림 | 반려 |
| ft-press-gate 확장만 | 부르는 사람만 걸림 | 안 부르면 그만(지금 호출자 0) | 낮음 | 단독으론 반려 — 허가 «발급자» 로만 씀 |
| ★cdp_helper PTT 누름 안 검사 + 게이트 허가 파일★ | ✓ | ✓(같은 helper import) | 셀렉터·진입점으로 좁힘 | ★채택★ |
| 나노 발주 템플릿 고정 | 선언 | 선언 | 0 | 보조(문구 · 강제 아님) |
- 못 막는 것(범위 밖 · 명시): helper 를 안 쓰고 CDP websocket 을 직접 짜는 스크립트. 사고는 «helper 재사용» 형태였고, 직접 구현은 우발이 아니라 의도라 이 안의 위협 모델 밖.

## ② 게이트가 볼 수 있는 값 / 못 보는 값 (#59409 요청)
| 시점 | 볼 수 있다 | 못 본다 |
|---|---|---|
| 발사 전(ft-press-gate · 러너 시작 전) | 부른 좌석 이름·역할(TMUX_PANE→세션명) · 서비스 기동시각·HEAD(②③) · 러너·worker HEAD 일치(⑤) · 카드 baseline(⑥) · 이 좌석의 «직전 회차» 증거 폴더와 그 BTS 4축 표가 채워졌나 · 이번 증거 폴더 선언 | poller 프로세스(러너가 띄운다 — 아직 없다) · 서버 세션 sid(R11 한계와 같음) · 이번 회차 BTS 내용(아직 안 생김) |
| 첫 PTT 누름 순간(cdp_helper 안) | 진입 스크립트(sys.argv[0])가 리포 추적 파일 tests/e2e/*.py 인가 · 좌석 역할 · 허가 파일(좌석·HEAD 일치) · poller pid 생존 + OUT 파일 실재(러너가 env 로 내려 준 값) · CDP 포트 | DOM 이 실제로 기록되는지(첫 스냅 전) · 오디오가 BlackHole 로 갔는지 |
| 회차 뒤(ft-checkpoint · 다음 게이트) | BTS 4축(아키 문서·코드·로그·화면) + 시간 칸이 채워졌나 · poller_dom.jsonl 줄 수 | — |
- ★「BTS 산출물이 없으면 press 를 못 한다」 = «직전 회차 표가 안 채워졌으면 다음 허가가 안 나온다»★ — 이번 회차 표는 press 뒤에만 생기므로 «이번 것» 은 발사 전에 볼 수 없다. 첫 회차는 빈 골격(4축+시간 칸) 파일 선언만 요구.

## ③ 좌석 역할 판별
- 값: 프로세스 env TMUX_PANE → `tmux display-message -p -t $TMUX_PANE '#{session_name}'` → ft-name-lint 규칙의 역할 토막(byz-<팀>-<역할>-<에이전트>#N · 옛 ft-v65-<역할>-…#N 도 같은 위치).
- 허용 = tester · checker 만. nano · temp(옛 나노 이름 — 사고 좌석) · 그 밖 · 이름 lint REJECT · TMUX_PANE 없음 = ★거부(fail-closed)★.
- 사람(오빠) 직접 press: `BYZ_PRESS_HUMAN=1` 명시 + stderr ERROR 배너 + 증거 폴더에 human.txt — #0 RULE 예외 3조건(명시 플래그·ERROR 로그·눈에 보이는 경고). 좌석 세션 안에서 이 플래그가 켜져 있으면 거부(좌석이 사람 행세 금지).
- codex·claude 무관(둘 다 tmux pane 자식이라 TMUX_PANE 상속 · 실측 필요 항목 = codex 의 셸 도구가 env 를 넘기는지 1회 확인 → 카드 V 완료 조건).

## ④ 거짓 차단 방지
- 검사는 PTT·마이크 셀렉터일 때만(기본 정규식 ptt|mic|record · v65 가 목록 확정) — 일반 UI 클릭·캡처는 무검사.
- 진입점 허용 = «리포에 추적된 tests/e2e/*.py» (git ls-files) — 러너 목록을 유지할 필요 없음 · scratchpad·/tmp 스크립트는 자동 거부.
- pytest(test_press15_recording_admission 등): 검사를 끄는 env 를 두지 않는다 — 그 시험이 진짜 CDP 를 치면 그것도 press 다. 목으로 치면 검사 함수에 픽스처(가짜 허가·가짜 pid)를 주입하는 시험용 인자로(카드 V 에서 시험 1건씩).
- ★multi 러너는 poller 를 안 띄운다(실측 3)★ → 이 규칙대로면 realtime_multi_e2e press 도 막힌다. 이건 오빠 원문 그대로의 결과(「poller 없이 press 없음」) — v65 선택지: multi 에 tcc8 의 poller 기동 블록 이식(권고) 또는 press 러너를 tcc8 로 일원화. ★v65 arch 결정 사항★(오빠 값 재요청 불요).

## ⑤ 카드 구성 (순서 · 파일 겹침)
| 순서 | 카드 | 주체 | 파일 | 겹침 |
|---|---|---|---|---|
| 0 | R9 동기 | v65 랜딩 → master 키트·라이브 동기 | ft-press-gate.sh(⑥) · ft-press-baseline-check.sh | 아래 H 의 base |
| 1 | H r15-gate-permit | 하네스 나노 | ft-press-gate.sh(추적본·키트) · ft-press-permit.sh · tests/harness 시험 | R9 뒤 |
|   | ⑦ 부른 좌석 역할 tester·checker 아니면 막힘 1 · ⑧ 이 좌석 직전 허가의 증거 폴더 BTS 표 4축+시간 칸 비면 막힘 · 통과 시 허가 파일 .fable-team/state/press-permits/<좌석>.json {seat, role, runner_head, card, evid, ts} 발급(이전 허가는 같은 파일 덮기 — 이력은 .log 1줄 append) | | | |
| 2 | V r15-helper-check | ★v65 소관★(tests/e2e = v65 코드 · 랜딩 주체 v65) — 설계 전달만 | cdp_helper.py(PTT 누름 첫 호출 검사) · tcc8(poller 기동 뒤 env BYZ_PRESS_POLLER_PID·BYZ_PRESS_POLLER_OUT export) · realtime_multi_e2e(④ 결정대로) | R11 반송(tcc8 탭 재사용)과 같은 파일 — v65 가 순서 결정 |
| 3 | T 문구 | 하네스 나노(nano-spawn BODY) + arch 초안(TESTER-BRIEF) + v65(SEATBELT 211행) | ft-nano-spawn.sh BODY 1문장 「press 금지 — 물리 차단됨 · 시험은 단위·캡처」 · TESTER-BRIEF 「press = 러너 + 허가 + poller + 직전 BTS 표」 · SEATBELT 211행 규칙 15 정정 | nano-spawn 은 지금 진행 카드 없음 |
- 닫는 증거(전체): ①나노 좌석에서 tcc8 실행 → 첫 PTT 에서 거부(역할) ②tester 좌석에서 scratchpad 스크립트 → 거부(진입점) ③tester 좌석 tcc8 + 허가 + poller → 통과 ④직전 BTS 표 빈 상태에서 게이트 → 막힘 — 4건 모두 오디오 없이(가짜 CDP·가짜 tmux)로 재현.
- 되돌림: 허가 검사는 cdp_helper 의 함수 하나 · 게이트 ⑦⑧ 은 단계 추가 — 각각 revert 1커밋.
