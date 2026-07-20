# fable-team 업데이트 — 로컬 패치 적용

트리거: **"FT 업데이트"** (보조: "fable-team 업데이트", "ft 패치"). 팩 소스(레포)의 변경분을 로컬 설치본(스킬 파일 + 에이전트 .md)에 적용한다. 재설치 인터뷰 없이 **기존 인터뷰 답변을 보존**한 패치가 목적이다.

## 절차

1. **소스 위치 확인**: 팩 레포의 `feature-pack/fable-team` — 현재 프로젝트가 레포면 그대로, 아니면 사용자에게 경로 확인 1회.
2. **스킬 파일 갱신**: `./install.sh user`(또는 `project:<path>`) 재실행 — SKILL.md + references/ 전체 교체(멱등, 설치본 에이전트 .md는 건드리지 않음).
3. **에이전트 .md 패치** (설치된 워커만 — opt-in 미설치 크루는 건드리지 않는다):
   1. 설치 답변 로드: 설치 스킬 위치의 `install.json` Read. **없으면(구설치본)** 설치된 `<PREFIX>-*.md`들의 frontmatter(model/effort/name)와 본문에서 placeholder 값을 역추출.
   2. 각 해당 템플릿(`agent-templates/*.md.tpl`)을 로드된 값으로 재치환 → 설치본 파일과 비교 → **내용이 달라진 파일만** Write. 잔여 `{{` 검사(남으면 실패로 간주, 해당 파일 롤백).
   2-1. **v3 세션 계약 프롬프트 재치환**: `templates/session-prompts/*.md`(8종)도 동일 로드값으로 재치환 → 설치본 `.fable-team/prompts/<role>.md`와 비교 → 달라진 파일만 Write(잔여 `{{` 검사 동일). agent-templates와 같은 키를 쓰므로 별도 값 불요 — install-interview §5-3-2와 대칭.
   3. 사용자 커스텀(`{{EXTRA_INSTRUCTIONS}}` 영역 등)이 감지되면 덮어쓰기 전에 사용자에게 보여주고 확인.
4. **기록**: `install.json`에 답변 스냅샷 + `updated: <ISO 시각>` + 팩 커밋 해시를 기록 (구설치본이면 이번에 생성 — 다음 업데이트부터 역추출 불요).
5. **재시작·재검증 안내**: 에이전트 .md가 1개라도 갱신됐으면 **"새 세션 필수"** 고지(정의는 세션 시작 시 스냅샷 등록 — SKILL.md 함정). 새 세션에서 프로브 재검증 — **경로 이원화(architect 포함) 기준**(install-interview §5-4).
6. **강제 게이트 4-레이어 재배포** (orchestration-gate 설치된 프로젝트만): `install.sh`가 `templates/`를 설치본에 재복사한다(2번에 포함). 게이트가 설치된 프로젝트(`.claude/hooks/orchestration-gate.sh` 존재)는 `templates/install-gate.sh --install <proj>`로 훅·rules·settings를 **4-레이어 세트로 함께 재배포**(멱등·병합·백업). **선언(SKILL/CLAUDE)·역할(agents)·기준(rules)·강제(hooks) 중 하나만 바뀌면 불일치** — 패치마다 세트로 갱신. 상세 `references/orchestration-gate.md`.
7. 결과 보고: 갱신된 파일 목록 + 스킵 목록(변경 없음/미설치) + 게이트 재배포 프로젝트 + 다음 행동(새 세션) 1줄.

## 함정

