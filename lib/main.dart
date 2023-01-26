import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show NativePort;
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:key_guardmanager/key_guardmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warp_api/warp_api.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:uni_links/uni_links.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'accounts.dart';
import 'animated_qr.dart';
import 'coin/coins.dart';
import 'devmode.dart';
import 'generated/l10n.dart';

import 'account_manager.dart';
import 'backup.dart';
import 'home.dart';
import 'keytool.dart';
import 'message.dart';
import 'multisend.dart';
// import 'multisign.dart';
import 'payment_uri.dart';
import 'pools.dart';
import 'qrscanner.dart';
import 'rescan.dart';
import 'reset.dart';
import 'scantaddr.dart';
import 'settings.dart';
import 'restore.dart';
import 'send.dart';
import 'store.dart';
import 'theme_editor.dart';
import 'transaction.dart';
import 'sync_chart.dart';
import 'txplan.dart';
import 'welcome.dart';

const ZECUNIT = 100000000.0;
var ZECUNIT_DECIMAL = Decimal.parse('100000000');
const mZECUNIT = 100000;
const DEFAULT_FEE = 1000;
const MAXMONEY = 21000000;
const DOC_URL = "https://hhanh00.github.io/zwallet/";
const APP_NAME = "YWallet";
const BACKUP_NAME = "${APP_NAME}.age";

const RECOVERY_FILE = "recover.bin";

const kExperimental = true;

// var accountManager = AccountManager();
var priceStore = PriceStore();
var syncStatus = SyncStatus();
var settings = Settings();
var multipayData = MultiPayStore();
var eta = ETAStore();
var contacts = ContactStore();
var syncStats = SyncStatsStore();
var active = ActiveAccount();
final messageKey = GlobalKey<MessageTableState>();

StreamSubscription? subUniLinks;

void handleUri(BuildContext context, Uri uri) {
  final scheme = uri.scheme;
  final coinDef = settings.coins.firstWhere((c) => c.def.currency == scheme);
  final coin = coinDef.coin;
  final id = WarpApi.getActiveAccountId(coin);
  active.setActiveAccount(coin, id);
  Navigator.of(context).pushNamed(
      '/send', arguments: SendPageArgs(uri: uri.toString()));
}

Future<void> initUniLinks(BuildContext context) async {
  try {
    final uri = await getInitialUri();
    if (uri != null) {
      handleUri(context, uri);
    }
  } on PlatformException {}

  subUniLinks = linkStream.listen((String? uriString) {
    if (uriString == null) return;
    final uri = Uri.parse(uriString);
    handleUri(context, uri);
  });
}

void handleQuickAction(BuildContext context, String type) {
  final t = type.split(".");
  final coin = int.parse(t[0]);
  final shortcut = t[1];
  final id = WarpApi.getActiveAccountId(coin);
  active.setActiveAccount(coin, id);
  switch (shortcut) {
    case 'receive':
      Navigator.of(context).pushNamed('/receive');
      break;
    case 'send':
      Navigator.of(context).pushNamed('/send');
      break;
  }
}

class LoadProgress extends StatefulWidget {
  LoadProgress({Key? key}): super(key: key);

  @override
  LoadProgressState createState() => LoadProgressState();
}

class LoadProgressState extends State<LoadProgress> {
  Timer? _reset;
  var _value = 0.0;
  String _message = "";
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    _reset = Timer(Duration(minutes: 3), () {
      if (!_disposed) resetApp();
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    _disposed = true;
    super.dispose();
  }
  
  void cancelResetTimer() {
    _reset?.cancel();
    _reset = null;
    _disposed = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Scaffold(body: Container(
        alignment: Alignment.center,
        child: SizedBox(height: 240, width: 200, child:
        Column(
            children: [
              Image.asset('assets/icon.png', height: 64),
              Padding(padding: EdgeInsets.all(16)),
              Text(S.of(context).loading, style: textTheme.headlineMedium),
              Padding(padding: EdgeInsets.all(16)),
              LinearProgressIndicator(value: _value),
              Padding(padding: EdgeInsets.all(8)),
              Text(_message, style: textTheme.labelMedium),
            ]
        )
        )));
  }

  void setValue(double v, String message) {
    setState(() {
      _value = v;
      _message = message;
    });
  }
}

final GlobalKey<NavigatorState> navigatorKey = new GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AwesomeNotifications().initialize(
    'resource://drawable/res_notification',
    [
      NotificationChannel(
        channelKey: APP_NAME,
        channelName: APP_NAME,
        channelDescription: 'Notification channel for ${APP_NAME}',
        defaultColor: Color(0xFFB3F0FF),
        ledColor: Colors.white,
      )
    ],
    debug: true
  );
  final home = ZWalletApp();

