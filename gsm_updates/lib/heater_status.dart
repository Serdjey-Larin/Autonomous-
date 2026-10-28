/// Parses explicit STATUS fields from the GSM START v1.5.5 passport.
/// A successful outgoing command or a generic OK is never a status.
class HeaterStatus {
  const HeaterStatus({required this.on, this.minutesLeft, this.battery, this.duration});
  final bool on;
  final int? minutesLeft;
  final double? battery;
  final int? duration;

  static HeaterStatus? parse(String body) {
    final states = RegExp(r'(?:^|[\r\n|;])\s*Heater\s*:\s*(ON|OFF)\b',
      caseSensitive: false).allMatches(body).toList();
    if (states.length != 1) return null;
    int? minutes(String field) {
      final m = RegExp('\\b$field\\s*:\\s*(\\d+)\\s*min\\b',
        caseSensitive: false).firstMatch(body);
      final n = int.tryParse(m?.group(1) ?? '');
      return n != null && n >= 0 && n <= 120 ? n : null;
    }
    final voltage = RegExp(r'\bBattery\s*:\s*(\d+(?:[.,]\d+)?)\s*V\b',
      caseSensitive: false).firstMatch(body);
    final v = double.tryParse((voltage?.group(1) ?? '').replaceAll(',', '.'));
    return HeaterStatus(
      on: states.single.group(1)!.toUpperCase() == 'ON',
      minutesLeft: minutes('Left'), duration: minutes('Time'),
      battery: v != null && v >= 0 && v <= 40 ? v : null,
    );
  }
}