- 세션 중 .md 수정은 이미 등록된 타입에 소급 반영 안 됨 — 업데이트를 수행한 세션에서 그 워커를 바로 쓰지 마라.
- `install.sh`는 `references/`를 `rm -rf` 후 복사한다 — 설치본 references에 수동 수정을 넣지 말 것(수정은 팩 레포에서 → 업데이트로 배포).
- 템플릿 기본값이 바뀐 경우(예: 새 워커 규칙 추가) 재치환 결과가 크게 달라질 수 있다 — diff 요약을 보고에 포함해 사용자가 변경 폭을 인지하게 한다.
- **구키 미마이그레이션 롤백**: §3-0a 리네임(구키 → 신키)을 건너뛰고 §3-0b만 실행하면 구키 잔존으로 재치환 대상 목록이 불일관 — 반드시 3-0a → 3-0b 순서.
- **bin 파일 단위 교체 금지** — bin 세트는 §P-2 원자 디렉토리 스왑으로만 갱신한다. **유일 예외 = Phase 0 가드 append**(자기완결 가드 블록 1개 append 한정 — 확대 금지).
- **`.swap.lock` 잔존 TTL 판정**: 크래시로 남은 락은 owner-ts(없으면 dir mtime) TTL 600s 초과 시 가드가 fail-open 회수. **owner 없는 락도 dir mtime으로 TTL 회수** — 수동 정리 시 owner 유무로 당황하지 말 것.
- **스왑 코어는 반드시 중립 파일명**(`.swap-core.<ts>.sh`) — argv에 래퍼 패턴(`ft-tmux-`/`ft-pm-watchd` 등) 노출 시 드레인 pgrep 자기매칭으로 false-nonzero.
- **NB1 trap 분리**: 시그널(INT/TERM)은 `on_sig`(복구-후-종료 exit 1), EXIT는 `cleanup`(정리 전용)로 분리한다. `trap cleanup EXIT INT TERM` 단일 통합 금지 — 시그널 수신 후에도 실행이 계속돼 락이 먼저 제거된 채 rename이 진행되는 결함(§P-2 시그널 프로토콜).
- **bypass는 명령 접두로만**: `FT_SWAP_BYPASS=1 bash …` 형태로만 부여 — 코어 자신의 env에 export 금지(다른 호출 누출 → 다음 스왑 우회 재발). 사용처 = 코어의 watchd stop/ensure(+on_sig 원복 ensure)뿐.
- **[§B1 정직 경계] swap-lock 물리 보장은 가드 배포 후(2회차+)부터.** 첫 스왑은 quiesce-invariant(직렬 단일 코어 실행·watchd 정지·드레인=0)가 커버하는 **부트스트랩 경계** — 이를 "물리 보장"으로 서술하지 말 것. 잔여 창(Phase 0 이전 기동 in-flight·드레인 관찰 비원자성)은 환원 불가능한 시스템 경계다.

---

## bin 세트 스왑 (스텝 2-1 상세 — bin 배포/리네임 전파 시)

> **적용 조건**: 팩의 `skill/scripts/` bin 11종(comm v2 = `ft-mbox.py`·`ft-mbox.sh` 포함)이 바뀌었거나(리네임·가드 추가 등) 설치본 bin이 스테일일 때. 문서(.md)만 바뀐 업데이트는 이 절차 불요 — 위 절차 1~7로 충분. mailbox 데이터(`.fable-team/comm/`)는 스왑 비대상 — 업데이트 중 큐 보존.
> **SSOT**: 설치 답변·상태의 단일 원천은 **프로젝트 `<root>/.fable-team/install.json`**. 후보 2위치(설치 스킬 위치 / 프로젝트 `.fable-team/`)가 상이하면 **상이한 것이 복수일 때만 중단**하고 사용자 확인. 순서는 3-1(스냅샷 로드) → 3-0(키 마이그레이션) → 3-2(프롬프트 재치환).

### §3-0. 키 마이그레이션 (SSOT 분기 후 — 2분할, 멱등)

**3-0a. 리네임 매핑 (구키 게이트)**:
- 구키(예: `planner`) → 신키(`architect`) 매핑표로 **제자리 리네임** → 배열은 **stable-dedup**(순서 보존 중복 제거).
- `migrated` 객체가 있으면 **병합 보존**(리네임 이력) — install.json에 `migrated` 필드 허용(schema3).
- 매핑에 없는 키는 **불변**. 재실행 시 구키 부재 → no-op(멱등).