  runApp(FutureBuilder(
      future: settings.restore(),
      builder: (context, snapshot) {
        return snapshot.connectionState == ConnectionState.waiting
            ? MaterialApp(home: Container()) :
        Observer(builder: (context) {
          final theme = settings.themeData.copyWith(
              dataTableTheme: DataTableThemeData(
                  headingRowColor: MaterialStateColor.resolveWith(
                          (_) => settings.themeData.highlightColor)));
          return MaterialApp(
            title: APP_NAME,
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: home,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            navigatorKey: navigatorKey,
            localizationsDelegates: [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            onGenerateRoute: (RouteSettings routeSettings) {
              var routes = <String, WidgetBuilder>{
                '/welcome': (context) => WelcomePage(),
                '/account': (context) => HomePage(),
                '/add_account': (context) => AddAccountPage(),
                '/add_first_account': (context) => AddAccountPage(firstAccount: true),
                '/send': (context) =>
                    SendPage(routeSettings.arguments as SendPageArgs?),
                '/receive': (context) =>
                    PaymentURIPage(),
                '/accounts': (context) => AccountManagerPage(),
                '/settings': (context) => SettingsPage(),
                '/tx': (context) =>
                    TransactionPage(routeSettings.arguments as int),
                '/message': (context) =>
                    MessagePage(routeSettings.arguments as int),
                '/backup': (context) {
                  final accountId = routeSettings.arguments as AccountId?;
                  final accountId2 = accountId ?? active.toId();
                  return BackupPage(accountId2.coin, accountId2.id);
                },
                '/pools': (context) => PoolsPage(),
                '/multipay': (context) => MultiPayPage(),
                '/edit_theme': (context) =>
                    ThemeEditorPage(onSaved: settings.updateCustomThemeColors),
                '/reset': (context) => ResetPage(),
                '/fullBackup': (context) => FullBackupPage(),
                '/fullRestore': (context) => FullRestorePage(),
                '/scantaddr': (context) => ScanTAddrPage(),
                '/qroffline': (context) => QrOffline(routeSettings.arguments as String),
                '/showRawTx': (context) => ShowRawTx(routeSettings.arguments as String),
                '/keytool': (context) => KeyToolPage(),
                '/dev': (context) => DevPage(),
                '/txplan': (context) => TxPlanPage.fromPlan(routeSettings.arguments as String, false),
                '/sign': (context) => TxPlanPage.fromPlan(routeSettings.arguments as String, true),
                '/syncstats': (context) => SyncChartPage(),
                '/scanner': (context) {
                  final args = routeSettings.arguments as Map<String, dynamic>;
                  return QRScanner(args['onScan'], completed: args['completed']);
                },
              };
              return MaterialPageRoute(builder: routes[routeSettings.name]!);
            },
          );
        });
      }));
}

class ZWalletApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ZWalletAppState();
}

class ZWalletAppState extends State<ZWalletApp> {
  bool initialized = false;
  final progressKey = GlobalKey<LoadProgressState>();

