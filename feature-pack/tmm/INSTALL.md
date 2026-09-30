# tmm 설치 (에이전트 자동 수행)

이 문서를 읽은 에이전트는 다음을 자동 수행한다.

## 사전 요구

```bash
command -v bash >/dev/null && [ "${BASH_VERSINFO[0]}" -ge 4 ]   # macOS 기본 bash 3.2 는 불가 → brew install bash
command -v tmux >/dev/null
command -v fzf  >/dev/null                                       # brew install fzf
command -v python3 >/dev/null                                    # 종료 뷰 스캐너 (표준 라이브러리만) — 0.54 이상 (bell·--listen·--track)
command -v curl >/dev/null                                       # 자동 갱신이 fzf 소켓에 POST 할 때 사용
```

필수 세트:

- `tmuxc` (feature-pack/tmuxc) **>= 0.4.0** — `tmm s` 도달확인, `tmm save`, 복구 규약, 그리고 **fork**(동일엔진 네이티브 `tmuxc fork`). **없으면 install.sh 가 중단**한다. 먼저 `bash feature-pack/tmuxc/install.sh`.
  - 0.4.0 미만이면 크로스엔진 fork 는 되지만 동일엔진 네이티브 fork 는 안 된다(경고만).

선택:

- Tailscale — 집 밖 접속.

## 설치 단계

### 1) install.sh 실행

```bash
bash feature-pack/tmm/install.sh
```

수행 내용:

1. `bash>=4`, `tmux`, `fzf` 확인 (누락 시 exit 2 + 설치 명령 안내)
2. `~/.tmm/versions/<version>/core/` 에 본체·libexec 복사, `~/.tmm/current` 심링 갱신
3. `~/.local/bin/tmm` 심링 (기존 일반 파일이 있으면 백업 후 교체)
4. `~/.local/bin` PATH 미등록이면 `~/.zshrc`/`~/.bashrc` 에 추가
5. `~/.zshrc` 에 `alias tmm=` 이 있으면 경고 (alias 가 바이너리를 가로챔)
6. `~/.tmm/categories` 가 없으면 예시 복사 (있으면 보존)
7. `~/.tmm/models` 가 없으면 예시 복사 (fork 모델 별칭 — 있으면 보존), `~/.tmm/forks/` 생성
8. `tmm doctor` 로 검증

### 2) 카테고리 규칙 편집

`~/.tmm/categories` 를 열어 실제 세션명 접두에 맞게 고친다. 형식은 `글롭<TAB>라벨`, 위에서부터 첫 매치. 규칙에 안 걸리면 역할 접두(`FB_`·`ft-`, `TMM_CAT_STRIP`)를 뗀 세션명의 첫 토큰(`-`/`_` 앞 5자)이 라벨이 된다 — `FB_CCU#0` 과 `CCU_ARCH#3` 은 둘 다 `CCU`, `ft-v65-…` 는 `v65`. 그래서 규칙 파일에는 «일반화로 안 되는 것»(별칭 병합·대소문자 통일)만 적으면 된다.

```bash
tmux ls -F '#S' | sed 's/#[0-9]*$//' | sort -u     # 현재 접두 목록 보기
```

### 3) 검증

```bash
tmm doctor
tmm ls | head            # 목록 (상태 열이 ? 면 seat-scan 경로 확인 → TMM_SCAN)
bash feature-pack/tmm/test/verify.sh   # 격리 tmux 소켓에서 회귀 (기존 세션 무접촉)
```

### 3-1) fork 모델 별칭 (선택)

`~/.tmm/models` 에 자주 쓰는 별칭을 직접 적거나, 라이브 목록에서 생성한다.

```bash
tmm models refresh                       # 각 CLI 라이브 목록 → ~/.tmm/models.generated (opencode=openrouter 기본)
TMM_MODELS_PROVIDER=opencode tmm models refresh   # opencode zen 게이트웨이로 생성
tmm models find deepseek-v4.1            # 별칭/모델 id 검색
```

**opencode 프로바이더 주의**: `--model` 접두사가 곧 게이트웨이다. `opencode/...` = zen(자체), `openrouter/...` = OpenRouter.
크레딧이 OpenRouter 에 있으면 별칭이 `openrouter/...` 여야 한다(`opencode/deepseek-v4.1-flash` 는 없고 `openrouter/deepseek/deepseek-v4.1-flash` 에 있다).

