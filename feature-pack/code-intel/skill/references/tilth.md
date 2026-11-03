# tilth (jahala/tilth) — 0.12.0

Rust 단일 바이너리(36.7MB). **인덱스 없음, 설정 없음, 상주 없음**. tree-sitter로 "정의 vs 언급"을 구분한다.
`~/.local/bin/tilth` (npx가 받은 네이티브 바이너리를 복사 — Node 불필요).

## 호출 형태
```bash
tilth <symbol> --scope <dir>          # 심볼 검색 (정의 우선 정렬)
tilth <symbol> --callers --scope <d>  # 호출 지점 (가장 빠름)
tilth <file> --deps                   # 파일 의존성 (local/external/dependents)
tilth <file>                          # 아웃라인 (+토큰 수)
tilth <file> --section "## Import"    # 섹션만 잘라 읽기
tilth "Sym1, Sym2" --scope .          # 다중 심볼 한 번에
tilth <sym> --expand=5 --scope .      # 상위 매치 본문까지
```
MCP 모드도 지원(`${kind: "callers"}` 등) — 필요 시에만.

## 출력 특징
- 헤더: `10 of 80 matches (50 definitions, 30 usages)` → **정의/언급 비율을 먼저 알려줌**
- 각 매치에 주변 심볼 컨텍스트 + 화살표(`->`)로 대상 지점
- 정의 확장 시 `-- calls --` footer 로 호출 대상 목록
- 파일 아웃라인 헤더에 `(275 lines, ~3.9k tokens)` → **Read 전 토큰 판단**

## 실측 (62k 파일 / 49GB)
| 호출 | 시간 | peak RSS |
|---|---|---|
| `dispatch --scope .` (80매치) | 6.50s | 105MB |
| `dispatch --callers --scope .` (51 호출지점) | **0.36s** | 74MB |
| `<file>` (아웃라인) | 0.00s | 3.5MB |
| `<file> --deps` | 0.11s | 16MB |

## 언제 tilth, 언제 probe
- **tilth**: 심볼명을 이미 알 때, 호출자/의존성/아웃라인, 토큰 절약이 중요할 때
- **probe**: 무엇을 찾을지 모를 때(의미검색), 구조 패턴, LSP 정밀 참조
- 호출자 추적은 항상 tilth (probe LSP의 pylsp는 call-hierarchy 미지원)

## 설치
```bash
npx -y tilth --version     # 네이티브 바이너리 받음
# 캐시 위치 예: ~/.npm/_npx/<hash>/node_modules/tilth/bin/tilth → ~/.local/bin/tilth 로 복사
# 또는: cargo install tilth
```

## ⚠️ 부하 주의 — 병렬 워크 (2026-10-23 실사고)

tilth 는 파일 워크를 **병렬(rayon)로** 돌린다. 그래서 빠르지만, **scope 가 크면 코어를 전부 먹는다.**

| 실측 사고 | 값 |
|---|---|
| `tilth <sym> …/harness/kit/…` (리포 전체 scope) | **585% CPU** |
| 동시 2건 (codex 세션이 날것 호출) | **574% 추가 → 약 11~12코어** |
| 지속 시간 | 4분 28초 (끝나지 않음 → 수동 kill) |
| load average | **139** |
| 회복 | kill 즉시 139 → 85 → 23 |

**규칙**
1. `tilth` 를 직접 치지 말고 **`ci sym` / `ci outline` 경유** (타임아웃 60s + scope 경고 내장)
2. scope 는 **하위 디렉터리**: `--scope shared/services` ✅
3. 리포 루트 전체가 필요하면 `CI_ALLOW_HEAVY=1 CI_TIMEOUT=600` 으로 명시적 예외
4. 파일 하나만 볼 때는 `ci outline <file>` (0.00s) — 이건 안전
