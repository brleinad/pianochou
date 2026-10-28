# Practice loop (M4)

Home → pick a score (or Add a score: `.musicxml`, `.xml`, `.mxl`) → choose From and To bars (or Whole song),
hands, tempo → Start. The bars are played with their repeats and endings (`Score.playing(from:to:)`): a
range inside a repeat is played once, a range over one includes it. The Setup preview and the playing
screen show all the bars in a sideways scroll (`ScrollingStaffView`, drawn in tiles); while playing it
follows the next notes, keeping them `Tuning.followPosition` of the way across.

- **Playing** (landscape, no taps): the first chord is highlighted; the run starts when you play it. The staff
  follows chord by chord: done notes fade, mistakes turn orange, the other hand is faded. A run ends on
  the last chord or after `Tuning.silenceGrace` of silence past when the next note was due.
- **Between runs**: score (good/total), one cell per note, the worst spot, Repeat (same bars again) and Next (next bars).
  Playing the first chord again starts another run.

Grading (`RunFollower`, drill mode): each note right / wrong / missed; each chord early / late when off by more
than 25% of the gap from the last chord (min 120 ms), judged from the last on-time chord *or* the chord
before, so neither a rush nor a hesitation spreads to the notes after it. Chords may be spread by 120 ms.
Grace notes are optional. Imported scores are copied to Documents/scores and never leave the phone.

Simulator checks without a piano: launch with
`-openScore <file> -autoStart YES -simulateRun YES [-simulatePause 6]`.

Holding notes: each note to play has a faint bar under it as long as it should be held (`HoldBars`, from
`Snippet.Note.duration`, ties included). A thin line (`RunFollower.playhead`) moves through the music at the
tempo from the last chord played and fills the bars; it waits at the next note until that is played. The
right note at the wrong time gets a small tick before (early) or after (late) it; only wrong or missed notes
turn orange. Every screen follows the phone's rotation.
