#!/bin/bash
# Install Finder integration for herdr.
#
# Two entries, both ending up in the same place — herdr opened in the selected
# folder (or a selected file's parent folder):
#
#   1. A Quick Action in ~/Library/Services  -> right-click > Quick Actions
#   2. The app's CFBundleDocumentTypes       -> right-click > Open With
#
# Only (1) is created here; (2) is declared in the app's Info.plist by
# scripts/build.sh and just needs LaunchServices to notice it.
set -euo pipefail

APP="${HERDR_TOPBAR_APP:-$HOME/Applications/HerdrBar.app}"
HELPER="$APP/Contents/MacOS/herdrbar-open"
SERVICE_NAME="Open with herdr"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW="$SERVICES_DIR/$SERVICE_NAME.workflow"

if [ ! -x "$HELPER" ]; then
    echo "HerdrBar is not built yet (missing $HELPER). Run scripts/build.sh first." >&2
    exit 1
fi

echo "==> Installing Quick Action: $SERVICE_NAME"
rm -rf "$WORKFLOW"
mkdir -p "$WORKFLOW/Contents"

cat > "$WORKFLOW/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict><key>default</key><string>$SERVICE_NAME</string></dict>
            <key>NSMessage</key><string>runWorkflowAsService</string>
            <key>NSRequiredContext</key>
            <dict>
                <key>NSApplicationIdentifier</key><string>com.apple.finder</string>
            </dict>
            <!-- public.item covers both files and folders. -->
            <key>NSSendFileTypes</key>
            <array><string>public.item</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# A minimal Automator "Run Shell Script" workflow, taking the selected paths as
# arguments. Written by hand so installing needs no Automator round-trip.
cat > "$WORKFLOW/Contents/document.wflow" <<WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMDocumentVersion</key><string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key><string>List</string>
                    <key>Optional</key><true/>
                    <key>Types</key><array><string>com.apple.cocoa.string</string></array>
                </dict>
                <key>AMActionVersion</key><string>2.0.3</string>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key><string>List</string>
                    <key>Types</key><array><string>com.apple.cocoa.string</string></array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key><string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>exec "$HELPER" "\$@"</string>
                    <key>CheckedForUserDefaultShell</key><true/>
                    <!-- 1 = pass input as arguments rather than on stdin. -->
                    <key>inputMethod</key><integer>1</integer>
                    <key>shell</key><string>/bin/bash</string>
                    <key>source</key><string></string>
                </dict>
                <key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key><string>2.0.3</string>
                <key>CanShowSelectedItemsWhenRun</key><false/>
                <key>CanShowWhenRun</key><true/>
                <key>Category</key><array><string>AMCategoryUtilities</string></array>
                <key>Class Name</key><string>RunShellScriptAction</string>
                <key>InputUUID</key><string>8B2C1F6A-0000-4000-A000-000000000001</string>
                <key>OutputUUID</key><string>8B2C1F6A-0000-4000-A000-000000000002</string>
                <key>UUID</key><string>8B2C1F6A-0000-4000-A000-000000000003</string>
                <key>UnlocalizedApplications</key><array><string>Automator</string></array>
                <key>arguments</key><dict/>
                <key>isViewVisible</key><integer>1</integer>
                <key>location</key><string>309.000000:253.000000</string>
                <key>nibPath</key>
                <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
            </dict>
            <key>isViewVisible</key><integer>1</integer>
        </dict>
    </array>
    <key>connectors</key><dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>serviceApplicationBundleID</key><string>com.apple.finder</string>
        <key>serviceInputTypeIdentifier</key>
        <string>com.apple.Automator.fileSystemObject</string>
        <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
        <key>serviceProcessesInput</key><integer>0</integer>
        <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
    </dict>
</dict>
</plist>
WFLOW

# Fail loudly if either plist is malformed: a bad workflow does not error at
# use time, it just silently never appears in the menu.
plutil -lint "$WORKFLOW/Contents/Info.plist" >/dev/null
plutil -lint "$WORKFLOW/Contents/document.wflow" >/dev/null

echo "==> Refreshing Services and LaunchServices"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

echo
echo "Installed:"
echo "  Quick Action : $WORKFLOW"
echo "  Open With    : $APP"
echo
echo "Right-click any file or folder in Finder:"
echo "  Services  > $SERVICE_NAME     (near the bottom of the menu)"
echo "  Open With > HerdrBar"
echo
echo "A .workflow lands in Finder's SERVICES submenu, not under Quick Actions"
echo "— macOS reserves that one for app extensions and Shortcuts."
echo
echo "If it does not show up, enable it in"
echo "System Settings > Keyboard > Keyboard Shortcuts... > Services,"
echo "then run: killall Finder"
