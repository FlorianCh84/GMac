# Contributing to GMac

## Setup

1. Clone the repository
2. Open `GMac.xcodeproj` in Xcode 26+
3. Create a Google Cloud project with Gmail API v1 and Drive API v3 enabled
4. Create OAuth 2.0 credentials (macOS desktop app type)
5. Fill in `GMac/Resources/Info.plist` :
   - `GOOGLE_CLIENT_ID` : your OAuth client ID
   - `GOOGLE_CLIENT_SECRET` : your OAuth client secret

> **Note:** For native macOS apps, Google treats the client secret as non-secret (public client). It is visible in the compiled binary. Do not use this credential for server-side operations.

## Rules

- No force-unwraps (`!`) — SwiftLint enforces this as an error
- All new Services must implement a protocol (testable without network)
- All mutations through `SessionStore` must use `pendingOperations` + `defer`
- Tests required for every new Service and every new mutation path
- No `@testable import` workarounds for production code — keep access levels correct

## Tests

```bash
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64'
```
