import 'dart:async';
import 'local_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'device_service.dart';
import 'protocol.dart';
import 'sms_inbox.dart';
import 'vehicle_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LarinGsmApp());
}

const appVersion = '1.7.1';

/// Выбранное оформление: как в телефоне (по умолчанию), светлое или тёмное.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

ThemeMode themeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    primary: p.dark ? const Color(0xFF8FD0FF) : Brand.blue,
    surface: p.card,
  );
  final base = p.dark ? ThemeData.dark() : ThemeData.light();
  return ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    fontFamily: brandFont,
    scaffoldBackgroundColor: p.canvas,
    colorScheme: scheme,
    extensions: [p],
    textTheme: base.textTheme.apply(fontFamily: brandFont, bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.accent),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: brandItalic(20, weight: FontWeight.w800, color: p.text),
      contentTextStyle: brandText(15, weight: FontWeight.w500, color: p.text, height: 1.35),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    listTileTheme: ListTileThemeData(textColor: p.text, iconColor: p.accent),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: p.dark ? const Color(0xFF1F7BE0) : Brand.blue,
      foregroundColor: Colors.white,
      textStyle: brandItalic(15, weight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: p.accent,
      side: BorderSide(color: p.line, width: 2),
      textStyle: brandText(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: p.accent, textStyle: brandText(14, weight: FontWeight.w700),
    )),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.green : null),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: brandText(14, color: Colors.white, weight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.dark ? const Color(0xFF081F42) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class LarinGsmApp extends StatelessWidget {
  const LarinGsmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Larin Cold Start',
        themeMode: mode,
        theme: buildTheme(Palette.light),
        darkTheme: buildTheme(Palette.darkPalette),
        home: const ControlShell(),
      ),
    );
  }
}

class ControlShell extends StatefulWidget {
  const ControlShell({super.key});

  @override
  State<ControlShell> createState() => _ControlShellState();
}

