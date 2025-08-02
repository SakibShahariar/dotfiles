#!/usr/bin/env python3
"""
Dual Color Picker v3.1
- Fixed alpha transparency in contrast calculations
- Precision decimal contrast ratings
- Logarithmic scaling for high contrast ratios
- Partial dot filling for visual accuracy
- Enhanced WCAG compliance descriptions
"""

import gi
import cairo
import math
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib

class DualColorPicker(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='com.example.DualColorPicker.v3_1')
        self.text_color = Gdk.RGBA()
        self.text_color.parse("rgb(0,0,0)")
        self.bg_color = Gdk.RGBA()
        self.bg_color.parse("rgb(255,255,255)")
        self.updating = False

    def do_activate(self):
        self.win = Gtk.ApplicationWindow(application=self, title="Dual Color Picker v3.1")
        self.win.set_default_size(800, 600)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.win.set_child(scrolled)

        main_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        main_container.set_margin_top(24)
        main_container.set_margin_bottom(24)
        main_container.set_margin_start(24)
        main_container.set_margin_end(24)
        scrolled.set_child(main_container)

        self.main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=24)
        main_container.append(self.main_box)

        self.text_panel, self.text_preview = self.create_color_panel("Text Color", self.text_color, "text")
        self.main_box.append(self.text_panel)

        separator = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.main_box.append(separator)

        self.bg_panel, self.bg_preview = self.create_color_panel("Background Color", self.bg_color, "bg")
        self.main_box.append(self.bg_panel)

        self.create_preview_box(main_container)
        self.create_contrast_rating_box(main_container)

        self.update_displays("text")
        self.update_displays("bg")
        self.update_contrast_rating()

        self.win.present()

    def blend_with_background(self, foreground, background):
        """Blend semi-transparent colors with their background"""
        if foreground.alpha >= 1.0:
            return foreground

        result = Gdk.RGBA()
        alpha = foreground.alpha
        result.red = foreground.red * alpha + background.red * (1 - alpha)
        result.green = foreground.green * alpha + background.green * (1 - alpha)
        result.blue = foreground.blue * alpha + background.blue * (1 - alpha)
        result.alpha = 1.0  # Result is now effectively opaque
        return result

    def create_contrast_rating_box(self, parent):
        contrast_frame = Gtk.Frame()
        contrast_frame.set_margin_top(24)
        contrast_frame.set_css_classes(["contrast-frame"])
        parent.append(contrast_frame)

        contrast_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        contrast_box.set_margin_start(12)
        contrast_box.set_margin_end(12)
        contrast_box.set_margin_top(12)
        contrast_box.set_margin_bottom(12)
        contrast_frame.set_child(contrast_box)

        title = Gtk.Label(label="Contrast Rating (WCAG 2.1)")
        title.set_css_classes(["title-4"])
        title.set_halign(Gtk.Align.CENTER)
        contrast_box.append(title)

        center_box = Gtk.CenterBox()
        contrast_box.append(center_box)

        self.rating_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        center_box.set_center_widget(self.rating_box)

        self.rating_dots = []
        for i in range(10):
            dot = Gtk.DrawingArea()
            dot.set_size_request(24, 24)
            dot.set_draw_func(self.draw_rating_dot, i+1)
            self.rating_dots.append(dot)
            self.rating_box.append(dot)

        self.rating_label = Gtk.Label()
        self.rating_label.set_margin_top(6)
        self.rating_label.set_halign(Gtk.Align.CENTER)
        contrast_box.append(self.rating_label)

        self.contrast_ratio_label = Gtk.Label()
        self.contrast_ratio_label.set_halign(Gtk.Align.CENTER)
        contrast_box.append(self.contrast_ratio_label)

        self.wcag_label = Gtk.Label()
        self.wcag_label.set_wrap(True)
        self.wcag_label.set_halign(Gtk.Align.CENTER)
        contrast_box.append(self.wcag_label)

        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"""
            .contrast-frame {
                border: 1px solid @borders;
                border-radius: 4px;
                padding: 12px;
            }
            .title-4 {
                font-weight: bold;
                font-size: 1.1em;
                margin-bottom: 6px;
            }
        """)
        contrast_frame.get_style_context().add_provider(
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def draw_rating_dot(self, area, cr, width, height, rating_level):
        ratio = self.calculate_contrast_ratio()
        if ratio is None:
            return

        rating = self.contrast_ratio_to_rating(ratio)
        dot_size = min(width, height) - 4
        x = (width - dot_size) / 2
        y = (height - dot_size) / 2

        if rating_level <= math.floor(rating):
            fill_level = 1.0
        elif rating_level <= rating:
            fill_level = rating - math.floor(rating)
        else:
            fill_level = 0.0

        if fill_level > 0:
            if rating >= 9:
                cr.set_source_rgb(0.0, 0.6, 0.1)  # Dark green
            elif rating >= 8:
                cr.set_source_rgb(0.2, 0.8, 0.2)  # Green
            elif rating >= 7:
                cr.set_source_rgb(0.5, 0.9, 0.2)  # Lime
            elif rating >= 5:
                cr.set_source_rgb(0.9, 0.8, 0.1)  # Yellow
            else:
                cr.set_source_rgb(0.9, 0.3, 0.2)  # Red

            cr.arc(x + dot_size/2, y + dot_size/2, dot_size/2 * fill_level, 0, 2 * math.pi)
            cr.fill()

        cr.set_source_rgb(0.7, 0.7, 0.7)
        cr.arc(x + dot_size/2, y + dot_size/2, dot_size/2, 0, 2 * math.pi)
        cr.set_line_width(1.5)
        cr.stroke()

    def calculate_relative_luminance(self, color):
        def srgb_to_linear(channel):
            if channel <= 0.03928:
                return channel / 12.92
            else:
                return ((channel + 0.055) / 1.055) ** 2.4

        r = srgb_to_linear(color.red)
        g = srgb_to_linear(color.green)
        b = srgb_to_linear(color.blue)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b

    def calculate_contrast_ratio(self):
        # Blend colors if they have transparency
        effective_text = self.blend_with_background(self.text_color, self.bg_color)
        effective_bg = self.blend_with_background(self.bg_color, self.text_color)

        l1 = self.calculate_relative_luminance(effective_text)
        l2 = self.calculate_relative_luminance(effective_bg)

        if l1 < l2:
            l1, l2 = l2, l1
        return (l1 + 0.05) / (l2 + 0.05)

    def contrast_ratio_to_rating(self, ratio):
        if ratio >= 21: return 10.0
        elif ratio >= 7:
            return 8.5 + (math.log10(ratio) - math.log10(7)) * (1.5 / (math.log10(21) - math.log10(7)))
        elif ratio >= 4.5: return 7 + (ratio - 4.5) / (7 - 4.5) * 1.5
        elif ratio >= 3: return 4 + (ratio - 3) / (4.5 - 3) * 3
        else: return max(1, ratio)

    def update_contrast_rating(self):
        ratio = self.calculate_contrast_ratio()
        if ratio is None:
            return

        for dot in self.rating_dots:
            dot.queue_draw()

        self.contrast_ratio_label.set_label(f"Contrast Ratio: {ratio:.2f}:1")

        rating = self.contrast_ratio_to_rating(ratio)
        rating_str = f"{rating:.1f}".replace(".0", "")

        if rating >= 9.5:
            rating_text = f"Perfect contrast ({rating_str}/10)"
            wcag_text = "Maximum possible contrast (21:1)"
        elif rating >= 8.5:
            rating_text = f"Excellent contrast ({rating_str}/10)"
            wcag_text = "Exceeds WCAG AAA (7:1)"
        elif rating >= 7:
            rating_text = f"Very good contrast ({rating_str}/10)"
            wcag_text = "Meets WCAG AAA (7:1)"
        elif rating >= 4.5:
            rating_text = f"Good contrast ({rating_str}/10)"
            wcag_text = "Meets WCAG AA (4.5:1)"
        elif rating >= 3:
            rating_text = f"Fair contrast ({rating_str}/10)"
            wcag_text = "Minimum for large text (3:1)"
        else:
            rating_text = f"Poor contrast ({rating_str}/10)"
            wcag_text = "Fails WCAG requirements"

        self.rating_label.set_label(f"Rating: {rating_text}")
        self.wcag_label.set_label(f"Accessibility: {wcag_text}")

    def create_preview_box(self, parent):
        preview_frame = Gtk.Frame()
        preview_frame.set_margin_top(24)
        preview_frame.set_css_classes(["preview-frame"])
        parent.append(preview_frame)

        self.combined_preview = Gtk.DrawingArea()
        self.combined_preview.set_size_request(350, 90)
        self.combined_preview.set_draw_func(self.draw_combined_preview, None)
        preview_frame.set_child(self.combined_preview)

        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"""
            .preview-frame {
                border: 1px solid @borders;
                border-radius: 4px;
                margin-left: 50px;
                margin-right: 50px;
            }
        """)
        preview_frame.get_style_context().add_provider(
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def draw_combined_preview(self, area, cr, width, height, data):
        # Draw background (with potential transparency)
        bg = self.blend_with_background(self.bg_color, self.text_color)
        Gdk.cairo_set_source_rgba(cr, bg)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        # Draw text (with potential transparency)
        text = self.blend_with_background(self.text_color, self.bg_color)
        Gdk.cairo_set_source_rgba(cr, text)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)

        line_height = height / 3
        base_y = line_height * 0.7

        cr.set_font_size(12)
        body_text = "Body"
        extents = cr.text_extents(body_text)
        cr.move_to((width - extents.width)/2, base_y)
        cr.show_text(body_text)

        cr.set_font_size(16)
        header_text = "Header"
        extents = cr.text_extents(header_text)
        cr.move_to((width - extents.width)/2, base_y + line_height)
        cr.show_text(header_text)

        cr.set_font_size(20)
        display_text = "Display"
        extents = cr.text_extents(display_text)
        cr.move_to((width - extents.width)/2, base_y + line_height*2)
        cr.show_text(display_text)

    def create_color_panel(self, title, color, prefix):
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

        title_label = Gtk.Label(label=title)
        title_label.set_halign(Gtk.Align.CENTER)
        title_label.set_margin_bottom(12)
        panel.append(title_label)

        preview_frame = Gtk.Frame()
        preview_frame.set_size_request(-1, 80)
        preview_frame.set_css_classes(["color-preview"])

        preview = Gtk.DrawingArea()
        preview.set_draw_func(self.draw_color_preview, color)
        preview_frame.set_child(preview)
        panel.append(preview_frame)

        formats = [
            ("HEX", self.get_hex_color, "hex"),
            ("HEX+Alpha", self.get_hex_alpha_color, "hex_alpha"),
            ("RGB", self.get_rgb_color, "rgb"),
            ("RGBA", self.get_rgba_color, "rgba")
        ]

        for name, formatter, prop in formats:
            frame = Gtk.Frame()
            frame.set_margin_bottom(8)

            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            box.set_margin_start(6)
            box.set_margin_end(6)
            box.set_margin_top(6)
            box.set_margin_bottom(6)

            label = Gtk.Label(label=name)
            label.set_size_request(80, -1)
            label.set_xalign(0)
            box.append(label)

            entry = Gtk.Entry()
            entry.set_text(formatter(color))
            entry.set_hexpand(True)
            box.append(entry)

            frame.set_child(box)
            panel.append(frame)

            setattr(self, f"{prefix}_{prop}_entry", entry)

            if prop == "rgba":
                entry.connect("notify::has-focus", self.on_rgba_focus_change, prefix)
                entry.connect("activate", self.on_rgba_activate, prefix)
            else:
                entry.connect("changed", getattr(self, f"on_{prop}_changed"), prefix)

        return panel, preview

    def on_rgba_focus_change(self, entry, param, prefix):
        if not entry.has_focus():
            self.validate_rgba(entry, prefix)

    def on_rgba_activate(self, entry, prefix):
        self.validate_rgba(entry, prefix)

    def validate_rgba(self, entry, prefix):
        if self.updating:
            return

        text = entry.get_text()

        try:
            parts = [p.strip() for p in text.split(",")]
            if len(parts) == 4:
                color = getattr(self, f"{prefix}_color")
                color.red = min(max(int(parts[0]), 0), 255)/255
                color.green = min(max(int(parts[1]), 0), 255)/255
                color.blue = min(max(int(parts[2]), 0), 255)/255
                alpha_str = parts[3]
                if alpha_str:
                    alpha = min(max(float(alpha_str), 0.0), 1.0)
                    color.alpha = alpha
                self.update_displays(prefix)

        except (ValueError, IndexError):
            color = getattr(self, f"{prefix}_color")
            self.updating = True
            entry.set_text(f"{int(color.red*255)}, {int(color.green*255)}, {int(color.blue*255)}, {round(color.alpha, 2)}")
            self.updating = False

    def get_hex_color(self, color):
        return f"#{int(color.red*255):02X}{int(color.green*255):02X}{int(color.blue*255):02X}"

    def get_hex_alpha_color(self, color):
        return f"#{int(color.red*255):02X}{int(color.green*255):02X}{int(color.blue*255):02X}{int(color.alpha*255):02X}"

    def get_rgb_color(self, color):
        return f"{int(color.red*255)}, {int(color.green*255)}, {int(color.blue*255)}"

    def get_rgba_color(self, color):
        return f"{int(color.red*255)}, {int(color.green*255)}, {int(color.blue*255)}, {round(color.alpha, 2)}"

    def draw_color_preview(self, area, cr, width, height, color):
        Gdk.cairo_set_source_rgba(cr, color)
        cr.rectangle(0, 0, width, height)
        cr.fill()

    def update_displays(self, color_var):
        if self.updating:
            return

        self.updating = True

        color = getattr(self, f"{color_var}_color")

        cursor_positions = {
            'hex': getattr(self, f"{color_var}_hex_entry").get_position(),
            'hex_alpha': getattr(self, f"{color_var}_hex_alpha_entry").get_position(),
            'rgb': getattr(self, f"{color_var}_rgb_entry").get_position(),
            'rgba': getattr(self, f"{color_var}_rgba_entry").get_position()
        }

        getattr(self, f"{color_var}_hex_entry").set_text(self.get_hex_color(color))
        getattr(self, f"{color_var}_hex_alpha_entry").set_text(self.get_hex_alpha_color(color))
        getattr(self, f"{color_var}_rgb_entry").set_text(self.get_rgb_color(color))
        getattr(self, f"{color_var}_rgba_entry").set_text(self.get_rgba_color(color))

        getattr(self, f"{color_var}_hex_entry").set_position(cursor_positions['hex'])
        getattr(self, f"{color_var}_hex_alpha_entry").set_position(cursor_positions['hex_alpha'])
        getattr(self, f"{color_var}_rgb_entry").set_position(cursor_positions['rgb'])
        getattr(self, f"{color_var}_rgba_entry").set_position(cursor_positions['rgba'])

        if color_var == "text":
            self.text_preview.queue_draw()
        else:
            self.bg_preview.queue_draw()

        self.combined_preview.queue_draw()
        self.update_contrast_rating()

        self.updating = False

    def on_hex_changed(self, entry, prefix):
        if self.updating:
            return

        text = entry.get_text().lstrip('#')
        if len(text) == 6:
            try:
                color = getattr(self, f"{prefix}_color")
                color.red = int(text[0:2], 16) / 255
                color.green = int(text[2:4], 16) / 255
                color.blue = int(text[4:6], 16) / 255
                self.update_displays(prefix)
            except:
                pass

    def on_hex_alpha_changed(self, entry, prefix):
        if self.updating:
            return

        text = entry.get_text().lstrip('#')
        if len(text) == 8:
            try:
                color = getattr(self, f"{prefix}_color")
                color.red = int(text[0:2], 16) / 255
                color.green = int(text[2:4], 16) / 255
                color.blue = int(text[4:6], 16) / 255
                color.alpha = int(text[6:8], 16) / 255
                self.update_displays(prefix)
            except:
                pass

    def on_rgb_changed(self, entry, prefix):
        if self.updating:
            return

        try:
            parts = [int(p.strip()) for p in entry.get_text().split(",")]
            if len(parts) == 3:
                color = getattr(self, f"{prefix}_color")
                color.red = min(max(parts[0], 0), 255)/255
                color.green = min(max(parts[1], 0), 255)/255
                color.blue = min(max(parts[2], 0), 255)/255
                self.update_displays(prefix)
        except:
            pass

if __name__ == "__main__":
    app = DualColorPicker()
    app.run()
