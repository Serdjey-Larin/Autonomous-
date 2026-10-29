import 'dart:async';
import 'dart:math' as math;
import 'local_alerts.dart';
import 'package:flutter/material.dart';

import 'device_service.dart';
import 'protocol.dart';
import 'sms_inbox.dart';
import 'vehicle_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LarinGsmApp());
}

const _blue = Color(0xFF0666BC);
const _navy = Color(0xFF10335E);
const _green = Color(0xFF16A65C);
const _canvas = Color(0xFFF2F7FC);

class LarinGsmApp extends StatelessWidget {
  const LarinGsmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LARIN COLD GSM Control',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: _blue, primary: _blue),
        appBarTheme: const AppBarTheme(
          backgroundColor: _canvas,
          foregroundColor: _navy,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const ControlShell(),
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
      await _sms.setDevices(_cars.map((c) => c.deviceNumber).where((n) => n.isNotEmpty).toList());
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
            '${autostart ? '\n4. Включите «Автозапуск» для LARIN GSM, иначе ответы при закрытом приложении могут не приниматься.' : ''}'
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
        backgroundColor: error ? const Color(0xFFAD2934) : _navy,
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
          ? 'После звонка нажмите «Состояние» — таймер покажет точное время.'
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('GSM CONTROL', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        actions: [
          IconButton(
            onPressed: _deviceDialog,
            tooltip: 'Настройки автомобиля',
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: IndexedStack(index: _page, children: [
        _HomeView(
          config: _config,
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
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.heat_pump_outlined),
            selectedIcon: Icon(Icons.heat_pump_rounded), label: 'Управление'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.config,
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
  final Future<void> Function() chooseCar, openMessages, reminder, confirmPending;
  final Future<void> Function(String) send;
  final Future<void> Function() call;
  final Future<void> Function() configure;
  final Future<void> Function(int) setTime;

  @override
  Widget build(BuildContext context) {
    final configured = GsmProtocol.validPhone(config.deviceNumber);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _BrandHeader(vehicle: config.vehicleName),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: chooseCar,
          icon: const Icon(Icons.swap_horiz),label: const Text('Выбрать автомобиль'))),
        const SizedBox(height: 14),
        if (!configured) ...[
          _InfoStrip(
            color: const Color(0xFFFFF4DD),
            icon: Icons.info_outline,
            message: 'Сначала укажи номер SIM-карты устройства.',
            action: TextButton(onPressed: configure, child: const Text('Настроить')),
          ),
          const SizedBox(height: 14),
        ],
        if (config.pendingCommand != null) ...[
          FilledButton.tonal(onPressed: confirmPending, child: const Text('Подтвердить отправку SMS')),
          const SizedBox(height: 10),
        ],
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Column(children: [
              const Text('АВТОНОМНЫЙ ОТОПИТЕЛЬ',
                style: TextStyle(color: Color(0xFF7388A0), fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _CountdownDial(config: config),
              const SizedBox(height: 12),
              Text(statusLine(config, DateTime.now()),
                style: const TextStyle(fontSize: 12, color: Color(0xFF647993)), textAlign: TextAlign.center),
              const SizedBox(height: 25),
              Row(children: [
                Expanded(child: _PowerButton(
                  label: 'ЗАПУСК', symbol: _PowerSymbol.start,
                  color: _green, onPressed: () => send(GsmProtocol.start),
                )),
                const SizedBox(width: 12),
                Expanded(child: _PowerButton(
                  label: 'ОСТАНОВКА', symbol: _PowerSymbol.stop,
                  color: const Color(0xFFC44651), onPressed: () => send(GsmProtocol.stop),
                )),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Время работы', icon: Icons.timer_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Выбранное время', style: TextStyle(color: _navy, fontWeight: FontWeight.w600)),
              Text('${config.durationMinutes} мин', style: const TextStyle(
                color: _blue, fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 11),
            Wrap(spacing: 8, runSpacing: 8, children: [15, 30, 45, 60, 90, 120].map((minutes) {
              final active = config.durationMinutes == minutes;
              return ChoiceChip(
                label: Text('$minutes мин'),
                selected: active,
                onSelected: (_) => setTime(minutes),
                selectedColor: const Color(0xFFDCF0FC),
              );
            }).toList()),
            const SizedBox(height: 7),
            const Text('Выбор времени откроет SMS TIME:… для подтверждения.',
              style: TextStyle(color: Color(0xFF75889B), fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _QuickAction(icon: Icons.fact_check_outlined, title: 'Состояние',
              subtitle: 'SMS STATUS', onTap: () => send(GsmProtocol.status))),
          const SizedBox(width: 10),
          Expanded(child: _QuickAction(icon: Icons.account_balance_wallet_outlined,
              title: 'Баланс', subtitle: balanceSubtitle(config), onTap: () => send(GsmProtocol.balance))),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: call,
          icon: const Icon(Icons.call_outlined),
          label: const Text('Управление звонком — переключение'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(51),
            foregroundColor: _navy, side: const BorderSide(color: Color(0xFFC4D8EC))),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: openMessages, icon: const Icon(Icons.forum_outlined),
          label: const Text('Открыть переписку с модулем')),
        OutlinedButton.icon(onPressed: reminder, icon: const Icon(Icons.notifications_active_outlined),
          label: Text(config.reminderMinutes == null ? 'Напомнить о запуске'
            : 'Ежедневно в ${(config.reminderMinutes! ~/ 60).toString().padLeft(2,'0')}:${(config.reminderMinutes! % 60).toString().padLeft(2,'0')}')),
        const SizedBox(height: 14),
        const _InfoStrip(
          color: Color(0xFFE7F3FF), icon: Icons.shield_outlined,
          message: 'Управление работает только с номера, зарегистрированного в модуле. '
            'Команда из приложения отправляется через обычную SMS.',
        ),
      ],
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
  });
  final bool smsGranted;
  final Future<void> Function() enableReplies;
  final VehicleConfig config;
  final Future<void> Function() chooseCar, deleteCar, notificationSettings;
  final Future<void> Function(String) send;
  final Future<void> Function() configure;
  final Future<void> Function(String) manageNumber;
  final Future<void> Function() configureUssd;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 26), children: [
      _SectionCard(title: 'Автомобиль и SIM-карта', icon: Icons.directions_car_outlined,
        child: Column(children: [
          _DetailLine('Автомобиль', config.vehicleName),
          _DetailLine('SIM модуля', config.deviceNumber.isEmpty ? 'Не указан' : config.deviceNumber),
          _DetailLine('Ваш номер', config.ownerNumber.isEmpty ? 'Не указан' : config.ownerNumber),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(onPressed: configure, icon: const Icon(Icons.edit_outlined),
            label: const Text('Изменить настройки')),
          TextButton(onPressed: chooseCar, child: const Text('Мои автомобили')),
          TextButton(onPressed: deleteCar, child: const Text('Удалить этот автомобиль')),
        ]),
      ),
      const SizedBox(height: 12),
      _SectionCard(title: 'Первый запуск', icon: Icons.person_add_alt_1_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('На новом модуле мастер регистрируется SMS с собственного номера '
              'в течение 10 минут после включения.', style: TextStyle(fontSize: 13)),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
      _SectionCard(title: 'Баланс SIM-карты', icon: Icons.wallet_outlined,
        child: Column(children: [
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
      const SizedBox(height: 12),
      _SectionCard(title: 'Уведомления', icon: Icons.notifications_outlined,
        child: TextButton(onPressed: notificationSettings, child: const Text('Разрешения, звук и точное время'))),
      const SizedBox(height: 12),
      _SectionCard(title: 'Ответы модуля', icon: Icons.mark_chat_read_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(smsGranted
              ? 'Приём включён: состояние обновляется по ответам STATUS с номера модуля.'
              : 'Выключено: приложение показывает только расчётный таймер.',
            style: const TextStyle(fontSize: 13)),
          if (config.lastReply != null && config.lastReplyAt != null) ...[
            const SizedBox(height: 8),
            Text('Последний ответ, ${_replyTime(config.lastReplyAt!)}:',
              style: const TextStyle(color: Color(0xFF6A7B90), fontSize: 12)),
            Text(config.lastReply!, style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          if (!smsGranted) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(onPressed: enableReplies, icon: const Icon(Icons.sms_outlined),
              label: const Text('Включить приём ответов')),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      const _SectionCard(title: 'Информация', icon: Icons.info_outline,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LARIN COLD GSM · приложение 1.5.3',
            style: TextStyle(fontWeight: FontWeight.w800, color: _navy)),
          SizedBox(height: 7),
          Text('Совместимо с LARIN COLD GSM START v1.5.5. '
            'Интернет и сервер не требуются. Расходуется обычный пакет SMS и звонков.',
            style: TextStyle(fontSize: 12, color: Color(0xFF657B91))),
          SizedBox(height: 9),
          Text('Приложение читает только SMS с номеров модулей (если приём ответов включён), '
            'не знает фактическое состояние горения и не гарантирует доставку сообщений. '
            'Запуск отопителя в закрытом помещении запрещён.',
            style: TextStyle(fontSize: 12, color: Color(0xFF657B91))),
        ]),
      ),
    ]);
  }
}

String _replyTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.vehicle});
  final String vehicle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(17, 10, 17, 15),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Colors.white, Color(0xFFE6F5FF)]),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD7E9F8)),
    ),
    child: Row(children: [
      Image.asset(
        'assets/larin_cold_logo.png',
        width: 124, height: 79, fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox(
          width: 124, height: 79,
          child: Center(child: Text('LARIN COLD',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _blue))),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('GSM START', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
          color: _navy, letterSpacing: -.5)),
        Text(vehicle, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _blue, fontWeight: FontWeight.w700)),
        const Text('Дистанционный запуск', style: TextStyle(color: Color(0xFF7790A9), fontSize: 11)),
      ])),
    ]),
  );
}

