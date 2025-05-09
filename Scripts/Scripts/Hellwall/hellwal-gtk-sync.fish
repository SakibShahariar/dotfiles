#!/usr/bin/env fish

/* 🔮 Auto-generated by hellwal-gtk-sync */

/* General Colors */
@define-color window_bg_color @theme_bg_color;
@define-color window_fg_color @theme_fg_color;
@define-color accent_color @accent_color;
@define-color accent_bg_color @accent_bg_color;
@define-color accent_fg_color @accent_fg_color;
@define-color sidebar_bg_color @theme_bg_color;
@define-color sidebar_fg_color @theme_fg_color;
@define-color card_bg_color @theme_bg_color;
@define-color card_fg_color @theme_fg_color;
@define-color dialog_bg_color @theme_bg_color;
@define-color dialog_fg_color @theme_fg_color;
@define-color popover_bg_color @popover_bg_color;
@define-color popover_fg_color @popover_fg_color;
@define-color tooltip_bg_color @tooltip_bg_color;
@define-color tooltip_fg_color @tooltip_fg_color;
@define-color highlight_bg_color @highlight_bg_color;
@define-color highlight_fg_color @highlight_fg_color;

/* Window and View */
window.csd {
    background-color: @window_bg_color;
    color: @window_fg_color;
}

window.csd:backdrop {
    background-color: @window_bg_color;
}

.content-pane, .content-pane.view, .view {
    background-color: @window_bg_color;
    color: @window_fg_color;
}

.content-pane:backdrop, .content-pane.view:backdrop, .view:backdrop {
    background-color: @window_bg_color;
}

.sidebar, .navigation-sidebar, .sidebar-pane {
    background-color: @sidebar_bg_color;
    color: @sidebar_fg_color;
}

.sidebar-pane .card {
    background-color: @card_bg_color;
    color: @card_fg_color;
}

.dialog, .popover {
    background-color: @dialog_bg_color;
    color: @dialog_fg_color;
}

.popover {
    background-color: @popover_bg_color;
    color: @popover_fg_color;
}

.tooltip {
    background-color: @tooltip_bg_color;
    color: @tooltip_fg_color;
}

.highlight {
    background-color: @highlight_bg_color;
    color: @highlight_fg_color;
}

/* Headerbar */
headerbar, .top-bar, .titlebar {
    background-color: @window_bg_color;
    color: @window_fg_color;
}

headerbar, .top-bar, .titlebar {
    color: @window_fg_color;
    background-color: @window_bg_color;
}

headerbar .image-button {
    background: transparent;
    border: none;
    padding: 3px;
}

headerbar .image-button:hover {
    background-image: none;
    color: @window_fg_color;
}

/* Link */
link {
    color: @accent_color;
}

link:hover {
    color: @accent_fg_color;
}

/* Scrollbar */
scrollbar slider {
    background-color: alpha(@window_fg_color, 0.5);
    border-radius: 6px;
    min-width: 6px;
    min-height: 6px;
}

scrollbar slider:hover {
    background-color: alpha(@window_fg_color, 0.8);
}

/* Menu */
menu, .menu {
    border-radius: 6px;
    box-shadow: 0 2px 8px 0px alpha(@window_bg_color, 0.2);
    padding: 6px;
}

menu > menuitem, .menu > menuitem {
    padding: 6px 12px;
    border-radius: 4px;
}

menu > menuitem:hover, .menu > menuitem:hover {
    background-color: alpha(@accent_color, 0.1);
}

/* Entry */
entry {
    padding: 6px 12px;
    border-radius: 6px;
    border: 1px solid alpha(@window_fg_color, 0.2);
    background-color: @window_bg_color;
    color: @window_fg_color;
}

entry:focus {
    border-color: @accent_color;
    box-shadow: 0 0 0 2px alpha(@accent_color, 0.2);
}

/* Progressbar */
progressbar {
    background-color: alpha(@window_fg_color, 0.1);
    border-radius: 6px;
}

progressbar > trough {
    background-color: transparent;
}

progressbar > trough > progress {
    background-color: @accent_color;
    border-radius: 6px;
}

/* List Row */
list row {
    padding: 4px 8px;
    border-radius: 4px;
}

list row:hover {
    background-color: alpha(@accent_color, 0.1);
}

list row:selected {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Window Border */
window.csd {
    border: 1px solid alpha(@window_fg_color, 0.1);
}

/* Button */
button {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
    padding: 6px 12px;
    border-radius: 6px;
}

button:hover {
    background-color: alpha(@accent_color, 0.1);
}

/* Toggle */
togglebutton {
    background-color: @window_bg_color;
    color: @window_fg_color;
    border: 1px solid alpha(@window_fg_color, 0.2);
    padding: 6px 12px;
    border-radius: 6px;
}

togglebutton:checked {
    background-color: @accent_color;
    color: @accent_fg_color;
}

togglebutton:checked:hover {
    background-color: alpha(@accent_color, 0.2);
}

/* Combo Box */
combobox, combobox popup {
    background-color: @window_bg_color;
    color: @window_fg_color;
    padding: 6px 12px;
    border-radius: 6px;
}

combobox:hover, combobox popup:hover {
    background-color: alpha(@accent_color, 0.1);
}

/* Radio Button */
radio {
    background-color: @window_bg_color;
    color: @window_fg_color;
    border-radius: 6px;
    padding: 6px 12px;
}

radio:checked {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Switch */
switch {
    background-color: @window_bg_color;
    color: @window_fg_color;
    border-radius: 6px;
    padding: 6px 12px;
}

switch:checked {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Icon View */
iconview, iconview-item {
    background-color: @window_bg_color;
    color: @window_fg_color;
}

iconview-item:selected {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Check Box */
checkbox {
    background-color: @window_bg_color;
    color: @window_fg_color;
    border-radius: 6px;
    padding: 6px 12px;
}

checkbox:checked {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Slider */
slider {
    background-color: alpha(@window_fg_color, 0.5);
    border-radius: 6px;
}

slider > trough {
    background-color: transparent;
}

slider > trough > progress {
    background-color: @accent_color;
    border-radius: 6px;
}
