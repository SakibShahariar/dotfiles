#!/usr/bin/env fish

# ============================================================
# Browser Benchmark
# Zen Browser vs Helium Browser
#
# Zen:
#   Zen -> Marionette :2828 -> geckodriver -> WebDriver -> Selenium
#
# Helium:
#   Helium -> Playwright
#
# Both browsers run headless.
# ============================================================


# ============================================================
# Configuration
# ============================================================

set -g SCRIPT_DIR (dirname (status --current-filename))
set -g PLAYWRIGHT_DIR "$SCRIPT_DIR/playwright"

set -g ZEN_BIN "/opt/zen/zen-bin"
set -g HELIUM_BIN "/usr/bin/helium"
set -g GECKODRIVER_BIN "$PLAYWRIGHT_DIR/node_modules/.bin/geckodriver"

set -g OUTPUT "$SCRIPT_DIR/results.csv"
set -g JS_FILE "$PLAYWRIGHT_DIR/benchmark.js"

set -g TESTS 5

# Zen 1.22.1b uses fixed Marionette port 2828.
set -g MARIONETTE_PORT 2828

set -g STARTUP_TIMEOUT 30
set -g POLL_INTERVAL 0.25

set -g URLS \
    "https://www.google.com" \
    "https://www.wikipedia.org" \
    "https://github.com" \
    "https://www.reddit.com" \
    "https://www.youtube.com"


# ============================================================
# Runtime state
# ============================================================

set -g ZEN_PID ""
set -g GECKO_PID ""

set -g ZEN_PROFILE ""
set -g ZEN_LOG ""
set -g GECKO_LOG ""

set -g WEBDRIVER_PORT ""


# ============================================================
# Cleanup
# ============================================================

function cleanup
    set -l exit_code $status

    if test -n "$GECKO_PID"
        if kill -0 $GECKO_PID 2>/dev/null
            kill $GECKO_PID 2>/dev/null
        end
    end

    if test -n "$ZEN_PID"
        if kill -0 $ZEN_PID 2>/dev/null
            kill $ZEN_PID 2>/dev/null
        end
    end

    sleep 0.5

    if test -n "$GECKO_PID"
        if kill -0 $GECKO_PID 2>/dev/null
            kill -9 $GECKO_PID 2>/dev/null
        end
    end

    if test -n "$ZEN_PID"
        if kill -0 $ZEN_PID 2>/dev/null
            kill -9 $ZEN_PID 2>/dev/null
        end
    end

    if test -n "$ZEN_PROFILE"
        if test -d "$ZEN_PROFILE"
            rm -rf "$ZEN_PROFILE"
        end
    end

    if test $exit_code -ne 0
        echo
        echo "Cleanup complete."
    end

    return $exit_code
end


function handle_interrupt
    echo
    echo "Interrupted. Cleaning up..."
    exit 130
end


trap handle_interrupt INT TERM
trap cleanup EXIT


# ============================================================
# Utility functions
# ============================================================

function command_exists
    command -q $argv[1]

    if test $status -ne 0
        echo "ERROR: Required command not found: $argv[1]" >&2
        return 1
    end
end


function get_free_port
    python3 -c '
import socket

s = socket.socket()
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
s.close()

print(port)
'
end


function port_is_open
    set -l port $argv[1]

    if test -z "$port"
        return 1
    end

    python3 -c '
import socket
import sys

port = int(sys.argv[1])

s = socket.socket()
s.settimeout(0.2)

try:
    result = s.connect_ex(("127.0.0.1", port))
finally:
    s.close()

sys.exit(0 if result == 0 else 1)
' "$port" >/dev/null 2>&1
end


function wait_for_port
    set -l port $argv[1]
    set -l timeout $argv[2]

    if test -z "$port"
        echo "ERROR: wait_for_port received an empty port." >&2
        return 1
    end

    if test -z "$timeout"
        echo "ERROR: wait_for_port received an empty timeout." >&2
        return 1
    end

    set -l elapsed 0

    while test $elapsed -lt $timeout
        if port_is_open "$port"
            return 0
        end

        sleep $POLL_INTERVAL
        set elapsed (math "$elapsed + $POLL_INTERVAL")
    end

    return 1
end


