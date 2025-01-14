import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:warp_api/data_fb_generated.dart';
import 'package:warp_api/types.dart';
import 'package:warp_api/warp_api.dart';
import 'package:badges/badges.dart' as Badges;

import 'about.dart';
import 'account.dart';
import 'animated_qr.dart';
import 'budget.dart';
import 'contact.dart';
import 'db.dart';
import 'history.dart';
import 'generated/l10n.dart';
import 'main.dart';
import 'message.dart';
import 'note.dart';
import 'store.dart';

class HomePage extends StatefulWidget {
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<HomePage> {
  StreamSubscription? _syncDispose;
  Timer? _syncTimer;
  Timer? _priceTimer;

  @override
  void initState() {
    super.initState();
    contacts.fetchContacts();
    Future.microtask(() async {
      await syncStatus.update();
      active.updateBalances();
      await priceStore.updateChart();

      await Future.delayed(Duration(seconds: 3));
      await syncStatus.sync(false);

      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(Duration(seconds: 15), (Timer t) async {
        syncStatus.sync(false);
        if (active.id != 0) {
          active.updateBalances();
        }
      });

      _priceTimer?.cancel();
      _priceTimer = Timer.periodic(Duration(minutes: 5), (Timer t) async {
        await priceStore.updateChart();
      });
    });
    _syncDispose = syncStream.listen((p) {
      if (p is String) {
        final pjs = jsonDecode(p);
        final progress = Progress.fromJson(pjs);
        syncStatus.setProgress(progress);
      }

      final syncedHeight = syncStatus.getDbSyncedHeight();
      if (syncedHeight != null) {
        final h = syncedHeight.height;
        syncStatus.setSyncHeight(h, syncedHeight.timestamp);
        eta.checkpoint(h, DateTime.now());
        active.update();
        final progress = syncStatus.progress;
        if (progress != null && isMobile()) {
          FlutterForegroundTask.updateService(
              notificationText: "$progress %");
        }
        syncStats.add(DateTime.now(), syncedHeight.height);
      }
    });
  }

  @override
  void dispose() {
    _syncDispose?.cancel();
    _syncTimer?.cancel();
    _priceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Observer(builder: (context) {
        // ignore: unused_local_variable
        final _simpleMode = settings.simpleMode;
        return HomeInnerPage(key: UniqueKey());
      });
}

class HomeInnerPage extends StatefulWidget {
  HomeInnerPage({Key? key}) : super(key: key);

  @override
  HomeInnerState createState() => HomeInnerState();
}

class HomeInnerState extends State<HomeInnerPage> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _tabIndex = 0;
  final contactKey = GlobalKey<ContactsState>();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid)
      _initForegroundTask();
    final tabController = TabController(length: settings.simpleMode ? 4 : 7, vsync: this);
    tabController.addListener(() {
      setState(() {
        _tabIndex = tabController.index;
      });
    });
    _tabController = tabController;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final simpleMode = settings.simpleMode;

    final contactTabIndex = simpleMode ? 3 : 6;
    Widget button = Container();
    if (_tabIndex == 0)
      button = FloatingActionButton(
        onPressed: _onSend,
        backgroundColor: theme.colorScheme.secondary,
        child: Icon(Icons.send),
      );
    else if (_tabIndex == contactTabIndex)
      button = FloatingActionButton(
        onPressed: _onAddContact,
        backgroundColor: theme.colorScheme.secondary,
        child: Icon(Icons.add),
      );
    else if (_tabIndex == 1)
      button = FloatingActionButton(
        onPressed: _onSend,
        backgroundColor: theme.colorScheme.secondary,
        child: Icon(Icons.send),
      );

