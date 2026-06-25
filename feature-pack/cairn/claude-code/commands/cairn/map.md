---
description: 복구 그래프(recovery-map) mermaid 생성
argument-hint: [--focus <node>] [--render] [--png]
allowed-tools: Bash
---

# /cairn:map

복구 그래프(recovery-map) mermaid 생성. 노드는 6필드(st·fin·wt·br·sess·note)로
표시되며, 워크트리/브랜치(wt·br)는 직계 부모와 달라진 head 노드에만 표기된다(전이 마커).

- `--render`: termaid로 터미널 렌더
- `--png`: PNG로 구워 Preview에 표시(mmdc 필요). mermaid 코드블록이 클라이언트에서
  안 보일 때 시각 확인용.

## 실행
```bash
bash ~/.cairn/current/bin/cairn map $ARGUMENTS
```
