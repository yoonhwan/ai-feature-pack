---
name: "yt-transcribe"
description: "YouTube URL → 로컬 STT → 전사본+요약 생성. ytdl(rust-yt-downloader) + whisper-cli(whisper.cpp) 기반 파이프라인."
version: "1.1.0"
status: active
---

# YT Transcribe Skill

YouTube 링크를 입력받아 로컬 Rust/C++ 도구로 오디오를 다운로드하고 STT 전사 후 Claude가 요약·정리 문서를 생성하는 스킬.

## When to Use

- YouTube URL (youtube.com, youtu.be) 공유
- "유튜브 전사해줘", "영상 내용 정리해줘", "YouTube 요약"
- "ytdl", "whisper", "yt-transcribe" 키워드

## ⚠️ 저장 경로 인터뷰 (필수)

스킬 발동 시 **작업 시작 전에 반드시 저장 경로를 확인**한다.
사용자 또는 에이전트가 직접 지정하지 않았다면 **인터뷰로 물어본다**.

### 인터뷰 방식

```
📁 문서를 어디에 저장할까요?

추천 경로:
1. 옵시디언 볼트: {{OBSIDIAN_VAULT_PATH}}/Sources/YT/
2. 소스 폴더: ~/sources/yt/
3. 프로젝트 지정: ~/Project/<프로젝트명>/docs/references/
4. 직접 입력

어떤 경로로 저장해드릴까요?
```

**절대 경로를 임의로 가정하거나 하드코딩하지 않는다.**

## Decision Flow

```
YouTube URL 수신
  ├─ 저장 경로 지정됨? → YES → 파이프라인 시작
  │                     → NO  → 인터뷰 → 경로 확인
  ↓
Step 1: mktemp -d → 임시 작업 디렉토리
  ↓
Step 2: ytdl audio <URL> -f mp3 → MP3 다운로드
  ↓
Step 3: ffmpeg → 16kHz mono WAV 변환
  ↓
Step 4: whisper-cli -m small -l auto → STT 전사
  ↓
Step 5: Claude 처리 → 요약/아웃라인/키포인트
  ↓
Step 6: README.md 저장 (지정 경로)
  ↓
Step 7: 임시 파일 전체 삭제 (README.md만 남김)
```

## 입력 파라미터

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `url` | **(필수)** | YouTube URL |
| `save_to` | **(필수, 인터뷰로 확인)** | 문서 저장 디렉토리 경로 |
| `language` | `auto` | STT 언어 코드 (auto/ko/en 등) |
| `model` | `small` | Whisper 모델 크기 (small/medium/large-v3) |
| `format` | `mp3` | 오디오 다운로드 포맷 |

## CLI Reference

### ytdl (YouTube 다운로더)

```bash
# 오디오 다운로드 (메인 사용)
ytdl audio <URL> -f mp3 -o <output_dir>
ytdl audio <URL> -f flac -o <output_dir>    # 무손실
ytdl audio <URL> -f wav -o <output_dir>     # 무압축

# 영상 정보 확인
ytdl info <URL>

# 영상 다운로드
ytdl download <URL> -q 1080p -f mp4 -o <output_dir>
ytdl download <URL> -q best -f mkv -o <output_dir>

# 플레이리스트 다운로드
ytdl playlist <URL> -o <output_dir>

# 오디오 포맷: mp3, m4a, flac, wav, opus
# 영상 품질: 144p, 240p, 360p, 480p, 720p, 1080p, 1440p, 4k, best, worst
# 영상 포맷: mp4, mkv, webm

# 공통 옵션
#   -o, --output <dir>  출력 디렉토리 (기본: .)
#   -s, --silence       진행바 숨김
#   -v, --verbose       상세 로그
```

### whisper-cli (STT 전사)

```bash
# 기본 전사 (텍스트 출력)
whisper-cli -m ~/.whisper/models/ggml-small.bin -l auto -f <audio.wav> -otxt --output-file <output_path>

# 주요 옵션
#   -m <model>           모델 경로 (필수)
#   -f <file>            입력 오디오 (필수, flac/mp3/ogg/wav)
#   -l <lang>            언어 (auto/ko/en/ja 등)
#   -otxt                텍스트 파일 출력
#   -osrt                SRT 자막 출력
#   -ovtt                VTT 자막 출력
#   -oj                  JSON 출력
#   --output-file <path> 출력 파일 경로 (확장자 제외)
#   -t <N>               스레드 수 (기본: 4)
#   --no-timestamps      타임스탬프 제거
#   -tr                  영어로 번역
#   --vad                음성 구간 감지 활성화
```

