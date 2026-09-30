/// Open a Payments.lk hosted checkout from a Flutter app, and get the outcome
/// back through the app's own URL scheme.
///
/// Your server creates the checkout with its secret key, setting `successUrl`
/// and `cancelUrl` to your app's scheme, such as `myshop://payments-lk/return`.
/// The app opens `checkout.url` with [PaymentsLkCheckout.open]. The customer
/// pays on the hosted page, so card details never touch the app, and the
/// result tells the app what to show while it asks your server to confirm.
/// The return is never proof of payment: your server confirms from the API or
/// the signed `payment.succeeded` webhook.
library;

export 'src/checkout.dart';
export 'src/links.dart';
