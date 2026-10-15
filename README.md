# IPTV Player

A native macOS IPTV client built with SwiftUI. Connects to Xtream Codes
portals and M3U playlists, and plays live TV, movies and series through a
hybrid AVFoundation/VLCKit engine.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)

> **This is a player, not a content provider.** No channels, streams or
> playlists are bundled with or distributed by this project. You supply your
> own IPTV subscription or playlist. See [Legal](#legal).

## Features

**Sources**
- Xtream Codes portals — full API integration (live, VOD, series, categories)
- M3U playlists from a local file or a remote URL
- Multiple sources active at once, each enabled or disabled independently
- Account info surfaced from the portal: expiry date, connection limit, trial status

**Browsing**
- Live TV, Movies and Series, each with a category sidebar and search
- Favorites across all source types
- Continue Watching, with playback positions persisted per profile
- Series browser with seasons, episodes and per-episode resume
- Poster artwork with an on-disk image cache
- Multiple local profiles — separate sources, favorites and history per profile

**Playback**
- Live TV streams through `AVPlayer`
- Movies and episodes fall back to VLCKit, which demuxes the Matroska, AVI and
  FLV containers AVFoundation cannot — roughly half of a typical Xtream VOD
  catalogue
- Audio and subtitle track selection
- EPG (electronic programme guide) data where the portal provides it
- Keyboard control: space to play/pause, arrows to seek, `M` to mute

**Credentials**
- Portal usernames and passwords are stored in the macOS Keychain, never in
  plaintext on disk
- Everything else (profiles, sources, favorites, cached catalogues) is JSON
  under `~/Library/Application Support/IPTVPlayer/`

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (the build targets `arm64` only)
- Swift 5.9 / Xcode 16 command line tools

## Build

VLCKit is not vendored into the repository — it is ~40 MB after thinning and
is reproducible from a pinned upstream archive. Fetch it first:

```bash
git clone https://github.com/BenAhmedAmir/iptv-player-macos.git
cd iptv-player-macos
scripts/fetch_vlckit.sh      # downloads VLCKit 3.7.3 into vendor/
scripts/build_app.sh         # builds and packages build/IPTV Player.app
open "build/IPTV Player.app"
```

`build_app.sh release` is the default; pass `debug` for an unoptimised build.

### Tests

```bash
scripts/run_tests.sh
```

197 tests covering the M3U parser, Xtream response decoding, catalogue
filtering, persistence, title cleaning and account-expiry handling. The suite
compiles the model and service layers standalone, so it runs without building
the full app.

### Xcode

The project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open IPTVPlayer.xcodeproj
```

A checked-in `IPTVPlayer.xcodeproj` is also present if you would rather not
install XcodeGen.

## Architecture

MVVM, with SwiftUI views observing `@Published` view-model state.

```
IPTVPlayer/
├── App/            SwiftUI entry point, menu commands
├── Models/         Channel, Profile, IPTVSource, VOD, playback position
├── Services/       Xtream API, M3U parser, Keychain, persistence, image cache
│                   VLCPlaybackEngine
├── ViewModels/     Channel, VOD, Player, Sources, Profile, Settings
└── Views/          Home, LiveTV, Movies, Series, Player, Sources, Settings
VLCBridge/          Objective-C shim reaching libVLC's subtitle text renderer,
                    which VLCKit does not expose publicly
scripts/            Build, test, VLCKit fetch, icon generation, signing cert
```

Two details worth knowing before changing things:

- **Keychain reads are memoized on purpose.** Every Keychain read from an app
  whose signature the item's ACL does not recognise prompts for the login
  password, and the VOD screens ask for credentials on nearly every
  interaction. `KeychainService` keeps one generic-password item per source and
  caches the result for the process lifetime.
- **`build_app.sh` updates the app bundle in place rather than recreating it.**
  A Keychain ACL records its trusted application by filesystem identity, so
  deleting and rebuilding the bundle makes the app a stranger to its own
  Keychain items and reintroduces the password prompt on every launch.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Legal

This software is a media player. It ships no channel lists, no stream URLs and
no credentials, and it has no affiliation with any IPTV provider. Supplying a
source is entirely the user's action, and it is the user's responsibility to
ensure they have the right to access whatever content they point it at. The
authors do not endorse or facilitate unauthorised access to copyrighted
material.

## Acknowledgements

- [VLCKit](https://code.videolan.org/videolan/VLCKit) by VideoLAN — the VOD
  playback path. VLCKit is LGPL-2.1-or-later and is linked dynamically as an
  unmodified binary framework; its license terms apply to that component.
- Poster and backdrop artwork is served by the portal or by
  [TMDB](https://www.themoviedb.org/) where the portal supplies TMDB ids.

## License

MIT — see [LICENSE](LICENSE).
