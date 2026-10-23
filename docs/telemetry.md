# Play telemetry

The game watches how it gets played so it can keep getting better. It's
built for friends and family: nothing leaves your own region server, there
are no outside services, and typed text and chat are never recorded.

## What it records

- **Finding things.** A "hunt" runs from when the player starts moving the
  mouse to the last button they press before using it on the map. It keeps
  the time, the clicks, the mouse travel (in screen diagonals) and the
  buttons on the way. Backing out with Escape or wandering off counts as
  not finding it.
- **Stuck moments.** Rage clicks (four fast clicks in one spot), Escape
  spam, undo streaks, the game turning down the same kind of action again
  and again, clicks on greyed-out buttons and on things that aren't buttons.
- **Feature use.** Presses per button, keyboard shortcuts, and game
  commands done or turned down.
- **Errors.** Every engine and script error and warning, with where it
  happened and the last thing the player pressed.
- **Speed.** Frame rate, the worst frame, stutters, memory and draw calls
  every 15 s; how long each loading screen stays up; how long the web page
  takes to reach the first frame (the download included).
- **Joining.** Failed joins (with the reason the player saw) and drops.
- **Replays.** Every action in order: buttons pressed, map clicks and
  drags (in town meters), keys, what the tool's hint line said, and every
  command with its settings and whether the game took it. Stuck moments
  carry the last 90 s of this, and new ones are caught too: building
  something and tearing it down again, picking a tool and backing out
  three times, and 15 clicks on the map with nothing built.

## Where it goes

The game keeps events in `user://telemetry/outbox.json` and sends them over
the region connection it already has. The server writes them, one JSON
line per batch, to `<region file name>-telemetry/YYYY-MM-DD.jsonl` (for
`--data ~/neighbors-region.json` that's `~/neighbors-region-telemetry/`;
`--telemetry DIR` moves it). A batch leaves the outbox only once the server
says it has it, so nothing is lost while the server is off.

Set `CITY_TELEMETRY=off` before starting a desktop build to turn it off.

## The fix list

The server rewrites `report.md` in the telemetry folder every half hour
when new data has come in, and when it stops. By hand:

    godot --headless -s tools/telemetry_report.gd -- ~/neighbors-region-telemetry

That writes `report.md` and `report.json`: fixes ranked so that problems
more players hit come first, broken beats slow, and slow beats hard to find.
Each fix names the thread that owns it. The ranking rules live in
`scripts/telemetry/insights.gd`.

To read back what one player did:

    godot --headless -s tools/telemetry_replay.gd -- ~/neighbors-region-telemetry Brawn 30

Other systems can add their own events with `Telemetry.event("kind", {...})`.