  @override
  void initState() {
    super.initState();
    if (isMobile()) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final isAllowed = await AwesomeNotifications().isNotificationAllowed();
        if (!isAllowed) {
          AwesomeNotifications().requestPermissionToSendNotifications(
            permissions: [
              NotificationPermission.Sound,
              NotificationPermission.Alert,
              NotificationPermission.FullScreenIntent,
              NotificationPermission.Badge,
              NotificationPermission.Vibration,
              NotificationPermission.Light,
            ],
          );
        }
        // Only after at least the action method is set, the notification events are delivered
        AwesomeNotifications().setListeners(
            onActionReceivedMethod:         NotificationController.onActionReceivedMethod,
            onNotificationCreatedMethod:    NotificationController.onNotificationCreatedMethod,
            onNotificationDisplayedMethod:  NotificationController.onNotificationDisplayedMethod,
            onDismissActionReceivedMethod:  NotificationController.onDismissActionReceivedMethod
        );
      });
    }
  }

  Future<bool> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recover = prefs.getBool('recover') ?? false;
      final exportDb = prefs.getBool('export_db') ?? false;
      prefs.setBool('recover', false);

      if (!initialized || recover || exportDb) {
        initialized = true;
        final secureStorage = new FlutterSecureStorage();
        var key = await secureStorage.read(key: APP_NAME + ":db_key");
        if (key == null) {
          final r = Random.secure();
          final randomKey = List<int>.generate(32, (index) => r.nextInt(256)).toList();
          key = base64Url.encode(randomKey);
          await secureStorage.write(key: APP_NAME + ":db_key", value: key);
        }

        final dbPath = await getDbPath();
        for (var coin in coins) {
          coin.init(dbPath);
        }

        if (exportDb) {
          await ycash.export(context, dbPath);
          await zcash.export(context, dbPath);
          prefs.setBool('export_db', false);
        }
        if (recover) {
          for (var coin in coins) {
            await coin.importFromTemp();
          }
        }
        print("db path $dbPath $key");
        WarpApi.mempoolRun(unconfirmedBalancePort.sendPort.nativePort);
        for (var coin in coins) {
          _setProgress(0.1 * (coin.coin+1), 'Initializing ${coin.ticker}');
          WarpApi.initWallet(coin.coin, coin.dbFullPath, key);
          WarpApi.migrateWallet(coin.coin);
        }

        _setProgress(0.6, 'Migrate Data');
        for (var s in settings.servers) {
          final server = s.getLWDUrl();
          if (server != null && server.isNotEmpty) {
            WarpApi.updateLWD(s.coin, server);
            WarpApi.migrateData(s.coin);
          }
        }

        _setProgress(0.7, 'Restoring Active Account');
        if (recover) {
          final aid = getAvailableId(coins[0].coin);
          if (aid != null)
            active.setActiveAccount(aid.coin, aid.id);
        }
        else await active.restore();

        if (isMobile()) {
          _setProgress(0.9, 'Setting Dashboard Shortcuts');
          await initUniLinks(this.context);
          final quickActions = QuickActions();
          quickActions.initialize((type) {
            handleQuickAction(this.context, type);
          });
          Future.microtask(() {
            final s = S.of(this.context);
            List<ShortcutItem> shortcuts = [];
            for (var c in settings.coins) {
              final coin = c.coin;
              final ticker = c.def.ticker;
              shortcuts.add(ShortcutItem(type: '$coin.receive',
                  localizedTitle: s.receive(ticker),
                  icon: 'receive'));
              shortcuts.add(ShortcutItem(type: '$coin.send',
                  localizedTitle: s.sendCointicker(ticker),
                  icon: 'send'));
            }
            quickActions.setShortcutItems(shortcuts);
          });
        }
      }

      _setProgress(1.0, 'Ready');
      progressKey.currentState?.cancelResetTimer();
      if (settings.protectOpen) {
        while (!await authenticate(this.context, 'Protect Launch')) {}
      }

      return true;
    } catch (e) {
      print("Init error: $e");
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _init(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return LoadProgress(key: progressKey);
          return HomePage();
        });
  }

  void _setProgress(double v, String message) {
    print(message);
    progressKey.currentState?.setValue(v, message);
  }
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
GlobalKey<ScaffoldMessengerState>();

List<ElevatedButton> confirmButtons(BuildContext context,
    VoidCallback? onPressed,
    {String? okLabel, Icon? okIcon, cancelValue}) {
  final s = S.of(context);
  final navigator = Navigator.of(context);
  return <ElevatedButton>[
    ElevatedButton.icon(
        icon: Icon(Icons.cancel),
        label: Text(s.cancel),
        onPressed: () {
          cancelValue != null ? navigator.pop(cancelValue) : navigator.pop();
        },
        style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondary)),
    ElevatedButton.icon(
      icon: okIcon ?? Icon(Icons.done),
      label: Text(okLabel ?? s.ok),
      onPressed: onPressed,
    )
  ];
}

