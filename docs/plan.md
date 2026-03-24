# AI Feature Pack — Plan

Date: 2026-03-25

## Goals
- Package reusable AI agent skills into a portable feature-pack
- Each feature = self-contained directory with bin/, scripts/, SKILL.md
- Easy install on fresh OpenClaw instances

## Packaging Flow
1. Create feature skeleton under `features/<name>/`
2. Add bin/ (CLI wrapper), scripts/ (core logic), SKILL.md (agent instructions)
3. Test locally → commit → push
4. Publish via ClawHub or manual install

## Current Features
- [x] pdf-reader — PDF text/table extraction skeleton

## Next
- [ ] Flesh out pdf-reader with real extraction (PyMuPDF/pdfminer)
- [ ] Add more feature skeletons (browser, tts, etc.)
- [ ] ClawHub publish workflow
- [ ] Install script / bootstrap automation
