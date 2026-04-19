# Samsung Remote (iOS, SwiftUI)

A native iOS remote for Samsung Smart TVs (2016+ / Tizen) that talks to the TV's
built‑in WebSocket remote‑control service (`samsung.remote.control`, port
`8001`/`8002`).

Features:

- SwiftUI interface (iOS 16+) — power, d‑pad, volume, channel, numbers,
  transport keys, source/menu/home/back, mute.
- First‑time pairing: the TV shows an "Allow" prompt; once accepted the app
  saves the returned token in `UserDefaults` and reconnects silently on later
  launches.
- TLS (`wss://…:8002`) with self‑signed certificate trust, or plain `ws://…:8001`
  for older sets.
- Settings screen for TV host/IP, TLS on/off, device name, and a "Forget
  pairing" button.

## Build it in Xcode

1. Open Xcode → **File ▸ New ▸ Project…** → **iOS ▸ App**.
2. Product Name: `SamsungRemote`, Interface: **SwiftUI**, Language: **Swift**.
   Pick any bundle ID you like. Minimum deployment: **iOS 16.0** (17 is fine
   too).
3. Close Xcode. In Finder, open the project folder Xcode just created (it will
   contain a `SamsungRemote.xcodeproj` and a `SamsungRemote/` source folder).
4. Copy every file from this repo's `SamsungRemote/` directory into that
   `SamsungRemote/` source folder, overwriting `SamsungRemoteApp.swift` and
   `ContentView.swift`.
5. Re‑open the `.xcodeproj`. In the Project navigator, right‑click the
   `SamsungRemote` group → **Add Files to "SamsungRemote"…**, select the newly
   added `.swift` files, check **Copy items if needed** is **off** and
   **Add to targets: SamsungRemote** is on.
6. Select the target → **Info** tab and add:
   - **Privacy - Local Network Usage Description**
     (`NSLocalNetworkUsageDescription`): `Used to reach your Samsung TV.`
   - **App Transport Security Settings** → **Allow Arbitrary Loads** = `YES`
     (needed because the TV uses a self‑signed certificate on port 8002 and/or
     unencrypted HTTP on 8001).
   Alternatively, replace the generated `Info.plist` with the one in this repo.
7. Build & run on a real iPhone on the same Wi‑Fi as your TV (the Simulator
   works too, but Local Network permission only exists on device).

## Using it

1. First launch → tap the gear icon → enter your TV's LAN IP (e.g.
   `192.168.1.42`) → **Done**.
2. Tap **Connect**. The TV should display an "Allow remote" prompt — accept it
   on the TV. The app will switch to **Connected** and store the pairing token.
3. Press buttons. If the connection drops (TV sleeps etc.) just tap **Connect**
   again; the saved token is reused.

### Finding the TV IP

On the TV: **Settings ▸ General ▸ Network ▸ Network Status ▸ IP Settings**.

### Troubleshooting

- **"Connection refused"** — TV is off or on standby, or you're on a different
  network. Samsung sets power down the remote service in deep sleep; Wake‑on‑LAN
  is required to boot them cold (not implemented here — `KEY_POWER` only works
  on a reachable TV).
- **Pairing prompt never appears** — older (pre‑2016) TVs use a different
  protocol and are not supported.
- **TLS errors** — turn TLS off in Settings to try port 8001, or leave it on
  (the app already trusts self‑signed certs).
