"""Sets the tags of an existing Workshop item through the official Steamworks DLL (steam_api64.dll).

Uses the Steam client that is already running and logged in: no password, no token is read or stored.
Only SetItemTags is called on the update handle, so content, preview, title, description and
visibility are left as they are. The change note is NULL (no change note).

Dry run by default: the update handle is prepared and the tags are checked locally, but nothing is
submitted. Pass --submit to send the update.

Adapted from Research Freedom's tool for BreachPilot's own item. Run from a working directory that holds
steam_appid.txt (3606890), with the game closed and the Steam client running:
    python set_workshop_tags.py --dll "<game>/steam_api64.dll" [--submit]
"""
import argparse
import ctypes
import sys
import time

APP_ID = 3606890
PUBLISHED_FILE_ID = 3833859813  # BreachPilot
RESEARCH_FREEDOM_ID = 3833196182  # never this one
TAGS = ["QOL"]
INVALID_HANDLE = 0xFFFFFFFFFFFFFFFF
SUBMIT_ITEM_UPDATE_RESULT = 3404  # k_iSteamUGCCallbacks (3400) + 4
RESULT_NAMES = {1: "OK", 2: "Fail", 8: "InvalidParam", 9: "FileNotFound", 15: "AccessDenied", 33: "LockingFailed", 25: "LimitExceeded"}


class SteamParamStringArray(ctypes.Structure):
	_fields_ = [("m_ppStrings", ctypes.POINTER(ctypes.c_char_p)), ("m_nNumStrings", ctypes.c_int32)]


class SubmitItemUpdateResult(ctypes.Structure):
	# Steamworks headers use 8-byte packing on 64-bit Windows: 4 + 1 + 3 (padding) + 8 = 16 bytes.
	_fields_ = [("m_eResult", ctypes.c_int32), ("m_bUserNeedsToAcceptWorkshopLegalAgreement", ctypes.c_bool),
		("m_nPublishedFileId", ctypes.c_uint64)]


def bind(dll):
	signatures = {
		"SteamAPI_InitFlat": (ctypes.c_int, [ctypes.c_char_p]),
		"SteamAPI_Shutdown": (None, []),
		"SteamAPI_RunCallbacks": (None, []),
		"SteamAPI_SteamUGC_v021": (ctypes.c_void_p, []),
		"SteamAPI_SteamUtils_v010": (ctypes.c_void_p, []),
		"SteamAPI_ISteamUGC_StartItemUpdate": (ctypes.c_uint64, [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint64]),
		"SteamAPI_ISteamUGC_SetItemTags": (ctypes.c_bool, [ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(SteamParamStringArray), ctypes.c_bool]),
		"SteamAPI_ISteamUGC_SubmitItemUpdate": (ctypes.c_uint64, [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_char_p]),
		"SteamAPI_ISteamUtils_IsAPICallCompleted": (ctypes.c_bool, [ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_bool)]),
		"SteamAPI_ISteamUtils_GetAPICallResult": (ctypes.c_bool, [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_bool)]),
	}
	for name, (restype, argtypes) in signatures.items():
		function = getattr(dll, name)
		function.restype = restype
		function.argtypes = argtypes
	return dll


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--dll", required=True)
	parser.add_argument("--submit", action="store_true", help="send the update (default: dry run)")
	args = parser.parse_args()
	if PUBLISHED_FILE_ID == RESEARCH_FREEDOM_ID:
		print("This is Research Freedom's item id")
		return 1

	api = bind(ctypes.CDLL(args.dll))
	error = ctypes.create_string_buffer(4096)  # SteamErrMsg is char[1024]; a larger buffer is harmless
	init = api.SteamAPI_InitFlat(error)
	if init != 0:
		print(f"SteamAPI_InitFlat failed ({init}): {error.value.decode(errors='replace')}")
		return 1
	try:
		ugc = api.SteamAPI_SteamUGC_v021()
		utils = api.SteamAPI_SteamUtils_v010()
		if not ugc or not utils:
			print("Steam interfaces not available")
			return 1
		handle = api.SteamAPI_ISteamUGC_StartItemUpdate(ugc, APP_ID, PUBLISHED_FILE_ID)
		if handle == INVALID_HANDLE:
			print("StartItemUpdate returned an invalid handle")
			return 1
		strings = (ctypes.c_char_p * len(TAGS))(*[tag.encode("ascii") for tag in TAGS])
		tags = SteamParamStringArray(strings, len(TAGS))
		if not api.SteamAPI_ISteamUGC_SetItemTags(ugc, handle, ctypes.byref(tags), False):
			print("SetItemTags refused the tags")
			return 1
		print(f"Prepared: item {PUBLISHED_FILE_ID}, app {APP_ID}, tags {TAGS}; only the tags would change.")
		if not args.submit:
			print("Dry run: nothing submitted.")
			return 0

		call = api.SteamAPI_ISteamUGC_SubmitItemUpdate(ugc, handle, None)
		if call == 0:
			print("SubmitItemUpdate returned an invalid call")
			return 1
		failed = ctypes.c_bool(False)
		deadline = time.time() + 60
		while not api.SteamAPI_ISteamUtils_IsAPICallCompleted(utils, call, ctypes.byref(failed)):
			if time.time() > deadline:
				print("No answer from Steam within 60 s: check the item page before trying again.")
				return 1
			api.SteamAPI_RunCallbacks()
			time.sleep(0.2)
		result = SubmitItemUpdateResult()
		if not api.SteamAPI_ISteamUtils_GetAPICallResult(utils, call, ctypes.byref(result), ctypes.sizeof(result), SUBMIT_ITEM_UPDATE_RESULT, ctypes.byref(failed)) or failed.value:
			print("Could not read the result: check the item page.")
			return 1
		name = RESULT_NAMES.get(result.m_eResult, str(result.m_eResult))
		print(f"SubmitItemUpdate final result from Steam: {name} ({result.m_eResult}); item {result.m_nPublishedFileId}; "
			f"legal agreement needed: {result.m_bUserNeedsToAcceptWorkshopLegalAgreement}")
		if result.m_nPublishedFileId not in (0, PUBLISHED_FILE_ID):
			print("Unexpected item id in the result: check the item page.")
			return 1
		return 0 if result.m_eResult == 1 else 1
	finally:
		api.SteamAPI_Shutdown()


if __name__ == "__main__":
	sys.exit(main())
