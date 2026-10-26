# Building levels driven by needs: spec (2026-10-25)

**Purpose (one sentence Nathan would say aloud):** Every home and building has a level that goes up when it has what it needs and down when it doesn't, and I can see exactly why.

**Nathan's words (2026-10-25):** "every home and building should have a 'level'. the level goes up or down based on whether it has what it needs. there should be a clear section that shows the level, what it needs, etc. clicking on it should show more detail about all its needs, the scores, etc. when properties reach a new level, an animated up (or down) arrow should show above the building for a moment"

**Who uses it:** every player, all game long.

**The one main thing on the screen:** a building's level as a big number or stars, with a row of need icons, each green, yellow or red.

## What it does
- **Needs by kind of building.**
  - Homes: power, water, sewer, trash pickup, road access, school, health care, police and fire cover, a park nearby, low noise and pollution, jobs within reach, shopping nearby.
  - Shops: customers, workers, deliveries, road access, utilities.
  - Factories: workers, freight access, utilities.
  Each need is a score from 0 to 100, built from what the town already tracks (service reach, utilities, land value, pollution, traffic and commute).
- **Level.**
  - The level rises one step when every need is above its threshold for a sustained time, and falls one step when a key need is below its floor for a sustained time. Hysteresis stops it flickering.
  - It ties into the existing building stages (BuildingTypes TYPES[type].stages, `b.level`), so a higher level can mean a bigger or better building, as now.
- **The panel** (the existing info panel when a building is selected).
  - A clear "Level N" section with the need icons.
  - "What it needs to level up" in plain words, for example "Needs a park within 400 m".
  - Clicking opens the detail: every need's score, where it comes from, and the trend.
- **The arrow.** A green up arrow or red down arrow rises above the building and fades over about 2 s when its level changes, only for buildings on screen. Sound optional, through the sound mixer.
- **A town view.** An overlay that colours buildings by level, or by their worst need.

## What it does NOT do (this round)
- No new services. It only reads what exists.
- No per-person needs.

## Data and access
- Level and need scores are part of the town save. They're worked out the same way after a load: determinism, with copies agreeing. No personal data.

## States
- A new building starts at level 1 with its needs shown at once.
- A building that is missing a basic need (power, water, road) shows it in red, with a one-line fix.

## Done when (Nathan can click through this himself)
1. Click a home: see its level and need icons. Click again for the scores.
2. Build a park beside a level 1 home that needs one. Within a game week it shows an up arrow and reads level 2.
3. Cut its power. It shows a red need, then a down arrow, and drops a level.
4. The level overlay shows the town by level.

**Depends on:** nothing new. Reads services, utilities, land value, pollution and traffic.
