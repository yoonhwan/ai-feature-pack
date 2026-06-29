# baton × tmuxc 운영 트러블슈팅 레퍼런스

> tmuxc 증류 + baton save/resume + 세션간 송신에서 반복되는 함정과 1줄 처방.
> SKILL.md UC10-4(baton 연계)에서 참조. 자동 로드 안 됨(on-demand) — 막히면 Read.
> 형식: 증상 → 원인 → 처방. 신규 함정은 위에 추가.

---

## 1. `baton save` 거부 — `❌ CURRENT.md 없음`

**증상**: 증류하려 `baton save` 했는데 `CURRENT.md 없음. /baton:wt-create 또는 /baton:plan 먼저`로 하드 거부.
**원인**: tmuxc로 직접 발주된 ad-hoc 세션은 wt-create/plan을 안 거쳐 `.baton/handoff/`가 없음. (2026-06-13 FB_MR_DA 실증)
**처방**: 수동 템플릿 sed/cp 금지. 정본 명령으로 스캐폴드 후 재시도 (v1.2.11+):
```bash
bash ~/.baton/current/bin/baton init-handoff <phase-id>   # phase-id = 작업요약 kebab-case
# CURRENT.md의 CONTEXT_PACK/VERIFIED 채우고 → baton save
```
main/master root에서는 거부됨(옵션 B) — 워크트리 안에서만.

---

## 2. baton CLI 함수가 조용히 죽음 — `set -e` + `var=$(failing-cmd)`

**증상**: baton 명령이 출력 없이 중간에 끝남(에러 메시지도 없이).
**원인**: baton bin은 `set -euo pipefail`. `var=$(cmd)`에서 cmd가 비0 exit하면 set -e가 트립해 함수 조기 종료. (2026-06-13 warming-done의 `elapsed=$(...)` 실증)
**처방**: 실패 허용 substitution은 `|| true` 명시:
```bash
elapsed=$(baton_warming_elapsed "$dir" 2>/dev/null || true)
```

---

## 3. `baton status` exit 128 (출력은 정상)

**증상**: `baton status` 출력은 멀쩡한데 종료코드 128 → `&&` 체인·CI가 실패로 오판.
**원인**: `.worktrees/` 하위에 git 메타(`.git/worktrees/<name>`) 깨진 stale 디렉토리가 있으면 루프 내 `git branch --show-current`가 `fatal` + exit 128 → 마지막 반복일 때 함수 반환값 오염. (2026-06-13 fb-tqa-realtime 실증)
**처방**: v1.2.13에서 fix됨(git 흡수 + `return 0`). stale 워크트리는 status에 `⚠ stale(git 메타 없음 — git worktree prune 후보)`로 표기 → `git worktree prune`로 정리(HIL).

---

## 4. CONTEXT_PACK 라인핀이 틀림

**증상**: resume 후 CONTEXT_PACK의 `파일:라인`을 열었더니 엉뚱한 위치(수~수백 줄 오차).
**원인**: save 시 라인을 **기억으로** 적음. (2026-06-13 도그푸딩 실증: core.sh:294로 적었으나 실제 함수는 689)
**처방**: 라인핀은 반드시 `grep -n`으로 실측해 적는다. 함수가 여러 곳이면 대표 라인 + 괄호 보조 라인 병기.
**더 나은 패턴**: resume 시 라인핀을 수기로 믿지 말고 **haiku 요약 에이전트가 grep으로 실시간 생성** — 도그푸딩에서 haiku가 수기보다 정확한 라인을 회수함.

---

## 5. tmux send-keys 메시지 미제출 (입력창에 남음)

**증상**: 세션간 메시지를 보냈는데 상대가 못 받음. capture-pane에 `❯ [orch→me] ...`로 입력창에 떠있음.
**원인**: `-l "msg" Enter`를 한 콜에 합치거나, 멀티라인 메시지라 첫 Enter가 줄바꿈으로 먹힘.
**처방**: COMM-GUIDE §2 검증 송신 — `-l "msg"` 전송 → `sleep 0.3` → **별도 콜로 `Enter`** → `sleep 2` → `capture-pane | grep -F`로 도달 확인. 입력창에 남아있으면 `Enter` 1회 더. **도달 확인 전 "전송 완료" 보고 금지.**

---

## 6. `ccs`/`ccd`/`ccf` alias 미정의 또는 effort 누락

**증상**: 증류 신규 세션 기동 시 `ccs: command not found` 또는 모델/effort가 의도와 다름.
**원인**: `~/.zshrc`의 3-tier alias 누락/불일치. (2026-06-13 ccs 미정의 + ccd effort 누락 실증)
**처방**: UC1-4 3-tier 확인 — `ccs`(sonnet/effort max, 워커) / `ccd`(opus/effort high, 오케·검증) / `ccf`(fable/effort medium, 설계). `zsh -ic 'type ccs ccd ccf'`로 해석 검증. send-keys 기동 시 alias 대신 resolved 명령(`~/.headroom/claude-hr.sh --model ... --effort ...`)을 직접 쓰면 alias 의존 회피.

---

## 7. claude --remote-control 부팅 대기 오판

**증상**: 신규 세션에 메시지 보냈는데 허공에 흘러감(claude 부팅 전).
**원인**: `tmux new-session` 직후 PTY/claude가 아직 안 떴는데 즉시 send.
**처방**: 부팅 폴링 — `capture-pane`에 `❯`(빈 프롬프트) + statusline `ctx:0% | /rc active` 뜰 때까지 3초 간격 재시도(보통 9~12초). 그 후 COMM-GUIDE 주입 → 프롬프트.

---

## 9. `baton warming-done`이 거짓 큰 값 (예: 1204s)

**증상**: 방금 띄운 세션인데 워밍이 수백~수천 초로 비현실적.
**원인**: warming 계측은 `baton resume` CLI 실행 시 `resume_start`를 찍는다. 세션을 **RESUME_MSG 텍스트로만 시작**(tmuxc 증류의 일반 패턴)하면 resume_start가 안 찍혀, warming-done이 **직전 세션의 오래된 resume_start**를 재측정. (2026-06-13 도그푸딩2 실증)
**처방**: v1.2.13에서 소비 가드 fix됨 — 이미 측정된 resume_start는 무효 처리하고 "baton resume CLI 경유 세션에서만 계측" 안내. **워밍을 계측하려면 세션이 `baton resume`를 실제 실행해야 한다**(텍스트 RESUME_MSG만으로는 미계측이 정상). `baton warming-stats`로 추이 확인 시 거짓값이 평균을 왜곡하면 `.warming.jsonl`에서 해당 줄 제거.

---

## 8. 멀티워크플로우 컨텍스트 축소 (에러 아님 — 활용 패턴)

**언제**: resume 선로딩/로그 풀서치/다파일 리뷰로 본체 ctx가 빠르게 차는 게 우려될 때.
**패턴**: Workflow `agent(..., {model:'haiku'})` 병렬로 파일을 격리 컨텍스트에서 읽히고 본체엔 요약만 회수. 2026-06-13 실측: 7파일 307k토큰 격리 / 본체 ~0.5KB = **본체 99%+ 절약**(11.7s). 직접 Read는 ctx 0→46%였음.
**주의**: 요약은 압축 — 원문 정밀 편집이 필요한 파일만 본체 Read(하이브리드). 서브에이전트는 세션 모델 상속이라 저비용은 `model` 명시 필요(effort는 서브에이전트 단위 설정 불가, 세션 레벨만).
