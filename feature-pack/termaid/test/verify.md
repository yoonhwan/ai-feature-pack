# termaid-render 설치 검증

## 체크리스트

```bash
# 1. CLI 존재
which termaid-render && echo "✅ termaid-render found" || echo "❌ not found"

# 2. help 출력
termaid-render --help

# 3. Flowchart 렌더링
echo 'graph LR
  A[Client] --> B{Auth?}
  B -->|yes| C[Service]
  B -->|no| D[Error]' | termaid-render && echo "✅ flowchart OK"

# 4. Sequence 렌더링
echo 'sequenceDiagram
  participant C as Client
  participant S as Server
  C ->> S : request
  S -->> C : response' | termaid-render && echo "✅ sequence OK"

# 5. State 렌더링
echo 'stateDiagram-v2
  [*] --> Active
  Active --> Done : finish' | termaid-render && echo "✅ state OK"

# 6. 파일 입력
echo 'graph TD
  A --> B' > /tmp/termaid_test.mmd
termaid-render /tmp/termaid_test.mmd && echo "✅ file input OK"
rm /tmp/termaid_test.mmd

# 7. 한글 노드
echo 'graph LR
  A[사용자] --> B[서버]
  B --> C[(데이터베이스)]' | termaid-render && echo "✅ korean OK"
```

## 기대 결과

7개 항목 전부 ✅ → 설치 완료.