function wait_for_marionette
    set -l port $argv[1]
    set -l timeout $argv[2]

    echo "Waiting for Marionette on port $port..."

    if wait_for_port "$port" "$timeout"
        echo "Marionette is listening on port $port."
        return 0
    end

    return 1
end


function wait_for_webdriver
    set -l port $argv[1]
    set -l timeout $argv[2]

    echo "Waiting for WebDriver on port $port..."

    set -l elapsed 0

    while test $elapsed -lt $timeout
        set -l response (curl -s --max-time 1 "http://127.0.0.1:$port/status" 2>/dev/null)

        if test -n "$response"
            echo "$response" | grep -q '"ready"'

            if test $status -eq 0
                echo "WebDriver is ready."
                return 0
            end
        end

        sleep $POLL_INTERVAL
        set elapsed (math "$elapsed + $POLL_INTERVAL")
    end

    return 1
end


function stop_zen
    if test -n "$GECKO_PID"
        if kill -0 $GECKO_PID 2>/dev/null
            kill $GECKO_PID 2>/dev/null
        end
    end

    if test -n "$ZEN_PID"
        if kill -0 $ZEN_PID 2>/dev/null
            kill $ZEN_PID 2>/dev/null
        end
    end

    sleep 0.5

    if test -n "$GECKO_PID"
        if kill -0 $GECKO_PID 2>/dev/null
            kill -9 $GECKO_PID 2>/dev/null
        end
    end

    if test -n "$ZEN_PID"
        if kill -0 $ZEN_PID 2>/dev/null
            kill -9 $ZEN_PID 2>/dev/null
        end
    end

    set -g GECKO_PID ""
    set -g ZEN_PID ""

    if test -n "$ZEN_PROFILE"
        if test -d "$ZEN_PROFILE"
            rm -rf "$ZEN_PROFILE"
        end
    end

    set -g ZEN_PROFILE ""
end


# ============================================================
# Dependency checks
# ============================================================

echo
echo "========================================"
echo " Browser Benchmark"
echo "========================================"
echo

command_exists node; or exit 1
command_exists python3; or exit 1
command_exists curl; or exit 1

if not test -x "$ZEN_BIN"
    echo "ERROR: Zen binary not found:"
    echo "  $ZEN_BIN"
    exit 1
end

if not test -x "$HELIUM_BIN"
    echo "ERROR: Helium binary not found:"
    echo "  $HELIUM_BIN"
    exit 1
end

if not test -x "$GECKODRIVER_BIN"
    echo "ERROR: geckodriver not found:"
    echo "  $GECKODRIVER_BIN"
    exit 1
end

if not test -d "$PLAYWRIGHT_DIR/node_modules"
    echo "ERROR: Node dependencies are missing:"
    echo "  $PLAYWRIGHT_DIR/node_modules"
    exit 1
end


# ============================================================
# Versions
# ============================================================

set -l ZEN_VERSION ( "$ZEN_BIN" --version 2>/dev/null | head -n 1 )
set -l HELIUM_VERSION ( "$HELIUM_BIN" --version 2>/dev/null | head -n 1 )
set -l GECKO_VERSION ( "$GECKODRIVER_BIN" --version 2>&1 | grep -E 'geckodriver|Detected Geckodriver' | head -n 1 )

if test -z "$ZEN_VERSION"
    set ZEN_VERSION "Unknown"
end

if test -z "$HELIUM_VERSION"
    set HELIUM_VERSION "Unknown"
end

if test -z "$GECKO_VERSION"
    set GECKO_VERSION "Unknown"
end


echo "Zen:         $ZEN_BIN"
echo "Helium:      $HELIUM_BIN"
echo "Geckodriver: $GECKODRIVER_BIN"
echo
echo "Zen version:         $ZEN_VERSION"
echo "Helium version:      $HELIUM_VERSION"
echo "Geckodriver version: $GECKO_VERSION"
echo
echo "Tests per site:      $TESTS"
echo


# ============================================================
# Generate benchmark JavaScript
# ============================================================

mkdir -p "$PLAYWRIGHT_DIR"

