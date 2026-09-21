#!/usr/bin/env node

const fs = require('fs');

// --- ABSOLUTE PATHS ---
const CSS_FILE = '/home/sakib/.config/matugen/matugen-colors.css';
const JSON_FILE = '/home/sakib/.config/zen-boosts/Matugen.json';

// --- COLOR-TUNING CONSTANTS ---
const CHROMA_MAX = 0.30;        // displayable ceiling of OKLab chroma for vivid sRGB colors
const MIN_BLEND = 0.1;          // floor for the accent blend amount (tint strength)
const MAX_BLEND = 0.95;         // ceiling for the accent blend amount
const PICKER_RADIUS_RATIO = 0.43; // editor's gradient ring radius as a fraction of widget width

// Helpers
function clamp(v, min, max) {
    return Math.min(max, Math.max(min, v));
}

function round4(v) {
    return parseFloat(v.toFixed(4));
}

// sRGB hex -> linear RGB [0..1]
function hexToLinearRgb(hex) {
    hex = hex.replace('#', '');
    return [0, 2, 4].map((i) => {
        const c = parseInt(hex.substring(i, i + 2), 16) / 255;
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
}

// Perceptual color: OKLab (Björn Ottosson) -> {L, a, b}
function oklabOf(hex) {
    const [r, g, b] = hexToLinearRgb(hex);
    const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    const l3 = Math.cbrt(l), m3 = Math.cbrt(m), s3 = Math.cbrt(s);
    return {
        L: 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
        a: 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
        b: 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3
    };
}

function oklabChroma(ok) {
    return Math.hypot(ok.a, ok.b);
}

// CIE L* tone (0..100) - the same lightness metric Material You palettes are built on
function ciedeTone(hex) {
    const [r, g, b] = hexToLinearRgb(hex);
    const x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
    const y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    const z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
    const f = (t) => t > 0.008856 ? Math.cbrt(t) : t / 0.12841855 + 0.13793103;
    return 116 * f(y) - 16;
}

// Same HSL conversion Zen's boosts use (ZenBoostsChild.sys.mjs) so values round-trip
function rgbToHsl(r, g, b) {
    r /= 255;
    g /= 255;
    b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
    let h;
    if (d === 0) h = 0;
    else if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    const l = (min + max) / 2;
    const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
    return { h: ((h * 60) % 360 + 360) % 360, s, l };
}

function hexToRgb255(hex) {
    hex = hex.replace('#', '');
    return [parseInt(hex.substring(0, 2), 16), parseInt(hex.substring(2, 4), 16), parseInt(hex.substring(4, 6), 16)];
}

// Signed angular distance in [-180, 180]
function hueDelta(from, to) {
    let d = to - from;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
}

// Picker position: Zen stores dotAngleDeg = geometric angle + 100deg and
// dotDistance as the ring radius fraction (saturation analog of the dots).
function pickerPos(hueDeg, distance, radiusRatio) {
    const geomDeg = ((hueDeg - 100) % 360 + 360) % 360;
    const rad = (geomDeg * Math.PI) / 180;
    const r = distance * radiusRatio;
    return {
        x: round4(clamp(0.5 + Math.cos(rad) * r, 0, 1)),
        y: round4(clamp(0.5 + Math.sin(rad) * r, 0, 1))
    };
}

function cssColor(cssContent, name) {
    const match = cssContent.match(new RegExp(`--${name}:\\s*(#[a-fA-F0-9]{6})`));
    return match ? match[1] : null;
}

try {
    if (!fs.existsSync(CSS_FILE)) {
        console.error(`Error: Cannot find CSS file at: ${CSS_FILE}`);
        process.exit(1);
    }
    const cssContent = fs.readFileSync(CSS_FILE, 'utf8');

    const primaryHex = cssColor(cssContent, 'primary');
    const backgroundHex = cssColor(cssContent, 'background');
    const surfaceHex = cssColor(cssContent, 'surface');
    const onSurfaceHex = cssColor(cssContent, 'on_surface');

    if (!primaryHex || (!surfaceHex && !backgroundHex)) {
        console.error("Could not extract both '--primary' and '--surface' from matugen-colors.css.");
        process.exit(1);
    }

    if (!fs.existsSync(JSON_FILE)) {
        console.error(`Error: Cannot find Boost JSON file at: ${JSON_FILE}`);
        process.exit(1);
    }
    const boostData = JSON.parse(fs.readFileSync(JSON_FILE, 'utf8'));

    // 1. PRIMARY DOT COLOR
    // Zen renders the boost accent as hsl(dotAngleDeg, 1 - saturation, 0.1 + 0.9*brightness).
    // Its hue comes from the theme accent; its saturation from the accent's perceptual
    // chroma; its lightness is anchored to the surface so it stays in the dark theme range.
    const [pr, pg, pb] = hexToRgb255(primaryHex);
    const primaryHsl = rgbToHsl(pr, pg, pb);
    const primaryOk = oklabOf(primaryHex);
    const primaryChroma = oklabChroma(primaryOk);

    boostData.dotAngleDeg = round4(primaryHsl.h);
    const renderedSat = clamp(Math.sqrt(primaryChroma / CHROMA_MAX), 0.05, 1);
    boostData.saturation = round4(clamp(1 - renderedSat, 0, 1));
    boostData.dotDistance = round4(renderedSat);

    // 2. LIGHTNESS: tint lightness tracks the surface tone (dark themes stay dark)
    const surfaceTone = ciedeTone(surfaceHex || backgroundHex);
    const tintLight = Math.max(surfaceTone / 100, 0.1);
    boostData.brightness = round4(clamp((tintLight - 0.1) / 0.9, 0, 1));

    // 3. SECONDARY DOT: paired with on_surface, the theme's text color
    const [orr, org, orb] = hexToRgb255(onSurfaceHex || '#ffffff');
    const onSurfaceHsl = rgbToHsl(orr, org, orb);
    boostData.secondaryDotAngleDegDelta = round4(hueDelta(primaryHsl.h, onSurfaceHsl.h));
    const secondaryHue = (primaryHsl.h + boostData.secondaryDotAngleDegDelta + 360) % 360;

    // 4. CONTRAST: accent blend strength from the theme's chroma and tonal spread
    const onSurfaceTone = ciedeTone(onSurfaceHex || '#ffffff');
    const chromaFactor = Math.sqrt(Math.min(1, primaryChroma / CHROMA_MAX));
    const tonalSpread = clamp((onSurfaceTone - surfaceTone) / 100, 0, 1);
    const blend = clamp(chromaFactor * (0.5 + 0.5 * tonalSpread), MIN_BLEND, MAX_BLEND);
    boostData.contrast = round4(clamp(1 - blend, 0.05, 0.9));

    // 5. DOT POSITIONS: place both dots on the picker ring at their true hues
    boostData.dotPos = pickerPos(boostData.dotAngleDeg, boostData.dotDistance, PICKER_RADIUS_RATIO);
    boostData.secondaryDotPos = pickerPos(secondaryHue, boostData.dotDistance, PICKER_RADIUS_RATIO);

    boostData.changeWasMade = true;

    fs.writeFileSync(JSON_FILE, JSON.stringify(boostData, null, 2), 'utf8');
    console.log('Matugen boost updated successfully.');
    console.log(`  Primary dot: hue ${boostData.dotAngleDeg}° (${primaryHex})`);
    console.log(`  Secondary dot: on_surface at ${boostData.secondaryDotAngleDegDelta}° delta`);
    console.log(`  Lightness: ${(0.1 + 0.9 * boostData.brightness).toFixed(3)} (surface tone ${(surfaceTone / 100).toFixed(3)})`);
    console.log(`  Saturation field: ${boostData.saturation} (renders ${(1 - boostData.saturation).toFixed(3)})`);
    console.log(`  Contrast: ${boostData.contrast} (blend ${blend.toFixed(3)})`);
    console.log(`  Dot positions: primary (${boostData.dotPos.x}, ${boostData.dotPos.y}), secondary (${boostData.secondaryDotPos.x}, ${boostData.secondaryDotPos.y})`);

} catch (error) {
    console.error("Pipeline error:", error.message);
}