List<TimeSeriesPoint<V>> sampleDaily<T, Y, V>(List<T> timeseries,
    int start,
    int end,
    int Function(T) getDay,
    Y Function(T) getY,
    V Function(V, Y) accFn,
    V initial) {
  assert(start % DAY_MS == 0);
  final s = start ~/ DAY_MS;
  final e = end ~/ DAY_MS;

  var acc = initial;
  var j = 0;
  while (j < timeseries.length && getDay(timeseries[j]) < s) {
    acc = accFn(acc, getY(timeseries[j]));
    j += 1;
  }

  List<TimeSeriesPoint<V>> ts = [];

  for (var i = s; i <= e; i++) {
    while (j < timeseries.length && getDay(timeseries[j]) == i) {
      acc = accFn(acc, getY(timeseries[j]));
      j += 1;
    }
    ts.add(TimeSeriesPoint(i, acc));
  }
  return ts;
}

void showQR(BuildContext context, String text, String title) {
  final s = S.of(context);
  showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return AlertDialog(
            content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(child: Column(children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final size = getScreenSize(context) * 0.5;
                    return QrImage(data: text, backgroundColor: Colors.white, size: size);
                  }),
                  Padding(padding: EdgeInsets.all(8)),
                  Text(title, style: Theme
                      .of(context)
                      .textTheme
                      .subtitle1),
                  Padding(padding: EdgeInsets.all(4)),
                  ElevatedButton.icon(onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    showSnackBar(s.textCopiedToClipboard(title));
                    Navigator.of(context).pop();
                  }, icon: Icon(Icons.copy), label: Text(s.copy))
                ])))
        ); });
}

Future<bool> showMessageBox(BuildContext context, String title, String content,
    String label) async {
  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: confirmButtons(context, () {
              Navigator.of(context).pop(true);
            }, okLabel: label, cancelValue: false)),
  );
  return confirm ?? false;
}

double getScreenSize(BuildContext context) {
  final size = MediaQuery
      .of(context)
      .size;
  return min(size.height, size.width);
}

Color amountColor(BuildContext context, num a) {
  final theme = Theme.of(context);
  if (a < 0) return Colors.red;
  if (a > 0) return Colors.green;
  return theme.textTheme.bodyText1!.color!;
}

TextStyle weightFromAmount(TextStyle style, num v) {
  final value = v.abs();
  final coin = activeCoin();
  final style2 = style.copyWith(fontFeatures: [FontFeature.tabularFigures()]);
  if (value >= coin.weights[2])
    return style2.copyWith(fontWeight: FontWeight.w800);
  else if (value >= coin.weights[1])
    return style2.copyWith(fontWeight: FontWeight.w600);
  else if (value >= coin.weights[0])
    return style2.copyWith(fontWeight: FontWeight.w400);
  return style2.copyWith(fontWeight: FontWeight.w200);
}

CurrencyTextInputFormatter makeInputFormatter(bool? mZEC) =>
    CurrencyTextInputFormatter(symbol: '', decimalDigits: precision(mZEC));

double parseNumber(String? s) {
  if (s == null || s.isEmpty) return 0;
  return NumberFormat.currency().parse(s).toDouble();
}

int stringToAmount(String? s) {
  final a = parseNumber(s);
  return (Decimal.parse(a.toString()) * ZECUNIT_DECIMAL).toBigInt().toInt();
}

bool checkNumber(String s) {
  try {
    NumberFormat.currency().parse(s);
  }
  on FormatException {
    return false;
  }
  return true;
}

const MAX_PRECISION = 8;
int precision(bool? mZEC) => (mZEC == null || mZEC) ? 3 : MAX_PRECISION;

Future<String?> scanCode(BuildContext context) async {
  final s = S.of(context);
  if (!isMobile()) {
    final codeController = TextEditingController();
    final code = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
            title: Text(s.inputBarcodeValue),
            content: TextFormField(
              decoration: InputDecoration(
                  labelText: s.barcode),
              controller: codeController,
            ),
            actions: confirmButtons(
                context, () => Navigator.of(context).pop(codeController.text),
                cancelValue: null)));
    return code;
  }
  else {
    final f = Completer();
    Navigator.of(context).pushNamed('/scanner', arguments: {
      'onScan': (Code code) {
        f.complete(code.text);
      },
      'completed': () => f.isCompleted,
    });
    return await f.future;
  }
}

String centerTrim(String v) =>
  v.length >= 16 ? v.substring(0, 8) + "..." +
      v.substring(v.length - 16) : v;

String trailing(String v, int n) {
  final len = min(n, v.length);
  return v.substring(v.length - len);
}

