# Payments.lk for Flutter

Open a [Payments.lk](https://payments.lk) hosted checkout from a Flutter app on iOS or Android, and get the outcome back through your app's own URL scheme. The customer pays on the hosted checkout, so card details never touch your app or your server.

- Flutter 3.24 or later, on iOS and Android
- The checkout opens in the system's authentication browser, through [`flutter_web_auth_2`](https://pub.dev/packages/flutter_web_auth_2): `ASWebAuthenticationSession` on iOS, a Custom Tab on Android
- The package never holds an API key and never sees card details

## How it fits together

1. Your app asks your server for a checkout for an order.
2. Your server creates it with its secret key, setting `successUrl` and `cancelUrl` to your app's scheme, such as `myshop://payments-lk/return`, and answers with the checkout's `id` and `url`.
3. The app calls `PaymentsLkCheckout().open`. The customer pays, and the checkout sends the browser to your scheme with `checkout=<id>&status=<outcome>`.
4. The app shows the outcome while it asks your server to confirm. Your server trusts only the API or the signed `payment.succeeded` webhook.

A secret key never goes in an app, and the return is never proof of payment: anyone can open a URL in your scheme.

## Install

```sh
flutter pub add payments_lk
```

## Register your scheme

**Android.** Add `flutter_web_auth_2`'s callback activity to `android/app/src/main/AndroidManifest.xml`, inside `<application>`, with your scheme:

```xml
<activity
    android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
    android:exported="true"
    android:taskAffinity="">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="myshop" />
    </intent-filter>
</activity>
```

**iOS.** Nothing to add: the authentication session catches the return itself.

A scheme is 3 to 40 lower case letters, digits, `+`, `.` or `-`, starting with a letter. Choose one only your app uses.

## Your server

With the [Node.js library](https://www.npmjs.com/package/@payments-lk/node):

```ts
app.post("/app/checkouts", requireSignedInCustomer, async (req, res) => {
  const order = await orders.forCustomer(req.user.id, req.body.orderId);
  const checkout = await lk.checkouts.create(
    { amountCents: order.totalCents, description: order.summary, reference: order.id, successUrl: "myshop://payments-lk/return", cancelUrl: "myshop://payments-lk/return" },
    { idempotencyKey: `order-${order.id}` },
  );
  res.json({ id: checkout.id, url: checkout.url });
});
```

## Your app

```dart
import 'package:payments_lk/payments_lk.dart';

final checkout = PaymentsLkCheckout();

Future<void> pay(String checkoutUrl) async {
  try {
    final result = await checkout.open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop');
    switch (result.status) {
      case CheckoutStatus.succeeded:
        showConfirming(); // then ask your server, which confirms with the API
      case CheckoutStatus.failed:
        showDeclined();
      case CheckoutStatus.canceled:
      case CheckoutStatus.expired:
      case CheckoutStatus.dismissed:
        showNotPaid();
    }
  } on PaymentsLkCheckoutException catch (error) {
    showCouldNotOpen(error.code);
  }
}
```

`result.checkoutId` is the checkout's id (`chk_...`) for every outcome except `dismissed`, when the customer closed the browser before the checkout finished. Pass `preferEphemeral: true` to open a private browser session that shares no cookies with the system browser.

| `error.code` | What happened |
|---|---|
| `insecureCheckoutUrl` | The URL is not https. Use `checkout.url` exactly as your server received it. |
| `invalidCallbackScheme` | The scheme is not an app's own, such as `myshop`. |
| `alreadyOpen` | Another checkout is open. |
| `couldNotOpen` | The system browser could not be opened. `error.cause` has the platform's error. |
| `unexpectedReturn` | The browser came back to your scheme without an outcome. |
| `invalidLink` | A subscription link's code or plan is not shaped like one. |

## Subscriptions and the customer portal

A subscription's first payment is an ordinary checkout, opened with `open`. A subscription link, where the customer picks a plan, and the customer portal, where they manage it, have no checkout of their own to report, so open them with `openPage`. It completes when the page returns to your scheme, or as `dismissed`:

```dart
final url = subscriptionLinkUrl(code: 'Gold_Plan-2026', plan: 'price_0123456789abcdefghij', email: customer.email);
final page = await checkout.openPage(url: url, callbackScheme: 'myshop');
if (page.status == PageStatus.returned) refreshSubscriptionFromYourServer();
```

The link's success address, set in the dashboard, and the portal session's return address must use your app's scheme.

## Testing

`PaymentsLkCheckout(authenticate: ...)` takes a function in place of the system browser, so a test can answer any return URL or throw `PlatformException(code: 'CANCELED')` for a closed browser. `parseCheckoutReturn`, `isAllowedCheckoutUrl` and `isValidCallbackScheme` are public, so your tests can run the same checks.

Sandbox keys (`sk_test_...`) and test cards are in the [developer guide](https://payments.lk/developers/guide).

## Support

Questions to hello@payments.lk. Security reports: see [SECURITY.md](https://github.com/PAYable-IPG/payments-lk-flutter/blob/main/SECURITY.md). What changed in each version is in `CHANGELOG.md`.
