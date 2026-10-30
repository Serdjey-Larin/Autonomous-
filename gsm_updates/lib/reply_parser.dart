/// Разбор ответных SMS модуля LARIN COLD.
///
/// Формат STATUS (прошивка):
///   LARIN COLD
///   Heater: ON
///   Left: 14 min
///   Battery: 14.6 V
///   Time: 30 min
///
/// `Heater` — состояние УПРАВЛЯЮЩЕГО ВЫХОДА модуля, а не факт горения.
/// Ответ `OK` одинаков для разных команд, поэтому сам по себе состояние
/// не меняет.
library;

enum ReplyKind { status, ok, balance, error, other, invalid }

class StatusReply {
  const StatusReply({required this.on, required this.leftMinutes,
      required this.timeMinutes, this.battery, this.already = false, this.ignored = false});
  final bool on;
  /// Ответ на START при уже работающем отопителе (или STOP при выключенном):
  /// строка «Already running» / «Already stopped» над обычным STATUS.
  final bool already;
  /// Прошивка v1.5.7 не выполнила устаревшую команду: строка «Old command ignored».
  final bool ignored;
  final int leftMinutes;
  final int timeMinutes;
  final double? battery;
}

class ParsedReply {
  const ParsedReply(this.kind, {this.status, this.reason, this.balance});
  final ReplyKind kind;
  final StatusReply? status;

  /// Для `balance` — сумма в рублях, если удалось выделить число.
  final double? balance;

  /// Для `invalid` — почему ответ отклонён (для отладки и тестов).
  final String? reason;
}

final _heater = RegExp(r'Heater\s*:\s*(ON|OFF)\b', caseSensitive: false);
final _already = RegExp(r'\balready\b|уже', caseSensitive: false);
final _ignored = RegExp(r'old command ignored', caseSensitive: false);
final _left = RegExp(r'Left\s*:\s*(\d{1,3})\s*min', caseSensitive: false);
final _time = RegExp(r'Time\s*:\s*(\d{1,3})\s*min', caseSensitive: false);
// Ответ на BALANCE: модуль пересылает USSD-ответ оператора, например
// «USSD: Vaw balans: 13 rub.» Сумма — число перед «rub/руб/р/₽».
final _balanceHint = RegExp(r'^USSD\s*:|balans|баланс|balance', caseSensitive: false);
final _amount = RegExp(r'(-?\d+(?:[.,]\d{1,2})?)\s*(?:rub|rur|руб|р(?![а-яё])|₽)', caseSensitive: false);
/// Оператор не написал валюту: берём первое число после слова «баланс».
final _afterHint = RegExp(r'(?:balans|баланс|balance)[^\d-]{0,24}(-?\d+(?:[.,]\d{1,2})?)', caseSensitive: false);
final _battery = RegExp(r'Battery\s*:\s*(\d{1,2}(?:[.,]\d{1,2})?)\s*V', caseSensitive: false);

/// Отказ модуля по-русски или null, если это не отказ.
/// Тексты — ровно те, что отправляет прошивка v1.5.5/v1.5.6.
String? moduleErrorText(String body) {
  final t = body.replaceAll('\r', '').trim().toUpperCase();
  if (t == 'DENIED') return 'команда доступна только мастер-номеру';
  if (t.startsWith('ERROR TIME')) return 'время должно быть от 15 до 120 мин';
  if (t == 'ERROR PHONE') return 'неверный номер телефона';
  if (t == 'ERROR MAX 3') return 'уже записаны 3 дополнительных номера';
  if (t == 'ERROR USSD CODE') return 'неверный USSD-код';
  if (t == 'UNKNOWN COMMAND') return 'модуль не знает такой команды';
  if (t == 'NO GSM NETWORK') return 'у модуля нет сети';
  if (t == 'NOT FOUND') return 'номера нет в модуле';
  if (t == 'ALREADY EXISTS') return 'номер уже записан в модуле';
  if (t == 'USSD CODE NOT SET') return 'не задан USSD-код баланса';
  if (t == 'USSD BUSY' || t.startsWith('USSD BUSY/')) return 'модуль занят запросом баланса';
  if (t.startsWith('USSD ') && !t.startsWith('USSD:') && !t.startsWith('USSD MENU')) {
    return 'оператор не ответил на запрос баланса';
  }
  return null;
}

ParsedReply parseReply(String body) {
  final text = body.replaceAll('\r', '').trim();
  if (text.toUpperCase() == 'OK') return const ParsedReply(ReplyKind.ok);
  final error = moduleErrorText(text);
  if (error != null) return ParsedReply(ReplyKind.error, reason: error);

  final heater = _heater.firstMatch(text);
  if (heater == null) {
    if (_balanceHint.hasMatch(text)) {
      final m = _amount.firstMatch(text) ?? _afterHint.firstMatch(text);
      return ParsedReply(ReplyKind.balance,
          balance: m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.')));
    }
    return const ParsedReply(ReplyKind.other);
  }

  final left = _left.firstMatch(text);
  final time = _time.firstMatch(text);
  if (left == null || time == null) {
    return const ParsedReply(ReplyKind.invalid, reason: 'нет Left или Time');
  }
  final on = heater.group(1)!.toUpperCase() == 'ON';
  final leftMin = int.parse(left.group(1)!);
  final timeMin = int.parse(time.group(1)!);
  if (timeMin < 1 || timeMin > 240) {
    return const ParsedReply(ReplyKind.invalid, reason: 'Time вне диапазона');
  }
  if (on && leftMin > timeMin) {
    return const ParsedReply(ReplyKind.invalid, reason: 'Left больше Time');
  }
  double? battery;
  final b = _battery.firstMatch(text);
  if (b != null) {
    battery = double.parse(b.group(1)!.replaceAll(',', '.'));
    if (battery < 5 || battery > 18) {
      return const ParsedReply(ReplyKind.invalid, reason: 'напряжение вне диапазона');
    }
  }
  return ParsedReply(ReplyKind.status, status: StatusReply(
      on: on, leftMinutes: on ? leftMin : 0, timeMinutes: timeMin, battery: battery,
      already: _already.hasMatch(text), ignored: _ignored.hasMatch(text)));
}

/// Канонический вид номера: +E.164. Совпадает с SmsInbox.normalize в Kotlin.
/// Для России 8XXXXXXXXXX и 7XXXXXXXXXX → +7XXXXXXXXXX.
String canonicalNumber(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
  return d.length < 10 ? '' : '+$d';
}
