import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/auth/qr_login_controller.dart';
import 'package:kanade/src/rust/api/types.dart';
import 'package:kanade/src/rust/frb_generated.dart';

QrCode _qr(String id) => QrCode(
  image: Uint8List.fromList([1, 2]),
  qrsig: id,
  url: 'https://example.com/$id',
);
const _user = UserInfo(uin: 'test', nickname: 'name', avatarUrl: '');

class _Api implements RustLibApi {
  final requests = <(LoginKind, String)>[];
  Future<QrCode> Function(LoginKind) create = (_) async => _qr('qr');
  Future<QrStatus> Function() poll = () async => const QrStatus.waiting();
  Future<QrCode> Function() ticket = () async => _qr('ticket');
  @override
  Future<QrCode> crateApiMusicCreateLoginQr({required LoginKind kind}) =>
      create(kind);
  @override
  Future<QrStatus> crateApiMusicPollLoginQr({
    required LoginKind kind,
    required String qrsig,
  }) {
    requests.add((kind, qrsig));
    return poll();
  }

  @override
  Future<QrCode> crateApiMusicCreateQqAppLogin() => ticket();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.requests.clear();
    api.create = (_) async => _qr('qr');
    api.poll = () async => const QrStatus.waiting();
    api.ticket = () async => _qr('ticket');
  });

  for (final kind in LoginKind.values) {
    testWidgets('$kind creates and polls the matching login type', (
      tester,
    ) async {
      LoginKind? created;
      api.create = (value) async {
        created = value;
        return _qr('qr');
      };
      final c = QrLoginController(kind, onSuccess: (_) {});
      await c.refresh();
      expect(created, kind);
      await tester.pump(const Duration(seconds: 2));
      expect(api.requests, [(kind, 'qr')]);
      expect(c.state, QrLoginState.waiting);
      c.dispose();
    });
  }

  testWidgets('scanned continues polling, success fires once', (tester) async {
    var successes = 0;
    UserInfo? received;
    final c = QrLoginController(
      LoginKind.qq,
      onSuccess: (u) {
        received = u;
        successes++;
      },
    );
    await c.refresh();
    api.poll = () async => const QrStatus.scanned();
    await tester.pump(const Duration(seconds: 2));
    expect(c.state, QrLoginState.scanned);
    api.poll = () async => const QrStatus.success(user: _user);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 6));
    expect(successes, 1);
    expect(received, _user);
    expect(api.requests.length, 2);
    c.dispose();
  });

  for (final status in [const QrStatus.expired(), const QrStatus.refused()]) {
    testWidgets('$status stops polling', (tester) async {
      final c = QrLoginController(LoginKind.qq, onSuccess: (_) {});
      await c.refresh();
      api.poll = () async => status;
      await tester.pump(const Duration(seconds: 2));
      expect(c.expired, isTrue);
      expect(
        c.state,
        status is QrStatus_Expired
            ? QrLoginState.expired
            : QrLoginState.refused,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(api.requests.length, 1);
      c.dispose();
    });
  }

  testWidgets('creation and polling failures retain the error', (tester) async {
    final error = StateError('network');
    api.create = (_) async => throw error;
    final c = QrLoginController(LoginKind.qq, onSuccess: (_) {});
    await c.refresh();
    expect(c.state, QrLoginState.loadFailed);
    expect(c.error, error);
    api.create = (_) async => _qr('qr');
    await c.refresh();
    api.poll = () async => throw error;
    await tester.pump(const Duration(seconds: 2));
    expect(c.state, QrLoginState.failed);
    expect(c.error, error);
    await tester.pump(const Duration(seconds: 4));
    expect(api.requests.length, 1);
    c.dispose();
  });

  testWidgets(
    'refresh ignores old creation and polling results without overlap',
    (tester) async {
      final first = Completer<QrCode>();
      api.create = (_) => first.future;
      var successes = 0;
      final c = QrLoginController(LoginKind.qq, onSuccess: (_) => successes++);
      final initial = c.refresh();
      api.create = (_) async => _qr('new');
      await c.refresh();
      first.complete(_qr('old'));
      await initial;
      expect(c.qr!.qrsig, 'new');
      final pending = Completer<QrStatus>();
      api.poll = () => pending.future;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      expect(api.requests.length, 1);
      await c.refresh();
      pending.complete(const QrStatus.success(user: _user));
      await tester.pump();
      expect(successes, 0);
      c.dispose();
    },
  );

  testWidgets('QQ ticket preserves image and invalidates the old poll', (
    tester,
  ) async {
    final pending = Completer<QrStatus>();
    api.poll = () => pending.future;
    var successes = 0;
    final c = QrLoginController(LoginKind.qq, onSuccess: (_) => successes++);
    await c.refresh();
    final image = c.qr!.image;
    await tester.pump(const Duration(seconds: 2));
    await c.prepareQqAppLogin();
    expect(c.qr!.image, image);
    expect(c.qr!.qrsig, 'ticket');
    pending.complete(const QrStatus.success(user: _user));
    await tester.pump();
    expect(successes, 0);
    api.poll = () async => const QrStatus.waiting();
    await tester.pump(const Duration(seconds: 2));
    expect(api.requests.last.$2, 'ticket');
    c.dispose();
  });

  testWidgets('dispose invalidates pending requests and notifications', (
    tester,
  ) async {
    final pending = Completer<QrStatus>();
    api.poll = () => pending.future;
    var successes = 0, notifications = 0;
    final c = QrLoginController(LoginKind.qq, onSuccess: (_) => successes++);
    await c.refresh();
    c.addListener(() => notifications++);
    await tester.pump(const Duration(seconds: 2));
    c.dispose();
    pending.complete(const QrStatus.success(user: _user));
    await tester.pump(const Duration(seconds: 4));
    expect(successes, 0);
    expect(notifications, 0);
    expect(api.requests.length, 1);
  });

  testWidgets('dispose also ignores pending creation and QQ tickets', (
    tester,
  ) async {
    final creation = Completer<QrCode>();
    api.create = (_) => creation.future;
    final c = QrLoginController(LoginKind.qq, onSuccess: (_) {});
    var notifications = 0;
    final refreshing = c.refresh();
    c.addListener(() => notifications++);
    c.dispose();
    creation.complete(_qr('late'));
    await refreshing;
    expect(notifications, 0);
    expect(c.qr, isNull);

    api.create = (_) async => _qr('qr');
    final d = QrLoginController(LoginKind.qq, onSuccess: (_) {});
    await d.refresh();
    final ticket = Completer<QrCode>();
    api.ticket = () => ticket.future;
    final preparing = d.prepareQqAppLogin();
    d.dispose();
    ticket.complete(_qr('late-ticket'));
    expect(await preparing, isNull);
    expect(d.qr!.qrsig, 'qr');
  });

  testWidgets(
    'refresh ignores a pending ticket and ticket failures keep the QR',
    (tester) async {
      final c = QrLoginController(LoginKind.qq, onSuccess: (_) {});
      await c.refresh();
      final ticket = Completer<QrCode>();
      api.ticket = () => ticket.future;
      final preparing = c.prepareQqAppLogin();
      api.create = (_) async => _qr('refreshed');
      await c.refresh();
      ticket.complete(_qr('old-ticket'));
      expect(await preparing, isNull);
      expect(c.qr!.qrsig, 'refreshed');
      final error = StateError('ticket failed');
      api.ticket = () async => throw error;
      await expectLater(c.prepareQqAppLogin(), throwsA(same(error)));
      expect(c.qr!.qrsig, 'refreshed');
      expect(c.state, QrLoginState.waiting);
      await tester.pump(const Duration(seconds: 2));
      expect(api.requests.last.$2, 'refreshed');
      c.dispose();
    },
  );
}
