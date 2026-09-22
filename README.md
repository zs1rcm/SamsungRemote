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

1. Clone the repo and double‑click **`SamsungRemote.xcodeproj`**.
2. Select the **SamsungRemote** target → **Signing & Capabilities** → set your
   Apple ID as the Team, and change the bundle identifier to something unique
   like `com.<yourname>.SamsungRemote` (Xcode will only accept one of each).
3. Pick your iPhone (or a Simulator) as the run destination and hit **⌘R**.

That's it — no manual file dragging, no Info.plist editing. Minimum
deployment is iOS 16.0.

### Adding an app icon (optional)

Save a 1024×1024 PNG named `AppIcon.png` and drop it onto the empty
1024×1024 well in `Assets.xcassets ▸ AppIcon` — Xcode generates every size
from that one image (single‑size mode).

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
- **Connect while the TV is off** — the app sends a Wake‑on‑LAN magic packet
  and polls for up to 20 s for the TV to come back before giving up. For this
  to work, on the TV:
  1. **Settings ▸ General ▸ Network ▸ Expert Settings ▸ Power On with Mobile**
     — turn it **On**.
  2. Prefer **Ethernet**: most Samsungs power down the Wi‑Fi radio in deep
     standby, so WoL over Wi‑Fi is unreliable.
  You can also wake a TV manually from Settings — swipe left on the TV in
  "My TVs" and tap **Wake**.
- **Pairing prompt never appears** — older (pre‑2016) TVs use a different
  protocol and are not supported.
- **TLS errors** — turn TLS off on the saved TV (via Add TV by IP…) to use
  port 8001; the app already trusts self‑signed certs on 8002.
