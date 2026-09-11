import 'package:flutter_test/flutter_test.dart';
import 'package:location_baohuo/main.dart';

void main() {
  testWidgets('renders the location background demo', (tester) async {
    await tester.pumpWidget(const LocationBackgroundApp());

    expect(find.text('iOS 后台定位计数 Demo'), findsOneWidget);
    expect(find.text('每分钟计数'), findsOneWidget);
  });
}
