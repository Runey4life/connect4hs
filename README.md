# Connect Four — Haskell on Fly.io

A WebSocket-powered Connect 4 game: Haskell (Warp + Scotty) backend,
retro arcade HTML/JS frontend. One URL, playable in any browser.

## Project layout

```
connect4-web/
├── src/
│   └── Main.hs          ← Haskell server (WebSockets + game logic)
├── static/
│   └── index.html       ← Frontend (pure HTML/CSS/JS)
├── connect4-web.cabal   ← Cabal build config
├── Dockerfile           ← Two-stage build (haskell:9.6 → debian-slim)
├── fly.toml             ← Fly.io deployment config
└── README.md            ← This file
```

---

## Deploy to Fly.io (step by step)

### 1 — Install flyctl

```bash
# macOS
brew install flyctl

# Linux
curl -L https://fly.io/install.sh | sh

# Windows (PowerShell)
iwr https://fly.io/install.ps1 -useb | iex
```

### 2 — Sign up / log in

```bash
fly auth signup   # new account
# — or —
fly auth login    # existing account
```

### 3 — Edit fly.toml

Open `fly.toml` and set a unique app name:

```toml
app = "connect4-yourname"   # must be globally unique on Fly.io
```

Pick the region closest to you:
| Code | Location        |
|------|-----------------|
| fra  | Frankfurt       |
| lhr  | London          |
| cdg  | Paris           |
| iad  | Washington D.C. |
| sjc  | San Jose        |
| nrt  | Tokyo           |

### 4 — Launch (first time only)

```bash
cd connect4-web
fly launch --no-deploy   # registers the app, skips immediate deploy
```

When prompted "Would you like to copy its configuration to the new app?" → **Yes**.

### 5 — Deploy

```bash
fly deploy
```

Fly.io will:
1. Build the Docker image (takes ~5 min first time — Haskell compiles deps)
2. Push the image to their registry
3. Start a VM

Subsequent deploys are faster because layers are cached.

### 6 — Open in browser

```bash
fly open
```

Or visit `https://connect4-yourname.fly.dev` directly.

---

## Local development (Docker)

```bash
docker build -t connect4 .
docker run -p 8080:8080 connect4
# open http://localhost:8080
```

## Local development (native Haskell)

```bash
cabal update
cabal run connect4-web
# open http://localhost:8080
```

Requires GHC 9.x and cabal-install. Install via [GHCup](https://www.haskell.org/ghcup/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

---

## How it works

```
Browser ──WebSocket──▶ Haskell (Warp)
                           │
                    Game state (IORef)
                           │
                    Logic in pure Haskell
                    (drop, win-check, draw)
                           │
                    JSON response ──▶ Browser renders board
```

- **No database** — state lives in an `IORef GameState` in memory.
  Refresh resets the game (intentional for a two-player same-screen game).
- **No auth** — anyone with the URL can play.
- **Auto-sleep** — `auto_stop_machines = true` in fly.toml means the VM
  sleeps when idle and wakes on the next request (cold start ~1 s).

---

## Keeping it free on Fly.io

Fly.io's free tier (as of 2024) includes:
- 3 shared-CPU VMs
- 256 MB RAM each
- 160 GB outbound transfer / month

This app uses 1 VM with `auto_stop_machines = true`, so it only runs
when someone is actually playing — well within the free tier.
"# connect4hs" 
