# Build plan

Scope: import a MusicXML score you own, pick any bars (up to the whole song), play them on the piano;
the app listens and tells you how well you played them: each note right, wrong or missed, early or late.
No PDF import, no MIDI, no skills or lesson planning (that work lives on the `full-scope` branch).

Each milestone ends with passing tests, an app build, and a "Test on your iPhone" checklist.

## Done

### M0 — Project setup
- Xcode project (SwiftUI, iOS) + local Swift package `PianoCore`, wired together.
- Bundle Bravura and Hanken Grotesk fonts. `Tuning.swift`. Git repo with `.gitignore`.
- Add microphone permission text to Info.plist.
- **Done when:** app launches on device to a blank Home screen; `swift test` runs (one trivial test).

### M1 — Score model + MusicXML import (PianoCore)
- Model: `Score → Part → Measure → Note/Chord/Rest`. Each note has pitch, spelling, onset and duration
  (in beats and as a written type), staff (hand), voice, ties, tuplets, grace flag, fingering, dynamics and pedal.
  Each measure has its own key, clef and time signature.
- Parse MusicXML with Foundation `XMLParser`. Handle multiple voices per staff, chords (`<chord/>`),
  `<backup>`/`<forward>`, ties, triplets, pickup measures, clef/key/time changes, and repeats (keep both
  written order and the "as played" order).
- Fixtures (hand-written, tiny): C-major scale, 3/4 waltz bar, triplets, two voices in one staff,
  clef change, key change, pickup bar, repeat with endings.
- **Done when:** all fixtures parse to the expected events in tests.

### M2 — Hear notes (spike, highest risk)
- AVAudioEngine input tap → FFT/constant-Q. Given a set of expected MIDI pitches, report
  "sounded / not sounded" + onset time for each. Onset detection on spectral flux.
- Debug screen: pick a target note or chord, play it, see it light up, plus measured latency.
- Handle a real acoustic or digital piano through the phone mic in a normal room.
- **Done when:** single notes and 3-note chords in the middle range are detected reliably; latency is
  shown on screen. Report detection limits honestly (low bass, fast repeats, pedal blur).

### M3 — Staff renderer
- SwiftUI `Canvas` drawing a grand staff, 1–2 bars wide, using Bravura glyphs: clefs, key signature,
  noteheads, stems, beams, accidentals, ledger lines, ties, triplet brackets, rests.
- Overlays: finger numbers on notes, beat counts under the staff, current-beat highlight,
  played notes faded, mistake notes in the "fix" color. Light and dark themes.
- **Done when:** SwiftUI previews render every M1 fixture correctly.

### M4 — First practice loop (MVP)
- Load a MusicXML from Files, pick bars, pick hand(s), set tempo.
- Landscape playing screen: listen → start on the first expected note → follow along → stop on silence.
- Grade each note: right/wrong/missed, early/late (drill mode only). Between-runs screen: score,
  the one worst spot, buttons "Slower" and "Next".
- **Done when:** the user can practice bars 1–2 of their own score on the piano and get a result.

### Metronome and tempo
- Metronome toggle and tempo − / + on the playing screen; 6/8 clicks on the dotted quarter, beat 1
  accented. Recorded public-domain clicks; the listener is told when each click reaches the microphone
  and ignores it.

## Next

### N1 — Any number of bars, up to the whole song
- Setup: choose From and To freely, plus one tap for the whole song.
- Repeats and endings are followed as played (`Score.playedOrder`).
- Playing: draw a window of about two bars that moves forward as you play; the thin progress line shows
  where you are in the whole range.
- **Done when:** the whole of a real song can be played through and followed to the end, repeats included.

### N2 — Feedback, kept simple
- While playing: right notes fade, wrong notes turn orange, missed notes are marked once passed,
  early/late notes get a small mark (direction by position).
- After a run: good/total, one cell per note, the worst spot, and one timing word (Rushing, Dragging,
  Steady). Timing is judged against the note before, so slow drift isn't punished.
- Long ranges: the result shows the bars with their marks, scrollable to the bad spots.
- **Done when:** after a run the user can see which notes were wrong, missed, early or late, and why the
  score is what it is.

### N3 — History (SwiftData)
- Save each run: score, bars, hands, tempo, date, right/wrong/missed, average timing error.
- Setup shows the last few results for the chosen bars, to see progress.
- Practice settings stay in UserDefaults.
- **Done when:** results survive relaunches and show on Setup.

### N4 — Polish to the design
- All screens match the minimal design in CLAUDE.md: dark mode, Dynamic Type where it fits, VoiceOver
  labels, touch targets. Remove debug launch options no longer needed.

## Later
- Automatic fingering, user-editable.
- Camera hand tracking (Vision) to check fingering.
