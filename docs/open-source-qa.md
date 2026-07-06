# Open Source QA Process

This project uses a lightweight open source QA process focused on public
documentation, repeatable local checks, and automated verification in the
development workflow.

## QA Documentation Published

QA expectations are published in this repository and in the MkDocs site so
contributors can review the process before opening a pull request.

Published QA documentation includes:

- Project setup and usage documentation in `README.md`.
- Contribution requirements in `CONTRIBUTING.md`.
- Project scope and governance in `PROJECT_CHARTER.md`.
- Public QA process in this document.
- Generated Flutter API documentation in the documentation site.

## Tests Executed as Part of Development Workflow

Contributors should run the same checks locally before opening a pull request:

```sh
flutter pub get
flutter analyze
flutter test --coverage
dart doc --output docs/tts/doc/api
mkdocs build --strict
```

The GitHub Pages workflow also executes the automated test suite before
generating API documentation and publishing the documentation site. It writes
line coverage to the GitHub Actions job summary and uploads `coverage/lcov.info`
as a workflow artifact. A failed test run or missing coverage report blocks the
documentation deployment.

## Review Checklist

Before merging changes, maintainers should confirm:

- Public documentation is updated when setup, behavior, or APIs change.
- Flutter analyzer checks pass.
- Flutter tests pass with coverage generated.
- Dart API documentation can be generated.
- MkDocs builds successfully with strict validation.
