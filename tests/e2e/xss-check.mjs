import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

async function loadPlaywright() {
  for (const pkg of ['playwright', 'playwright-core']) {
    try {
      const mod = await import(pkg);
      return mod.chromium ? mod : mod.default;
    } catch {
      // try next
    }
  }
  const fallback = process.env.PLAYWRIGHT_MODULE_PATH;
  if (fallback && existsSync(fallback)) {
    const mod = await import(pathToFileURL(fallback).href);
    return mod.chromium ? mod : mod.default;
  }
  throw new Error('Could not import playwright or playwright-core. Install playwright or set PLAYWRIGHT_MODULE_PATH.');
}

function findSystemBrowser() {
  const candidates = [
    process.env.PLAYWRIGHT_CHROME_PATH,
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/google-chrome',
  ].filter(Boolean);
  return candidates.find((p) => existsSync(p));
}

async function auditFile(browser, htmlPath, label, interactiveMain) {
  const context = await browser.newContext();
  const page = await context.newPage();
  const dialogs = [];
  const pageErrors = [];

  page.on('dialog', async (d) => {
    dialogs.push(`${d.type()}: ${d.message()}`);
    await d.dismiss();
  });
  page.on('pageerror', (err) => {
    pageErrors.push(err.message);
  });

  const url = pathToFileURL(path.resolve(htmlPath)).href;
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(300);

  if (interactiveMain) {
    // Switch to Findings, License ROI, and Roadmap tabs so all innerHTML renders run
    for (const btnId of ['navAllFindings', 'navRoi', 'navRoadmap']) {
      const btn = page.locator(`#${btnId}`);
      if (await btn.count()) {
        await btn.click();
        await page.waitForTimeout(150);
      }
    }
    await page.locator('#navAllFindings').click();
    await page.waitForTimeout(150);
    // Open all <details> elements to verify RemediationTr/Result/Description rendering
    await page.evaluate(() => {
      document.querySelectorAll('details').forEach((d) => { d.open = true; });
    });
    await page.waitForTimeout(150);
  }

  const domAudit = await page.evaluate((isMain) => {
    const evilNodes = document.querySelectorAll('[onerror],[onload],[onmouseover]');
    const findingCount = isMain
      ? document.querySelectorAll('.finding').length
      : document.querySelectorAll('table:nth-of-type(2) tbody tr').length;
    const bodyText = document.body ? document.body.innerText : '';
    const actionTableText = !isMain && document.querySelector('table:nth-of-type(2) tbody')
      ? document.querySelector('table:nth-of-type(2) tbody').innerText
      : '';
    return {
      evilAttrCount: evilNodes.length,
      evilTags: Array.from(evilNodes).map((el) => el.outerHTML.slice(0, 120)),
      xssFlag: Boolean(window.__xssTriggered),
      findingCount,
      hasEscapedPayloadText: isMain
        ? bodyText.includes('alert(1)')
        : (actionTableText.includes('99901') && actionTableText.includes('alert(1)')),
    };
  }, interactiveMain);

  await context.close();

  const rowLabel = interactiveMain ? 'findings' : 'top15ActionRows';
  console.log(`[E2E XSS] ${label}: dialogs=${dialogs.length}, pageErrors=${pageErrors.length}, evilAttrCount=${domAudit.evilAttrCount}, xssFlag=${domAudit.xssFlag}, hasEscapedPayloadText=${domAudit.hasEscapedPayloadText}, ${rowLabel}=${domAudit.findingCount}`);

  if (dialogs.length > 0) {
    throw new Error(`${label} triggered unexpected dialog(s): ${dialogs.join(' | ')}`);
  }
  if (pageErrors.length > 0) {
    throw new Error(`${label} had JS pageerror(s): ${pageErrors.join(' | ')}`);
  }
  if (domAudit.evilAttrCount > 0) {
    throw new Error(`${label} rendered DOM elements with onerror/onload/onmouseover: ${domAudit.evilTags.join(' | ')}`);
  }
  if (domAudit.xssFlag) {
    throw new Error(`${label} executed injected script (window.__xssTriggered === true)`);
  }
  if (domAudit.findingCount < 1) {
    throw new Error(`${label} rendered 0 ${rowLabel} (malicious finding did not reach rendered output)`);
  }
  if (!domAudit.hasEscapedPayloadText) {
    throw new Error(`${label} did not render the escaped payload text in DOM (fixture may not have loaded)`);
  }
}

async function main() {
  const [mainHtml, execHtml] = process.argv.slice(2);
  if (!mainHtml || !execHtml) {
    console.error('Usage: node tests/e2e/xss-check.mjs <TenantBriefReport-TR.html> <TenantBrief-ExecutiveSummary-TR.html>');
    process.exit(2);
  }

  const pw = await loadPlaywright();
  const launchOpts = { headless: true };
  const sysBrowser = findSystemBrowser();
  if (sysBrowser && !process.env.PLAYWRIGHT_USE_BUNDLED) {
    launchOpts.executablePath = sysBrowser;
  }

  const browser = await pw.chromium.launch(launchOpts);
  try {
    await auditFile(browser, mainHtml, 'Main Report (TR)', true);
    await auditFile(browser, execHtml, 'Executive Summary (TR)', false);
    console.log('[E2E XSS] PASS: 0 dialogs, 0 pageErrors, 0 DOM onerror/onload/onmouseover attributes.');
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error('[E2E XSS] FAIL:', err.message);
  process.exit(1);
});