**3-0b. architect 존재 보장 (구키 유무 무관 — 항상 실행, 전 케이스 커버)**:
- `installed_prompts` 배열 존재 + `"architect"` 없음 → 말미 append.
- **필드 자체 부재(구설치본) → `["architect"]`로 필드 생성** — architect는 필수 역할이므로 최소 보장 배열을 만든다(무조건 보장). 생성 시 보고 1줄 + "여타 역할은 실물 `.fable-team/prompts/*.md` 역추출로 보완해 배열에 반영 권고" 병기(보장 우선, 역추출은 보완).
- architect 기존재 → no-op. 멱등.
- → §2-C "architect는 항상 재치환 대상"이 전 케이스 성립.

### §2-C. 재치환 대상
대상 = 3-0 후 `installed_prompts`. DA형은 `brains.da/da2` 활성형 판정·목록 내만.

### §2-D. 프롬프트 트랜잭션 — ②-1 fail-closed 백업 게이트 [H6]

각 `<role>.md` 재치환은 ⓐ치환 → ⓑ잔여 `{{` 검사 → ①tmp write → ②-1 stale 백업 게이트 → ③ 원자 `mv -f` 순. **②-1 백업이 overwrite 선행 게이트(fail-closed)**:
- (i) `<role>.md` 기존재 시 목적지 `prompts/.archive/<role>.md.pre-update.<YYYYMMDD>` — 기존재 시 `-2`,`-3`… 첫 빈 이름(직전 `test ! -e` 재확인, 단일 오케 액터 직렬 계약).
- (ii) `cp <원본> <목적지>` — **exit 0 확인**.
- (iii) **백업본 검증**: 존재 + 크기>0 + `cksum` 원본 일치.
- (ii)(iii) 하나라도 실패 = **해당 파일 교체 중단**(`mv -f` 진행 금지 — 기존 증거 무손상). **architect면 archive 체인 전면 금지 + 보고**. 전부 통과 후에만 ③ `mv -f` 자격.

### §W. watchd 절차 (실행 위치 = §P-2 ②⑥⑦, bypass 명시)
watchd stop/ensure는 스왑 코어 안에서 `FT_SWAP_BYPASS=1 bash <bin>/ft-pm-watchd.sh …` **명령 접두**로만 호출. 기동 확증 = pidfile + `kill -0` + proj 3조건 bounded wait(1초×10, 재시도 1회).

### §P-0. Phase 0 — 가드 선배포 (inert·동작 불변 — 잔여 창 축소 best-effort, §B1 지위)

설치본 `<bin>/ft-lib.sh`에 `ft_swap_guard` 부재 시 1회성(기존재 시 skip=멱등):
1. 현행 설치본 `<bin>/ft-lib.sh`를 **바이트 그대로** + 말미에 §L-2 가드 블록만 append한 패치본을 `<bin>/.tmp.ft-lib.sh`로 생성 — 리네임·`FT_KNOWN_ROLES` 등 **다른 어떤 변경도 금지**.
2. `bash -n` — 실패 시 tmp 삭제·전체 중단(구 bin 무변화).
3. 같은 디렉토리 원자 `mv -f` + exit 0 확인 + `ft_swap_guard` grep 확인.
4. 안전 근거: 락 부재 시 가드는 stat 1회 후 즉시 return(**inert**). 원자 mv 중 구 inode를 source 중인 프로세스는 POSIX 의미론상 구 inode로 완주(rename = 디렉토리 엔트리 교체).
- 효과: Phase 0 이후 신규 기동 래퍼는 가드 적용본을 source해 Phase 2 락을 존중한다. **단 잔여 창의 축소이지 물리 보장이 아니다** — Phase 0 이전 in-flight·드레인 관찰 비원자성은 §B1 quiesce-invariant가 커버.

### §P-2. Phase 2 — 본 스왑 (중립 파일명 코어 단일 호출)

절차 전체를 `<root>/.fable-team/.swap-core.<ts>.sh`로 Write 후 `bash <경로>` **단일 호출**(이 동안 오케는 다른 bin 호출 발행 0 = quiesce 축 ①). 완료 후 코어 삭제.

