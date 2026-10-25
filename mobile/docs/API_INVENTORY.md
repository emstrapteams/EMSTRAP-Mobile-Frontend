# EMSTRAP API inventory (mobile)

Source of truth: `EMSTRAP-Mobile-Backend` (`app.js`, `src/routes/*`, `src/controllers/*`,
`src/middlewares/*`, `src/sockets/socket.js`) at commit `bcf1da0`, cross-checked against the web
client in this repo (`src/services/api.js`, `src/pages/**`).

**Verified live** = exercised against the backend running locally on 2026-10-24 (local MongoDB,
`ENABLE_AI=false`, no Cloudinary/SMTP credentials).

## Session mechanism

| Item | Value | Source |
|---|---|---|
| Login response | `{ success, message, token, user: {_id, name, email, role, driverStatus, isOnTrip, vehicleNumber}, ...same fields flattened }` | `auth.controller.js` `buildAuthResponse` |
| Token | JWT `{ id, role }`, `expiresIn: 7d`. No refresh endpoint. | `generateTokenAndSetCookie` |
| How the app authenticates | `Authorization: Bearer <token>` (middleware reads cookie `token` first, then Bearer) | `auth.middleware.js` |
| Web app | HttpOnly cookie + same Bearer token from `localStorage` | web `services/api.js` |
| App storage | `flutter_secure_storage` (Android Keystore), key `auth_token` | `core/storage/token_storage.dart` |
| Current user | `GET /auth/me` → **bare user document** (no `user` wrapper) | `getMe` — verified live |
| Logout | `POST /auth/logout` clears the cookie only; the JWT is not revoked server-side | `logoutUser` |
| Expired/invalid token | `401 {success:false, message:"Invalid or expired token"}` | verified live |
| Error format | `{ success?: false, message: string }`; 5xx bodies contain raw `error.message` (never shown in the app) | all controllers |
| CORS | Requests without `Origin` (mobile) are allowed | `app.js` |

## Roles

`user`, `ambulance_driver` (alias `ambulance`), `private_driver`, `hospital` / `hospital_admin`,
`police` / `police_hq`, `admin`. Self-registration accepts only `user` and `ambulance_driver`.
Email verification is required to log in, except for admin/hospital/police roles.

## Endpoints used by the app (milestone 1)

| Feature | Method | Path | Auth | Request | Response | Errors | Verified |
|---|---|---|---|---|---|---|---|
| Login | POST | `/auth/login` | none | `{email, password}` (email lower-cased) | see above | 400 missing fields · 404 "User not found" · 401 "Invalid credentials" / "Please verify your email to login" | ✅ |
| Register | POST | `/auth/register` | none | `{name, email, password, mobile, city, address, role, vehicleNumber?}` | 201 `{message}` | 400 mobile/password/role/"User already exists" · 500 email send failed (user NOT saved) | ✅ |
| Verify email | GET | `/auth/verify-email/:token` | none | — | `{message}` | 400 invalid/expired | ✅ (link opens the web app) |
| Current user | GET | `/auth/me` | Bearer | — | user document | 401 | ✅ |
| Logout | POST | `/auth/logout` | none | — | `{message}` | — | ✅ |
| Photo precheck | POST | `/api/emergency/precheck` | **none** | `{imageUrl: data URL, latitude, longitude}` (lat/lng unused) | 200 `{secureImageUrl, warningRequired, priority, aiAnalysis{predictedClass, confidence, severity, recommendedAmbulance, allProbabilities}}` | 400 no image · 500 "Image upload failed" · **503 AI disabled — still returns `secureImageUrl`** | ✅ 500 path (no Cloudinary locally) |
| Create emergency | POST | `/api/emergency` | optional | `{latitude, longitude, imageUrl?}` (Cloudinary URL from precheck, or data URL) | 201 `{success, data: EmergencyRequest}` | 500 | ✅ anon + signed in |
| Emergency details | GET | `/api/emergency/:id` | optional | — | `{success, data}`; `ambulance` populated `{name, email, mobile, vehicleNumber, currentLocation}`, `hospital` populated; live locations overlaid | 404 · 403 if signed in and not owner/driver/staff | ✅ |
| My emergencies | GET | `/api/emergency` | Bearer | — | `{success, data: EmergencyRequest[]}` newest first | 401 | ✅ |
| Cancel (user) | PUT | `/api/emergency/:id/user-cancel` | optional | — | `{success, message, data}` | 404 · 400 "Emergency already closed." | ✅ |
| Add evidence photo | POST | `/api/emergency/:id/evidence` | optional | `{imageUrl}` | `{success, evidence[]}` | 400 · 404 · 500 | ❌ needs Cloudinary |

