# 설치 검증

## 1. CLI 버전

```bash
agent-browser --version
# 기대: 0.16.3 이상
```

## 2. Native 모드 기본 동작

```bash
agent-browser --native open "https://example.com" \
  && agent-browser --native get title \
  && agent-browser --native screenshot /tmp/ab-test.png \
  && agent-browser --native close
# 기대: 타이틀 "Example Domain" + 스크린샷 생성
```

## 3. Snapshot (@ref)

```bash
agent-browser --native open "https://example.com" \
  && agent-browser --native snapshot -i \
  && agent-browser --native close
# 기대: [eN] 형태의 ref 목록 출력
```

## 4. Pillow (카드 생성용)

```bash
python3 -c "from PIL import Image; img = Image.new('RGB', (375, 100), '#1a1a2e'); img.save('/tmp/ab-pillow-test.png'); print('Pillow OK')"
# 기대: "Pillow OK" + 이미지 생성
```

## 5. Standard 모드 Fallback

```bash
agent-browser open "https://example.com" \
  && agent-browser get title \
  && agent-browser close
# 기대: native 없이도 동작 확인
```

## 정리

```bash
rm -f /tmp/ab-test.png /tmp/ab-pillow-test.png
```

## 검증 결과

| 항목 | 기대 | 결과 |
|------|------|------|
| CLI 버전 | 0.16.3+ | |
| Native 동작 | 스크린샷 생성 | |
| Snapshot | @ref 출력 | |
| Pillow | OK 출력 | |
| Standard fallback | 타이틀 출력 | |
