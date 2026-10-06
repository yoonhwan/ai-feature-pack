# ORDER — 풀스택 다이어그램 사실 수집 (ft-harness-arch#3 → ft-harness-nano#1 · 2026-10-05 · 읽기 전용)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 골의 축: 표 A(모니터 대상 지도) · 표 C(전 머신 배분의 입력 = 머신·인프라 지도) · 원문 5. 이 발주 = 상위 ORDER-fullstack-diagram-20261005.md 할 일 1(사실 수집).

## 규칙 (전부 HARD)
- **읽기 전용**: 서버 기동·press·설정 변경·커밋 0. 쓰는 파일은 아래 산출 1개뿐.
- **시크릿 0**: 환경변수는 **이름만**(값 금지) · 토큰·키·계정 ID·이메일 0. 값이 섞이면 그 줄 삭제.
- 노드마다 **[사실] 출처 1줄**(`파일:라인` 또는 «명령 그대로» + 출력 요약). 확인 못 하면 **[추측]** 표시.
- 하네스 트리(③)는 `design/harness/issue-improvement/SPEC-main-orch-tree-20261005.md` §3 이 정본 — 다시 조사하지 말고 **지금 tmux 와 달라진 줄만** 적는다.
- 산출: `design/harness/diagrams/FACTS-fullstack-20261005.md` 1장. 끝나면 mbox 로 arch 에 「완료 + 줄 수 + [추측] 개수」 3줄. 커밋은 하지 않는다(ops 가 한다).
- 상한: 명령 출력은 각 40줄 이내로 잘라 적는다. 10분 넘으면 그때까지 것을 저장하고 보고.

## 수집 항목 (번호 그대로 절 제목으로)

### 1. 외부 서비스 (이름·역할·연결만)
```bash
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops
grep -rhoE '\b[A-Z][A-Z0-9_]{3,}_(API_KEY|TOKEN|SECRET|URL|BASE_URL|ENDPOINT|PROJECT|BUCKET|HOST|DSN)\b' .env.example src server gateway worker apps web 2>/dev/null | sort -u
ls ~/.hermes 2>/dev/null; ls ~/.hermes/config* 2>/dev/null
grep -rhoE '"(provider|host|url)"\s*:\s*"[^"]{0,60}"' ~/.cliproxy* ~/.config/cliproxy* 2>/dev/null | sort -u | head -40
```
적을 것: Slack · GitHub · Supabase · GCP(Cloud Run · IAP · GCE GPU VM) · STT/TTS/LLM 프로바이더(이름 전부) · Cloudflare/도메인 · cliproxy/headroom 상류 · Perplexity/Codex/Cursor 등 에이전트 CLI 상류. 각 줄 = `외부서비스명 | 역할 | 연결하는 내부 노드 | 출처`.

### 2. 머신·프로세스·포트
```bash
launchctl list | grep -iE 'byz|ft-|hermes|cliproxy|headroom|zombie|tick|caddy|redis|postgres|vllm|tunnel'
ls ~/Library/LaunchAgents
lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1{print $1,$2,$9}' | sort -u
docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'
for f in /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/*/.worktree-info.json; do echo "$f"; python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print({k:d.get(k) for k in ('branch','purpose','ports','base_port','created_at')})" "$f"; done
grep -rn "38301\|38300\|8443\|8080\|3001\|3002\|9333" docs/rules/dev_scripts.md CLAUDE.md 2>/dev/null | head -20
grep -rn "10\.2\.0\.\|jarvis\|LOOM\|GPU VM\|a1p\|ccu-stress-vllm\|ccu-stress-stt" docs design/ccu design/cfo --include=*.md -l 2>/dev/null | head -10
cat /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/state/gce-op-model/BREACH.md 2>/dev/null | head -20
```
적을 것: 이 Mac 의 listen 포트 → 소유 프로세스 → 소유 워크트리(`lsof -p <pid> | grep cwd`) · Caddy 8443 · gateway/worker/FE · Redis · Postgres(로컬 컨테이너인지 Supabase 인지) · GPU VM 이름·터널 주소(대역만) · 다른 머신(jarvis 등) 이름과 역할. 각 줄 = `머신/프로세스 | 포트 | 소유(워크트리/팀) | 출처`.

### 3. 하네스 노드 (정본 §3 과의 차이만)
```bash
tmux list-sessions -F '#{session_name} #{pane_current_path}' 2>/dev/null
ls /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/
ls /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/ /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ 2>/dev/null | head -60
ls ~/.claude/fable-team/bin 2>/dev/null | head -40
```
적을 것: 정본 §3 트리와 지금 tmux 의 차이(새 세션·죽은 세션) · 명부 파일 6개 이름 · mbox 파일 4종 경로 · `bin/` 의 ft-*.sh 이름 목록(역할 1단어씩).

### 4. 로컬 파일시스템 지도
```bash
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
ls -d */ .claude .fable-team .worktrees .baton .omc 2>/dev/null
ls .worktrees/ ; ls .claude/ ; ls .claude/rules .claude/skills .claude/hooks 2>/dev/null
ls design/ ; ls design/harness design/planner design/v65 design/cfo design/ccu design/kk 2>/dev/null | head -80
ls ~/.claude/ ; ls ~/.claude/skills ~/.claude/rules ~/.claude/hooks ~/.claude/archives 2>/dev/null | head -80
ls ~/.hermes ~/.codex ~/.baton 2>/dev/null | head -30
ls /tmp/mbox 2>/dev/null | head -5; ls /tmp/byz-*.log 2>/dev/null
```
적을 것: 트리 1장(깊이 2) · 각 폴더 한 줄 역할([사실] = README/CLAUDE.md 줄 인용 · 없으면 [추측]).

## 산출 머리줄 (파일 첫 5줄에 그대로)
```
# FACTS — 풀스택 다이어그램 사실 (ft-harness-nano#1 · 2026-10-05 · 읽기 전용 · 시크릿 0)
> 상위 ORDER: design/harness/diagrams/ORDER-fullstack-diagram-20261005.md 할 일 1 · 골 축 = 표 A·표 C·원문 5
> 수집 시각(UTC) · 머신 hostname(`hostname -s`) · HEAD sha(`git rev-parse --short HEAD`)
> [사실] N줄 · [추측] M줄
```