**시그널 프로토콜 (NB1/NNB1 — trap 분리 + 조건부 cleanup)**:
```bash
PHASE=pre; CLEANED=0
SWAP_INCONSISTENT=0        # bin 불일관 플래그 — 1이면 어떤 경로에서도 락 제거 금지

cleanup() {               # EXIT trap 공용 — 최상단 불일관 가드(NNB1 핵심)
  if [ "$SWAP_INCONSISTENT" = 1 ]; then
    echo "SWAP inconsistent — 락 의도 유지, MANUAL-RECOVERY 필요 ($LOCK/RECOVERY)" >&2
    return 0              # 락 제거 스킵 — exit 1의 EXIT trap 경유에도 락 잔존 보장
  fi
  [ "$CLEANED" = 1 ] && return 0; CLEANED=1
  rm -f "$LOCK/owner" "$LOCK/RECOVERY" 2>/dev/null; rmdir "$LOCK" 2>/dev/null
}
mark_inconsistent() {     # 역롤백/임계구간 복구 실패 시 호출
  SWAP_INCONSISTENT=1
  printf 'phase=%s ts=%s\n' "$PHASE" "$(date +%s)" > "$LOCK/RECOVERY" 2>/dev/null
  # owner는 원 timestamp 보존(TTL 판정 소스 불변). RECOVERY는 별도 마커 파일.
}
on_sig() {                # INT/TERM 전용 — 복구-후-종료(exit 1). 실행 계속 금지.
  trap '' INT TERM        # 핸들러 중 재진입 차단
  case "$PHASE" in
    pre)       FT_SWAP_BYPASS=1 bash "$BIN/ft-pm-watchd.sh" --root "$ROOT" --ensure >/dev/null 2>&1
               cleanup; exit 1;;
    post-swap) if swap_rollback; then cleanup; else mark_inconsistent; fi
               exit 1;;   # 실패 시 플래그가 EXIT trap의 락 제거를 차단 — 락 잔존
    done)      cleanup; exit 1;;
    critical)  exit 1;;   # 도달 불가(마스킹) — 방어 분기
  esac
}
trap on_sig INT TERM      # 시그널 = 복구-후-종료(비0)
trap cleanup EXIT         # EXIT = 정상 경로 최종 정리만(멱등)
```
**임계구간 마스킹 포위**(rename mv 쌍 §P-2 ④·롤백 mv 쌍 ⑦): `trap '' INT TERM` → `PHASE=critical` → mv 쌍(둘째 실패 시 같은 마스킹 안에서 즉시 역롤백까지) → `PHASE=post-swap`(또는 done) → `trap on_sig INT TERM` 복원. (bash는 무시 중 시그널을 큐잉 안 함 — 임계구간 <1s 완주가 불일관 중단보다 안전.)

**락 해제 불변식**: `cleanup`(락 제거)은 bin이 일관 상태(완전 구본 or 완전 신본)일 때만 도달 — pre(구본)/post-swap 역롤백 성공(구본)/정상 완료(신본). 복구 실패 = `mark_inconsistent`로 락 의도 잔존(TTL 600s 상한). KILL(-9)은 방어 불가 — 락 잔존 → TTL 후 fail-open + 함정 수동 절차.

