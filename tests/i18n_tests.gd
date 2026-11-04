extends RefCounted
## The mod's two languages: same ids and values in both, every id the code asks for present, the language
## picked from the game's locale, and numbers written the way each language writes them.

const MOD := "res://mods-unpacked/Daneisra-BreachPilot/"
const I18n := preload(MOD + "core/i18n.gd")
const HackingAdvisor := preload(MOD + "features/hacking_advisor/hacking_advisor.gd")
const HackingAdvice := preload(MOD + "features/hacking_advisor/hacking_advice.gd")
const HackingUpgrades := preload(MOD + "features/hacking_advisor/hacking_upgrades.gd")
const ThreatObserver := preload(MOD + "features/threat_manager/threat_observer.gd")
const ID_PATTERN := "^[a-z_]+(\\.[a-z_0-9]+)+$"

var _check_call: Callable


func run(check: Callable) -> void:
	_check_call = check
	var before := I18n.forced
	_test_tables()
	_test_ids_in_code()
	_test_language()
	_test_formats()
	I18n.forced = before


func _check(condition: bool, label: String) -> void:
	_check_call.call(condition, label)


func _values(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for match: RegExMatch in RegEx.create_from_string("\\{([a-z_]+)\\}").search_all(text):
		if not found.has(match.get_string(1)):
			found.append(match.get_string(1))
	found.sort()
	return found


func _test_tables() -> void:
	var english: Dictionary = I18n.TABLES.en
	for language: String in I18n.TABLES:
		var table: Dictionary = I18n.TABLES[language]
		var missing := english.keys().filter(func(id: String) -> bool: return not table.has(id))
		var extra := table.keys().filter(func(id: String) -> bool: return not english.has(id))
		_check(missing.is_empty() and extra.is_empty(), "%s has exactly the English ids: missing %s, extra %s" % [language, missing, extra])
		var mismatched := PackedStringArray()
		var empty := PackedStringArray()
		for id: String in english:
			if table.has(id) and _values(table[id]) != _values(english[id]):
				mismatched.append(id)
			if table.has(id) and str(table[id]).strip_edges() == "" and not id.begins_with("fmt."):
				empty.append(id)
		_check(mismatched.is_empty(), "%s fills the same values as English: %s" % [language, ", ".join(mismatched)])
		_check(empty.is_empty(), "%s has no empty text: %s" % [language, ", ".join(empty)])


## Every id written in the code, plus the families built from a name, exists in every table.
func _test_ids_in_code() -> void:
	var asked := {}
	var id := RegEx.create_from_string(ID_PATTERN)
	var literal := RegEx.create_from_string("\"([^\"]*)\"")
	var counted := RegEx.create_from_string("t_count\\(\"([^\"]+)\"")
	var variant := RegEx.create_from_string("vowel_variant\\(\"([^\"]+)\"")
	var prefixes := {}
	for known: String in I18n.TABLES.en:
		prefixes[known.get_slice(".", 0)] = true
	for path: String in _sources(MOD):
		if path.get_file().begins_with("strings_"):
			continue
		var source := FileAccess.get_file_as_string(path)
		for line: String in source.split("\n"):
			if not line.contains("I18n.") and not line.contains("\"block.") and not line.contains("insufficient."):
				continue
			for found: RegExMatch in literal.search_all(line):
				var text := found.get_string(1)
				if id.search(text) != null and prefixes.has(text.get_slice(".", 0)):
					asked[text] = true
		for found: RegExMatch in counted.search_all(source):
			asked[found.get_string(1) + ".one"] = true
			asked[found.get_string(1) + ".other"] = true
			asked.erase(found.get_string(1))
		for found: RegExMatch in variant.search_all(source):
			asked[found.get_string(1) + ".vowel"] = true
	for name: String in ThreatObserver.BLOCK_TEXTS:
		asked["block.%s" % name] = true
	for name: String in HackingAdvisor.ERROR_TEXTS:
		asked["error.%s" % name] = true
	for level: int in 3:
		asked["reliability.%d" % level] = true
	for name: String in HackingUpgrades.COST_NAMES:
		asked["cost.%s.one" % name] = true
		asked["cost.%s.other" % name] = true
	for name: String in HackingUpgrades.FOLLOWED:
		asked["effect.%s" % name] = true
	for language: String in I18n.TABLES:
		var missing := asked.keys().filter(func(wanted: String) -> bool: return not I18n.TABLES[language].has(wanted))
		_check(missing.is_empty(), "every id the code asks for is in %s: %s" % [language, missing])
	_check(asked.size() > 100, "the scan finds the ids: %d" % asked.size())
	var unused := I18n.TABLES.en.keys().filter(func(known: String) -> bool: return not asked.has(known) and not known.begins_with("fmt."))
	_check(unused.is_empty(), "no text is left unused: %s" % [unused])


func _sources(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(_sources(folder.path_join(sub)))
	return found


func _test_language() -> void:
	_check(I18n.language_of("fr") == "fr" and I18n.language_of("fr_FR") == "fr" and I18n.language_of("fr-CA") == "fr" and I18n.language_of("FR_be") == "fr", "French in every French locale")
	_check(I18n.language_of("en") == "en" and I18n.language_of("en_US") == "en", "English in English")
	_check(I18n.language_of("de_DE") == "en" and I18n.language_of("zh_Hans") == "en", "English for a language without a table")
	_check(I18n.language_of("") == "en" and I18n.language_of("_") == "en", "and when no locale can be read")
	I18n.forced = ""
	_check(I18n.language() == I18n.language_of(TranslationServer.get_locale()), "outside the tests, the game's locale decides")
	I18n.forced = "en"
	_check(I18n.t("panel.close") == "Close" and I18n.t("state.active") == "Auto: on", "English texts")
	I18n.forced = "fr"
	_check(I18n.t("panel.close") == "Fermer" and I18n.t("state.active") == "Auto : actif", "French texts")
	_check(I18n.t("card.keep", {"goal": "XP"}) == "Gardez votre branchement : c'est déjà le meilleur pour XP.", "values are filled in")
	_check(I18n.t("no.such.text") == "no.such.text", "an unknown id shows itself, which the table tests forbid")


func _test_formats() -> void:
	I18n.forced = "fr"
	_check(I18n.percent(99) == "99 %" and I18n.percent(2, true) == "+2 %" and I18n.percent(-21, true) == "-21 %", "French percentages")
	_check(HackingUpgrades.grouped(26113829114.0) == "26 113 829 114" and I18n.group_digits("-1234") == "-1 234", "French digit groups")
	_check(I18n.join_and(PackedStringArray(["A", "B", "C"])) == "A, B et C" and I18n.join_and(PackedStringArray(["A"])) == "A", "French lists")
	_check(I18n.t_count("card.more_trials", 1) == "1 autre piste dans le détail des calculs." and I18n.t_count("card.more_trials", 3).begins_with("3 autres pistes"), "French counts")
	_check(I18n.t(I18n.vowel_variant("step.unplug", "Anonymous"), {"stream": "Payload", "target": "Anonymous"}) == "Payload : débrancher d'Anonymous", "French elides before a vowel")
	_check(I18n.t(I18n.vowel_variant("step.unplug", "Gouvernement"), {"stream": "Payload", "target": "Gouvernement"}) == "Payload : débrancher de Gouvernement", "and not before a consonant")
	_check(HackingUpgrades.cost_text(1.0, "hack_points") == "1 point de piratage" and HackingUpgrades.cost_text(3.0, "hack_points") == "3 points de piratage", "French costs")
	I18n.forced = "en"
	_check(I18n.percent(99) == "99%" and I18n.percent(2, true) == "+2%" and HackingAdvice.percent(120.0, 100.0) == "+20%", "English percentages")
	_check(HackingUpgrades.grouped(26113829114.0) == "26,113,829,114" and HackingUpgrades.grouped(4603854016022367232.0) == "4.60e18", "English digit groups")
	_check(I18n.join_and(PackedStringArray(["A", "B"])) == "A and B", "English lists")
	_check(I18n.t(I18n.vowel_variant("step.unplug", "Anonymous"), {"stream": "Payload", "target": "Anonymous"}) == "Payload: disconnect from Anonymous", "English ignores elision")
	_check(HackingUpgrades.cost_text(1.0, "hack_points") == "1 hack point" and HackingUpgrades.cost_text(2.0, "token") == "2 tokens", "English costs")
	_check(HackingUpgrades.downsides({"breach_damage_multiplier": {"ratio": 0.6}}) == PackedStringArray(["Payload damage -40%"]), "a purchase's loss in English")
