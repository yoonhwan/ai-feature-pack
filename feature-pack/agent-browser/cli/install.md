# agent-browser CLI 설치

## 설치

```bash
# npm 글로벌 설치 (권장, 가장 빠름)
npm install -g agent-browser

# Chromium 다운로드 (최초 1회)
agent-browser install
```

## Pillow 설치 (스크린샷 카드용)

```bash
pip3 install Pillow
# 또는
python3 -m pip install Pillow
```

## 설치 검증

```bash
# 버전 확인 (0.16.3+ 필요)
agent-browser --version

# Native 모드 테스트
agent-browser --native open "https://example.com" && agent-browser --native get title && agent-browser --native close

# Pillow 확인
python3 -c "from PIL import Image; print('Pillow OK')"
```

## 업데이트

```bash
npm update -g agent-browser
```
