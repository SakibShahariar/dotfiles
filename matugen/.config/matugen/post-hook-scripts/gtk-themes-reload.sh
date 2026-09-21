#!/usr/bin/env bash

hc=$(gsettings get org.gnome.desktop.a11y.interface high-contrast)

if [[ "$hc" == "true" ]]; then
    gsettings set org.gnome.desktop.a11y.interface high-contrast false
    gsettings set org.gnome.desktop.a11y.interface high-contrast true
else
    gsettings set org.gnome.desktop.a11y.interface high-contrast true
    gsettings set org.gnome.desktop.a11y.interface high-contrast false
fi