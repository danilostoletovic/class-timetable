# Android Release Signing Key & Certificate

This folder contains the release signing credentials and exported certificates for the **Class Timetable** Android application.

## Credentials

- **Keystore File**: `upload-keystore.jks` (also located at `android/app/upload-keystore.jks`)
- **Key Alias**: `upload`
- **Store Password**: `TimetableRelease2026!`
- **Key Password**: `TimetableRelease2026!`
- **Validity**: 10,000 days (valid until 2054)
- **Key Type**: RSA 2048-bit (SHA384withRSA)

## Exported Certificates

- **`upload_certificate.pem`**: Public certificate in standard RFC/PEM format (`-----BEGIN CERTIFICATE-----`), suitable for Google Play Console App Signing upload or web validation.
- **`upload_certificate.crt`**: Public certificate in binary DER format.

## Certificate Fingerprints

- **SHA-256**: `47:73:06:7C:BD:99:57:A6:EE:7C:0E:B8:7F:F5:1D:5A:A2:CC:45:05:0D:1A:2A:CD:65:CF:3B:BA:0A:DD:16:73`
- **SHA-1**: `21:54:77:D5:D6:16:8B:01:6A:61:3C:2F:77:CA:40:5E:33:CA:CB:B2`
- **Owner & Issuer**: `CN=Class Timetable Release, OU=Mobile, O=TimetableApp, L=Belgrade, ST=Serbia, C=RS`
