# TOOLS.md 추가 섹션

아래 내용을 `{{OPENCLAW_WORKSPACE}}/TOOLS.md`에 추가하세요.

---

```markdown
### 🎬 YT Transcribe 파이프라인

YouTube → STT → 정리 문서 자동 생성 로컬 파이프라인.

**CLI 도구:**
| 도구 | 경로 | 설치 방식 |
|------|------|----------|
| `ytdl` | `~/.cargo/bin/ytdl` | `cargo install rust-yt-downloader` |
| `whisper-cli` | `/opt/homebrew/bin/whisper-cli` | `brew install whisper-cpp` |
| `ffmpeg` | `/opt/homebrew/bin/ffmpeg` | `brew install ffmpeg` |

**Whisper 모델:**
- `~/.whisper/models/ggml-small.bin` (462MB, 기본, 한국어/영어)
- medium/large-v3은 수동 다운로드 필요 (SKILL.md 참고)

**파이프라인 순서:**
1. `ytdl audio <URL> -f mp3 -o /tmp/yt_work/` → MP3 다운로드
2. `ffmpeg -i *.mp3 -ar 16000 -ac 1 audio.wav` → WAV 변환
3. `whisper-cli -m ggml-small.bin -l auto audio.wav -otxt` → STT 전사
4. Claude → 요약/아웃라인/키포인트 + 원본 YouTube URL 포함 문서 생성
5. 지정 경로에 README.md 저장
6. 임시 파일 전체 삭제 → **README.md 하나만 남긴다**

**주의사항:**
- `whisper-cli`는 MP3 직접 처리 가능하지만 WAV(16kHz mono)로 변환 시 품질 최적
- `ytdl`은 오디오를 `<output_dir>/` 폴더 안에 저장 (파일명은 영상 제목)
- yt-dlp가 내부 의존성 → `brew install yt-dlp` 설치 필요
```
