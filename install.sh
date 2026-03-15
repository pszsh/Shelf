#!/bin/bash
set -e

APP_NAME="Shelf"

bash build.sh

killall "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "/Applications/$APP_NAME.app"
open "/Applications/$APP_NAME.app"
