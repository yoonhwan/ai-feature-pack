# FACTS — 마이크 입력 vs 소리 직접 입력 · «머신당 1» 자원 실측 (ft-harness-arch#2 요청 · ft-harness-nano#1 실행 · 조각 P9)

> 측정 시각 **2026-10-05 18:25 KST** · 읽기 전용 · 수정·커밋 0 · **press·러너 실행 0**(grep·Read·ls·system_profiler 만).
> 산출 위치 = `design/teams/harness/issue-improvement/`. 원본 = `design/teams/harness/issue-improvement/facts-raw/H*.txt`.
> 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #57062 · 발주 = ops#3 ORDER-mic-vs-sound-input(#57059).

---

## H1. v65 press 가 소리를 넣는 경로 — 구성요소 사슬과 «머신당 1»

| 구성요소 | 사실(파일:줄) |
|---|---|
| 음원 재생 | `tests/e2e/realtime_multi_e2e.py:1331` `say -o` → `.aiff` → afconvert 정규화 · `:1368` 「`_verify_tts_output` 이 **afplay** 로 재생해 BlackHole 입력 유지」 · RMS 게이트 공용 `tts_rms_gate.py` |
| Chrome 이 소리를 받는 길 | FE `clients/web/src/domains/audio/pcm-capture.ts:52-71` `navigator.mediaDevices.getUserMedia({audio: audioConstraints})` → `createMediaStreamSource` → AudioWorklet `"pcm-capture"` |
| PTT/mic 클릭 | `realtime_multi_e2e.py:887-983` `_real_click_ws`/`_real_click` = **CDP trusted mouse** `Input.dispatchMouseEvent`(`:890` 「el.click()(isTrusted=false) 으로는 mic 권한 미해소」) |
| CDP 접속 포트 | `realtime_multi_e2e.py:8` 「CDP **9333** + BlackHole 인프라는 04 와 공유」 · `CDP_PORT`(:67) |
| 탭 개폐 규칙 | `_close_tab_by_url`(:3365) · `_close_host_tab`(:3387) · mbox 56743 「press 중 탭 개폐 0」 |

**[사실] 장치 수**(`system_profiler SPAudioDataType`): **BlackHole 2ch = 1개**(Input 2ch·Output 2ch) · **Multi-Output Device = 1개**(2ch) · MacBook Pro Microphone(1ch) · MacBook Pro Speakers · S32B80P(모니터 2). `SwitchAudioSource` 있음(`/opt/homebrew/bin`).
**[사실] «머신당 1» 가드/규칙**:
- `~/.claude/CLAUDE.md:191` 「★★**오디오 E2E는 동시 실행 불가** — BlackHole 루프백은 **시스템 전역 장치가 하나**라 두 테스트가 동시에 발화하면 오디오가 섞인다. Chrome CDP 탭도 같다 … ★"서버는 동시에, 오디오 press는 순차로"★」 · `:192` 「"포트가 막힘"과 "오디오가 막힘"은 다른 문제」.
- `tests/e2e/realtime_multi_e2e.py:180` xfail 「**BlackHole 단일 오디오 디바이스** — 동시 TTS 출력 충돌로 STT 인식 불가(인프라 한계)」 · `:28` 「speaker lock: P1 에서 realtime=완화 → 동시 발화 가능(turn-queue 없음)」.
- `~/.claude/CLAUDE.md:161`·`docs/rules/e2e_testing.md:14` trusted 클릭 항.

---

## H2. CCU 가 소리를 넣는 경로 — 어디로 · 어떤 형식 · 어느 계층부터 · 증거

