# kit/ops-intake — #howto-talk-ops 접수 도구 (하네스팀 몫)

사용자가 슬랙 `#howto-talk-ops` 에 쓴 글 → mini 의 aina 접수 카드 → 이 맥 접수 팀장 → byz 이슈팀 등록 → 같은 스레드로 번호·상태 회신.
이 폴더는 그 사슬의 **기계 부품**이다(팀·좌석·명부는 플래팀 · 설치·시험은 r956 h-A·h-B·h-C · 기획 정본 = 멀티호스트 팀 `docs/multihost/DESIGN-ops-intake-20261026.md`).

## 파일 지도

| 파일 | 어디서 도나 | 무엇 |
|---|---|---|
| `ops_intake_write.py` | mini | JSON stdin → 접수 카드 1장 + `[OPS-NEW]` 쪽지 1통. 스키마 엄격 · 비밀·개인정보 마스킹 · 폭주 한도 |
| `ops_intake_poster.py` | mini · launchd 60초 | `[OPS-REPLY]` 1통 → 같은 슬랙 스레드 답글 1건 → 쪽지 삭제. `thread_ts` 없으면 게시 0 · 문장 검사 · 중복 게시 0 |
| `ops_intake_sync.py intake` | 이 맥 | 끌어온 카드 비밀 재검사 → 걸리면 quarantine 마스킹 사본만 + mini 카드 덮어쓰기 + 이슈 요청 0 |
| `ops_intake_sync.py status` | 이 맥 · launchd 5분 | 열린 접수 건 gh 읽기 → 상태 라벨 변화·닫힘·`[사용자 공지]` 코멘트만 `[OPS-REPLY]` push |
| `sat-mbox.py` | 이 맥 · launchd 60초 | mini 쪽지함 ↔ 이 맥 쪽지함 pull/push (원본 = 멀티호스트 가지 · 이식 조건 적용) |
| `ops_intake_common.py` | 공용 | 경로(전부 env) · 스키마 · 마스킹 · 쪽지 · 시각 |
| `com.byz.sat-pull.plist.template` | 이 맥 | pull 데몬(60초 · 좌석 목록 파일 1개) |
| `com.byz.ops-intake-sync.plist.template` | 이 맥 | 상태 동기화(5분) |
| `com.hermes.ops-intake-poster.plist.template` | mini | 게시기(60초) |
| `seats-pull.txt.example` | 이 맥 | pull 대상 좌석 목록(접수 팀장 + 위성 나노 팀장) |

시험 = `harness/tests/test_ops_intake.py` (+ `test_ops_intake.sh` 러너). 실 슬랙·실 gh·실 ssh·실 mini 호출 0.

## 계약(바꾸면 시험도 같이 고친다)

1. **마스킹은 정본 규칙 재사용** — `harness/bin/ft_secret_shapes.py` 의 `mask()` 를 그대로 부른다(규칙 복제 0). 규칙 모듈을 못 찾으면 «판정 불가 = 차단»(rc2). 개인정보(전화·이메일) 정규식 2개만 이 폴더에 더한다.
2. **`secrets_masked: <정수>` 는 필수 칸** — 없거나 못 읽으면 이 맥이 등록을 차단한다(조용한 통과 0).
3. **원본 보존 0** — 이 맥은 카드를 임시 파일로 받아 재검사하고 그 자리에서 지운다. 걸린 카드는 `quarantine/` 에 `[제거]` 사본만, 같은 사본을 mini 카드로 덮어쓴다.
4. **게시 문장 검사는 정본 규칙표 재사용** — `kit/slack-mirror/post_guard.py` 의 `SECRETS`·`INTERNAL`. 사람 채널 판정(명부 조회)은 mini 에 명부가 없어 쓰지 않고 «항상 사람 채널» 로 건다. 커밋 sha 꼴은 이 폴더에서 1줄 더 막는다.
5. **슬랙 호출은 `mirror_lib.post` 재사용** — 7초 상한·재시도 1 이 그 안에 있다(하드 룰 12).
6. **쪽지 형식·잠금은 `ft-mbox.py` 재사용** — 이 폴더가 쪽지 파일을 직접 쓰지 않는다.
7. **절대경로 기본값 없음** — 이 맥 쪽지함·장부 경로는 `FT_MBOX_DIR`·`SAT_STATE`, ssh 대상은 `MINI`/`SAT_SSH`. 없으면 리포 루트 추정, 그것도 없으면 중단.
8. **쪽지함 큐 ≥10 이면 pull 보류** — 보내지 않고 로그 1줄만 남긴다(버리지 않음).

## mini 설치 시 함께 복사하는 정본 모듈(h-B)

`ops_intake_common.py`·`ops_intake_write.py`·`ops_intake_poster.py` +
`kit/slack-mirror/{post_guard.py,mirror_lib.py,mirror_share.py}` +
`harness/bin/{ft_secret_shapes.py,ft_secret_targets.py}`.
파일이 빠지면 write 는 마스킹 판정 불가로, poster 는 모듈 없음으로 **스스로 멈춘다**(rc2).

## rc

| rc | 뜻 |
|---|---|
| 0 | 정상 |
| 2 | 스키마/형식/설정 — 아무것도 만들지 않았다 |
| 3 | 폭주 한도(«잠시 뒤») · 외부 호출 실패 |
| 4 | 게시 거부(비밀·내부어) |
| 5 | 쪽지·push 실패 |
