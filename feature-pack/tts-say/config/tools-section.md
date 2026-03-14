### 🔊 TTS (tts-say CLI)

- **CLI**: `tts-say` (Python, macOS say + ElevenLabs sag 통합)
- **Config**: `~/.config/tts-say/config.json`
- **기본 엔진**: config에서 설정 (auto/say/sag)

**주요 명령어:**
```bash
tts-say "텍스트"                          # config default로 읽기
tts-say speak --engine sag -v Roger "텍스트" # 엔진/보이스 지정
tts-say voices --engine say               # 보이스 목록
tts-say config set sag.voice "보이스명"    # 기본 보이스 변경
tts-say config show                       # 현재 설정 확인
```

**에이전트 패턴:**
```bash
pytest && tts-say "테스트 통과" || tts-say "테스트 실패"
tts-say speak -o /tmp/alert.mp3 "알림음"
```
