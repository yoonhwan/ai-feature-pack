# cartier-auto 공유 & 설치 가이드

이 문서는 cartier-auto 스킬을 **다른 사용자(다른 macOS 머신)에게 전달**할 때의
공유 방법과, 전달받은 사용자가 겪게 될 설치·사용 흐름을 정리한 것이다.
시나리오 시뮬레이션은 마지막 섹션.

## 1. 외부 종속 (전달 전에 상대가 준비해야 할 것)

스킬은 다음 외부 요소를 요구한다. **설치 스크립트가 자동으로 설치하는 것과,
사용자가 직접 준비해야 하는 것이 다르다.**

### 사용자 직접 준비 (필수)
| 항목 | 필요 버전 | 설치 예시 (macOS) | 비고 |
|---|---|---|---|
| Python | 3.11+ | `brew install python@3.12` | 홈브루 권장 |
| Google Chrome | 최신 | `brew install --cask google-chrome` | 스킬이 `channel="chrome"` 사용 |

### 스킬 설치기가 자동 설치
| 항목 | 설치 위치 | 비고 |
|---|---|---|
| Playwright (Python) | 스킬 전용 venv (`~/.local/state/cartier-auto/.venv`) | `install.sh`가 실행 |
| Playwright chromium | 위 venv | `install.sh`가 실행 (실패해도 시스템 Chrome 폴백) |
| 스킬 패키지 복사본 | `~/.local/share/cartier-auto/skill` | `install.sh`가 실행 |
| Codex/Claude 스킬 심볼릭링크 | `~/.codex/skills/cartier-auto`, `~/.claude/skills/cartier-auto`, `~/.claude/commands/cartier-auto.md` | `install.sh`가 실행 |
| `cartier-auto` 명령 | `~/.local/bin/cartier-auto` | `install.sh`가 실행 |

### 선택 (있으면 좋음)
| 항목 | 용도 | 없으면 |
|---|---|---|
| tmux | 감시 백그라운드 세션 | nohup+PID 파일 폴백 (동작은 같음) |

### 필요 없는 것 (혼동 주의)
- 1Password, Node.js, npm, git, agent-browser(별도 브라우저) — **불필요**. Playwright가 직접 처리.

## 2. 공유 방법

### 전달 단위
다음 디렉터리 전체를 압축/복사해 전달한다:

```
skills/cartier-auto/
├── SKILL.md
├── SHARING.md          # 이 문서
├── commands/cartier-auto.md
├── config/cartier-site.json
└── scripts/
    ├── install.sh              # ★ 대화형 설치기
    ├── setup-credentials.sh    # ★ 자격증명 설정
    ├── run.sh                  # 런처
    ├── quick_validate.py
    ├── tests/
    └── cartier_auto/
        ├── cli.py  (doctor/wishlist/schedule/launch/run/status/logs/stop/setup)
        ├── site.py  monitor.py  runner.py  purchaser.py  config.py  credentials.py  _common.py
```

전달 방법 예시 (상대 머신에서):
```bash
# 1) 압축 파일 받기 (예: scripts 경유)
tar -czf cartier-auto.tar.gz skills/cartier-auto

# 2) 상대가 압축 해제
tar -xzf cartier-auto.tar.gz
cd cartier-auto
```

> ⚠️ **`installed.json`, `credentials.env`, `session-state.json`, `jobs/`, `logs/` 등
> 개인 데이터/자격증명은 공유에서 제외**해야 한다. (아래 [공유 시 제외] 참고)

### 공유 시 제외할 것
| 경로 | 이유 |
|---|---|
| `~/.local/state/cartier-auto/installed.json` | 설치 상태는 상대 머신에서 새로 생성 |
| `~/.config/cartier-auto/credentials.env` | **자격증명 (까르띠에/네이버 비밀번호)** |
| `~/.local/state/cartier-auto/session-state.json` | 로그인 세션 쿠키 |
| `~/.local/state/cartier-auto/jobs/`, `logs/`, `runs/` | 사용자별 작업 이력 |

## 3. 설치 가이드 (전달받은 사용자용)

전달받은 패키지 안에서 실행한다:

```bash
# 1) 설치 (환경 체크 → 대화형 확인 → 설치 → 상태 저장)
bash scripts/install.sh
#    → Python 3.11+/Chrome 체크 후 "설치할까요? [y/N]" → y 입력
#    → 설치 완료 시 ~/.local/state/cartier-auto/installed.json 에 상태 저장

# 2) 자격증명 등록 (ID는 일반, 비밀번호는 숨김 입력)
bash scripts/setup-credentials.sh
#    → ~/.config/cartier-auto/credentials.env (0600)

# 3) 설치/자격증명 상태 확인
bash scripts/run.sh setup --json      # 설치 완료 여부
bash scripts/run.sh doctor --json     # READY 여부 (설치+파이썬+크롬+런타임+자격증명)
```

