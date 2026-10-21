#!/usr/bin/env bash
# mini-audio-check.sh — D9 «마이크·소리 확인용 녹음»(MIC 확정 회차 전 단계): BlackHole 2ch 로 들어온 신호의 크기(RMS)를 잰다.
# ★이 파일은 mini 의 «터미널 앞»(GUI 로그인 세션 byz)에서 직접 실행한다★ — 녹음은 macOS 마이크 권한이 필요하고, 권한 팝업은 ssh 로는 못 누른다.
#   실행: mini 터미널에서 `bash <이 파일 경로>` (이 맥에서 `scp` 로 옮기지 않고, 리포 워크트리가 mini 에 없으면 파일 내용을 붙여넣어 실행)
# 하는 일: ① 읽기 전용 상태 표시 ② 현재 출력=Multi-Output Device 일 때만 짧은 시험음(afplay 시스템 음, 약 1초) ③ ffmpeg 로 «BlackHole 2ch» 입력 2초 녹음 → 평균 볼륨(dB) 판정
# 쓰는 것: /tmp 아래 임시 파일 1개(끝에 지움) — 설치·설정 변경·기본 장치 변경 0. 소리가 mini 스피커에서 1초 난다(오빠가 mini 앞에 있어야 함).
# 마이크 권한: 처음 실행하면 터미널(또는 ffmpeg)이 마이크 접근을 묻는 팝업이 뜰 수 있다 → «허용». 허용 전에는 무음(-91 dB 부근)으로 나오며 이것은 «권한 미확인»이지 장치 고장이 아니다.
# 판정: 평균 볼륨 > -50 dB 면 MIC_OK 후보(신호 들어옴) · 그 이하면 권한/라우팅 미확인(MIC_UNVERIFIED 유지). 최종 확정은 기존 e2e 러너의 trusted 클릭 회차(설계 P6 ①)에서만 — 이 스크립트 결과는 «사전 점검»이다.
# rc: 0 신호 확인(MIC_OK 후보) · 2 사전조건 실패 · 3 신호 없음(권한 또는 라우팅 확인)
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
say() { printf '[mini-audio] %s\n' "$*"; }
die() { printf '[mini-audio] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

for c in ffmpeg afplay SwitchAudioSource; do command -v "$c" >/dev/null 2>&1 || die 2 "$c 가 없다"; done
CUR_OUT="$(SwitchAudioSource -c -t output 2>/dev/null)"; CUR_IN="$(SwitchAudioSource -c -t input 2>/dev/null)"
say "1/3 상태(읽기): 출력=$CUR_OUT · 입력=$CUR_IN"
SwitchAudioSource -a -t input 2>/dev/null | grep -q 'BlackHole 2ch' || die 2 "입력 장치에 BlackHole 2ch 가 없다(h135 먼저)"
[ "$CUR_OUT" = "Multi-Output Device" ] || die 2 "현재 출력이 Multi-Output Device 가 아니다($CUR_OUT) — 시험음이 BlackHole 로 가지 않는다. 출력만 Multi-Output 으로 바꾼 뒤 다시(이 스크립트는 기본 장치를 바꾸지 않는다)"

T="$(mktemp /tmp/aifp-mini-audio.XXXXXX.wav)"
trap 'rm -f "$T"' EXIT

say "2/3 시험음 1회 + BlackHole 2ch 입력 2초 녹음 (소리가 mini 스피커에서 약 1초 납니다)"
( sleep 1; afplay /System/Library/Sounds/Ping.aiff >/dev/null 2>&1 ) &
timeout 12 ffmpeg -nostdin -loglevel error -y -f avfoundation -i ":BlackHole 2ch" -t 3 "$T" 2>/tmp/aifp-mini-audio.err
wait
RC=$?
if [ ! -s "$T" ]; then
  say "녹음 파일이 비었다 — $(head -c 200 /tmp/aifp-mini-audio.err 2>/dev/null)"
  rm -f /tmp/aifp-mini-audio.err
  die 3 "녹음 실패 — 터미널 마이크 권한 팝업에서 «허용» 했는지, 시스템 설정 → 개인정보 보호 및 보안 → 마이크 에서 터미널이 켜져 있는지 확인"
fi
rm -f /tmp/aifp-mini-audio.err

say "3/3 분석"
VOL="$(ffmpeg -nostdin -hide_banner -i "$T" -af volumedetect -f null - 2>&1 | grep -E 'mean_volume|max_volume' | sed 's/^.*\] //')"
echo "$VOL" | sed 's/^/        /'
MEAN="$(echo "$VOL" | sed -n 's/^mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')"
if [ -n "$MEAN" ] && awk -v m="$MEAN" 'BEGIN{exit !(m > -50)}'; then
  say "신호 들어옴(평균 ${MEAN} dB) → MIC_OK 후보. 최종 확정은 e2e 러너의 trusted 클릭 회차에서."
  exit 0
fi
die 3 "신호가 없다(평균 ${MEAN:-?} dB) — 터미널 마이크 권한이 «허용» 인지 확인하고 한 번 더. 그래도 무음이면 Multi-Output 구성원에 BlackHole 2ch 가 체크돼 있는지 확인"