### 4) 모바일 연결 (Termius 예)

1. Mac: 시스템 설정 → 일반 → 공유 → 원격 로그인 켜기.
2. 키: `ssh-keygen -t ed25519 -f ~/.ssh/mobile_ed25519 -N ''` → `cat ~/.ssh/mobile_ed25519.pub >> ~/.ssh/authorized_keys`.
   개인키(`~/.ssh/mobile_ed25519`)는 1Password 등에 저장 → 폰 Termius Keychain 에 붙여넣기.
3. 주소: 같은 Wi-Fi 면 `ipconfig getifaddr en0`, 밖에서는 `tailscale ip -4`.
4. Termius 호스트: 주소 · 포트 22 · 사용자 · 키 · **Startup command: `tmm`**.
5. 데스크탑에서 자가 테스트:
   ```bash
   ssh -i ~/.ssh/mobile_ed25519 -o IdentitiesOnly=yes <IP> -t 'zsh -ilc tmm'
   ```
   비대화 ssh 는 PATH 가 `/usr/bin:/bin` 뿐이라 `zsh -ilc`(로그인+인터랙티브) 로 감싸야 `tmux`/`tmm` 이 잡힌다. Termius 의 Startup command 는 로그인 셸에서 실행되므로 그대로 `tmm` 이면 된다.

## 제거

```bash
bash feature-pack/tmm/uninstall.sh     # ~/.tmm/categories 는 보존
```

## 트러블슈팅

