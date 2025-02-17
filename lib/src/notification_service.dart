import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_client.dart';
import 'package:lichess_mobile/src/model/auth/auth_session.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/correspondence/correspondence_service.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/utils/badge_service.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_service.g.dart';

@Riverpod(keepAlive: true)
NotificationService notificationService(
  NotificationServiceRef ref,
) {
  return NotificationService(
    Logger('NotificationServiceService'),
    ref: ref,
  );
}

class NotificationService {
  NotificationService(this._log, {required this.ref});

  final NotificationServiceRef ref;
  final Logger _log;

  Future<void> registerDevice() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await registerToken(token);
    }
  }

  Future<void> registerToken(String token) async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }
    _log.info('will register fcmToken: $token');
    final authClient = ref.read(authClientProvider);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }
    final result = await authClient
        .post(Uri.parse('$kLichessHost/mobile/register/firebase/$token'));
    if (result.isError) {
      _log.severe(
        'could not register device; ${result.asError!.error}',
      );
    }
  }

  Future<void> unregister() async {
    _log.info('will unregister');
    final authClient = ref.read(authClientProvider);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }
    final result =
        await authClient.post(Uri.parse('$kLichessHost/mobile/unregister'));
    if (result.isError) {
      _log.severe('could not unregister');
    }
  }

  /// Process a message received while the app is in the foreground.
  Future<void> processDataMessage(RemoteMessage message) async {
    _log.fine('processing message received in foreground: $message');
    final gameFullId = message.data['lichess.fullId'] as String?;
    final round = message.data['lichess.round'] as String?;
    // update correspondence game
    if (gameFullId != null && round != null) {
      final fullId = GameFullId(gameFullId);
      final game = PlayableGame.fromServerJson(
        jsonDecode(round) as Map<String, dynamic>,
      );
      // opponent just played, invalidate ongoing games
      if (game.sideToMove == game.youAre) {
        ref.invalidate(ongoingGamesProvider);
      }
      ref.read(correspondenceServiceProvider).updateGame(fullId, game);
    }

    // update badge
    final badge = message.data['lichess.iosBadge'] as String?;
    if (badge != null) {
      try {
        badgeService.setBadge(int.parse(badge));
      } catch (e) {
        _log.severe('Could not parse badge: $badge');
      }
    }
  }
}
