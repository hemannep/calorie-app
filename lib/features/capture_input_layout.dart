import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The footer keeps its screen position; only the editor viewport avoids IME.
class CaptureInputLayout extends StatelessWidget {
  const CaptureInputLayout({
    super.key,
    required this.content,
    required this.footer,
  });
  final Widget content, footer;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _CaptureInputDelegate(MediaQuery.viewInsetsOf(context).bottom),
    children: [
      LayoutId(id: 'content', child: content),
      LayoutId(id: 'footer', child: footer),
    ],
  );
}

class _CaptureInputDelegate extends MultiChildLayoutDelegate {
  _CaptureInputDelegate(this.keyboardInset);
  final double keyboardInset;

  @override
  void performLayout(Size size) {
    final footer = layoutChild(
      'footer',
      BoxConstraints(
        maxWidth: size.width,
        maxHeight: size.height,
        minWidth: size.width,
      ),
    );
    positionChild('footer', Offset(0, size.height - footer.height));
    final contentHeight = math.max(
      0.0,
      size.height - math.max(footer.height, keyboardInset),
    );
    layoutChild(
      'content',
      BoxConstraints.tight(Size(size.width, contentHeight)),
    );
    positionChild('content', Offset.zero);
  }

  @override
  bool shouldRelayout(_CaptureInputDelegate oldDelegate) =>
      keyboardInset != oldDelegate.keyboardInset;
}
