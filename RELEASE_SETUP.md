# RTS Tracking release setup

The repository contains `codemagic.yaml` for Android App Bundle and iOS IPA builds.

Configure these CodeMagic resources without committing secrets:

- Android keystore named `rts_tracking_keystore`.
- Environment group `rts_tracking_play` containing `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`.
- Environment group `rts_tracking_api` containing the non-secret
  `RTS_API_BASE_URL` value, including the HTTPS API base path.
- iOS App Store Connect integration and environment group `rts_tracking_app_store`.
- Android application ID: `com.rts.tracking`.
- iOS bundle identifier: `com.rts.tracking`.

Google Play and Apple Developer app records, signing certificates, provisioning profiles, and CodeMagic integrations must be created in their respective dashboards. This repository only contains the build wiring.

The Android and iOS workflows pass `RTS_API_BASE_URL` to Flutter with
`--dart-define`; the value is never embedded in source control. Set it to the
deployed API base URL, for example `https://api.example.com/rts/`, so the app
requests `/owner/login` and `/owner/dashboard` below that path. Production
URLs must use HTTPS.