### `EmergencyRequest` (from `emergencyRequest.model.js`)

`_id, user?, imageUrl, location{latitude, longitude}, evidence[], embedding[], duplicateDetected,
duplicateOf, similarityScore, aiAnalysis{predictedClass, confidence, severity, recommendedAmbulance,
allProbabilities}, status, hospitalResolved*, ambulance, hospital, declinedBy[], requestType, createdAt, updatedAt`

Status enum: `PENDING → AMBULANCE_ACCEPTED → ARRIVED_AT_LOCATION → EN_ROUTE_TO_HOSPITAL → COMPLETED`, or `CANCELLED`.

⚠️ With AI disabled, `aiAnalysis` is still stored with schema defaults (`predictedClass: ""`,
`severity: "LOW"`). The app treats AI as present only when `predictedClass` is non-empty.

⚠️ `duplicateDetected: true` → the request is created but **not broadcast to ambulances**.

## Socket.IO (`src/sockets/socket.js`)

Same origin as REST. **No handshake authentication.** The app uses one connection (websocket transport).

| Direction | Event | Payload | Notes |
|---|---|---|---|
| app → server | `track_request` | `{requestId}` | Joins room `request_<id>`. Re-sent on every (re)connect. |
| app → server | `update_user_location` | `{requestId, latitude, longitude}` | Sent only while status is `AMBULANCE_ACCEPTED` and location permission was already granted. Persisted (throttled 5 s). |
| server → room | `ambulance_assigned` | `{eta:"Calculating...", driverName, driverMobile, vehicleNumber, hospitalName, hospitalLocation}` | **no requestId** |
| server → room | `emergency_updated` | full EmergencyRequest | accept / arrive / hospital / complete |
| server → room | `driver_arrived` | `{requestId, status}` | |
| server → room | `hospital_assigned` | full request | |
| server → room | `ambulance_location` | `{requestId, lat, lng}` | from driver `update_location` |
| server → room | `trip_completed` | `{requestId, status}` | |
| server → room | `emergency_cancelled` | `{requestId, status}` | |

All verified live except `hospital_assigned` / `trip_completed` (need the driver hospital flow).
The app treats every event except `ambulance_location` as a signal to refetch `GET /api/emergency/:id`.

## Endpoints for later milestones (not used yet; from routes, not yet verified)

| Area | Endpoints |
|---|---|
| Gov. driver | `GET /api/ambulances/pending` ✅, `PUT /api/emergency/:id/{accept ✅, decline, cancel, mark-arrived ✅, assign-hospital, complete}`, `GET /api/emergency/driver/history`, `PUT /api/ambulances/{status, location, profile}`, `GET /api/ambulances/{current-emergency, history}`, `GET /api/hospitals/available` |
| Private driver | `GET /api/bookings/{available, driver/dashboard, history}`, `PUT /api/bookings/:id/{accept, decline, arrive, start, complete}`, `GET /api/private-drivers/{current-booking, pending}`, `PUT /api/private-drivers/{status, location, profile}`; sockets `join_private_driver`, `new_booking_request`, `booking_*` |
| User bookings | `POST/GET /api/bookings`, `GET /api/bookings/:id`, `PUT /api/bookings/:id/cancel`, `GET /api/bookings/:id/payment`, `POST /api/bookings/:id/pay` |
| Hospital | `GET /api/hospitals/patients`, `PUT /api/hospitals/patients/:id/resolve`, `PATCH /api/hospitals/update-beds`, `GET/PUT /api/hospitals/profile`, `GET /api/alerts`, `PUT /api/emergencies/:id/status`; sockets `join_hospital`, `hospital_alert` |
| Police | `GET /api/police/{emergencies, cases}`, `PUT /api/police/cases/:id/status`; sockets `join_police`, `police_alert`, `police_new_case` |
| Admin | `/api/admin/*`, `/api/users`, CRUD on `/api/hospitals`, `/api/police`, `/api/ambulances`, `/api/private-drivers` |

## Upload limits

`express.json({ limit: "50mb" })`. Images go as base64 data URLs inside JSON; there is no multipart
route. The app downsizes to ≤1280 px at 70% JPEG quality and refuses files over 8 MB.

## Environment

| Setting | Value |
|---|---|
| `API_BASE_URL` (dart-define) | Emulator + local backend: `http://10.0.2.2:5050` (debug default). Physical device: `http://<Mac LAN IP>:5050`. Release builds require it. |
| Local backend | `PORT=5050` (macOS AirPlay occupies 5000), local MongoDB, `ENABLE_AI=false` |
| Render | `https://emstrap-finalworking.onrender.com` — unreachable on 2026-10-24 |
