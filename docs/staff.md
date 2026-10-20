# Staff renderer (M3)

Two layers:
- `PianoCore/Engraving` — `Engraver.engrave(score, measures:)` lays out a 1–2 bar window as positioned
  items (glyphs, lines, beams, ties, text) in staff spaces. Pure logic, unit-tested.
- `Pianochou/Staff/StaffView` — a SwiftUI `Canvas` that fills Bravura glyph outlines (CoreText) and
  colors items by note state: played (faded), mistake (fix), current (now) with the beat band.

Glyph metrics and engraving defaults come from Bravura's metadata (`Bravura.json`), copied into `Glyph.swift`.
Spacing and beam tunables live in `Tuning.swift` under "Staff drawing".

## Handled
Clefs (incl. 8vb), clef changes at the barline and mid-bar, key signatures and key changes (with
cancelling naturals), time signatures, noteheads, stems (by position, voice, or as written), seconds in
chords, accidentals per measure with stacking, ledger lines, dots, rests (incl. whole-bar), flags,
beams (8ths–64ths, hooks), ties (incl. across the window edge), tuplet numbers/brackets, repeat
barlines, final barline, brace. Overlays: finger numbers (right hand above, left hand below), beat
counts ("1 & 2 &" when a note falls on a half beat), current-beat highlight.

## Not yet
- Volta brackets (1. / 2. endings), dynamics, pedal marks, slurs, articulations, grace-note slashes.
- Collisions between two voices on one staff (unisons, seconds across voices) and between rests and notes.
- Cross-staff beams; beams spanning a barline.

## Checking by eye
Home → Staff gallery shows every fixture two bars at a time, with a pretend run in progress.
In the simulator: launch with `-staff-gallery -galleryFrom <fixture>`. Xcode previews are in
`StaffGalleryView.swift`.
