# Project Board Suggestion

## Project Name

Bookbot TTS Quality & Release Board

## Short Description

Tracks open-source maintenance, QA, documentation, CI coverage, and release
readiness for the Bookbot Flutter text-to-speech plugin.

## README

This project board is the public planning surface for `bookbot-kids/tts`.
It should help contributors and maintainers see what is planned, in progress,
blocked, and ready for review.

Recommended views:

- **Triage**: New issues and incoming contributor reports.
- **Development**: Implementation tasks, bug fixes, and documentation work.
- **QA & CI**: Test coverage, workflow health, branch protection, and release
  checks.
- **Release Readiness**: Items required before publishing a new tag or package
  release.

Recommended fields:

- **Status**: Triage, Ready, In Progress, In Review, Blocked, Done.
- **Type**: Bug, Feature, Documentation, QA, CI, Release.
- **Priority**: High, Medium, Low.
- **Area**: Dart API, Android, iOS, Documentation, CI, Example App.

Suggested automation:

- Add newly opened issues to **Triage**.
- Move linked issues to **In Review** when a pull request is opened.
- Move linked issues to **Done** when a pull request is merged.

Initial cards to create:

- Enable branch protection and required PR review on `main`.
- Add and monitor CI coverage reporting.
- Review public documentation after each API change.
- Track native Android/iOS test gaps that require device or simulator coverage.

