# Changelog

## 0.1.0 (30 September 2026)

The first version.

- `PaymentsLkCheckout.open` opens a hosted checkout in the system's authentication browser (`ASWebAuthenticationSession` on iOS, a Custom Tab on Android, through `flutter_web_auth_2`) and answers the outcome from the checkout's return to your app's scheme: `succeeded`, `failed`, `canceled`, `expired`, or `dismissed` when the customer closes the browser.
- `PaymentsLkCheckout.openPage` and `subscriptionLinkUrl` open a subscription link or the customer portal and report whether the page returned to the app.
- The same checks as the React Native, iOS and Android SDKs: https checkout URLs only (plain http on this machine or the Android emulator's host, for testing), an app scheme that is not a web or script scheme, and a return with exactly one checkout id and one outcome.
