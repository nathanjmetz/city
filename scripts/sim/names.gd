class_name Names
extends RefCounted
## Believable names for a Grant County, Indiana town (Brawn): every family,
## farm, shop, factory and company gets one, the way a real small town reads.
## Pure data and seeded picks; Families keeps who owns what.
##
## Real references:
##   - Surnames: the families of east-central Indiana (Grant, Madison,
##     Delaware and Howard counties; US Census surname counts and county
##     histories): the English and Scots-Irish majority, the North Carolina
##     Quaker families who settled Fairmount and Jonesboro, and the German
##     families of Marion's factory years.
##   - First names: the most common names in Indiana by birth decade (SSA),
##     1950s-60s for owners, 1985-95 for the next generation.
##   - Business names follow what's on real Indiana main streets and county
##     roads: the owner's name ("Overman Hardware", "Hayes Feed & Seed"),
##     the possessive for food and service ("Dot's Diner", "Kendall's
##     Tavern"), or a local place ("Mississinewa Pizza", "Gas Belt
##     Hardwoods"). No real chains or trademarks.

const SURNAMES := [
	"Miller", "Hayes", "Smith", "Johnson", "Davis", "Wilson", "Thomas", "Jones", "Brown", "Moore",
	"Overman", "Elliott", "Hollingsworth", "Bogue", "Coggeshall", "Hiatt", "Hunt", "Rush", "Jay", "Ratliff",
	"Harvey", "Pierce", "Lewis", "Wright", "Hill", "Hoover", "Stout", "Kelsay", "Kimes", "Leach",
	"Payne", "Shields", "Wolfe", "Zimmerman", "Fischer", "Bauer", "Kendall", "Lindley", "Cecil", "Jackson",
	"Seybold", "Bell", "Cox", "Crowe", "Cooper", "Gray", "Richardson", "Sims", "Young", "Boyd",
	"Carter", "Davidson", "Fowler", "Garr", "Hale", "Jenkins", "Kirkpatrick", "Lamb", "Martin", "Mason",
	"McCoy", "Nelson", "Osborne", "Parks", "Reece", "Sanders", "Swanson", "Tharp", "Underwood", "Vance",
	"Wells", "Whitson", "Yeager", "Ashby", "Barley", "Coahran", "Ellis", "Gunyon", "Haisley", "Harmon",
]
## Owners: Indiana's common names for babies born 1950-1965 (SSA).
const FIRST_OLD := [
	"Dale", "Gary", "Larry", "Roger", "Dennis", "Ron", "Jim", "Mike", "Steve", "Kevin",
	"Doug", "Randy", "Terry", "Wayne", "Darrell", "Mark", "Tim", "Jeff", "Greg", "Rick",
	"Linda", "Karen", "Debbie", "Brenda", "Pam", "Cindy", "Sharon", "Donna", "Teresa", "Diane",
	"Janet", "Carol", "Peggy", "Rhonda", "Vicki", "Connie", "Joyce", "Barb", "Kathy", "Sue",
]
## The next generation: Indiana's common names for babies born 1985-1995.
const FIRST_NEW := [
	"Tyler", "Kyle", "Cody", "Josh", "Brandon", "Justin", "Zach", "Travis", "Derek", "Matt",
	"Megan", "Ashley", "Brooke", "Kayla", "Amanda", "Lindsey", "Whitney", "Courtney", "Jenna", "Kelsey",
]
## Local places a business can take its name from instead of a family's.
const PLACES := [
	"Mississinewa", "Grant County", "Hoosier", "Prairie", "Gas Belt", "Riverside", "Four Corners", "Courthouse",
	"Back Creek", "Deer Creek", "Big Four", "Wabash Valley", "Oak Hill", "Heartland", "Country", "Crossroads",
]

