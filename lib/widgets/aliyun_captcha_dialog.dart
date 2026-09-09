// Captcha dialog — wraps CaptchaWidget.
import 'package:flutter/material.dart';
import 'aliyun_captcha_widget.dart' show CaptchaWidget;

class CaptchaDialog extends StatelessWidget {
  const CaptchaDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verification required'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Free guest mode requires solving a captcha before each '
              'chat session.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            CaptchaWidget(
              onSolved: (param) => Navigator.of(context).pop(param),
              onError: (err) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Captcha: $err')),
                );
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
