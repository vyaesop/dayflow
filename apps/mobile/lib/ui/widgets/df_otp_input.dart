import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// Six-box verification code input with a single hidden text field driving it,
/// so paste, autofill, and keyboard navigation all behave natively.
class DfOtpInput extends StatefulWidget {
  const DfOtpInput({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.hasError = false,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  State<DfOtpInput> createState() => DfOtpInputState();
}

class DfOtpInputState extends State<DfOtpInput> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  String get _value => _controller.text;

  void clear() {
    _controller.clear();
    setState(() {});
    _focusNode.requestFocus();
  }

  void shake() => _shake.forward(from: 0);

  @override
  void didUpdateWidget(covariant DfOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) shake();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final progress = _shake.value;
        final offset = progress == 0 ? 0.0 : (progress * 6 * 3.14159).clamp(0, 18.85);
        return Transform.translate(
          offset: Offset(8 * (1 - progress) * (offset == 0 ? 0 : _wave(progress)), 0),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: widget.enabled ? _focusNode.requestFocus : null,
        child: Stack(
          children: [
            // Hidden real input.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onChanged: (value) {
                    setState(() {});
                    if (value.length == widget.length) widget.onCompleted(value);
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.length, (i) {
                final filled = i < _value.length;
                final isActive = i == _value.length && _focusNode.hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 46,
                  height: 56,
                  margin: EdgeInsets.only(right: i == widget.length - 1 ? 0 : DfSpacing.xs),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? DfColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(DfRadius.md),
                    border: Border.all(
                      color: widget.hasError
                          ? DfColors.danger
                          : isActive
                              ? DfColors.primary
                              : (isDark ? DfColors.borderDark : DfColors.border),
                      width: isActive || widget.hasError ? 1.6 : 1,
                    ),
                  ),
                  child: Text(
                    filled ? _value[i] : '',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  double _wave(double t) => (t < 0.5 ? 1 : -1) * (1 - (2 * t - 1).abs());
}
