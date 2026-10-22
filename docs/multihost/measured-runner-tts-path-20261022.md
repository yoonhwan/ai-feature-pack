# 러너 TTS 경로 실측 — mini 에 `sag`·`tts-say`·`sox` 가 없을 때 (2026-10-22)

> 작성: `aifp-pi-master-pi#0` · 발주 #3122 · **읽기 전용**(코드 수정 0 · 원격 쓰기 0)
> 대상: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/tests/e2e/realtime_multi_e2e.py` · `tests/e2e/tts_rms_gate.py`
> mini 실측(오늘): `sag`·`tts-say`·`sox` **없음** · `say`·`afplay`·**`afconvert`**·`afinfo` 있음 · `say -v "?"` 에 ko_KR 계열 **9건** 있음

---

## ① 발화 엔진 선택 옵션 — 있다. 다만 «say 만으로 도는 경로» 는 **없다**

### 선택 지점
| 위치 | 줄 | 내용 |
|---|---|---|
| CLI 인자 | **4795** | `p.add_argument("--engine", choices=["say","sag"], default="say", help="발화 엔진 (say=macOS TTS, sag=ElevenLabs)")` |
| 함수 기본값 | **1326** | `def _speak(sentences, lang, rate=180, pause_s=1.0, voice=None, engine="say")` |
| 분기 | **1333** | `if engine == "sag": … else: …` |

- **환경변수로 엔진을 고르는 코드는 없다**(`os.environ` 로 engine 을 읽는 곳 0 — `grep 'environ.*ENGINE'` 0건). env 로 바꿀 수 있는 것은 **RMS 임계값**(`BYZ_TTS_RMS_GATE`, tts_rms_gate.py:41) 뿐.
- `voice` 는 인자/`TTS_VOICE_MAP`(93-97: ko→`Yuna`, en→`Samantha`, …)로 정해지고, `--engine say` 면 `rate` 도 쓴다.

### 두 엔진의 실체 (핵심)
| engine | 실제 실행 | mini 에서 |
|---|---|---|
| `sag` | **1352-1355**: `subprocess.run(["sag","speak","-v",sag_voice,"-o",audio_path,"--play", s], check=True)` · 그 전 **1348-1350** 에서 `shutil.which("sag") is None` → **`RuntimeError("sag CLI not found on PATH …")`** | ❌ 즉시 raise |
| `say` | **1369-1372**: `subprocess.run(["tts-say","speak","--engine","say","-v",say_voice,"--say-rate",str(rate),"--output",audio_path, s], check=True)` | ❌ `tts-say` 없음 → **FileNotFoundError** |

★**say 엔진도 `tts-say` 를 거친다**★ — 러너는 raw `say` 를 직접 부르지 않는다(이 파일에 `subprocess.run(["say"` 0건). 즉 **mini 에는 `tts-say` 설치가 필요**하다.
- 참고: `tts-say` 는 **파이썬 단일 스크립트**(`~/.local/bin/tts-say`, `#!/usr/bin/env python3`)이고, 그 say 엔진은 내부적으로 `say -v <voice> --rate … -o <output>` 을 만든다(tts-say:143-149 · 198). 즉 «순수 say 로 대체» 는 **코드 수정 없이는 불가**(러너가 문자열 `"tts-say"` 를 하드코딩).
- raw `say` 를 쓰는 다른 드라이버는 있다(`spike_v5_e2e.py:232`, `v5_backend_e2e.py:249` — `check=False` 로 무음 통과 위험) 그러나 **이 러너(`realtime_multi_e2e.py`)는 아니다**.

### 결론(①)
- 옵션은 `--engine say|sag` 하나뿐 · 기본 `say` · **env 로 못 바꾼다**.
- mini 에서 발화를 하려면 **`tts-say` 를 설치**(say 경로)하거나 **`sag` 설치**(sag 경로) 중 하나가 필수. `say`·`afplay` 만으로는 **발화 단계에서 반드시 죽는다**(무음 통과 아님 — raise).

---

## ② `sox` 가 없으면 RMS 게이트는 — **죽지 않는다. `afconvert` 로 통과한다**

`tts_rms_gate.py` 의 `rms_of_file()` (100-160) 순서:

| 순위 | 줄 | 조건 | sox 없을 때 |
|---|---|---|---|
| 1 | **114-131** | `if shutil.which("afconvert") is not None:`(114) → `afconvert -f WAVE -d LEI16`(119) 로 변환 후 16-bit 샘플 RMS | ✅ **여기서 끝난다** |
| 2 | **134-152** | `rms is None` 일 때만 `sox = shutil.which("sox")`(**136**) → `if sox is not None:`(**137**) → `sox … -n stat`(**138**) · sox 자체가 없으면 **이 블록을 그냥 건너뛴다** | 건너뜀 |
| 3 | **154** | `if rms is None:`(153) → `RuntimeError("[tts_rms_gate] 측정 불가 — afconvert 도 sox 도 없음")`(**154**) | afconvert 가 있으므로 **발생 안 함** |

- **mini 에 `afconvert` 있음**(실측 `/usr/bin/afconvert`) → **sox 0 이어도 RMS 게이트 정상**.
- 게이트 자체는 **엄격**(`verify_tts_audio`):
  - 111·119-126 등: 측정 실패는 `RuntimeError`(**None 반환 없음**)
  - 157-161: RMS 가 0..1 밖이면 `RuntimeError`
  - **182**: `if rms < gate:` → `RuntimeError("TTS silent output …")` · `RMS_MIN = float(os.environ.get("BYZ_TTS_RMS_GATE","0.01"))`(**41**)
  - **189-190**: `play=True` 면 `afplay` 없을 때 `RuntimeError`(**189**) · 재생 `subprocess.run(["afplay", …])`(**190**) — **mini 에 afplay 있음** ✓
- ⚠ `--play`(기본 True) 재생은 **sag 경로는 `--play` 플래그로 sag 가 직접 재생**(1353-1354), **say 경로는 게이트가 `afplay` 로 재생**(193). 둘 다 «파일 저장만 하면 소리가 안 나간다» 를 막는 장치다.

### 결론(②)
**sox 없어도 죽지 않는다**(afconvert 우선). 단 «afconvert 도 sox 도 없는» 환경이면 153-154 에서 raise. mini 는 해당 없음.

---

## ③ BlackHole 로 소리가 나가는 방식 — **`afplay` = 시스템 기본 출력장치 재생 · SwitchAudioSource 불필요**

- say 경로의 재생은 `subprocess.run(["afplay", audio_path], check=True, timeout=120)` (**tts_rms_gate.py:190** · 없으면 189 에서 raise). `afplay` 는 **기본 출력 장치**로 재생한다 — 장치 지정 인자가 없다.
- 따라서 **시스템 기본 출력 = `BlackHole 2ch`(또는 Multi-Output Device)** 여야 BlackHole 입력으로 되돌아 들어간다. sag 경로도 `--play` 로 같은 기본 장치를 쓴다.
- `SwitchAudioSource` 는 **재생에 필요 없다** — 쓰임은 «현재 장치 읽기/바꾸기» 이고, 러너 코드에는 등장하지 않는다(`grep -c SwitchAudioSource realtime_multi_e2e.py tts_rms_gate.py` = 0).
  - 즉 오늘 실측에서 `SwitchAudioSource` 가 없어 «현재 선택값을 못 봤다» 는 것은 **판독 도구 부재**였고, **재생 자체와는 무관**하다.
- 실제 검증은 README 하드룰(§1.3): Output·Input 을 `BlackHole 2ch`(또는 Multi-Output) 로 두고 `say "테스트"` → Chrome mic 레벨 상승. **이건 사람이 System Settings 에서 1회 맞춰야 하는 부분**(코드로 못 함).
- mini 오디오 실측(오늘): `BlackHole2ch.driver` 존재 · 장치 목록에 `BlackHole 2ch`·`Multi-Output Device` 있음 ✓ (선택값만 미확인).

### 결론(③)
`afplay` 가 **기본 출력장치**로 재생 → **출력 기본값을 BlackHole 2ch(또는 Multi-Output)로 맞추는 것**이 조건. `SwitchAudioSource` 설치 불필요(설치한다면 «선택값 읽기/자동화» 용도일 뿐).

---

## 요약 — mini 이관 시 «발화가 도는 최소 조건»

| 필요 | 이유(줄) | 현재 mini |
|---|---|---|
| **`tts-say`** (또는 `sag`) | 1369-1372 하드코딩(또는 1348-1350 raise) | ❌ 없음 → **발화 불가** |
| `say` 음성(ko=en 등) | TTS_VOICE_MAP 93-97 | ✅ ko 계열 9건 있음 |
| **`afconvert`** | tts_rms_gate 114(게이트 1순위) | ✅ 있음 |
| `afplay` | tts_rms_gate 190(재생) · 189(없으면 raise) | ✅ 있음 |
| `sox` | 136-137(2순위 폴백) | ❌ 없어도 **무관** |
| 기본 출력 = BlackHole 2ch | afplay 는 장치 지정 없음 | ⚠ **사람이 1회 설정** |
| `websockets` | cdp_helper 100·118 | ❌ (별건 h 에서 설치) |
| Chrome `--remote-debugging-port=9333` | cdp_helper:21 | ❌ 재기동 필요 |

**한 줄**: mini 에서 발화를 살리려면 **`tts-say` 하나만 더 있으면 된다**(say 경로). `sox` 는 없어도 되고, `SwitchAudioSource` 도 없어도 되며, 대신 **출력 기본장치를 BlackHole 로 맞추는 사람 손 1회**가 필요하다.

## 이 문서가 하지 않은 것
- 코드 수정 0 · 원격 쓰기 0 · 앱 실행 0 · 비밀값 출력 0(`ELEVENLABS_API_KEY` 등 값은 읽지 않았다)
