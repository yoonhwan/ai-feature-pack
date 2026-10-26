# r938 증거 — ft-nano-close.sh 단계 시각 줄 + 외부 호출 7초 상한

카드: `design/harness/indices/진행/r938-nano-close-step-timing-and-7s-caps.md` · Issue #3618 · 1.1.245

## 무엇이 문제였나
라이브 1.1.244 에서 `ft-nano-close.sh byz-planner-nano-r-planner-worktree-census#0 --result … --recv 169092` 가 3회 모두 70초+ 무출력으로 멈췄고, 마지막 출력은 `WARN ④checkpoint 면제` 였다. 그 뒤 단계들의 출력은 변수에 담겨 끝에 한꺼번에 나오기 때문에 «어느 단계에서 멈췄는지» 화면으로 알 길이 0 이었다. 원격 받아오기(fetch)에는 시간 상한이 없었다.

## 고친 것 (파일 1 + 시험 2)
| 축 | 값 |
|---|---|
| ⓐ 단계 시각 줄 | ④checkpoint 뒤 단계마다 stderr 로 `STEP <이름> +<초>s` (⑥증거검사 · ⑤cherry · fetch · freshness · sheet · ledger · slots) · stdout 은 손대지 않는다 |
| ⓑ fetch 상한 | `nf_fetch` = `fm_fetch`(ft-merge-lib.sh 공용 · 시도당 7초 + 재시도 1 = 총 ≤14초) · 실패면 «origin/main fetch 시간 초과(7초+재시도 1) 또는 실패 — 옛 ref 로 대조하지 않는다(R22)» |
| ⓒ 하위 검사 상한 | `nf_bound` = `min(고정비 4.5초 + 7초 × 배수, 70초)` 초과 시 rc 124 → «<단계> 시간 초과(11s 상한) — 닫지 않음» (명부·원장·세션 변경 0) |
| 무상한 호출 | `grep -c 'fetch -q'` = **0** — 카드 ref·연구·cherry 재대조·feat ref 네 곳 전부 `nf_fetch` 경유 |

## 실측 표 (ⓐ만 넣은 판 · 하위 스크립트 대역이 90초 걸리는 인자 꼴: `--result` · `--recv` · role=nano · press 산출 0)
| 단계 | ④ WARN 뒤 다음 STEP 줄 | 그 단계가 먹은 시간 | 멈췄나 |
|---|---|---|---|
| ⑥증거 검사 | `STEP ⑤cherry +91s` | 91초 | 예 — 무출력 멈춤(원인 단계) |
| ⑤cherry 게이트 | `STEP sheet +91s` | 90초 | 예 — 무출력 멈춤 |
| freshness | (다음 줄 없음 · 90초 뒤 끝) | 90초 | 예 — 무출력 멈춤 |
| fetch(원격) | `STEP freshness +15s` | 14초(7+재시도1) | 아니오 — 상한에서 잘림 |

근거 파일: `steps/pre-cap-c-evidence.txt` · `steps/pre-cap-c-cherry.txt` · `steps/pre-cap-c-freshness.txt` (상한만 끈 사본 = «ⓐ만 넣은 판» 과 같은 시간 거동) · `pre-cap-test.txt`(그 회차 전체 출력)

## 기존 닫기 시험 회귀(같은 파일을 건드리므로 같이 돌렸다)
| 시험 | 결과 |
|---|---|
| test_nano_close_never_started.sh | ALL PASS |
| test_nano_close_sha_base.sh | ALL PASS |
| test_nano_feat_remote_ref.sh | fail=0 (r938: _fetch_remote_feat 가 nf_fetch 를 쓰므로 시험이 그 도우미도 떼어 오게 2줄 고침) |
| test_nano_close_research_r888.sh · test_nano_close_rerun_wt_clean.sh · test_nano_close_rerun_named_equal.sh · test_nano_close_std_wt_other_branch.sh · test_pack_nano_worktree_place.sh · test_reap_agent_pi_r542.sh | ALL PASS |
| test_sheet_events.sh · test_harness_root.sh · test_nano_team_env.sh · test_wt_sweep_budget_replan_r535.sh · test_install_worktree_shim.sh · test_baseline_lint.sh | ALL PASS |
| test_r655_nano_name_prefix.sh · test_nano_spawn_teamset_cap.sh · test_da_hold_gate.sh | **선행 빨강**(origin/main 판에서도 같은 FAIL 수 — 내 변경과 무관) |

## 고친 뒤 (상한이 걸린 판)
| 시나리오 | 결과 | 걸린 시간 | 근거 |
|---|---|---|---|
| 정상 대역(모두 즉시) | `CLOSED` · STEP 5줄 · stdout 그대로 | 1~2초 | `steps/a-normal.txt` |
| fetch 대역 30초 | `REJECT` «origin/main fetch 시간 초과» · 두 번째 게이트 호출 0 | 15초 | `steps/b-fetch.txt` |
| 증거 검사 대역 90초 | `REJECT` «⑥증거 검사 시간 초과(11s 상한) — 닫지 않음» | 11초 | `steps/c-evidence.txt` |
| cherry 게이트 대역 90초 | `REJECT` «⑤cherry 게이트 시간 초과(11s 상한) — 닫지 않음» · freshness 단계 0 | 11초 | `steps/c-cherry.txt` |
| freshness 대역 90초 | `REJECT` «⑤-생애 freshness 시간 초과(11s 상한)» | 12초 | `steps/c-freshness.txt` |

## 시험
- `tests/test_nano_close_step_timing_r938.sh` — 전 축 초록: `test-green.txt` (ALL PASS · `/bin/bash` 3.2)
- `tests/mutate_r938_step_timing.py` — 변이 3종 전부 빨강: `mutation.txt`
  - ⓐ 시각 줄 끔 → STEP 5줄 검사 빨강(8 FAIL)
  - ⓑ fetch 상한 끔(옛 판 무상한 git fetch) → «시간 초과» 문구·총 소요 빨강(7 FAIL · 31초)
  - ⓒ 하위 상한 끔(nf_bound 통과) → 상한 검사 빨강(15 FAIL · 92초 멈춤 재현)

## press
- 필요 없음 — 이 카드는 라이브 오디오 시험 대상이 아니다(press 0). 실 좌석 1회 닫기는 master 몫(설치 뒤).
