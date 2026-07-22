# Dependencies and licensing

Codex Power Mode currently has no third-party runtime or development packages. This inventory is intentionally explicit so a future dependency cannot be added silently before a public release.

## Runtime requirements

- Node.js 20 or newer. The JavaScript implementation uses only built-in `node:` modules.
- macOS with the system Swift toolchain for the native overlay.
- Apple system frameworks: AppKit, ApplicationServices, Foundation, and QuartzCore.
- Codex desktop application and its local plugin lifecycle hooks.

Node.js, macOS, Apple frameworks, Swift, and Codex are platform prerequisites. They are not copied into or redistributed with this repository.

The optional first-party media build additionally uses the macOS ImageIO and UniformTypeIdentifiers system frameworks to compose synthetic PNG frames into GIFs. Those frameworks are not shipped with the plugin.

## Bundled third-party code and assets

None. The lockfile contains only the root package. The repository does not bundle third-party JavaScript packages, fonts, images, videos, native libraries, or precompiled executables. The small preview PNGs under `docs/media/` are first-party output generated from the project's native renderer; their provenance is recorded in `docs/MEDIA.md`.

The browser preview's CSS names `Inter` as an optional preferred local font, followed by operating-system fonts. No Inter font file is downloaded or distributed.

## CI-only tools

GitHub Actions currently uses the following GitHub-maintained actions. They run in GitHub's CI environment and are not included in the plugin package:

- `actions/checkout@v5` — MIT; source and license are maintained in the `actions/checkout` repository.
- `actions/setup-node@v5` — MIT; source and license are maintained in the `actions/setup-node` repository.

Reconfirm the action versions and their upstream license files when preparing a release tag. Pin actions to immutable commit SHAs before the first public release if the chosen supply-chain policy requires it.

## Project license decision

The project remains `UNLICENSED`, private, and all rights reserved. The owner must explicitly choose the public license. Common candidates to evaluate include:

- MIT for a short permissive grant.
- Apache-2.0 for a permissive grant with an explicit patent license and notice obligations.

This list is not a license selection. Do not replace `LICENSE`, change the manifest license, publish the repository, or create a public release without the owner's explicit approval.

## Updating this inventory

Any change that introduces a package, copied snippet, font, image, animation asset, native library, generated bundle, or new CI action must update this document and any required notice file in the same change. Run `npm run check`; the dependency inventory test guards the current zero-package baseline and private-license boundary.
