# Godot Addressable addon

**0.1.0 (experimental)**. APIs and content formats may change.

Install this folder at `res://addons/addressables/` and enable **Addressables** in
Project Settings → Plugins. No autoload or application integration is installed.
The editor/runtime use GDScript; `dotnet/` is an optional C# facade.

The repository is called `godot-addressable`. Its local checkout directory can be
`addressable`; the installed addon path remains `addons/addressables`.

Drag assets into `AddressableReference` fields, build catalogs/PCKs with
`AddressablesBuild`, then load assets through owned handles. Keep each handle
until its consumer is finished and release it explicitly. PCKs can be copied from
a local content directory or downloaded from a direct HTTPS CDN URL on demand.

| Guide | Contents |
| --- | --- |
| [Usage](docs/USAGE.md) | Installation, authoring, builds, complete GDScript/C# examples |
| [Recipes](docs/RECIPES.md) ([Vietnamese](docs/RECIPES.vi.md)) | Minimal copy-paste cases: match load/release, shared assets, references, build |
| [Architecture](docs/ARCHITECTURE.md) | End-to-end flow, ownership and lifecycle |
| [API](docs/API.md) | Public methods, properties, return values and errors |
| [Content format](docs/CONTENT_FORMAT.md) | Catalog, reference and cache formats |
| [File guide](docs/FILE_GUIDE.md) | Every source/test file and its responsibilities |
| [Testing and troubleshooting](docs/TESTING_AND_TROUBLESHOOTING.md) | Native suite, limits and diagnosis |

Targets Godot 4.6 and newer 4.x; validated with Godot .NET 4.6.3 and 4.7.2
on Windows and .NET SDK 8. Older-minor content may be read by a newer minor in the
same major; the native PCK/resource loader still enforces format compatibility. The integration runner
generates isolated projects; it is currently Windows oriented. Production CDN,
mobile imports and memory budgets require testing on the intended targets.

This addon is distributed under the [MIT license](LICENSE). Preserve its notice
when copying the addon. See the repository README for repository checks and CI.
