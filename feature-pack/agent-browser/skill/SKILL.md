---
name: agent-browser
description: >
  Browser automation via agent-browser CLI (Playwright + Rust CDP). Use when the task involves
  opening web pages, clicking/filling elements, taking screenshots, scraping content, recording
  videos, debugging console/network, form automation, login flows, cookie management, or generating
  styled screenshot cards from HTML. Triggers on "browse", "open page", "screenshot", "scrape",
  "E2E test", "form fill", "login automate", "record video", "console log", "network mock",
  "hero card", "스크린샷", "브라우저", "페이지 열어", "캡처", "녹화".
  NOT for web search (use web_search/web_fetch) or simple URL content reading (use web_fetch).
---

# Agent-Browser Skill

CLI browser automation for AI agents. Two modes: **native** (Rust CDP, preferred) and **standard** (Node.js Playwright).

## Installation Check

```bash
which agent-browser || echo "NOT INSTALLED — run: npm install -g agent-browser && agent-browser install"
agent-browser --version  # expect 0.16.3+
```

## Mode Selection

| Scenario | Mode | Why |
|----------|------|-----|
| General browsing/scraping | `--native` | Faster (~150ms/page), no Node.js |
| Screenshot/capture | `--native` | Lower latency |
| Chrome extension needed | `--native connect <port>` | Real Chrome only |
| Complex JS SPA rendering issues | standard (no flag) | Playwright stability |
| CI/CD pipeline | standard headless | Proven reliability |

**Default: always try `--native` first.** Fall back to standard if issues arise.

## Core Workflow

```bash
SESSION="task-$(date +%s)"
trap "agent-browser close --session $SESSION 2>/dev/null" EXIT ERR

# 1. Open (native + headed for local)
agent-browser --native --session "$SESSION" --headed open "https://example.com"

# 2. Wait for load
agent-browser --native --session "$SESSION" wait --load networkidle

# 3. Snapshot first (get @refs)
agent-browser --native --session "$SESSION" snapshot -i
# Output: [e3] button "Submit"  [e5] input#email ...

# 4. Interact via @ref (preferred) or CSS selector
agent-browser --native --session "$SESSION" click @e3
agent-browser --native --session "$SESSION" fill @e5 "hello@world.com"

# 5. Verify
agent-browser --native --session "$SESSION" get text ".result"

# 6. Screenshot
agent-browser --native --session "$SESSION" screenshot ./result.png

# 7. Close
agent-browser --native --session "$SESSION" close
```

### Command Chaining (single shell)

```bash
agent-browser --native open example.com && agent-browser --native snapshot -i && agent-browser --native screenshot shot.png
```

## Key Patterns

### Session Isolation
Always use `--session <name>` + `trap` cleanup:
```bash
trap "agent-browser close --session $SESSION 2>/dev/null" EXIT ERR
```

### Snapshot-First Principle
Before any interaction, run `snapshot -i` to discover elements. `@ref` values change per session — never reuse across sessions.

