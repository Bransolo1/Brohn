import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import fs from 'node:fs/promises';
import path from 'node:path';

async function accessibility(page, testInfo, label) {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
  await testInfo.attach(`${label}-axe.json`, { body: JSON.stringify(results, null, 2), contentType: 'application/json' });
  expect(results.violations.map(x => ({ id: x.id, impact: x.impact, nodes: x.nodes.map(n => n.target) }))).toEqual([]);
}

test('guided sample can save, export and reopen its protocol', async ({ page }, testInfo) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Open guided sample', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Open guided sample', exact: true }).click();
  const title = `Tooling check ${testInfo.project.name}`;
  await page.getByLabel('Study name', { exact: true }).fill(title);
  await page.getByRole('button', { name: '4 Review', exact: true }).click();
  await page.getByRole('button', { name: 'Save protocol snapshot', exact: true }).click();
  const downloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Export protocol snapshot', exact: false }).click();
  const download = await downloadEvent;
  const downloaded = testInfo.outputPath('study-protocol.json');
  await download.saveAs(downloaded);
  const protocol = JSON.parse(await fs.readFile(downloaded, 'utf8'));
  expect(protocol.status).toBe('planned');
  expect(protocol.study.title).toBe(title);
  expect(protocol.registry.trials).toHaveLength(2);
  expect(protocol.registry.epochs.map(x => x.phase)).toEqual(['passive_viewing', 'active_response', 'passive_viewing', 'active_response']);
  await accessibility(page, testInfo, 'review');
  await page.getByRole('button', { name: 'My studies', exact: true }).click();
  const choice = page.getByLabel('Choose a study', { exact: true });
  await expect(choice).toBeVisible();
  const value = await choice.locator('option').filter({ hasText: title }).getAttribute('value');
  await choice.selectOption(value);
  await page.getByRole('button', { name: 'Open study', exact: true }).click();
  await page.getByRole('button', { name: '4 Review', exact: true }).click();
  await expect(page.getByText(`Snapshot saved for study revision ${protocol.study.revision}`, { exact: true })).toBeVisible();
});

test('library accessibility baseline', async ({ page }, testInfo) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Create study', exact: true })).toBeVisible();
  await accessibility(page, testInfo, 'library');
});

test('installed jsPsych plugins execute an isolated synthetic smoke trial', async ({ page }) => {
  await page.setContent('<html lang="en"><head><title>Tooling smoke check</title></head><body></body></html>');
  for (const pkg of ['jspsych', '@jspsych/plugin-html-keyboard-response', '@jspsych/plugin-image-keyboard-response', '@jspsych/plugin-survey-likert', '@jspsych/plugin-preload']) {
    await page.addScriptTag({ path: path.resolve('node_modules', pkg, 'dist/index.browser.js') });
  }
  await page.evaluate(() => {
    const experiment = initJsPsych({ on_finish: () => { window.smokeData = experiment.data.get().values(); } });
    experiment.run([{ type: jsPsychHtmlKeyboardResponse, stimulus: '<p>Tooling trial: press space.</p>', choices: [' '], data: { origin: 'synthetic_tooling_check' } }]);
  });
  await expect(page.getByText('Tooling trial: press space.', { exact: true })).toBeVisible();
  await page.keyboard.press('Space');
  await expect.poll(() => page.evaluate(() => window.smokeData?.length)).toBe(1);
  const response = await page.evaluate(() => window.smokeData[0]);
  expect(response.response).toBe(' ');
  expect(response.origin).toBe('synthetic_tooling_check');
  expect(Number.isFinite(response.rt)).toBe(true);
  // Execution/compatibility only: no assertion about physical display/input accuracy.
});
