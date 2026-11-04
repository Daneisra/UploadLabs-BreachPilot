extends RefCounted
## The inventory stays bounded, hides what it must not read, and only reads.

const AdvisorInventory := preload("res://mods-unpacked/Daneisra-BreachPilot/features/hacking_advisor/advisor_inventory.gd")


class FakeContainer extends Node:
	var resource := "hack_power"
	var count := 12.5
	var inputs: Array = []


class FakeWindow extends Node:
	var window := "breach_corps"
	var token := "SECRET-VALUE"
	var data := {"level": 3, "account_name": "SECRET-VALUE"}
	var containers: Array = []
	var called := false

	func level_up(_times: int) -> void:
		called = true


class FakeOther extends Node:
	var window := "collector"
	var containers: Array = []


class FakeDesktop extends Node:
	var windows: Node


class FakeAutoload extends Node:
	var breach_bonus := 1.5
	var unrelated := 7
	var account_token := "SECRET-VALUE"
	var mixed := {"crit_chance": 0.1, "gold": 3, "save_path": "SECRET-VALUE"}


class FakeAccount extends Node:
	var breach_token := "SECRET-VALUE"


func run(check: Callable) -> void:
	var inventory := AdvisorInventory.new()
	check.call(inventory.is_sensitive("account_name") and inventory.is_sensitive("Save_Slot") and inventory.is_sensitive("files"), "inventory hides account and save names")
	check.call(not inventory.is_sensitive("breach_damage") and not inventory.is_sensitive("id"), "inventory keeps game names")
	check.call(inventory.describe(1.23456) == "1.2346" and inventory.describe(null) == "null", "inventory describes plain values")

	var deep: Variant = 1
	for _i in AdvisorInventory.MAX_DEPTH + 3:
		deep = [deep]
	check.call(inventory.describe(deep).contains("[1]"), "inventory stops at its depth limit")
	var long_list := range(AdvisorInventory.MAX_ITEMS + 5)
	check.call(inventory.describe(long_list).contains("+5"), "inventory stops at its item limit")

	var root := Node.new()
	root.name = "root"
	var autoload := FakeAutoload.new()
	autoload.name = "Attributes"
	root.add_child(autoload)
	var account := FakeAccount.new()
	account.name = "Account"
	root.add_child(account)
	var desktop := FakeDesktop.new()
	desktop.windows = Node.new()
	for i in 2:
		var window := FakeWindow.new()
		window.name = "Breach%d" % i
		var container := FakeContainer.new()
		container.name = "Input"
		window.add_child(container)
		window.containers = [container]
		desktop.windows.add_child(window)
	for i in 3:
		var other := FakeOther.new()
		other.name = "Other%d" % i
		desktop.windows.add_child(other)

	var text := "\n".join(inventory.snapshot(root, desktop))
	check.call(not text.contains("SECRET-VALUE"), "inventory never prints a hidden value")
	check.call(text.contains("autoload Account skipped"), "inventory skips the account autoload")
	check.call(text.contains("Attributes.breach_bonus=1.5") and text.contains("crit_chance:0.1"), "inventory keeps hacking values")
	check.call(not text.contains("gold") and not text.contains("unrelated=7"), "inventory leaves out unrelated values")
	check.call(text.contains("name=Breach0") and text.contains("name=Breach1"), "inventory details every hacking window")
	check.call(text.contains("name=Other0") and not text.contains("name=Other1"), "inventory details one window of any other type")
	check.call(text.contains("of=Breach1") and text.contains("resource=hack_power"), "inventory details containers")
	check.call(text.contains("collector:3"), "inventory counts windows by type")
	check.call(not desktop.windows.get_child(0).called, "inventory calls no game method")
	check.call(inventory.snapshot(root, null).has("desktop none"), "inventory survives without a desktop")

	var many := PackedStringArray()
	root.free()
	desktop.windows.free()
	desktop.free()
	many.resize(AdvisorInventory.MAX_LINES + 10)
	check.call(inventory._finished(many).size() == AdvisorInventory.MAX_LINES + 1, "inventory stops at its line limit")