| 항목 | 사실(파일:줄) |
|---|---|
| 러너 실체 | **Cloud Run Job**(`.worktrees/ccu-stress/design/ccu/` 도구군 + Job 이미지) · `CLOSEOUT-ccu-u-staircase-20261004.md:12` 「API 레벨 가입 > 테스트(**Cloud Run Job 분산 주입 · TTS 오디오 API 송신**)」 |
| 입력 형식 | `DESIGN-ccu-stress-infra.md:43` 「전송 형식 = **WAV(PCM 16 kHz mono s16le)**」 · `:50` 「mp3 → 16 kHz mono s16le PCM → WAV」 |
| 보내는 곳 | `DESIGN…:50` 「`POST /v5/audio_event`(`input_ref` · LST 창 누적 PCM ~1.1 s · 창 상한 20 s · silence_flush 800 ms) → release → `POST /v5/control_events`(ptt_release)」 = **gateway HTTP** |
| FE/Chrome 거치나 | **0** — `DESIGN…:50` 「재생·BlackHole·브라우저 **0**」 · `:63` 「FE 없음」 |
| 실제 증거 | `CLOSEOUT…:13` 「U 계단 **9회차**(200e4328d4) · 첫 위반 **N=4**」 · `:25` 「ccu-stress-gateway 00004-nk5 · ccu-stress-worker 00005-zps · Redis ccu-stress-redis 10.232.84.75 · 시간당 ~$0.25」 (2026-10-04) |
| CCU «머신당 1» | `DESIGN…:31` 「worker **max=1**·1 vCPU·1Gi — 클라우드 u 유력 상한」 · gateway max=5 · Redis `ccu-stress-redis`(10.232.84.75) · GPU `10.0.0.9`(dev worker 공유) |

**[추측]** CCU 는 **브라우저·마이크·BlackHole 없이 gateway HTTP 로 PCM 을 직접 주입** → 마이크 «머신당 1» 을 우회한다.

---

## H3. 두 경로가 시험하는 계층 차이

| 계층 | 마이크(v65) | CCU 소리직접 | 근거 |
|---|:--:|:--:|---|
| FE 마이크 캡처(getUserMedia) | **Y** | **N** | `pcm-capture.ts:52` vs `DESIGN…:50` 「브라우저 0」 |
| VAD·PTT 버튼 | **Y**(trusted 클릭) | **부분**(control_events 로 대체) | `_real_click` vs `DESIGN…:50` |
| FE→gateway 전송 형식 | **Y** | **Y**(직접 PCM/WAV) | `input_reference.py:59-63` 「PCM/WAV 만 수락」 |
| gateway | Y | Y | 동일 gateway |
| worker STT·LLM·TTS | Y | Y | `DESIGN…:100` 「로컬과 같은 레인」 |
| FE 렌더·말풍선 DOM | **Y** | **N** | `DESIGN…:63` 「FE 없음」 |
| poller 화면 축 | **Y** | **N** | CCU 화면 관측 없음 |

**[사실] 마이크 경로에서만 잡힌 사고**: `docs/rules/e2e_testing.md:14` 「(2026-06-13: 5d + token-cap lost here; detail `SPEECH_VAD_AUTOMATION.md` §②)」 — `isTrusted=false → getUserMedia 실패 → silent(speech_ms=0 / audio 0B)`.
**[사실] CCU 가 못 잡는 것**: `DESIGN-ccu-stress-infra.md:63` 「①A2「FE cover 시각」은 FE 없음 → «이벤트 수신 시각(SSE)» 으로 대체」.

---

## H4. 마이크 없이도 «머신당 1»로 남는 자원(= 병렬 상한 후보)

| 자원 | 지금 수 / 근거 | 늘릴 수 있나 | 머신당 1 |
|---|---|---|---|
| 포트 슬롯 | `38301~38399` 대역 · 실사용 예 `38301`(gateway)·`38303`(FE) — `docs/work/loom-domain-ops/BRIEF-T0-orgs-list.md:460-461` | 자리 만들면 됨(CLAUDE.md:192 「포트가 막힘」) | **아니오** |
| Redis | 로컬 `localhost:6379`(docker `byz-agents-redis-1`) · CCU 는 cloud `ccu-stress-redis`(10.232.84.75) | 키 네임스페이스 분리 여부 미확인(`DESIGN…:85` 미해결) | 로컬 **1** |
| 공유 vLLM/GPU | dev GPU **IAP 터널 1개** `:8001 → 10.0.0.9:8000`(`docs/rules/dev_scripts.md:9`) | VPC 내부 IP·터널 추가 가능하나 GPU 자원 1 | **1(dev GPU)** |
| Chrome CDP | `9333` **하나**(`realtime_multi_e2e.py:8` 「04 와 공유」) · `chrome_profile_pool.py` 프로필 다수 | 프로필 추가 가능·포트는 늘릴 수 있음 | 포트 1·장치 1 |
| STT 외부 API 요금/rate | `design/COST_BASE_REVIEW.md`(원가 베이스) | — | 요금 축 |
| `single_set_testing` | 같은 HEAD 세트 조건(`docs/rules/single_set_testing.md:24`) | — | 세트 1 |

