# cartier-auto 설치 가이드

에이전트가 이 문서를 읽고 자율 설치하는 절차. (수동 설치도 동일)

## Prerequisites

- macOS
- **Python 3.11+** (`python3 --version` 확인, 없으면 `brew install python@3.12`)
- **Google Chrome** (`/Applications/Google Chrome.app` — 없으면 `brew install --cask google-chrome`)
- tmux (선택 — 감시 백그라운드, 없으면 nohup 폴백으로 동작)
- Claude Code 또는 Codex

## 설치

### Step 1: 설치기 실행

```bash
# 패키지 복사 → venv + Playwright 설치 → Codex/Claude 스킬 연결 → 설치 상태 저장
bash skill/scripts/install.sh
#   → 환경 체크 후 "설치할까요? [y/N]" → y
#   → 설치 완료 시 ~/.local/state/cartier-auto/installed.json 생성
```

비대화형(에이전트 자동)이면:
```bash
bash skill/scripts/install.sh --yes
```

### Step 2: 자격증명 등록

```bash
bash skill/scripts/setup-credentials.sh
# CARTIER_ID / CARTIER_PASSWORD / NAVER_ID / NAVER_PASSWORD (비밀번호는 숨김 입력)
# → ~/.config/cartier-auto/credentials.env (0600)
```

### Step 3: readiness 확인

```bash
bash skill/scripts/run.sh doctor --json
# ready: true 가 되어야 함 (설치 + Python + Chrome + Playwright + 자격증명)
```

## 검증

```bash
# 1. 설치 상태
bash skill/scripts/run.sh setup --json          # installed: true

# 2. 구조 검증
python3 skill/scripts/quick_validate.py         # OK 출력

# 3. 단위 테스트
python3 skill/scripts/tests/test_cartier_auto.py  # 10/10

# 4. 위시리스트 조회 (실제 로그인)
bash skill/scripts/run.sh wishlist --json
# → 상품 목록(이름/PID/가격) 출력. (로그인 자동, 재캡처 시 브라우저에서 직접 인증)
```

## 사용

```bash
cartier-auto wishlist --json                     # 위시리스트 조회
cartier-auto schedule --pid PID --at 'YYYY-MM-DD HH:MM:SS' --interval 5 --approved-price 2340000 --confirm
cartier-auto launch --job JOBID                  # 감시 시작
cartier-auto status --job JOBID --json           # 상태
cartier-auto stop --job JOBID                    # 중지 (사용자 명시 요청)
```

> `~/.local/bin`이 PATH에 없으면 `export PATH="$HOME/.local/bin:$PATH"` 또는
> `bash skill/scripts/run.sh ...` 로 실행.

## 업데이트

```bash
# 레포 pull 후 재설치 (자격증명·데이터는 유지, 패키지만 교체)
git pull
bash skill/scripts/install.sh --yes
```

## 제거

```bash
rm -f ~/.codex/skills/cartier-auto ~/.claude/skills/cartier-auto ~/.claude/commands/cartier-auto.md ~/.local/bin/cartier-auto ~/.local/bin/cartier-auto-python
rm -rf ~/.local/share/cartier-auto ~/.local/state/cartier-auto ~/.config/cartier-auto
```
