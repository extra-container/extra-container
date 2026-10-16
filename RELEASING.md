# Releasing

## Versions

extra-container uses [semantic versioning](https://semver.org): `major.minor.patch`,
with an optional pre-release suffix (`1.0.0-pre.1`).

- Patch releases (`1.0.0`->`1.0.1`) only contain non-breaking fixes.
- Breaking changes bump at least the minor version (`1.0.x` -> `1.1.0`). A change of a default option value is a breaking change.
- Adding a new nix option with a default value that doesn't change behavior is a non-breaking change, and may be included in a patch, minor, or major bump (our disscretion).
- Bug fixes may or may not be back-ported (our discretion). Follow the repo to get notified of updates.

## Branches and tags

| Ref           | Contents                                                                 |
| ------------- | ------------------------------------------------------------------------ |
| `main`        | Development. Default branch and PR target. May contain breaking changes. |
| `release-x.y` | Release `x.y.0` and its patch releases. Never receives breaking changes. |
| `vX.Y.Z`      | Tag of an exact release, on `release-x.y` (pre-releases: on `main`).     |

Flake inputs:

```nix
# Follow release-1.0 branch and get non-breaking patches with `nix flake update`
inputs.extra-container.url = "github:extra-container/extra-container/release-1.0";
# Pin exact release
inputs.extra-container.url = "github:extra-container/extra-container/v1.0.0";
# YOLO/Development, may break
inputs.extra-container.url = "github:extra-container/extra-container";
```

Install instructions in README.md use the latest release branch.

## Supported release branches

Development is against `nixos-unstable`. On a weekly basis, CI tests `main` with the most recent nixos release (e.g., 26.05) and current nixos-unstable.

Release branches will usually use the most recent nixos release.

## Signatures

All release commits (including cherry-picks to release branches) and all release tags
are signed. Verify signatures before pushing:

```bash
git verify-commit HEAD
git verify-tag vX.Y.Z
```

To avoid unsigned release commits, enable signing by default in the release checkout:

```bash
git config commit.gpgSign true
git config tag.gpgSign true
```

## Release checklist

### New minor or major version (`x.y.0`)

1. On `main`: make sure CI passes, including the VM test (`nix flake check`).
1. Update `CHANGELOG.md`: rename the top section to the version, and describe every breaking change (before, after, and how to restore the old behavior).
1. Set `version` in `default.nix`.
1. Update the README install instructions to use `release-x.y`.
1. Commit on `main`, create the release branch, and pin `flake.lock` to the targeted
   NixOS release (change the `nixpkgs` input URL in `flake.nix` first if needed):
   ```bash
   git commit -S -m "Release X.Y.0"
   git switch -c release-x.y
   nix flake update nixpkgs
   git commit -S -m "release-x.y: pin nixpkgs" flake.nix flake.lock
   ```
1. Check CI on `release-x.y`, then tag, verify, and push:
   ```bash
   git tag -s vX.Y.0 -m "extra-container X.Y.0"
   git verify-commit HEAD
   git verify-tag vX.Y.0
   git push origin main release-x.y vX.Y.0
   ```
1. Create a GitHub release for the tag with the CHANGELOG section as notes.
1. Update the nixpkgs package (see below).

### Patch release (`x.y.z`)

1. Fix on `main` first, if the fix applies there, then cherry-pick to `release-x.y`.
1. On `release-x.y`: update `CHANGELOG.md` and `version` in `default.nix`, check CI,
   then commit, tag, verify, and push:
   ```bash
   git switch release-x.y
   git cherry-pick -S -x <commit>...
   git commit -S -m "Release X.Y.Z" CHANGELOG.md default.nix
   git tag -s vX.Y.Z -m "extra-container X.Y.Z"
   git verify-commit HEAD
   git verify-tag vX.Y.Z
   git push origin release-x.y vX.Y.Z
   ```
1. Create a GitHub release and update the nixpkgs package.

### Pre-release (`x.y.0-pre.n`)

Tag on `main` and create a GitHub release marked as pre-release. Don't create a release branch and don't update nixpkgs.

```bash
git commit -S -m "Release X.Y.0-pre.N" CHANGELOG.md default.nix
git tag -s vX.Y.0-pre.N -m "extra-container X.Y.0-pre.N"
git verify-commit HEAD
git verify-tag vX.Y.0-pre.N
git push origin main vX.Y.0-pre.N
```

## Security releases

1. Develop the fix privately in a GitHub security advisory (see [SECURITY.md](./SECURITY.md)).
1. Release a patch version on every supported release branch, and include the fix on `main`.
1. Publish the advisory with the fixed versions (e.g. "fixed in 1.0.2").
1. Update nixpkgs unstable and request backports to the supported NixOS stable releases.
   Mention the advisory in the PR.

## nixpkgs

The nixpkgs package (`pkgs/by-name/ex/extra-container`) fetches a release tag.

- Patch releases can be backported to NixOS stable releases.
- Breaking (minor or major) releases only go to nixpkgs unstable. Mention the breaking
  changes in the PR and, if they affect NixOS users, in the NixOS release notes.
