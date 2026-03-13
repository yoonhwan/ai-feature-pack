# Feature Pack: YT Transcribe

> 이 문서는 OpenClaw 에이전트가 읽고 자율적으로 설치를 진행하는 프롬프트입니다.
> 사용자에게 질문이 필요한 항목은 `{{PLACEHOLDER}}` 로 표시되어 있습니다.
> placeholder를 발견하면 **반드시 사용자에게 인터뷰**하고, 답변으로 대치한 뒤 진행하세요.

---

## 개요

**YT Transcribe** — YouTube 영상을 로컬에서 오디오 다운로드 → STT 전사 → AI 요약/정리 문서 자동 생성하는 파이프라인.

**설치 후 할 수 있는 것:**
- YouTube URL만 주면 오디오 다운로드 + 전사 + 요약 문서 자동 생성
- API 키 불필요 (로컬 whisper.cpp 기반, 완전 오프라인 STT)
- Apple Silicon M1/M2/M3 Metal 가속 지원 (빠르고 무료)
- Obsidian 볼트에 자동 저장하여 세컨드브레인 구축 가능
- 한국어/영어/일본어 등 다국어 자동 감지

---

## Prerequisites (사전 요구사항)

### 필수
- **macOS** (Apple Silicon 권장, Intel도 지원)
- **Homebrew** — `brew --version` 으로 확인
- **Rust/Cargo** — `cargo --version` 으로 확인
- **디스크 공간** — Whisper 모델 파일용 최소 500MB 여유

### 선택
- **Obsidian** — 문서 저장소로 활용 시

### Rust 미설치 시
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

---

## Step 1: CLI 설치

### 1-1. ytdl 설치 (YouTube 다운로더, Rust)

```bash
cargo install rust-yt-downloader
```

설치 후 확인:
```bash
~/.cargo/bin/ytdl --help
# "Usage: ytdl <COMMAND>" 출력되면 성공
```

> ⚠️ `ytdl` 명령을 찾을 수 없으면 PATH에 `~/.cargo/bin` 추가:
> ```bash
> echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
> source ~/.zshrc
> ```

### 1-2. whisper-cli 설치 (STT 엔진, whisper.cpp)

```bash
brew install whisper-cpp
```

설치 후 확인:
```bash
whisper-cli -h
# whisper-cli 옵션 목록 출력되면 성공
```

### 1-3. ffmpeg 설치 (오디오 변환)

```bash
brew install ffmpeg
```

설치 후 확인:
```bash
ffmpeg -version | head -1
# "ffmpeg version X.X.X" 출력되면 성공
```

### 1-4. yt-dlp 설치 (ytdl 내부 의존성)

```bash
brew install yt-dlp
```

설치 후 확인:
```bash
yt-dlp --version
```

### 1-5. Whisper 모델 다운로드

```bash
# 모델 디렉토리 생성
mkdir -p ~/.whisper/models

# small 모델 다운로드 (462MB, 한국어/영어 지원, 기본 권장)
curl -L -o ~/.whisper/models/ggml-small.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
```

모델 확인:
```bash
ls -lh ~/.whisper/models/ggml-small.bin
# 약 462MB 파일이 존재해야 함
```

**더 높은 정확도가 필요하면 (선택):**
```bash
# medium (1.5GB, 더 정확)
curl -L -o ~/.whisper/models/ggml-medium.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"

# large-v3 (2.9GB, 최고 정확도)
curl -L -o ~/.whisper/models/ggml-large-v3.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
```

---

## Step 2: 스킬 설치

### 2-1. 스킬 폴더 복사

이 Feature Pack의 `skill/` 폴더를 OpenClaw 워크스페이스 스킬 디렉토리에 복사합니다.

```bash
SKILL_DIR="{{OPENCLAW_WORKSPACE}}/skills/yt-transcribe"
# 예: ~/.openclaw/workspace/skills/yt-transcribe

cp -r skill/ "$SKILL_DIR"
```

