# 🧅 OnionTalkie

**Encrypted End-to-End Voice Communications over the Tor Network.**

**OnionTalkie** is a **Push-to-Talk (PTT)** voice communication platform designed for maximum privacy. It uses no central servers, no phone numbers, and no accounts. Each user is identified solely by their locally generated `.onion` address.

### Who is it for?

* **Journalists & activists** operating under censorship or surveillance regimes
* **Lawyers & healthcare professionals** handling privileged or sensitive communications
* **Security researchers** studying anonymous communication protocols
* **NGOs & human rights organizations** coordinating fieldwork in hostile environments
* **Whistleblowers** who need untraceable voice channels with no account trail
* **Privacy enthusiasts** who refuse to trust centralized infrastructure with their metadata
* **Users in censored countries** where mainstream messaging apps are blocked (via Snowflake Bridge)

---

## ✨ Key Features

* **No Central Infrastructure:** Direct peer-to-peer communication via *Tor Hidden Services*.
* **Zero Metadata:** No record of who talks to whom. Traffic is routed through three random Tor nodes.
* **State-of-the-Art Encryption:**
  * **PFS (Perfect Forward Secrecy):** Via **SPAKE2 (PAKE)** key exchange per RFC 9382.
  * **Multi-Cipher:** 21 cipher variants supported (AES, ChaCha20, Camellia, ARIA).
  * **HMAC-SHA256:** Message authentication with anti-replay nonce.
* **Anti-Censorship:** Native **Snowflake Bridge** integration to connect even where Tor is blocked.
* **Cross-Platform:** Native Android/iOS app and self-hosted Web version for LAN use.
* **Privacy-by-Design:** Built-in voice changer and instant Onion address rotation.

---

## 🛠️ Architecture

OnionTalkie turns your device into a Tor server.

1. **Mobile Version:** The Tor binary is embedded directly in the app — no Orbot or external dependencies required.
2. **Web/LAN Version:** A local Dart server manages the SOCKS5 proxy, allowing any browser on your home network to join the conversation securely.

```
┌──────────────────────────────────────────────────────┐
│                    LOCAL NETWORK (LAN)                │
│                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │  Phone   │   │  Laptop  │   │   Desktop PC     │ │
│  │ (browser)│   │ (browser)│   │   (browser)      │ │
│  └────┬─────┘   └────┬─────┘   └────────┬─────────┘ │
│       │              │                   │           │
│       └──────────────┼───────────────────┘           │
│                      │ HTTP + WebSocket              │
│              ┌───────▼────────┐                      │
│              │  Local Server  │                      │
│              │  (Dart/shelf)  │                      │
│              │   port 8080    │                      │
│              └───────┬────────┘                      │
│                      │ SOCKS5                        │
│              ┌───────▼────────┐                      │
│              │      Tor       │                      │
│              │  (localhost)   │                      │
│              └───────┬────────┘                      │
└──────────────────────┼───────────────────────────────┘
                       │
                  ─────▼─────
                 ( Tor Network)
                 (   .onion   )
                  ───────────
```

---

## 🚀 Quick Start

### 📱 Android

1. Download the latest APK from the [Releases](../../releases) page.
2. On first launch, the app will automatically configure your `.onion` address.
3. Share the QR Code with a friend and start talking.

### 💻 Web / Self-Hosted (Recommended for Desktop)

**Prerequisites:**