printf '%s\n' \
'const { chromium } = require("playwright");' \
'const { Builder } = require("selenium-webdriver");' \
'' \
'const browserName = process.argv[2];' \
'const webdriverPort = Number(process.argv[3]);' \
'const urls = JSON.parse(process.argv[4]);' \
'const iterations = Number(process.argv[5]);' \
'const heliumBinary = process.argv[6] || "";' \
'' \
'function sleep(ms) {' \
'    return new Promise(resolve => setTimeout(resolve, ms));' \
'}' \
'' \
'function round(value) {' \
'    if (value === null || value === undefined || Number.isNaN(value)) {' \
'        return "";' \
'    }' \
'    return Math.round(value * 100) / 100;' \
'}' \
'' \
'function createLCPObserver() {' \
'    let lcp = null;' \
'' \
'    try {' \
'        const observer = new PerformanceObserver(list => {' \
'            const entries = list.getEntries();' \
'            if (entries.length > 0) {' \
'                lcp = entries[entries.length - 1].startTime;' \
'            }' \
'        });' \
'' \
'        observer.observe({ type: "largest-contentful-paint", buffered: true });' \
'' \
'        return {' \
'            get: () => lcp,' \
'            disconnect: () => observer.disconnect()' \
'        };' \
'    } catch (_) {' \
'        return {' \
'            get: () => null,' \
'            disconnect: () => {}' \
'        };' \
'    }' \
'}' \
'' \
'async function getZenMetrics(driver, lcpValue) {' \
'    return await driver.executeScript(`' \
'        const navigation = performance.getEntriesByType("navigation")[0];' \
'        const paints = performance.getEntriesByType("paint");' \
'        const fcp = paints.find(entry => entry.name === "first-contentful-paint");' \
'' \
'        return {' \
'            ttfb: navigation ? navigation.responseStart : null,' \
'            domContentLoaded: navigation ? navigation.domContentLoadedEventEnd : null,' \
'            load: navigation ? navigation.loadEventEnd : null,' \
'            fcp: fcp ? fcp.startTime : null,' \
'            lcp: arguments[0]' \
'        };' \
'    `, lcpValue);' \
'}' \
'' \
'async function runZen() {' \
'    const driver = await new Builder()' \
'        .forBrowser("firefox")' \
'        .usingServer(`http://127.0.0.1:${webdriverPort}`)' \
'        .build();' \
'' \
'    const results = [];' \
'' \
'    try {' \
'        for (const url of urls) {' \
'            for (let iteration = 1; iteration <= iterations; iteration++) {' \
'                let lcpObserver = null;' \
'                const start = performance.now();' \
'' \
'                try {' \
'                    lcpObserver = createLCPObserver();' \
'' \
'                    await driver.get(url);' \
'' \
'                    const navigationMs = performance.now() - start;' \
'' \
'                    await sleep(500);' \
'' \
'                    const lcpValue = lcpObserver.get();' \
'                    lcpObserver.disconnect();' \
'' \
'                    const metrics = await getZenMetrics(driver, lcpValue);' \
'' \
'                    const result = {' \
'                        browser: "Zen",' \
'                        url,' \
'                        iteration,' \
'                        navigation_ms: round(navigationMs),' \
'                        ttfb_ms: round(metrics.ttfb),' \
'                        domcontentloaded_ms: round(metrics.domContentLoaded),' \
'                        load_ms: round(metrics.load),' \
'                        fcp_ms: round(metrics.fcp),' \
'                        lcp_ms: round(metrics.lcp),' \
'                        status: "ok",' \
'                        error: ""' \
'                    };' \
'' \
'                    results.push(result);' \
'                    console.log(JSON.stringify(result));' \
'                } catch (error) {' \
'                    if (lcpObserver) {' \
'                        lcpObserver.disconnect();' \
'                    }' \
'' \
'                    const result = {' \
'                        browser: "Zen",' \
'                        url,' \
'                        iteration,' \
'                        navigation_ms: "",' \
'                        ttfb_ms: "",' \
'                        domcontentloaded_ms: "",' \
'                        load_ms: "",' \
'                        fcp_ms: "",' \
'                        lcp_ms: "",' \
'                        status: "error",' \
'                        error: String(error.message || error)' \
'                    };' \
'' \
'                    results.push(result);' \
'                    console.log(JSON.stringify(result));' \
'                }' \
'            }' \
'        }' \
'    } finally {' \
'        await driver.quit().catch(() => {});' \
'    }' \
'' \
'    return results;' \
'}' \
'' \
'async function getHeliumMetrics(page, lcpValue) {' \
'    return await page.evaluate((lcp) => {' \
'        const navigation = performance.getEntriesByType("navigation")[0];' \
'        const paints = performance.getEntriesByType("paint");' \
'        const fcp = paints.find(entry => entry.name === "first-contentful-paint");' \
'' \
'        return {' \
'            ttfb: navigation ? navigation.responseStart : null,' \
'            domContentLoaded: navigation ? navigation.domContentLoadedEventEnd : null,' \
'            load: navigation ? navigation.loadEventEnd : null,' \
'            fcp: fcp ? fcp.startTime : null,' \
'            lcp' \
'        };' \
'    }, lcpValue);' \
'}' \
'' \
'async function runHelium() {' \
'    const browser = await chromium.launch({' \
'        executablePath: heliumBinary,' \
'        headless: true,' \
'        args: [' \
'            "--disable-gpu",' \
'            "--no-sandbox"' \
'        ]' \
'    });' \
'' \
'    const context = await browser.newContext({' \
'        viewport: { width: 1280, height: 800 },' \
'        ignoreHTTPSErrors: true' \
'    });' \
'' \
'    const page = await context.newPage();' \
'    const results = [];' \
'' \
'    try {' \
'        for (const url of urls) {' \
'            for (let iteration = 1; iteration <= iterations; iteration++) {' \
'                let lcpValue = null;' \
'' \
'                const lcpHandle = await page.evaluateHandle(() => {' \
'                    let value = null;' \
'' \
'                    try {' \
'                        const observer = new PerformanceObserver(list => {' \
'                            const entries = list.getEntries();' \
'                            if (entries.length > 0) {' \
'                                value = entries[entries.length - 1].startTime;' \
'                            }' \
'                        });' \
'                        observer.observe({ type: "largest-contentful-paint", buffered: true });' \
'                        window.__benchmarkLCPObserver = observer;' \
'                    } catch (_) {}' \
'' \
'                    return true;' \
'                });' \
'' \
'                await lcpHandle.dispose().catch(() => {});' \
'' \
'                const start = performance.now();' \
'' \
'                try {' \
'                    await page.goto(url, {' \
'                        waitUntil: "load",' \
'                        timeout: 60000' \
'                    });' \
'' \
'                    const navigationMs = performance.now() - start;' \
'' \
'                    await sleep(500);' \
'' \
'                    lcpValue = await page.evaluate(() => {' \
'                        try {' \
'                            const entries = performance.getEntriesByType("largest-contentful-paint");' \
'                            return entries.length ? entries[entries.length - 1].startTime : null;' \
'                        } catch (_) {' \
'                            return null;' \
'                        }' \
'                    });' \
'' \
'                    const metrics = await getHeliumMetrics(page, lcpValue);' \
'' \
'                    await page.evaluate(() => {' \
'                        if (window.__benchmarkLCPObserver) {' \
'                            window.__benchmarkLCPObserver.disconnect();' \
'                            delete window.__benchmarkLCPObserver;' \
'                        }' \
'                    });' \
'' \
'                    const result = {' \
'                        browser: "Helium",' \
'                        url,' \
'                        iteration,' \
'                        navigation_ms: round(navigationMs),' \
'                        ttfb_ms: round(metrics.ttfb),' \
'                        domcontentloaded_ms: round(metrics.domContentLoaded),' \
'                        load_ms: round(metrics.load),' \
'                        fcp_ms: round(metrics.fcp),' \
'                        lcp_ms: round(metrics.lcp),' \
'                        status: "ok",' \
'                        error: ""' \
'                    };' \
'' \
'                    results.push(result);' \
'                    console.log(JSON.stringify(result));' \
'                } catch (error) {' \
'                    await page.evaluate(() => {' \
'                        if (window.__benchmarkLCPObserver) {' \
'                            window.__benchmarkLCPObserver.disconnect();' \
'                            delete window.__benchmarkLCPObserver;' \
'                        }' \
'                    }).catch(() => {});' \
'' \
'                    const result = {' \
'                        browser: "Helium",' \
'                        url,' \
'                        iteration,' \
'                        navigation_ms: "",' \
'                        ttfb_ms: "",' \
'                        domcontentloaded_ms: "",' \
'                        load_ms: "",' \
'                        fcp_ms: "",' \
'                        lcp_ms: "",' \
'                        status: "error",' \
'                        error: String(error.message || error)' \
'                    };' \
'' \
'                    results.push(result);' \
'                    console.log(JSON.stringify(result));' \
'                }' \
'            }' \
'        }' \
'    } finally {' \
'        await page.close().catch(() => {});' \
'        await context.close().catch(() => {});' \
'        await browser.close().catch(() => {});' \
'    }' \
'' \
'    return results;' \
'}' \
'' \
'(async () => {' \
'    try {' \
'        if (browserName === "zen") {' \
'            await runZen();' \
'        } else if (browserName === "helium") {' \
'            await runHelium();' \
'        } else {' \
'            throw new Error(`Unknown browser: ${browserName}`);' \
'        }' \
'    } catch (error) {' \
'        console.error(error.stack || error);' \
'        process.exit(1);' \
'    }' \
'})();' \
> "$JS_FILE"