> **{{OPENCLAW_WORKSPACE}}** — OpenClaw 워크스페이스 경로.
> 보통 `~/.openclaw/workspace` 입니다.
> "OpenClaw 워크스페이스 경로가 어디인가요? (기본: ~/.openclaw/workspace)"

### 2-2. 스킬 확인

```bash
ls "$SKILL_DIR/SKILL.md"
# 파일이 존재해야 함
```

---

## Step 3: OpenClaw 설정

### 3-1. TOOLS.md에 추가

`{{OPENCLAW_WORKSPACE}}/TOOLS.md` 파일에 아래 섹션을 추가합니다.
이미 존재하면 내용을 업데이트합니다.

```markdown
### 🎬 YT Transcribe 파이프라인

YouTube → STT → 정리 문서 자동 생성 로컬 파이프라인.

**CLI 도구:**
| 도구 | 경로 | 버전 |
|------|------|------|
| `ytdl` | `~/.cargo/bin/ytdl` | 0.1.0 (rust-yt-downloader) |
| `whisper-cli` | `/opt/homebrew/bin/whisper-cli` | (whisper.cpp, M1 최적화) |
| `ffmpeg` | `/opt/homebrew/bin/ffmpeg` | brew 설치, MP3→WAV 변환용 |

**Whisper 모델:**
- `~/.whisper/models/ggml-small.bin` (462MB, 기본, 한국어/영어)
- medium/large-v3은 수동 다운로드 필요

**파이프라인 순서:**
1. `ytdl audio <URL> -f mp3 -o /tmp/yt_work/` → MP3 다운로드
2. `ffmpeg -i *.mp3 -ar 16000 -ac 1 audio.wav` → WAV 변환
3. `whisper-cli -m ggml-small.bin -l auto audio.wav -otxt` → STT 전사
4. Claude → 요약/아웃라인/키포인트 + 원본 YouTube URL 포함 문서 생성
5. 지정 경로에 README.md 저장
6. 임시 파일 전체 삭제
```

### 3-2. AGENTS.md 수정 (선택사항)

