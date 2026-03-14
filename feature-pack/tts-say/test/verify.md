# tts-say 설치 검증

## 체크리스트

```bash
# 1. CLI 존재
which tts-say && echo "✅ tts-say found" || echo "❌ tts-say not found"

# 2. help 출력
tts-say --help

# 3. say 엔진
tts-say speak --engine say "say 테스트" && echo "✅ say OK"

# 4. config 동작
tts-say config show

# 5. config set/unset
tts-say config set say.voice Yuna
tts-say config unset say.voice

# 6. voices 목록
tts-say voices --engine say | head -5

# 7. sag 엔진 (API 키 있는 경우)
tts-say speak --engine sag "sag 테스트" && echo "✅ sag OK"

# 8. auto fallback
tts-say "자동 선택 테스트" && echo "✅ auto OK"

# 9. 파일 저장
tts-say speak --engine say -o /tmp/tts_verify.aiff "파일 저장" && ls -la /tmp/tts_verify.aiff && echo "✅ file save OK"

# 10. stdin 파이프
echo "파이프 테스트" | tts-say --engine say && echo "✅ stdin OK"
```

## 기대 결과

10개 항목 전부 ✅ → 설치 완료.
sag 테스트(#7)는 API 키 없으면 skip 가능.
