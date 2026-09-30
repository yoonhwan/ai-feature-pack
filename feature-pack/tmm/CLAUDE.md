# tmm — 작업 지침 (이 폴더에서 세션을 열면 자동 로드)

> 정본은 이 파일. `AGENTS.md`는 심링(codex/기타 에이전트용). 둘을 따로 고치지 말 것.

## 이게 뭔가

폰(Termius/SSH)에서 수십 개 tmux 에이전트 좌석을 커서로 고르고 붙는 fzf TUI. 사용자는 iPhone Termius의
Startup command `tmm`으로 진입한다. **폰 화면 60~80열, Ctrl 키는 툴바 탭**이 모든 UI 판단의 전제다.

- 본체: `core/bin/tmm` (bash, 단일 파일). 상태 판정은 `core/libexec/seat-scan.sh`(tmuxc 스킬 사본, 수정 금지 — 원본은 `~/.claude/skills/tmuxc/scripts/seat-scan.sh`, 바뀌면 여기 다시 복사). 트랜스크립트 인덱스 해석·fork 발췌는 `core/libexec/tmm-dead-scan.py`(`resolve`/`excerpt` 서브커맨드).
- 설치본: `~/.tmm/versions/<VERSION>/` → `~/.tmm/current` → `~/.local/bin/tmm` 심링. 카테고리 규칙 `~/.tmm/categories`, fork 모델 별칭 `~/.tmm/models`, fork 발췌 `~/.tmm/forks/`.
- 사용자 문서: `README.md`(기능·키·함정) · `INSTALL.md`(설치·트러블슈팅). 코드를 바꾸면 이 둘도 같은 커밋에서 맞춘다.

## 개선 작업 절차 (매번 이 순서)

1. `bash test/verify.sh` 먼저 — 격리 tmux 소켓에서 돈다. 통과 못 하면 시작하지 않는다.
2. 코드 수정 → `bash -n core/bin/tmm` → `bash test/verify.sh` 재통과.
3. **폰 경로로 실측** (아래 "검증 방법"). 로컬 pty나 tmux 안에서 돌린 결과는 폰 결과가 아니다 — `/dev/tty` 오류가 그렇게 새어 나갔다.
4. `core/VERSION` 올리고 `bash install.sh` 로 로컬 설치본 갱신 → `tmm doctor`.
5. README/INSTALL 반영 → 커밋(`[feat]`/`[fix]`/`[test]` 접두, main 직접) → push.

## 검증 방법 (폰과 같은 경로)

```bash
# 데스크탑 자가 테스트 alias (~/.ssh/config `mac-mobile-test`, 키 ~/.ssh/termius_mobile_ed25519)
ssh -i ~/.ssh/termius_mobile_ed25519 -o IdentitiesOnly=yes 100.92.216.120 -t 'zsh -ilc tmm'

# 키 주입 자동화 — stdin 파이프 + ssh -tt (expect 는 pty 0x0 이라 fzf 가 안 그린다)
( sleep 8; printf 'diag'; sleep 1.5; printf '\r'; sleep 3; printf '\001d'; sleep 3; printf '\030' ) \
  | ssh -tt -o BatchMode=yes mac-mobile-test 'export TERM=xterm-256color; stty cols 60 rows 24; zsh -ilc tmm'
```

판독은 ANSI 제거 후 마커 순서로: `좌석>` → `git:(`(attach 성공) → `좌석>`(복귀) → exit 0. `can't use /dev/tty` 가 한 번이라도 보이면 실패.
실험 대상 좌석은 **셸만 있는 좌석**(`tmm ls | grep ○`)을 쓴다. 에이전트 좌석에 키를 흘리면 진행 중 작업을 깬다.

## 절대 규칙

