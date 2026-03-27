# termaid-render CLI 설치

## 의존성

| 도구 | 필수 | 설치 |
|------|------|------|
| Go 1.22+ | ✅ | `brew install go` |

## 설치

```bash
# 소스 클론 (최초 1회)
git clone https://github.com/MKlolbullen/termaid.git ~/scripts/termaid

# 빌드 패치 (업스트림 미완성 TUI 제외)
cd ~/scripts/termaid
mv internal/tui/builder.go internal/tui/builder.go.wip 2>/dev/null || true

# 빌드
go build -o termaid-render ./cmd/render/

# PATH에 복사
cp termaid-render /opt/homebrew/bin/termaid-render
chmod +x /opt/homebrew/bin/termaid-render
```

## 검증

```bash
termaid-render --help
echo 'graph LR
  A --> B --> C' | termaid-render
```

## 재빌드

```bash
cd ~/scripts/termaid && go build -o termaid-render ./cmd/render/ && cp termaid-render /opt/homebrew/bin/
```
