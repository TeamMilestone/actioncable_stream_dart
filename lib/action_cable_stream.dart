import 'dart:io';

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import 'action_cable_stream_states.dart';
import 'channel_id.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/io.dart';

typedef _OnConnectionLostFunction = void Function();

class ActionCable {
  StreamChannelMixin? _socketChannel;
  StreamSubscription? _listener;
  PublishSubject<ActionCableDataState>? stream;
  DateTime? _lastPing;
  late Timer _timer;
  Duration? timeoutAfter;
  Duration? healthCheckDuration;
  _OnConnectionLostFunction? onConnectionLost;

  ActionCable.Stream(
    String url, {
    Map<String, String> headers = const {},
    this.healthCheckDuration,
    this.timeoutAfter,
    this.onConnectionLost,
  }) {
    _socketChannel = _connectSocketChannel(url, headers);
    stream = PublishSubject<ActionCableDataState>();
    stream?.sink.add(ActionCableConnectionLoading());
    _listener = _socketChannel?.stream.listen(_onData, onError: (Object err) {
      stream?.sink.add(ActionCableError('Something went wrong while trying to connect.'));
    });

    _timer = Timer.periodic(healthCheckDuration ?? const Duration(seconds: 3), healthCheck);
  }

  StreamChannelMixin? _connectSocketChannel(String url, Map<String, String> headers) {
    if (kIsWeb) {
      return HtmlWebSocketChannel.connect(Uri.parse(url));
    }
    return IOWebSocketChannel.connect(url, headers: headers, pingInterval: Duration(seconds: 3));
  }

  void disconnect() {
    _timer.cancel();
    _socketChannel?.sink.close();
    stream?.close();
    _listener?.cancel();
  }

  // channelName being 'Chat' will be considered as 'ChatChannel',
  // 'Chat', { id: 1 } => { channel: 'ChatChannel', id: 1 }
  void subscribeToChannel(String channelName, {Map? channelParams}) {
    stream?.sink.add(ActionCableSubscribeLoading());
    final channelId = encodeChannelId(channelName, channelParams);
    _send({'identifier': channelId, 'command': 'subscribe'});
  }

  void unsubscribeToChannel(String channelName, {Map? channelParams}) {
    stream?.sink.add(ActionCableUnsubscribeLoading());
    final channelId = encodeChannelId(channelName, channelParams);
    _socketChannel?.sink.add(jsonEncode({'identifier': channelId, 'command': 'unsubscribe'}));
  }

  void performAction(String channelName, String actionName, {Map? channelParams, Map? actionParams}) {
    final channelId = encodeChannelId(channelName, channelParams);

    actionParams ??= {};
    actionParams['action'] = actionName;

    _send({'identifier': channelId, 'command': 'message', 'data': jsonEncode(actionParams)});
  }

  void _onData(dynamic payload) {
    payload = jsonDecode(payload);

    if (payload['type'] != null) {
      _handleProtocolMsg(payload);
    } else {
      _handleDataMsg(payload);
    }
  }

  void _handleProtocolMsg(Map payload) {
    switch (payload['type']) {
      case 'ping':
        _lastPing = DateTime.fromMillisecondsSinceEpoch(payload['message'] * 1000);
        break;
      case 'welcome':
        stream?.sink.add(ActionCableConnected());
        break;
      case 'disconnect':
        stream?.sink.add(ActionCableDisconnected());
        break;
      case 'confirm_subscription':
        final channelId = parseChannelId(payload['identifier']);
        stream?.sink.add(ActionCableSubscriptionConfirmed(channelId));
        break;
      case 'reject_subscription':
        final channelId = parseChannelId(payload['identifier']);
        stream?.sink.add(ActionCableSubscriptionRejected(channelId));
        break;
      default:
        stream?.sink.add(ActionCableError("Invalid Protocol Message: ${payload['type']}"));
    }
  }

  void _handleDataMsg(Map payload) {
    stream?.sink.add(ActionCableMessage(payload['message']));
  }

  void _send(Map payload) {
    _socketChannel?.sink.add(jsonEncode(payload));
  }

  void healthCheck(_) {
    if (_lastPing == null) {
      return;
    }
    if (DateTime.now().difference(_lastPing as DateTime) > (timeoutAfter ?? const Duration(seconds: 6))) {
      this.disconnect();
      if (this.onConnectionLost != null) this.onConnectionLost!();
    }
  }
}