# ============================================================
# Prepare CSV
# ============================================================

printf '%s\n' \
'browser,url,iteration,navigation_ms,ttfb_ms,domcontentloaded_ms,load_ms,fcp_ms,lcp_ms,status,error' \
> "$OUTPUT"


# ============================================================
# URL JSON
# ============================================================

set -l URL_JSON (
    printf '%s\n' $URLS |
    python3 -c '
import json
import sys

print(json.dumps([
    line.strip()
    for line in sys.stdin
    if line.strip()
]))
'
)


# ============================================================
# Temporary raw result files
# ============================================================

set -l ZEN_RAW "$SCRIPT_DIR/.zen-results.jsonl"
set -l HELIUM_RAW "$SCRIPT_DIR/.helium-results.jsonl"

rm -f "$ZEN_RAW" "$HELIUM_RAW"


# ============================================================
# ZEN
# ============================================================

echo
echo "========================================"
echo " Testing ZEN"
echo "========================================"
echo


if port_is_open "$MARIONETTE_PORT"
    echo "ERROR: Port $MARIONETTE_PORT is already in use."
    echo
    echo "Check it with:"
    echo "  ss -ltnp | grep ':$MARIONETTE_PORT'"
    echo
    echo "The benchmark will not kill an unrelated process."
    exit 1