void showSnackBar(String msg, { bool autoClose = false, bool quick = false }) {
  final duration = quick ? Duration(seconds: 1) : Duration(seconds: 4);
  final snackBar = SnackBar(content: SelectableText(msg),
    duration: autoClose ? duration : Duration(minutes: 1),
    action: SnackBarAction(label: S.current.close, onPressed: () {
      rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
  }));
  rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
}

void showBalanceNotification(int prevBalances, int curBalances) {
  final s = S.current;
  if (syncStatus.isRescan) return;
  if (Platform.isAndroid &&
      prevBalances != curBalances) {
    final amount = (prevBalances - curBalances).abs();
    final amountStr = amountToString(amount, MAX_PRECISION);
    final ticker = active.coinDef.ticker;
    final NotificationContent content;
    if (curBalances > prevBalances) {
      content = NotificationContent(
        id: 1,
        channelKey: APP_NAME,
        title: s.incomingFunds,
        body: s.received(amountStr, ticker),
        actionType: ActionType.Default,
      );
    }
    else {
      content = NotificationContent(
        id: 1,
        channelKey: APP_NAME,
        title: s.paymentMade,
        body: s.spent(amountStr, ticker),
        actionType: ActionType.Default,
      );
    }
    AwesomeNotifications().createNotification(
        content: content
    );
  }
}

enum DeviceWidth {
  xs,
  sm,
  md,
  lg,
  xl
}

DeviceWidth getWidth(BuildContext context) {
  final width = MediaQuery
      .of(context)
      .size
      .width;
  if (width < 600) return DeviceWidth.xs;
  if (width < 960) return DeviceWidth.sm;
  if (width < 1280) return DeviceWidth.md;
  if (width < 1920) return DeviceWidth.lg;
  return DeviceWidth.xl;
}

final DateFormat todayDateFormat = DateFormat("HH:mm");
final DateFormat monthDateFormat = DateFormat("MMMd");
final DateFormat longAgoDateFormat = DateFormat("yy-MM-dd");

String humanizeDateTime(DateTime datetime) {
  final messageDate = datetime.toLocal();
  final now = DateTime.now();
  final justNow = now.subtract(Duration(minutes: 1));
  final midnight = DateTime(now.year, now.month, now.day);
  final year = DateTime(now.year, 1, 1);

  String dateString;
  if (justNow.isBefore(messageDate))
    dateString = S.current.now;
  else if (midnight.isBefore(messageDate))
    dateString = todayDateFormat.format(messageDate);
  else if (year.isBefore(messageDate))
    dateString = monthDateFormat.format(messageDate);
  else
    dateString = longAgoDateFormat.format(messageDate);
  return dateString;
}

String decimalFormat(double x, int decimalDigits, { String symbol = '' }) =>
    NumberFormat.currency(decimalDigits: decimalDigits, symbol: symbol).format(
        x).trimRight();

String amountToString(int amount, int decimalDigits) => decimalFormat(amount / ZECUNIT, decimalDigits);

DecodedPaymentURI decodeAddress(BuildContext context, String? v) {
  final s = S.of(context);
  try {
    if (v == null || v.isEmpty) throw s.addressIsEmpty;
    if (WarpApi.validAddress(active.coin, v))
      return DecodedPaymentURI(v, 0, "");
    // not a valid address, try as a payment URI
    final json = WarpApi.parsePaymentURI(v);
    final payment = DecodedPaymentURI.fromJson(jsonDecode(json));
    return payment;
  }
  on String catch (e) {
    throw e;
  }
}

Future<bool> authenticate(BuildContext context, String reason) async {
  if (!isMobile()) return true;
  final localAuth = LocalAuthentication();
  try {
    final bool didAuthenticate;
    if (Platform.isAndroid && !await localAuth.canCheckBiometrics) {
      didAuthenticate = await KeyGuardmanager.authStatus == "true";
    }
    else  {
      didAuthenticate = await localAuth.authenticate(
          localizedReason: reason, options: AuthenticationOptions());
    }
    if (didAuthenticate) {
      return true;
    }
  } on PlatformException catch (e) {
    await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) =>
            AlertDialog(
                title: Text(S.of(context).noAuthenticationMethod),
                content: Text(e.message ?? "")));
  }
  return false;
}

