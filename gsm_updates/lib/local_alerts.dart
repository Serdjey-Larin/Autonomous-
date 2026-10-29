import 'package:flutter/services.dart';
import 'device_service.dart';

class LocalAlerts {
  static const channel = MethodChannel('ru.larincold/alerts');
  Future<bool> permission() async => await channel.invokeMethod<bool>('permission') ?? false;
  Future<bool> exact() async => await channel.invokeMethod<bool>('exact') ?? false;
  Future<void> settings() async => channel.invokeMethod<void>('settings');
  Future<void> exactSettings() async => channel.invokeMethod<void>('exactSettings');
  Future<String?> selectedCar() => channel.invokeMethod<String>('selectedCar');
  Future<void> restore() => channel.invokeMethod<void>('restore');
  Future<void> cancel(String key) => channel.invokeMethod<void>('cancel', {'key': key});
  Future<void> timer(VehicleConfig car) => channel.invokeMethod<void>('schedule', {
    'key': 'timer_${car.id}', 'car': car.id, 'name': car.vehicleName, 'at': car.endMs,
    'daily': false, 'minutes': 0});
  Future<void> reminder(VehicleConfig car) => channel.invokeMethod<void>('schedule', {
    'key': 'reminder_${car.id}', 'car': car.id, 'name': car.vehicleName,
    'at': 0, 'daily': true, 'minutes': car.reminderMinutes});
}
