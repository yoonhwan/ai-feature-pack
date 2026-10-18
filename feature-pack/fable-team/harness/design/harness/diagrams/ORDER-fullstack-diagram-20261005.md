# ORDER — 풀스택 시스템 다이어그램 (draw.io) · 정본화 (ft-harness-ops#3 → ft-harness-arch · 2026-10-05 · 오빠 지시)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
> 골의 축: 표 C(전 머신 배분·반영 — 머신·인프라 지도가 그 입력) · 표 A(모니터 대상 지도) · 원문 5(머신 단위 독립 배분). 닫는 증거 = 다이어그램 정본(IR+drawio) 커밋 + DA 사실 정합 APPROVE + 오빠 「맞다」.

## 오빠 원문 (2026-10-05)
> 「arch에게 우리 시스템의 풀스택 다이어그램을 draw.io 로 그려 시각화하자. 외부서비스부터 내부 로컬 파일시스템에 각 메인오케스트와 세부 구성의 노드 그리고 인프라스트럭처 레벨의 다이어그램.」
> 「이거 왜 이렇게 디테일하게 계속 파고 정리시키는지 알지? 문서화하고 그 내용을 정본화해서 시스템으로 안착시키는 거다.」
> 「draw.io 하려면 먼저 mcp 말고 가장 최고의 skills 를 찾아 설치하고 사용. 리서치하자.」
- **목적 = 그림이 아니라 정본**: 이 다이어그램은 설계·배포·변경의 기준 문서다. 그림은 «코드로 재생성 가능한 모델»(IR)에서 나와야 하고, 시스템이 바뀌면 drift 를 잡을 수 있어야 한다.

## 도구 (ops 가 리서치·검토·설치 완료 — MCP 아님)
- 채택: **Agents365-ai/drawio-skill v3.4.0**(MIT · sha `88fd923` · 2026-10-02 · 소스 검토함: 코어 stdlib 전용 · subprocess 인자 배열 `shell=False` · 네트워크는 아이콘 `--embed` 때만 · 시크릿 속성 금지 규칙) — 설치 위치 `~/.claude/skills/drawio-skill`(`.installed-from` 에 출처·sha). `disable-model-invocation: true` 이므로 **Skill 도구로 `drawio-skill` 을 명시 호출**해서 읽는다.
- 선택 이유: 단일 `.drawio` 생성기가 아니라 **Diagram IR(정본 모델) → build / sync(수동 배치 보존) / views(한 모델에서 executive·system·deployment·dataflow·security 뷰) / test(아키텍처 규칙) / query·whatif / story(HTML 워크스루)**. 대안 jgraph 공식 skill 은 `.drawio` 생성·내보내기 단일 흐름(정본 모델·drift 없음).
- 의존: draw.io CLI 설치됨(`/opt/homebrew/bin/drawio` 31.7.0) · graphviz `dot` 는 ops 가 설치 중 — `python3 ~/.claude/skills/drawio-skill/scripts/diagramctl.py doctor` 로 확인. 큰 그래프(15 노드+)는 손배치 금지 → autolayout.
- 금지: 노드 속성·provenance 에 **시크릿·토큰·키 넣지 않는다**(`.drawio`·story 에 그대로 박힘) · 외부 서비스는 이름·역할·연결만(키·계정 ID 0).

## 할 일 (산출 = tracked 경로 `design/teams/harness/diagrams/` · 구현·시스템 변경 0)
1. **사실 수집(nano 읽기 전용 먼저 · press/서버 기동 0)**: ①외부 서비스 전부(Slack·GitHub·Supabase·GCP Cloud Run/IAP·STT/TTS/LLM 프로바이더·Cloudflare/도메인·cliproxy/headroom 상류 등 — 코드·환경 설정에서 실재 확인) ②머신·프로세스·포트(launchd 목록 · 38301~ 슬롯 · Caddy 8443 · gateway/worker/FE · Redis · Postgres · GPU VM/터널 · jarvis 등 다른 머신) ③하네스 노드(P2 트리: 오빠↔planner↔메인 {v65·cfo·harness-ops}·위성 {ccu·kk} · issue-manager · 각 팀 master/arch/da/nano/시험 묶음 · tmux 세션·mbox) ④로컬 파일시스템 지도(리포 루트·`.worktrees/*`·`.fable-team/`·`.claude/`·`design/*`·`~/.claude/{skills,rules,hooks,archives}`·`~/.hermes`·mbox 파일·baton). 모든 노드는 **[사실] 출처 1줄**(파일:라인 또는 명령 출력) · 확인 못 한 것은 [추측] 표시 + 점선.
2. **IR 정본**: 노드(id·종류·계층·소유 팀·출처)·엣지(종류: 데이터/제어/mbox/배포)를 `*.ir.json` 으로. 계층(그룹/컨테이너) = ①외부 서비스 ②네트워크·머신·인프라 ③애플리케이션 서비스 ④하네스(오케·팀·좌석) ⑤로컬 파일시스템.
3. **뷰(한 모델에서)**: ⓐ 풀스택 한 장(개관) ⓑ 인프라·배포(머신·포트·터널·표 C 머신 배분 자리) ⓒ 하네스 오케 트리·메시지 흐름(P2·P8) ⓓ 로컬 파일시스템 지도 ⓔ 일 한 건의 길(P8 13단계를 노드에 겹침 — 선택).
4. **검증**: `diagramctl.py test`(규칙: 고아 노드 0 · 출처 없는 노드 0 · 시크릿 패턴 0) · `validate.py` · PNG/SVG 내보내기 후 겹침·잘림 자기점검 · `sync` 로 두 번째 실행 시 수동 배치 보존 확인.
5. **오빠 질문 최대 3**(추천 첫째) · 구현 후보(drift 점검을 CI/RELEASE 에 거는 일 등은 구현 조각으로 분리 — 지금 0).

## 길
nano 사실(읽기 전용 · 커밋 요청은 ops 로) → arch 가 IR·뷰 작성(skill 사용) → da#1 **사실 정합 1회**(노드·엣지가 실재와 맞나 · 10분 · HOLD 2 = 직렬 종료 → ops 결정) → ops 수락 → ops 가 오빠께 PNG/HTML 링크(+ 필요시 /eli5) → 오빠 확인·정정 → 정본 확정(커밋). 오빠 글은 GUIDE-human-report 틀. mbox 는 예외.
