// Phase 0's one test: the app must build and show its shell without
// throwing. It deliberately does not assert on live network data (that's
// what the backend/API-level checks in README's verification steps are
// for) — a widget test has no real backend to call.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app/app.dart';

void main() {
  testWidgets('App shell builds and shows the system status heading', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WarehouseOsApp()));

    // The health checks themselves will resolve to an error in this test
    // environment (no backend running) — that's fine; we're only proving
    // the app shell renders, not asserting live data.
    await tester.pump();

    expect(find.text('System status'), findsOneWidget);
  });
}