// Drawn with Canvas to avoid depending on a device icon font. These are
// visual symbols only: the SMS actions remain exactly the same.
enum _PowerSymbol { start, stop }

class _ActionSymbol extends StatelessWidget {
  const _ActionSymbol({required this.symbol});
  final _PowerSymbol symbol;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(30, 30),
    painter: _ActionSymbolPainter(symbol),
  );
}

class _ActionSymbolPainter extends CustomPainter {
  const _ActionSymbolPainter(this.symbol);
  final _PowerSymbol symbol;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 30, size.height / 30);
    if (symbol == _PowerSymbol.start) {
      final stroke = Paint()
        ..color = Colors.white
        ..strokeWidth = 3.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // Opening at the top of the universal power icon.
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(15, 15.5), radius: 10.5),
        -0.79, 4.72, false, stroke,
      );
      canvas.drawLine(const Offset(15, 2.8), const Offset(15, 14.5), stroke);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(6.5, 6.5, 17, 17),
          const Radius.circular(2.5),
        ),
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ActionSymbolPainter oldDelegate) =>
      oldDelegate.symbol != symbol;
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.label, required this.symbol,
    required this.color, required this.onPressed});
  final String label;
  final _PowerSymbol symbol;
  final Color color;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: color, foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: Column(children: [_ActionSymbol(symbol: symbol), const SizedBox(height: 5),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))]),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.title, required this.subtitle,
    required this.icon, required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _blue, size: 28), const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: Color(0xFF71849C), fontSize: 11)),
        ]),
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5EDF5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: _blue, size: 23), const SizedBox(width: 9),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy, fontSize: 16))]),
      const SizedBox(height: 14),
      child,
    ]),
  );
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.color, required this.icon,
    required this.message, this.action});
  final Color color;
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Icon(icon, color: _navy, size: 20), const SizedBox(width: 10),
      Expanded(child: Text(message,
        style: const TextStyle(fontSize: 12, color: _navy, height: 1.4))),
      if (action != null) action!,
    ]),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF6A7B90), fontSize: 12))),
      Flexible(child: Text(value, textAlign: TextAlign.right,
        style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 12))),
    ]),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.title, required this.description,
    required this.icon, required this.onTap});
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, child: ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: _blue),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    subtitle: Text(description, style: const TextStyle(fontSize: 11)),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  ));
}

