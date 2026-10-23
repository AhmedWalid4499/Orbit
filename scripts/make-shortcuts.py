#!/usr/bin/env python3
"""Builds the two Orbit shortcuts shared with the iPhone app and signs them for anyone to import.

Each one takes the automation's Shortcut Input and passes its fields to an Orbit action, so the user's
automation only has to run the shortcut. Output: iOS/Support/Shortcuts/*.shortcut (bundled in the app).
Run on the Mac: python3 scripts/make-shortcuts.py
"""
import os, shutil, plistlib, subprocess, sys, tempfile, uuid

BUNDLE, TEAM = "com.ahmedwalid.orbit", "Y2K55S3UA9"
OUT = os.path.join(os.path.dirname(__file__), "..", "iOS", "Support", "Shortcuts")

def input_property(name):
    """Shortcut Input › <property>, as a text field value."""
    return {
        "Value": {
            "string": "￼",
            "attachmentsByRange": {"{0, 1}": {
                "Type": "ExtensionInput",
                "Aggrandizements": [{"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}],
            }},
        },
        "WFSerializationType": "WFTextTokenString",
    }

def whole_input():
    """The whole Shortcut Input, as a text field value."""
    return {
        "Value": {"string": "\ufffc", "attachmentsByRange": {"{0, 1}": {"Type": "ExtensionInput"}}},
        "WFSerializationType": "WFTextTokenString",
    }

def action(intent, params):
    p = {"AppIntentDescriptor": {"AppIntentIdentifier": intent, "BundleIdentifier": BUNDLE, "Name": "Orbit", "TeamIdentifier": TEAM},
         "UUID": str(uuid.uuid4()).upper()}
    p.update(params)
    return {"WFWorkflowActionIdentifier": f"{BUNDLE}.{intent}", "WFWorkflowActionParameters": p}

def shortcut(actions, glyph, color, input_class):
    return {
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "3600.0.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": glyph, "WFWorkflowIconStartColor": color},
        "WFWorkflowImportQuestions": [],
        # The trigger's own type first, so Shortcuts keeps its properties (Sender, Merchant…) instead of turning it into text.
        "WFWorkflowInputContentItemClasses": [input_class, "WFStringContentItem"],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFQuickActionSurfaces": [],
    }

SHORTCUTS = {
    "Orbit Bank Message": shortcut([action("LogBankMessageIntent", {
        "message": input_property("Content"), "sender": input_property("Sender"), "fullInput": whole_input()})], 59511, 4282601983, "WFMessageContentItem"),
    "Orbit Card Payment": shortcut([action("LogCardPaymentIntent", {
        "amount": input_property("Amount"), "merchant": input_property("Merchant"), "card": input_property("Card or Pass")})], 59446, 431817727, "WFWalletTransactionContentItem"),
}

os.makedirs(OUT, exist_ok=True)
# shortcuts(1) can only read and write where the user can (not a private temp folder or the iCloud Desktop).
with tempfile.TemporaryDirectory(dir=os.path.expanduser("~/Library/Caches")) as tmp:
    for name, data in SHORTCUTS.items():
        raw = os.path.join(tmp, name + ".shortcut")
        with open(raw, "wb") as f: plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
        signed = os.path.join(tmp, name + " signed.shortcut")
        r = subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", raw, "--output", signed], capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(signed):
            sys.exit(f"Signing {name} failed: {r.stderr or r.stdout}")
        out = os.path.join(OUT, name + ".shortcut")
        shutil.copyfile(signed, out)
        print("signed", out)
