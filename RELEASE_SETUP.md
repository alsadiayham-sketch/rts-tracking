# RTS Tracking release setup

The repository contains `codemagic.yaml` for Android App Bundle and iOS IPA builds.

Configure these CodeMagic resources without committing secrets:

- Android keystore named `rts_tracking_keystore`.
- Environment group `rts_tracking_play` containing `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`.
- iOS App Store Connect integration and environment group `rts_tracking_app_store`.
- Android application ID: `com.rts.tracking`.
- iOS bundle identifier: `com.rts.tracking`.

Google Play and Apple Developer app records, signing certificates, provisioning profiles, and CodeMagic integrations must be created in their respective dashboards. This repository only contains the build wiring.
