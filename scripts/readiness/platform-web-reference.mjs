// Isolated synthetic Form Library and plugin-load probes; no app or participant session.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const work = resolve(root, '../../work/tooling/research-web-tools');
const requireRoot = createRequire(resolve(root, 'package.json'));
const { chromium } = requireRoot('@playwright/test');
const pkg = JSON.parse(await readFile(resolve(work, 'package.json'), 'utf8'));
const checks = [];
const check = (id, actual, expected = true, evidence = 'synthetic library API probe') => {
  const passed = JSON.stringify(actual) === JSON.stringify(expected);
  checks.push({ id, passed, actual, expected, evidence });
  if (!passed) throw new Error(`Failed ${id}: ${JSON.stringify(actual)}`);
};
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome', headless: true });
try {
  const page = await browser.newPage();
  await page.setContent('<!doctype html><html lang="en"><head><title>Brohn synthetic survey probe</title></head><body><div id="survey"></div></body></html>');
  await page.addScriptTag({ path: resolve(work, 'node_modules/survey-core/survey.core.min.js') });
  await page.addScriptTag({ path: resolve(work, 'node_modules/survey-js-ui/survey-js-ui.min.js') });
  const surveyChecks = await page.evaluate(() => {
    const result = [];
    const add = (id, actual, expected = true) => result.push({ id, actual, expected });
    const definition = {
      title: 'Synthetic questionnaire', clearInvisibleValues: 'onHidden',
      pages: [{ name: 'main', elements: [
        { type: 'radiogroup', name: 'seen', title: 'Have you seen this?', isRequired: true,
          choices: [{ value: 'yes', text: 'Yes' }, { value: 'no', text: 'No' }] },
        { type: 'rating', name: 'liking', title: 'How much did you like it?', isRequired: true,
          rateMin: 1, rateMax: 7, visibleIf: "{seen} = 'yes'" },
        { type: 'text', name: 'count', title: 'Count', inputType: 'number' },
        { type: 'boolean', name: 'agree', title: 'Agree?' },
        { type: 'matrix', name: 'attributes', title: 'Attributes', rows: ['clear', 'useful'], columns: [1, 2, 3] },
        { type: 'comment', name: 'optional_comment', title: 'Optional comment' }
      ] }]
    };
    const model = new Survey.Model(definition);
    model.render(document.getElementById('survey'));
    add('survey_visible_in_dom', !!document.querySelector('input'));
    add('unanswered_is_absent', !Object.hasOwn(model.data, 'optional_comment'));
    add('branch_initially_hidden', model.getQuestionByName('liking').isVisible, false);
    add('required_gate_blocks_completion', model.validate(), false);
    model.setValue('seen', 'yes');
    add('branch_visible_after_yes', model.getQuestionByName('liking').isVisible);
    add('branch_required_when_visible', model.validate(), false);
    model.setValue('liking', 6);
    model.setValue('count', 0);
    model.setValue('agree', false);
    model.setValue('attributes', { clear: 2, useful: 3 });
    add('zero_is_preserved', model.data.count, 0);
    add('false_is_preserved', model.data.agree, false);
    add('matrix_row_identity_preserved', model.data.attributes, { clear: 2, useful: 3 });
    model.setValue('seen', 'no');
    add('hidden_prior_answer_cleared', !Object.hasOwn(model.data, 'liking'));
    add('hidden_required_does_not_block', model.validate());
    let completed = false;
    model.onComplete.add(() => { completed = true; });
    model.doComplete();
    add('completion_callback', completed);
    const roundtrip = new Survey.Model(model.toJSON());
    add('definition_roundtrip_choice_ids', roundtrip.getQuestionByName('seen').choices.map(x => x.value), ['yes', 'no']);
    const requested = ['text', 'comment', 'radiogroup', 'checkbox', 'dropdown', 'tagbox', 'boolean',
      'rating', 'ranking', 'matrix', 'matrixdropdown', 'matrixdynamic', 'paneldynamic', 'multipletext',
      'imagepicker', 'expression', 'html', 'file', 'signaturepad'];
    const types = Survey.QuestionFactory.Instance.getAllTypes();
    add('question_type_registry_available', requested.filter(t => !types.includes(t)), []);
    return result;
  });
  for (const x of surveyChecks) check(x.id, x.actual, x.expected);
  await page.addScriptTag({ path: resolve(work, 'node_modules/jspsych/dist/index.browser.js') });
  for (const [name, version] of Object.entries(pkg.dependencies).filter(([n]) => n.startsWith('@jspsych/'))) {
    const filename = resolve(work, 'node_modules', name, 'dist/index.browser.js');
    const source = await readFile(filename, 'utf8');
    const globalName = source.match(/var\s+(jsPsych\w+)\s*=/)?.[1];
    if (!globalName) throw new Error(`No browser global found: ${name}`);
    await page.addScriptTag({ path: filename });
    const info = await page.evaluate(n => ({ exists: typeof window[n] === 'function',
      name: window[n]?.info?.name, version: window[n]?.info?.version }), globalName);
    check(`plugin_load:${name}`, info.exists && info.name === name.replace('@jspsych/plugin-', '') && info.version === version,
      true, 'browser bundle load and plugin metadata only; task execution not tested');
  }
  const report = { schema: 'brohn-platform-web-probes/0.1', generated: new Date().toISOString(),
    browser: browser.version(), origin: 'synthetic/reference', application_integration: false,
    checks_passed: checks.length, checks, versions: pkg.dependencies,
    limitations: [
      'Form Library API and basic rendering only; not an implemented Brohn survey builder, accessibility audit or branching journal.',
      'Absent values alone do not distinguish not-shown, skipped, declined, invalid or interrupted: Brohn must preserve response state and exposure events separately.',
      'clearInvisibleValues=onHidden clears answer data, so revision-aware event history is required to preserve prior exposure/response audit.',
      'Question type registration does not establish accessible rendering, scoring validity, safe file upload or timing performance.',
      'Plugin loading does not qualify display timing, correction-inclusive RT, physical response devices or scientific task protocols.'
    ] };
  await writeFile(resolve(root, 'docs/preparation/platform-results-web.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(`${checks.length} platform web checks passed`);
} finally { await browser.close(); }
