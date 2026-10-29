import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/device_service.dart';
import 'package:larin_cold_gsm_control/main.dart';
import 'package:flutter/material.dart';
void main() {
  test('each vehicle retains independent timer and reminder across serialization', () {
    final start = DateTime(2026,10,29,7);
    final a=VehicleConfig(id:'a',vehicleName:'Газель',durationMinutes:30,cycleMinutes:30,
      endMs:start.add(const Duration(minutes:30)).millisecondsSinceEpoch,reminderMinutes:420);
    final b=VehicleConfig(id:'b',vehicleName:'Transit',durationMinutes:60);
    final restored=VehicleConfig.fromJson(a.toJson());
    expect(restored.secondsLeft(start.add(const Duration(minutes:15))),900);
    expect(restored.secondsLeft(start.add(const Duration(minutes:31))),0);
    expect(restored.reminderMinutes,420);
    expect(b.endMs,isNull);
    a.durationMinutes=60;
    expect(a.secondsLeft(start.add(const Duration(minutes:15))),900);
    expect(a.cycleMinutes,30);
  });
  test('pending command survives restart without claiming a launch', () {
    final a=VehicleConfig(id:'a',pendingCommand:'START',pendingSince:100);
    final restored=VehicleConfig.fromJson(a.toJson());
    expect(restored.pendingCommand,'START');expect(restored.endMs,isNull);
  });
  testWidgets('main application can be mounted', (tester) async {
    await tester.pumpWidget(const LarinGsmApp());
    expect(find.byType(MaterialApp),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
