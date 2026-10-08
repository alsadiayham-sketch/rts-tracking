# RTS Tracking

Flutter owner-monitoring app for two operational modes:

- **RTS Business**: sales, orders, store connectivity, stock alerts, and store-level status.
- **RTS Clinic**: appointments, waiting patients, clinic connectivity, follow-ups, and clinic-level status.

The app starts in clearly labeled demo mode unless a live endpoint is selected.
Live mode always starts behind owner authentication.

## Run and validate

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Android release builds include the Internet permission required by the live API.

## Live API configuration

Select a live API at build time:

```powershell
flutter run --dart-define=RTS_API_BASE_URL=https://api.example.com
```

The value is a base URL, so a path is supported (for example,
`https://api.example.com/rts/`) and the app appends `/owner/login` and
`/owner/dashboard`. Production deployments must use HTTPS; plain HTTP is only
accepted for local loopback testing.

CodeMagic release workflows read the non-secret `RTS_API_BASE_URL` from the
`rts_tracking_api` environment group and pass it with `--dart-define`. Do not
put credentials or access tokens in the URL or source code.

### Owner login contract

The configured API must accept:

```http
POST /owner/login
Content-Type: application/json
Accept: application/json

{"organizationName":"RTS Clinic Main","username":"owner","password":"password"}
```

Successful response:

```json
{
  "token": "opaque-access-token",
  "mode": "business",
  "organizationName": "RTS Business Main",
  "ownerName": "Owner name",
  "displayName": "Optional display name"
}
```

`token`, `mode`, and the submitted `organizationName` are required. `mode` must
be exactly `business` or `clinic`; the backend must verify that the supplied
business/clinic name belongs to the authenticated account.
the optional names must be non-empty strings when present. HTTP 401 or 403 is
shown as an invalid-credentials error. Connectivity failures, invalid
configuration, and other server failures are reported separately in the UI.

The authenticated `mode` is authoritative. Live users cannot switch products in
the app, and every dashboard request uses only that mode:

```http
GET /owner/dashboard?mode=business
Authorization: Bearer <token>
Accept: application/json
```

For a clinic-authenticated owner, the query value is `clinic` instead. The
backend must enforce the same owner-to-mode authorization; client-side mode
locking is not a security boundary.

Expected dashboard response:

```json
{
  "mode": "business",
  "metrics": [
    {"key": "salesToday", "label": "Sales today", "value": "₪18,420"}
  ],
  "sites": [
    {
      "id": "main-store",
      "name": "RTS Business Main Store",
      "online": true,
      "updatedLabel": "Updated just now",
      "primaryLabel": "Sales today",
      "primaryValue": "₪9,840",
      "attention": "2 low-stock items"
    }
  ],
  "alerts": [
    {
      "id": "low-stock",
      "title": "2 low-stock items need review",
      "detail": "RTS Business Mall",
      "level": "warning"
    }
  ],
  "synchronizedLabel": "Updated just now"
}
```

Alert levels are `info`, `warning`, and `critical`. A response whose `mode`
does not match the authenticated/requested mode is rejected.

## Connectivity behavior

- 12-second request, response, and body timeouts.
- Explicit loading, empty, authentication, and connection-error states.
- Last-known in-memory data remains visible if a refresh fails.
- Demo data never silently replaces a failed live response.
- Dashboard HTTP 401 or 403 clears the saved session and returns to login.

## Session security

- The access token and minimal session metadata needed to restore its mode are
  stored with `flutter_secure_storage` in platform-protected storage.
- Credentials are submitted to the login endpoint and are never persisted.
- The session is restored on startup. Because the contract has no token
  validation or refresh endpoint, validity is confirmed by the first dashboard
  request; a 401 or 403 removes the stored session.
- Logout removes the stored session before returning to login.
- Token expiry, refresh, revocation, and server-side owner/mode authorization
  remain backend responsibilities.

Offline dashboard persistence is not implemented.
