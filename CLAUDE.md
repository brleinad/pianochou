# Piano learning app — context for Claude Code

## What we're building
An iOS app that takes an adult from near zero to playing one specific song they chose.
The user imports a score they own (MusicXML or MIDI). The app breaks it into the skills it
needs, teaches those skills just before they're needed, and runs short daily practice
sessions on 1–2 bar snippets. It listens through the microphone and follows along on the score.

First target songs (the user's own copies, never committed to the repo):
Comptine d'un autre été (Tiersen), Plus tôt (Stréliski). Later: Studio Ghibli pieces.

## Tech decisions (settled — don't revisit without asking)
- Swift + SwiftUI, iOS only. 
- Two layers:
  - `PianoCore`: a local Swift package with all the pure logic. It covers the score model, MusicXML/MIDI import,
    analysis, the planner and the scheduler. No UIKit/SwiftUI/AVFoundation imports, so it builds and
    tests with `swift test` on macOS and Linux.
  - App target: SwiftUI screens, audio (AVAudioEngine), persistence (SwiftData).
- Sheet music: draw it ourselves with SwiftUI `Canvas` + the Bravura SMuFL font (SIL OFL).
  We only ever show a 1–2 bar window, so a full engraver isn't needed. Verovio is the fallback if this gets out of hand.
- Note detection is **score-informed**: we always know which notes *should* come next,
  so detect "did the expected pitches sound, and when", not general transcription. Use FFT/constant-Q
  energy at the expected pitches + harmonics, plus onset detection. Add an ML model only if this fails.
- Everything runs on device. Imported scores never leave the phone and are never uploaded.
- No third-party dependencies without asking first.

## How to work
- Work one milestone at a time from `docs/PLAN.md`. Start each with a short plan, then build.
- PianoCore is test-first: write XCTest/Swift Testing cases with tiny hand-written MusicXML fixtures
  in `PianoCore/Tests/Fixtures/`. Fixtures must be original or public domain. Never commit copyrighted scores.
- Run `swift test` (PianoCore) and build the app before saying a milestone is done.
- You can't hear a piano. End every milestone with a short **"Test on your iPhone"** checklist:
  exact steps for the user to verify by hand, and what they should see.
- Keep tunable numbers (timing tolerances, tempo steps, hint-fade thresholds) in one
  `Tuning.swift` file with comments, not scattered.
- Small commits, one per working step, with clear messages.

## The learning method (from research — the planner and scheduler must follow this)
- Teach backward from the target song: only the skills the song needs, right before they're needed.
- Practice tiny chunks; find the exact hard spot and loop it slower until it's fixed.
- Ladder per snippet: right hand → left hand → one hand full + other hand simplified → both hands slow → up to tempo.
- Interleave 2–3 snippets in a session instead of repeating one.
- Short daily sessions (~15–25 min). Start each with a quick review of yesterday's snippet.
- Fade the help: rich note-by-note feedback when new, then feedback only after a run, then no hints.
- Grade strict timing in drills only. In full run-throughs follow the player's tempo (rubato).
  Grade grace notes and ornaments leniently.

## Skills
`docs/skill-list.md` is the source of truth: 54 skills with prerequisites, IDs like R1, T9, H15, M7.
The analyzer tags each bar with skill IDs; the planner orders missing skills by prerequisites.

## Design (minimal — less text is always better)
- Two contexts:
  - **In hand (portrait):** Home, Import, Check the reading, Plan.
  - **On the stand (landscape):** Playing, Between runs. Big type, readable at ~60 cm.
- While playing, no taps are needed: a run starts on the first note and ends on silence.
- One main action per screen. Almost no text: numbers, a few words, no explanations on screen.
- Finger numbers sit on the notes, with beat counts under the staff. No separate keyboard graphic while playing.
- Status lives at the edges (thin progress line, small listening dot). No pop-ups mid-run, no confetti, no streaks.
- Colors: paper `#F6F6F3`, ink `#121212`, muted `#6A6A66`, hairline `#DCDCD7`,
  now/current `#1F4FE0`, fix/mistake `#C2410C`. Dark (evening) mode: bg `#0E0E0D`, ink `#EDEDE9`,
  now `#8AA6FF`, fix `#FB923C`.
- One typeface: Hanken Grotesk (SIL OFL, bundle it). Light weight for big numbers.
- Touch targets ≥ 44 pt, pill buttons 56–60 pt tall.