- **기본 tmux 서버의 좌석에 send/kill/detach 하지 않는다.** 테스트는 `TMUX_TMPDIR` 격리 소켓(verify.sh 방식) 또는 셸-only 좌석으로만.
- **좌석별 tmux 호출 루프 금지.** 65좌석 × 3호출 = 6초였다. `list-panes -a -F` 한 번으로 받고, 좌석당 꼭 필요한 capture는 `xargs -P 8`.
- **attach/메시지 입력은 fzf 밖에서.** `--bind execute()` 안에서는 tty가 없다. `--expect` 로 (키, 선택) 만 받아 본체 루프가 처리한다.
- **`--sync` 유지.** 빼면 로딩 중 Enter 가 빈 선택으로 흡수돼 "Enter 가 안 먹는다"로 보고된다.
- **`capture-pane -t "=NAME:"`** (콜론 필수). `has-session`/`display` 는 `=NAME`.
- **에이전트 판정은 `pane_current_command`.** `pgrep -P pane_pid` 는 zsh 플러그인 자식(gitstatusd)을 에이전트로 오판한다.
- **`tmuxc send` 는 무가드**다. 셸 pane 에 그대로 타이핑된다. tmm 의 가드를 우회하는 경로를 만들지 않는다.
- 이름을 `tm` 으로 바꾸지 않는다 — 사용자 zshrc 의 `alias tm=` 이 가로챈다.
- 시각 마커 정규식은 한국어(`done 오후 12:56`)·영어(`done 12:56 PM`) 둘 다 유지.
- **attach 직전 `set -wu window-size`** (`cmd_attach`, `-i` 제외). `window-size manual` 의 출처는 `new-session -d` 가 아니라 좌석들의 `resize-window -x 200 → 원복`(ctx 읽기) 관행이다 — 격리 실측 2026-09-09. 스폰 경로의 `set -wu` 는 보험일 뿐 근본 방어가 아니다. verify (p).
- **복구 커맨드는 fable 계열 제외 전부 `[1m]`** (`with_1m`). 사용자 확정 2026-09-09 — «작은 창으로 절대 열지 않는다». 스냅샷 `resume_cmd` 는 그대로 존중.
- **종료 세션 스캐너(`tmm-dead-scan.py`)는 읽기 전용**. 트랜스크립트·스냅샷·opencode DB 를 쓰지 않는다. 라이브 세션 제외 3중(ps argv uuid · tmux 세션명 · mtime 90초)을 빼지 않는다 — 빼면 살아있는 세션을 «종료» 로 보여 주고 복구가 동명 세션 생성으로 실패한다.
- **`rows-cur` 는 `$RUN/view` 를 따른다.** ^R·20초 자동 갱신이 이것만 부르므로, dead 뷰 분기를 여기서 빼면 20초 뒤 살아있는 목록으로 되돌아간다.
- **헤더는 4섹션(이동/정렬/화면/상태 · dead 는 복구/창/정렬/상태) + 색(키 청록·설명 회색·섹션 노랑)**. 각 줄 표시폭 ≤58(fzf 들여쓰기 2). 새 키는 해당 섹션에 넣고 verify (j) 로 잰다. `?` 는 필터 문자 — 바인드 금지(도움말은 `^/`).
- **레이아웃 폭 판정은 `term_cols`** (= FZF_COLUMNS + FZF_PREVIEW_COLUMNS). `tput cols` 는 fzf 자식에서 80 고정이라 쓰지 않는다. fzf 0.74 에 `transform-preview-window` 없음 → `transform($SELF pw-action)`.
- **tmuxc 는 필수 세트** — install.sh 가드·doctor·manifest required 를 같이 유지. **fork 는 tmuxc >= 0.4.0 필요**(`tmuxc fork` 네이티브).
- **fork 는 «소스 대화를 새 에이전트 세션으로 이어받기»다** (기능2, 0.6.0). 동일 엔진은 `tmuxc fork`(네이티브 — 전체 히스토리·부모 불변·새 conversation id), 크로스 엔진은 `tmuxc open` + 트랜스크립트 경로·발췌 주입. **스폰·창옵션·COMM-GUIDE 주입을 tmm 이 재구현하지 않는다** — 전부 tmuxc 위임. 이름 기본=소스 `#N`→`#N+1`, 충돌 시 자동 증가. 모델 별칭은 `~/.tmm/models`(사용자) + `~/.tmm/models.generated`(생성본) 병합 — **사용자 우선**. `tmm models refresh`가 라이브 목록에서 생성본을 만든다. claude 는 fable 제외 `--ctx 1m` 자동. 크로스엔진 발췌는 `~/.tmm/forks/`에 영속(피커 종료 후에도 새 에이전트가 읽음).
- **opencode 의 `--model` 접두사가 곧 프로바이더다** — `opencode/`=zen(자체 게이트웨이), `openrouter/`=OpenRouter. 크레딧이 OpenRouter 에 있으면 반드시 `openrouter/...`. `TMM_MODELS_PROVIDER`(기본 `openrouter`)로 refresh 생성본의 접두사를 정한다. `opencode/deepseek-v4.1-flash` 는 없고 `openrouter/deepseek/deepseek-v4.1-flash` 에 있다.
- **`^F` fork 흐름은 «취소 가능»해야 한다**(사용자 요구 2026-09-19): 각 프롬프트에서 `^C`(또는 이름/에이전트/모델에서 `q`), 생성 중 아무 키=취소 → 피커 복귀. 취소 시 백그라운드 프로세스·자식(tmuxc)·이미 만들어진 `$name` 세션을 정리한다. `trap INT` 는 함수 끝에서 반드시 해제(`trap - INT`). 모델 선택은 fzf(검색) — 600+ 별칭 대응.
- **대화 기록 인덱스**(기능1, 0.6.0): `tmm idx NAME|SID [--json|--path]` + TUI `^Y`. 라이브는 `cwd` 슬러그 + `agentName` 정확매치(exact) → 최근 활성 파일(fallback), 종료는 sid. codex/cmd 는 cwd, opencode 는 DB. `tmm-dead-scan.py resolve`가 2패스(exact 먼저)로 «같은 cwd 혼재» 오탐을 막는다. `^Y`는 fzf `execute`(정보화면, 커서 유지), `^F`는 `--expect`로 fzf 밖에서 처리.
- **`resolve` 의 cwd 비교는 `_cwd_eq`(realpath)** — tmux `pane_current_path`는 심링크를 해석(`/private/var/…`)하므로 cwd 슬러그는 원본·realpath 후보를 모두 시도한다.
- **TUI 는 tmux 세션 안에서 돈다**(`tui_wrap`, 0.5.0). 터미널이 창 드래그 중 pty 를 회수하면 그 pty 에 직접 붙은 프로세스는 SIGHUP 으로 즉사한다 — A/B 실측: 래핑 없으면 피커 소멸, 래핑하면 세션·피커 생존. **비대화 서브명령은 래핑하지 않는다**(ls/dead/restore 가 tmux 세션을 만들면 안 된다). 끄기 `TMM_NO_WRAP=1`.
- **스캔 캐시는 tmux 서버별**(`socket_path` 해시). 격리 소켓 테스트가 실사용 캐시를 덮어써 전 좌석 상태가 `?` 가 된 사고(2026-09-14) 재발 방지 — 수동 격리 테스트 때 `TMPDIR` 도 같이 갈아끼운다.
- **피커 세션은 tmux 프리픽스를 끈다**(`tui_wrap`, `prefix None`). 전역 프리픽스가 `C-a` 면 피커의 `^A` 가 fzf 에 안 닿고, 이어 `^D` 가 «프리픽스+d» 로 detach → tmm 종료(2026-09-30). 좌석 세션의 `C-a d` 는 그대로(`cmd_dkey` 가 출발 피커 → 직전 → 빈 피커 순 복귀). verify (x)(y).
- **키워드는 뷰별**(`$RUN/query.live`·`query.dead`)이다 — 뷰 전환은 fzf 안 `vswitch` 로 저장·복원한다. `change-query:` 는 콜론 형식이며 액션 체인의 «마지막»이어야 질의 속 `)`·`+` 가 구문을 안 깬다.
- **탭 뷰(기본)**: 탭 줄은 헤더의 «마지막» 줄(프롬프트 바로 위), `전체`(`*`)는 «마지막 탭», 시작 탭은 «첫 카테고리»(전체는 가장 무겁다 — 사용자 지정 2026-09-30). `Tab`/`S-Tab` 은 탭 뷰에서만 가로챈다(목록·종료 뷰는 원래 toggle). `cmd_header` 를 `cmd && x` 로 끝내지 않는다 — 탭이 꺼져 있으면 종료코드 1.
- **카테고리는 일반화 폴백이 정본**(`cat_of`): 역할 접두(`FB_ ft-`)를 떼고 첫 토큰. 규칙 파일에 프로젝트별 줄을 늘리지 않는다. verify (z).
- **부팅 속도 3종을 빼지 않는다**: ① `rows-boot`(직전 스냅샷 즉시 + `boot-reload`) ② `ep.cache`(좌석별 `(window_activity,pane_pid)` 키) ③ dead-scan 의 `lsof -c …` 범위 축소(전체 `lsof` 는 5초). verify (zz).
- `SELF`/`HERE` 는 `$0` 기준(심링 해석). `command -v tmm` 으로 잡으면 소스 트리 실행이 설치본 libexec 를 본다.

