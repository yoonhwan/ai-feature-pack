# YT Transcribe Feature Pack

YouTube 영상 → 로컬 STT 전사 → AI 요약/정리 문서 자동 생성 파이프라인.

## 무엇을 할 수 있나요?

- YouTube 영상의 오디오를 로컬에서 다운로드
- whisper.cpp 기반 **오프라인 STT** (API 키 불필요, 무료)
- Claude/AI가 전사본을 분석하여 **요약 + 아웃라인 + 키포인트** 문서 생성
- Obsidian 볼트에 자동 저장하여 세컨드브레인 구축

## 기술 스택

| 도구 | 역할 | 설치 방식 |
|------|------|----------|
| **ytdl** | YouTube 오디오 다운로드 (Rust) | `cargo install` |
| **whisper-cli** | 오프라인 STT 전사 (whisper.cpp, M1 최적화) | `brew install` |
| **ffmpeg** | 오디오 포맷 변환 (MP3→WAV) | `brew install` |
| **yt-dlp** | ytdl 내부 의존성 | `brew install` |

## 요구사항

- macOS (Apple Silicon 권장, Intel도 지원)
- Rust/Cargo (ytdl 빌드용)
- Homebrew
- OpenClaw 에이전트 환경

## 설치

`INSTALL.md`를 에이전트에게 전달하면 자율 설치됩니다.

## 파이프라인 흐름

```
YouTube URL
  ↓ ytdl audio (MP3 다운로드)
  ↓ ffmpeg (MP3 → 16kHz mono WAV)
  ↓ whisper-cli (STT 전사)
  ↓ Claude AI (요약 + 아웃라인 + 키포인트)
  ↓ README.md 저장 (지정 경로)
  ↓ 임시 파일 전체 삭제
```
