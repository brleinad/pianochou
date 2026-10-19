# Piano app — skill list (v1)

Each skill: ID · name · needs (prerequisites). The lesson planner tags each bar of an imported MusicXML with the skills it needs, then orders the missing ones by prerequisites.

★ = added after checking common Studio Ghibli piano repertoire (Joe Hisaishi and others).

## Reading
| ID | Skill | Needs |
|---|---|---|
| R1 | Keyboard map: black-key groups, find any C | — |
| R2 | Treble staff landmarks (middle C, G, high C) | R1 |
| R3 | Bass staff landmarks (middle C, F, low C) | R1 |
| R4 | Reading by steps and skips | R2, R3 |
| R5 | Ledger lines | R4 |
| R6 | Sharps, flats, naturals | R4 |
| R7 | Key signatures, 1–2 sharps or flats | R6, M2 |
| R8 | Repeats, 1st and 2nd endings | T1 |
| R9 ★ | D.C., D.S., coda | R8 |
| R10 ★ | Octave signs (8va, 8vb) | R5 |
| R11 ★ | Clef changes (both hands in treble, etc.) | R4 |
| R12 ★ | Keys with 3+ sharps or flats | R7 |

## Rhythm
| ID | Skill | Needs |
|---|---|---|
| T1 | Steady pulse and counting | — |
| T2 | Quarter, half, whole notes and rests | T1 |
| T3 | Eighth notes | T2 |
| T4 | Dotted notes | T3 |
| T5 | Ties | T2 |
| T6 | Sixteenth notes | T3 |
| T7 ★ | 3/4 time | T2 |
| T8 ★ | Pickup notes (anacrusis) | T2 |
| T9 ★ | Triplets | T3 |
| T10 ★ | Syncopation | T3, T5 |
| T11 ★ | 6/8 and compound time | T9 |
| T12 ★ | Two against three | T9, H8 |
| T13 ★ | Rubato, ritardando, fermata, a tempo | T1 |

## Technique
| ID | Skill | Needs |
|---|---|---|
| H1 | Posture, curved fingers, finger numbers | — |
| H2 | Five-finger position, one hand | H1, R1 |
| H3 | Position shifts | H2 |
| H4 | Thumb under, finger over | H3 |
| H5 | Broken-chord / rolling left hand | H2, M3 |
| H6 | Block chords (triads) | H2, M3 |
| H7 | Hands together, same rhythm | H2, T2 |
| H8 | Hands together, different rhythms | H7, T3 |
| H9 | Legato and staccato | H2 |
| H10 | Fast right-hand runs | H4, T6 |
| H11 | Octave reach | H3 |
| H12 | Sustain pedal (direct, then legato pedalling) | H7 |
| H13 | Dynamics: soft/loud, crescendo/diminuendo | H2 |
| H14 | Melody louder than accompaniment (between hands) | H8, H13 |
| H15 ★ | Waltz bass: low note, then chord (leap) | H6, T7, H3 |
| H16 ★ | Wide arpeggios beyond one hand position | H5, H4 |
| H17 ★ | Melody and accompaniment in the same hand (voicing the top note) | H14, H6 |
| H18 ★ | Melody in octaves | H11 |
| H19 ★ | Grace notes and simple ornaments (trill, mordent) | H9 |
| H20 ★ | Big leaps and hand crossing | H3 |

## Theory
| ID | Skill | Needs |
|---|---|---|
| M1 | Half and whole steps | R1 |
| M2 | Major and minor scales | M1 |
| M3 | Major and minor triads | M2 |
| M4 | Inversions | M3 |
| M5 | Common progressions (incl. IV–V–iii–vi) | M3 |
| M6 ★ | 7th and 9th chords | M4 |
| M7 ★ | Sus and quartal chords (built in 4ths) | M3 |
| M8 ★ | Mode and pentatonic colours (Lydian, minor pentatonic) | M2 |
| M9 ★ | Key changes within a piece | R7, M5 |

## What the additions mean for the app
- **Rubato (T13):** the microphone can't grade strict timing during expressive passages. Grade strict timing in drills only; in full run-throughs, follow the player's tempo.
- **Ornaments (H19):** grace notes are very short and easy for pitch detection to miss. Grade them leniently.
- **Same-hand voicing (H17):** the MusicXML parser must read multiple voices within one staff (`<voice>`), not just one line per hand.
- **Clef changes, octave signs, key changes (R10, R11, M9):** tag each bar with its local clef and key, not one value per piece.
