# A month is a day — spec (2026-10-26)

**Purpose (Nathan's words):** "It would make sense to the user if a month is a day and a day is an hour. So every hour you see on your screen one day pass, but there's been 1 month of progress."
**Who uses it:** every player, every session.
**The one main thing on the screen:** the sky. One long daylight per month, then a short dark night that is a natural break ("a natural point for the user to get up and use the bathroom or get a drink").

## Decisions (Nathan, 2026-10-26)
- One game month = one sky day-and-night = about one real hour. **Daylight 50 minutes, night 10 minutes.**
- Sunrise on the 1st of each month; sunset near the end; the month's last days are night. Months of 28-31 days stretch or shrink the cycle a little; sunrise always lands on the 1st.
- **The clock goes 20% faster** (Nathan picked A: "the clock is somewhat arbitrary now"), so a 30-day month takes 60 real minutes instead of 72. Today: 10 ticks a second, 1 game minute a tick.
- **One play speed.** 2x and 4x are removed; Pause stays.
- **The top bar shows no time of day:** day of the week, month and year (for example "Mon · Feb 2030").
- At night: darker and harder to see, fewer cars and walkers on screen, quieter. The town keeps building and earning at the same pace.

## What it does
- The sky (sun, moon, streetlights, window lights) follows the month, not the clock's hours.
- Night thins out what's drawn (traffic, walkers, ambient life, sounds) without changing the simulation.

## What it does NOT do (this round)
- Change how long things take in game time (a house is still the same number of game days).
- Change saves: the date saved is the same kind of date.

## Three kinds of time (Nathan 2026-10-26, settled while building)
- **Real time**: minutes on your watch.
- **Perceived time**: what you see. Anything that moves (people, cars, trains) runs in real time. Everything about the look of time follows one slow sky (SkyClock): sun, streetlights, lit windows, rush hour, the quiet night, weather.
- **Progress time**: what the game counts. The calendar (Seasons): a day is 2 real minutes, a month (28-31 days) about an hour, a year about 12 hours. Money and timers count in days.
- Named exceptions: building is shown sped up on purpose (a house in about 84 seconds). The town's own sim clock is unchanged (a sim day every 2.4 real minutes settles the budget), so the town builds and earns at the pace it always did. Lifecycles that should be seen in a session (family businesses and their signs, markers, tree growth, bank years, county fairs and other venues) count "pace years" (Seasons.pace_year: the old 29-minute year). A county fair's "July" is therefore not the calendar's July.
- Seasons, crops, school terms, winter work holds and the charter's census follow the calendar. A city charter takes effect on the 1st of the next month (the law says January 1, which could be 12 hours away).
- Towns saved before this change keep their date (CitySim.calendar_offset).

## Done when (Nathan can click through this himself)
1. Start a town on the 1st: the sun rises. Play about 50 minutes: the sun sets near the end of the month.
2. About 10 minutes of dusky, quiet night, then sunrise on the next month's 1st.
3. The top bar shows the weekday, month and year, with no clock time and no 2x/4x buttons.
4. A house takes no longer in real time than it does today.
