# 실측 — Mac mini BlackHole 2ch + SwitchAudioSource (2026-10-21 23:2x KST · 읽기 전용 확인)

| 항목 | 값 |
|---|---|
| 설치 | `blackhole-2ch` cask · `switchaudio-osx` — 설치됨 (h135 가 mini 앞 sudo 단계 안내 후 오빠가 설치) |
| 드라이버 파일 | `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver` (ParrotAudioPlugin 과 공존) |
| 설치 직후 상태 | 장치 목록 «BlackHole 2ch» **없음** (`SwitchAudioSource -a` 0건) — 드라이버가 아직 로드되지 않음 |
| 조치 | 오빠가 mini 에서 `sudo killall coreaudiod` (오디오 서비스 재시작, 1~2초 끊김) — 23:21:27 시작 |
| 재시작 직후 | `SwitchAudioSource -a` → `BlackHole 2ch` (입력·출력 각 1) · `system_profiler` 1 건 — **장치 보임** |
| 마이크 권한 | 변경 없음 — MIC_UNVERIFIED (D9 확인 녹음에서 판정) |

## 배운 것 (h135 보정)
- 사전점검이 «설치됨(bh=1 · sas=yes) + 장치 없음(dev=0)» 을 설치 필요(rc=11)로 안내한 것은 오류였다. 이 조합은 **드라이버 미로드**이므로 재설치가 아니라 오디오 서비스 재시작이 맞다.
- 보정: 장치 판정을 `system_profiler` 와 `SwitchAudioSource -a` 둘 중 하나라도 보이면 «보임» 으로 하고, 설치됨+안 보임이면 rc=13(재시작 안내), 재시작 안내 뒤에도 안 보이면 rc=14(재부팅 여부를 오빠께 묻는 단계 — 스크립트가 재부팅하지 않음).

## 추가 (2026-10-21 23:3x KST) — Multi-Output Device
| 항목 | 값 | 근거 |
|---|---|---|
| 출력 목록 | TFG27Q14P2 · BlackHole 2ch · Mac mini Speakers · **Multi-Output Device** | `SwitchAudioSource -a -t output` (읽기) |
| 입력 목록 | BlackHole 2ch 1개 | `SwitchAudioSource -a -t input` |
| 현재 기본 | 출력 = Multi-Output Device · 입력 = BlackHole 2ch | `SwitchAudioSource -c` |
| Multi-Output 구성원 | BlackHole 2ch + Mac mini Speakers | **오빠 확인**(도구로 실측 불가 — 목록 API 가 구성원을 노출하지 않음) |
| 시험 도구 | ffmpeg · afplay · python3 있음 / sox 없음 | `command -v` (읽기) |
| 마이크 권한 | MIC_UNVERIFIED 그대로 | ssh 세션은 권한 팝업을 못 누름 → mini 터미널 앞 시험으로 판정 |

다음 단계(D9 사전 점검): `docs/multihost/h-plans/mini-audio-check.sh` — mini 터미널에서 직접 실행. 시험음 1초(Ping) + BlackHole 입력 3초 녹음 → 평균 볼륨 > -50 dB 면 MIC_OK 후보. 소리가 mini 스피커에서 나므로 **오빠가 mini 앞에 있어야 함**. 최종 확정은 e2e 러너의 trusted 클릭 회차(설계 P6 ①).
