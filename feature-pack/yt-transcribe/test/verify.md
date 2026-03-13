# 설치 검증

## 1. CLI 개별 검증

```bash
# ytdl
~/.cargo/bin/ytdl --help
# → "Usage: ytdl <COMMAND>" 출력되면 ✅

# whisper-cli
whisper-cli -h
# → 옵션 목록 출력되면 ✅

# ffmpeg
ffmpeg -version | head -1
# → "ffmpeg version X.X.X" 출력되면 ✅

# yt-dlp
yt-dlp --version
# → 버전 번호 출력되면 ✅

# Whisper 모델
ls -lh ~/.whisper/models/ggml-small.bin
# → ~462MB 파일 존재하면 ✅
```

## 2. 전체 파이프라인 테스트

짧은 테스트 영상(YouTube 최초 업로드 영상 "Me at the zoo", 19초)으로 검증:

```bash
# 임시 디렉토리
TMPDIR=$(mktemp -d /tmp/yt-verify-XXXXXX)

# 오디오 다운로드
~/.cargo/bin/ytdl audio "https://www.youtube.com/watch?v=jNQXAC9IVRw" -f mp3 -o "$TMPDIR"

# WAV 변환
MP3_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
ffmpeg -i "$MP3_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TMPDIR/audio.wav" -y

# STT 전사
whisper-cli -m ~/.whisper/models/ggml-small.bin -l auto -otxt -f "$TMPDIR/audio.wav" --output-file "$TMPDIR/transcript"

# 결과 확인
echo "=== 전사 결과 ==="
cat "$TMPDIR/transcript.txt"

# 정리
rm -rf "$TMPDIR"
echo "=== 검증 완료 ==="
```

## 3. 체크리스트

- [ ] `ytdl --help` → 정상 출력
- [ ] `whisper-cli -h` → 정상 출력
- [ ] `ffmpeg -version` → 정상 출력
- [ ] `yt-dlp --version` → 정상 출력
- [ ] `~/.whisper/models/ggml-small.bin` → 파일 존재
- [ ] 테스트 영상 전사 → 텍스트 출력 성공
- [ ] 스킬 SKILL.md → `{{OPENCLAW_WORKSPACE}}/skills/yt-transcribe/SKILL.md` 존재
- [ ] TOOLS.md → YT Transcribe 섹션 추가됨

## 4. 실패 시 대응

| 단계 | 실패 증상 | 대응 |
|------|----------|------|
| ytdl | `command not found` | `cargo install rust-yt-downloader` + PATH 확인 |
| ytdl | 다운로드 에러 | `yt-dlp --version` 확인, `brew install yt-dlp` |
| ffmpeg | 변환 실패 | `brew install ffmpeg` |
| whisper | 모델 로드 실패 | 모델 파일 경로/크기 확인 (462MB) |
| whisper | 전사 결과 비어있음 | `-l ko` 또는 `-l en` 명시적 지정 |
