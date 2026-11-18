# Notch Prompter

A teleprompter for MacBooks with a notch. Your script or document sits right under the camera, so you can read while looking at the lens. It's hidden from screen sharing, so you can use it on video calls and in interviews.

See [REQUIREMENTS.md](REQUIREMENTS.md) for the full feature list.

## Install

**Option A: download a build**
1. Open the repo's **Actions** tab, choose the latest **Build macOS app** run, and download `NotchPrompter`.
2. Unzip it and move `NotchPrompter.app` to Applications.
3. The build isn't signed with an Apple Developer ID, so the first time you open it, right-click the app → **Open** → **Open**.

**Option B: build it yourself** (needs Xcode 15 or newer)

```bash
./scripts/build-app.sh
```

```bash
open build/NotchPrompter.app
```

To work on the code, open `Package.swift` in Xcode and press Run.

## Use

- The panel appears in the notch. Hover over it to see the controls.
- To resize it, drag the small handle at the bottom edge (3–20 lines).
- A menu-bar icon (☰) has every action, plus Settings.
- To load something, drop a file on the panel, press ⌃⌥O, or write or paste a script with ⌃⌥E.
- Supported files: `.txt`, `.md`, `.rtf`, `.docx`, `.doc`, `.odt`, `.pdf`, `.html`.

### Shortcuts (work in any app)

| Keys | Action |
|---|---|
| ⌃⌥Space | Play / pause |
| ⌃⌥→ / ⌃⌥← | Faster / slower |
| ⌃⌥↓ / ⌃⌥↑ | Next / previous sentence |
| ⌃⌥R | Return to where I was (after scrolling back) |
| ⌃⌥F | Search (Return = next match, Esc = close) |
| ⌃⌥G / ⌃⌥⇧G | Next / previous match |
| ⌃⌥H | Show / hide the prompter |
| ⌃⌥O | Open a document |
| ⌃⌥E | Edit the script |

## Notes

- **Screen sharing and screenshots:** by default the panel is kept out of screen sharing, recordings and screenshots. To take a screenshot, turn off **Hide from Screen Capture** in the menu-bar menu, then turn it back on. A red dot shows on the panel while it's off. Test it once with your own Teams or Zoom before an important call.
- **Code layout:** `Sources/NotchPrompter/Scrolling/ScrollDriver.swift` is where a future voice-follow mode will plug in.
