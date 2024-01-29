import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/html.dart';

class ActionCableStreamChannel {
  static StreamChannelMixin? connect(String url, Map<String, String> headers) {
    return HtmlWebSocketChannel.connect(Uri.parse(url));
  }
}
