# RTS Tracking

Flutter owner-monitoring app for two operational modes:

- **RTS Business**: sales, orders, store connectivity, stock alerts, and store-level status.
- **RTS Clinic**: appointments, waiting patients, clinic connectivity, follow-ups, and clinic-level status.

The app starts in clearly labeled demo mode unless a live endpoint is selected.

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

The client requests:

```text
GET /owner/dashboard?mode=business
GET /owner/dashboard?mode=clinic
Authorization: Bearer <owner token>
Accept: application/json
```

`RtsTrackingApp` and `OwnerApi` support injection of an authenticated
`AuthTokenProvider`. The repository does **not** include an identity-provider
SDK, tenant/client IDs, token scopes, or a sign-in endpoint, so live builds fail
closed until the product's owner-auth contract is supplied.

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
does not match the requested mode is rejected.

## Connectivity behavior

- 12-second request, response, and body timeouts.
- Explicit loading, empty, authentication, and connection-error states.
- Last-known in-memory data remains visible if a refresh fails.
- Demo data never silently replaces a failed live response.

Offline persistence is not implemented because the repository has no approved
storage/encryption choice or data-retention requirements.
