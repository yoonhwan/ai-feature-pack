# CLI Installation Guide

## 1. ytdl (YouTube 다운로더)

**패키지**: `rust-yt-downloader`
**설치**: `cargo install rust-yt-downloader`
**바이너리**: `~/.cargo/bin/ytdl`
**버전 확인**: `ytdl --help` (--version은 미지원)

### Prerequisites
- Rust/Cargo: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- yt-dlp (내부 의존성): `brew install yt-dlp`

### 주요 명령어
```bash
ytdl audio <URL> -f mp3 -o <dir>      # 오디오 추출
ytdl download <URL> -q 1080p -o <dir>  # 영상 다운로드
ytdl info <URL>                        # 영상 정보
ytdl playlist <URL> -o <dir>           # 플레이리스트
```

---

## 2. whisper-cli (STT 엔진)

**패키지**: `whisper-cpp`
**설치**: `brew install whisper-cpp`
**바이너리**: `/opt/homebrew/bin/whisper-cli`
**버전 확인**: `whisper-cli -h`

### 모델 다운로드 (필수)
```bash
mkdir -p ~/.whisper/models
curl -L -o ~/.whisper/models/ggml-small.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
```

### 주요 사용법
```bash
whisper-cli -m ~/.whisper/models/ggml-small.bin -l auto -f <wav> -otxt --output-file <path>
```

---

## 3. ffmpeg (오디오 변환)

**설치**: `brew install ffmpeg`
**바이너리**: `/opt/homebrew/bin/ffmpeg`
**버전 확인**: `ffmpeg -version | head -1`

### 주요 사용법
```bash
ffmpeg -i input.mp3 -ar 16000 -ac 1 -c:a pcm_s16le output.wav -y
```

---

## 4. yt-dlp (ytdl 의존성)

**설치**: `brew install yt-dlp`
**버전 확인**: `yt-dlp --version`

---

## 전체 검증

```bash
~/.cargo/bin/ytdl --help && echo "✅ ytdl OK"
whisper-cli -h > /dev/null 2>&1 && echo "✅ whisper-cli OK"
ffmpeg -version > /dev/null 2>&1 && echo "✅ ffmpeg OK"
yt-dlp --version > /dev/null 2>&1 && echo "✅ yt-dlp OK"
ls ~/.whisper/models/ggml-small.bin > /dev/null 2>&1 && echo "✅ whisper model OK"
```
