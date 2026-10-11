# RTS Tracking release setup

The repository contains `codemagic.yaml` for Android App Bundle and iOS IPA builds.

Configure these CodeMagic resources without committing secrets:

- Android keystore named `rts_tracking_keystore`.
- Environment group `rts_tracking_play` containing `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`.
- iOS App Store Connect integration and environment group `rts_tracking_app_store`.
- Android application ID: `com.rts.tracking`.
- iOS bundle identifier: `com.rts.tracking`.

Google Play and Apple Developer app records, signing certificates, provisioning profiles, and CodeMagic integrations must be created in their respective dashboards. This repository only contains the build wiring.

The Android and iOS workflows set the non-secret `RTS_API_BASE_URL` to the
deployed RTS Royal host, `https://rts-royal.pages.dev`, and pass it to Flutter
with `--dart-define`. Native builds created outside CodeMagic must pass an
explicit value; missing configuration fails closed so development builds never
connect to production by accident.

The compatible backend must expose `/owner/login` and `/owner/dashboard` below
the configured base path. Production URLs must use HTTPS, and URLs must not
contain credentials, query parameters, or fragments.
