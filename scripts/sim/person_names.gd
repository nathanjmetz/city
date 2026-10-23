class_name PersonNames
extends RefCounted
## Names for people and places in a Midwestern American town. Everything is
## drawn from the sim's own random numbers, so every copy of a city agrees.

const FIRST := [
	"James", "Mary", "Robert", "Linda", "John", "Patricia", "Michael", "Barbara", "David", "Susan",
	"William", "Karen", "Richard", "Nancy", "Thomas", "Lisa", "Mark", "Betty", "Daniel", "Sandra",
	"Paul", "Donna", "Steven", "Carol", "Kevin", "Sharon", "Brian", "Michelle", "Gary", "Laura",
	"Eric", "Amy", "Scott", "Angela", "Jeffrey", "Melissa", "Ryan", "Rebecca", "Jacob", "Emily",
	"Tyler", "Hannah", "Kyle", "Megan", "Dustin", "Ashley", "Travis", "Brittany", "Cody", "Kayla",
	"Erik", "Ingrid", "Lars", "Greta", "Hank", "Dolores", "Gene", "Arlene", "Dale", "Darlene",
	"Wayne", "Joyce", "Duane", "Marlene", "Roger", "Bonnie", "Dean", "Lois", "Glen", "Judy",
	"Noah", "Emma", "Liam", "Olivia", "Mason", "Ava", "Logan", "Harper", "Owen", "Avery",
	"Luke", "Ella", "Carter", "Addison", "Wyatt", "Brooklyn", "Hunter", "Paige", "Caleb", "Morgan",
]
const TREES := ["Maple", "Oak", "Elm", "Cedar", "Walnut", "Hickory", "Willow", "Birch", "Ash", "Linden",
	"Cottonwood", "Sycamore", "Chestnut", "Pine", "Spruce", "Poplar"]
const LOCAL := ["Main Street", "Prairie", "Heartland", "Riverside", "Lakeside", "Hometown", "Countryside",
	"Midway", "Crossroads", "Union", "Liberty", "Pioneer", "Harvest", "Meadow", "Sunrise", "Northside",
	"Westgate", "Old Town", "Twin Oaks", "Bluestem", "Railroad", "County Line", "Mill Creek", "Golden Grain"]
const SHOPS := ["Hardware", "Grocery", "Diner", "Pharmacy", "Bakery", "Barber Shop", "Hair Salon", "Florist",
	"Coffee House", "Pizza", "Bar & Grill", "Thrift Store", "Bookstore", "Insurance", "Auto Parts", "Tavern",
	"Café", "Gas & Go", "Furniture", "Appliance", "Feed & Seed", "Dental", "Bank", "Credit Union", "Laundromat",
	"Sporting Goods", "Pet Supply", "Tax Service", "Ice Cream", "Donuts", "Liquor", "Optometry", "Video Games",
	"Quilt Shop", "Bait & Tackle", "Market", "Supper Club", "Tire & Lube", "Real Estate", "Fitness"]
const WORKS := ["Manufacturing", "Machine Works", "Tool & Die", "Plastics", "Packaging", "Fabrication",
	"Foundry", "Millwork", "Printing", "Supply", "Industries", "Metal Works", "Logistics", "Components",
	"Castings", "Wire & Cable", "Foods", "Feeds", "Implement", "Trailer"]


static func first(rng: RandomNumberGenerator) -> String:
	return FIRST[rng.randi() % FIRST.size()]


## Surnames come from the town's own families (Names), so the people on
## the sidewalk share names with the signs on main street.
static func last(rng: RandomNumberGenerator) -> String:
	return Names.SURNAMES[rng.randi() % Names.SURNAMES.size()]


## A place name nobody in `taken` has yet. `family` names a home after the
## people living there.
static func place(zone: int, rng: RandomNumberGenerator, taken: Dictionary, family := "") -> String:
	for attempt in 40:
		var name := _place_once(zone, rng, family)
		if attempt > 20 and family != "":
			name = "%s %s home" % [first(rng), family]
		if not taken.has(name):
			return name
	var base := _place_once(zone, rng, family)
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


## A name nobody has yet for a farm ("farm"), a resource company (its
## industry kind: "oil", "ore", "forest") or a city service (its own name,
## such as "Fire station").
static func other(kind: String, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for attempt in 40:
		var name := _other_once(kind, rng)
		if not taken.has(name):
			return name
	var base := _other_once(kind, rng)
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


static func _other_once(kind: String, rng: RandomNumberGenerator) -> String:
	var local: String = LOCAL[rng.randi() % LOCAL.size()]
	var tree: String = TREES[rng.randi() % TREES.size()]
	match kind:
		"farm":
			match rng.randi() % 4:
				0: return "%s Family Farm" % last(rng)
				1: return "%s Acres" % tree
				2: return "%s Farm" % last(rng)
				_: return "%s Grain Farm" % local
		"oil":
			return ["%s Oil Co." % local, "%s Petroleum" % last(rng), "%s Energy" % local][rng.randi() % 3]
		"ore":
			return ["%s Mining" % last(rng), "%s Stone & Ore" % local, "%s Quarry" % tree][rng.randi() % 3]
		"forest":
			return ["%s Timber" % tree, "%s Lumber Co." % last(rng), "%s Woodlands" % local][rng.randi() % 3]
	return "%s %s" % [local, kind]


static func _place_once(zone: int, rng: RandomNumberGenerator, family: String) -> String:
	match zone:
		ZoneMap.Zone.RESIDENTIAL:
			return "%s home" % (family if family != "" else last(rng))
		ZoneMap.Zone.COMMERCIAL:
			var kind: String = SHOPS[rng.randi() % SHOPS.size()]
			match rng.randi() % 3:
				0: return "%s's %s" % [last(rng), kind]
				1: return "%s %s" % [LOCAL[rng.randi() % LOCAL.size()], kind]
				_: return "%s Street %s" % [TREES[rng.randi() % TREES.size()], kind]
		ZoneMap.Zone.INDUSTRIAL:
			var kind: String = WORKS[rng.randi() % WORKS.size()]
			match rng.randi() % 3:
				0: return "%s %s" % [last(rng), kind]
				1: return "%s %s Co." % [LOCAL[rng.randi() % LOCAL.size()], kind]
				_: return "%s & %s %s" % [last(rng), last(rng), kind]
	return "%s %s" % [LOCAL[rng.randi() % LOCAL.size()], "Lot"]
