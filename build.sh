#!/bin/zsh
set -euo pipefail
here="${0:A:h}"
source "$here/scripts/identity.sh"
dest="${INSTALL_DIR:-$HOME/Applications}"
app="$dest/$APP_NAME.app"
last="$here/build/.last-identity"

"$here/scripts/build-app.sh" >/dev/null

prev() { [[ -f "$last" ]] && sed -n "s/^$1=//p" "$last" | head -1 || true; }
prev_app="$(prev app)"
prev_exe="$(prev executable)"
prev_cfg="$(prev config)"

if [[ -n "$prev_app" && "$prev_app" != "$app" && -d "$prev_app" ]]; then
  [[ -n "$prev_exe" ]] && "$prev_app/Contents/MacOS/$prev_exe" --login-off >/dev/null 2>&1 || true
  [[ -n "$prev_exe" ]] && pkill -x "$prev_exe" >/dev/null 2>&1 || true
  rm -rf "$prev_app"
fi
if [[ -n "$prev_cfg" && "$prev_cfg" != "$CONFIG_DIR_NAME" && -d "$HOME/.config/$prev_cfg" && ! -e "$HOME/.config/$CONFIG_DIR_NAME" ]]; then
  ditto "$HOME/.config/$prev_cfg" "$HOME/.config/$CONFIG_DIR_NAME"
  chmod 700 "$HOME/.config/$CONFIG_DIR_NAME"
  find "$HOME/.config/$CONFIG_DIR_NAME" -type f -exec chmod 600 {} +
  print "Copied settings from ~/.config/$prev_cfg to ~/.config/$CONFIG_DIR_NAME"
fi

if [[ -d "$app" ]]; then
  old_id="$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
  old_exe="$(defaults read "$app/Contents/Info.plist" CFBundleExecutable 2>/dev/null || true)"
  if [[ -n "$old_id" && "$old_id" != "$BUNDLE_ID" && -n "$old_exe" ]]; then
    "$app/Contents/MacOS/$old_exe" --login-off >/dev/null 2>&1 || true
  fi
  [[ -n "$old_exe" && "$old_exe" != "$EXECUTABLE" ]] && pkill -x "$old_exe" >/dev/null 2>&1 || true
fi
pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
sleep 0.5
mkdir -p "$dest"
rm -rf "$app"
ditto "$here/build/$APP_NAME.app" "$app"

defaults write pbs NSServicesStatus -dict-add '"(null) - Fix text - runWorkflowAsService"' \
  '{enabled_context_menu = 1; enabled_services_menu = 1; presentation_modes = {ContextMenu = 1; ServicesMenu = 1;};}'
mkdir -p "$HOME/Library/Services"
[[ -d "$HOME/Library/Services/Fix text.workflow" ]] || cp -R "$here/Resources/Fix text.workflow" "$HOME/Library/Services/"
wf="$HOME/Library/Services/Fix text.workflow/Contents/document.wflow"
if [[ -f "$wf" ]]; then
  plutil -replace actions.0.action.ActionParameters.COMMAND_STRING -string "$app/Contents/Resources/fixer" "$wf"
  /System/Library/CoreServices/pbs -update
fi

print -l "app=$app" "executable=$EXECUTABLE" "config=$CONFIG_DIR_NAME" "bundle=$BUNDLE_ID" > "$last"
"$app/Contents/MacOS/$EXECUTABLE" --login-on >/dev/null || true
open -g "$app" --args --background
print -r -- "installed: $app"
