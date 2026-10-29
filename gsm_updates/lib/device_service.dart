import 'dart:convert';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'protocol.dart';

class VehicleConfig {
  VehicleConfig({
    this.deviceNumber = '',
    this.ownerNumber = '',
    this.vehicleName = 'Мой автомобиль',
    this.durationMinutes = 30,
    this.ussdCode = '',
    this.id = 'primary',
    this.endMs,
    this.cycleMinutes = 30,
    this.reminderMinutes,
    this.pendingCommand,
    this.pendingSince,

  });

  String id;
  int? endMs;
  int cycleMinutes;
  int? reminderMinutes;
  String? pendingCommand;
  int? pendingSince;
  int secondsLeft(DateTime now) => endMs == null ? 0 : ((endMs! - now.millisecondsSinceEpoch) / 1000).ceil().clamp(0, cycleMinutes * 60);
  Map<String, dynamic> toJson() => {'id': id, 'deviceNumber': deviceNumber, 'ownerNumber': ownerNumber,
    'vehicleName': vehicleName, 'durationMinutes': durationMinutes, 'ussdCode': ussdCode,
    'endMs': endMs, 'cycleMinutes': cycleMinutes, 'reminderMinutes': reminderMinutes,
    'pendingCommand': pendingCommand, 'pendingSince': pendingSince};
  factory VehicleConfig.fromJson(Map<String, dynamic> j) => VehicleConfig(
    id: j['id'] as String, deviceNumber: j['deviceNumber'] as String? ?? '',
    ownerNumber: j['ownerNumber'] as String? ?? '', vehicleName: j['vehicleName'] as String? ?? 'Автомобиль',
    durationMinutes: j['durationMinutes'] as int? ?? 30, ussdCode: j['ussdCode'] as String? ?? '',
    endMs: j['endMs'] as int?, cycleMinutes: j['cycleMinutes'] as int? ?? 30,
    reminderMinutes: j['reminderMinutes'] as int?, pendingCommand: j['pendingCommand'] as String?,
    pendingSince: j['pendingSince'] as int?);
  String deviceNumber;
  String ownerNumber;
  String vehicleName;
  int durationMinutes;
  String ussdCode;
}

class DeviceService {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<VehicleConfig> load() async {
    final minutes = await _prefs.getInt('durationMinutes') ?? 30;
    return VehicleConfig(
      deviceNumber: await _prefs.getString('deviceNumber') ?? '',
      ownerNumber: await _prefs.getString('ownerNumber') ?? '',
      vehicleName: await _prefs.getString('vehicleName') ?? 'Мой автомобиль',
      durationMinutes: GsmProtocol.validDuration(minutes) ? minutes : 30,
      ussdCode: await _prefs.getString('ussdCode') ?? '',
    );
  }

  Future<({List<VehicleConfig> cars, String selected})> loadGarage() async {
    final raw = await _prefs.getString('garage149');
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cars = (data['cars'] as List).map((j) => VehicleConfig.fromJson(Map<String, dynamic>.from(j))).toList();
      if (cars.isNotEmpty) return (cars: cars, selected: data['selected'] as String);
    }
    final old = await load();
    return (cars: [old], selected: old.id);
  }
  Future<void> saveGarage(List<VehicleConfig> cars, String selected) =>
    _prefs.setString('garage149', jsonEncode({'cars': cars.map((c) => c.toJson()).toList(), 'selected': selected}));

  Future<void> openMessages(String number) async {
    final normalized = GsmProtocol.normalizePhone(number);
    if (!GsmProtocol.validPhone(normalized)) throw const FormatException('Укажи номер модуля');
    if (!await launchUrl(Uri(scheme: 'sms', path: normalized), mode: LaunchMode.externalApplication)) {
      throw StateError('Не удалось открыть сообщения');
    }
  }

  /// Нативный редактор SMS на Android/iOS. ПОЛЬЗОВАТЕЛЬ сам нажимает Отправить.
  /// Возвращаемое значение плагина не подтверждает ни доставку, ни запуск отопителя.
  Future<bool> composeSms(String deviceNumber, String text) async {
    final normalized = GsmProtocol.normalizePhone(deviceNumber);
    if (!GsmProtocol.validPhone(normalized)) {
      throw const FormatException('Сначала укажи номер SIM-карты модуля (+7…)');
    }
    try {
      final result = await sendSMS(message: text, recipients: <String>[normalized]);
      final normalizedResult = result.toLowerCase();
      // На разных платформах результат называется по-разному. Отмена НЕ
      // должна повторно открывать окно SMS и не должна считаться отправкой.
      if (normalizedResult.contains('cancel')) return false;
      return true;
    } catch (e) {
      final reason = e.toString().toLowerCase();
      if (reason.contains('cancel')) return false;
      throw StateError('Не удалось открыть редактор SMS: $e');
    }
  }

  /// Звонок — только ПЕРЕКЛЮЧЕНИЕ, а не однозначный запуск/остановка.
  Future<void> call(String deviceNumber) async {
    final normalized = GsmProtocol.normalizePhone(deviceNumber);
    if (!GsmProtocol.validPhone(normalized)) {
      throw const FormatException('Сначала укажи номер SIM-карты модуля (+7…)');
    }
    if (!await launchUrl(Uri(scheme: 'tel', path: normalized))) {
      throw StateError('Не удалось открыть телефон.');
    }
  }
}
