# r938 증거 — ft-nano-close.sh 단계 시각 줄 + 외부 호출 상한 (r2)

카드: `design/harness/indices/진행/r938-nano-close-step-timing-and-7s-caps.md` · Issue #3618 · 1.1.246
r2 근거: DA⑥ r1 HOLD → 반송문 `design/harness/evidence/r938-da6/REWORK-r938-r2.md` (N1~N4 · 시험 ⓐ·ⓕ~ⓙ)

## 무엇이 문제였나
라이브 1.1.244 `ft-nano-close.sh … --result … --recv 169092` 가 3회 모두 70초+ 무출력으로 멈췄고 마지막 줄은 `WARN ④checkpoint 면제` 였다. 그 뒤 단계 출력이 변수에 담겨 끝에 한꺼번에 나와 «어느 단계» 인지 알 수 없었고, 원격 받아오기에는 상한이 없었다.

## 고친 것 (파일 1 + 시험 2)
| 축 | 값 |
|---|---|
| ⓐ 단계 시각 줄 | ④ 뒤 단계마다 stderr 한 줄 `STEP <이름> +<초>s`. stdout 은 0줄 바뀜 — **기준판(같은 파일에서 시각 줄만 기계적으로 뺀 사본)과 stdout cmp0** 시험 |
| ⓑ fetch 상한 | 네 곳(카드 ref·연구 origin main·cherry 재대조·feat ref) 전부 시도당 7초 + 재시도 1 = 총 ≤14초 · 무상한 `fetch -q` 0줄 |
| ⓒ 검사 상한 | `nf_bound` = python3 `start_new_session` → 상한이면 **묶음째 TERM → 1초 → KILL → 회수 대기**. 상한 = `min(고정비 + 7초 × 배수, 70)` · 배수 = 그 검사가 보는 커밋 수 |
| 고정비(실측 3회) | 증거검사 0.04·0.04·0.07 → 1.0초 · cherry 0.61·0.66·0.61 → 2.0초 · freshness 0.55·0.23·0.31 → 1.5초 (push 측정값 재사용 0) |
| 거절 줄 | `<단계> 시간 초과 <걸린>/<상한>s · 배수 <n> — 다시: 같은 명령(일시 부하면) · 계속이면 arch 에 <단계>·<초>s 보고` |
| N1 검사 먼저 | 상한 걸리는 검사(⑥·⑤·fetch·freshness)가 모든 쓰기보다 먼저 · `[wip]` 커밋·중단 검사도 그 뒤 · **사건 원장 abort trap 은 prepare «전»** 등록 |
| N4 fetch 실패 | 그 자리 REJECT «origin/main fetch 실패 — 옛 ref 대조 0(R22)» · cherry 재검사·freshness 0 · 옛 ref 로 «통과» 줄 0 |

## 실측 표 (ⓐ만 넣은 판 · 하위 스크립트 대역이 90초 걸리는 인자 꼴: `--result` · `--recv` · role=nano · press 산출 0)
| 단계 | ④ WARN 뒤 다음 STEP 줄 | 그 단계가 먹은 시간 | 멈췄나 |
|---|---|---|---|
| ⑥증거 검사 | `STEP ⑤cherry +91s` | 91초 | 예 — 무출력 멈춤(원인 단계) |
| ⑤cherry 게이트 | `STEP sheet +91s` | 90초 | 예 — 무출력 멈춤 |
| freshness | (다음 줄 없음) | 90초 | 예 — 무출력 멈춤 |
| fetch(원격) | `STEP freshness +15s` | 14초(7+재시도1) | 아니오 — 상한에서 잘림 |

근거 파일: `steps/pre-cap-c-evidence.txt` · `steps/pre-cap-c-cherry.txt` · `steps/pre-cap-c-freshness.txt`(상한만 끈 사본 = «ⓐ만 넣은 판» 과 같은 시간 거동) · `pre-cap-test.txt`

