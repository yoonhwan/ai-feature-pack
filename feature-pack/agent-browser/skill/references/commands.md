# Agent-Browser CLI Reference (v0.16.3+)

## Core

| Command | Description | Example |
|---------|-------------|---------|
| `open <url>` | Navigate to URL | `open https://example.com` |
| `close` | Close browser | `close --session test` |
| `snapshot` | AI accessibility tree | `snapshot -i` (interactive only) |
| `screenshot [path]` | Screenshot | `screenshot ./shot.png` |
| `screenshot --full` | Full page screenshot | `screenshot --full ./full.png` |
| `screenshot --annotate` | Labeled screenshot (vision) | `screenshot --annotate` |
| `pdf <path>` | Save as PDF | `pdf ./page.pdf` |
| `eval <js>` | Run JavaScript | `eval "document.title"` |
| `connect <port\|url>` | Connect via CDP | `connect 9222` |

## Navigation

| Command | Description |
|---------|-------------|
| `back` | Go back |
| `forward` | Go forward |
| `reload` | Reload page |

## Interaction

| Command | Description | Example |
|---------|-------------|---------|
| `click <sel>` | Click | `click @e3` |
| `dblclick <sel>` | Double-click | `dblclick ".item"` |
| `fill <sel> <text>` | Clear + fill | `fill "#email" "a@b.com"` |
| `type <sel> <text>` | Append text | `type "#search" "query"` |
| `press <key>` | Key press | `press "Enter"` |
| `keyboard type <text>` | Real keystrokes (no selector) | `keyboard type "hello"` |
| `keyboard inserttext <text>` | Insert without key events | `keyboard inserttext "text"` |
| `hover <sel>` | Mouse over | `hover ".menu"` |
| `focus <sel>` | Focus element | `focus "#input"` |
| `select <sel> <val>` | Dropdown select | `select "#country" "KR"` |
| `check <sel>` | Check checkbox | `check "#agree"` |
| `uncheck <sel>` | Uncheck | `uncheck "#newsletter"` |
| `scroll <dir> [px]` | Scroll | `scroll down 500` |
| `scrollintoview <sel>` | Scroll to element | `scrollintoview "#footer"` |
| `drag <src> <dst>` | Drag and drop | `drag ".item" ".target"` |
| `upload <sel> <files>` | File upload | `upload "#file" "./doc.pdf"` |
| `download <sel> <path>` | Download by click | `download ".link" "./file"` |

## Get Info

| Command | Description |
|---------|-------------|
| `get text <sel>` | Text content |
| `get html <sel>` | Inner HTML |
| `get value <sel>` | Input value |
| `get attr <sel> <name>` | Attribute value |
| `get title` | Page title |
| `get url` | Current URL |
| `get count <sel>` | Element count |
| `get box <sel>` | Position/size |
| `get styles <sel>` | Computed styles |

## Check State

| Command | Description |
|---------|-------------|
| `is visible <sel>` | Element visible? |
| `is enabled <sel>` | Element enabled? |
| `is checked <sel>` | Checkbox checked? |

## Wait

| Command | Example |
|---------|---------|
| `wait <sel>` | `wait "#result"` |
| `wait <ms>` | `wait 2000` |
| `wait --text <text>` | `wait --text "Success"` |
| `wait --url <pattern>` | `wait --url "**/dashboard"` |
| `wait --load <state>` | `wait --load networkidle` |

## Session & Profile

| Command | Description |
|---------|-------------|
| `--session <name>` | Session isolation |
| `--profile <path>` | Persistent browser profile |
| `--session-name <name>` | Auto-save/restore state |
| `session` | Current session name |
| `session list` | List sessions |

## Tabs

| Command | Description |
|---------|-------------|
| `tab new` | New tab |
| `tab list` | List tabs |
| `tab close` | Close current tab |
| `tab <n>` | Switch to tab n |

## Network

