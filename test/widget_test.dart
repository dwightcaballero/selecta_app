import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/data/notifiers.dart';

void main() {
  test('App font scale notifier default and update test', () {
    expect(appFontScaleNotifier.value, 1.0);
    appFontScaleNotifier.value = 1.15;
    expect(appFontScaleNotifier.value, 1.15);
    appFontScaleNotifier.value = 0.90;
    expect(appFontScaleNotifier.value, 0.90);
    appFontScaleNotifier.value = 1.0;
  });
}