## 고친 뒤 (시험 80 PASS · `test-green.txt`)
| 카드 | 무엇을 단언하나 | 걸린 시간 |
|---|---|---|
| ⓐ | STEP 5줄은 stderr 에만 · stdout 기준판 cmp0 · 기준판 stderr 에 STEP 0줄 | 2초 |
| ⓑ | fetch 대역 30초 → «origin/main fetch 실패» + «옛 ref 대조 0» + 두 번째 게이트 0회 + 총 ≤20초 · 카드 ref fetch 도 같은 상한 | 15초 |
| ⓒ⑥/⑤/fr | 상한 뒤 REJECT · 배수·다시 하는 길 1줄 · 명부·원장·tmux 변경 0 | 8~12초 |
| ⓓ | 즉시 대역 → CLOSED · 원장 행 · 세션 kill | 2초 |
| ⓔ | 실측 인자 꼴에서 ④ 면제 WARN + STEP 5줄 끝까지 | 2초 |
| ⓕ | 상한 REJECT 시 `.prepared` 0 · 명부·원장 **바이트 불변** · prepare 자체가 잘려도 `.prepared` 0(trap 이 prepare 전) | 3초 |
| ⓖ | 자식을 분리해 띄운 대역 → REJECT 뒤 3초 자식 쓰기 0 · 묶음 생존 0 | 5초 |
| ⓗ | TERM 무시 대역 · 상한 1초 → rc 124 · 2초에 끝남(≤3초) | 2초 |
| ⓘ | 커밋 12 · 커밋당 1초 → 배수 12 → 상한 70초 안 → **통과(rc0)** — 거짓 거절 0 | 13초 |
| ⓙ | 원격 없음 + 캐시 origin/main → fetch 실패 REJECT · cherry «전부 origin/main 에 있» 줄 0 | 2초 |
| ⓚ | `min(고정비+7×배수,70)` 값 · 600/300초 0 · 무상한 fetch 0 · trap 위치(prepare 전) | 즉시 |

## 변이 (`mutation.txt` · 6종 전부 «빨강이어야 할 칸 이름» 단언)
| 변이 | 빨강이 된 칸 |
|---|---|
| ⓐ 시각 줄 끔 | [ⓐ] |
| ⓐ 시각 줄을 stdout 으로 | [ⓐ] |
| ⓑ fetch 상한 끔 | [ⓑ] |
| ⓒ 하위 상한 끔(무제한 실행) | [ⓒ] [ⓕ] [ⓖ] [ⓗ] |
| ⓘ 배수 고정 1 | [ⓘ] |
| ⓕ abort trap 을 prepare 뒤로 | [ⓕ] |

## 기존 시험 회귀(같은 파일을 건드리므로 같이 돌렸다)
| 시험 | 결과 |
|---|---|
| test_nano_close_never_started.sh · test_nano_close_suspended.sh · test_nano_close_sha_base.sh · test_nano_close_research_r888.sh · test_nano_close_rerun_wt_clean.sh · test_nano_close_rerun_named_equal.sh · test_nano_close_std_wt_other_branch.sh · test_pack_nano_worktree_place.sh · test_reap_agent_pi_r542.sh · test_sheet_events.sh · test_baseline_lint.sh · test_r922a_news_draft_gate_warn.sh | ALL PASS |
| test_nano_feat_remote_ref.sh | fail=0 (r938: `_fetch_remote_feat` 가 `nf_fetch` 를 쓰므로 도우미 추출 2줄 + 실패 문구 단언을 «origin/main fetch 실패» 로) |
| test_r655_nano_name_prefix.sh · test_nano_spawn_teamset_cap.sh · test_da_hold_gate.sh | **선행 빨강** — origin/main 판에서도 같은 FAIL 수(내 변경과 무관) |

## press
- 필요 없음 — 이 카드는 라이브 오디오 시험 대상이 아니다(press 0). 실 좌석 1회 닫기는 master 몫(설치 뒤 STEP 줄 확인).
