#!/usr/bin/env python3
"""Optional browser QA for an already running Godot Web export.
Install playwright and its Chromium browser, or set CHROMIUM_PATH explicitly.
"""
import argparse
import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("--url", default="http://127.0.0.1:8080")
parser.add_argument("--screenshot", default="artifacts/menu.png")
parser.add_argument("--test", action="store_true")
parser.add_argument("--play", action="store_true")
args = parser.parse_args()
errors = []
with sync_playwright() as p:
    launch_args = {
        "headless": True,
        "args": ["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
    }
    if os.environ.get("CHROMIUM_PATH"):
        launch_args["executable_path"] = os.environ["CHROMIUM_PATH"]
    browser = p.chromium.launch(**launch_args)
    page = browser.new_page(viewport={"width": 1280, "height": 720})
    def log(message):
        print(message.type.upper(), message.text)
        if message.type == "error":
            errors.append(message.text)
    page.on("console", log)
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(args.url + ("?test=1" if args.test else ""), wait_until="networkidle")
    if args.test:
        try:
            page.wait_for_function("window.__testResult", timeout=120000)
            result = page.evaluate("window.__testResult")
            print(json.dumps(result, ensure_ascii=False, indent=2))
            if result.get("failed"):
                errors.append("Godot smoke tests failed")
        except Exception as e:
            errors.append(str(e))
    else:
        page.wait_for_timeout(3000)
    if args.play:
        page.mouse.click(260, 568)
        page.wait_for_timeout(2500)
    target = Path(args.screenshot)
    target.parent.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(target), timeout=90000)
    browser.close()
if errors:
    print("\nERRORS:", "\n".join(errors))
    raise SystemExit(1)
