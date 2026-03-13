# Feature Pack: tts

macOS `say`와 ElevenLabs `sag`를 하나의 `tts` 명령어로 통합하는 TTS CLI.

## 주요 기능

- **엔진 통합**: `say` + `sag`를 `tts` 하나로 추상화
- **Config 저장**: 기본 엔진/보이스/옵션을 저장하면 매번 자동 적용
- **Auto Fallback**: sag → say 자동 선택
- **에이전트/바이브코딩**: `pytest && tts "테스트 통과"` 패턴

## 빠른 시작

```bash
tts "안녕하세요"                         # config default engine
tts speak --engine say "say로 읽기"      # explicit
tts voices --engine sag --search korean  # 보이스 검색
tts config set default_engine sag        # 기본 엔진 변경
```

## 설치

에이전트에게 `INSTALL.md` 전달 → 자율 설치.
수동 설치는 `INSTALL.md` 참조.