### 설치 상태 판정 (중요)
- `installed.json`에 `"installed": true` 로 기록 → 이후 `setup`/`doctor`가 **설치 완료 분기**.
- 설치를 안 했다면 `setup`이 **"미설치 상태 + 환경 체크 + 설치 명령 안내"**를 출력해 설치로 유도.
- 즉, **설치 완료 여부가 로컬 저장되어, 미설치 시 자동으로 설치 경로로 이어진다.**

### 사용
```bash
bash scripts/run.sh wishlist --json          # 위시리스트 조회 (로그인 자동)
bash scripts/run.sh schedule --pid ... --at '...' --interval 5 --approved-price 2340000 --confirm
bash scripts/run.sh launch --job JOBID        # 감시 시작
bash scripts/run.sh status --job JOBID --json
bash scripts/run.sh stop --job JOBID          # 중지
```

> `~/.local/bin`이 PATH에 없으면 `export PATH="$HOME/.local/bin:$PATH"` 또는
> `bash scripts/run.sh ...` 로 직접 실행.

## 4. 전달 후 수신자 시나리오 (시뮬레이션)

전달받은 사용자가 위 가이드를 따를 때 겪는 단계별 상황:

### 시나리오 A — 정상 경로 (모든 준비 완료)
1. **패키지 받음** → `cartier-auto/` 디렉터리 확인.
2. `bash scripts/install.sh` 실행
   - 환경 체크: Python OK / Chrome OK 출력.
   - "설치할까요? [y/N]" → y 입력.
   - 7단계 진행 → 마지막에 `installed.json` 생성, `설치 완료.` 메시지.
3. `bash scripts/setup-credentials.sh` → ID/PW 4종 숨김 입력 → `credentials.env`(0600) 저장.
4. `bash scripts/run.sh doctor --json`
   - 출력: `ready: true`, `install.installed: true`, credentials ok.
5. `bash scripts/run.sh wishlist --json`
   - 위시리스트 조회 → 상품 목록(이름/PID/가격) 표시. (로그인 자동)
6. 상품 선택 → `schedule --confirm` → `launch` → 감시 시작 → 필요 시 `stop`.
   - **성공 시나리오**: 전체 흐름이 동작.

### 시나리오 B — Python/Chrome 미설치
1. `bash scripts/install.sh` 실행.
2. 환경 체크에서 `[!!] Python 3.11+ 필요` 또는 `[!!] Google Chrome 없음` 출력.
3. `환경 미충족 — 설치 중단` → 설치 안 됨, `installed.json` 미생성.
4. 수신자가 `brew install python@3.12`, Chrome 설치 후 재실행 → A로 진행.
   - **스킬 문제가 아니라 환경 준비 문제임을 메시지가 명확히 구분**.

### 시나리오 C — 설치 후 재실행/재설치
1. 이미 설치된 머신에서 `bash scripts/install.sh` 실행.
2. 환경 체크에서 `[i] 기존 설치 상태 있음` 출력.
3. (대화형) 다시 설치할지 확인 → y → 재설치 → `installed.json` 갱신.
   - **idempotent**: 기존 자격증명/데이터는 유지(패키지만 교체).

### 시나리오 D — 미설치 상태에서 setup 호출
1. 수신자가 `bash scripts/run.sh setup --json` 만 먼저 실행.
2. `installed: false` + 환경 체크 + `설치하려면: bash .../install.sh` 안내 출력.
3. 수신자가 안내대로 install.sh 실행 → A로 진행.
   - **설치 여부가 로컬 저장되어 미설치 시 자동으로 설치로 유도되는 경로**.

### 시나리오 E — 자격증명 없이 사용 시도
1. `bash scripts/run.sh wishlist --json` 실행 (자격증명 미등록).
2. `"CARTIER_ID/CARTIER_PASSWORD 자격증명 필요"` JSON 오류 반환.
3. 수신자가 `setup-credentials.sh` 실행 → 이후 정상.
   - **자격증명 값은 절대 로그/출력에 노출되지 않음.**

## 5. 설치 상태 저장 요약
| 파일 | 내용 | 생성 시점 |
|---|---|---|
| `~/.local/state/cartier-auto/installed.json` | installed/version/시각/python/chrome/skill_dir | 설치 완료 시 (install.sh) |
| `~/.config/cartier-auto/credentials.env` | 자격증명 4종 (0600) | setup-credentials.sh |
| `~/.local/state/cartier-auto/session-state.json` | 로그인 세션 (쿠키) | 로그인 성공 시 |
