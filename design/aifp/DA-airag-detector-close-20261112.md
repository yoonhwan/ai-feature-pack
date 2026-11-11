# AIRAG 탐지기 S0·S1 닫힘 판정문

## §1 airag-detector-s0s1

닫힘 — airag-detector-s0s1 — 판정 불가 확정(h9) · 착지 코드 0 · 정본 영향 없음

APPROVE. 동결 `ac7c93e9fe8ac292ffe4ee0a5c9679d2eb0835e4`의 완료 조건 1·2·3을 기존 증거와 대조했다. 새 시험·설치·사람 실행은 0이다.

- 완료 조건 1: aifp 쪽지 3535에 계획 파일 경로와 `bash -n rc 0`이 기록돼 있다. 현재 파일은 18185바이트, SHA-1 `b6577ecce8e3`로 시작하며 카드에 기입한 파일 정보와 일치한다. 이번에는 구문 시험을 다시 실행하지 않았다.
- 완료 조건 2: 같은 쪽지의 `OPPROBE_DRY=1` 결과는 rc0, 걸린 초 0.0(벽시계 0.16), Sandbox deny 2, TCC AppData 1·AllFiles 6·PROMPTING 1이며, 행 이름 9건과 전체 기대값 일치가 기록돼 있다. 가짜 입력을 사용하는 점검 모드의 기존 결과다.
- 완료 조건 3: `facts-h8-h9-20261107.md`의 h9 절에 사람 실행 rc0·16.9초와 원문 인용이 보존돼 있다. S0·S1 모두 Sandbox deny 0·PROMPTING 0, 끝 줄은 `행 이름: S0 deny 0`이다. `/tmp/h9.out`은 현재 없으므로 이번 대조는 사실 팩의 보존 인용을 사용했다.
- 정본 대조: `feature/rag-transplant`의 `arch-20261028-appreg.md` §4 69행은 S0 deny 0을 판정 불가로 정한다. planner arch#43의 h9 판정은 이를 확정하고 안 B 경로와 h-A·h-B 기대값을 유지한다. `origin/main` 반입 `433c2216`의 `CLOSEOUT-airag-20261109.md:23`도 끝 줄 3 기입 후 이 카드 완성을 명시한다.

닫는 범위는 탐지기 계획 파일·기존 실행 결과의 판정 기록이다. 확정된 결과는 판정 불가이며, 안 B 후속 앱 시험은 기존 경로를 따른다. 카드 이동은 arch가 수행한다.

근거: aifp 쪽지 3535·4124·4125, `.fable-team/state/team-main/airag/facts-h8-h9-20261107.md` §h9, 같은 폴더 `verdict-h8-h9-h10-arch43-20261107.md` §h9, `feature/rag-transplant:feature-pack/rag/docs/artifacts/arch-20261028-appreg.md` §4, `433c2216:design/aifp/CLOSEOUT-airag-20261109.md:23`.
