/* This entry is part of the immutable assigned-runtime distribution. */
import {mountParticipantHost} from './participant-host.mjs';

const opening = document.getElementById('brohn-opening');
const alert = document.getElementById('brohn-opening-error');
try {
  const match = /^\/api\/runtime\/([a-f0-9]{64})\/([a-f0-9]{64})\/participant\/index\.html$/.exec(location.pathname);
  const query = new URLSearchParams(location.search);
  if (!match || query.getAll('token').length !== 1 || query.get('token') !== match[1] || query.has('study'))
    throw Error('Assigned runtime link does not identify one original release.');
  const host = mountParticipantHost({container: document.getElementById('brohn-study'), releaseToken: match[1],
    rendererIdentity: {schema: 'participant-renderer-identity/0.1', id: 'brohn-assigned-host/0.1.0', manifest_hash: match[2]}});
  await host.ready;
  opening.hidden = true;
} catch (_) {
  opening.hidden = true;
  alert.textContent = 'We couldn’t open this study. Reopen the original link from your researcher. If this continues, contact them for help.';
  alert.hidden = false;
  alert.focus({preventScroll: true});
}