class _ControlShellState extends State<ControlShell> with WidgetsBindingObserver {
  final DeviceService _service = DeviceService();
  VehicleConfig _config = VehicleConfig();
  List<VehicleConfig> _cars = [];
  final LocalAlerts _alerts = LocalAlerts();
  final SmsInboxBridge _sms = SmsInboxBridge();
  bool _syncing = false;
  bool _syncAgain = false;
  bool _smsGranted = false;
  String _maker = '';
  Timer? _tick;
  bool _confirming = false;
  bool _sending = false;
  bool _loading = true;
  int _page = 0;
  bool _snowOn = false;
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    _sms.listen(() { _syncInbox(); });
    _load();
  }

  @override
  void dispose() { _tick?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _resume();
    }
  }
  Future<void> _resume() async {
    try {
      await _alerts.restore();
      final id = await _alerts.selectedCar();
      if (!mounted) return;
      if (id != null && _cars.any((c) => c.id == id)) {
        setState(() { _config = _cars.firstWhere((c) => c.id == id); _page = 0; });
        await _persist();
      }
      await _syncInbox();
      await _confirmPending();
    } catch (e) { _notice('Не удалось обновить напоминания: $e', error: true); }
  }

  /// Состояние разрешения на приём SMS. Без нативного канала (тесты) — false.
  Future<void> _refreshSmsState() async {
    try {
      final st = await _sms.state();
      _smsGranted = st.granted;
      _maker = st.manufacturer;
    } catch (_) {
      _smsGranted = false;
    }
  }

  Future<void> _pushDevices() async {
    try {
      await _sms.setDevices([
        for (final c in _cars)
          if (c.deviceNumber.isNotEmpty) (number: c.deviceNumber, id: c.id, name: c.vehicleName),
      ]);
    } catch (_) {}
  }

  /// Забрать новые ответы модулей из нативного журнала и применить их.
  /// Журнал подтверждается (ack) только после сохранения состояния.
  Future<void> _syncInbox() async {
    if (_syncing) { _syncAgain = true; return; }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _refreshSmsState();
        await _pushDevices();
        final last = await _service.lastSmsSeq();
        final rows = await _sms.drain(last);
        if (rows.isEmpty) continue;
        var maxSeq = last;
        final retime = <VehicleConfig>{};
        for (final sms in rows) {
          if (sms.seq > maxSeq) maxSeq = sms.seq;
          if (sms.seq <= last) continue;
          final car = carForNumber(_cars, sms.number);
          if (car == null) continue;
          if (applyReply(car, sms).timerChanged) retime.add(car);
        }
        await _service.saveGarage(_cars, _config.id);
        await _service.setLastSmsSeq(maxSeq);
        await _sms.ack(maxSeq);
        for (final car in retime) {
          await _alerts.cancel('timer_${car.id}');
          if (car.endMs != null && car.secondsLeft(DateTime.now()) > 0) await _alerts.timer(car);
        }
      } while (_syncAgain);
    } catch (_) {
      // Нет нативного канала или разрешения — приложение работает как раньше.
    } finally {
      _syncing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _enableReplies() async {
    try {
      if (await _sms.request()) {
        await _refreshSmsState();
        _notice('Приём ответов модуля включён.');
        await _syncInbox();
        return;
      }
      if (!mounted) return;
      final autostart = const ['xiaomi', 'redmi', 'poco', 'realme', 'oppo', 'oneplus', 'vivo', 'huawei', 'honor']
          .any((m) => _maker.contains(m));
      final go = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Разрешите приём SMS'),
        scrollable: true,
        content: Text('Android ограничивает это разрешение для приложений, установленных не из магазина.\n\n'
            '1. Откроются «Сведения о приложении».\n'
            '2. Нажмите ⋮ вверху справа → «Разрешить ограниченные настройки» и подтвердите.\n'
            '3. «Разрешения» → «SMS» → «Разрешить».'
            '${autostart ? '\n4. Включите «Автозапуск» для Larin Cold Start, иначе ответы при закрытом приложении могут не приниматься.' : ''}'
            '\n\nПриложение сохраняет только SMS с номеров модулей и никуда их не передаёт.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть настройки'))]));
      if (go == true) await _sms.appSettings();
    } catch (e) {
      _notice('Не удалось запросить разрешение: $e', error: true);
    }
  }
  Future<void> _load() async {
    try {
      final garage = await _service.loadGarage();
      try { _snowOn = await _prefs.getBool('winterSnow') ?? true; } catch (_) { _snowOn = false; }
      try { themeMode.value = themeFromName(await _prefs.getString('themeMode')); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _cars = garage.cars;
        _config = _cars.firstWhere((c) => c.id == garage.selected, orElse: () => _cars.first);
        _loading = false;
      });
      await _resume();
    } catch (e) {
      if (mounted) { setState(() { _cars = [_config]; _loading = false; }); _notice('Ошибка загрузки: $e', error: true); }
    }
  }
  Future<void> _toggleSnow(bool value) async {
    setState(() => _snowOn = value);
    try { await _prefs.setBool('winterSnow', value); } catch (_) {}
  }
  Future<void> _setTheme(ThemeMode mode) async {
    themeMode.value = mode;
    try { await _prefs.setString('themeMode', mode.name); } catch (_) {}
  }
  Future<void> _openAppSettings() async {
    try { await _sms.appSettings(); } catch (e) { _notice('$e', error: true); }
  }
  Future<void> _persist() async {
    await _service.saveGarage(_cars, _config.id);
    await _pushDevices();
    if (mounted) setState(() {});
  }
  /// Подтверждение отправки START/STOP/TIME. При включённом приёме ответов
  /// команда подтверждается сама ответом OK модуля, и диалог открывается только
  /// по кнопке «Подтвердить отправку SMS» (manual).
  Future<void> _confirmPending({bool manual = false}) async {
    if (_confirming || _sending || !mounted) return;
    // Ожидание старше 2 часов — уже неактуально, не спрашиваем и не запускаем отсчёт.
    final staleBefore = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
    var dropped = false;
    for (final c in _cars) {
      if (c.pendingCommand != null && (c.pendingSince ?? 0) < staleBefore) {
        c.pendingCommand = null; c.pendingSince = null; dropped = true;
      }
    }
    if (dropped) await _persist();
    if (_smsGranted && !manual) return;
    final pending = manual
        ? _cars.where((c) => c.pendingCommand != null && c.id == _config.id).toList()
        : _cars.where((c) => c.pendingCommand != null).toList();
    if (pending.isEmpty) return;
    _confirming = true;
    try {
      final car = pending.first;
      final command = car.pendingCommand!;
      final isStart = command == GsmProtocol.start;
      final approved = await showDialog<bool>(context: context, barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('${car.vehicleName}: SMS отправлено?'),
          content: Text(isStart
            ? 'Если ты отправил START, начнём расчётный отсчёт на ${car.durationMinutes} мин. Он не подтверждает получение команды модулем.'
            : command == GsmProtocol.stop
              ? 'Если STOP отправлено, остановим расчётный таймер. Ответ отопителя смотри в переписке.'
              : 'Подтверди отправку $command. Ответ об изменении времени смотри в переписке.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Не отправлял')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да, отправил'))],
        ));
      car.pendingCommand = null; car.pendingSince = null;
      if (approved == true) {
        final timerChanged = applyUserSent(car, command, DateTime.now());
        await _persist();
        if (isStart) {
          await _alerts.cancel('timer_${car.id}');
          final allowed = await _alerts.permission();
          await _alerts.timer(car);
          if (!allowed) _notice('Таймер запущен. Для сигнала разреши уведомления в настройках приложения.');
          else if (!await _alerts.exact()) _notice('Без доступа «Будильники и напоминания» сигнал может задержаться.');
        } else if (command == GsmProtocol.stop) {
          await _alerts.cancel('timer_${car.id}');
        } else if (timerChanged) {
          await _alerts.cancel('timer_${car.id}');
          if (car.endMs != null && car.secondsLeft(DateTime.now()) > 0) await _alerts.timer(car);
        }
      }
      await _persist();
    } finally { _confirming = false; }
  }
  Future<void> _chooseCar() async {
    final id = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Мои автомобили')),
        for (final car in _cars) ListTile(leading: const Icon(Icons.directions_car),
          title: Text(car.vehicleName), subtitle: Text(car.deviceNumber.isEmpty ? 'Номер не указан' : car.deviceNumber),
          trailing: car.id == _config.id ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(ctx, car.id)),
        ListTile(leading: const Icon(Icons.add), title: const Text('Добавить автомобиль'), onTap: () => Navigator.pop(ctx, 'new')),
      ]))));
    if (id == null || !mounted) return;
    if (id == 'new') {
      final previous = _config;
      final added = VehicleConfig(id: DateTime.now().microsecondsSinceEpoch.toString(), vehicleName: 'Автомобиль ${_cars.length + 1}');
      setState(() { _cars.add(added); _config = added; });
      await _deviceDialog();
      if (added.deviceNumber.isEmpty) { _cars.remove(added); _config = previous; }
    } else { _config = _cars.firstWhere((c) => c.id == id); }
    await _persist();
  }
  Future<void> _deleteCar() async {
    if (_cars.length <= 1) { _notice('Должен остаться хотя бы один автомобиль.'); return; }
    final car = _config;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Удалить ${car.vehicleName}?'), content: const Text('Таймер и напоминание будут отменены. Команда STOP модулю не отправляется.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx,true),child: const Text('Удалить'))]));
    if (yes != true) return;
    await _alerts.cancel('timer_${car.id}'); await _alerts.cancel('reminder_${car.id}');
    _cars.remove(car); _config = _cars.first; await _persist();
  }
  Future<void> _openMessages() async {
    if (!await _ensureDevice()) return;
    try { await _service.openMessages(_config.deviceNumber); } catch(e) { _notice('$e',error:true); }
  }
  Future<void> _reminder() async {
    final car = _config;
    if (car.reminderMinutes != null) {
      final action = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text('Напоминание: ${car.vehicleName}'), content: Text('Ежедневно в ${_clockText(car.reminderMinutes!)}'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,'off'),child: const Text('Выключить')),
          FilledButton(onPressed: () => Navigator.pop(ctx,'edit'),child: const Text('Изменить'))]));
      if (action == null) return;
      if (action == 'off') { await _alerts.cancel('reminder_${car.id}'); car.reminderMinutes=null; await _persist(); return; }
    }
    if (!mounted) return;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour:(car.reminderMinutes??420) ~/60, minute:(car.reminderMinutes??420)%60));
    if (picked == null) return;
    if (!await _alerts.permission()) { _notice('Сначала разреши уведомления в настройках приложения.'); return; }
    car.reminderMinutes = picked.hour*60 + picked.minute;
    await _alerts.reminder(car); await _persist();
    _notice(await _alerts.exact() ? 'Ежедневное напоминание установлено. Оно не отправляет START.' : 'Напоминание установлено. Для точного времени включи «Будильники и напоминания».');
  }
  Future<void> _notificationSettings() async {
    final allowed = await _alerts.permission();
    if (!allowed) { await _alerts.settings(); return; }
    if (!await _alerts.exact()) { await _alerts.exactSettings(); return; }
    await _alerts.settings();
  }
  String _clockText(int minutes) => '${(minutes ~/ 60).toString().padLeft(2,'0')}:${(minutes % 60).toString().padLeft(2,'0')}';

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Brand.red : Brand.text,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _ensureDevice() async {
    if (GsmProtocol.validPhone(_config.deviceNumber)) return true;
    await _deviceDialog();
    return GsmProtocol.validPhone(_config.deviceNumber);
  }

  Future<void> _send(String command) async {
    if (_sending) return;
    if (!await _ensureDevice()) return;
    final car = _config;
    _sending = true;
    try {
      if (command == GsmProtocol.start || command == GsmProtocol.stop || command.startsWith('TIME:')) {
        car.pendingCommand=command; car.pendingSince=DateTime.now().millisecondsSinceEpoch;
        await _persist();
      }
      final opened = await _service.composeSms(car.deviceNumber, command);
      if (!opened) { car.pendingCommand=null; car.pendingSince=null; await _persist(); }
    } catch(e) {
      car.pendingCommand=null; car.pendingSince=null; await _persist();
      _notice('$e', error:true);
    } finally { _sending=false; }
  }

  Future<void> _makeCall() async {
    if (!await _ensureDevice()) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Управление звонком'),
        content: const Text(
          'Внимание: звонок ПЕРЕКЛЮЧАЕТ состояние. Если отопитель включён, он выключится, и наоборот. '
          'Без ответа STATUS приложение не знает текущее состояние.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Позвонить')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      final car = _config;
      await _service.call(car.deviceNumber);
      applyCall(car, DateTime.now());
      await _alerts.cancel('timer_${car.id}');
      await _persist();
      _notice(_smsGranted
          ? 'После звонка нажмите ⟳ рядом с состоянием — таймер покажет точное время.'
          : 'После звонка отправьте STATUS и посмотрите ответ в переписке.');
    } catch (e) {
      _notice('$e', error: true);
    }
  }

  Future<void> _deviceDialog() async {
    final name = TextEditingController(text: _config.vehicleName);
    final phone = TextEditingController(text: _config.deviceNumber);
    final owner = TextEditingController(text: _config.ownerNumber);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройка автомобиля'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Название автомобиля')),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Номер SIM-карты модуля', hintText: '+79991234567',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: owner,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Ваш номер (для регистрации мастера)', hintText: '+79991234567',
              ),
            ),
            const SizedBox(height: 10),
            const Text('Номер SIM-карты модуля и ваш личный номер — разные поля.',
              style: TextStyle(color: Color(0xFF60748D), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (!GsmProtocol.validPhone(phone.text)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Укажи номер SIM-карты модуля в формате +7…')),
              );
              return;
            }
            if (owner.text.trim().isNotEmpty && !GsmProtocol.validPhone(owner.text)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ваш номер должен быть в формате +7…')),
              );
              return;
            }
            Navigator.pop(context, true);
          }, child: const Text('Сохранить')),
        ],
      ),
    );
    if (saved == true) {
      final oldNumber = _config.deviceNumber;
      _config.vehicleName = name.text.trim().isEmpty ? 'Мой автомобиль' : name.text.trim();
      _config.deviceNumber = GsmProtocol.normalizePhone(phone.text);
      _config.ownerNumber = GsmProtocol.normalizePhone(owner.text);
      if (oldNumber != _config.deviceNumber) {
        _config.endMs = null; _config.pendingCommand = null; _config.pendingSince = null;
        await _alerts.cancel('timer_${_config.id}');
      }
      if (_config.reminderMinutes != null) await _alerts.reminder(_config);
      if (_config.endMs != null && _config.secondsLeft(DateTime.now()) > 0) await _alerts.timer(_config);
      await _persist();
      _notice('Настройки сохранены только на этом телефоне.');
    }
    name.dispose(); phone.dispose(); owner.dispose();
  }

  Future<void> _manageNumber(String action) async {
    if (action == 'list') { await _send(GsmProtocol.usersList); return; }
    final input = TextEditingController();
    final title = switch (action) {
      'add' => 'Добавить пользователя',
      'remove' => 'Удалить пользователя',
      _ => 'Передать мастер-номер',
    };
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(hintText: '+79991234567', labelText: 'Номер телефона'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (!GsmProtocol.validPhone(input.text)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Нужен международный номер +7…')),
              );
              return;
            }
            Navigator.pop(context, GsmProtocol.normalizePhone(input.text));
          }, child: const Text('Подготовить SMS')),
        ],
      ),
    );
    input.dispose();
    if (value == null) return;
    final command = switch (action) {
      'add' => GsmProtocol.addUser(value),
      'remove' => GsmProtocol.removeUser(value),
      _ => GsmProtocol.changeMaster(value),
    };
    await _send(command);
  }

  Future<void> _configureUssd() async {
    final field = TextEditingController(text: _config.ussdCode);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Код проверки баланса'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: field,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'USSD-код оператора', hintText: '*100#'),
          ),
          const SizedBox(height: 12),
          const Text('Модуль запоминает код только после отправки SMS и ответа OK.',
            style: TextStyle(color: Color(0xFF60748D), fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (!GsmProtocol.validUssd(field.text.trim())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пример правильного кода: *100#')),
              );
              return;
            }
            Navigator.pop(context, field.text.trim());
          }, child: const Text('Подготовить SMS')),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    _config.ussdCode = value;
    await _persist();
    await _send(GsmProtocol.balanceCode(value));
  }

  Future<void> _setTime(int minutes) async {
    await _send(GsmProtocol.duration(minutes));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final overlay = (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent, systemNavigationBarColor: p.nav);
    if (_loading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: Scaffold(
        body: Center(child: Image.asset('assets/larin_cold_logo.png', width: 220,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink()))));
    }
    final now = DateTime.now();
    final snow = _snowOn && isWinterSeason(now) && !MediaQuery.of(context).disableAnimations;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: SpeedStreaks()),
          if (snow) const Positioned.fill(child: Snowfall()),
          SafeArea(
            bottom: false,
            child: IndexedStack(index: _page, children: [
              _HomeView(
                config: _config,
                now: now,
                chooseCar: _chooseCar,
                openMessages: _openMessages,
                confirmPending: () => _confirmPending(manual: true),
                reminder: _reminder,
                send: _send,
                call: _makeCall,
                configure: _deviceDialog,
                setTime: _setTime,
              ),
              _SettingsView(
                config: _config,
                chooseCar: _chooseCar,
                deleteCar: _deleteCar,
                notificationSettings: _notificationSettings,
                send: _send,
                configure: _deviceDialog,
                manageNumber: _manageNumber,
                configureUssd: _configureUssd,
                smsGranted: _smsGranted,
                enableReplies: _enableReplies,
                openAppSettings: _openAppSettings,
                autostartMaker: const ['xiaomi', 'redmi', 'poco', 'realme', 'oppo', 'oneplus', 'vivo', 'huawei', 'honor']
                    .any((m) => _maker.contains(m)),
                snowOn: _snowOn,
                toggleSnow: _toggleSnow,
                setTheme: _setTheme,
              ),
            ]),
          ),
        ]),
        bottomNavigationBar: _BottomBar(page: _page, select: (value) => setState(() => _page = value)),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.page, required this.select});
  final int page;
  final ValueChanged<int> select;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(int index, String label, Widget Function(Color) icon) {
      final active = page == index;
      final color = active ? p.accent : p.muted;
      return Expanded(child: Semantics(
        button: true, selected: active, label: label,
        child: InkWell(
          onTap: () => select(index),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            icon(color),
            const SizedBox(height: 3),
            Text(label, style: active ? brandItalic(13, color: color, weight: FontWeight.w800) : brandText(13, color: color)),
          ]),
        ),
      ));
    }
    return Container(
      decoration: BoxDecoration(color: p.nav, border: Border(top: BorderSide(color: p.navBorder, width: 2))),
      child: SafeArea(top: false, child: SizedBox(height: 64, child: Row(children: [
        item(0, 'Управление', (c) => PowerGlyph(size: 22, color: c, width: 2.4)),
        item(1, 'Настройки', (c) => Icon(Icons.settings_outlined, color: c, size: 23)),
      ]))),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.config,
    required this.now,
    required this.chooseCar,
    required this.openMessages,
    required this.confirmPending,
    required this.reminder,
    required this.send,
    required this.call,
    required this.configure,
    required this.setTime,
  });
  final VehicleConfig config;
  final DateTime now;
  final Future<void> Function() chooseCar, openMessages, reminder, confirmPending;
  final Future<void> Function(String) send;
  final Future<void> Function() call;
  final Future<void> Function() configure;
  final Future<void> Function(int) setTime;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final configured = GsmProtocol.validPhone(config.deviceNumber);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Header(vehicle: config.vehicleName, chooseCar: chooseCar, call: call),
        if (!configured) ...[
          const SizedBox(height: 8),
          _InfoStrip(
            icon: Icons.info_outline,
            message: 'Сначала укажите номер SIM-карты модуля.',
            action: TextButton(onPressed: configure, child: const Text('Настроить')),
          ),
        ],
        if (configured && replyOverdue(config, now)) ...[
          const SizedBox(height: 8),
          _InfoStrip(
            icon: Icons.sms_failed_outlined,
            message: 'Модуль не отвечает. Чаще всего на SIM-карте модуля кончились деньги — '
                'команды он принимает, а ответить не может. Пополните счёт ${config.deviceNumber}. '
                'Проверка: позвоните на модуль — если после трёх сигналов прозвучат ещё шесть одинаковых, '
                'модуль работает, но не может отправить SMS.',
            action: TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: config.deviceNumber));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Номер модуля скопирован — вставьте его в приложении банка')));
                }
              },
              child: const Text('Номер'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _ControlCard(config: config, now: now, send: send, confirmPending: confirmPending),
        const SizedBox(height: 16),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _Tile(label: 'АКБ', value: batteryText(config),
            sub: config.outAt == null ? 'нажмите, чтобы узнать' : 'SMS ${_replyTime(config.outAt!)}',
            onTap: () => send(GsmProtocol.status))),
          const SizedBox(width: 10),
          Expanded(child: _Tile(label: 'БАЛАНС', value: balanceAmount(config), sub: balanceDate(config),
            warm: balanceLow(config), onTap: () => send(GsmProtocol.balance))),
          const SizedBox(width: 10),
          Expanded(child: _Tile(label: 'РАБОТА', value: '${config.durationMinutes} мин', sub: 'время прогрева')),
        ])),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final minutes in const [15, 30, 45, 60, 90, 120])
            SkewChip(
              label: config.durationMinutes == minutes ? '$minutes мин' : '$minutes',
              selected: config.durationMinutes == minutes,
              onTap: () => setTime(minutes),
            ),
        ]),
        const SizedBox(height: 6),
        Text('Выбор времени откроет SMS TIME:… для подтверждения.', style: brandText(11, color: p.muted, weight: FontWeight.w500)),
        const SizedBox(height: 12),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _SoftButton(
            icon: Icons.notifications_none_rounded,
            onTap: reminder,
            child: config.reminderMinutes == null
                ? Text('Напомнить о запуске', textAlign: TextAlign.center, style: brandText(14, color: p.text))
                : Text.rich(TextSpan(text: 'Ежедневно в ', style: brandText(14, color: p.text), children: [
                    TextSpan(text: _clock(config.reminderMinutes!), style: brandItalic(15, color: p.accent)),
                  ])),
          )),
          const SizedBox(width: 10),
          Expanded(child: _SoftButton(icon: Icons.chat_bubble_outline_rounded, onTap: openMessages,
            child: Text('Переписка', style: brandText(14, color: p.text)))),
        ])),
        const SizedBox(height: 16),
        Text('Управление работает только с номера, зарегистрированного в модуле. '
            'Команда отправляется обычной SMS.',
          textAlign: TextAlign.center, style: brandText(11, color: p.muted, weight: FontWeight.w500, height: 1.35)),
      ],
    );
  }
}