class _CountdownDial extends StatelessWidget {
  const _CountdownDial({required this.config});
  final VehicleConfig config;
  @override
  Widget build(BuildContext context) {
    final remaining = config.secondsLeft(DateTime.now());
    final running = config.endMs != null && remaining > 0;
    final label = config.endMs == null ? 'НЕТ ОТСЧЁТА' : remaining == 0 ? 'ВРЕМЯ ИСТЕКЛО' : 'ОСТАЛОСЬ';
    final total = config.endMs == null ? config.durationMinutes : config.cycleMinutes;
    return SizedBox(width: 220, height: 220, child: CustomPaint(
      painter: _TicksPainter(total, running ? remaining/(total*60) : 0),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.power_settings_new, color: running && confirmedOn(config, DateTime.now()) ? _green : _blue, size: 36),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: _navy, fontWeight: FontWeight.w700)),
        Text(config.endMs == null ? '—:—' : '${(remaining ~/ 60).toString().padLeft(2,'0')}:${(remaining % 60).toString().padLeft(2,'0')}',
          style: const TextStyle(fontSize: 32, color: _navy, fontWeight: FontWeight.w800)),
        Text('из $total мин', style: const TextStyle(fontSize: 12,color: Color(0xFF647993))),
      ])),
    ));
  }
}
class _TicksPainter extends CustomPainter {
  _TicksPainter(this.minutes, this.fraction);
  final int minutes;
  final double fraction;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width/2,size.height/2);
    final radius = math.min(size.width,size.height)/2 - 5;
    final count = minutes;
    final elapsed = ((1-fraction)*count).floor();
    for(var i=0;i<count;i++) {
      final angle = -math.pi/2 + 2*math.pi*i/count;
      final paint = Paint()..color = i < elapsed ? const Color(0xFFDCECFB) : _green
        ..strokeWidth = (count > 60 ? 2.0 : 3.0)
        ..strokeCap = StrokeCap.round;
      final direction = Offset(math.cos(angle),math.sin(angle));
      canvas.drawLine(center+direction*(radius-(i%5==0?13:9)),center+direction*radius,paint);
    }
  }
  @override
  bool shouldRepaint(_TicksPainter old) => old.minutes != minutes || old.fraction != fraction;
}