## Lettering styles real small-town signs use, by the font that draws them
## (assets/brand/fonts/signs): painted slab serif on feed stores and
## lumber yards, the elegant serif on banks and funeral homes, condensed
## gothic on garages and machine shops, brush script on diners and
## bakeries, 1960s Franklin on grocers and drug stores, and the plain
## modern sans most businesses move to when they redo their look.
const STYLES := ["slab", "serif", "condensed", "script", "franklin", "gothic"]
## Real sign colour pairs, panel then letters: red and white, forest green
## and cream, navy and gold, black and gold, maroon and cream, white and
## blue, brown and cream, and blue and white.
const COLORS := [
	["#9b1c1c", "#f4f1ea"], ["#1d4d2c", "#efe6c8"], ["#1f3b6e", "#e8c25a"], ["#1e1e20", "#d9b44a"],
	["#6a1f2a", "#efe6c8"], ["#f2efe6", "#1f3b6e"], ["#5a3e2a", "#efe6c8"], ["#2a5b9a", "#f4f1ea"],
	["#f2efe6", "#9b1c1c"], ["#2d2f33", "#f4f1ea"],
]

## Main-street businesses, weighted by how often a real Indiana town of a
## few thousand has one: {trade, weight, style, names}. In a name, {S} is the
## brand (a surname or place) and {F} a first name. A possessive brand
## ("Miller's") reads {S's}.
const TRADES := [
	{"trade": "restaurant", "w": 10, "style": "script", "names": ["{S's} Diner", "{S's} Family Restaurant", "{F's} Cafe", "{S} Grill"]},
	{"trade": "tavern", "w": 6, "style": "condensed", "names": ["{S's} Tavern", "{S's} Pub", "{S} Bar & Grill"]},
	{"trade": "pizza", "w": 5, "style": "condensed", "names": ["{S's} Pizza", "{S} Pizza"]},
	{"trade": "hair", "w": 6, "style": "script", "names": ["{F's} Hair Studio", "{S's} Salon", "{F's} Beauty Shop"]},
	{"trade": "barber", "w": 3, "style": "serif", "names": ["{F's} Barber Shop", "{S's} Barber Shop"]},
	{"trade": "insurance", "office": true, "w": 5, "style": "serif", "names": ["{S} Insurance", "{S} Insurance Agency"]},
	{"trade": "hardware", "w": 3, "style": "slab", "names": ["{S} Hardware", "{S's} Hardware", "{S} Hardware & Supply"]},
	{"trade": "feed", "w": 2, "style": "slab", "names": ["{S} Feed & Seed", "{S} Farm Supply"]},
	{"trade": "pharmacy", "w": 2, "style": "franklin", "names": ["{S} Drugs", "{S} Pharmacy"]},
	{"trade": "grocery", "w": 2, "style": "franklin", "names": ["{S's} Market", "{S} Foods"]},
	{"trade": "auto", "w": 5, "style": "condensed", "names": ["{S} Auto Repair", "{S} Tire & Auto", "{S's} Garage"]},
	{"trade": "florist", "w": 2, "style": "script", "names": ["{S} Florist", "{F's} Flowers"]},
	{"trade": "bakery", "w": 2, "style": "script", "names": ["{S's} Bakery", "{S} Bakery & Donuts"]},
	{"trade": "furniture", "w": 2, "style": "serif", "names": ["{S} Furniture", "{S} Furniture & Appliance"]},
	{"trade": "funeral", "w": 2, "style": "serif", "names": ["{S} Funeral Home", "{S} & Sons Funeral Home"]},
	{"trade": "law", "office": true, "w": 2, "style": "serif", "names": ["{S} Law Office", "{S} & Associates"]},
	{"trade": "realty", "office": true, "w": 2, "style": "franklin", "names": ["{S} Realty", "{S} Real Estate"]},
	{"trade": "antiques", "w": 2, "style": "serif", "names": ["{S} Antiques", "{S} Antique Mall"]},
	{"trade": "clothing", "w": 2, "style": "serif", "names": ["{S's} Clothing", "{S} Western Wear"]},
	{"trade": "gifts", "w": 2, "style": "script", "names": ["{F's} Gifts", "{S} Gift Shop"]},
	{"trade": "appliance", "w": 1, "style": "franklin", "names": ["{S} Appliance & TV"]},
	{"trade": "accounting", "office": true, "w": 2, "style": "serif", "names": ["{S} Tax & Accounting"]},
]
## What each kind of trade is called in a sentence ("a diner").
const TRADE_WORD := {
	"restaurant": "restaurant", "tavern": "tavern", "pizza": "pizza place", "hair": "hair salon",
	"barber": "barber shop", "insurance": "insurance agency", "hardware": "hardware store",
	"feed": "feed store", "pharmacy": "drug store", "grocery": "grocery", "auto": "garage",
	"florist": "florist", "bakery": "bakery", "furniture": "furniture store", "funeral": "funeral home",
	"law": "law office", "realty": "real estate office", "antiques": "antique store",
	"clothing": "clothing store", "gifts": "gift shop", "appliance": "appliance store",
	"accounting": "accounting office",
	"mill": "grain mill", "sawmill": "sawmill", "refinery": "plastics plant", "metal": "machine shop",
	"general": "factory", "farm": "farm", "oil": "oil company", "ore": "stone quarry", "forest": "logging company",
}

