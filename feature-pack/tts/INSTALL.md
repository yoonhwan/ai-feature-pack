# Feature Pack: tts
> 에이전트 자율 설치 프롬프트 — macOS say + ElevenLabs sag 통합 TTS CLI

## 개요

`tts` CLI는 macOS 내장 `say`와 ElevenLabs `sag`를 하나로 통합한 TTS 프론트엔드.
에이전트, 바이브코딩, 스크립트에서 `tts` 하나만 호출하면 자동으로 최적 엔진을 선택한다.

**할 수 있는 것:**
- 텍스트 → 음성 재생 (`tts "텍스트"`)
- 텍스트 → 오디오 파일 저장 (`tts speak -o out.mp3 "텍스트"`)
- 엔진별 보이스 목록 조회 (`tts voices`)
- 기본 엔진/보이스/옵션 Config 저장 (`tts config set ...`)
- stdin 파이프 입력 (`echo "텍스트" | tts`)

## Prerequisites

| 항목 | 필수 | 확인 명령 |
|------|------|----------|
| macOS | ✅ | `uname` → Darwin |
| Python 3.10+ | ✅ | `python3 --version` |
| `say` | ✅ (내장) | `which say` |
| `sag` | 선택 | `which sag` |
| ElevenLabs API Key | 선택 | `echo $ELEVENLABS_API_KEY` |

> `say`만으로도 동작함. `sag`는 고품질 음성 원할 때만 필요.

## Step 1: sag 설치 (선택)

```bash
brew install steipete/tap/sag
```

검증:
```bash
sag --version
```

## Step 2: ElevenLabs API Key 설정 (선택)

sag 사용 시 필요. `~/.zshrc` 또는 `~/.bashrc`에 추가:

```bash
export ELEVENLABS_API_KEY="{{ELEVENLABS_API_KEY}}"
```

> Placeholder: 사용자에게 "ElevenLabs API 키가 있으신가요? (없으면 say 엔진만 사용합니다)" 질문

## Step 3: tts CLI 설치

이 feature-pack의 `skill/scripts/tts` 파일을 PATH에 복사:

```bash
cp skill/scripts/tts {{TTS_INSTALL_PATH}}
chmod +x {{TTS_INSTALL_PATH}}
```

> Placeholder `{{TTS_INSTALL_PATH}}`: 설치 경로 (기본: `/usr/local/bin/tts` 또는 `~/.local/bin/tts`)
> 질문: "tts CLI를 어디에 설치할까요? (기본: ~/.local/bin/tts)"

검증:
```bash
tts --help
```

## Step 4: 기본 Config 설정

```bash
# 기본 엔진 설정 (sag API 키 있으면 sag, 없으면 say)
tts config set default_engine {{DEFAULT_ENGINE}}

# say 기본 보이스 (한국어)
tts config set say.voice Yuna

# sag 기본 설정 (API 키 있는 경우)
tts config set sag.voice "{{SAG_DEFAULT_VOICE}}"
tts config set sag.model_id eleven_multilingual_v2
tts config set sag.lang ko
```

> Placeholder `{{DEFAULT_ENGINE}}`: API 키 여부에 따라 `sag` 또는 `say` (기본: `auto`)
> Placeholder `{{SAG_DEFAULT_VOICE}}`: 사용자 선호 보이스. `tts voices --engine sag` 로 목록 확인 후 선택

검증:
```bash
tts config show
```

## Step 5: 스킬 설치

`skill/` 폴더를 OpenClaw 워크스페이스 스킬 경로에 복사:

```bash
cp -r skill/ {{OPENCLAW_SKILLS_PATH}}/tts/
```

> Placeholder `{{OPENCLAW_SKILLS_PATH}}`: (기본: `~/.openclaw/workspace/skills`)

## Step 6: OpenClaw 설정 (선택)

### TOOLS.md 추가

`config/tools-section.md` 내용을 `{{OPENCLAW_WORKSPACE}}/TOOLS.md`에 추가.

## Step 7: 설치 검증

```bash
# 1. CLI 동작
tts --help

# 2. say 엔진 테스트
tts speak --engine say --voice Yuna "say 엔진 테스트"

# 3. sag 엔진 테스트 (API 키 있는 경우)
tts speak --engine sag "sag 엔진 테스트"

# 4. auto 모드
tts "자동 엔진 선택 테스트"

# 5. config 확인
tts config show

# 6. 보이스 목록
tts voices --engine say
```

모든 명령이 정상이면 설치 완료.

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `tts: command not found` | PATH 미등록 | `echo $PATH` 확인, `~/.local/bin` 추가 |
| `sag: command not found` | sag 미설치 | `brew install steipete/tap/sag` |
| `ELEVENLABS_API_KEY not set` | 환경변수 누락 | `~/.zshrc`에 export 추가 후 `source ~/.zshrc` |
| `voice "X" not found` | 잘못된 보이스명 | `tts voices --engine sag` 로 확인 |
| say 한국어 안 됨 | 보이스 미설치 | 시스템 설정 > 접근성 > 음성 콘텐츠에서 한국어 보이스 다운로드 |

## Placeholder 정리

| Placeholder | 질문 | 기본값 |
|-------------|------|--------|
| `{{ELEVENLABS_API_KEY}}` | ElevenLabs API 키 (없으면 say만 사용) | (없음) |
| `{{TTS_INSTALL_PATH}}` | tts CLI 설치 경로 | `~/.local/bin/tts` |
| `{{DEFAULT_ENGINE}}` | 기본 TTS 엔진 | `auto` |
| `{{SAG_DEFAULT_VOICE}}` | sag 기본 보이스 | (voices 목록에서 선택) |
| `{{OPENCLAW_SKILLS_PATH}}` | 스킬 설치 경로 | `~/.openclaw/workspace/skills` |
| `{{OPENCLAW_WORKSPACE}}` | 워크스페이스 경로 | `~/.openclaw/workspace` |

## 설치 완료 후

```bash
# 일상 사용
tts "빌드가 끝났습니다"

# 바이브코딩 알림
pytest && tts "테스트 통과" || tts "테스트 실패"

# 보이스 변경
tts config set sag.voice "다른보이스"

# 파일 저장
tts speak -o /tmp/alert.mp3 "알림음"
```
