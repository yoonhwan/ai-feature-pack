# r445 master 집행 순서 (나노 산출 · 설치·실사건은 master 손)

## 실측 정정 (나노 · 2026-10-19)
- BYZ `origin/main` 의 `.claude/hooks/context-distill-gate.sh` 는 이미 **키트 사본(622행 · 400k/450k)** 이다(a2a1a0a934 · 217e9e317f). 카드가 본 «BYZ 300k/450k · 15-16행 · force_pct» 는 **공용 루트 체크아웃의 옛 파일(157행 · c6b644015f 2026-07-06)** — 루트 `main` 이 origin/main 보다 21520 커밋 뒤라 그 사본이 남아 있다.
- 그래서 BYZ 변경 = 키트 새 훅을 그대로 복사(cmp0). force_pct 줄은 origin/main 에 없다(유지할 줄 0).
- ★루트에서 뜬 claude 좌석(`CLAUDE_PROJECT_DIR` = 루트)은 지금도 옛 300k/450k 훅을 탄다★ — 설치 2 에서 루트도 cp 대상.
- BYZ `CLAUDE.md` 의 해당 줄은 337행이 아니라 268행(origin/main 기준).

## 순서
1. 착지 2: 팩 `nano/r445-distill-threshold-550k-warn-600k-bl`(키트) · BYZ `nano/r445-distill-threshold-550k-warn-600k-bl`(훅 사본 + 문서 2).
2. 설치(되돌림 = `.bak-r445`):
   - 홈 훅: `cp ~/.claude/hooks/context-distill-gate.sh ~/.claude/hooks/context-distill-gate.sh.bak-r445` → 키트 템플릿 cp → `cmp` 0.
   - BYZ 훅: 루트 + 활성 워크트리 전부 `.claude/hooks/context-distill-gate.sh` ← main 착지본 cp → 각 `cmp` 0(#3 RULE 워크트리 sync).
   - 홈 문서 2(master 손): `~/.claude/CLAUDE.md` 오케스트레이션 절 «컨텍스트 450k에서 증류 경고, 600k…» 문단 → «550k 경고 · 600k 차단 · 프로젝트 훅도 같음(이원화 끝)» · `~/.claude/rules/orchestration.md` 증류 줄 → «550k warn · 600k 차단 · BYZ 동일». CLAUDE_MASTER_SYNC 블록엔 임계값 글자 0 → 전파본 갱신 0.
3. 실사건 1: 어느 claude 좌석의 `~/.claude/logs/context-distill-gate.log` 에 `block_at=600k` 행(deny/exempt) 또는 warn 주입문 «경고선(550k)» 1건.
4. ②③④: codex `~/.codex/config.toml:1-3`(window 1M · auto_compact 780k · scope total) · opencode `~/.config/opencode/opencode.json:7-10`(compaction auto true · prune true) — 이 단위 전후 sha256 동일(나노 실측: config.toml d2d133ef… · opencode.json 0b46c400…) → 변경 0.

press 필요: 없음(훅 값 변경 · 단위 시험으로 닫힘).
