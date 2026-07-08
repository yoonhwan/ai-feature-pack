# tmuxc 재해 복구 레퍼런스 (UC8 + UC11)

> tmux 세션/서버 장애 복구. SKILL.md 본문에서 분리(on-demand) — 평상시 불필요, 장애 시에만 Read.
> UC8 = cmux 미러 디스커넥트(서버 살아있음) / UC11 = 서버 프로세스 사망(세션 소실).
> **먼저 구분**: `tmux list-sessions`가 `attached=0`이면 UC8, `no server running` 에러면 UC11.

---

## UC8: cmux 디스커넥트 복구 (`tmuxc recover`)

cmux(cmuxterm.app) 워크스페이스에서 보던 tmux 세션들이 `[server exited unexpectedly]`로 한꺼번에 끊겼을 때 자동 재연결. **(주의: tmux 서버 자체가 죽은 게 아니라 cmux 미러 연결만 끊긴 경우. 서버 사망은 UC11.)**

**배경 (2026-05-31 실측)**: cmux는 자체 tmux 호환 레이어(`pipe-pane`/`set-hook`/`respawn-pane`)를 가진 멀티플렉서. 그 안에서 `tmux -CC`(control 모드)로 미러링하면 control 스트림이 충돌 → 미러 클라이언트가 동시에 끊김. **tmux 서버·claude는 안 죽고 `attached=0`이 될 뿐.**

**진단 (죽음 vs 단순 디스커넥트 구분)**:
1. `tmux list-sessions -F "#{session_name} attached=#{session_attached}"` → 전부 `attached=0`이면 연결만 끊긴 것 (서버 살아있음)
2. claude 생존 확인: `ps -o time= -p <pids>`를 시차 두고 2회 → CPU time 증가 = 살아서 연산 중
3. pane이 `node` 아닌 값(`2.1.158` 등)으로 보여도 오탐 — `pgrep -P <pane_pid>`로 자식 claude 직접 확인
4. **`tmux list-sessions` 자체가 "no server running" 에러면 → 서버 사망(UC11 restore)**

**복구 동작**:
1. cmux 생존 확인: `CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux; "$CMUX" ping` → `PONG`
2. 대상 워크스페이스 ref 확인: `"$CMUX" list-workspaces`
3. 각 detached tmux 세션마다:
   ```bash
   out=$("$CMUX" new-pane --workspace <ws-ref> --direction down)   # 새 페인
   surf=$(echo "$out" | grep -oE 'surface:[0-9]+' | head -1)
   "$CMUX" focus-panel --panel "$surf" --workspace <ws-ref>
   for try in 1 2 3 4 5 6; do                                      # PTY lazy spawn 대기
     sleep 1
     "$CMUX" send-panel --panel "$surf" --workspace <ws-ref> "tmux attach -t <session>" && {
       "$CMUX" send-key-panel --panel "$surf" --workspace <ws-ref> Enter; break; }
   done
   ```
4. 검증: `tmux list-sessions -F "#{session_name} att=#{session_attached}"` → 전부 `att=1`

**핵심 함정**:
- `cmux send --surface ...`는 `Surface is not a terminal`로 막힘. 입력은 반드시 **`send-panel --panel`** (panel 레벨). Enter는 `send-key-panel --panel ... Enter`.
- `new-pane` 직후 PTY는 **lazy spawn** — 즉시 send하면 흘러감. 셸 프롬프트 뜰 때까지 재시도 루프 필수. 명령이 흘렀으면 `send-key-panel C-c`로 정리 후 재주입.

**규칙**: cmux 안에서는 `tmux -CC`(control 모드) **절대 금지**, 일반 `tmux attach`만 사용 (control 모드가 충돌 원인).

---

## UC11: tmux 서버 사망 복원 (`tmuxc restore`)

**tmux 서버 프로세스 자체가 죽어**(대표: PC 재부팅) 모든 세션이 소실된 상황(UC8과 달리 세션이 아예 없음). claude/codex 작업 세션은 디스크에 보존되므로, **세션 로그에서 복구 대상을 자동 식별해 tmux를 재생성하고 resume으로 대화까지 복원**한다.

### 11-0. 자동 복구 (구현됨 — `tmuxc restore`, v0.2.0)

재부팅 후 이 명령 하나로 복구한다:
```bash
tmuxc restore                    # 스캔 → 통합 리스트업 → 대화형 선택 → 복구·레디
tmuxc restore --select all --go  # 비대화형 일괄 복구
tmuxc restore --select 1,3,5 --go
tmuxc restore --select claude --go   # claude 세션만 (codex 도 동일)
tmuxc restore --baton --select 1 --go  # --resume 없이 새 세션 + /baton:resume (경량)
tmuxc restore --since 48         # 시간창 확대 (기본 24h)
tmuxc restore --loose            # 세션명 규약(#N) 필터 해제 — ad-hoc claude 세션까지
```

