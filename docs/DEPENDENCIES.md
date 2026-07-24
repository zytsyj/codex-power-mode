# Dependencies and licensing

Codex Power Mode currently has no third-party runtime or development packages. This inventory is intentionally explicit so a future dependency cannot be added silently.

## Runtime requirements

- Node.js 20 or newer. The JavaScript implementation uses only built-in `node:` modules.
- macOS with the system Swift toolchain for the native overlay.
- Apple system frameworks: AppKit, ApplicationServices, Foundation, and QuartzCore.
- Codex desktop application and its local plugin lifecycle hooks.

Node.js, macOS, Apple frameworks, Swift, and Codex are platform prerequisites. They are not copied into or redistributed with this repository.

The optional first-party media build additionally uses the macOS ImageIO and UniformTypeIdentifiers system frameworks to compose synthetic PNG frames into GIFs. Those frameworks are not shipped with the plugin.

## Bundled code and assets

The lockfile contains only the root package. The repository does not bundle third-party JavaScript packages, copied source code, fonts, videos, native libraries, or precompiled executables. The small preview PNGs under `docs/media/` are first-party output generated from the project's native renderer; their provenance is recorded in `docs/MEDIA.md`.

Four user-supplied meme images and their derived transparent cutouts are bundled under `assets/meme-stickers/` for cursor effects. They are explicitly excluded from the MIT license and documented in `THIRD_PARTY_NOTICES.md`. A redistributor can omit these optional PNG files to produce a code-only MIT package.

The browser preview's CSS names `Inter` as an optional preferred local font, followed by operating-system fonts. No Inter font file is downloaded or distributed.

## CI-only tools

GitHub Actions currently uses the following GitHub-maintained actions. They run in GitHub's CI environment and are not included in the plugin package:

- `actions/checkout` commit `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` (`v5`) — MIT.
- `actions/setup-node` commit `a0853c24544627f65ddf259abe73b1d18a591444` (`v5`) — MIT.

Both actions are pinned to immutable commits. Reconfirm their upstream license and desired major version when updating either pin.

## Project license

The source code, documentation, and project-authored media are available under the MIT license. The legacy meme PNG files are separately excluded as described above; no license grant is made for them.

## Updating this inventory

Any change that introduces a package, copied snippet, font, image, animation asset, native library, generated bundle, or new CI action must update this document and any required notice file in the same change. Run `npm run check`; the dependency inventory test guards the zero-package baseline, bundled-media disclosure, and license boundary.
