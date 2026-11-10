reviewed: v1 (.claude/plans/v6-rt-langflip-fix-design.md)
codex-session-id: 019f2bc6-215a-76c0-925e-ed9541e46bda
da-agent: ft-da (adae9aac8e13abec3)
round: 1

## VERDICT: APPROVED

- Q1 covered: `energy.start()` can run after barrier, but `createPcmCapture()` awaits the injected stream before VAD/POST can occur; the outer press continuation then reaches :440 with no await between guard pass and freezing refs.
- Q2 covered: normal `release()` awaits `ptt.release()`/`chunker.stop()` before clearing `activeSideRef`; final flush sees frozen refs after :440.
- Q3 confirmed: guard-fail, `stream=null`, and init-error paths return before :440, so they never authorize `sendSeatRef`.
- Q4 confirmed: MR/lecture use separate hooks/buildParams; solo-v5 change is not shared.
- Q5 sound: :426→:440 has no await, so JS cannot interleave another press before `sendPsidRef` snapshots `pulseSessionIdRef`.
