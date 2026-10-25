# Team status (start here)

Updated 2026-10-25 by the coordinating session ("Desktop photoreal handoff"). This file is the state, not a diary: rewrite it at each stop.

## Standing orders from Nathan (2026-10-25)

- "i want you to begin the work and continue without asking me anything. i wont be here to approve so i dont want you to stop."
- Merge to main when each step is verified, meaning every web-preview test passes and a second reviewer has checked the diff. Then confirm the web and desktop builds finish before calling anything live.
- What the game is and how it runs never change. What it does and how it looks are sliders on one performance budget (see `docs/desktop-photoreal-handoff.md`). Every feature and every detail is priced in measured ms and memory, next to what it adds. Costly, low-value things go to Nathan, not cut silently.
- Still waits for Nathan: anything touching sign-in, paid services, data loss, big downloads (the real county map data and its OpenStreetMap credit line), or deleting things.

## Working now (background helpers, each in its own worktree and branch)

| Helper | Branch | Goal |
| --- | --- | --- |
| Town speed | `claude/town-speed` | 69k-person town: under 15 ms a step, no step over 100 ms, builds in under a minute |
| Shared region | `claude/region-playthrough` | The region play-through finishes loading |
| New drawing style | `claude/new-drawing-test` | 16k town drawn the new way, measured against today's 58 ms, 6.7 GB and 470/369 stutters |

## Next, in order (start each when it can run without file clashes)

1. Drawing helpers, shaped by the new-drawing numbers: drawing speed and automatic quality (browser, Mac mini, Mac Studio); houses grown in code; trees that grow; ground wear and desire paths.
2. People and crowds: varied clothes and behavior, real fan behavior, and the field (players, lights, cheerleaders, camera crews).
3. Closer zoom in steps, once detail exists. It stops where extra detail stops paying off (no shirt buttons).
4. The 713 ideas in `docs/real-life-details.md`, a few at a time.

## Results so far

- `docs/scale-test-2026-10-25.md`: the measurements and the plan.
- Live today: #527 (desktop land preload), #528 (no construction-truck jam), #529 (house trucks), #530 (free builder's yard).