String _clock(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class _Header extends StatelessWidget {
  const _Header({required this.vehicle, required this.chooseCar, required this.call});
  final String vehicle;
  final Future<void> Function() chooseCar, call;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pillBg = p.dark ? p.card : Colors.white;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Image.asset('assets/larin_cold_logo.png', width: 140, height: 88, fit: BoxFit.contain, gaplessPlayback: true,
        semanticLabel: 'Larin Cold',
        errorBuilder: (context, error, stackTrace) => SizedBox(width: 140, height: 88,
          child: Center(child: Text('LARIN COLD', style: brandItalic(18, color: p.accent))))),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const StartBadge(),
        const SizedBox(height: 8),
        Material(
          color: pillBg,
          shape: StadiumBorder(side: BorderSide(color: p.lineSoft, width: 2)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: chooseCar,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(vehicle, maxLines: 1, overflow: TextOverflow.ellipsis, style: brandText(14, color: p.text))),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 20, color: p.text),
              ]),
            ),
          ),
        ),
      ])),
      Tooltip(
        message: 'Позвонить на модуль',
        child: Material(
          color: pillBg,
          shape: CircleBorder(side: BorderSide(color: p.lineSoft, width: 2)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: call,
            child: SizedBox(width: 46, height: 46, child: Icon(Icons.call_outlined, color: p.accent, size: 22)),
          ),
        ),
      ),
    ]);
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.config, required this.now, required this.send, required this.confirmPending});
  final VehicleConfig config;
  final DateTime now;
  final Future<void> Function(String) send;
  final Future<void> Function() confirmPending;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final remaining = config.secondsLeft(now);
    final running = config.endMs != null && remaining > 0;
    final total = config.endMs == null ? config.durationMinutes : config.cycleMinutes;
    final confirmed = confirmedOn(config, now);
    final label = config.endMs == null ? 'НЕТ ОТСЧЁТА' : remaining == 0 ? 'ВРЕМЯ ИСТЕКЛО' : 'ОСТАЛОСЬ';
    final time = config.endMs == null
        ? '—:—'
        : '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}';
    final timeShadows = p.dark
        ? const [Shadow(color: Color(0x8C4FAAFF), blurRadius: 18), Shadow(color: Color(0xFF0B57C4), offset: Offset(0, 3))]
        : const [
            Shadow(color: Colors.white, offset: Offset(-2, -2)), Shadow(color: Colors.white, offset: Offset(2, -2)),
            Shadow(color: Colors.white, offset: Offset(-2, 2)), Shadow(color: Colors.white, offset: Offset(2, 2)),
            Shadow(color: Color(0x400B57C4), offset: Offset(0, 6), blurRadius: 12),
          ];
    return StickerCard(
      shadow: true,
      ring: p.cardRing,
      radius: 26,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(children: [
          Positioned(right: -58, bottom: -40, child: Transform.rotate(angle: .21,
            child: Opacity(opacity: p.dark ? .14 : .10,
              child: LogoSnowflake(size: 190, color: p.dark ? const Color(0xFF3FD27A) : Brand.green)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(children: [
              SizedBox(width: 240, height: 240, child: CustomPaint(
                painter: RingPainter(fraction: running ? remaining / (total * 60) : 0,
                    color: confirmed ? Brand.green : (p.dark ? const Color(0xFF1F7BE0) : Brand.blue),
                    track: p.track, glow: p.dark && confirmed),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: brandItalic(13, color: p.muted, weight: FontWeight.w800, letterSpacing: 1.5)),
                  Text(time, style: brandItalic(62, color: p.numbers, height: 1.05).copyWith(
                    shadows: timeShadows, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(config.endMs == null ? 'выбрано $total мин' : 'из $total мин',
                    style: brandText(15, color: p.muted)),
                ])),
              )),
              const SizedBox(height: 10),
              _StatusPill(config: config, now: now, refresh: () => send(GsmProtocol.status)),
              if (config.pendingCommand != null) TextButton(
                onPressed: confirmPending,
                child: const Text('Подтвердить отправку SMS вручную'),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Expanded(child: SkewButton(label: 'ЗАПУСК', color: Brand.green, shadow: p.greenShadow,
                    ring: p.greenRing, icon: const PowerGlyph(), onPressed: () => send(GsmProtocol.start))),
                  const SizedBox(width: 14),
                  Expanded(child: SkewButton(label: 'СТОП', color: Brand.red, shadow: p.redShadow,
                    ring: p.redRing,
                    icon: Container(width: 15, height: 15, decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(2.5))),
                    onPressed: () => send(GsmProtocol.stop))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.config, required this.now, required this.refresh});
  final VehicleConfig config;
  final DateTime now;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = statusTone(config, now);
    final (bg, fg, ring, dot) = switch (tone) {
      StatusTone.on => (p.onBg, p.onText, p.onRing, p.dark ? const Color(0xFF3FD27A) : Brand.green),
      StatusTone.waiting => (p.waitBg, p.waitText, p.waitRing, p.waitText),
      StatusTone.warning => (p.warnBg, p.warnText, p.warnRing, p.warnDot),
      StatusTone.off || StatusTone.idle => (p.offBg, p.offText, p.offRing, p.offDot),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(19),
        border: p.dark ? null : Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: ring, spreadRadius: 1)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (tone == StatusTone.waiting)
          SnowSpinner(size: 16, color: fg)
        else
          Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(child: Text(statusLine(config, now), maxLines: 2, textAlign: TextAlign.center,
          style: brandText(14, color: fg, height: 1.2))),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Узнать состояние (SMS STATUS)',
          child: Material(
            color: p.pillButton,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: refresh,
              child: SizedBox(width: 30, height: 30, child: Icon(Icons.refresh_rounded, size: 19, color: fg)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.sub, this.onTap, this.warm = false});
  final String label, value;
  final String? sub;
  final VoidCallback? onTap;
  final bool warm;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final labelColor = warm ? p.warmLabel : p.muted;
    final valueColor = warm ? p.warmValue : p.numbers;
    return Container(
      decoration: BoxDecoration(
        color: warm ? p.warmBg : p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: warm && !p.dark ? Colors.white : p.sticker, width: 2),
        boxShadow: [BoxShadow(color: warm ? p.warmRing : p.ring, spreadRadius: 2)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: brandItalic(11, color: labelColor, weight: FontWeight.w800, letterSpacing: 1)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(value, maxLines: 1, style: brandItalic(22, color: valueColor, height: 1.15))),
              if (sub != null)
                Text(sub!, maxLines: 2, style: brandText(10.5, color: labelColor, weight: FontWeight.w500, height: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.icon, required this.child, required this.onTap});
  final IconData icon;
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.sticker, width: 2),
        boxShadow: [BoxShadow(color: p.ring, spreadRadius: 2)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: p.accent, size: 21),
              const SizedBox(width: 7),
              Flexible(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.config,
    required this.chooseCar,
    required this.deleteCar,
    required this.notificationSettings,
    required this.send,
    required this.configure,
    required this.manageNumber,
    required this.configureUssd,
    required this.smsGranted,
    required this.enableReplies,
    required this.openAppSettings,
    required this.autostartMaker,
    required this.snowOn,
    required this.toggleSnow,
    required this.setTheme,
  });
  final bool smsGranted;
  final Future<void> Function() enableReplies, openAppSettings;
  final bool autostartMaker;
  final VehicleConfig config;
  final Future<void> Function() chooseCar, deleteCar, notificationSettings;
  final Future<void> Function(String) send;
  final Future<void> Function() configure;
  final Future<void> Function(String) manageNumber;
  final Future<void> Function() configureUssd;
  final bool snowOn;
  final Future<void> Function(bool) toggleSnow;
  final Future<void> Function(ThemeMode) setTheme;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = brandText(13, color: p.text, weight: FontWeight.w500, height: 1.35);
    final small = brandText(12, color: p.muted, weight: FontWeight.w500, height: 1.35);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 26), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
        child: Text('Настройки', style: brandItalic(28, color: p.text)),
      ),
      _SectionCard(title: 'Оформление', icon: Icons.dark_mode_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (context, mode, _) => Row(children: [
              Expanded(child: _ThemeOption(label: 'Светлая', kind: ThemeMode.light, selected: mode == ThemeMode.light, onTap: setTheme)),
              const SizedBox(width: 10),
              Expanded(child: _ThemeOption(label: 'Тёмная', kind: ThemeMode.dark, selected: mode == ThemeMode.dark, onTap: setTheme)),
              const SizedBox(width: 10),
              Expanded(child: _ThemeOption(label: 'Как в телефоне', kind: ThemeMode.system, selected: mode == ThemeMode.system, onTap: setTheme)),
            ]),
          ),
          const SizedBox(height: 10),
          Text('«Как в телефоне» — тема меняется вместе с системной.', style: small),
          const SizedBox(height: 4),
          Material(color: Colors.transparent, child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: snowOn,
            onChanged: toggleSnow,
            secondary: const SizedBox(width: 24, height: 24, child: Center(child: LogoSnowflake(size: 22))),
            title: Text('Зимний снег', style: brandText(14, color: p.text)),
            subtitle: Text('С 1 декабря по 30 января. Не показывается, если анимация отключена в системе.', style: brandText(11, color: p.muted, weight: FontWeight.w500)),
          ))
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Автомобиль и SIM-карта', icon: Icons.directions_car_outlined,
        child: Column(children: [
          _DetailLine('Автомобиль', config.vehicleName),
          _DetailLine('SIM модуля', config.deviceNumber.isEmpty ? 'Не указан' : config.deviceNumber),
          _DetailLine('Ваш номер', config.ownerNumber.isEmpty ? 'Не указан' : config.ownerNumber),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: configure,
            icon: const Icon(Icons.edit_outlined), label: const Text('Изменить настройки'))),
          TextButton(onPressed: chooseCar, child: const Text('Мои автомобили')),
          TextButton(onPressed: deleteCar, child: const Text('Удалить этот автомобиль')),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Ответы модуля и уведомления', icon: Icons.mark_chat_read_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(smsGranted
              ? 'Приём включён: экран обновляется по ответам модуля, а когда приложение закрыто, '
                'ответ приходит уведомлением от Larin Cold Start.'
              : 'Выключено: приложение показывает только расчётный таймер.',
            style: body),
          if (config.lastReply != null && config.lastReplyAt != null) ...[
            const SizedBox(height: 8),
            Text('Последний ответ, ${_replyTime(config.lastReplyAt!)}:', style: small),
            Text(config.lastReply!, style: brandText(12, color: p.text)),
          ],
          if (!smsGranted) ...[
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: enableReplies, icon: const Icon(Icons.sms_outlined),
              label: const Text('Включить приём ответов')),
          ],
          const SizedBox(height: 12),
          Text('Советы', style: brandItalic(14, color: p.text, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('• Звук в переписке с модулем в SMS-приложении можно выключить — '
              'уведомления будут приходить от Larin Cold Start.', style: small),
          Text('• В «Сведениях о приложении» выключите «Удалять разрешения, если приложение не используется», '
              'иначе Android может отключить приём ответов.', style: small),
          if (autostartMaker)
            Text('• На вашем телефоне включите для Larin Cold Start «Автозапуск».', style: small),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft,
            child: TextButton(onPressed: openAppSettings, child: const Text('Открыть сведения о приложении'))),
          _ActionRow(title: 'Уведомления', description: 'Разрешения, звук и точное время',
            icon: Icons.notifications_active_outlined, onTap: notificationSettings),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Первый запуск', icon: Icons.person_add_alt_1_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('На новом модуле мастер регистрируется SMS с собственного номера '
              'в течение 10 минут после включения.', style: body),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: GsmProtocol.validPhone(config.ownerNumber)
              ? () => send(GsmProtocol.pairMaster(config.ownerNumber))
              : configure,
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Зарегистрировать мастер-номер'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Разрешённые номера', icon: Icons.groups_outlined,
        child: Column(children: [
          _ActionRow(title: 'Список пользователей', description: 'ACCLIMLIST',
            icon: Icons.list_alt, onTap: () => manageNumber('list')),
          _ActionRow(title: 'Добавить номер', description: 'До трёх дополнительных',
            icon: Icons.person_add_alt, onTap: () => manageNumber('add')),
          _ActionRow(title: 'Удалить номер', description: 'По номеру телефона',
            icon: Icons.person_remove_alt_1, onTap: () => manageNumber('remove')),
          _ActionRow(title: 'Сменить мастера', description: 'Передать права новому номеру',
            icon: Icons.admin_panel_settings_outlined, onTap: () => manageNumber('master')),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Баланс SIM-карты', icon: Icons.wallet_outlined,
        child: Column(children: [
          _DetailLine('Последний баланс', config.balanceAt == null ? 'Не запрашивался'
              : '${balanceAmount(config)} ${balanceDate(config)}'),
          _DetailLine('Сохранённый в приложении USSD',
            config.ussdCode.isEmpty ? 'Не указан' : config.ussdCode),
          _ActionRow(title: 'Установить USSD-код', description: 'Например, *100#',
            icon: Icons.edit_note, onTap: configureUssd),
          _ActionRow(title: 'Узнать код модуля', description: 'BALCODE?',
            icon: Icons.help_outline, onTap: () => send(GsmProtocol.balanceCodeQuery)),
          _ActionRow(title: 'Проверить баланс', description: 'BALANCE',
            icon: Icons.account_balance_wallet_outlined, onTap: () => send(GsmProtocol.balance)),
          _ActionRow(title: 'Удалить код из модуля', description: 'BALCODE:OFF',
            icon: Icons.delete_outline, onTap: () => send(GsmProtocol.balanceCodeOff)),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(title: 'Информация', icon: Icons.info_outline,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Larin Cold Start · приложение $appVersion', style: brandItalic(15, color: p.text, weight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('Совместимо с прошивкой LARIN COLD GSM START v1.5.6 (и v1.5.5). '
            'Интернет и сервер не требуются. Расходуется обычный пакет SMS и звонков.', style: small),
          const SizedBox(height: 9),
          Text('Приложение читает только SMS с номеров модулей (если приём ответов включён), '
            'никуда их не передаёт, не знает фактическое состояние горения и не гарантирует доставку сообщений. '
            'Запуск отопителя в закрытом помещении запрещён.', style: small),
          const SizedBox(height: 9),
          Text('Шрифт Exo 2 — SIL Open Font License.', style: brandText(11, color: p.muted, weight: FontWeight.w500)),
        ]),
      ),
    ]);
  }
}

