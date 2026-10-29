import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/device_service.dart';
import 'package:larin_cold_gsm_control/main.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter/services.dart';
final class MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final values = <String, Object>{};
  @override
  dynamic noSuchMethod(Invocation call) {
    final key = call.positionalArguments.isEmpty ? '' : call.positionalArguments.first as String;
    if (call.memberName == #getString) return Future<String?>.value(values[key] as String?);
    if (call.memberName == #getInt) return Future<int?>.value(values[key] as int?);
    if (call.memberName == #setString) { values[key] = call.positionalArguments[1] as String; return Future<void>.value(); }
    return super.noSuchMethod(call);
  }
}
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
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ru.larincold/alerts'), (call) async => null);
    await tester.pumpWidget(const LarinGsmApp());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