**[추측]** 마이크를 빼도 **CDP `9333`(1 포트·1 Chrome)·로컬 Redis(1)·dev GPU 터널(1)** 이 «머신당 1» 로 남아 병렬 상한 후보다 — 오빠 가정(«머신당 1» 자원이 하나라도 남으면 상한)은 **성립**.

---

## H5. 3번째 후보 「디버그 재생 주입」 — FE 캡처 입구 사실

**[사실] FE 캡처 사슬**(`clients/web/src/domains/audio/pcm-capture.ts`): `:52` `getUserMediaWithFallback(true)`(주입 가능 prop) 또는 `:57` `navigator.mediaDevices.getUserMedia({audio:{channelCount:1, echoCancellation:false, noiseSuppression:false, deviceId?}})` → `:68` `new AudioContext` → `:70` `createMediaStreamSource(mediaStream)` → `:72` `AudioWorkletNode("pcm-capture")` → 다운샘플 → chunk/post.
→ **`createMediaStreamSource` 노드부터 «마이크와 공통»**.

| 주입 후보 | 건드리는 파일 수 · 재사용 | 사실/추측 |
|---|---|---|
| ⓐ MediaStream 대체 | **기존 seam 존재** — `pcm-capture.ts:52-53` `getUserMediaWithFallback` prop + `deviceId` 옵션 → 파일 1개·재사용 가능 | [사실] |
| ⓑ 오디오 그래프 입력 노드 교체 | `createMediaStreamSource`(:70) 를 `MediaElementSource`/`BufferSource` 로 교체 — pcm-capture.ts 그래프 수정(파일 1~2) | [사실] |
| ⓒ 브라우저 가짜 장치 | `--use-fake-device-for-media-stream` — **레포가 금지** `tests/e2e/chrome_profile_pool.py:8-9` 「리포 금지(`scripts/e2e/run_v5_prod_demo.sh:62-65`)는 `--use-fake-ui-for-media-stream` / `--use-fake-device-for-media-stream` 플래그다 — 실제 media-device 경로와 권한 표시기를 요구」 | [사실] |

**[추측] 가장 작은 곳 = ⓐ** (`getUserMediaWithFallback` 이 이미 주입 seam 으로 존재).
**[사실] 디버그 격리 수단**: `NEXT_PUBLIC_BUBBLE_DEBUG`(`bubble-debug-enabled.ts:7` · `v5-freeze-debug.ts:4`) · `NODE_ENV`(`speech-auth.ts:26`) — **오디오 주입 전용 플래그는 0**.
**[사실] 주입에서 빠지는 것**: 실제 장치 샘플레이트(코드가 네이티브 레이트로 캡처 후 다운샘플 — `pcm-capture.ts:63-67`) · `echoCancellation:false`/`noiseSuppression:false` 제약(`:57-59`) · 권한 프롬프트 · 장치 전환 이벤트.
**[사실] 기존 전례**: `tests/e2e/chrome_profile_pool.py`(프로필 권한 영속) · `tests/e2e/v5_prod_demo_scenarios.py` · `tests/e2e/solo_realtime_corpus/cdp_bubbles.py` · `tests/e2e/fanout_press_harness.py:95` — **재생 주입/mock mic 코드는 0**(fake-device 플래그는 금지됨).

---

## 회신 요약

- **못 한 항목**: 없음 — H1~H5 전부 실행(press/러너 실행 0). 숫자 미확정 2: Redis 키 네임스페이스 분리 여부(`DESIGN…:85` 미해결로 남아 있음) · COST_BASE rate 한도.
- **사실/추측**: [사실] 약 30항 / [추측] 4항 → **사실 ≈ 88% · 추측 ≈ 12%**.
- **두드러진 3**: ① v65 소리 = **say→afplay→BlackHole(1개·2ch)→getUserMedia** 사슬, CCU = **gateway HTTP 직접 PCM(브라우저 0)** ② 마이크를 빼도 **CDP 9333·로컬 Redis·dev GPU 터널이 머신당 1** 로 남아 병렬 상한(오빠 가정 성립) ③ 디버그 주입 **최소 = ⓐ MediaStream 대체**(`getUserMediaWithFallback` seam 이미 존재) — 브라우저 fake-device(ⓒ)는 **레포가 금지**.