    return Observer(builder: (context) {
      // ignore: unused_local_variable
      final _unused1 = active.dataEpoch;
      // ignore: unused_local_variable
      final _unused2 = syncStatus.paused;
      // ignore: unused_local_variable
      final _unused3 = syncStatus.syncing;

      final rescanMsg;
      if (syncStatus.paused)
        rescanMsg = s.resumeScan;
      else if (syncStatus.syncing)
        rescanMsg = s.cancelScan;
      else
        rescanMsg = s.rescan;

      final unread = active.unread;
      final messageTab = unread != 0 ?
        Tab(child: Badges.Badge(
            child: Text(s.messages),
            badgeContent: Text('$unread'))) :
        Tab(text: s.messages);

      if (active.id == 0) {
        Future.microtask(() async {
          Navigator.of(context).pushReplacementNamed('/accounts');
        });
        return SizedBox(); // Show a placeholder
      }

      final menu = PopupMenuButton<String>(
        itemBuilder: (context) {
          return [
            PopupMenuItem(child: Text(s.accounts), value: "Accounts"),
            PopupMenuItem(child: Text(s.backup), value: "Backup"),
            PopupMenuItem(child: Text(rescanMsg), value: "Rescan"),
            if (!simpleMode) PopupMenuItem(child: Text(s.pools), value: "Pools"),
            if (!simpleMode)
              PopupMenuItem(child:
              PopupMenuButton(
                  child: Text(s.advanced),
                  itemBuilder: (_) => [
                    PopupMenuItem(child: Text(s.rewindToCheckpoint), value: "Rewind"),
                    PopupMenuItem(child: Text(s.convertToWatchonly), enabled: active.canPay, value: "Cold"),
                    PopupMenuItem(child: Text(s.signOffline), enabled: active.canPay, value: "Sign"),
                    PopupMenuItem(child: Text(s.broadcast), value: "Broadcast"),
                    PopupMenuItem(child: Text(s.multipay), value: "MultiPay"),
                    PopupMenuItem(child: Text(s.keyTool), enabled: active.canPay, value: "KeyTool"),
                  ], onSelected: _onMenu)),
            // if (!simpleMode && !isMobile())
            //   PopupMenuItem(child: Text(s.ledger), value: "Ledger"),
            if (settings.isDeveloper)             
              PopupMenuItem(child: Text(s.expert), value: "Expert"),
            PopupMenuItem(child: Text(s.settings), value: "Settings"),
            PopupMenuItem(child: Text(s.help), value: "Help"),
            PopupMenuItem(child: Text(s.about), value: "About"),
          ];
        },
        onSelected: _onMenu,
      );

      showAboutOnce(this.context);

      return WithForegroundTask(child:
        Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: GestureDetector(
            onTap: () => settings.tapDeveloperMode(context),
            child: Text("${active.account.name}")),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: [
              Tab(text: s.account),
              messageTab,
              if (!simpleMode) Tab(text: s.notes),
              Tab(text: s.history),
              if (!simpleMode) Tab(text: s.budget),
              if (!simpleMode) Tab(text: s.tradingPl),
              Tab(text: s.contacts),
            ],
          ),
          actions: [menu],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            AccountPage(),
            MessageWidget(messageKey),
            if (!simpleMode) NoteWidget(),
            HistoryWidget(),
            if (!simpleMode) BudgetWidget(),
            if (!simpleMode) PnLWidget(),
            ContactsTab(key: contactKey),
          ],
        ),
        floatingActionButton: button,
      ));
    });
  }

  _onSend() {
    Navigator.of(context).pushNamed('/send');
  }

  _onMenu(String choice) {
    switch (choice) {
      case "Accounts":
        Navigator.of(context).pushNamed('/accounts');
        break;
      case "Backup":
        _backup();
        break;
      case "Rescan":
        _rescan();
        break;
      case "Pools":
        Navigator.of(context).pushNamed('/pools');
        break;
      case "Rewind":
        _rewind();
        break;
      case "Cold":
        _cold();
        break;
      case "MultiPay":
        _multiPay();
        break;
      case "Sign":
        _sign();
        break;
      case "Broadcast":
        _broadcast();
        break;
      case "KeyTool":
        _keyTool();
        break;
      case "Expert":
        Navigator.of(context).pushNamed('/dev');
        break;
      case "Ledger":
        _ledger();
        break;
      case "Settings":
        _settings();
        break;
      case "Help":
        launchUrl(Uri.parse(DOC_URL));
        break;
      case "About":
        showAbout(this.context);
        break;
    }
  }

  _backup() async {
    final didAuthenticate = await authenticate(context, S.of(context).pleaseAuthenticateToShowAccountSeed);
    if (didAuthenticate) {
      Navigator.of(context).pushNamed('/backup');
    }
  }

  _keyTool() async {
    final didAuthenticate = await authenticate(context, S.of(context).pleaseAuthenticateToShowAccountSeed);
    if (didAuthenticate) {
      Navigator.of(context).pushNamed('/keytool');
    }
  }
  
  _rewind() async {
    final s = S.of(context);
    int? height;
    final checkpoints = WarpApi.getCheckpoints(active.coin);
    final items = checkpoints.map((c) => DropdownMenuItem<int>(value: c.height,
      child: Text('${noteDateFormat.format(DateTime.fromMillisecondsSinceEpoch(c.timestamp * 1000))} - ${c.height}')
    )).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(s.rewindToCheckpoint),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(items: items, hint: Text(s.selectCheckpoint), onChanged: (v) { height = v; })]
        )),
        actions: confirmButtons(context, () => Navigator.of(context).pop(true))
      )
    ) ?? false;
    final h = height;
    if (confirmed && h != null) {
      showSnackBar(s.blockReorgDetectedRewind(h));
      WarpApi.rewindTo(h);
    }
  }

  _cold() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
            title: Text(S.of(context).coldStorage),
            content:
            Text(S.of(context).doYouWantToDeleteTheSecretKeyAndConvert),
            actions: confirmButtons(context, _convertToWatchOnly,
                okLabel: S.of(context).delete)));
  }

  _rescan() {
    if (syncStatus.paused)
      syncStatus.setPause(false);
    else if (syncStatus.syncing)
      cancelScan(context);
    else
      rescan(context);
  }

  _multiPay() {
    Navigator.of(context).pushNamed('/multipay');
  }

  _sign() async {
    final String? tx;
    if (settings.qrOffline) {
      tx = await scanMultiCode(context);
    } else {
      final res = await pickFile();
      if (res == null) return;
      final path = res.files.single.path!;
      final file = File(path);
      tx = file.readAsStringSync();
    }
    if (tx != null)
      Navigator.of(context).pushNamed('/sign', arguments: tx);
  }

  _broadcast() async {
    String? rawTx;
    if (settings.qrOffline) {
      rawTx = await scanMultiCode(context);
    } else {
      final result = await pickFile();
      if (result != null) {
        String path = result.files.single.path!;
        File f = File(path);
        rawTx = f.readAsStringSync();
      }
    }

    if (rawTx != null) {
      try {
        final res = WarpApi.broadcast(rawTx);
        showSnackBar(res);
      }
      on String catch (e) {
        showSnackBar(e);
      }
    }
  }

  _ledger() async {
    // final result = await FilePicker.platform.pickFiles();
    //
    // if (result != null) {
    //   final res = WarpApi.ledgerSign(active.coin, result.files.single.path!);
    //   final snackBar = SnackBar(content: Text(res));
    //   rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
    // }
  }

  _convertToWatchOnly() {
    WarpApi.convertToWatchOnly(active.coin, active.id);
    active.canPay = false;
    Navigator.of(context).pop();
  }

  _settings() {
    Navigator.of(context).pushNamed('/settings');
  }

  _onAddContact() async {
    final contact = await contactKey.currentState
        ?.showContactForm(context, ContactT(), false);
    if (contact != null) {
      contacts.add(contact);
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: '$APP_NAME Sync',
        channelName: '$APP_NAME Foreground Notification',
        channelDescription: 'YWallet Synchronization',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(
          resType: ResourceType.drawable,
          resPrefix: ResourcePrefix.ic,
          name: 'notification',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        isOnceEvent: true,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.setOnLockScreenVisibility(false);
  }
}

