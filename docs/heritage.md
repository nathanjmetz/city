# The town's story: culture, heritage, markers, leaders' asks, timelapse

A town in Neighbors has a culture that drifts, leaders who ask it for
things, old buildings that gain charm, roadside markers for its firsts, and
a record of how it grew. Together they let a town change identity on its
own while the player stays in control: every big change is a yes or a no.

All of it runs once a game month, one part an hour from 14:00 to 18:00
(districts, then charm, markers, culture and asks, then the timelapse), plus
a quick check of answered asks every game hour. Each part is one pass over
the buildings or less: a few ms in the big test town (3,150 buildings). Numbers live in `Balance` under "Town heritage, culture and leader
requests".

## Culture and nicknames (`scripts/sim/culture.gd`)

- Six things a town can be known for: farming, industry, shops and Main
  Street, offices and banking, college, and history.
- The mix follows where people work, slowly (half the gap closes in two
  game years), plus a lean from the player's answers on the bell.
- It feeds back: owners on new lots lean toward the town's kind of
  building, and leaders of the town's kind are keener to build.
- A nickname is earned once the town has 150 people and one culture leads.
  A new one must lead the old one clearly before it takes over, and old
  nicknames are remembered ("Once the Corn Capital of Pike County, 2027 to
  2041").
- Real references: Elkhart, "RV Capital of the World"; Bedford, "Limestone
  Capital of the World"; Crawfordsville, "Athens of Indiana"; the state
  motto, "The Crossroads of America".

## Old buildings and historic districts (`scripts/sim/heritage.gd`)

- A building ages from when it went up, or from when it was last rebuilt as
  a different type. It is historic at 10 game years (the National Register
  uses 50 real years; a game evening covers decades).
- Charm grows from year 4 to year 25, more for Main Street blocks and old
  homes, less for offices. It lifts land value, and so property tax.
- A corner of town that is mostly historic is an eligible district, named
  for its street ("Main Street Historic District").
- The county historical society asks on the bell to protect it, the way an
  Indiana town council designates a local historic district (IC 36-7-11):
  - Yes: nothing there is torn down or built up, land is worth up to 15%
    more, visitors come (shop demand), the commission costs $1,500 a month,
    and a district plaque goes up.
  - No: owners rebuild as the town grows; the society may ask again in 5
    years.
- The player can protect or lift protection any time from a building's
  panel or the Town panel.
- Demolition delay: an owner who wants to tear down a charming building
  outside a district asks first. Yes: it comes down for the bigger
  building. No: the town buys a preservation easement and it stays for good.

## Historic markers (`scripts/sim/markers.gd`, `scripts/art/marker_view.gd`)

- Firsts get a roadside marker the month they happen: the founding, first
  home, store, factory, farm, Main Street block, school, bank, post office,
  park, college, hospital, railroad depot, stoplight and office building,
  and the oldest family business.
- They look like Indiana Historical Bureau markers: dark blue and gold, a
  crest on top, on a post in the grass strip, signed with the year.
- A farm kept by one family for a generation gets a Hoosier Homestead sign;
  a protected district gets a plaque.

## Leaders' asks (`scripts/sim/leader_asks.gd`)

At most one new ask a month, on the bell, never a pop-up. Each card says
what a yes and a no bring. Which leaders ask follows the culture, and each
answer leans it.

| Ask | Who | Real reference | Yes | No |
| --- | --- | --- | --- | --- |
| Tax abatement | A company | Indiana tax abatement, IC 6-1.1-12.1 | It builds its next step now; the town forgoes part of the new taxes for 5 years | It saves up |
| Pave a gravel road | A farm family | Community Crossings grants; spring weight limits | The town pays its 25% share | It stays gravel |
| Stoplight | The bank president or a Main Street owner | MUTCD chapter 4C signal warrants | The town pays $250,000; the main road flows | It stays a four-way stop |
| Fall festival | Main Street merchants | Special event permits | The town pays $15,000; shops do a month's extra business | No festival |
| Office park on farmland | A bank president | Brawn's identity-shift example | Frontage zoned for shops and offices; fields in the way go | It stays farm country; the town leans toward farming |

## Timelapse (`scripts/sim/timelapse.gd`, `scripts/ui/timelapse_view.gd`)

- Each month the record notes which roads, buildings and fields came and
  went, and the population and nickname. Nothing is copied twice.
- "Watch the town grow" in the Town panel plays it back in about 24
  seconds, drawn like a Sanborn fire insurance map: cream paper, yellow for
  wood-frame houses, pink for brick, blue for stone, grey for factories.
