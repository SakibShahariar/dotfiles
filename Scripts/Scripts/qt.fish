#!/usr/bin/env fish

set qt5config ~/.config/qt5ct/qt5ct.conf
set qt6config ~/.config/qt6ct/qt6ct.conf
set kvconfig ~/.config/Kvantum/kvantum.kvconfig

# get current kvantum theme (matugen generated)
set matugen_theme (grep '^theme=' $kvconfig | cut -d= -f2)

# fallback style
set fallback Fusion

# --- Qt5: force away ---
if test -f $qt5config
    sed -i "s/^style=.*/style=$fallback/" $qt5config
end

# --- Qt6: force away ---
if test -f $qt6config
    sed -i "s/^style=.*/style=$fallback/" $qt6config
end

sleep 0.3

# --- restore kvantum theme ---
sed -i "s/^theme=.*/theme=$matugen_theme/" $kvconfig

# --- restore kvantum engine ---
if test -f $qt5config
    sed -i "s/^style=.*/style=kvantum/" $qt5config
end

if test -f $qt6config
    sed -i "s/^style=.*/style=kvantum/" $qt6config
end
