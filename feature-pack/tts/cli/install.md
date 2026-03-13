# tts CLI 설치

## 의존성

| 도구 | 필수 | 설치 |
|------|------|------|
| Python 3.10+ | ✅ | `brew install python3` |
| macOS `say` | ✅ | 내장 |
| `sag` | 선택 | `brew install steipete/tap/sag` |

## 설치

```bash
# 이 피처팩의 스크립트를 PATH에 복사
cp skill/scripts/tts ~/.local/bin/tts
chmod +x ~/.local/bin/tts

# PATH 확인 (~/.local/bin이 없으면 추가)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## 검증

```bash
tts --help
tts speak --engine say "설치 확인"
```

## sag (ElevenLabs) 추가 설치

```bash
brew install steipete/tap/sag
export ELEVENLABS_API_KEY="your-key"  # ~/.zshrc에 추가
sag --version
```