Future<void> shieldTAddr(BuildContext context) async {
  try {
    final txPlan = WarpApi.shieldTAddr(
        active.coin, active.id, active.tbalance, settings.anchorOffset);
    Navigator.of(context).pushNamed('/txplan', arguments: txPlan);
  }
  on String catch (msg) {
    showSnackBar(msg);
  }
}

Future<void> shareCsv(List<List> data, String filename, String title) async {
  final csvConverter = ListToCsvConverter();
  final csv = csvConverter.convert(data);
  await saveFile(csv, filename, title);
}

Future<void> saveFile(String data, String filename, String title) async {
  if (isMobile()) {
    final context = navigatorKey.currentContext!;
    Size size = MediaQuery.of(context).size;
    final tempDir = settings.tempDir;
    final path = p.join(tempDir, filename);
    final xfile = XFile(path);
    final file = File(path);
    await file.writeAsString(data);
    await Share.shareXFiles([xfile], subject: title, sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2));
  }
  else {
    final fn = await FilePicker.platform.saveFile();
    if (fn != null) {
      final file = File(fn);
      await file.writeAsString(data);
    }
  }
}

Future<void> exportFile(BuildContext context, String path, String title) async {
  final confirmed = await showMessageBox(context, title, "Exporting ${path}", S.of(context).ok);
  if (!confirmed) return;
  if (isMobile()) {
    final context = navigatorKey.currentContext!;
    Size size = MediaQuery.of(context).size;
    final xfile = XFile(path);
    await Share.shareXFiles([xfile], subject: title, sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2));
  }
  else {
    final fn = await FilePicker.platform.saveFile();
    if (fn != null) {
      final file = File(path);
      await file.copy(fn);
    }
  }
}

Future<File> getRecoveryFile() async {
  String fn = p.join(settings.tempDir, RECOVERY_FILE);
  final f = File(fn);
  return f;
}

Future<bool> showConfirmDialog(BuildContext context, String title, String body) async {
  final s = S.of(context);
  final confirmation = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: confirmButtons(context, () {
          Navigator.of(context).pop(true);
        }, okLabel: s.ok, cancelValue: false)),
  ) ?? false;
  return confirmation;
}

Future<void> rescan(BuildContext context) async {
  final height = await rescanDialog(context);
  if (height != null) {
    active.clear();
    syncStatus.rescan(height);
  }
}

void cancelScan(BuildContext context) {
  syncStatus.setPause(true);
  WarpApi.cancelSync();
}

Future<String> getDataPath() async {
  String? home;
  if (Platform.isAndroid) home = (await getApplicationDocumentsDirectory()).parent.path;
  if (Platform.isWindows) home = Platform.environment['LOCALAPPDATA'];
  if (Platform.isLinux) home = Platform.environment['XDG_DATA_HOME'];
  if (Platform.isMacOS) home = Platform.environment['HOME'];
  final h = home ?? "";
  return h;
}

Future<String> getTempPath() async {
  if (isMobile()) {
    final d = await getTemporaryDirectory();
    return d.path;
  }
  final dataPath = await getDataPath();
  final tempPath = p.join(dataPath, "tmp");
  Directory(tempPath).createSync(recursive: true);
  return tempPath;
}

Future<String> getDbPath() async {
  if (Platform.isIOS) return (await getApplicationDocumentsDirectory()).path;
  final h = await getDataPath();
  return "$h/databases";
}

bool isMobile() => Platform.isAndroid || Platform.isIOS;

class NotificationController {

  /// Use this method to detect when a new notification or a schedule is created
  @pragma("vm:entry-point")
  static Future <void> onNotificationCreatedMethod(ReceivedNotification receivedNotification) async {
  }

  /// Use this method to detect every time that a new notification is displayed
  @pragma("vm:entry-point")
  static Future <void> onNotificationDisplayedMethod(ReceivedNotification receivedNotification) async {
    FlutterRingtonePlayer.playNotification();
  }

  /// Use this method to detect if the user dismissed a notification
  @pragma("vm:entry-point")
  static Future <void> onDismissActionReceivedMethod(ReceivedAction receivedAction) async {
  }

  /// Use this method to detect when the user taps on a notification or action button
  @pragma("vm:entry-point")
  static Future <void> onActionReceivedMethod(ReceivedAction receivedAction) async {
  }
}

void resetApp() {
  WarpApi.truncateData();
}
