const { chromium } = require("playwright");
const { Builder } = require("selenium-webdriver");

const browserName = process.argv[2];
const webdriverPort = Number(process.argv[3]);
const urls = JSON.parse(process.argv[4]);
const iterations = Number(process.argv[5]);
const heliumBinary = process.argv[6] || "";

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function round(value) {
    if (value === null || value === undefined || Number.isNaN(value)) {
        return "";
    }
    return Math.round(value * 100) / 100;
}

function createLCPObserver() {
    let lcp = null;

    try {
        const observer = new PerformanceObserver(list => {
            const entries = list.getEntries();
            if (entries.length > 0) {
                lcp = entries[entries.length - 1].startTime;
            }
        });

        observer.observe({ type: "largest-contentful-paint", buffered: true });

        return {
            get: () => lcp,
            disconnect: () => observer.disconnect()
        };
    } catch (_) {
        return {
            get: () => null,
            disconnect: () => {}
        };
    }
}

async function getZenMetrics(driver, lcpValue) {
    return await driver.executeScript(`
        const navigation = performance.getEntriesByType("navigation")[0];
        const paints = performance.getEntriesByType("paint");
        const fcp = paints.find(entry => entry.name === "first-contentful-paint");

        return {
            ttfb: navigation ? navigation.responseStart : null,
            domContentLoaded: navigation ? navigation.domContentLoadedEventEnd : null,
            load: navigation ? navigation.loadEventEnd : null,
            fcp: fcp ? fcp.startTime : null,
            lcp: arguments[0]
        };
    `, lcpValue);
}

async function runZen() {
    const driver = await new Builder()
        .forBrowser("firefox")
        .usingServer(`http://127.0.0.1:${webdriverPort}`)
        .build();

    const results = [];

    try {
        for (const url of urls) {
            for (let iteration = 1; iteration <= iterations; iteration++) {
                let lcpObserver = null;
                const start = performance.now();

                try {
                    lcpObserver = createLCPObserver();

                    await driver.get(url);

                    const navigationMs = performance.now() - start;

                    await sleep(500);

                    const lcpValue = lcpObserver.get();
                    lcpObserver.disconnect();

                    const metrics = await getZenMetrics(driver, lcpValue);

                    const result = {
                        browser: "Zen",
                        url,
                        iteration,
                        navigation_ms: round(navigationMs),
                        ttfb_ms: round(metrics.ttfb),
                        domcontentloaded_ms: round(metrics.domContentLoaded),
                        load_ms: round(metrics.load),
                        fcp_ms: round(metrics.fcp),
                        lcp_ms: round(metrics.lcp),
                        status: "ok",
                        error: ""
                    };

                    results.push(result);
                    console.log(JSON.stringify(result));
                } catch (error) {
                    if (lcpObserver) {
                        lcpObserver.disconnect();
                    }

                    const result = {
                        browser: "Zen",
                        url,
                        iteration,
                        navigation_ms: "",
                        ttfb_ms: "",
                        domcontentloaded_ms: "",
                        load_ms: "",
                        fcp_ms: "",
                        lcp_ms: "",
                        status: "error",
                        error: String(error.message || error)
                    };

                    results.push(result);
                    console.log(JSON.stringify(result));
                }
            }
        }
    } finally {
        await driver.quit().catch(() => {});
    }

    return results;
}

async function getHeliumMetrics(page, lcpValue) {
    return await page.evaluate((lcp) => {
        const navigation = performance.getEntriesByType("navigation")[0];
        const paints = performance.getEntriesByType("paint");
        const fcp = paints.find(entry => entry.name === "first-contentful-paint");

        return {
            ttfb: navigation ? navigation.responseStart : null,
            domContentLoaded: navigation ? navigation.domContentLoadedEventEnd : null,
            load: navigation ? navigation.loadEventEnd : null,
            fcp: fcp ? fcp.startTime : null,
            lcp
        };
    }, lcpValue);
}

async function runHelium() {
    const browser = await chromium.launch({
        executablePath: heliumBinary,
        headless: true,
        args: [
            "--disable-gpu",
            "--no-sandbox"
        ]
    });

    const context = await browser.newContext({
        viewport: { width: 1280, height: 800 },
        ignoreHTTPSErrors: true
    });

    const page = await context.newPage();
    const results = [];

    try {
        for (const url of urls) {
            for (let iteration = 1; iteration <= iterations; iteration++) {
                let lcpValue = null;

                const lcpHandle = await page.evaluateHandle(() => {
                    let value = null;

                    try {
                        const observer = new PerformanceObserver(list => {
                            const entries = list.getEntries();
                            if (entries.length > 0) {
                                value = entries[entries.length - 1].startTime;
                            }
                        });
                        observer.observe({ type: "largest-contentful-paint", buffered: true });
                        window.__benchmarkLCPObserver = observer;
                    } catch (_) {}

                    return true;
                });

                await lcpHandle.dispose().catch(() => {});

                const start = performance.now();

                try {
                    await page.goto(url, {
                        waitUntil: "load",
                        timeout: 60000
                    });

                    const navigationMs = performance.now() - start;

                    await sleep(500);

                    lcpValue = await page.evaluate(() => {
                        try {
                            const entries = performance.getEntriesByType("largest-contentful-paint");
                            return entries.length ? entries[entries.length - 1].startTime : null;
                        } catch (_) {
                            return null;
                        }
                    });

                    const metrics = await getHeliumMetrics(page, lcpValue);

                    await page.evaluate(() => {
                        if (window.__benchmarkLCPObserver) {
                            window.__benchmarkLCPObserver.disconnect();
                            delete window.__benchmarkLCPObserver;
                        }
                    });

                    const result = {
                        browser: "Helium",
                        url,
                        iteration,
                        navigation_ms: round(navigationMs),
                        ttfb_ms: round(metrics.ttfb),
                        domcontentloaded_ms: round(metrics.domContentLoaded),
                        load_ms: round(metrics.load),
                        fcp_ms: round(metrics.fcp),
                        lcp_ms: round(metrics.lcp),
                        status: "ok",
                        error: ""
                    };

                    results.push(result);
                    console.log(JSON.stringify(result));
                } catch (error) {
                    await page.evaluate(() => {
                        if (window.__benchmarkLCPObserver) {
                            window.__benchmarkLCPObserver.disconnect();
                            delete window.__benchmarkLCPObserver;
                        }
                    }).catch(() => {});

                    const result = {
                        browser: "Helium",
                        url,
                        iteration,
                        navigation_ms: "",
                        ttfb_ms: "",
                        domcontentloaded_ms: "",
                        load_ms: "",
                        fcp_ms: "",
                        lcp_ms: "",
                        status: "error",
                        error: String(error.message || error)
                    };

                    results.push(result);
                    console.log(JSON.stringify(result));
                }
            }
        }
    } finally {
        await page.close().catch(() => {});
        await context.close().catch(() => {});
        await browser.close().catch(() => {});
    }

    return results;
}

(async () => {
    try {
        if (browserName === "zen") {
            await runZen();
        } else if (browserName === "helium") {
            await runHelium();
        } else {
            throw new Error(`Unknown browser: ${browserName}`);
        }
    } catch (error) {
        console.error(error.stack || error);
        process.exit(1);
    }
})();
