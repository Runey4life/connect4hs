# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM haskell:9.6 AS builder

WORKDIR /app

# Cache dependency build separately from source
COPY connect4-web.cabal ./
RUN cabal update && cabal build --only-dependencies -j4

# Build the app
COPY src/ ./src/
RUN cabal build -j4
RUN cp $(cabal list-bin connect4-web) /app/connect4-server

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    libgmp10 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/connect4-server ./connect4-server
COPY static/ ./static/

EXPOSE 8080
CMD ["./connect4-server"]