링크 공유 채널(예: #threads-web-link)이 있다면, 해당 채널 규칙에 추가:

```markdown
### YouTube 링크 자동 처리
- YouTube URL 감지 시 yt-transcribe 파이프라인 자동 실행
- 저장 경로: {{DEFAULT_SAVE_PATH}}
```

---

## Step 4: Obsidian 연동 (선택사항)

YouTube 전사 문서를 Obsidian 볼트에 자동 저장할 수 있습니다.

### 4-1. 저장 경로 설정

```
{{OBSIDIAN_VAULT_PATH}}/Sources/YT/
```

> **{{OBSIDIAN_VAULT_PATH}}** — Obsidian 볼트 경로.
> "Obsidian 볼트 경로가 어디인가요?"
> macOS 기본: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/{볼트이름}`

### 4-2. 폴더 생성

```bash
mkdir -p "{{OBSIDIAN_VAULT_PATH}}/Sources/YT"
```

### 4-3. 저장 구조

```
Sources/YT/
└── YYYY-MM-DD_영상-제목-슬러그/
    └── README.md    ← 요약 + 아웃라인 + 키포인트 + 전사 원문 + 원본 URL
```

문서에는 frontmatter로 원본 URL, 날짜, 제목 등 메타데이터가 포함됩니다.

---

## Step 5: 설치 검증

### 5-1. CLI 동작 확인

```bash
# ytdl
~/.cargo/bin/ytdl --help
# → "Usage: ytdl <COMMAND>" 출력

# whisper-cli
whisper-cli -h
# → 옵션 목록 출력

# ffmpeg
ffmpeg -version | head -1
# → "ffmpeg version X.X.X" 출력

# yt-dlp
yt-dlp --version
# → 버전 출력

# Whisper 모델
ls -lh ~/.whisper/models/ggml-small.bin
# → ~462MB 파일 존재
```

### 5-2. 전체 파이프라인 테스트 (짧은 영상)

```bash
# 1. 짧은 테스트 영상 다운로드 (30초~1분)
TMPDIR=$(mktemp -d /tmp/yt-test-XXXXXX)
~/.cargo/bin/ytdl audio "https://www.youtube.com/watch?v=jNQXAC9IVRw" -f mp3 -o "$TMPDIR"

# 2. WAV 변환
MP3_FILE=$(find "$TMPDIR" -name "*.mp3" | head -1)
ffmpeg -i "$MP3_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TMPDIR/audio.wav" -y

# 3. STT 전사
whisper-cli -m ~/.whisper/models/ggml-small.bin -l auto -otxt -f "$TMPDIR/audio.wav" --output-file "$TMPDIR/transcript"

# 4. 결과 확인
cat "$TMPDIR/transcript.txt"

# 5. 정리
rm -rf "$TMPDIR"
```

### 5-3. 검증 체크리스트

- [ ] `ytdl --help` 정상 출력
- [ ] `whisper-cli -h` 정상 출력
- [ ] `ffmpeg -version` 정상 출력
- [ ] `yt-dlp --version` 정상 출력
- [ ] `~/.whisper/models/ggml-small.bin` 파일 존재 (~462MB)
- [ ] 테스트 영상 전사 성공
- [ ] 스킬 폴더 존재: `ls {{OPENCLAW_WORKSPACE}}/skills/yt-transcribe/SKILL.md`
- [ ] TOOLS.md에 YT Transcribe 섹션 추가됨

---

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| `ytdl: command not found` | PATH 미설정 | `export PATH="$HOME/.cargo/bin:$PATH"` 추가 |
| `cargo: command not found` | Rust 미설치 | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| ytdl 빌드 실패 | cmake 버전 이슈 | `brew install cmake` 후 재시도 |
| ytdl 다운로드 실패 | Private/멤버십 영상 | 공개 영상 URL로 재시도 |
| `whisper-cli` 없음 | brew 설치 안됨 | `brew install whisper-cpp` |
| Whisper 모델 없음 | 모델 다운로드 안됨 | Step 1-5 실행 |
| 전사 품질 낮음 | small 모델 한계 | medium/large-v3 모델로 교체 |
| WAV 변환 실패 | ffmpeg 없음 | `brew install ffmpeg` |
| `yt-dlp: command not found` | 미설치 | `brew install yt-dlp` |
| 전사 중 한글 깨짐 | 언어 감지 실패 | `-l ko` 명시적 지정 |

---

## Placeholder 정리

설치 중 사용자에게 인터뷰가 필요한 항목:

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_WORKSPACE}}` | OpenClaw 워크스페이스 경로 | `~/.openclaw/workspace` |
| `{{OBSIDIAN_VAULT_PATH}}` | Obsidian 볼트 경로 (Obsidian 연동 시) | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/{볼트이름}` |
| `{{DEFAULT_SAVE_PATH}}` | 기본 문서 저장 경로 (채널 자동화 시) | — |

---

## 설치 완료 후

1. YouTube URL을 에이전트에게 공유하면 자동 전사+요약 실행
2. "유튜브 전사해줘", "영상 내용 정리해줘" 등 자연어로 트리거
3. 저장 경로는 매번 인터뷰로 확인 (채널 자동화 제외)

**CLI 직접 사용:**
```bash
# 영상 정보 확인
ytdl info "https://youtube.com/watch?v=VIDEO_ID"

# 오디오만 다운로드
ytdl audio "https://youtube.com/watch?v=VIDEO_ID" -f mp3 -o ~/Downloads

# 영상 다운로드
ytdl download "https://youtube.com/watch?v=VIDEO_ID" -q 1080p -f mp4 -o ~/Downloads
```

**Whisper 모델 업그레이드:**
```bash
# medium (더 정확, 1.5GB)
curl -L -o ~/.whisper/models/ggml-medium.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
```
