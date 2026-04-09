# Versioning And Repository Distribution Rules

This project uses separate documents for separate kinds of truth. Keep them distinct.

## Release Source Of Truth

- `CHANGELOG.md` is not used yet in this repository.
- Git tags are the canonical release identifiers when releases begin.
- `README.md` describes the current main-branch operator workflow, not historical releases.

If a version is not tagged, do not present it as a formal release history item.

## Internal Tracking

- internal planning documents remain in the private source repository

These documents are internal working records. They are not part of the public distribution set.

## Public Distribution Policy

This repository follows the same private/public separation model used in the Eldrun project.

Repository roles:
- private source repo: full working tree, including internal planning documents
- offense360 public repo: public distribution set only
- Kangwonland public repo: same distribution set as the offense360 public repo

The public distribution set is defined only by `.publish-manifest`.

Anything not listed in `.publish-manifest` must be treated as non-public by default.

## Document Boundary

Public documents:
- `README.md`
- `docs/runbooks/2026-04-10-offline-deployment-rehearsal.md`
- `docs/versioning.md`
- `docs/versioning_ko.md`

Internal-only documents:
- internal design and planning records maintained only in the private source repo

Do not copy internal planning documents into public distribution repos.

## Update Rule

When publishing to the public repos:

1. Make changes in the private source repo.
2. Update public-facing docs only if operator-visible behavior changed.
3. Keep internal design and plan docs in the private repo.
4. Sync the public whitelist using the private repo maintenance workflow.

## Local Mirror Layout

The private source repository maintains local mirrors for the two public distributions.
