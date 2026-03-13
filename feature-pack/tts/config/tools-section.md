### 🔊 TTS (Text-to-Speech)

- **CLI**: `tts` (Python, macOS say + ElevenLabs sag 통합)
- **Config**: `~/.config/tts/config.json`
- **기본 엔진**: config에서 설정 (auto/say/sag)

**주요 명령어:**
```bash
tts "텍스트"                          # config default로 읽기
tts speak --engine sag -v Roger "텍스트" # 엔진/보이스 지정
tts voices --engine say               # 보이스 목록
tts config set sag.voice "보이스명"    # 기본 보이스 변경
tts config show                       # 현재 설정 확인
```

**에이전트 패턴:**
```bash
pytest && tts "테스트 통과" || tts "테스트 실패"
tts speak -o /tmp/alert.mp3 "알림음"
```
