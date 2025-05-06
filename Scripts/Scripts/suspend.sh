#!/usr/bin/env fish
zenity --question --text="Do you want to suspend your computer?"
if test $status -eq 0
    systemctl suspend
end