| Software | Installation |
|----------|-------------|
| **Flutter** >= 3.22.0 | [flutter.dev/get-started](https://flutter.dev/docs/get-started/install) |
| **Dart** >= 3.4.0 | Included with Flutter |
| **Tor** | macOS: `brew install tor` · Linux: `sudo apt install tor` · Windows: [torproject.org](https://www.torproject.org/download/) |

```bash
git clone https://github.com/g-cesar/OnionTalkie.git
cd OnionTalkie
chmod +x start.sh
./start.sh
```

The script will build the web app, start Tor, and launch the local server. Access the interface at `http://localhost:8080` or via LAN from any device.

<details>
<summary>Advanced Options</summary>

```bash
# Custom port
PORT=9090 ./start.sh

# Manual launch (without script)
flutter build web --release
cd server && dart pub get
dart run bin/server.dart --port 8080 --host 0.0.0.0

# Tor already running separately
dart run bin/server.dart --no-tor

# All parameters
dart run bin/server.dart --help
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--port`, `-p` | `8080` | HTTP server port |
| `--host`, `-H` | `0.0.0.0` | Bind address (0.0.0.0 = LAN accessible) |
| `--web-dir`, `-w` | `../build/web` | Path to Flutter web build output |
| `--tor-socks` | `127.0.0.1:9050` | Tor SOCKS5 proxy address |
| `--tor-data` | `./tor_data` | Tor data directory |
| `--no-tor` | `false` | Don't auto-start Tor |

</details>

---

## 🔒 Security & Encryption

### Key Exchange (PAKE)

Unlike traditional systems, OnionTalkie uses **SPAKE2** (RFC 9382 on P-256). You agree on a simple passphrase with your contact (in person, via a secure app, etc.). The algorithm derives a robust session key without ever sending the password over the network, protecting you from brute-force attacks and ensuring every call has a unique key.

### Cipher Selection

You can negotiate the cipher for each session:

| Family | Variants | Notes |
|--------|----------|-------|
| **AES** | 128/192/256-bit in CBC, CTR, CFB, OFB | Standard performance |
| **ChaCha20** | ChaCha20-Poly1305 (AEAD), ChaCha20 | Ideal for mobile devices |
| **Camellia** | 128/192/256-bit in CBC, CTR | Alternative security standard |
| **ARIA** | 128/192/256-bit in CBC, CTR | Korean standard cipher |

### Additional Security Features

* **HMAC-SHA256** message authentication with anti-replay nonce
* **At-rest secret protection** — optional passphrase to encrypt the shared secret on disk (AES-256-CBC, 100k PBKDF2 iterations)
* **Node exclusion** — Five/Nine/Fourteen Eyes presets to exclude relays from specific countries
* **Circuit visualization** — view the Tor circuit path in real-time

---

## 📡 Protocol

Line-based text protocol over TCP (native) / WebSocket (web):

| Message | Direction | Description |
|---------|-----------|-------------|
| `SPAKE2_PUB:<base64>` | ↔ | SPAKE2 blinded public key |
| `SPAKE2_CONFIRM:<hex>` | ↔ | SPAKE2 HMAC confirmation |
| `ID:<onion>` | → | Identification |
| `CIPHER:<name>` | ↔ | Cipher negotiation |
| `PTT_START` | → | Recording started |
| `PTT_STOP` | → | Recording ended |
| `AUDIO:<base64>` | ↔ | Encrypted audio data |
| `MSG:<base64>` | ↔ | Encrypted chat message |
| `HANGUP` | ↔ | End call |
| `PING` | ↔ | Keep-alive |

<details>
<summary>SPAKE2 Call Flow Diagram</summary>

```
Initiator                           Responder
    │                                    │
    │──── ID:<onion> ───────────────────▶│  Identification
    │──── CIPHER:<name> ────────────────▶│  Cipher negotiation
    │◀─── ID:<onion> ───────────────────│  Responder identification
    │◀─── CIPHER:<name> ────────────────│  Responder cipher
    │                                    │
    │  ✓ Responder loads SECRET          │
    │                                    │
    │──── SPAKE2_PUB:<base64> ──────────▶│  Blinded public key exchange
    │◀─── SPAKE2_PUB:<base64> ──────────│  Responder replies
    │◀─── SPAKE2_CONFIRM:<hex> ─────────│  Responder confirms
    │──── SPAKE2_CONFIRM:<hex> ─────────▶│  Initiator confirms
    │                                    │
    │  ✓ Session key derived             │  ✓ Session key derived
    │                                    │
    │  ══════ Call Active ══════         │
    │  (HMAC enabled after handshake)    │
    │                                    │
    │──── PTT_START ────────────────────▶│
    │──── AUDIO:<base64> ───────────────▶│  Audio encrypted with SPAKE2 key
    │──── PTT_STOP ─────────────────────▶│
    │                                    │
```

</details>

---

## 👨‍💻 Development & Build

### Requirements

* Flutter SDK >= 3.22.0
* Dart SDK >= 3.4.0
* Tor binary (for desktop/web builds)

### Android Build

Download the native Tor binaries before compiling:

```bash
# Download latest stable Tor binaries (auto-detected)
bash scripts/fetch_tor_android.sh

# Debug build
flutter build apk --debug

# Release build
flutter build apk --release

# Split by architecture (smaller APKs)
flutter build apk --split-per-abi --release
```

### iOS Build

```bash
# Debug (simulator only)
flutter build ios --debug --simulator

# Release (unsigned archive)
flutter build ipa --release --no-codesign
```

> For sideloading without the App Store, use SideStore, AltStore, Sideloadly, or an ad-hoc/enterprise certificate.

### Web Build

```bash
flutter build web --release
```

---

## 📂 Project Structure

```
├── lib/
│   ├── main.dart                        # Entry point
│   ├── app.dart                         # MaterialApp.router
│   ├── core/
│   │   ├── constants/app_constants.dart # Constants, ciphers, protocol
│   │   ├── router/app_router.dart       # GoRouter config
│   │   └── theme/app_theme.dart         # Material 3 theme
│   ├── models/                          # Data classes (CallState, TorStatus, etc.)
│   ├── providers/                       # Riverpod state management
│   ├── screens/                         # UI screens
│   ├── services/                        # Platform services (audio, connection, tor, encryption)
│   └── widgets/                         # Reusable UI components
├── scripts/
│   └── fetch_tor_android.sh             # Download Tor binaries for Android
├── server/
│   ├── bin/server.dart                  # Local relay server (Tor bridge)
│   └── pubspec.yaml                     # Server dependencies
├── start.sh                             # Quick start script
└── README.md
```

---

## 🤝 Credits & Inspiration

OnionTalkie draws inspiration and foundational concepts from:

* **[TerminalPhone](https://gitlab.com/here_forawhile/terminalphone):** Special thanks to the TerminalPhone developers for their pioneering approach to voice communication over the Tor network. Many of the circuit management and PTT protocol patterns are derived from their excellent open-source implementation.
* **[The Tor Project](https://www.torproject.org/):** For providing the anonymity infrastructure on which this project is built.

---

## ⚖️ License

Distributed under the MIT License. See the `LICENSE` file for details.

> **Disclaimer:** This software is provided "as is", for educational and privacy-protection purposes. The developers are not responsible for any improper or illegal use of this tool.

---

**Want to contribute?** Pull Requests are welcome! If you find a bug or have a suggestion to improve the cryptography, please open an Issue.

**Like the project?** Leave a ⭐ on GitHub!
