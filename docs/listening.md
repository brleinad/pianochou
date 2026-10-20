# Note detection (M2)

Code: `PianoCore/Sources/PianoCore/Listening/`. Numbers: `Tuning.swift` › Listening.

## How it works
- 4096-sample Hann FFT every 512 samples (85 ms window, ~11 ms steps at 48 kHz).
- Each pitch gets a **salience**: the weighted mean *contrast* of up to 8 partials. Contrast = how far a
  partial stands above both the noise floor and the spots a semitone either side. Leakage from loud
  neighbours and broadband hammer/room noise give low contrast.
- Only partials where a semitone spans ≥ 2.5 bins are used, so low notes are judged on higher harmonics.
- **Onset** of an expected pitch = salience present (≥ 10 dB) and jumped ≥ 6 dB within 60 ms.
  The pitch re-arms once its salience levels off, so one strike isn't counted twice.
- **Octave guards:** the lower note needs an odd partial; the upper note is rejected if the odd partials
  of the octave below (1.5·f0, 2.5·f0) stand out — unless the chord explains them.
- **Unexpected note** = broadband strike (spectral flux + energy rise) with no expected onset within 80 ms,
  and a pitch guess exists. Unpitched noises are ignored.

## Measured on synthetic tones (tests)
- Reliable from A1 (55 Hz) to A7, soft or loud, with room noise at −40 dBFS.
- Algorithm latency ≈ 40 ms after the strike; strike time estimated within ±15 ms.
- Repeated notes every 300 ms, with or without pedal; 3-note chords; wrong notes; octave errors.

## Known limits
- **Lowest keys (A0–F#1)** are not detected; with a piano 30 cents flat the limit rises to ~C2.
  Fix if needed: a larger FFT for the bass, or a lower `minSemitoneBins`.
- **C8** can double-trigger (one usable partial).
- **Fast repeats** of the same note faster than ~10/s merge (`onsetRefractory`).
- **Semitone clusters** in one chord (e.g. E+F together) lower each note's contrast.
- **Pedal blur:** a held note's harmonics stay high, so a new note sharing many partials with it
  (octave, fifth) rises less. Untested on a real piano yet.
- Synthetic tones are cleaner than a real piano in a room. Real-piano results go here once tested.
