#!/usr/bin/env fish

# Infinite loop to constantly check if GNOME Software is running
while true
    # Check if any gnome-software process is running (including background ones)
    if pgrep -x "gnome-software" > /dev/null
        # Kill all instances of gnome-software (main and background processes)
        killall -9 gnome-software
    end
    # Sleep for a short time before checking again
    sleep 5
end
