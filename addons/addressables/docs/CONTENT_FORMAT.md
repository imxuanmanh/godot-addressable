# Content and metadata formats

All formats are experimental in 0.1.0. Keep an application export and its content
build together. There is no runtime catalog update/migration API.

## Lightweight reference

A serialized AddressableReference contains its script plus `key`,
`expected_type` and `source_path` strings. It has no target PackedScene/Texture
external-resource dependency. The script dependency itself belongs in the base
application. A reference container `.tres` is different from its target asset.

| Key form | Benefit | Caveat |
| --- | --- | --- |
| `uid://...` | Follows UID mapping during editor rename/build | Preserve UID sidecar/import data |
| `res://props/crate.tscn` | Useful when no UID exists | Renames need a key/reference update |
| `prefabs/crate` | Stable application identity | Author and group must use the same custom key |

Runtime always resolves the key through `catalog.assets`. It does not interpret
a UID directly or fetch a URL supplied as a key. The catalog chooses the target
path and pack.

## Catalog schema v1

The builder writes `OUTPUT/catalog.json`. The export filter injects the bytes at
`res://addressables/catalog.json` in the application. No automatic catalog HTTP
fetch is implemented; the application loads a trusted catalog dictionary.

An illustrative packed entry looks like this; placeholders must be replaced
with the real builder output, especially hash, size and imported file list:

```json
{
  "schema_version": 1,
  "engine": "4.6",
  "platform": "Windows",
  "assets": {
    "prefabs/crate": {
      "path": "res://props/crate.tscn",
      "type": "PackedScene",
      "pack": "props"
    }
  },
  "packs": {
    "props": {
      "file": "props-<sha256>.pck",
      "sha256": "<64 hexadecimal characters from the built PCK>",
      "size": 12345,
      "dependencies": [],
      "files": ["res://props/crate.tscn"]
    }
  },
  "base_dependencies": []
}
```

| Field | Contract |
| --- | --- |
| `schema_version` | Must be 1 |
| `engine` | Godot major.minor; generated explicitly; runtime checks exact match |
| `platform` | OS target string; generated explicitly; runtime checks host |
| `assets` | Dictionary of nonempty keys to locations |
| `packs` | Dictionary of pack IDs to delivery metadata |
| `base_dependencies` | Builder information about code left in the base application |

Engine/platform values omitted from hand-written catalogs default to the host
during validation. Generated catalogs include them. Rely on explicit metadata
for published content instead of treating omission as cross-platform support.

### Asset location

`path` is required and must be a normalized nonempty `res://` path. Traversal,
backslashes and `::` subresource paths are rejected. `type` defaults to Resource
and must be a native class derived from Resource. `pack` defaults to an empty
string; if nonempty, it must name an existing pack whose `files` declares `path`.

An empty pack means that the resource is already available to the application;
it is not a request to download a file using its path.

### Pack record

| Field | Validation and use |
| --- | --- |
| `file` | Filename only, `.pck` suffix, no `..`; joined to content root |
| `sha256` | Exactly 64 hexadecimal characters; integrity/cache/mount identity |
| `size` | Positive integral bytes, at most 2,147,483,647 |
| `dependencies` | Array of existing pack IDs; default empty |
| `files` | Array of normalized resource paths; default empty |

Validation rejects dependency cycles and excessive depth. It does not open a PCK
to prove that its contents match `files`. Trust the builder/catalog publisher;
the declaration is also used for collision checks.

## Minimal source-development catalog

For a project that actually contains `res://demo/crate.tscn`, the following is a
valid metadata example on Windows/Godot 4.6:

```json
{
  "schema_version": 1,
  "engine": "4.6",
  "platform": "Windows",
  "assets": {
    "prefabs/crate": {"path": "res://demo/crate.tscn", "type": "PackedScene", "pack": ""}
  },
  "packs": {}
}
```

Use a matching reference key and `configure(catalog, "", true)`. Change platform
and engine metadata for your actual host. This does not test external packaging;
the clean-client suite does.

## Pack layout and sharing

PCK entries retain their `res://` locations. A resource can include source data,
`.import` metadata and engine-imported files under `.godot/imported/`. These
imported payloads must exist before building. A handwritten list containing only
the scene can omit textures or remaps, which is why the builder collects closure.

The builder assigns files used by several groups to `__shared`. Group pack
records list `__shared` as a dependency when needed. A top-level asset present in
several groups can itself point to `__shared`.

Scripts (`gd`, `gdc`, `cs`) and native extensions remain base dependencies.
Editor-only addon resources cannot be packed. Include required code and exported
types in the application ahead of time. This is a data-content pipeline, not a
remote compilation system.

Filenames use `GROUP-SHA256.pck`. Repeated identical bytes reuse an existing
hashed output. Old output files are not automatically deleted. Upload only files
referenced by the successful release catalog and retain prior releases according
to your deployment policy.

## Internal export state

`res://.godot/addressables/export.json` is generated local state, not a runtime
catalog and not a CDN artifact. Its fields are:

| Field | Purpose |
| --- | --- |
| `excluded` | Collected optional files, settings/group resources, output packs and catalog |
| `catalog_path` | Location of the generated catalog |
| `catalog_sha256` | Detect changed catalog bytes before export |
| `source_hashes` | Detect collected sources/settings/groups changed after build |
| `output_directory` | Exclude generated content output from the base export |

The filter adds runtime catalog bytes at a fixed export path. It skips matching
files for that export without deleting originals. Missing build state does not
produce an inferred content split. Rebuild after import/cache cleanup. A changed
file or stale catalog must be fixed by rebuilding, not by bypassing export errors.

The state is not a universal reproducible-build manifest: preserve matching
engine/import settings and rebuild whenever the content pipeline changes.

## Runtime disk and transfer state

| Location | Meaning |
| --- | --- |
| `user://addressables/SHA256.pck` | Verified persistent cache entry |
| `user://addressables/SHA256.pck.STORE_ID.part` | Incomplete store-specific transfer |
| Store `_pending` | Per-store in-flight transfer entries, keyed by SHA |
| Static `_mounted` | Successfully mounted SHA identities for the current process |

The runtime validates cached size and hash before use. Corrupt entries are
replaced through a verified temporary file. A valid entry needs no transfer;
mounted packs are reused. Closing a store cancels HTTP and removes its partials.

The cache has no version index, size quota, eviction or resume mechanism. Handle
release does not delete files. Multiple services may each perform their own
transfer; their temporary filenames differ. Mount history is shared across
services within one process.

## Delivery and release compatibility

Use a direct directory URL such as
`https://cdn.example.invalid/releases/release-001`; the runtime appends each
catalog `file`. Replace this illustrative domain with your real endpoint. HTTP
redirects, user-provided URLs and catalog authentication are not handled here.

Publish immutable PCKs with the exact catalog from their build. Size/SHA checks
reject accidental corruption or mismatched bytes. They do not establish trust
when the catalog itself is untrusted.

Mounting uses replacement disabled and rejects collisions with existing declared
paths. New content at the same virtual paths cannot hot-replace a mounted release
through this API. Use a fresh process and matched base app/content versions.

Choosing Android/iOS metadata does not perform platform imports or install SDKs.
Test actual exported builds on target hardware. See [Testing](TESTING_AND_TROUBLESHOOTING.md).
