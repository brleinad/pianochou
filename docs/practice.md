# Practice loop (M4)

Home → pick a score (or Add a score: `.musicxml`, `.xml`, `.mxl`) → choose From and To bars (or Whole song),
hands, tempo → Start. The bars are played with their repeats and endings (`Score.playing(from:to:)`): a
range inside a repeat is played once, a range over one includes it. While playing, the staff shows
`Tuning.playingWindowBars` bars and moves on bar by bar.

- **Playing** (landscape, no taps): the first chord is highlighted; the run starts when you play it. The staff
  follows chord by chord: done notes fade, mistakes turn orange, the other hand is faded. A run ends on
  the last chord or after `Tuning.silenceGrace` of silence past when the next note was due.
- **Between runs**: score (good/total), one cell per note, the worst spot, Slower (−10%) and Next (next bars).
  Playing the first chord again starts another run.

Grading (`RunFollower`, drill mode): each note right / wrong / missed; each chord early / late when off by more
than 25% of the gap from the last chord (min 120 ms), judged from the last on-time chord *or* the chord
before, so neither a rush nor a hesitation spreads to the notes after it. Chords may be spread by 120 ms.
Grace notes are optional. Imported scores are copied to Documents/scores and never leave the phone.

Simulator checks without a piano: launch with
`-openScore <file> -autoStart YES -simulateRun YES [-simulatePause 6]`.