end


set -g WEBDRIVER_PORT (get_free_port)

set -g ZEN_PROFILE "/tmp/zen-benchmark-"(random)"-"(date +%s)
set -g ZEN_LOG "$SCRIPT_DIR/zen.log"
set -g GECKO_LOG "$SCRIPT_DIR/geckodriver.log"

mkdir -p "$ZEN_PROFILE"


echo "Zen profile:    $ZEN_PROFILE"
echo "Marionette:     $MARIONETTE_PORT"
echo "WebDriver:      $WEBDRIVER_PORT"
echo

echo "Starting Zen..."


"$ZEN_BIN" \
    -headless \
    -new-instance \
    -no-remote \
    -marionette \
    -profile "$ZEN_PROFILE" \
    >"$ZEN_LOG" 2>&1 &

set -g ZEN_PID $last_pid

echo "Zen PID:        $ZEN_PID"


if not wait_for_marionette "$MARIONETTE_PORT" "$STARTUP_TIMEOUT"
    echo
    echo "ERROR: Zen did not start Marionette within $STARTUP_TIMEOUT seconds."
    echo
    echo "Zen log:"
    tail -n 50 "$ZEN_LOG"
    exit 1
end


echo
echo "Starting geckodriver..."

"$GECKODRIVER_BIN" \
    --connect-existing \
    --marionette-host 127.0.0.1 \
    --marionette-port "$MARIONETTE_PORT" \
    --host 127.0.0.1 \
    --port "$WEBDRIVER_PORT" \
    --log warn \
    >"$GECKO_LOG" 2>&1 &

set -g GECKO_PID $last_pid

echo "Geckodriver PID: $GECKO_PID"


if not wait_for_webdriver "$WEBDRIVER_PORT" "$STARTUP_TIMEOUT"
    echo
    echo "ERROR: geckodriver did not become ready within $STARTUP_TIMEOUT seconds."
    echo
    echo "Geckodriver log:"
    tail -n 50 "$GECKO_LOG"
    exit 1
end


echo
echo "Running Zen benchmark..."
echo


node "$JS_FILE" \
    zen \
    "$WEBDRIVER_PORT" \
    "$URL_JSON" \
    "$TESTS" \
    >"$ZEN_RAW"

set -l ZEN_STATUS $status


