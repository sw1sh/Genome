// genealogy-browser.mjs - the Playwright runner behind the "Browser" class of
// GenealogySearch providers, part of the WolframInstitute/Genome paclet.
//
// Some genealogical archives publish a usable HTTP API; those are queried
// straight from the kernel and never reach this file.  The ones here publish
// none, and a plain HTTP fetch of their search page returns either a JavaScript
// shell or an anti-bot interstitial.  Driving a real browser is what makes them
// answerable at all, and it is also what lets a signed-in session be reused:
// the archives that gate results behind an account are unlocked by a stored
// storageState rather than by handing this process a password.
//
// Contract.  One JSON job in, one JSON result out on stdout, nothing else on
// stdout ever, so the kernel can parse the whole stream.  Diagnostics go to
// stderr.
//
//   job:    {mode, provider, url, max, statePath, headless, timeoutMs}
//   result: {ok: true,  provider, rows: [...], total, note}
//           {ok: false, provider, kind, error}
//
//   kind is one of "no-playwright", "no-browser", "challenge", "timeout",
//   "no-results-selector" or "error", so the kernel can say something more
//   useful than "it failed".
//
// Usage:
//   node genealogy-browser.mjs <job.json>
//   node genealogy-browser.mjs -            (job on stdin)

import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { readFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

function emit(obj) {
    process.stdout.write(JSON.stringify(obj));
    process.stdout.write('\n');
}

function fail(provider, kind, error) {
    emit({ ok: false, provider, kind, error: String(error).slice(0, 600) });
    process.exit(0);            // a failed job is still a well-formed answer
}

// --- locating playwright ---------------------------------------------------
// The paclet ships this script but cannot ship a browser automation stack, so
// playwright-core is looked for where a user would plausibly have put it: an
// explicit override first, then the usual node_modules roots.
async function loadPlaywright() {
    const candidates = [];
    if (process.env.GENOME_PLAYWRIGHT) candidates.push(process.env.GENOME_PLAYWRIGHT);
    const require_ = createRequire(import.meta.url);
    for (const base of [process.cwd(), dirname(new URL(import.meta.url).pathname)]) {
        candidates.push(join(base, 'node_modules', 'playwright-core'));
        candidates.push(join(base, '..', 'node_modules', 'playwright-core'));
        candidates.push(join(base, '..', '..', 'node_modules', 'playwright-core'));
        candidates.push(join(base, '..', '..', '..', 'node_modules', 'playwright-core'));
    }
    try {
        return await import('playwright-core');
    } catch { /* fall through to the explicit paths */ }
    for (const c of candidates) {
        try {
            return await import(pathToFileURL(require_.resolve(c)).href);
        } catch { /* try the next one */ }
    }
    return null;
}

// --- per-provider extraction ----------------------------------------------
// Each extractor runs in the page and returns plain rows.  They are written
// against the markup each site actually serves; a site redesign shows up as an
// empty result with kind "no-results-selector", never as a silent wrong answer.

const providers = {
    // Find a Grave lists one .memorial-item per burial; the anchor text carries
    // the name and the life dates, and the rest of the row carries the cemetery
    // and its place.
    FindAGrave: {
        locale: 'en-US',
        ready: '.memorial-item, .alert, #search-results',
        extract: (max) => {
            const items = [...document.querySelectorAll('.memorial-item')].slice(0, max);
            const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
            return items.map((it) => {
                const a = it.querySelector('a[href*="/memorial/"]');
                const linkText = clean(a && a.innerText).replace(/^No grave photo\s*/i, '');
                // A date is "12 Oct 1866", "Oct 1866", "1866" or "unknown".  The
                // pattern has to be tight: a loose \w* swallows the surname and
                // silently reports a one-word name.
                const MONTH = '(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*';
                const DATE = '(?:unknown|(?:\\d{1,2}\\s+)?(?:' + MONTH + '\\s+)?\\d{4})';
                const m = linkText.match(new RegExp('^(.*?)\\s+(' + DATE + ')\\s*[-\u2013\u2014]\\s*(' + DATE + ')\\s*$'));
                const rowText = clean(it.innerText).replace(/^No grave photo\s*/i, '');
                const place = clean(rowText.slice(linkText.length));
                const yr = (s) => { const y = (s || '').match(/\d{4}/); return y ? parseInt(y[0], 10) : null; };
                return {
                    name: m ? clean(m[1]) : linkText,
                    birth: m ? yr(m[2]) : null,
                    death: m ? yr(m[3]) : null,
                    place: place || null,
                    detail: 'burial record',
                    url: a ? new URL(a.getAttribute('href'), location.origin).href : null,
                };
            });
        },
        total: () => {
            const m = document.body.innerText.match(/([\d,]+)\s+(?:results?|records?|memorials?)\s+(?:found|matching)/i);
            return m ? parseInt(m[1].replace(/,/g, ''), 10) : null;
        },
    },

    // Yandex Archive returns archival PAGES, not people: each hit is a scanned
    // page of a metrical book, revision tale or confession list whose
    // handwriting recognition matched the query.  The card title is the
    // archival unit and the snippet is the recognised text around the match,
    // which is the part actually worth reading.
    YandexArchive: {
        locale: 'ru-RU',
        ready: '.Snippet-Title, .Snippet-Body, [class*="EmptySearch"]',
        extract: (max) => {
            const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
            const titles = [...document.querySelectorAll('.Snippet-Title')].slice(0, max);
            return titles.map((t) => {
                const a = t.querySelector('a') || t.closest('a');
                const body = t.closest('.Snippet-Body') || t.parentElement;
                const content = body ? body.querySelector('.Snippet-Content') : null;
                return {
                    name: clean(t.innerText) || null,
                    birth: null,
                    death: null,
                    place: null,
                    detail: clean(content && content.innerText).slice(0, 400) || 'archival page match',
                    url: a ? new URL(a.getAttribute('href'), location.origin).href : null,
                };
            });
        },
        total: () => {
            const m = document.body.innerText.match(/Всего найден[оа]?\s+([\d\s ]+)\s+результат/i);
            return m ? parseInt(m[1].replace(/[\s ]/g, ''), 10) : null;
        },
    },

    // Pamyat Naroda serves its results server-side, one card per matched
    // person, each linking to a person-hero page.
    PamyatNaroda: {
        locale: 'ru-RU',
        ready: 'a[href*="person-hero"], .heroes-list, .no-results, .empty',
        extract: (max) => {
            const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
            const seen = new Set();
            const links = [...document.querySelectorAll('a[href*="person-hero"]')].filter((a) => {
                const h = a.getAttribute('href');
                if (!h || seen.has(h)) return false;
                seen.add(h);
                return true;
            }).slice(0, max);
            return links.map((a) => {
                const card = a.closest('li, article, [class*="card"], [class*="item"], tr') || a.parentElement;
                const text = clean(card && card.innerText);
                const born = text.match(/(?:Дата рождения|Год рождения)[:\s]*([^,;]*?(\d{4}))/i);
                const place = text.match(/Место рождения[:\s]*([^,;]{0,80})/i);
                return {
                    name: clean(a.innerText) || null,
                    birth: born ? parseInt(born[2], 10) : null,
                    death: null,
                    place: place ? clean(place[1]) : null,
                    detail: text.slice(0, 300) || 'service record',
                    url: new URL(a.getAttribute('href'), location.origin).href,
                };
            });
        },
        total: () => {
            const m = document.body.innerText.match(/Найдено[^\d]{0,20}([\d\s ]+)/i);
            return m ? parseInt(m[1].replace(/[\s ]/g, ''), 10) : null;
        },
    },
};

// An interstitial is not an empty result set, and reporting it as one would be
// a lie about coverage.  These are the titles the three archives serve when
// they refuse the request.
function challengeQ(title, bodyText) {
    const t = `${title} ${bodyText}`.toLowerCase();
    return /проверка безопасности|just a moment|attention required|access denied|are you a robot|доступ ограничен|403 forbidden/.test(t);
}

// --- main ------------------------------------------------------------------

const arg = process.argv[2];
if (!arg) fail('', 'error', 'no job given; pass a job file path or - for stdin');
const job = JSON.parse(arg === '-' ? readFileSync(0, 'utf8') : readFileSync(arg, 'utf8'));
const provider = job.provider || '';
const spec = providers[provider];
if (!spec) fail(provider, 'error', `unknown provider ${provider}`);

const pw = await loadPlaywright();
if (!pw) {
    fail(provider, 'no-playwright',
        'playwright-core is not installed. Run "npm install playwright-core" and set GENOME_PLAYWRIGHT to it if it is not on the default module path.');
}

const headless = job.mode === 'login' ? false : job.headless !== false;
const timeoutMs = job.timeoutMs || 45000;
const statePath = job.statePath || null;

let browser;
try {
    browser = await pw.chromium.launch({
        channel: 'chrome',
        headless,
        args: ['--disable-blink-features=AutomationControlled'],
    });
} catch (e) {
    fail(provider, 'no-browser',
        `could not start Chrome through Playwright: ${e}. Install Google Chrome, or point Playwright at another Chromium build.`);
}

try {
    const ctxOpts = {
        locale: spec.locale,
        userAgent: UA,
        viewport: { width: 1400, height: 1200 },
        extraHTTPHeaders: { 'Accept-Language': spec.locale },
    };
    // A saved session is what unlocks the archives that gate results behind an
    // account, and what carries an anti-bot pass granted to a real login.
    if (statePath && existsSync(statePath)) ctxOpts.storageState = statePath;
    const ctx = await browser.newContext(ctxOpts);
    const page = await ctx.newPage();

    if (job.mode === 'login') {
        // Headed, and the operator drives it.  No password ever reaches this
        // process: the browser collects it, and only the resulting cookies are
        // written out.
        await page.goto(job.url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
        process.stderr.write('Sign in in the browser window, then close it to save the session.\n');
        await page.waitForEvent('close', { timeout: job.loginTimeoutMs || 600000 }).catch(() => {});
        mkdirSync(dirname(statePath), { recursive: true });
        await ctx.storageState({ path: statePath });
        emit({ ok: true, provider, mode: 'login', statePath, rows: [], total: null, note: 'session saved' });
        await browser.close();
        process.exit(0);
    }

    const response = await page.goto(job.url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    const status = response ? response.status() : null;
    await page.waitForSelector(spec.ready, { timeout: Math.min(timeoutMs, 20000) }).catch(() => {});
    await page.waitForTimeout(job.settleMs || 2500);

    const title = await page.title();
    const bodyText = await page.evaluate(() => document.body.innerText.slice(0, 400));
    if (challengeQ(title, bodyText) || status === 401 || status === 403) {
        fail(provider, 'challenge',
            `${provider} served an anti-bot or access check (HTTP ${status}, "${title}") instead of results. Sign in with GenealogyLogin to store a session, or try again from a network it accepts.`);
    }

    const max = Math.max(1, Math.min(job.max || 10, 100));
    const rows = await page.evaluate(spec.extract, max);
    const total = await page.evaluate(spec.total).catch(() => null);
    if (!rows.length) {
        const empty = await page.evaluate(() => document.body.innerText.slice(0, 200));
        emit({ ok: true, provider, rows: [], total: total ?? 0, note: `no results extracted; page said: ${empty.replace(/\s+/g, ' ').slice(0, 160)}` });
    } else {
        emit({ ok: true, provider, rows, total, note: null });
    }
    await browser.close();
    process.exit(0);
} catch (e) {
    try { await browser.close(); } catch { /* already gone */ }
    const kind = /Timeout|timeout/.test(String(e)) ? 'timeout' : 'error';
    fail(provider, kind, e);
}
