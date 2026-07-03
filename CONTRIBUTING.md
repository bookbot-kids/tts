# Contributing to TTS

Hi there. Thanks for taking your time to contribute.

We welcome contributions that improve the plugin, documentation, examples, and
platform integrations. We want contributing to this project to be as easy and
transparent as possible, whether it is:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Improving examples or documentation
- Becoming a maintainer

## Code of Conduct

Please be mindful to respect our [Code of Conduct](https://github.com/bookbot-kids/tts/blob/main/CODE_OF_CONDUCT.md).

## We Develop with GitHub

We use GitHub to host code, track issues and feature requests, and accept pull
requests.

## Pull Requests

Pull requests are the best way to propose changes to the codebase. We actively
welcome pull requests:

1. Fork the repo and create your branch from `main`.
2. If you add code that should be tested, add tests.
3. If you change APIs, update `README.md` and the docs in `docs/`.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Open the pull request.

## Development Setup

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install), then
fetch dependencies from the repository root:

```sh
flutter pub get
```

Run the analyzer and tests before opening a pull request:

```sh
flutter analyze
flutter test
```

To exercise the plugin manually, run the example application in `example/` on a
supported Android or iOS target with the required ONNX model and IPA mapping
assets configured.

## Documentation

Documentation is built with MkDocs:

```sh
mkdocs serve
```

When changing public APIs or setup instructions, update both the root
`README.md` and the relevant files under `docs/`.

## License

Any contributions you make will be under the Apache 2.0 License. In short, when
you submit code changes, your submissions are understood to be under the same
[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0) that covers
the project. Feel free to contact the maintainers if that is a concern.

## Report Bugs Using GitHub Issues

We use GitHub issues to track public bugs. Report a bug by
[opening a new issue](https://github.com/bookbot-kids/tts/issues/new).

## Write Bug Reports with Detail, Background, and Sample Code

Great bug reports tend to have:

- A quick summary and background
- Steps to reproduce
- Sample code or a minimal reproduction when possible
- The platform and device or simulator used
- The ONNX model, language, and speaker configuration involved
- What you expected would happen
- What actually happened
- Notes about anything you tried that did not work

## References

This document was adapted from the open-source contribution guidelines for
[Facebook's Draft](https://github.com/facebook/draft-js/blob/a9316a723f9e918afde44dea68b5f9f39b7d9b00/CONTRIBUTING.md).