if test -f "$ZEN_RAW"
    cat "$ZEN_RAW"
end


if test $ZEN_STATUS -ne 0
    echo
    echo "ERROR: Zen benchmark failed."
    echo
    echo "Geckodriver log:"
    tail -n 50 "$GECKO_LOG"
    exit 1
end


python3 -c '
import csv
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path, encoding="utf-8") as source, \
     open(output_path, "a", newline="", encoding="utf-8") as target:

    writer = csv.writer(target)

    for line in source:
        line = line.strip()

        if not line:
            continue

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        writer.writerow([
            data.get("browser", ""),
            data.get("url", ""),
            data.get("iteration", ""),
            data.get("navigation_ms", ""),
            data.get("ttfb_ms", ""),
            data.get("domcontentloaded_ms", ""),
            data.get("load_ms", ""),
            data.get("fcp_ms", ""),
            data.get("lcp_ms", ""),
            data.get("status", ""),
            data.get("error", "")
        ])
' "$ZEN_RAW" "$OUTPUT"


echo
echo "Zen benchmark complete."
echo "Stopping Zen..."

stop_zen


# ============================================================
# HELIUM
# ============================================================

echo
echo "========================================"
echo " Testing HELIUM"
echo "========================================"
echo

echo "Running Helium benchmark..."
echo


node "$JS_FILE" \
    helium \
    0 \
    "$URL_JSON" \
    "$TESTS" \
    "$HELIUM_BIN" \
    >"$HELIUM_RAW"

set -l HELIUM_STATUS $status


if test -f "$HELIUM_RAW"
    cat "$HELIUM_RAW"
end


if test $HELIUM_STATUS -ne 0
    echo
    echo "ERROR: Helium benchmark failed."
    exit 1
end


python3 -c '
import csv
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path, encoding="utf-8") as source, \
     open(output_path, "a", newline="", encoding="utf-8") as target:

    writer = csv.writer(target)

    for line in source:
        line = line.strip()

        if not line:
            continue

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        writer.writerow([
            data.get("browser", ""),
            data.get("url", ""),
            data.get("iteration", ""),
            data.get("navigation_ms", ""),
            data.get("ttfb_ms", ""),
            data.get("domcontentloaded_ms", ""),
            data.get("load_ms", ""),
            data.get("fcp_ms", ""),
            data.get("lcp_ms", ""),
            data.get("status", ""),
            data.get("error", "")
        ])
' "$HELIUM_RAW" "$OUTPUT"


# ============================================================
# Remove temporary files
# ============================================================

rm -f "$ZEN_RAW" "$HELIUM_RAW"


# ============================================================
# Summary
# ============================================================

echo
echo "========================================"
echo " Benchmark complete"
echo "========================================"
echo

echo "Results:"
echo "  $OUTPUT"
echo


python3 -c '
import csv
import statistics
import sys
from collections import defaultdict

path = sys.argv[1]

rows = []

with open(path, newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if row["status"] == "ok":
            rows.append(row)

metrics = [
    ("navigation_ms", "Navigation"),
    ("ttfb_ms", "TTFB"),
    ("domcontentloaded_ms", "DOMContentLoaded"),
    ("load_ms", "Load"),
    ("fcp_ms", "FCP"),
    ("lcp_ms", "LCP"),
]

grouped = defaultdict(lambda: defaultdict(list))

for row in rows:
    browser = row["browser"]

    for key, _ in metrics:
        value = row.get(key, "")

        if value:
            try:
                grouped[browser][key].append(float(value))
            except ValueError:
                pass

print("========================================")
print(" Summary")
print("========================================")
print()

for browser in ["Zen", "Helium"]:
    print(browser)
    print("----------------------------------------")

    for key, label in metrics:
        values = grouped[browser][key]

        if not values:
            print(f"{label:20} N/A")
            continue

        mean = statistics.mean(values)
        median = statistics.median(values)

        print(
            f"{label:20} "
            f"mean {mean:8.2f} ms   "
            f"median {median:8.2f} ms"
        )

    print()

print("Successful measurements:", len(rows))
print("Expected measurements:  ", len(rows) if False else 50)
' "$OUTPUT"


echo
echo "Logs:"
echo "  Zen:         $SCRIPT_DIR/zen.log"
echo "  Geckodriver: $SCRIPT_DIR/geckodriver.log"
echo







