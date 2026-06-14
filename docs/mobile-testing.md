# Mobile testing — getting Kithbound onto a phone

Rung 1 is a test of **feel** on a touch device, so the fastest way to learn
something is to hold the companion in your hand. This doc covers both targets.
**Android is dramatically easier** (no Mac, no signing) and tests the same
touch feel — reach for it first unless you specifically need iOS.

The project already ships an [`export_presets.cfg`](../pokepals/export_presets.cfg)
with an **iOS** and an **Android** preset. The bundle/package identifier is
`com.maxwang.kithbound` — change it freely. The platform-specific signing
fields are intentionally left blank; you fill them in on your build machine
(they're per-developer and shouldn't be committed).

---

## iOS (requires a Mac)

There is no way around this: Apple only lets you build and sign iOS apps from
**macOS with Xcode**. Godot's iOS export doesn't produce a finished app — it
produces an **Xcode project** that you then compile, sign, and deploy from
Xcode.

For *local* testing on *your own* iPhone you only need a **free Apple ID** — no
$99/yr account. Tradeoff: the app expires after 7 days and you re-deploy it.

### One-time setup on the Mac
1. Install **Godot 4.6** (standard build — this project is GDScript-only, no .NET).
2. In Godot: **Editor → Manage Export Templates**. If the dialog shows no
   mirrors and no **Download and Install** button, first click **"go online"**
   (Godot starts offline) — the mirror list and the download button appear after
   that. The template version must match 4.6 exactly.
3. Install **Xcode** from the App Store, then `xcode-select --install` for the
   command-line tools. Open Xcode once and sign in with your Apple ID under
   **Settings → Accounts**.

### Finish the iOS preset
Open the project (`godot --path pokepals`) → **Project → Export → iOS**. The
preset is already there.
- **App Store Team ID** — you can leave this **blank** for free personal-team
  local testing and let Xcode handle signing in the next step (Godot shows it as
  a warning but still exports the Xcode project). If you'd rather fill it in,
  see "Finding your Team ID" below.
- **Signing identity / provisioning** — leave blank; resolve in Xcode.
- Adjust **Bundle Identifier** if you don't want `com.maxwang.kithbound`.

#### Finding your Team ID (only if you want to fill it in)
It's a 10-character string like `A1B2C3D4E5`. Apple doesn't show it next to
"Personal Team" in Xcode's accounts pane, so grab it one of these ways:
- **Keychain Access** (definitive): **My Certificates** → double-click your
  **"Apple Development: …"** cert → **Details** → **Organizational Unit (OU)** is
  the Team ID. (The cert exists once you've selected your Personal Team on a
  project in Xcode at least once.)
- **Terminal:** `security find-identity -v -p codesigning` → the `(XXXXXXXXXX)`
  in the `Apple Development:` line.
- **Portal:** [developer.apple.com/account](https://developer.apple.com/account)
  → **Membership details** (visible on free accounts).

### Export, then build & deploy
1. In the Export dialog, **Export Project** to a folder → you get a `.xcodeproj`.
2. Plug the iPhone in via USB. On the phone, enable **Developer Mode**
   (Settings → Privacy & Security → Developer Mode) — required on iOS 16+.
3. Open the generated `.xcodeproj`. Under **Signing & Capabilities**, enable
   **Automatically manage signing** and pick your **Personal Team** from the
   dropdown — Xcode generates the cert + provisioning profile and fills in the
   Team ID for you.
4. Select your iPhone as the run target and press **Run (▶)**. Xcode compiles,
   installs, and launches it.
5. First launch only: the phone refuses to open it until you trust the cert —
   Settings → General → **VPN & Device Management** → tap your developer
   profile → **Trust**.

Re-deploying after a change: re-export from Godot → **Run** in Xcode. For
pure-GDScript tweaks, Godot's **one-click deploy** can push to the
already-installed app over Wi-Fi without a full Xcode rebuild.

---

## Android (no Mac needed — fastest path)

1. Install **Android Studio** (you only need the SDK + platform tools it bundles).
2. In Godot: **Editor → Editor Settings → Export → Android** and point the
   **Android SDK Path** / **Debug Keystore** at your install. Godot can generate
   a debug keystore for you (Editor Settings has a button), or:
   ```sh
   keytool -keyalg RSA -genkeypair -alias androiddebugkey \
     -keypass android -keystore debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
3. On the phone: enable **Developer options** (tap Build Number 7×) and turn on
   **USB debugging**. Plug it in and accept the trust prompt.
4. In Godot, the phone appears in the top-right **one-click deploy** dropdown
   (the little phone icon). Click it — Godot builds the APK, installs, and
   launches it on the device in one step.

The on-screen thumbstick and `Space`-to-examine touch interactions all work, so
this is enough to actually judge presence and mood in the hand.

---

## No phone handy?

You can still approximate touch on desktop: run the project and use
**Project → Tools → ... **/ the editor's device-simulation, or just resize the
window to a phone aspect — the project uses `canvas_items` stretch with an
`expand` aspect, so the world reflows to phone screens. It's not a substitute
for feeling it on glass, but it catches layout problems early.
