// Exercise the actual completed-transfer review. Never queue an import through
// a fixture API or replay a stale hidden identity in place of the visible action.
import path from 'node:path';
import {expect} from '@playwright/test';

export async function importTransferredSource(page, file, {
  destination = 'Destination: Data library, with no study link yet.',
  timeout = 120000,
  onReview = null,
  onSubmitted = null,
} = {}) {
  const fields = {};
  for (const name of ['title', 'modality', 'origin']) {
    fields[name] = await page.locator(`#dataset_${name}`).inputValue();
  }
  const previous = await page.locator('#ingestion_upload_review_identity').count()
    ? await page.locator('#ingestion_upload_review_identity').inputValue() : null;
  await page.locator('#dataset_upload').setInputFiles(file);
  const review = page.locator('#ingestion_upload_review');
  await expect(review.getByText(`Ready to import: ${path.basename(file)}`, {exact: true})).toBeVisible({timeout});
  await expect(review.getByText(destination, {exact: typeof destination === 'string'})).toBeVisible();
  await expect(review.getByText(`Dataset: ${fields.title} · Family: ${fields.modality} · Origin: ${fields.origin}`, {exact: true})).toBeVisible();
  const identity = page.locator('#ingestion_upload_review_identity');
  await expect(identity).toHaveValue(/^[a-f0-9]{64}$/);
  if (previous) await expect(identity).not.toHaveValue(previous);
  // A rendered input is not yet evidence that Shiny has bound and sent it.
  // Wait on the actual binding instead of adding a timing delay before clicking.
  await page.waitForFunction(() => {
    const field = document.getElementById('ingestion_upload_review_identity');
    const view = document.getElementById('ingestion_upload_review');
    return field?.classList.contains('shiny-bound-input') && !view?.classList.contains('recalculating') &&
      window.Shiny?.shinyapp?.$inputValues?.ingestion_upload_review_identity === field.value;
  });
  const receipt = {filename: path.basename(file), ...fields, identity: await identity.inputValue()};
  if (onReview) await onReview(receipt);
  await page.locator('#start_source_import').click();
  if (onSubmitted) await onSubmitted(receipt);
  await expect(page.getByRole('heading', {name: fields.title, exact: true})).toBeVisible({timeout});
  const form = page.locator(fields.modality === 'multimodal' ? '#multistream_form_identity' : '#dataset_form_identity');
  await expect(form).toHaveValue(/^dataset-[^:]+:[1-9][0-9]*$/);
  receipt.dataset_identity = await form.inputValue();
  return receipt;
}
