import 'package:dayflow/core/theme/theme.dart';
import 'package:dayflow/core/theme/tokens.dart';
import 'package:dayflow/ui/widgets/df_avatar.dart';
import 'package:dayflow/ui/widgets/df_button.dart';
import 'package:dayflow/ui/widgets/df_misc.dart';
import 'package:dayflow/ui/widgets/df_otp_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? dayflowLightTheme() : dayflowDarkTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('DfButton fires onPressed and swaps to a spinner while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(DfButton(label: 'Log in', onPressed: () => taps++)));

    await tester.tap(find.text('Log in'));
    expect(taps, 1);

    await tester.pumpWidget(_host(const DfButton(label: 'Log in', loading: true)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('DfButton with a null callback is inert', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(DfButton(label: 'Next', onPressed: null)));
    await tester.tap(find.text('Next'));
    expect(taps, 0);
  });

  testWidgets('DfOtpInput reports the code once all six digits are entered', (tester) async {
    String? completed;
    await tester.pumpWidget(_host(DfOtpInput(onCompleted: (code) => completed = code)));

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(completed, isNull, reason: 'must not fire before the field is full');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(completed, '123456');
  });

  testWidgets('DfAvatar renders two-letter initials', (tester) async {
    await tester.pumpWidget(_host(const DfAvatar(name: 'Alex Smith')));
    expect(find.text('AS'), findsOneWidget);
  });

  testWidgets('DfAvatar falls back to one initial for a single-word name', (tester) async {
    await tester.pumpWidget(_host(const DfAvatar(name: 'Dayflow')));
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('DfStatusPill shows its label', (tester) async {
    await tester.pumpWidget(_host(const DfStatusPill(label: 'Working on it', colorToken: 'amber')));
    expect(find.text('Working on it'), findsOneWidget);
  });

  testWidgets('DfProgressRing animates to the given percent', (tester) async {
    await tester.pumpWidget(_host(const DfProgressRing(percent: 33)));
    expect(find.text('33%'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    final indicator = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(indicator.value, closeTo(0.33, 0.001));
  });

  testWidgets('both themes build without error', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_host(const DfAvatar(name: 'Alex Smith'), brightness: brightness));
      expect(tester.takeException(), isNull);
    }
  });

  test('color tokens resolve by name and fall back for unknown values', () {
    expect(DfColors.token('green'), DfColors.accentGreen);
    expect(DfColors.token('not-a-color'), DfColors.statusGrey);
  });

  test('avatar colors are stable for the same seed', () {
    expect(DfColors.avatarFor('u1'), DfColors.avatarFor('u1'));
  });
}