| 증상 | 원인 / 처방 |
|---|---|
| `^A` `^D` 를 누르면 뷰가 안 바뀌고 tmm 이 종료됨 | 0.6.x 결함 — tmux 프리픽스(`C-a`)가 피커의 `^A` 를 먹음. 0.7.0 은 피커 세션 프리픽스를 끔 — 재설치 후 **`tmm` 세션을 새로 연다**(이미 떠 있는 옛 `tmm` 세션은 옵션이 없음: `^X` 로 끝내고 다시 실행) |
| 좌석에서 `C-a d` 가 tmm 으로 안 돌아오고 셸로 나감 | 0.6.x — 직전 세션이 피커가 아니면 detach. 0.7.0 은 출발 피커를 기록해 복귀 |
| 종료 뷰에 좌석뷰에서 친 키워드가 남아 있음 | 0.6.x — 키워드가 뷰 간 공유. 0.7.0 은 뷰별 기억 |
| Enter 를 눌러도 attach 안 됨, `can't use /dev/tty` | 구버전(fzf execute 안에서 attach). 0.1.0 은 fzf 밖에서 attach — 재설치 |
| Enter 가 필터만 갱신하는 듯 | 목록 로딩 중(`0/0`) 에 누름. `--sync` 로 첫 화면이 완성 후 뜨니 `좌석>` 가 보이면 누른다 |
| 화면 오른쪽·아래가 점(…)으로 채워짐 | ① `-i`(ignore-size) attach 였나 ② `tmux show -wv -t '=NAME:' window-size` 가 `manual` — 좌석의 `resize-window` 관행이 남긴 것. 0.4.8 은 attach 직전 자동 해제 — 재설치. 수동: `tmux set -wu -t '=NAME:' window-size` |
| 상태 열이 전부 `?` | seat-scan 미발견. `tmm doctor` → `TMM_SCAN=/path/seat-scan.sh` |
| 목록이 3초 넘게 걸림 | 좌석 수 × seat-scan. `TMM_CACHE_TTL` 을 늘리면 필터·재정렬은 캐시. 첫 로딩은 못 줄임 |
| 메시지가 셸에 타이핑됨 | tmm 가드는 pane 자식 프로세스 유무로 판정. 에이전트가 pane 의 자식이 아닌 구조(예: nohup)면 `tmm ss` 로 상태 먼저 확인 |
| `tmm` 이 엉뚱한 동작 | `type tmm` → alias 면 `~/.zshrc` 에서 제거 |
| 종료 뷰가 0건 | `tmm doctor` 의 dead-scan 줄 확인. 창이 좁으면 `^]`. 방금 재부팅했는데 0건이면 `TMM_LIVE_GRACE` 안(90초)이라 제외된 것 — 잠시 후 `^R` |
| 종료 뷰에 스냅샷 없는 세션이 안 보임 | 정상 — 스냅샷 없이도 트랜스크립트로 잡는다. 안 보이면 `~/.claude/projects/*/*.jsonl` 에 그 세션 파일이 있는지, mtime 이 창 안인지 확인 |
| 복구했더니 200K 창으로 떴다 | `tmuxc model NAME` 로 확인. fable 이 아닌데 `[1m]` 이 없다면 SNAP 경로(스냅샷 argv 그대로)였을 가능성 — 스냅샷이 200K 로 저장된 세션. 세션 안에서 `/model` 로 바꾸거나 `tmuxc save` 를 다시 |
| 복구 후 «부팅 확인 못 함» | 세션은 남아 있다. attach 해서 pane 을 본다. 대개 headroom 프록시 지연 |
| 자동 갱신이 안 돎 (헤더는 `pane:5s all:20s`) | `tmm doctor` 의 fzf 버전(≥0.54)·curl 확인. 소켓은 `$TMPDIR/tmm-<uid>/run-<pid>/fzf.sock` |
| 헤더 뒤쪽 키 안내·`auto:` 가 안 보임 | 0.1.0 헤더가 60열을 넘어 fzf 가 잘랐음. 0.2.0 은 3줄·각 60열 이내 — 재설치 |
| `^R` 누르면 정렬이 최근순으로 돌아감 | 0.1.0 결함. 0.2.0 은 현재 모드 유지 — 재설치 |
| 미리보기가 흑백·바닥에 branch/OMC 줄·오래된 내용부터 | 0.2.0 이하 렌더. 0.2.1 은 색 유지·statusline 제거·바닥 우선 — 재설치. 그래도 statusline 이 남으면 `tmux capture-pane -p -e -J -t '=NAME:' \| tail -8` 로 입력박스 모양이 «구분선→`❯`» 인지 확인 |
| `tmm idx NAME` 이 "인덱스 없음" | `tmm idx NAME --json` 의 `match` 확인. 라이브 claude 는 cwd 슬러그 + `agentName` 매치 실패 시에만 실패(신규 세션은 최근 활성 파일로 폴백). codex/cmd 는 cwd 매칭, opencode 는 `opencode.db` |
| `^Y` 를 눌러도 화면이 안 바뀜 | fzf ≥ 0.54 필요(`execute`). `tmm doctor` 로 fzf 확인. 정보화면은 아무 키로 복귀 |
| fork 했는데 동일엔진인데도 전체 히스토리가 안 이어짐 | `tmuxc fork` 부재(tmuxc < 0.4.0). `tmuxc fork` 실행해 usage 나오는지 확인 → tmuxc 재설치. 그 전엔 크로스엔진 경로(경로·발췌 주입)만 동작 |
| fork 모델 메뉴가 빔 | `~/.tmm/models` 없음. `install.sh` 재실행(예시 복사) 또는 `tmm models refresh` |
| fork 모델 메뉴에 원하는 모델이 없음 | `tmm models refresh` (라이브 목록 갱신) → `tmm models find QUERY` 로 확인. 별칭은 `~/.tmm/models` 에 직접 추가 가능 |
| fork 가 opencode zen 으로 열려 크레딧이 안 잡힘 | 별칭이 `openrouter/...` 인지 확인. `TMM_MODELS_PROVIDER=openrouter tmm models refresh`. `opencode/` = zen(자체), `openrouter/` = OpenRouter |
| fork 하다가 취소하고 싶다 | 어느 프롬프트에서든 `^C`(이름/에이전트/모델은 `q`). 생성 중에는 아무 키 — 만들어지던 세션까지 정리하고 피커로 복귀 |
| fork 후 새 세션이 직전 작업을 못 이어감 | 발췌 파일(`~/.tmm/forks/`) 존재·크기 확인. `TMM_FORK_EXCERPT_N` 를 늘리거나 `--prompt` 로 지시 보강. 라이브 소스는 `^Y` 로 원문 경로를 확인해 새 세션에 직접 주소를 줄 수 있다 |
