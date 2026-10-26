# Traffic control that grows with the town: spec (2026-10-25)

**Purpose (one sentence Nathan would say aloud):** Early on I time my own traffic lights; as the town grows I can coordinate them, and later hire engineers to tune them for me.

**Nathan's words (2026-10-25):** "I don't just wanna put a traffic light at a intersection. I want to coordinate that traffic light with other lights or set one direction to be longer than the other one based on traffic flow… I could eventually build a traffic flow building or add a civic engineering wing to a university and they would fine-tune all of that for me… Early on the traffic issues are mine to deal with because they are simple. Later in the game, they become more complicated and so we provide more sophisticated solutions, just like in real life."

**Who uses it:** the player, from the first signal to a big city.

**The one main thing on the screen:** a signal's panel. It shows the junction, each direction's green time as a bar, live queue lengths, and cars per green.

## What it does (in stages, unlocked as the town grows)

1. **Your own lights (from the start).**
   - Click a signal to set each direction's green time.
   - Choose a few plans: fixed time, "main road gets more", or "left-turn arrow".
   - The panel shows the queue and cars per green, so you can see whether it helped.
2. **Coordinated lights, a "green wave" (unlocked by town size or road count).**
   - Link lights along a street so a car at the speed limit hits green after green.
   - Set the travel direction and the speed. The game works out the offsets.
3. **Lights that sense cars (needs a road department or a small budget line).**
   - Sensors in the road give green to whoever is waiting, and skip empty turns.
   - Real name: actuated signals.
4. **A Traffic Management Center (civic building), or a civil engineering wing at a university.**
   - Engineers watch the whole network and keep retuning timing, coordination and plans by time of day: rush hour, night and events.
   - Better staffing or funding means better tuning. Real name: adaptive signal control (SCOOT and SCATS are real systems).
   - The player can still override any light by hand.

**Design rule this follows (Nathan, 2026-10-25):** simple problems are the player's to solve by hand early on. As the town grows and problems get harder, the game offers more sophisticated tools and institutions, as in real life. Use the same pattern elsewhere: water, power, schools, health and policing.

## What it does NOT do (this round)
- No freeway ramp meters or roundabout design.
- No traffic police directing intersections by hand.

## Data and access
- Signal plans are part of the town's save. No accounts and no personal data. In a shared region, only the town's owner can change its lights.

## States
- A new signal starts with sensible default timing, by traffic engineering rules.
- A light that's badly timed shows a growing queue and a hint ("north-south waits 70 s; try a longer green").

## Done when (Nathan can click through this himself)
1. Place a light, open its panel, and give the main road a longer green. The queue on the main road gets shorter within two cycles.
2. Link three lights on a street as a green wave, then drive a car along it (follow cam). It gets three greens in a row.
3. Build the Traffic Management Center. Within a game day the worst junction's queue drops, and the panel says the engineers retimed it.
4. Turn any of it off and the lights go back to the player's own timing.

**Depends on:** the green-light fix (drivers using a green properly; branch `claude/green-light-flow`). Timing a light means nothing if the cars hesitate.
