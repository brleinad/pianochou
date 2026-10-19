# Build plan

The riskiest part (hearing the piano) comes early. Milestone 4 is the first real end-to-end loop.
Each milestone ends with passing tests and a "Test on your iPhone" checklist.

## M0 — Project setup
- Xcode project (SwiftUI, iOS) + local Swift package `PianoCore`, wired together.
- Bundle Bravura and Hanken Grotesk fonts. `Tuning.swift`. Git repo with `.gitignore`.
- Add microphone permission text to Info.plist.
- **Done when:** app launches on device to a blank Home screen; `swift test` runs (one trivial test).

## M1 — Score model + MusicXML import (PianoCore)
- Model: `Score → Part → Measure → Note/Chord/Rest`. Each note has pitch, spelling, onset and duration
  (in beats and as a written type), staff (hand), voice, ties, tuplets, grace flag, fingering, dynamics and pedal.
  Each measure has its own key, clef and time signature.
- Parse MusicXML with Foundation `XMLParser`. Handle multiple voices per staff, chords (`<chord/>`),
  `<backup>`/`<forward>`, ties, triplets, pickup measures, clef/key/time changes, and repeats (keep both
  written order and the "as played" order).
- Fixtures (hand-written, tiny): C-major scale, 3/4 waltz bar, triplets, two voices in one staff,
  clef change, key change, pickup bar, repeat with endings.
- **Done when:** all fixtures parse to the expected events in tests.

## M2 — Hear notes (spike, highest risk)
- AVAudioEngine input tap → FFT/constant-Q. Given a set of expected MIDI pitches, report
  "sounded / not sounded" + onset time for each. Onset detection on spectral flux.
- Debug screen: pick a target note or chord, play it, see it light up, plus measured latency.
- Handle a real acoustic or digital piano through the phone mic in a normal room.
- **Done when:** single notes and 3-note chords in the middle range are detected reliably; latency is
  shown on screen. Report detection limits honestly (low bass, fast repeats, pedal blur).

## M3 — Staff renderer
- SwiftUI `Canvas` drawing a grand staff, 1–2 bars wide, using Bravura glyphs: clefs, key signature,
  noteheads, stems, beams, accidentals, ledger lines, ties, triplet brackets, rests.
- Overlays: finger numbers on notes, beat counts under the staff, current-beat highlight,
  played notes faded, mistake notes in the "fix" color. Light and dark themes.
- **Done when:** SwiftUI previews render every M1 fixture correctly.

## M4 — First practice loop (MVP)
- Load a MusicXML from Files, pick bars, pick hand(s), set tempo.
- Landscape playing screen: listen → start on the first expected note → follow along → stop on silence.
- Grade each note: right/wrong/missed, early/late (drill mode only). Between-runs screen: score,
  the one worst spot, buttons "Slower" and "Next".
- **Done when:** the user can practice bars 1–2 of their own score on the piano and get a result.

## M5 — Analyzer (PianoCore)
- Bar fingerprints from rhythm + interval pattern, so the same pattern matches when transposed → find repeated material and sections.
- Skill tagging per bar using `docs/skill-list.md` (load the list from a bundled JSON).
- Difficulty score per bar: notes/sec at target tempo, hand shifts, max stretch, rhythm complexity,
  hand independence, number of new skills. Weights in `Tuning.swift`.
- **Done when:** fixtures get the expected tags; a debug view lists tags + difficulty per bar.

## M6 — Planner (PianoCore)
- Skill graph from the skill list; plan = the song's needed skills not yet mastered, in prerequisite order.
- Chunk into 1–2 bar snippets on phrase boundaries; a snippet unlocks when its skills are learned.
- Generate practice versions per snippet: RH only, LH only, RH + LH downbeats, LH + simplified RH,
  broken chords as blocks, full slow, full at tempo.
- Concept lesson stub per skill (title + one-line text, filled in later).
- **Done when:** a plan for each fixture is produced and tested; Plan screen shows it.

## M7 — Scheduler + persistence
- SwiftData store for each snippet's state: accuracy, timing error, best tempo, hint level, last practiced.
- Daily session: 1 review (spaced-repetition intervals), 1 new snippet, 2–3 snippets alternated. ~15–25 min.
- Tempo ladder: up a step after N clean runs, down after mistakes. Hint fading by clean-run count.
  Join neighbouring snippets once both are solid.
- **Done when:** Home shows today's session and it changes based on results.

## M8 — Import + Check screen + MIDI
- Import sheet: MusicXML, MIDI. (PDF/photo comes later.)
- MIDI: read with AudioToolbox `MusicSequence`. Snap timing to the nearest note value, split hands
  (by track if available, else by pitch + hand-span rules), spell pitches from the key.
- Check screen: flag uncertain bars; for MIDI ask "Is the hand split right?"
- **Done when:** a MIDI exported from MuseScore imports and plays through M4 correctly.

## M9 — Polish to the design
- All screens match the minimal design in CLAUDE.md. Dark mode, Dynamic Type where it fits,
  VoiceOver labels, haptics only where useful.

## Later
- Automatic fingering (dynamic programming over finger choices, minimizing stretch/crossings), user-editable.
- PDF/photo import (optical music recognition).
- On-device language model for short concept explanations.
- Camera hand tracking (Vision) to check fingering.
