# Notch Teleprompter — Requirements

A personal macOS teleprompter that sits in the MacBook notch, right under the camera, so you can read a script while looking (almost) at the lens.

## Context

- **Target machine:** MacBook Pro (2026) with notch.
- **Use cases:** live video calls (Teams, Zoom) and recorded videos.
- **Audience:** personal use only. Not distributed, no App Store.
- **Tech:** Swift + SwiftUI, macOS 14+, menu-bar app (no Dock icon).

## 1. Notch display

- Black, pill-shaped panel attached to the notch, so it looks like an extension of it.
- Shows 2–3 lines. The current line is highlighted and the other lines are dimmed.
- **Hidden from screen sharing and recording** (Zoom, Teams, OBS, QuickTime).
- Fallback: if no notch is detected (for example on an external monitor), it shows as the same panel at the top centre of the screen.

## 2. Always on top

- Floats above every window, including the menu bar.
- Visible on all desktops (Spaces) and over full-screen apps (Zoom, Teams, Keynote).
- Clicking another app never hides it.
- Show and hide it with a shortcut or from the menu-bar icon.
- The panel receives mouse events (not click-through), so trackpad scrolling and on-panel controls work.

## 3. Script input

- One script at a time.
- Paste text, or drag and drop a `.txt` or `.md` file.
- Simple editor window to write and edit the script.
- The last script is restored when the app starts.

## 4. Autoscroll

- Start, pause and resume via a global shortcut and an on-panel button.
- Optional 3-second countdown before starting.

## 5. Speed

- Speed is set in **words per minute (WPM)**.
- Change it live with shortcuts and on-panel +/- controls. The new value shows briefly.
- The last-used speed is remembered.

## 6. Manual scrolling and "return to position"

- Trackpad or mouse scroll on the panel, and shortcuts to move one sentence up or down.
- Manual scrolling pauses autoscroll.
- The app always tracks the **last sentence reached while reading**.
- A **"Return"** shortcut and button jump back to that sentence after you scroll back to re-read. You can then resume.

## 7. Search

- Search the script from the editor and from the panel (shortcut opens a small search field).
- Highlights matches, with next/previous navigation.
- Selecting a match jumps the panel to that sentence. Autoscroll pauses there.

## 8. Controls

- **Global keyboard shortcuts** (work while other apps have focus). They are customisable later; defaults are TBD.
- **Small on-panel controls** that appear on mouse hover: play/pause, speed −/+, return, search, close.
- Menu-bar icon menu: open editor, show/hide panel, settings, quit.

## 9. Settings

- Font size, panel width, number of visible lines, text colour.
- Countdown on or off.

## 10. Reference / interview mode

- Use the same panel for reference documents (CV, notes, job description), not only scripts.
- Load `.txt`, `.md`, `.rtf`, `.docx`, `.doc`, `.odt`, `.pdf` and `.html`. They're converted to plain text.
- Read by moving manually (trackpad, sentence up/down) with no autoscroll needed. Find content with search.
- Visible lines can go up to 10, to see more context.
- The last document and reading position are restored on restart.
- Hidden from screen sharing, as above.

## 11. Design for the future (not in MVP)

- **Voice-follow scrolling** (speech recognition moves the text as you speak). Build the code so the scroll position is driven by an interchangeable "scroll driver": timer/WPM now, voice later.
- The script is modelled as a list of sentences/words with indexes, so voice matching and search can share it.

## Out of scope (for now)

- Multiple scripts or a script library.
- Remote, clicker or phone control.
- Mirroring/flipping text for hardware teleprompters.
- App Store distribution.
