#!/usr/bin/env bash
set -euo pipefail

APP="Sprint Tracker.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library Sources/SprintTracker/SprintTrackerApp.swift \
  -o "$APP/Contents/MacOS/SprintTracker" \
  -framework SwiftUI -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
echo "Built: $APP"