## Factories by chain (Balance.FACTORY_CHAINS), farms and resource
## companies (Industry.KINDS), named the way the real ones are.
const KIND_NAMES := {
	"mill": {"style": "slab", "names": ["{S} Milling Co.", "{S} Grain & Feed", "{S} Mills"]},
	"sawmill": {"style": "slab", "names": ["{S} Lumber Co.", "{S} Hardwoods", "{S} Sawmill"]},
	"refinery": {"style": "gothic", "names": ["{S} Plastics", "{S} Polymers"]},
	"metal": {"style": "condensed", "names": ["{S} Machine & Tool", "{S} Steel Fabricators", "{S} Foundry"]},
	"general": {"style": "condensed", "names": ["{S} Manufacturing", "{S} Industries", "{S} Products Co."]},
	"farm": {"style": "slab", "names": ["{S} Farms", "{S} Family Farms", "{S} Bros. Farms", "{S} Acres"]},
	"oil": {"style": "condensed", "names": ["{S} Oil Co.", "{S} Oil & Gas", "{S} Energy"]},
	"ore": {"style": "condensed", "names": ["{S} Coal Co.", "{S} Mining Co.", "{S} Coal & Mining"]},
	"forest": {"style": "slab", "names": ["{S} Timber", "{S} Logging", "{S} Forest Products"]},
}


## A person's name from a seed: an owner, or the next generation.
static func person(seed: int, surname: String, young := false) -> String:
	var list: Array = FIRST_NEW if young else FIRST_OLD
	return "%s %s" % [list[absi(seed) % list.size()], surname]


static func surname(seed: int) -> String:
	return SURNAMES[absi(seed) % SURNAMES.size()]


static func place(seed: int) -> String:
	return PLACES[absi(seed) % PLACES.size()]


## A shop's trade, weighted like a real main street; `office` keeps to the
## trades that rent office space.
static func trade(seed: int, office := false) -> Dictionary:
	var total := 0
	for t in TRADES:
		if not office or t.get("office", false):
			total += int(t.w)
	var r := absi(seed) % total
	for t in TRADES:
		if not office or t.get("office", false):
			r -= int(t.w)
			if r < 0:
				return t
	return TRADES[0]


## Name patterns and default lettering for a trade or kind.
static func patterns(what: String) -> Dictionary:
	if KIND_NAMES.has(what):
		return KIND_NAMES[what]
	for t in TRADES:
		if t.trade == what:
			return t
	return KIND_NAMES.general


## Fills a pattern: {S} the brand, {S's} its possessive, {F} / {F's} the
## owner's first name.
static func fill(pattern: String, brand: String, first: String) -> String:
	return pattern.replace("{S's}", possessive(brand)).replace("{S}", brand) \
		.replace("{F's}", possessive(first)).replace("{F}", first)


## "Miller's", "Hayes'", and place names that don't take one ("Mississinewa").
static func possessive(word: String) -> String:
	if word in PLACES:
		return word
	return word + ("'" if word.ends_with("s") else "'s")


## What a business is, in a few words ("a hardware store").
static func trade_word(what: String) -> String:
	return TRADE_WORD.get(what, "business")
