class_name Words
extends RefCounted
## Plain English for text built from names: "a" or "an", plurals, and a
## name's capitals in the middle of a sentence. One place for the rules, so a
## hint never reads "You have no county fairgroundses yet", "no rv plants" or
## "make it a Avenue" (the critic's text dump, 2026-10-27).
## Names are written in sentence case ("Water tower", "RV plant", "Farm
## Credit office"); these keep a name's own capitals where they mean something.

## Words that are already plural, or the same either way.
const SAME := ["fairgrounds", "grounds", "series", "species", "sheep", "deer", "fish", "cattle",
	"headquarters", "works", "barracks", "people", "aircraft", "logs", "goods", "news", "swine"]
## Plurals that don't follow the rules.
const IRREGULAR := {"person": "people", "man": "men", "woman": "women", "child": "children",
	"foot": "feet", "tooth": "teeth", "mouse": "mice", "goose": "geese", "ox": "oxen",
	"leaf": "leaves", "shelf": "shelves", "half": "halves", "calf": "calves", "loaf": "loaves",
	"life": "lives", "knife": "knives", "wife": "wives", "wolf": "wolves",
	"hero": "heroes", "potato": "potatoes", "tomato": "tomatoes", "echo": "echoes"}
## Starts that sound like a consonant though they're spelled with a vowel
## ("a university", "a one-way street", "a utility").
const SAID_LIKE_Y_OR_W := ["one", "once", "uni", "use", "usu", "uti", "ura", "ure", "euro", "eu", "ewe", "u-"]
## Starts with a silent h ("an hour").
const SILENT_H := ["hour", "honest", "honor", "heir", "herb"]
## Letters whose names start with a vowel sound, for initials ("an RV", "an ATM").
const VOWEL_LETTERS := "AEFHILMNORSX"
## Where a name's head noun ends: "Avenue, center turn lane", "Street with
## bike lanes" pluralize to "Avenues, ..." and "Streets with ...".
const HEAD_ENDS := [", ", " with ", " for ", " of ", " on ", " in "]


## "a" or "an" before `phrase`, by how its first word sounds:
## "an avenue", "a university", "an RV plant", "a one-way street".
static func a(phrase: String) -> String:
	return ("an " if wants_an(phrase) else "a ") + phrase


## The same as a(), starting a sentence: "An avenue".
static func a_first(phrase: String) -> String:
	return first_up(a(phrase))


## True when `phrase` takes "an".
static func wants_an(phrase: String) -> bool:
	var word := phrase.strip_edges().get_slice(" ", 0)
	if word == "":
		return false
	var c := word.substr(0, 1)
	# Numbers by how they're said: "an 8", "an 11", "an 18,000", "a 110".
	if c.is_valid_int():
		return c == "8" or word.get_slice("-", 0).get_slice(",", 0).get_slice(".", 0) in ["11", "18"]
	var head := word.get_slice("-", 0)
	# Initials, or one capital letter before a hyphen, are said by their
	# letters: "an RV", "an S-curve", "a T-junction", "a U-turn".
	if _initials(head) or (word.contains("-") and head.length() == 1 and head != head.to_lower()):
		return VOWEL_LETTERS.contains(c)
	var low := word.to_lower()
	for s in SILENT_H:
		if low.begins_with(s):
			return true
	for s in SAID_LIKE_Y_OR_W:
		if low.begins_with(s) and not (s == "uni" and (low.begins_with("unin") or low.begins_with("unim"))):
			return false
	return "aeiou".contains(low.substr(0, 1))


## The plural of a name or noun, keeping its capitals: "county fairgrounds"
## stays, "RV plant" is "RV plants", "community library" is "community
## libraries", "bus" is "buses", "Avenue with bike lanes" is "Avenues with
## bike lanes".
static func plural(noun: String) -> String:
	var cut := noun.length()
	for e in HEAD_ENDS:
		var i := noun.find(e)
		if i > 0 and i < cut:
			cut = i
	var head := noun.substr(0, cut)
	var tail := noun.substr(cut)
	var space := head.rfind(" ")
	var before := head.substr(0, space + 1)
	var word := head.substr(space + 1)
	return before + _plural_word(word) + tail


## "1 well pad", "3 well pads".
static func count(n: int, noun: String) -> String:
	return "%d %s" % [n, noun if n == 1 else plural(noun)]


## A name as it reads mid-sentence: "Water tower" becomes "water tower", but
## initials and proper names keep their capitals ("RV plant", "ATM
## vestibule", "Farm Credit office").
static func mid(name: String) -> String:
	var words := name.split(" ")
	if words.is_empty() or words[0] == "":
		return name
	if _initials(words[0].get_slice("-", 0)):
		return name
	if words.size() > 1 and words[1] != "" and words[1].substr(0, 1) != words[1].substr(0, 1).to_lower():
		return name
	return words[0].substr(0, 1).to_lower() + name.substr(1)


## Only the first letter up, the rest as written ("crude oil" is "Crude oil";
## Godot's capitalize() would make it "Crude Oil").
static func first_up(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


static func _plural_word(word: String) -> String:
	if word == "":
		return word
	if _initials(word):
		return word + "s"
	var low := word.to_lower()
	var out := ""
	if low in SAME or low.ends_with("grounds"):
		return word
	# Already plural: "teller lanes", "bike lanes" (but "bus", "class",
	# "campus", "gas" and "basis" take "es").
	if low.ends_with("s") and not (low.ends_with("ss") or low.ends_with("us") or low.ends_with("is") or low.ends_with("as")):
		return word
	if IRREGULAR.has(low):
		out = IRREGULAR[low]
	elif low.ends_with("s") or low.ends_with("x") or low.ends_with("z") or low.ends_with("ch") or low.ends_with("sh"):
		out = low + "es"
	elif low.ends_with("y") and low.length() > 1 and not "aeiou".contains(low.substr(low.length() - 2, 1)):
		out = low.substr(0, low.length() - 1) + "ies"
	else:
		out = low + "s"
	# Keep the word's own first capital ("Avenue" -> "Avenues").
	return (out.substr(0, 1).to_upper() + out.substr(1)) if word.substr(0, 1) != low.substr(0, 1) else out


## Initials like "RV", "ATM" or "US": two or more letters, all capitals.
static func _initials(word: String) -> bool:
	var letters := word.rstrip(".,:;")
	if letters.ends_with("s"):
		letters = letters.substr(0, letters.length() - 1)  # "RVs"
	return letters.length() >= 2 and letters == letters.to_upper() and letters != letters.to_lower()
