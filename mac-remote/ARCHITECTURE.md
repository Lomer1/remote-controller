# MacRemote — Architecture

## Overview
Two-app system: iOS remote control app + macOS server app.
Communication via Wi-Fi (Bonjour/TCP) and Bluetooth (MultipeerConnectivity).

## Protocol

### Transport Layer
- **Primary**: TCP socket over Wi-Fi, discovered via Bonjour (NetService type `_macremote._tcp`)
- **Fallback**: MultipeerConnectivity framework (handles both Wi-Fi Direct and Bluetooth)
- Both transports use the same JSON message format

### Message Format (JSON over newline-delimited stream)
```json
{"type": "mousemove", "dx": 5.2, "dy": -3.1}
{"type": "click", "button": "left"}
{"type": "click", "button": "right"}
{"type": "scroll", "dx": 0, "dy": -10}
{"type": "keypress", "text": "hello"}
{"type": "hotkey", "modifiers": ["cmd"], "key": "c"}
{"type": "media", "action": "playpause"}
{"type": "media", "action": "volumeup"}
{"type": "media", "action": "volumedown"}
{"type": "media", "action": "next"}
{"type": "media", "action": "previous"}
{"type": "media", "action": "brightnessup"}
{"type": "media", "action": "brightnessdown"}
{"type": "media", "action": "mute"}
```

## macOS Server App (SwiftUI, menu bar app)

### Structure
```
MacRemoteServer/
├── MacRemoteServerApp.swift          # App entry, menu bar
├── Views/
│   └── StatusView.swift              # Menu bar popover showing status & connected devices
├── Networking/
│   ├── BonjourServer.swift           # NWListener + Bonjour advertisement
│   ├── MultipeerServer.swift         # MCNearbyServiceAdvertiser + MCSession
│   └── ConnectionManager.swift       # Unified interface over both transports
├── Input/
│   ├── MouseController.swift         # CGEvent-based mouse move/click/scroll
│   ├── KeyboardController.swift      # CGEvent-based key input
│   └── MediaController.swift         # Media key simulation (NX_KEYTYPE_PLAY, etc.)
├── Model/
│   └── RemoteCommand.swift           # Codable command structs
└── Info.plist                        # Accessibility permission description
```

### Key Implementation Details
- **Menu bar app**: Uses MenuBarExtra (macOS 13+)
- **Mouse control**: CGEvent with CGEventPost(.cghidEventTap, event)
- **Keyboard**: CGEvent for key events, supports Unicode text input
- **Media keys**: Use IOKit HID system events (NX_KEYTYPE_PLAY, NX_KEYTYPE_SOUND_UP, etc.)
- **Network**: Use Network.framework (NWListener/NWConnection) for TCP, Bonjour built-in
- **Permissions**: Needs Accessibility permission for CGEvent injection
- **Sandbox**: App must NOT be sandboxed (needs CGEvent access)

### Entitlements
- com.apple.security.app-sandbox = false (or remove entitlement)
- Accessibility access required (user grants in System Preferences)

## iOS App (SwiftUI)

### Structure
```
MacRemote/
├── MacRemoteApp.swift                # App entry
├── Views/
│   ├── ContentView.swift             # Tab-based main view
│   ├── ConnectionView.swift          # Device discovery & connection
│   ├── TouchpadView.swift            # Trackpad area + gesture recognition
│   ├── KeyboardView.swift            # Text input with system keyboard
│   └── MediaControlView.swift        # Media remote with buttons
├── Networking/
│   ├── BonjourBrowser.swift          # NWBrowser for service discovery
│   ├── MultipeerBrowser.swift        # MCNearbyServiceBrowser
│   └── ConnectionManager.swift       # Unified interface, auto-reconnect
├── Model/
│   └── RemoteCommand.swift           # Same Codable structs (shared)
└── Info.plist
```

### UI Design Principles
- Dark theme, modern look (SF Symbols, gradients, blur effects)
- Tab bar at bottom: Touchpad | Keyboard | Media | Connection
- **Touchpad tab**: Large touch area, single/double/right-tap, two-finger scroll, drag
- **Keyboard tab**: TextField that opens system keyboard + quick action buttons (Cmd+C/V/Z/A, arrows, Esc, Tab, Enter, Delete)
- **Media tab**: Large play/pause button center, prev/next on sides, volume slider, brightness slider, mute button
- **Connection tab**: List of discovered Macs, connection status, auto-reconnect toggle

### Gesture Recognition on Touchpad
- Single finger drag → mouse move
- Single tap → left click
- Double tap → double click  
- Two-finger tap → right click
- Two-finger drag → scroll
- Long press + drag → click and drag

## Shared Code
RemoteCommand.swift is identical in both projects (copy, not framework — simpler for user).

## Build Requirements
- Xcode 15+
- macOS 14+ (Sonoma) for server
- iOS 17+ for client
- No external dependencies (all Apple frameworks)
