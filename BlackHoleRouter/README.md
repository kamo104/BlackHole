# BlackHole Router

A macOS audio routing GUI equivalent to the Linux qpwgraph + PipeWire stack, built for use with the BlackHole virtual audio driver.

## Overview

BlackHole Router provides a node-graph visual interface for routing audio between macOS applications via the BlackHole virtual audio devices.

### Architecture

The BlackHole driver now creates two distinct virtual devices:

| Device | Role | Apps use it as... |
|--------|------|-------------------|
| **BlackHole Sink** (`*ch Sink`) | Receives audio | Output device (speaker) |
| **BlackHole Source** (`*ch Source`) | Provides audio | Input device (microphone) |

Audio flows: **App A → BlackHole Sink → (ring buffer) → BlackHole Source → App B**

This mirrors the PipeWire model where a *sink* consumes audio and a *source* produces audio.

### Routing Example

To record Spotify into Logic Pro:
1. Set Spotify's output to **BlackHole Sink**
2. Set Logic's input to **BlackHole Source**
3. Audio from Spotify flows into Logic in real-time

## Requirements

- macOS 13.0 (Ventura) or later
- BlackHole driver installed (with the Sink/Source variant)
- Xcode 15+ or Swift 5.9+

## Build & Run

### Via Xcode (recommended)
```bash
cd BlackHoleRouter
open Package.swift   # Opens in Xcode
# Press ⌘R to build and run
```

### Via Swift Package Manager
```bash
cd BlackHoleRouter
swift run BlackHoleRouter
```

## GUI Features

- **Node Graph Canvas** — dark-themed graph showing all audio devices as draggable nodes
  - 🟠 Orange nodes = BlackHole Sink devices
  - 🟢 Green nodes = BlackHole Source devices  
  - 🔵 Blue nodes = output-only devices (speakers, headphones)
  - 🟡 Yellow nodes = input-only devices (microphones)
  - 🟣 Purple nodes = input+output devices
- **Connection Lines** — solid green lines show the internal BlackHole routing (Sink → Source)
- **Left Sidebar** — lists all devices; shows system default input/output
- **Quick Setup** — one-click buttons to route system audio through BlackHole
- **Inspector Panel** — shows device details; set default input/output per device
- **Right-click context menu** on any device node to set system defaults
- **Pan** the canvas by dragging the background
- **Auto-layout** button to reset node positions

## How It Works

The node graph is visual only — the actual audio routing is handled by:

1. **The BlackHole driver ring buffer** (automatic Sink → Source routing)
2. **System audio preferences** (set via the sidebar Quick Setup or Inspector)
3. **App-level device selection** (Spotify, Logic, etc. choose their own devices)

For advanced routing (e.g. mixing multiple sources), you can create an **Aggregate Device** in macOS Audio MIDI Setup (`/Applications/Utilities/Audio MIDI Setup.app`) that combines BlackHole with your physical devices.

## Differences from Linux qpwgraph

| Feature | qpwgraph (Linux) | BlackHole Router (macOS) |
|---------|-----------------|--------------------------|
| Audio engine | PipeWire | CoreAudio + BlackHole driver |
| Port connections | Real-time PipeWire graph | System default + Aggregate Devices |
| Per-app routing | PipeWire handles it | Apps choose their own devices |
| MIDI routing | Yes | Not yet |
| Plugin processing | Yes (pw-filter) | Not yet |
