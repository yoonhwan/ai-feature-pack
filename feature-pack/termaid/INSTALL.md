# Feature Pack: termaid
> 에이전트 자율 설치 프롬프트 — Mermaid 다이어그램 터미널 렌더러

## 개요

`termaid-render` CLI는 Mermaid 문법을 파싱하여 터미널에서 스타일링된 다이어그램으로 출력하는 도구.
에이전트가 설계 논의/아키텍처 설명 시 자동으로 사용한다.

**할 수 있는 것:**
- Mermaid → 터미널 스타일링 출력 (`echo 'graph LR ...' | termaid-render`)
- 파일 렌더링 (`termaid-render diagram.mmd`)
- flowchart, sequence, class, state, ER 다이어그램 지원

## Prerequisites

| 항목 | 필수 | 확인 명령 |
|------|------|----------|
| macOS | ✅ | `uname` → Darwin |
| Go 1.22+ | ✅ | `go version` |

> Go만 있으면 됨. 외부 API 키 불필요.

## Step 1: 소스 클론

```bash
git clone https://github.com/MKlolbullen/termaid.git {{TERMAID_SOURCE_PATH}}
```

> Placeholder `{{TERMAID_SOURCE_PATH}}`: 소스 저장 경로 (기본: `~/scripts/termaid`)

이미 클론 되어 있으면 pull:
```bash
cd {{TERMAID_SOURCE_PATH}} && git pull
```

## Step 2: 빌드 패치 (필수)

업스트림 `builder.go`에 컴파일 오류가 있어 제외 필요:

```bash
cd {{TERMAID_SOURCE_PATH}}

# builder.go 제외 (미완성 TUI)
mv internal/tui/builder.go internal/tui/builder.go.wip 2>/dev/null || true

# menu.go에서 NewBuilder 참조 제거
sed -i '' 's/return NewBuilder(catalogueNames()), nil/return errView(fmt.Errorf("workflow builder not yet available")), nil/' internal/tui/menu.go 2>/dev/null || true
```

## Step 3: 바이너리 빌드

```bash
cd {{TERMAID_SOURCE_PATH}}
go build -o termaid-render ./cmd/render/
```

검증:
```bash
./termaid-render --help
```

## Step 4: PATH에 설치

```bash
cp {{TERMAID_SOURCE_PATH}}/termaid-render {{TERMAID_INSTALL_PATH}}
chmod +x {{TERMAID_INSTALL_PATH}}
```

> Placeholder `{{TERMAID_INSTALL_PATH}}`: 설치 경로 (기본: `/opt/homebrew/bin/termaid-render`)

검증:
```bash
which termaid-render
termaid-render --help
```

## Step 5: 스킬 설치

`skill/SKILL.md`를 Claude Code 스킬 경로에 복사:

```bash
mkdir -p {{CLAUDE_SKILLS_PATH}}/termaid/
cp -r skill/SKILL.md {{CLAUDE_SKILLS_PATH}}/termaid/
```

> Placeholder `{{CLAUDE_SKILLS_PATH}}`: (기본: `~/.claude/skills`)

## Step 6: 설치 검증

```bash
# 1. CLI 존재
which termaid-render && echo "OK" || echo "FAIL"

# 2. Flowchart 렌더링
echo 'graph LR
  A[Client] --> B{Auth?}
  B -->|yes| C[Service]' | termaid-render

# 3. Sequence 렌더링
echo 'sequenceDiagram
  C ->> S : request
  S -->> C : response' | termaid-render

# 4. 파일 렌더링
echo 'stateDiagram-v2
  [*] --> Active
  Active --> Done : finish' > /tmp/test.mmd
termaid-render /tmp/test.mmd
rm /tmp/test.mmd
```

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `termaid-render: command not found` | PATH 미등록 | `cp termaid-render /opt/homebrew/bin/` |
| `go: command not found` | Go 미설치 | `brew install go` |
| `builder.go compile error` | 업스트림 미완성 | Step 2 패치 확인 |
| `yaml unmarshal error` | TUI init() 패닉 | `cmd/render/`만 빌드 (TUI 우회) |

## Placeholder 정리

| Placeholder | 질문 | 기본값 |
|-------------|------|--------|
| `{{TERMAID_SOURCE_PATH}}` | termaid 소스 저장 경로 | `~/scripts/termaid` |
| `{{TERMAID_INSTALL_PATH}}` | 바이너리 설치 경로 | `/opt/homebrew/bin/termaid-render` |
| `{{CLAUDE_SKILLS_PATH}}` | Claude 스킬 경로 | `~/.claude/skills` |

## 설치 완료 후

```bash
# 일상 사용 — 파이프
echo 'graph LR
  A --> B --> C' | termaid-render

# 파일에서
termaid-render my-diagram.mmd

# 에이전트 사용 — Claude가 자동으로 사용
# (설계 논의, 아키텍처 설명 시 자동 발동)
```

## 재빌드 (소스 수정 후)

```bash
cd ~/scripts/termaid && go build -o termaid-render ./cmd/render/ && cp termaid-render /opt/homebrew/bin/
```
