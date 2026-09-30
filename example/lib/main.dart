// A button that pays for an order with Payments.lk. Your server creates the
// checkout with its secret key, with successUrl and cancelUrl in the app's
// scheme (myshop://payments-lk/return); the app opens it and shows the outcome
// while the server confirms it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:payments_lk/payments_lk.dart';

void main() => runApp(const MaterialApp(home: PayScreen()));

/// One order, one button.
class PayScreen extends StatefulWidget {
  /// The screen.
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  final PaymentsLkCheckout _checkout = PaymentsLkCheckout();
  String _message = 'Chicken kottu, Rs. 1,450.00';

  Future<void> _pay() async {
    try {
      // Your own endpoint: it prices the order from your records and answers the checkout's id and url.
      final HttpClient http = HttpClient();
      final HttpClientRequest request =
          await http.postUrl(Uri.parse('https://yourshop.lk/app/checkouts'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'orderId': 'order-8891'}));
      final HttpClientResponse response = await request.close();
      final Map<String, dynamic> created =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;

      final CheckoutResult result = await _checkout.open(
          checkoutUrl: created['url'] as String, callbackScheme: 'myshop');
      setState(() {
        _message = switch (result.status) {
          CheckoutStatus.succeeded => 'Confirming your payment...',
          CheckoutStatus.failed => 'The card was declined.',
          CheckoutStatus.canceled ||
          CheckoutStatus.expired ||
          CheckoutStatus.dismissed =>
            'Not paid yet.',
        };
      });
      // Then ask your server, which confirms with the API or the signed payment.succeeded webhook.
    } on PaymentsLkCheckoutException catch (error) {
      setState(
          () => _message = 'Could not open the checkout: ${error.code.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(_message),
          const SizedBox(height: 16),
          FilledButton(onPressed: _pay, child: const Text('Pay with card')),
        ]),
      ),
    );
  }
}
