# Feature Pack: termaid

Mermaid 다이어그램을 터미널에서 직접 렌더링하는 CLI 도구.

> **이름**: "terminal" + "mermaid" = **termaid**

## 주요 기능

- **Flowchart 렌더링**: `graph LR/TD` — 노드 형태(box/diamond/round/cylinder), subgraph, 엣지 라벨
- **Sequence Diagram**: participant, 동기/비동기 화살표, loop/alt/else 블록
- **Class/State/ER Diagram**: 기본 지원
- **stdin 파이프**: Claude나 스크립트에서 `echo '...' | termaid-render`
- **파일 입력**: `termaid-render diagram.mmd`
- **lipgloss 스타일링**: 터미널 색상/테두리/볼드 적용

## 빠른 시작

```bash
# 플로우차트
echo 'graph LR
  A[Client] --> B{Auth?}
  B -->|yes| C[Service]
  B -->|no| D[401]' | termaid-render

# 시퀀스 다이어그램
echo 'sequenceDiagram
  C ->> S : POST /login
  S -->> C : 200 OK' | termaid-render

# 파일에서
termaid-render workflow.mmd
```

## 설치

에이전트에게 `INSTALL.md` 전달 → 자율 설치.
수동 설치는 `INSTALL.md` 참조.
