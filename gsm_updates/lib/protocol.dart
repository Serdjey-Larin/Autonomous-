/// Точные SMS-команды прошивки LARIN COLD GSM START v1.5.5.
/// Никаких новых команд для модуля приложение не вводит.
class GsmProtocol {
  static final RegExp _phone = RegExp(r'^\+[0-9]{10,15}$');
  static final RegExp _ussd = RegExp(r'^\*[0-9*#]{1,14}#$');

  /// Разрешён только международный формат, который принимает прошивка:
  /// плюс, затем от 10 до 15 цифр.
  static String normalizePhone(String text) =>
      text.replaceAll(RegExp(r'[\s()\-]'), '');

  static bool validPhone(String text) => _phone.hasMatch(normalizePhone(text));
  static bool validUssd(String text) => text.length <= 16 && _ussd.hasMatch(text);
  static bool validDuration(int minutes) => minutes >= 15 && minutes <= 120;

  static const start = 'START';
  static const stop = 'STOP';
  static const status = 'STATUS';
  static const balance = 'BALANCE';
  static const balanceCodeQuery = 'BALCODE?';
  static const balanceCodeOff = 'BALCODE:OFF';
  static const usersList = 'ACCLIMLIST';

  static String duration(int minutes) {
    if (!validDuration(minutes)) throw const FormatException('15–120 минут');
    return 'TIME:$minutes';
  }

  static String balanceCode(String code) {
    if (!validUssd(code)) throw const FormatException('USSD: *числа#');
    return 'BALCODE:$code';
  }

  static String addUser(String phone) => 'ACCLIMADD:${_verified(phone)}';
  static String removeUser(String phone) => 'ACCLIMDEL:${_verified(phone)}';
  /// Регистрация и смена мастер-номера: ACCLIM:+7XXXXXXXXXX (двоеточие обязательно).
  static String changeMaster(String phone) => 'ACCLIM:${_verified(phone)}';
  static String pairMaster(String phone) => changeMaster(phone);

  static String _verified(String phone) {
    final value = normalizePhone(phone);
    if (!validPhone(value)) throw const FormatException('Номер в формате +7…');
    return value;
  }
}