## 현재 설계 결정 (사용자 확정)

- 종료 뷰(`^D`) = 완전 전환. 기본 12h 창, `^]`/`^\` ±12h, `^L` 계보 전체↔최신. 상태 열 = 출처 배지(SNAP/CC/CDX/CMD/OC). Enter = resume 복구.
- 기본 정렬 = **마지막 응답 시각 역순**. 진입 시 최신 대화가 맨 위. 대기 우선은 `^W`, 카테고리 `^G`, 대기만 `^H`.
- Enter = attach (별도 명령 아님). 떼면(`C-a d`) 피커로 복귀.
- Termius 스니펫(Pro 유료) 대신 서버측 서브명령(`tmm ls/h/p/s/a/save`).
- attach 기본은 폰 크기 추종. `-i`(ignore-size)는 옵션 — 폰 화면이 점으로 채워져 사용자가 거부했다.

## 알려진 한계 (다음 개선 후보)

- 완료 마커에 날짜가 없다. 이틀 넘게 방치된 좌석은 경과가 작게 보일 수 있다 (`~` 폴백이 더 정확).
- 첫 로딩은 seat-scan 시간(65좌석 2~3초, 부하 시 더)에 묶인다. 캐시 TTL 20초로 재진입만 빠르다. TUI 가 떠 있는 동안은 전좌석 자동 갱신(20초 고정, `^U`는 미리보기 5/10/15초만)이 캐시를 갱신하지만 첫 진입은 여전히 스캔을 기다린다.
- 헤더는 fzf 가 폭에 맞춰 «자른다»(줄바꿈 없음). 각 줄 표시폭 ≤ 60 을 verify.sh 가 재고, 넘기면 폰에서 뒤쪽 키가 안 보인다.
- 자동 갱신은 fzf `--listen` 소켓 + 백그라운드 핑거(1초 틱). 핑거 수명 = fzf 한 번 — attach 중 정지는 이 구조에서 나온다. 상태 파일은 `$TMPDIR/tmm-<uid>/run-<pid>/` 인스턴스별.
- 미리보기 렌더러(`render_pane`)도 TUI 모양에 의존한다 — Claude 입력박스 «구분선→`❯`», Codex «`› Ask Codex`». macOS awk `length()` 는 바이트라 멀티바이트 정규식(`(─)+`)을 쓰지 않는다. 골든은 `verify.sh` (k).
- seat-scan 은 Claude Code TUI 문자열(`Enter to select`, `API Error`)에 의존한다. Claude Code 가 문구를 바꾸면 상태 열이 틀어진다.
