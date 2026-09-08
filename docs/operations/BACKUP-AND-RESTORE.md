# Verified local workspace backup and restore

Brohn creates a **folder artifact** containing a consistent SQLite catalog, every
registered content-addressed object and a hashed manifest. Choose a new destination
outside the source workspace; its parent directory must already exist. The artifact
can subsequently be copied using a trusted filesystem tool and verified again.
This implementation does not create a ZIP archive or upload anything.

Backups contain research data, historical records, private participant credentials
and queued work. They are **not encrypted**. Treat them as private workspace data.
SHA-256 checks detect corruption; they do not authenticate who produced a backup.

## Researcher workflow

1. Create a backup in a new directory. The current workspace remains usable.
2. Verify the backup after copying or storing it.
3. Restore into another new directory. Existing destinations are refused.
4. Inspect the restored studies, datasets, runs, histories and results.
5. Explicitly resume pending analysis when ready. Publish a new release for any
   new participant collection; restoring or resuming never reopens old releases.

The API calls are `brohn_backup_workspace(store, destination)`,
`brohn_verify_backup(path)`, `brohn_restore_workspace(backup, destination)`,
`brohn_workspace_execution_status(store)` and `brohn_resume_workspace(store)`.
The first two return verification evidence; successful creation and successful
restore are separate facts.

From the repository root, the same operations are available through:

```text
Rscript scripts/backup-workspace.R backup --root WORKSPACE --destination NEW_BACKUP_DIRECTORY
Rscript scripts/backup-workspace.R verify --backup BACKUP_DIRECTORY
Rscript scripts/backup-workspace.R restore --backup BACKUP_DIRECTORY --destination NEW_WORKSPACE_DIRECTORY
Rscript scripts/backup-workspace.R resume --root RESTORED_WORKSPACE
```

Use the Brohn runtime library when invoking Rscript. This development checkout's
launcher also locates its prepared `r-library-brohn` directory.

## Consistency and validation

- A separate read connection starts a transaction and pins the source catalog
  view. `RSQLite::sqliteCopyDatabase` invokes SQLite's online backup API. Copying
  `catalog.sqlite` with a file-copy operation is deliberately not used: committed
  records may still be in its WAL.
- SQLite writers can continue after that view is pinned. The captured catalog
  contains the earlier complete transaction state. Object membership comes from
  that captured catalog, rather than from a later live directory listing.
- All registered objects are copied, including registered objects without a
  current study reference. Unregistered orphan objects, temporary worker files
  and external files outside the catalog are excluded.
- SQLite integrity, foreign keys, current-to-historical revision membership,
  stored JSON hashes, frozen run design hashes, table counts, object paths, byte
  counts and SHA-256 values are checked. Every artifact file must occur in the
  manifest. Unknown extra files, missing objects, traversal paths and filesystem
  links are rejected. The supported inventory limit is 100,000 objects and a
  64 MiB manifest.
- Work is staged in a private sibling directory. Only a fully verified artifact
  is renamed into its absent destination. Copy, verification or publication
  failure leaves the destination unpublished. Cleanup is restricted to the
  checked temporary directory.

## Restore isolation

Restore preserves scientific/entity history, data objects, frozen protocols,
participant events and job results. It records a new workspace identity with
the source workspace, backup and manifest identities as provenance.

Before the destination becomes available, all deployments are closed and
participant credentials are rotated. Queued jobs remain queued; running jobs
are returned to the queue with their old worker token and lease cleared. Their
attempt counter is retained, so the next claim receives a newer fence. Completed,
failed and cancelled jobs retain their terminal outcomes.

A persisted execution pause prevents automatic job claims, participant writes
and new releases. Explicit resume clears that pause but leaves historical
deployments closed. Old participant links/tokens cannot continue into the restored
copy. In-progress runs retain the recorded snapshot state and evidence; restore
does not invent participant completion or rerun an exposure.

## Evidence and limits

`tests/platform-backup.R` exercises a separate-process writer committing while
the backup read snapshot is pinned, a verified restore with histories and frozen
events, preserved completed results, paused/requeued jobs, token rotation,
corruption, traversal, missing and unexpected objects, unsupported schema,
existing destinations and injected backup/restore interruptions.

The current checks establish application-level snapshot consistency and recovery
behavior. They do not qualify filesystem fsync/power-loss behavior, removable
media, network filesystems, encrypted backups or cloud recovery. Backups do not
implement participant-data purges or reconciliation with a protected external
purge ledger; those lifecycle features remain separately required. A recorded
withdrawal outcome is not a claim that retained data or backups have been erased.
