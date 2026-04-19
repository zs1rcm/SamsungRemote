# Samsung Remote (iOS, SwiftUI)

A native iOS remote for Samsung Smart TVs (2016+ / Tizen) that talks to the TV's
built‑in WebSocket remote‑control service (`samsung.remote.control`, port
`8001`/`8002`).

Features:

- SwiftUI interface (iOS 16+) — power, d‑pad, volume, channel, numbers,
  transport keys, source/menu/home/back, mute.
- **Auto‑discovery**: scans your local /24 subnet for Samsung TVs by probing
  the `:8001/api/v2/` device‑info endpoint. No multicast entitlement required.
- **Multi‑TV library**: save as many TVs as you like and switch between them
  from Settings. Each TV keeps its own pairing token.
- **DHCP‑proof**: TVs are stored by MAC address, not IP. If the router hands
  the TV a new address, the app rescans on Connect and updates the stored host
  automatically.
- First‑time pairing: the TV shows an "Allow" prompt; once accepted the app
  saves the returned token in `UserDefaults` and reconnects silently on later
  launches.
- TLS (`wss://…:8002`) with self‑signed certificate trust, or plain `ws://…:8001`
  for older sets.

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

1. First launch → tap the gear icon → **Scan for TVs**. The app probes every
   address on your Wi‑Fi subnet; any Samsung TV that responds appears in the
   list. Tap it to save and set it active.
   - If your TV is off or on a different subnet, use **Add TV by IP…** to add
     it manually.
2. Tap **Connect**. The TV should display an "Allow remote" prompt — accept it
   on the TV. The app switches to **Connected** and stores the pairing token
   for that TV.
3. Press buttons. If the connection drops (TV sleeps etc.) just tap **Connect**
   again; the saved token is reused.

### DHCP & changing IPs

TVs are keyed by MAC address. When you tap Connect the app first pings the
last known IP; if the TV doesn't answer there it automatically rescans the
subnet, matches by MAC, and updates the stored host. You don't need to do
anything when your router hands the TV a new lease.

### Finding the TV IP manually

On the TV: **Settings ▸ General ▸ Network ▸ Network Status ▸ IP Settings**.

### Troubleshooting

- **Scan finds nothing** — make sure the iPhone is on the same Wi‑Fi SSID as
  the TV (some routers isolate the "guest" and 5 GHz networks). On first scan
  iOS will prompt for Local Network permission; if you denied it, re‑enable it
  in Settings ▸ Samsung Remote ▸ Local Network.
- **"Connection refused"** — TV is off or on standby, or you're on a different
  network. Samsungs power down the remote service in deep sleep; Wake‑on‑LAN
  is required to boot them cold (not implemented here — `KEY_POWER` only works
  on a reachable TV).
- **Pairing prompt never appears** — older (pre‑2016) TVs use a different
  protocol and are not supported.
- **TLS errors** — turn TLS off on the saved TV (via Add TV by IP…) to use
  port 8001; the app already trusts self‑signed certs on 8002.
