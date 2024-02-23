import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry/src/sentry_tracer.dart';
import 'package:sentry_flutter/src/integrations/app_start/app_start_tracker.dart';
import 'package:sentry_flutter/src/navigation/time_to_initial_display_tracker.dart';
import 'package:sentry_flutter/src/sentry_flutter_measurement.dart';

import '../fake_frame_callback_handler.dart';
import '../mocks.dart';

void main() {
  PageRoute<dynamic> route(RouteSettings? settings) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => Container(),
        settings: settings,
      );

  late Fixture fixture;

  setUp(() {
    fixture = Fixture();
  });

  testWidgets('SentryDisplayWidget reports manual ttid span after didPush',
      (WidgetTester tester) async {
    final currentRoute = route(RouteSettings(name: 'Current Route'));

    await tester.runAsync(() async {
      fixture.navigatorObserver.didPush(currentRoute, null);
      await tester.pumpWidget(fixture.getSut());
      await fixture.navigatorObserver.completedDisplayTracking?.future;
    });

    final tracer = fixture.hub.getSpan() as SentryTracer;
    final spans = tracer.children.where((element) =>
        element.context.operation ==
        SentrySpanOperations.uiTimeToInitialDisplay);

    expect(spans, hasLength(1));
    final ttidSpan = spans.first;
    expect(ttidSpan.context.operation,
        SentrySpanOperations.uiTimeToInitialDisplay);
    expect(ttidSpan.finished, isTrue);
    expect(ttidSpan.context.description, 'Current Route initial display');
    expect(ttidSpan.origin, SentryTraceOrigins.manualUiTimeToDisplay);
    expect(tracer.measurements, hasLength(1));
    final measurement = tracer.measurements['time_to_initial_display'];
    expect(measurement, isNotNull);
    expect(measurement?.unit, DurationSentryMeasurementUnit.milliSecond);
  });

  testWidgets('SentryDisplayWidget is ignored for app starts',
      (WidgetTester tester) async {
    final currentRoute = route(RouteSettings(name: '/'));

    await tester.runAsync(() async {
      fixture.navigatorObserver.didPush(currentRoute, null);
      await tester.pumpWidget(fixture.getSut());
      AppStartTracker().setAppStartInfo(AppStartInfo(
        DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
        DateTime.fromMillisecondsSinceEpoch(10).toUtc(),
        SentryFlutterMeasurement.timeToInitialDisplay(
          Duration(milliseconds: 10),
        ),
      ));
      await fixture.navigatorObserver.completedDisplayTracking?.future;
    });

    final tracer = fixture.hub.getSpan() as SentryTracer;
    final spans = tracer.children.where((element) =>
        element.context.operation ==
        SentrySpanOperations.uiTimeToInitialDisplay);

    expect(spans, hasLength(1));

    final ttidSpan = spans.first;
    expect(ttidSpan.context.operation,
        SentrySpanOperations.uiTimeToInitialDisplay);
    expect(ttidSpan.finished, isTrue);
    expect(ttidSpan.context.description, 'root ("/") initial display');
    expect(ttidSpan.origin, SentryTraceOrigins.autoUiTimeToDisplay);

    expect(ttidSpan.startTimestamp,
        DateTime.fromMillisecondsSinceEpoch(0).toUtc());
    expect(
        ttidSpan.endTimestamp, DateTime.fromMillisecondsSinceEpoch(10).toUtc());

    expect(tracer.measurements, hasLength(1));
    final measurement = tracer.measurements['time_to_initial_display'];
    expect(measurement, isNotNull);
    expect(measurement?.value, 10);
    expect(measurement?.unit, DurationSentryMeasurementUnit.milliSecond);
  });
}

class Fixture {
  final Hub hub =
      Hub(SentryFlutterOptions(dsn: fakeDsn)..tracesSampleRate = 1.0);
  late final SentryNavigatorObserver navigatorObserver;
  late final TimeToInitialDisplayTracker timeToInitialDisplayTracker;
  final fakeFrameCallbackHandler = FakeFrameCallbackHandler();

  Fixture() {
    SentryFlutter.native = TestMockSentryNative();
    navigatorObserver = SentryNavigatorObserver(hub: hub);
    timeToInitialDisplayTracker = TimeToInitialDisplayTracker(
        frameCallbackHandler: fakeFrameCallbackHandler);
  }

  MaterialApp getSut() {
    return MaterialApp(
      home: SentryDisplayWidget(
        frameCallbackHandler: FakeFrameCallbackHandler(
          finishAfterDuration: Duration(milliseconds: 50),
        ),
        child: Text('my text'),
      ),
    );
  }
}