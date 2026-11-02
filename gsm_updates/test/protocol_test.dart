import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/protocol.dart';

void main() {
  test('номер модуля в международном формате', () {
    expect(GsmProtocol.normalizePhone('+7 (999) 123-45-67'), '+79991234567');
    expect(GsmProtocol.validPhone('+79991234567'), true);
    expect(GsmProtocol.validPhone('89991234567'), false);
    expect(GsmProtocol.validPhone(''), false);
  });

  test('точное соответствие SMS протоколу v1.5.5', () {
    expect(GsmProtocol.start, 'START');
    expect(GsmProtocol.stop, 'STOP');
    expect(GsmProtocol.status, 'STATUS');
    expect(GsmProtocol.balance, 'BALANCE');
    expect(GsmProtocol.duration(30), 'TIME:30');
    expect(GsmProtocol.addUser('+79991234567'), 'ACCLIMADD:+79991234567');
    expect(GsmProtocol.removeUser('+79991234567'), 'ACCLIMDEL:+79991234567');
    expect(GsmProtocol.pairMaster('+79991234567'), 'ACCLIM:+79991234567');
    expect(GsmProtocol.changeMaster('+79991234567'), 'ACCLIM:+79991234567');
  });

  test('ограничения таймера и USSD', () {
    expect(GsmProtocol.validDuration(15), true);
    expect(GsmProtocol.validDuration(120), true);
    expect(GsmProtocol.validDuration(14), false);
    expect(GsmProtocol.validUssd('*100#'), true);
    expect(GsmProtocol.validUssd('*105#'), true);
    expect(GsmProtocol.validUssd('100'), false);
    expect(GsmProtocol.balanceCode('*100#'), 'BALCODE:*100#');
  });
}
