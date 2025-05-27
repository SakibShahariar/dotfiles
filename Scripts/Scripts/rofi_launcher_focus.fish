#!/usr/bin/env fish

# Get a Wayland XDG activation token
set token (gdbus call --session \
  --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.portal.RequestSession.CreateSession \
  "{}" 2>/dev/null | string split -m1 "'" | tail -n 1)

# If token was received
if test -n "$token"
    env XDG_ACTIVATION_TOKEN=$token /home/sakib/.config/rofi/launchers/type-1/launcher.sh
else
    /home/sakib/.config/rofi/launchers/type-1/launcher.sh
end
