import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as IO;

class InmeetSocketIO {
  Function()? onOpen;
  Function()? onFail;
  Function(dynamic e)? onDisconnected;
  Function()? onClose;
  IO.Socket? _socket;
  bool _shouldDispose = false;

  Function(dynamic request, dynamic accept, dynamic reject)?
      onRequest; // request, accept, reject
  Function(dynamic notification)? onNotification;

  InmeetSocketIO(
      {required String socketUrl,
      required String projectId,
      required String userName,
      required String userId,
      required String roomID,
      required String peerId,
      required bool breakoutRooms,
      required String? breakoutRoomId}) {
    if (_socket != null) {
      _socket!.dispose();
    }
    final socketUri = "$socketUrl?peerId=$peerId&roomId=$roomID&projectId=$projectId&tp=false&_uid=${getUid(userId)}=&record=false&mDeviceId=null&mDeviceType=null&displayName=$userName&breakoutRooms=$breakoutRooms&breakoutRoomId=$breakoutRoomId";
    _socket = IO.io(
        socketUri,
        <String, dynamic>{
          'transports': ['websocket', 'polling'],
        });
    _socket!.io.uri = socketUri;
        _shouldDispose = false;

    _socket?.onConnectError((data) => log("data onconnecterror $data"));
    _socket?.onConnectTimeout((data) => log("data onconnection timeout $data"));

    _socket?.on('connect', (_) {
      if (onOpen != null) {
        onOpen!();
      }
    });

    _socket?.on('notification', (dynamic notification) {
      if (onNotification != null) {
        onNotification!(notification);
      }
    });

    _socket?.on('reconnect_failed', (data) {
      log("the reconnect failed is working with data $data");
    });

    _socket?.on('reconnect', (data) {
      log("the reconnect is working with data $data");
    });

    _socket?.on('close', (_) {
      if (onClose != null) {
        onClose!();
      }
    });

    _socket?.on('error', (_) {
      if (onFail != null) {
        onFail!();
      }
    });

    _socket?.on('request', (dynamic request) {
      if (onRequest != null) {
        onRequest!(request, (dynamic response) {
          _socket?.emit('response', response);
        }, (dynamic error) {
          _socket?.emit('response', error);
        });
      }
    });

    _socket?.on('disconnect', (e) {
      if (onDisconnected != null) {
        onDisconnected!(e);
      }
      if (_shouldDispose) {
        _socket?.dispose();
        _socket = null;
      }
    });

    _socket?.connect();
  }

  close() async {
    _shouldDispose = true;
    _socket?.disconnect();
  }

  // send request emit to socket server and wait for response
  sendEventEmitterAck(method, data) async {
    log('sendRequestEmitterAck() [method: $method, data: $data]');
    final completer = Completer<dynamic>();
    final requestId = _socket?.id;
    _socket?.emitWithAck(
      'request',
      {
        'method': method,
        'data': data,
        'requestId': requestId,
      },
      ack: (response) {
        log('Ack $method: $response');
        completer.complete(response[1]);
      },
    );
    return completer.future;
  }

  /// send reuest emit to socket server
  /// use for send message to other peer
  sendEventEmitter(method, data) async {
    _socket?.emit('request', {
      'method': method,
      'data': data,
    });
  }

  String getUid(String mail) {
    final bytes = utf8.encode(mail);
    final base64Uid = base64.encode(bytes);
    return base64Uid;
  }
}
