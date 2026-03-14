# Engine Reference

## say (macOS built-in)

### Korean voices
```bash
say -v '?' | grep ko_KR
# Eddy, Flo, Grandma, Grandpa, Reed (ko_KR)
```

### Parameters
| Flag | Type | Description |
|------|------|-------------|
| `-v NAME` | string | Voice name |
| `-r WPM` | int | Words per minute (default ~175) |
| `-o PATH` | path | Save to file (.aiff, .m4a) |

### File formats
- Default: AIFF
- `-o out.m4a --data-format aac` for M4A

### Limitations
- macOS only
- No streaming API
- Limited expressiveness
- No SSML support

---

## sag (ElevenLabs)

### Requirements
- `brew install steipete/tap/sag`
- `ELEVENLABS_API_KEY` environment variable

### Models
| Model | ID | Notes |
|-------|----|-------|
| v3 (default) | `eleven_v3` | Most expressive |
| Multilingual v2 | `eleven_multilingual_v2` | Stable, multi-lang |
| Flash v2.5 | `eleven_flash_v2_5` | Fast, cheap |
| Turbo v2.5 | `eleven_turbo_v2_5` | Balanced |

### Parameters
| Flag | Type | Description |
|------|------|-------------|
| `-v NAME` | string | Voice name or ID |
| `--model-id` | string | Model (default: eleven_v3) |
| `--lang` | string | 2-letter ISO code (e.g. ko, en) |
| `--speed` | float | Speed multiplier (0.5–2.0) |
| `--stability` | float | 0–1, higher = more consistent |
| `--style` | float | 0–1, higher = more stylized |
| `--similarity` | float | 0–1, voice similarity boost |
| `--speaker-boost` | bool | Improve clarity |
| `-o PATH` | path | Save to file (.mp3) |
| `-r WPM` | int | say-compatible WPM rate |

### v3 Audio Tags
Place at line start:
- `[whispers]`, `[shouts]`, `[sings]`
- `[laughs]`, `[sighs]`, `[excited]`, `[sarcastic]`
- `[short pause]`, `[long pause]`

Example: `tts-say speak --engine sag "[whispers] 조용히 말할게요"`

### Pronunciation Tips
- Respell for clarity: "key-note" → "kee-note"
- `--lang ko` for Korean normalization
- `--normalize auto` for numbers/URLs

### Voice Search
```bash
tts-say voices --engine sag --search korean --limit 10
```
