import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/io.dart';

class ActionCableStreamChannel {
  static StreamChannelMixin? connect(String url, Map<String, String> headers) {
    return IOWebSocketChannel.connect(url, headers: headers, pingInterval: Duration(seconds: 3));
  }
}
