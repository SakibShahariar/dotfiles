#!/usr/bin/env fish
# File: ~/Scripts/qt_xcb_wrap.fish
# Usage: qt_xcb_wrap.fish kate
# Wraps a Qt app with XCB for GNOME launcher

if test (count $argv) -eq 0
    echo "Usage: qt_xcb_wrap.fish <app-binary-or-name>"
    exit 1
end

set app $argv[1]

# Find the binary path
set bin (which $app)
if test -z "$bin"
    echo "Binary not found: $app"
    exit 1
end

# Search for desktop file
set desktop_file ""
for dir in $HOME/.local/share/applications /usr/share/applications
    for f in (find $dir -type f -name "*.desktop")
        if grep -q "Exec=.*"(basename $bin) $f
            set desktop_file $f
            break
        end
    end
    if test -n "$desktop_file"
        break
    end
end

if test -z "$desktop_file"
    echo "No .desktop file found for $app"
    exit 1
end

# Ensure user folder
mkdir -p $HOME/.local/share/applications

# Copy to user folder if not already there
set user_desktop $HOME/.local/share/applications/(basename $desktop_file)
if test $desktop_file != $user_desktop
    cp $desktop_file $user_desktop
end

# Backup original
cp $user_desktop $user_desktop.bak

# Prepend env to Exec line if not already done
if not grep -q "^Exec=env QT_QPA_PLATFORM=xcb" $user_desktop
    sed -i "s|^Exec=|Exec=env QT_QPA_PLATFORM=xcb |" $user_desktop
    echo "Patched $user_desktop → QT_QPA_PLATFORM=xcb"
else
    echo "Already patched: $user_desktop"
end
