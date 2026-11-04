extends RefCounted
## The mod's own words, in the language the game shows. The game translates its texts through Godot's
## TranslationServer, so its locale is the game's language: names of nodes and resources, which come from
## the game's tables, already follow it. A language without a table falls back to English.
##
## Texts are looked up by a stable id and filled with named values: {gain}, {target}. A text missing in
## one language comes from English; one missing everywhere shows its id, which the tests forbid.
## To add a language: a table next to strings_en.gd with the same ids and values, and one line in TABLES.

const StringsEn := preload("strings_en.gd")
const StringsFr := preload("strings_fr.gd")

const FALLBACK := "en"
const TABLES := {
	"en": StringsEn.TEXTS,
	"fr": StringsFr.TEXTS,
}

## Set by the tests to pick a language; empty in the game, where the game's locale decides.
static var forced := ""


## "fr" for fr, fr_FR or fr_CA; English for a language the mod has no table for, or no locale at all.
static func language() -> String:
	if forced != "":
		return forced
	return language_of(TranslationServer.get_locale())


static func language_of(locale: String) -> String:
	var code := locale.get_slice("_", 0).get_slice("-", 0).to_lower()
	return code if TABLES.has(code) else FALLBACK


static func t(id: String, values: Dictionary = {}) -> String:
	var table: Dictionary = TABLES[language()]
	var text: String = table.get(id, TABLES[FALLBACK].get(id, id))
	return text.format(values) if not values.is_empty() else text


## The text for a count: id.one for 1, id.other otherwise. {count} is filled in.
static func t_count(id: String, count: int, values: Dictionary = {}) -> String:
	var filled := values.duplicate()
	filled.count = count
	return t("%s.%s" % [id, "one" if count == 1 else "other"], filled)


## Groups of three digits, with the language's separator: 26 113 829 or 26,113,829.
static func group_digits(digits: String) -> String:
	var separator := t("fmt.thousands")
	var sign := ""
	if digits.begins_with("-"):
		sign = "-"
		digits = digits.substr(1)
	var text := ""
	while digits.length() > 3:
		text = separator + digits.right(3) + text
		digits = digits.left(digits.length() - 3)
	return sign + digits + text


## A whole percentage as the language writes it: 99 % or 99%, +2 % or +2%.
static func percent(value: int, signed: bool = false) -> String:
	return t("fmt.percent", {"value": ("%+d" if signed else "%d") % value})


## A list read as a sentence: A, B and C.
static func join_and(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return t("fmt.and", {"first": ", ".join(items.slice(0, items.size() - 1)), "last": items[-1]})


## French elides before a vowel: "d'Anonymous" but "de Gouvernement". Other languages ignore it.
static func vowel_variant(id: String, word: String) -> String:
	var vowel := "AEIOUYÉÈÊÀÂÎÔaeiouyéèêàâîô".contains(word.left(1)) and word != ""
	return "%s.vowel" % id if vowel else id