/// Карточка выбора темы с маленьким эскизом экрана.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.label, required this.kind, required this.selected, required this.onTap});
  final String label;
  final ThemeMode kind;
  final bool selected;
  final Future<void> Function(ThemeMode) onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget half(Palette s) => Container(color: s.canvas, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle,
        border: Border.all(color: s.track, width: 4))),
      const SizedBox(height: 6),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 8, decoration: BoxDecoration(color: Brand.green, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 3),
        Container(width: 14, height: 8, decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(height: 5),
      Container(width: 34, height: 8, decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(2),
        border: Border.all(color: s.ring))),
    ])));
    final preview = switch (kind) {
      ThemeMode.light => half(Palette.light),
      ThemeMode.dark => half(Palette.darkPalette),
      ThemeMode.system => Row(children: [
          Expanded(child: ClipRect(child: OverflowBox(maxWidth: 60, alignment: Alignment.centerLeft, child: SizedBox(width: 60, child: half(Palette.light))))),
          Expanded(child: ClipRect(child: OverflowBox(maxWidth: 60, alignment: Alignment.centerRight, child: SizedBox(width: 60, child: half(Palette.darkPalette))))),
        ]),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: 'Тема: $label',
      child: Material(
        color: selected ? (p.dark ? const Color(0xFF10305E) : const Color(0xFFE6F0FF)) : p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? p.accent : p.line, width: 2)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(kind),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Column(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 60, height: 84, child: preview)),
              const SizedBox(height: 7),
              Text(label, textAlign: TextAlign.center, maxLines: 2,
                style: selected ? brandItalic(13, color: p.accent) : brandText(13, color: p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

String _replyTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StickerCard(
      radius: 22,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: p.accent, size: 23), const SizedBox(width: 9),
          Flexible(child: Text(title, style: brandItalic(17, color: p.text, weight: FontWeight.w800)))]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
      decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: p.warnRing, spreadRadius: 1)]),
      child: Row(children: [
        Icon(icon, color: p.warnText, size: 20), const SizedBox(width: 10),
        Expanded(child: Text(message, style: brandText(13, color: p.warnText, height: 1.35))),
        if (action != null) action!,
      ]),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: brandText(12, color: p.muted, weight: FontWeight.w500))),
        Flexible(child: Text(value, textAlign: TextAlign.right, style: brandText(12, color: p.text))),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.title, required this.description,
    required this.icon, required this.onTap});
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(color: Colors.transparent, child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: p.accent),
      title: Text(title, style: brandText(14, color: p.text)),
      subtitle: Text(description, style: brandText(11, color: p.muted, weight: FontWeight.w500)),
      trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
      onTap: onTap,
    ));
  }
}
