import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/heater_status.dart';

void main() {
  test('real STATUS format from module passport', () {
    final s = HeaterStatus.parse('LARIN COLD\nHeater: ON\nLeft: 24 min | Battery: 12.6 V\nTime: 30 min')!;
    expect(s.on, true); expect(s.minutesLeft, 24);
    expect(s.battery, 12.6); expect(s.duration, 30);
  });
  test('OFF, CRLF, case and decimal comma', () {
    final s = HeaterStatus.parse('LARIN COLD\r\nheater: off\r\nBattery: 12,4 V')!;
    expect(s.on, false); expect(s.battery, 12.4); expect(s.minutesLeft, null);
  });
  test('acknowledgements, echoes, errors and conflicting replies are not state', () {
    for (final s in ['OK', 'START', 'STOP', 'BALCODE:OFF', 'Error: Heater: ON',
      'Heater: ONLINE', 'Heater: ON\nHeater: OFF', 'Balance: 100']) {
      expect(HeaterStatus.parse(s), isNull, reason: s);
    }
  });
  test('invalid optional fields do not invent measurements', () {
    final s = HeaterStatus.parse('Heater: ON\nLeft: 999 min | Battery: 999 V')!;
    expect(s.minutesLeft, isNull); expect(s.battery, isNull);
  });
}
