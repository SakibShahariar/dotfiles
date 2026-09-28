#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// --- INPUT / OUTPUT ---
// The accent is read from whichever theme palette was written most recently,
// so the same script works for both the matugen and the tinct pipeline.
const CSS_CANDIDATES = [
    '/home/sakib/.config/matugen/matugen-colors.css',
    '/home/sakib/.config/hellwal/hellwal-colors.css'
];
const JSON_FILE = '/home/sakib/.config/zen-boosts/Matugen.json';

// --- COLOR-TUNING CONSTANTS ---
const CHROMA_MAX = 0.30;        // displayable ceiling of OKLab chroma for vivid sRGB colors
const PICKER_RADIUS_RATIO = 0.43; // editor's gradient ring radius as a fraction of widget width

// Zen's boost editor clamps the contrast slider to this range (zen-boost-editor.xhtml:108).
const ZEN_CONTRAST_MIN = 0.05;
const ZEN_CONTRAST_MAX = 0.9;

// Zen renders a boost as hsl(dotAngleDeg, 1 - saturation, 0.1 + 0.9 * brightness),
// so the reachable lightness window is [0.1, 1.0] and only a target below L 0.1
// cannot be reproduced exactly. See ZenBoostsChild.sys.mjs.
const ZEN_L_MIN = 0.1;
const ZEN_L_MAX = 1.0;

// --- CLI ---
const argv = process.argv.slice(2);
function flag(name) {
    return argv.includes(name);
}
function opt(name, fallback) {
    const i = argv.indexOf(name);
    return i !== -1 && argv[i + 1] ? argv[i + 1] : fallback;
}

const dryRun = flag('--dry-run');
const quiet = flag('--quiet');
const jsonOnly = flag('--json');
const cssOverride = opt('--css', null);
const jsonOverride = opt('--out', JSON_FILE);
const mode = opt('--mode', 'exact');   // 'exact' = byte-exact accent, 'perceptual' = prior tuning
// The boost colour is the page's accent, not a background fill. Zen always paints
// it fully opaque and only tints the page around it, so targeting the dark
// background role produced a dull near-black boost. The accent role is both
// byte-exact (20/20) and keeps text punchy against the page.
const targetVar = opt('--target', 'primary');
// Contrast is Zen's own legibility control, not a tint strength: the boost colour
// is stored fully opaque and (1 - contrast) * 255 is only a data byte in the alpha
// slot (ZenBoostsChild.sys.mjs:104-109). Keep Zen's own default of 0.75 rather
// than inventing a value - pushing it low is what makes text dull and washed out.
const contrast = clamp(Number(opt('--contrast', '0.75')), ZEN_CONTRAST_MIN, ZEN_CONTRAST_MAX);

// Helpers
function clamp(v, min, max) {
    return Math.min(max, Math.max(min, v));
}

function round4(v) {
    return parseFloat(v.toFixed(4));
}

