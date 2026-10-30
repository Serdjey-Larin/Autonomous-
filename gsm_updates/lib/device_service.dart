import 'dart:convert';
import 'package:flutter/services.dart';
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
    this.startMs,
    this.basis,
    this.outState,
    this.outAt,
    this.battery,
    this.leftMin,
    this.timeMin,
    this.lastReply,
    this.lastReplyAt,
    this.awaitCmd,
    this.awaitSince,
    this.ackCmd,
    this.ackAt,
    this.balanceRub,
    this.balanceText,
    this.balanceAt,
    this.callAt,
    this.outAlready = false,
    this.outIgnored = false,
    this.cmdAt,
    this.errorText,
    this.errorAt,
  });

  String id;
  int? endMs;
  int cycleMinutes;
  int? reminderMinutes;
  String? pendingCommand;
  int? pendingSince;

  // --- Расчётный отсчёт: endMs/cycleMinutes выше, плюс начало и источник. ---
  /// Начало текущего цикла (для пересчёта при TIME во время работы).
  int? startMs;
  /// Источник расчёта: 'user' — по «Да, отправил», 'status' — по ответу STATUS.
  String? basis;

  // --- Последний ответ STATUS: единственный источник состояния выхода. ---
  /// 'on' | 'off' | null (неизвестно).
  String? outState;
  /// Время получения этого STATUS, мс.
  int? outAt;
  double? battery;
  int? leftMin;
  int? timeMin;

  // --- Связь с модулем. ---
  String? lastReply;
  int? lastReplyAt;
  /// Команда, отправку которой подтвердил пользователь и на которую ждём ответ.
  String? awaitCmd;
  int? awaitSince;
  /// Команда, на которую модуль ответил OK (только если ожидалась одна).
  String? ackCmd;
  int? ackAt;

  // --- Баланс SIM-карты модуля из ответа на BALANCE. ---
  double? balanceRub;
  String? balanceText;
  int? balanceAt;

  /// Звонок на модуль из приложения: выход переключён, состояние неизвестно
  /// до следующего STATUS.
  int? callAt;

  /// Последний STATUS был ответом «уже запущен / уже выключен».
  bool outAlready;

  /// Последний STATUS сообщил, что модуль не выполнил устаревшую команду.
  bool outIgnored;

  /// Время (часы телефона) последней команды, меняющей состояние: START/STOP/TIME
  /// или звонок. Ответ, сформированный модулем раньше, состояние не меняет.
  int? cmdAt;

  /// Последний отказ модуля («DENIED», «ERROR …») по-русски и его время.
  String? errorText;
  int? errorAt;

  /// Номер модуля сменился: всё, что пришло от прежнего модуля, забываем.
  void forgetModuleData() {
    endMs = null; startMs = null; basis = null;
    pendingCommand = null; pendingSince = null;
    outState = null; outAt = null; battery = null; leftMin = null; timeMin = null;
    lastReply = null; lastReplyAt = null;
    awaitCmd = null; awaitSince = null; ackCmd = null; ackAt = null;
    balanceRub = null; balanceText = null; balanceAt = null;
    callAt = null; outAlready = false; outIgnored = false; cmdAt = null; errorText = null; errorAt = null;
  }
  int secondsLeft(DateTime now) => endMs == null ? 0 : ((endMs! - now.millisecondsSinceEpoch) / 1000).ceil().clamp(0, cycleMinutes * 60);
  Map<String, dynamic> toJson() => {'id': id, 'deviceNumber': deviceNumber, 'ownerNumber': ownerNumber,
    'vehicleName': vehicleName, 'durationMinutes': durationMinutes, 'ussdCode': ussdCode,
    'endMs': endMs, 'cycleMinutes': cycleMinutes, 'reminderMinutes': reminderMinutes,
    'pendingCommand': pendingCommand, 'pendingSince': pendingSince,
    'startMs': startMs, 'basis': basis, 'outState': outState, 'outAt': outAt,
    'battery': battery, 'leftMin': leftMin, 'timeMin': timeMin,
    'lastReply': lastReply, 'lastReplyAt': lastReplyAt, 'awaitCmd': awaitCmd,
    'awaitSince': awaitSince, 'ackCmd': ackCmd, 'ackAt': ackAt,
    'balanceRub': balanceRub, 'balanceText': balanceText, 'balanceAt': balanceAt, 'callAt': callAt,
    'outAlready': outAlready, 'outIgnored': outIgnored, 'cmdAt': cmdAt, 'errorText': errorText, 'errorAt': errorAt};
  factory VehicleConfig.fromJson(Map<String, dynamic> j) => VehicleConfig(
    id: j['id'] as String, deviceNumber: j['deviceNumber'] as String? ?? '',
    ownerNumber: j['ownerNumber'] as String? ?? '', vehicleName: j['vehicleName'] as String? ?? 'Автомобиль',
    durationMinutes: j['durationMinutes'] as int? ?? 30, ussdCode: j['ussdCode'] as String? ?? '',
    endMs: j['endMs'] as int?, cycleMinutes: j['cycleMinutes'] as int? ?? 30,
    reminderMinutes: j['reminderMinutes'] as int?, pendingCommand: j['pendingCommand'] as String?,
    pendingSince: j['pendingSince'] as int?,
    startMs: j['startMs'] as int?, basis: j['basis'] as String?,
    outState: j['outState'] as String?, outAt: j['outAt'] as int?,
    battery: (j['battery'] as num?)?.toDouble(), leftMin: j['leftMin'] as int?,
    timeMin: j['timeMin'] as int?, lastReply: j['lastReply'] as String?,
    lastReplyAt: j['lastReplyAt'] as int?, awaitCmd: j['awaitCmd'] as String?,
    awaitSince: j['awaitSince'] as int?, ackCmd: j['ackCmd'] as String?,
    ackAt: j['ackAt'] as int?, balanceRub: (j['balanceRub'] as num?)?.toDouble(),
    balanceText: j['balanceText'] as String?, balanceAt: j['balanceAt'] as int?, callAt: j['callAt'] as int?,
    outAlready: j['outAlready'] == true, outIgnored: j['outIgnored'] == true, cmdAt: j['cmdAt'] as int?,
    errorText: j['errorText'] as String?, errorAt: j['errorAt'] as int?);
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
  /// Номер последней обработанной записи журнала входящих SMS.
  Future<int> lastSmsSeq() async => await _prefs.getInt('smsSeq150') ?? 0;
  Future<void> setLastSmsSeq(int seq) => _prefs.setInt('smsSeq150', seq);

  Future<void> saveGarage(List<VehicleConfig> cars, String selected) =>
    _prefs.setString('garage149', jsonEncode({'cars': cars.map((c) => c.toJson()).toList(), 'selected': selected}));

  Future<void> openMessages(String number) async {
    final normalized = GsmProtocol.normalizePhone(number);
    if (!GsmProtocol.validPhone(normalized)) throw const FormatException('Укажи номер модуля');
    if (!await launchUrl(Uri(scheme: 'sms', path: normalized), mode: LaunchMode.externalApplication)) {
      throw StateError('Не удалось открыть сообщения');
    }
  }

  static const _smsChannel = MethodChannel('ru.larincold/sms');

  /// Открывает SMS-приложение с готовым текстом. ПОЛЬЗОВАТЕЛЬ сам нажимает «Отправить».
  /// Обычный startActivity, без ожидания результата: Samsung/Google «Сообщения»,
  /// запущенные «за результатом», показывали «Не удаётся начать разговор»
  /// и оставляли поверх приложения невидимое окно — экран «зависал».
  /// true — редактор открыт (это не подтверждает ни отправку, ни запуск отопителя).
  Future<bool> composeSms(String deviceNumber, String text) async {
    final normalized = GsmProtocol.normalizePhone(deviceNumber);
    if (!GsmProtocol.validPhone(normalized)) {
      throw const FormatException('Сначала укажи номер SIM-карты модуля (+7…)');
    }
    try {
      if (await _smsChannel.invokeMethod<bool>('compose', {'number': normalized, 'body': text}) == true) return true;
    } on PlatformException catch (_) {
      // ниже — запасной путь через ссылку sms:
    } on MissingPluginException catch (_) {}
    final uri = Uri.parse('sms:$normalized?body=${Uri.encodeComponent(text)}');
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    throw StateError('Не удалось открыть SMS-приложение');
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
