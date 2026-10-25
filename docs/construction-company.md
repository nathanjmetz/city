# Construction company: spec (2026-10-25)

## What shipped (2026-10-25)

Built as planned, except for two changes:

- **Houses don't wait for their crew.** That was the plan's own condition. In a replay of Nathan's town with houses waiting, 21 homes were done in the time 104 are today, because the town's long, winding roads make every trip slow. So houses start on time. The yard's crews and concrete trucks go to each house they can reach while there's still work: the crew stays until the house is done, and the concrete truck comes for the foundation pour, or else for the driveway at the end. In the same replay, homes went up at today's pace (102 against 104), 27 crews and 11 concrete trucks arrived while work was going on, and 12 trucks arrived late.
- **Old towns get an Advice tip, not a pop-up card.** The game's rule is that nothing pops up unless asked. Until the yard is placed, Advice says: "Your first builder's yard is free: Utilities, Builder."

Other things learned along the way:

- **Builders go job to job.** A crew or concrete truck that's done drives straight on to the nearest house that can still use it.
- **Draw payments.** The company is paid 30% of its fee when its crew starts a house and the rest when the house is done. Crews are subcontractors paid by the job, so idle crews don't cost the owner wages.
- **Ratio of trucks.** The owner keeps about one concrete truck for every three crews, and never sells below the trucks it started with.
- **Trucks start straight off the street.** The yard's trucks pull straight out of its gate, instead of backing out of a stall one at a time, which made later trucks wait minutes.
- **Two older bugs fixed.** Construction trucks parked out front used to be drawn at sea level, 250 m underground, and the traffic system also parked an extra copy in the driveway.

Code: `scripts/sim/builders.gd` (the company), `scripts/sim/construction.gd` (`_from_yard`, `_next_jobs`), `scripts/sim/hub_lot.gd` (lot growth), `tests/test_builders.gd`.

---

**The plan as approved:**

**Purpose (one sentence Nathan would say aloud):** Every town starts with its own free construction company, so the builders' trucks come from inside town and show up while the work is still going on.

**Who uses it:** Every player, as the second thing they do in a new town (after the first streets).

**The one main thing on the screen:** The builder's yard. While you place it, the streets it can reach in time light up.

## Why

Trucks drive in real time, but a house goes up in about 1½ minutes of play. Today, crews and concrete trucks come from the edge of the map, which is 2 to 5½ minutes away in Nathan's town, so they almost never arrive in time. With a yard in town, most trips are short. In Nathan's words: "This removes the problem of delay altogether because the first thing you do if we start a city is to decide where to put your construction hub."

## What it does

- **Free yard at the start.** A new town gets one free **builder's yard**: an office, a gravel lot, and room for pickups and concrete trucks. You place it beside a street, like the bus depot.
- **Shows its reach while you place it.** Streets turn green where a truck from the yard gets there before a house is half built. This works the same way as the service coverage roads.
- **Added to the first-town tour.** The steps become: lay out streets → **pick your builder's yard** → power → water → zone homes.
- **A hub with a leader.** The company gets a name, an owner and its own money, the same as other hubs. It is paid for each house it builds.
- **Crews and trucks come from the yard.** Each house gets the contractor's pickup (ladder on top) and one concrete truck. The pickup stays out front until the house is done. The concrete truck stays through the foundation.
- **Builders go job to job.** A crew or truck that finishes goes straight to the nearest house waiting for one, instead of returning to the yard each time.
- **Grows with the town.** The owner buys more pickups and concrete trucks when houses are waiting, as far as the money goes, up to what the yard holds. They take the land next door when the yard is full, as the bus depot does.
- **Houses wait for their crew again.** Nathan wanted this first. It ships only if a replay of his town shows homes going up at close to today's pace. If not, houses start on time and we talk.
- **Old towns get the yard too.** A town without one gets a one-time "place your builder's yard" card. Until then it works the way it does today.

## What it does NOT do (this round)

- No masonry plant, block or brick deliveries. Later, a local quarry or masonry plant sells stone and block to the company, which helps that industry grow.
- No second yard across town.
- No change to shops, factories or civic buildings. They keep their own trucks.
- No change to how fast buildings go up.

## Data and access

- Game data only: the yard, its fleet and its books are saved inside the town save. There is no personal data, nothing leaves the game, and nothing new goes to the region server beyond what a town already sends.

## States

- **No yard yet:** the bell shows "Place your builder's yard", and crews come from the next town over, as they do now.
- **Yard placed, all trucks busy:** a house shows "Waiting for a crew (3 ahead of it)".
- **Working:** a house shows its stage, as it does now. Clicking the yard shows its trucks, which houses they're at, and its money.

## Done when (Nathan can click through this himself)

1. Start a new town. After the first streets, the tour asks you to place the builder's yard, and it's free.
2. While placing it, the streets it can reach in time turn green.
3. Zone a block of homes. Pickups and concrete trucks drive out of the yard, and each house gets one pickup parked out front until it's done.
4. Click the yard: it shows its name, its owner, its trucks and its money.
5. The town grows about as fast as it does today, and there's no jam: never more than 10 trucks on the way at once.
6. Open an old town: the "place your builder's yard" card shows up once.
