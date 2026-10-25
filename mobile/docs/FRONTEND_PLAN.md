# EMSTRAP mobile — frontend plan & status

## Decisions (2026-10-24)

- The Flutter app lives in `mobile/` inside `EMSTRAP-Mobile-Frontend`, next to the React web app, which is untouched.
- Emergencies can be requested **with or without** logging in (matches backend `optionalAuth` and the web app).
- Development uses the backend run locally; Render later.
- No backend changes. Gaps are documented below for the team.

## Architecture

```
lib/
  main.dart / app.dart          bootstrap, ProviderScope, MaterialApp.router
  core/
    config/       AppConfig from --dart-define
    network/      Dio client, auth interceptor, safe logging, ApiException
    realtime/     single Socket.IO connection (RealtimeService)
    routing/      go_router + pure authRedirect()
    storage/      SecureStore, TokenStorage
    theme/        tokens + Material 3 theme
  shared/widgets/ AppButton, StatusChip, InlineMessage, EmergencyCallBar, …
  features/
    auth/         login, register, session restore, profile
    home/         home for signed-out visitors and `user` accounts
    emergency/    request flow, tracking, history
    workspace/    landing for roles whose tools aren't built yet
```

State: Riverpod 2 `Notifier`s (no code generation). Models: hand-written typed classes.

## Milestone 1 — done

| Item | Status |
|---|---|
| Foundation: config, theme/tokens, Dio client, error mapping, secure token storage | ✅ |
| Auth: login, register (+ check-email), session restore via `/auth/me`, logout, 401 → signed out | ✅ |
| Role-based routing (role from backend only) | ✅ |
| User emergency flow: GPS → optional photo → AI precheck → create → track | ✅ (photo path blocked locally by missing Cloudinary) |
| Tracking: REST + Socket.IO, reconnect catch-up, polling fallback, live ambulance position, patient location sharing while the ambulance is on its way, cancel, add photo | ✅ |
| History for signed-in users; resume an active request after restart | ✅ |
| Unit + widget tests (74), live end-to-end tests against the local backend (4) | ✅ |
| Android debug build | ✅ (needs JDK 17–24, see README) |
| Emulator run, driven end to end on 2026-10-25 (Pixel 8, Android 15) | ✅ anonymous request → driver accept → live locations both ways → arrival (GPS released) → cancel; login, session restore after kill, history, logout, driver role routing |
| Physical device | ⏳ not yet |

## Next milestones

1. **Government ambulance driver**: available requests (`/api/ambulances/pending` + `new_emergency_request`), accept/decline, arrive, assign hospital, complete, location updates, history.
2. **Private booking**: user booking flow + private driver accept/decline/arrive/start/complete.
3. **Hospital / police / admin** screens that exist in the web app.
4. Release setup: app icon, signing, HTTPS API URL, push notifications (needs backend work).

## Product rules the app enforces

- Success is shown only after the backend returns the created request.
- `POST /api/emergency` is never retried automatically. After a timeout, signed-in users are reconciled against their history; otherwise the user is told the outcome is unknown and decides.
- No invented ETA, expiry, severity or dispatch claims. Elapsed time is shown while `PENDING`.
- AI output is labelled "AI-generated", "not a medical assessment".
- 108 / 112 direct-dial is on every emergency screen.
- No IP geolocation fallback; no background location.
- Debug logs: method, path, status, duration only.

## Backend gaps to raise with the team (not changed)

1. Socket.IO has no authentication (any client can join any room or send locations).
2. `GET /api/emergency/:id` returns the full record (name, mobile, location) to anonymous callers.
3. `PUT /api/emergency/:id/user-cancel` has no ownership check.
4. `acceptEmergency` is check-then-update (race between drivers); conflict returns 400, not 409.
5. "Nearest hospital" is `Hospital.findOne()`.
6. Login logs plaintext passwords; `server.js` logs `EMAIL_PASS`; default admin password `312` when unset.
7. `forgot-password` with `platform: "mobile"` emails a hardcoded Expo URL — the app doesn't offer password reset yet.
8. No server-side expiry for `PENDING` emergencies; no push notifications.
9. Duplicate requests are stored but not broadcast; the user only learns from `duplicateDetected`.
