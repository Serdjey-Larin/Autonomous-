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

enum ReplyKind { status, ok, balance, other, invalid }

class StatusReply {
  const StatusReply({required this.on, required this.leftMinutes,
      required this.timeMinutes, this.battery});
  final bool on;
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
final _left = RegExp(r'Left\s*:\s*(\d{1,3})\s*min', caseSensitive: false);
final _time = RegExp(r'Time\s*:\s*(\d{1,3})\s*min', caseSensitive: false);
// Ответ на BALANCE: модуль пересылает USSD-ответ оператора, например
// «USSD: Vaw balans: 13 rub.» Сумма — число перед «rub/руб/р/₽».
final _balanceHint = RegExp(r'^USSD\s*:|balans|баланс|balance', caseSensitive: false);
final _amount = RegExp(r'(-?\d+(?:[.,]\d{1,2})?)\s*(?:rub|rur|руб|р(?![а-яё])|₽)', caseSensitive: false);
/// Оператор не написал валюту: берём первое число после слова «баланс».
final _afterHint = RegExp(r'(?:balans|баланс|balance)[^\d-]{0,24}(-?\d+(?:[.,]\d{1,2})?)', caseSensitive: false);
final _battery = RegExp(r'Battery\s*:\s*(\d{1,2}(?:[.,]\d{1,2})?)\s*V', caseSensitive: false);

ParsedReply parseReply(String body) {
  final text = body.replaceAll('\r', '').trim();
  if (text.toUpperCase() == 'OK') return const ParsedReply(ReplyKind.ok);

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
      on: on, leftMinutes: on ? leftMin : 0, timeMinutes: timeMin, battery: battery));
}

/// Канонический вид номера: +E.164. Совпадает с SmsInbox.normalize в Kotlin.
/// Для России 8XXXXXXXXXX и 7XXXXXXXXXX → +7XXXXXXXXXX.
String canonicalNumber(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
  return d.length < 10 ? '' : '+$d';
}
