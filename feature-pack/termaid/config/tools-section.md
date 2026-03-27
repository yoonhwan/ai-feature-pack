### 📊 Mermaid Diagrams (termaid-render CLI)

- **CLI**: `termaid-render` (Go, charmbracelet/lipgloss 기반)
- **소스**: `~/scripts/termaid/cmd/render/`
- **용도**: 설계 논의, 아키텍처 시각화 시 Mermaid → 터미널 렌더링

**주요 명령어:**
```bash
# stdin 파이프 (에이전트 기본 사용 패턴)
echo 'graph LR
  A[Client] --> B{Auth?}
  B -->|yes| C[Service]' | termaid-render

# 파일에서
termaid-render diagram.mmd

# 도움말
termaid-render --help
```

**에이전트 자동 발동:**
- 설계 논의, 아키텍처 설명, 플로우 시각화 시
- "다이어그램", "시퀀스", "아키텍처", "mermaid" 키워드

**지원 타입:** flowchart, sequenceDiagram, classDiagram, stateDiagram-v2, erDiagram
