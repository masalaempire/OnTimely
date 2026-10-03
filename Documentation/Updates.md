# OnTimely updates

Sparkle 2.10.0 is pinned through Xcode's Swift Package Manager integration. `AppUpdater` owns one `SPUStandardUpdaterController` for the application's lifetime. The menu and Settings share it, and observe its preferences and availability using KVO. Preferences are stored by Sparkle rather than duplicated in OnTimely's defaults.

## Hosting

- Feed: `https://raw.githubusercontent.com/masalaempire/OnTimely/main/appcast.xml`
- Downloads: versioned assets in `masalaempire/OnTimely` GitHub Releases.
- Future website download link: `https://github.com/masalaempire/OnTimely/releases/latest/download/OnTimely.dmg`

The initial feed intentionally contains no release entries. Packaging, uploads, and real update installation testing are deferred. Once published, release assets must be public and named `OnTimely.dmg` for the website link to work. Feed enclosure URLs must name the specific release tag so an existing signature always describes the same download.

## Signing key

The private Ed25519 key is stored in the macOS login Keychain with account `one.simonlm.OnTimely`. The corresponding public key is committed as `SUPublicEDKey` in `Configuration/Info.plist`. This update signature is independent of Apple Developer signing and notarization.

Use Sparkle's `generate_keys --account one.simonlm.OnTimely -p` to inspect the public key. Before publishing the first downloadable release, back up the private key with `generate_keys --account one.simonlm.OnTimely -x <secure-file-outside-the-repository>` and keep the exported file in secure storage. Never commit or paste the exported key. Keep this same key for future updates; losing it prevents signing compatible updates for installed copies.

## Sandboxed, ad-hoc app

The installer launcher XPC service is enabled through `SUEnableInstallerLauncherService`. Its Mach lookup entitlements use the app's bundle identifier. Downloads use the app's network client entitlement. `SUVerifyUpdateBeforeExtraction` requires archive verification before extraction.

The application is ad-hoc signed because the maintainer has no paid Apple Developer membership. Library validation is disabled for loading the Sparkle framework with a different signing identity; the app sandbox and hardened runtime remain enabled. Release signing does not inject debugging entitlements. Future downloads will be unnotarized until Developer ID signing and notarization are added.

## Publishing a future version

1. Increase `MARKETING_VERSION` and the monotonically increasing `CURRENT_PROJECT_VERSION` in both Xcode configurations.
2. Build and package the app, preserving its bundle identifier and public update key.
3. Use Sparkle's `generate_appcast` with account `one.simonlm.OnTimely` to create the signed archive enclosure. Preserve older feed entries and use a version-specific GitHub download URL.
4. Upload and publish the release asset, then verify the public download works. Only then replace the repository's `appcast.xml` with the generated feed.
5. Verify a real update from an installed older version, including manual checks, automatic preferences, quit/install/relaunch, and saved task persistence.

Official references: [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [sandboxing](https://sparkle-project.org/documentation/sandboxing/), and [publishing](https://sparkle-project.org/documentation/publishing/).