### Headed vs Headless
- **Local**: `--headed` (see what's happening)
- **CI/CD**: omit `--headed` (headless default)

### Wait Strategies
```bash
wait "#element"              # element appears
wait 2000                    # fixed delay (ms)
wait --text "Success"        # text appears
wait --url "**/dashboard"    # URL matches
wait --load networkidle      # all requests settled
```

### Login & Cookie Persistence
```bash
# Save cookies after login
agent-browser --native --session "$SESSION" cookies get > cookies.json

# Restore in new session
agent-browser --native --session "$SESSION" cookies set "$(cat cookies.json)"
```

### Login Popup Bypass
Do NOT `remove()` DOM elements (destroys content). Use CSS hide:
```bash
agent-browser --native --session "$SESSION" eval "
  document.querySelectorAll('div[role=\"dialog\"], [class*=\"modal\"]').forEach(el => {
    if (getComputedStyle(el).position === 'fixed') el.style.display = 'none';
  });
  document.body.style.overflow = 'auto';
"
```

### Network Mocking
```bash
# Block analytics
agent-browser --native --session "$SESSION" network route "**/analytics/*" --abort

# Mock API response
agent-browser --native --session "$SESSION" network route "**/api/user" --body '{"id":1,"name":"Test"}'

# Clear routes
agent-browser --native --session "$SESSION" network unroute
```

### Video Recording
```bash
agent-browser --native --session "$SESSION" --headed open "https://example.com"
agent-browser --native --session "$SESSION" record start "./demo.webm"
# ... do actions ...
agent-browser --native --session "$SESSION" record stop

# Convert to GIF
ffmpeg -i demo.webm -vf "fps=10,scale=480:-1:flags=lanczos" -c:v gif demo.gif
```

### Debug Console/Errors
```bash
agent-browser --native --session "$SESSION" console          # view logs
agent-browser --native --session "$SESSION" errors           # view errors
agent-browser --native --session "$SESSION" eval "document.title"  # run JS
```

## Native CDP Connection

Connect to an already-running Chrome instance:

```bash
# By port
agent-browser --native connect 9222 --session "$SESSION"

# By WebSocket URL
agent-browser --native connect "ws://127.0.0.1:9222/devtools/browser/UUID" --session "$SESSION"

# Auto-discover running Chrome
agent-browser --auto-connect --native snapshot
```

Use `--native connect` when:
- Chrome extensions are needed
- macOS audio (BlackHole) loopback required
- Connecting to remote/debug Chrome instances

## Screenshot Card Pipeline

Generate mobile-optimized styled cards from HTML for sharing (Slack, Discord, etc.).

### Constraints
- agent-browser viewport is **fixed 1280×720px** — content taller than ~620px gets clipped
- Target card width: **375px** (mobile-friendly)
- Final output: **2× retina scale** (830px wide)

### Pipeline

```bash
# 1. Write HTML card (375px wide, ≤620px tall)
cat > /tmp/card.html << 'HTMLEOF'
<html><body style="width:375px; margin:0; padding:16px; background:#1a1a2e; color:#e0e0e0; font-family:-apple-system,sans-serif; font-size:12px;">
  <!-- content here -->
  <div style="text-align:center; color:#555; font-size:9px; margin-top:8px;">footer ✓</div>
</body></html>
HTMLEOF

# 2. Screenshot
agent-browser --native --session cap open "file:///tmp/card.html"
agent-browser --native --session cap screenshot "/tmp/raw.png"
agent-browser --native --session cap close

# 3. Crop + 2× retina scale
python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/raw.png")
w, h = img.size
crop_w = 415  # 375 + padding
pixels = img.load()
bg = pixels[0, 0]
bottom = h
for y in range(h - 1, 0, -1):
    for x in range(0, min(crop_w, w), 8):
        if pixels[x, y] != bg:
            bottom = min(y + 12, h)
            break
    else:
        continue
    break
cropped = img.crop((0, 0, min(crop_w, w), bottom))
final = cropped.resize((cropped.width * 2, cropped.height * 2), Image.LANCZOS)
final.save("/tmp/final.png")
PYEOF
```

### Card Design Rules

| Content | Title | Body | Code/Table | Padding |
|---------|-------|------|-----------|---------|
| Short (1-2 sections) | 15px | 12px | 11px | 20px |
| Medium (2-3 sections) | 14px | 11px | 10px | 16px |
| Long (20+ row table) | 13px | 10.5px | 9.5px | 14px |

**Split rules**: If content > 620px tall → split into multiple cards (1 card = 1 topic). Always verify with `image` tool that footer is visible. A clipped card is worse than an extra card.

**Theme**: Dark (bg: `#1a1a2e`, card: `#16213e`, table-header: `#0f3460`, border: `#1a4080`).

### Verify & Send

```bash
# Verify: use image tool to check footer visibility
# If clipped → split cards or reduce font

# Send to Slack (example)
openclaw message send \
  --channel slack \
  --target "channel:<ID>" \
  --message "Caption" \
  --media /tmp/final.png \
  --reply-to <thread_ts>
```

## Locator Strategy (Priority Order)

1. **@ref** from `snapshot -i` — most reliable, AI-native
2. **CSS selector** — `#id`, `.class`, `[attr=val]`
3. **find** commands — `find role button click`, `find text "Submit" click`, `find testid "btn" click`

## Error Recovery

| Error | Fix |
|-------|-----|
| `No session found` | Run `open` first |
| `Element not found` | Run `snapshot -i`, check refs |
| `Timeout` | Increase `--timeout`, check `wait` condition |
| Zombie session | `agent-browser session list` → `close --session <name>` |
| `--native` fails | Remove `--native` flag, use standard mode |

## Full CLI Reference

See `references/commands.md` for complete command table.

```bash
agent-browser --help           # all commands
agent-browser <command> --help # per-command help
```