### ffmpeg (오디오 변환)

```bash
# MP3 → WAV 변환 (whisper-cli 호환 포맷)
ffmpeg -i <input.mp3> -ar 16000 -ac 1 -c:a pcm_s16le <output.wav> -y

# 옵션 설명
#   -ar 16000  샘플레이트 16kHz (whisper 권장)
#   -ac 1      모노 채널
#   -c:a pcm_s16le  16bit PCM (무압축)
#   -y         덮어쓰기 확인 없이 실행
```

## Pipeline Steps

### Step 1: 임시 작업 디렉토리

```bash
TMPDIR=$(mktemp -d /tmp/yt-transcribe-XXXXXX)
```

### Step 2: 오디오 다운로드

```bash
~/.cargo/bin/ytdl audio "<YOUTUBE_URL>" -f mp3 -o "$TMPDIR"
```

### Step 3: MP3 → WAV 변환

```bash
MP3_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
ffmpeg -i "$MP3_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TMPDIR/audio.wav" -y
```

### Step 4: STT 전사

```bash
whisper-cli \
  -m ~/.whisper/models/ggml-small.bin \
  -l auto \
  -otxt \
  -f "$TMPDIR/audio.wav" \
  --output-file "$TMPDIR/transcript"
# → $TMPDIR/transcript.txt 생성
```

### Step 5: Claude 처리

전사본(`transcript.txt`)을 읽어 다음을 생성:
1. **전체 요약** (3~5 문장)
2. **섹션별 아웃라인** (타임스탬프 기반)
3. **핵심 키포인트** (bullet)
4. **액션 아이템** (있을 경우)

### Step 6: 문서 저장

```bash
SLUG=$(echo "<영상제목>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9가-힣]/-/g' | sed 's/--*/-/g')
OUTPUT_DIR="<save_to>/$(date +%Y-%m-%d)_${SLUG}"
mkdir -p "$OUTPUT_DIR"
# README.md 생성 (요약+아웃라인+전사원문 인라인)
```

README.md frontmatter 예시:
```yaml
---
source: "https://youtube.com/watch?v=VIDEO_ID"
title: "영상 제목"
date: 2026-03-14
language: ko
model: small
duration: "12:34"
tags: [youtube, transcription]
---
```

### Step 7: 정리

```bash
rm -rf "$TMPDIR"
```

**남기는 파일:** `README.md` (요약+전사 원문 인라인)
**삭제하는 파일:** MP3, WAV, transcript.txt 등 모든 중간 파일

## Whisper 모델 가이드

| 모델 | 크기 | 속도 | 정확도 | 용도 |
|------|------|------|--------|------|
| small | 462MB | ★★★★★ | ★★★☆☆ | 일상 전사 (기본) |
| medium | 1.5GB | ★★★☆☆ | ★★★★☆ | 높은 정확도 |
| large-v3 | 2.9GB | ★★☆☆☆ | ★★★★★ | 최고 정확도 |

모델 다운로드:
```bash
curl -L -o ~/.whisper/models/ggml-{small,medium,large-v3}.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{모델명}.bin"
```

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| ytdl 다운로드 실패 | Private/멤버십 영상 | 공개 영상 URL로 재시도 |
| whisper 모델 없음 | 모델 파일 누락 | `curl -L -o ~/.whisper/models/ggml-small.bin ...` |
| 전사 품질 낮음 | small 모델 한계 | medium 또는 large-v3로 교체 |
| WAV 변환 실패 | ffmpeg 없음 | `brew install ffmpeg` |
| 한글 깨짐/미인식 | 언어 감지 실패 | `-l ko` 명시적 지정 |
| save_to 미지정 | 경로 인터뷰 미진행 | 반드시 인터뷰 후 진행 |
| ytdl 빌드 실패 | cmake 버전 이슈 | `brew install cmake` 후 재시도 |

## Best Practices

- **저장 경로 항상 인터뷰**: 채널 자동화 제외, 매번 사용자에게 확인
- **임시 파일 반드시 삭제**: README.md만 남기고 전부 정리
- **원본 URL 필수 포함**: frontmatter `source` + 본문 첫 줄 양쪽 다
- **긴 영상은 medium 모델**: 1시간+ 영상은 small → medium 교체 추천
- **VAD 활용**: 무음 구간이 많은 영상은 `--vad` 옵션으로 정확도 향상
