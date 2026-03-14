---
name: tts-say
description: "Unified Text-to-Speech CLI wrapping macOS say + ElevenLabs sag. Use when: (1) speaking text aloud, (2) generating TTS audio files, (3) agent/vibe-coding audio notifications, (4) listing/selecting TTS voices, (5) configuring default TTS engine/voice/options. Triggers: tts-say, tts, text-to-speech, 음성 출력, 읽어줘, speak, voice output."
---

# tts-say — Unified TTS CLI

Wraps macOS `say` and ElevenLabs `sag` into a single `tts-say` command.
Agents and scripts call `tts-say` only — engine selection is automatic.

> **Why `tts-say`?** `tts` conflicts with generic TTS API/tech names. `tts-say` clearly identifies this as a CLI tool.

## Install

```bash
# 1. Copy CLI to PATH
cp scripts/tts-say ~/.local/bin/tts-say
chmod +x ~/.local/bin/tts-say

# 2. sag (optional, for ElevenLabs)
brew install steipete/tap/sag
export ELEVENLABS_API_KEY="your-key"

# 3. Set defaults
tts-say config set default_engine sag
tts-say config set sag.voice "Aria"
tts-say config set sag.lang ko
tts-say config set say.voice Yuna
```

## Quick Reference

```bash
# Speak (uses config defaults)
tts-say "빌드가 완료되었습니다"

# Explicit engine
tts-say speak --engine say --voice Yuna "say로 읽습니다"
tts-say speak --engine sag --voice Aria --lang ko "sag로 읽습니다"

# Save to file
tts-say speak -o /tmp/alert.mp3 "알림음"

# Stdin
echo "파이프 입력" | tts-say

# List voices
tts-say voices --engine say
tts-say voices --engine sag --search korean --limit 10

# Config
tts-say config show
tts-say config set sag.speed 1.1
tts-say config set sag.stability 0.6
tts-say config unset say.rate
tts-say config example-env
tts-say config path
```

## Architecture

### Engine Resolution (priority order)
1. `--engine` CLI flag (highest)
2. `config.default_engine` from `~/.config/tts-say/config.json`
3. Auto-detect: sag (if API key set) → say (macOS fallback)

### Option Merge (priority order)
1. CLI arguments (highest)
2. Config file defaults (`tts-say config set ...`)
3. Engine hardcoded defaults (lowest)

### Config File

Location: `~/.config/tts-say/config.json`

```json
{
  "default_engine": "sag",
  "say": { "voice": "Yuna", "rate": 180 },
  "sag": {
    "voice": "Aria",
    "model_id": "eleven_multilingual_v2",
    "lang": "ko",
    "speed": 1.0,
    "stability": 0.5,
    "style": 0.7
  }
}
```

Dotpath set: `tts-say config set sag.stability 0.6`

## Subcommands

### `tts-say speak [OPTIONS] "text"`

| Option | Engine | Description |
|--------|--------|-------------|
| `--engine {auto,say,sag}` | both | Force engine |
| `--voice, -v` | both | Voice name/ID |
| `--output, -o` | both | Save audio to file |
| `--say-rate` | say | WPM rate |
| `--model-id` | sag | ElevenLabs model |
| `--lang` | sag | Language code (ko, en…) |
| `--speed` | sag | Speed multiplier |
| `--stability` | sag | Voice stability 0–1 |
| `--style` | sag | Style exaggeration 0–1 |
| `--similarity` | sag | Voice similarity 0–1 |
| `--speaker-boost` | sag | Enable clarity boost |
| `--no-play` | sag | Don't play (file only) |

Engine-mismatched options are silently ignored.

### `tts-say voices [--engine say|sag] [--search X] [--limit N]`

Lists voices for the specified or default engine.
Without `--engine`: shows both if available.

### `tts-say config {show|set|unset|example-env|path}`

Manage persistent config at `~/.config/tts-say/config.json`.

## Agent/Vibe-Coding Patterns

```bash
# Build notification
npm run build && tts-say "빌드 성공" || tts-say "빌드 실패"

# Test completion
pytest && tts-say "테스트 통과"

# Agent start/end
tts-say "에이전트 작업을 시작합니다"
# ... work ...
tts-say "에이전트 작업이 완료되었습니다"

# Long task alert
rsync -avz ... && tts-say "동기화 완료"
```

## Engine Details

For model-specific parameters, pronunciation tips, audio tags, and voice search:
→ Read [references/engines.md](references/engines.md)