// Boost fields drive Zen's round()-to-integer render, so they are written with
// more precision than the perceptual path needs.
function round6(v) {
    return parseFloat(v.toFixed(6));
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

// --- Zen's exact render path (ZenBoostsChild.sys.mjs) ---
// Kept byte-identical to the browser so the solver can verify its own output.
function zenHueToRgb(p, q, t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
}

function zenRender(dotAngleDeg, saturation, brightness) {
    const h = dotAngleDeg / 360;
    const s = 1 - saturation;
    const l = ZEN_L_MIN + (ZEN_L_MAX - ZEN_L_MIN) * brightness;
    let r, g, b;
    if (s === 0) {
        r = g = b = l;
    } else {
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        const p = 2 * l - q;
        r = zenHueToRgb(p, q, h + 1 / 3);
        g = zenHueToRgb(p, q, h);
        b = zenHueToRgb(p, q, h - 1 / 3);
    }
    return [r, g, b].map((v) => Math.round(v * 255));
}

const sameRgb = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

// Invert Zen's mapping for a target hex, then nudge the stored fields until the
// rendered integer RGB matches byte for byte. The fields are written as floats,
// so the only source of error is Zen's round() landing on a boundary.
function solveExact(targetHex) {
    const target = hexToRgb255(targetHex);
    const t = rgbToHsl(...target);

    const reachable = t.l >= ZEN_L_MIN - 1e-9 && t.l <= ZEN_L_MAX + 1e-9;
    if (!reachable) {
        return {
            exact: false,
            reachable: false,
            reason: `target lightness ${t.l.toFixed(4)} is outside Zen's [${ZEN_L_MIN}, ${ZEN_L_MAX}] window`,
            dotAngleDeg: round6(t.h),
            saturation: round6(clamp(1 - t.s, 0, 1)),
            brightness: round6(clamp((t.l - ZEN_L_MIN) / (ZEN_L_MAX - ZEN_L_MIN), 0, 1)),
            rendered: zenRender(t.h, clamp(1 - t.s, 0, 1), clamp((t.l - ZEN_L_MIN) / (ZEN_L_MAX - ZEN_L_MIN), 0, 1))
        };
    }

    const baseH = t.h;
    const baseS = clamp(1 - t.s, 0, 1);
    const baseB = clamp((t.l - ZEN_L_MIN) / (ZEN_L_MAX - ZEN_L_MIN), 0, 1);

    // Widen the search outward from the analytic solution; the required nudge is
    // normally 0, and never more than a few float ULPs.
    const H_STEP = 1e-4, S_STEP = 1e-6, B_STEP = 1e-6, RADIUS = 400;
    for (let ring = 0; ring <= RADIUS; ring++) {
        const offsets = ring === 0 ? [0] : [ring, -ring];
        for (const ds of offsets) {
            const sat = baseS + ds * S_STEP;
            if (sat < 0 || sat > 1) continue;
            for (const db of offsets) {
                const bri = baseB + db * B_STEP;
                if (bri < 0 || bri > 1) continue;
                for (const dh of offsets) {
                    const hue = baseH + dh * H_STEP;
                    if (sameRgb(zenRender(hue, sat, bri), target)) {
                        return {
                            exact: true,
                            reachable: true,
                            dotAngleDeg: round6(hue),
                            saturation: round6(sat),
                            brightness: round6(bri),
                            rendered: target,
                            nudges: { h: dh, s: ds, b: db }
                        };
                    }
                }
            }
        }
    }

    return {
        exact: false,
        reachable: true,
        reason: 'no exact solution found within the search radius',
        dotAngleDeg: round6(baseH),
        saturation: round6(baseS),
        brightness: round6(baseB),
        rendered: zenRender(baseH, baseS, baseB)
    };
}

// Newest existing candidate wins, so tinting with either backend is picked up.
function pickCssFile() {
    if (cssOverride) return cssOverride;
    let best = null;
    for (const p of CSS_CANDIDATES) {
        if (!fs.existsSync(p)) continue;
        const mtime = fs.statSync(p).mtimeMs;
        if (!best || mtime > best.mtime) best = { path: p, mtime };
    }
    return best ? best.path : null;
}

const DEFAULT_BOOST = {
    boostName: 'Matugen',
    dotAngleDeg: 0,
    dotPos: { x: 0.5, y: 0.5 },
    dotDistance: 0.5,
    secondaryDotAngleDegDelta: 0,
    secondaryDotPos: { x: 0.5, y: 0.5 },
    brightness: 0.5,
    saturation: 0.5,
    contrast: 0.5,
    fontFamily: '',
    enableColorBoost: true,
    smartInvert: false,
    autoTheme: false,
    textCaseOverride: 'none',
    sizeOverride: 1,
    zapSelectors: [],
    customCSS: '',
    changeWasMade: true
};

try {
    const cssFile = pickCssFile();
    if (!cssFile) {
        console.error(`Error: none of the theme CSS files exist:\n  ${CSS_CANDIDATES.join('\n  ')}`);
        process.exit(1);
    }
    const cssContent = fs.readFileSync(cssFile, 'utf8');

    const primaryHex = cssColor(cssContent, 'primary');
    const backgroundHex = cssColor(cssContent, 'background');
    const surfaceHex = cssColor(cssContent, 'surface');
    const onSurfaceHex = cssColor(cssContent, 'on_surface');

    if (!primaryHex || (!surfaceHex && !backgroundHex)) {
        console.error(`Could not extract '--primary' and '--surface'/'--background' from ${cssFile}.`);
        process.exit(1);
    }

    // Start from the existing boost so user fields (fontFamily, zapSelectors, ...)
    // survive; fall back to a full default set when the file is absent.
    let boostData;
    if (fs.existsSync(jsonOverride)) {
        try {
            boostData = JSON.parse(fs.readFileSync(jsonOverride, 'utf8'));
        } catch (e) {
            console.error(`Could not parse ${jsonOverride}: ${e.message}`);
            process.exit(1);
        }
    } else {
        boostData = { ...DEFAULT_BOOST, boostName: path.basename(jsonOverride, '.json') };
    }

    // Resolve the color exact mode aims at.
    const targetHex = cssColor(cssContent, targetVar);
    if (!targetHex) {
        console.error(`Could not extract '--${targetVar}' from ${cssFile}.`);
        process.exit(1);
    }

    const [pr, pg, pb] = hexToRgb255(primaryHex);
    const primaryHsl = rgbToHsl(pr, pg, pb);
    const primaryOk = oklabOf(primaryHex);
    const primaryChroma = oklabChroma(primaryOk);

    // 1. PRIMARY DOT COLOR
    // Zen renders the boost accent as hsl(dotAngleDeg, 1 - saturation, 0.1 + 0.9*brightness).
    // In 'exact' mode that mapping is inverted so the painted accent is byte-identical
    // to the source palette color. In 'perceptual' mode the previous tuning is kept:
    // hue from the accent, saturation from its perceptual chroma, lightness anchored
    // to the surface so the tint stays in the dark theme range.
    let exact = null;
    if (mode === 'exact') {
        exact = solveExact(targetHex);
        boostData.dotAngleDeg = exact.dotAngleDeg;
        boostData.saturation = exact.saturation;
        boostData.brightness = exact.brightness;
        // The picker ring radius is the closest visual analogue of chroma available.
        boostData.dotDistance = round4(clamp(Math.sqrt(primaryChroma / CHROMA_MAX), 0.05, 1));
    } else {
        boostData.dotAngleDeg = round4(primaryHsl.h);
        const renderedSat = clamp(Math.sqrt(primaryChroma / CHROMA_MAX), 0.05, 1);
        boostData.saturation = round4(clamp(1 - renderedSat, 0, 1));
        boostData.dotDistance = round4(renderedSat);

        // 2. LIGHTNESS: tint lightness tracks the surface tone (dark themes stay dark).
        // The surface's CIE L* tone is used directly as Zen's brightness. An earlier
        // floor of max(tone, 0.1) followed by (tone - 0.1) / 0.9 saturated at
        // brightness 0 for every Material You dark surface (all sit below L* 10),
        // so the lightness input carried no signal at all.
        const surfaceTone = ciedeTone(surfaceHex || backgroundHex);
        boostData.brightness = round4(clamp(surfaceTone / 100, 0, 1));
    }
    const renderedSat = boostData.dotDistance;
    const surfaceTone = ciedeTone(surfaceHex || backgroundHex);

    // 3. SECONDARY DOT: paired with on_surface, the theme's text color
    const [orr, org, orb] = hexToRgb255(onSurfaceHex || '#ffffff');
    const onSurfaceHsl = rgbToHsl(orr, org, orb);
    boostData.secondaryDotAngleDegDelta = round4(hueDelta(primaryHsl.h, onSurfaceHsl.h));
    const secondaryHue = (primaryHsl.h + boostData.secondaryDotAngleDegDelta + 360) % 360;

    // 4. CONTRAST: Zen's legibility control for the boosted page. Deliberately
    // left at Zen's own default; see the note on the --contrast option above.
    boostData.contrast = round4(contrast);

    // 5. DOT POSITIONS: place both dots on the picker ring at their true hues
    boostData.dotPos = pickerPos(boostData.dotAngleDeg, boostData.dotDistance, PICKER_RADIUS_RATIO);
    boostData.secondaryDotPos = pickerPos(secondaryHue, boostData.dotDistance, PICKER_RADIUS_RATIO);

    boostData.changeWasMade = true;

    // Self-check: replay Zen's own maths on the values actually being written.
    const verifyRgb = zenRender(boostData.dotAngleDeg, boostData.saturation, boostData.brightness);
    const verifyHex = '#' + verifyRgb.map((v) => v.toString(16).padStart(2, '0')).join('');
    const accuracy = {
        mode,
        target: `--${targetVar}`,
        targetHex,
        renderedHex: verifyHex,
        exact: verifyHex.toLowerCase() === targetHex.toLowerCase(),
        reason: exact && !exact.exact ? exact.reason : null
    };

    const summary = {
        source: cssFile,
        output: jsonOverride,
        dryRun,
        mode,
        accuracy,
        primaryHex,
        targetHex,
        surfaceHex: surfaceHex || backgroundHex,
        onSurfaceHex: onSurfaceHex || '#ffffff',
        primaryHsl: { h: round4(primaryHsl.h), s: round4(primaryHsl.s), l: round4(primaryHsl.l) },
        primaryChroma: round4(primaryChroma),
        surfaceTone: round4(surfaceTone),
        renderedSat: round4(renderedSat),
        rendered: {
            dotAngleDeg: boostData.dotAngleDeg,
            saturation: boostData.saturation,
            brightness: boostData.brightness,
            contrast: boostData.contrast
        },
        boost: boostData
    };

    if (!dryRun) {
        fs.mkdirSync(path.dirname(jsonOverride), { recursive: true });
        fs.writeFileSync(jsonOverride, JSON.stringify(boostData, null, 2), 'utf8');
    }

    if (jsonOnly) {
        process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
    } else if (!quiet) {
        console.log(JSON.stringify(summary, null, 2));
        console.log(dryRun ? 'Dry run - no file written.' : 'Matugen boost updated successfully.');
        console.log(`  Primary dot: hue ${boostData.dotAngleDeg}° (${primaryHex})`);
        console.log(`  Secondary dot: on_surface at ${boostData.secondaryDotAngleDegDelta}° delta`);
        console.log(`  Lightness: ${(0.1 + 0.9 * boostData.brightness).toFixed(3)} (surface tone ${(surfaceTone / 100).toFixed(3)})`);
        console.log(`  Saturation field: ${boostData.saturation} (renders ${(1 - boostData.saturation).toFixed(3)})`);
        console.log(`  Contrast: ${boostData.contrast} (Zen default 0.75; lower = duller text)`);
        console.log(`  Dot positions: primary (${boostData.dotPos.x}, ${boostData.dotPos.y}), secondary (${boostData.secondaryDotPos.x}, ${boostData.secondaryDotPos.y})`);
    }

} catch (error) {
    console.error("Pipeline error:", error.message);
    process.exit(1);
}