| Command | Description |
|---------|-------------|
| `network requests` | Request list |
| `network requests --filter <p>` | Filter requests |
| `network route <url> --abort` | Block requests |
| `network route <url> --body <json>` | Mock response |
| `network unroute [url]` | Clear routes |

## Storage

| Command | Description |
|---------|-------------|
| `cookies get` | Get cookies (JSON) |
| `cookies set <json>` | Set cookies |
| `cookies clear` | Clear cookies |
| `storage local` | localStorage |
| `storage session` | sessionStorage |

## Debug

| Command | Description |
|---------|-------------|
| `console [--clear]` | Console logs |
| `errors [--clear]` | Page errors |
| `trace start` | Start Playwright trace |
| `trace stop <path>` | Save trace (.zip) |
| `profiler start` | Start Chrome profiler |
| `profiler stop <path>` | Save profile |
| `highlight <sel>` | Highlight element |

## Recording

| Command | Description |
|---------|-------------|
| `record start <path> [url]` | Start WebM recording |
| `record stop` | Stop + save |
| `record restart <path>` | Stop current + start new |

## Diff

| Command | Description |
|---------|-------------|
| `diff snapshot` | Compare current vs last snapshot |
| `diff screenshot --baseline <path>` | Compare current vs baseline image |
| `diff url <u1> <u2>` | Compare two pages |

## Find Elements

| Command | Example |
|---------|---------|
| `find role <type> <action>` | `find role button click` |
| `find text <text> <action>` | `find text "Submit" click` |
| `find label <text> <action>` | `find label "Email" fill "a@b.com"` |
| `find testid <id> <action>` | `find testid "submit-btn" click` |
| `find placeholder <text> <action>` | `find placeholder "Search..." fill "query"` |

## Browser Settings

| Command | Example |
|---------|---------|
| `set viewport <w> <h>` | `set viewport 1920 1080` |
| `set device <name>` | `set device "iPhone 14"` |
| `set geo <lat> <lng>` | `set geo 37.5665 126.978` |
| `set offline [on\|off]` | `set offline on` |
| `set headers <json>` | `set headers '{"X-Key":"val"}'` |
| `set credentials <user> <pass>` | `set credentials admin pass` |
| `set media [dark\|light]` | `set media dark` |

## Mouse (low-level)

| Command | Description |
|---------|-------------|
| `mouse move <x> <y>` | Move cursor |
| `mouse down [btn]` | Press button |
| `mouse up [btn]` | Release button |
| `mouse wheel <dy> [dx]` | Scroll wheel |

## Global Options

| Option | Description |
|--------|-------------|
| `--session <name>` | Session name |
| `--native` | Rust CDP daemon (preferred) |
| `--headed` | Show browser window |
| `--cdp <port\|url>` | CDP connection via Node.js |
| `--auto-connect` | Auto-discover Chrome |
| `--json` | JSON output |
| `--timeout <ms>` | Command timeout |
| `--proxy <url>` | Proxy server |
| `--user-agent <ua>` | Custom User-Agent |
| `--color-scheme <dark\|light>` | Color scheme |
| `--profile <path>` | Persistent profile dir |

## iOS Simulator (requires Xcode + Appium)

| Command | Example |
|---------|---------|
| `-p ios open <url>` | `agent-browser -p ios open example.com` |
| `-p ios --device <name>` | `--device "iPhone 15 Pro"` |
| `-p ios device list` | List simulators |
| `-p ios swipe <dir>` | `swipe up` |
| `-p ios tap @ref` | Touch element |

## Key Environment Variables

| Variable | Description |
|----------|-------------|
| `AGENT_BROWSER_NATIVE` | `1` = always use native mode |
| `AGENT_BROWSER_AUTO_CONNECT` | `1` = auto-discover Chrome |
| `AGENT_BROWSER_TIMEOUT` | Default timeout (ms) |
| `AGENT_BROWSER_HEADLESS` | `false` = always headed |
| `AGENT_BROWSER_ALLOWED_DOMAINS` | Comma-separated allowlist |