**코어 내부 순서**:
1. 락 생성 — §L-1(①mkdir → ②trap 즉시 → ③owner 기록 실패 시 cleanup·중단).
2. watchd 정지(quiesce 축 ②·fail-closed): `FT_SWAP_BYPASS=1 bash <구bin>/ft-pm-watchd.sh --root <root> --stop-if-owned` → 구 pid 소멸 bounded wait. 실패=중단(trap 락 제거). proj=<root> 데몬만.
3. 드레인(quiesce 축 ③): `pgrep -f 'ft-tmux-|ft-pm-watchd|ft-ctx-triage|ft-gzip|ft-mbox'` 잔존 0까지 1초×최대 10초. **제외 = 명시 PID 2개만: ① 코어 자신(`$$`) ② pgrep 프로세스 자신(기본 제외 — 방어적 명시)**. **`pgrep -P $$` 블랭킷 자식 제외 폐기**(false zero 방지 — 코어 직접 자식이라도 $0이 래퍼면 정확 포착·배출 대기). 10초 초과 → ps 확보·중단(trap 락 제거)·오케 명시 판단 재시도 1회.
4. 스왑(임계구간): `mv bin bin.old.<ts> && mv bin.new.<ts> bin` — 둘째 실패 시 마스킹 안에서 즉시 역롤백 후 중단(락 내부).
5. 사후 검증(락 내부): 11종 `cmp` identical + `-x`. 실패 = ⑦ 롤백.
6. watchd 재기동(락 내부 — bypass 상속): `FT_SWAP_BYPASS=1 bash <신bin>/ft-pm-watchd.sh --root <root> --ensure`(nohup `--run` 자식까지 env 상속 → 가드 통과 → 락 유지 중 기동) → §W 기동 확증. (락 잔존 수 초 watchd send 호출은 exit 7일 수 있으나 watchd가 무시 → 무해.)
7. **실패 롤백(락 내부 — B2/NNB1)**: ⑤/⑥ 최종 실패 시 `swap_rollback`(`mv bin bin.failed.<ts> && mv bin.old.<ts> bin`) → 구bin `--ensure` 원상복구. **`swap_rollback` 실패 = `mark_inconsistent` 후 exit — 락 제거 금지**(불일관 bin 노출 방지). + state.md에 `ALERT SWAP-INCONSISTENT — <root>/.fable-team/bin 수동 확인 필요(TTL 600s 내)` 즉시 기록 + 오케 HIL 보고.
8. **락 제거 = 유일 정상 제거 지점**(성공·롤백 공통, SWAP_INCONSISTENT=0일 때만): owner/RECOVERY rm → rmdir(trap과 이중). 이후 2차 `--ensure` "WATCHD reuse" 확인(락 밖).
9. 코어 스크립트 삭제 + `bin.old.<ts>`/`bin.failed.<ts>` 보존 보고(유니크 서픽스).

### §P-P. PM 공지 — 보류 상태 폐지 + 재개의 실패 사다리 [H5]

- **PM "보류 상태" 자체 폐지** — 락 중 PM 래퍼 호출은 가드가 exit 7 + "retry" stderr로 튕기고, 락 해제(수십 초) 후 재시도가 성공한다. 정지 "상태"가 없으므로 무기한 중지가 구조적으로 불가.
- **감시 재개의 실체 = ⑥ watchd `--ensure` 물리 재기동**. 단 **절대표현("반드시 재기동") 금지 — 실패 사다리로 담보**: ① 신bin ensure + 기동 확증 재시도(§W) → ② 전량 실패 시 B2 롤백(구bin ensure 원상복구) → ③ 그마저 실패 시 **HIL 상신이 종착**: state.md `ALERT watchd-ensure 전량 실패 — 수동 개입 필요` 기록 + 오케 보고. "무기한 중지 불가"는 이 사다리(물리 재기동 2경로 + HIL)로 성립.
- 공지는 정보용 best-effort 1줄로 강등: Phase 2 前 PM 생존 시 `[orch->pm] bin 교체 1분 내 진행 — 이 사이 bin 호출은 exit 7, 재시도하면 된다`. 도달 실패해도 진행·state.md 기록만(게이트 아님). PM 계약(prompts/pm.md) 갱신 불요.

### §B1. 부트스트랩 경계 (보고에 1줄 명기 — 정직 서술)

- **정상상태(가드 배포 후 = 2회차+)**: swap-lock **물리 보장 완전 유효** — 신규 래퍼 진입을 가드가 코드 레벨에서 차단.
- **첫 스왑(부트스트랩)**: **quiesce-invariant가 커버** — ① 단일 직렬 코어 호출 ② watchd 정지(fail-closed) ③ 드레인=0. 단일-오케 모델에서 래퍼 호출자는 오케·watchd뿐이고 둘 다 절차가 통제하므로 잔여 창은 실질 빈 집합 — **단, 물리 차단은 아니다(이 문장이 보장의 정확한 상한)**.
- Phase 0의 지위 = 잔여 창 축소 best-effort 하드닝. 이 경계는 #8(PM 물리강제 불가)과 동일 계열의 정직 문서화 대상.