**판별 엔진** (`core/libexec/tmuxc-restore-scan.py`) — 2026-07-08 실측 확립 로직:
- **정렬 키 = jsonl 내부 마지막 유효 라인의 `timestamp`** (재부팅 시 mtime이 한 시각으로 뭉개지므로 mtime 불사용). 파일 끝 64KB만 tail-seek → 833개도 수 초.
- **claude 스캔** (`~/.claude/projects/*/*.jsonl`): `isSidechain` / baton 헤드리스 / 영어 DA 프롬프트 / user 텍스트 0개 세션 제외. 세션명은 user 메시지의 `세션명(me)=X` → `[A→B]`의 B 순으로 추출(부연 절삭). 기본은 `#N` 카운터 있는 tmuxc 규약 세션만(해제=`--loose`). 모델은 assistant `"model"` 최빈값 → `ccf`/`ccs`/`ccd` alias 라우팅(런타임 `zsh -ic type` 해석 — 미해석 시 해당 세션 스킵+에러 표기, 일반 claude 우회 금지).
- **codex 스캔** (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`): 첫 줄 `session_meta`에서 session_id·cwd, 세션명은 `~/.codex/session_index.jsonl`의 `thread_name`(1순위 — 없으면 헤드리스로 간주·제외). resume은 `codex resume {session_id}`(UUID 인자, 0.142.4 확인).
- **공통 필터**: 같은 base의 증류 체인(`#N`)은 최대 N만 / `lsof`로 로그를 물고 있는 **라이브 프로세스 세션 제외**(살아있는 세션 오탐 방지) / cwd 소실은 `no-cwd`로 표기만 하고 스킵 / 동명 tmux 세션 존재 시 스킵.
- **레디 확인**: claude는 statusline `ctx:` 출현 폴링(resume 세션은 ctx:0%가 아님), codex는 pane 자식 프로세스 생존. 복원 후 COMM-GUIDE 재주입.
- tmux 서버가 살아있으면 UC8(디스커넥트) 오진 경고를 먼저 낸다.

### 11-1. 사망 감지
```bash
tmux list-sessions 2>&1   # "no server running on ..." 또는 "error connecting" = 서버 사망
```

> 아래 11-2/11-3은 `tmuxc restore` 미설치 환경이나 수동 개입이 필요할 때의 수동 절차다.

### 11-2. claude 세션 인덱스 조회
claude는 프로젝트별로 세션을 저장한다:
```
~/.claude/projects/{project-path-hash}/sessions-index.json
```
**스키마는 `{version, entries:[...], originalPath}` envelope (dict)** — 실측 검증. 각 엔트리: `{ sessionId(UUID), fullPath(JSONL), summary, firstPrompt, messageCount, modified, projectPath, gitBranch, isSidechain }`. (구버전이 bare array일 가능성도 방어.)
```bash
# 최근 세션 후보 나열 (프로젝트별) — entries 배열에서 추출
for idx in ~/.claude/projects/*/sessions-index.json; do
  python3 - "$idx" <<'PY'
import json,sys
d = json.load(open(sys.argv[1]))
entries = d["entries"] if isinstance(d, dict) else d   # dict envelope / bare array 모두 대응 (#0 RULE: 스키마 불일치 시 KeyError로 시끄럽게 실패)
for e in entries:
    print(e.get("sessionId"), e.get("gitBranch"), e.get("projectPath"), "|", (e.get("summary") or "")[:60])
PY
done
```
또는 claude 종료 시 화면에 뜨는 `Resume this session with: claude --resume {uuid}`의 uuid를 직접 사용.

### 11-3. 복원 (tmux 재생성 + claude --resume 동시)
각 복원 대상 세션마다:
```bash
tmux new-session -d -s {name} -c {projectPath}
# ccd 해석 결과 + --resume {sessionId} (remote-control은 새 세션명으로)
tmux send-keys -t {name} -l "{ccd-resolved} --name {name} --resume {sessionId} --remote-control {name}"
tmux send-keys -t {name} Enter
```
- 부팅 후 **통신 가이드 주입** (UC1 step 8과 동일) — resume된 세션도 최신 통신 표준을 재수신.
- `--resume {sessionId}`가 **직전 대화 전체 컨텍스트**를 복원(증류 10-3보다 완전, 단 무거움).
- 가벼운 복원이 필요하면 `--resume` 대신 신규 claude + `/baton:resume`(핸드오프만) 사용.
- `--all`: 인덱스의 활성 프로젝트별 최신 세션을 일괄 재생성.

### 11-4. 재발 방지
- tmux 서버 사망 원인은 대개 OOM/충돌. 중요 세션은 baton handoff를 주기적으로 저장(`/baton:save`)해 두면 `--resume` 실패 시에도 핸드오프로 복원 가능.
- 이중 멀티플렉서(cmux 안 tmux + `-CC`)는 서버 충돌 위험을 키움 — UC8 규칙 준수.
