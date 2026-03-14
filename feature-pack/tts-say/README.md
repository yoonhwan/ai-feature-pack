# Feature Pack: tts-say

macOS `say`와 ElevenLabs `sag`를 하나의 `tts-say` 명령어로 통합하는 TTS CLI.

> **이름 변경**: `tts` → `tts-say` (v1.1.0) — 일반 TTS API/기술용어와의 혼동 방지.

## 주요 기능

- **엔진 통합**: `say` + `sag`를 `tts-say` 하나로 추상화
- **Config 저장**: 기본 엔진/보이스/옵션을 저장하면 매번 자동 적용
- **Auto Fallback**: sag → say 자동 선택
- **에이전트/바이브코딩**: `pytest && tts-say "테스트 통과"` 패턴

## 빠른 시작

```bash
tts-say "안녕하세요"                         # config default engine
tts-say speak --engine say "say로 읽기"      # explicit
tts-say voices --engine sag --search korean  # 보이스 검색
tts-say config set default_engine sag        # 기본 엔진 변경
```

## 설치

에이전트에게 `INSTALL.md` 전달 → 자율 설치.
수동 설치는 `INSTALL.md` 참조.
