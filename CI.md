# CI status

## Included now

`.github/workflows/ci.yml` runs on pushes, pull requests and manual dispatches.
It uses an Ubuntu runner with Python and no application secrets. It checks:

- Repository/addon MIT licenses and experimental version labeling.
- The `addons/addressables/` installation layout and plugin metadata.
- Python syntax without importing or executing the native test runner.
- Local Markdown links and balanced fenced code blocks.
- English source comments/documentation and absence of original application branding.

These checks can be reproduced locally with:

```text
python tools/check_repository.py
```

The workflow uses the official [checkout](https://github.com/actions/checkout)
and [setup-python](https://github.com/actions/setup-python) actions. The hosted
workflow itself is not considered verified until it has run after the first push.

## Native integration tests

The full suite is available now but is not automatically run by this workflow.
It currently assumes a Windows Desktop export preset and identifies the .NET
branch from a `mono` executable filename. Do not run it on a Linux runner and
claim equivalent C#/export coverage.

For a later native CI job:

1. Use a Windows runner and install Python 3.10+ and .NET SDK 8.
2. Download an official matching Godot .NET distribution (validated locally: 4.6.3 and 4.7.2), preserving its
   `GodotSharp` directory and offline NuGet packages.
3. Pass the executable explicitly to `addons/addressables/tests/run_tests.py`.
4. Allow the test process to connect to its loopback HTTP server.
5. Upload logs/report on failure, not staged engines or NuGet caches.
6. Verify the C# branch ran instead of inferring it from a generic PASS message.

Before adding Linux/macOS jobs, remove the preset/Mono-name assumptions and add
tests for that change. Cross-platform support should be established by real
native runs, not by changing only a platform string in catalog metadata.

## Publishing

Content building, application export and repository checks are separate steps.
Use `editor/export_cli.py` for application export: the native Godot CLI may return
zero after logging errors. Publish artifacts only after the wrapper succeeds.

This repository's workflow does not create releases, upload PCKs or modify any
application project. It has read-only repository permissions.
