# probe LSP 계층 — 온디맨드

`probe lsp` 는 유닉스 소켓 데몬(`$TMPDIR/lsp-daemon.sock`)에 언어 서버를 붙여 정밀 LSP 기능을 노출한다.
**상주 금지 원칙**: 필요한 작업 직전 `up`, 끝나면 `down`.

## 수명주기
```bash
ci lsp up --scope .          # probe lsp init -w .        (실측 0.31s / 9.5MB)
ci lsp status                # 데몬 상태·요청 수
ci lsp down                  # probe lsp shutdown
probe lsp languages          # 언어별 서버 설치 여부
probe lsp doctor             # 데몬 진단
probe lsp index-status       # (선택) 인덱스 상태
```

## 호출
```bash
ci refs "path/file.py#symbol"        # references (실측 0.75s / 12MB)
ci def  "path/file.py#symbol"        # definition
ci impl "path/file.py#symbol"        # implementations
ci type "path/file.py#symbol"        # type-definition
probe lsp call hover "path/file.py:42:10"
probe lsp call document-symbols <file>
probe lsp call workspace-symbols "<query>"
```
위치 문법 두 가지: `file.rs:42:10` (1-based line:col) 또는 `file.rs#symbol_name`.

## 언어별 서버 요구표
| 언어 | 서버 | 현재 상태 | 설치 |
|---|---|---|---|
| Bash | bash-language-server | ✓ 있음 | serena language_servers 공유 |
| TypeScript/JS | typescript-language-server | ✓ 있음 | 동일 |
| C/C++ | clangd | ✓ 있음 | Xcode/brew |
| **Python** | **pylsp** (pyright 아님!) | ✓ 설치함(`uv tool install python-lsp-server`) | pylsp v1.15.0 |
| Go | gopls | ✗ | `go install golang.org/x/tools/gopls@latest` |
| Rust | rust-analyzer | ✓ (`~/.rustup`) | rustup |

## 지원 한계
- **`call-hierarchy` 는 pylsp 미지원** → 호출자 추적은 `ci sym --callers`(tilth, AST 기반, 0.36s).
- pylsp는 pyright보다 타입 추론이 약함(동적 코드 오탐 가능) → 넓은 탐색은 tilth, 확정 참조만 LSP.
- 대형 모노레포에서 `init` 은 워크스페이스 루트를 잡는다 → 하위만 하려면 `--scope <subdir>`.

## crash-loop 수리 (r1636)
데몬이 기동 즉시 죽으면(`probe lsp crash-logs` 에 "couldn't read enough data") 호출은 25초를 기다린다. `ci doctor` 가 rc=3 + `lsp : CRASH-LOOP … · 다음: ci lsp repair` 로 알리고, `ci lsp repair [--ws <이름>]` 이 워크스페이스 캐시를 지우지 않고 `…corrupt-<YYYYmmddHHMMSS>` 로 옮긴 뒤 데몬을 다시 세운다(rm 0 · 되돌림 = 이름 되돌리기).

## 비용
유휴 시 lsp-daemon 33MB + pylsp 79MB = **112MB**. 쓰지 않으면 `down`.
