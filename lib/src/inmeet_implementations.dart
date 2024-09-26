import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:inapi_core_sdk/inapi_core_sdk.dart';
import 'package:inapi_core_sdk/src/inmeet_helpers.dart';
import 'package:inapi_core_sdk/src/models/inmeet_br_model.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
import 'package:flutter_webrtc/src/native/factory_impl.dart' as nav;
import 'dart:math' as math;
import 'package:collection/src/iterable_extensions.dart';
import 'package:http/http.dart' as http;

class InMeetClient {
  InmeetSocketIO? socketIo;
  Device? mediasoupDevice;
  bool produce = false;
  Transport? sendTransport;
  Transport? recvTransport;
  late String socketUrl;
  late String projectId;
  late String userName;
  late String userId;
  late String hostId;
  bool isBreakoutRooms = false;
  String? breakoutRoomId;
  Producer? mic;
  Producer? webcam;
  Producer? localScreenShareProducer;
  MediaStream? localVideoStream;
  MediaStream? localAudioStream;
  MediaStream? localScreenShareStream;
  List<InMeetPeerModel> peers = [];
  List<InMeetPeerModel> hosts = [];
  List<InMeetPeerModel> screenSharePeers = [];
  Map<String, String> screenShareConsumerIds = {};
  InMeetClientEvents? _listeners;
  Set<ParticipantRoles> clientRole = {ParticipantRoles.participant};
  String peerId = '';
  String roomId = "";
  List<MediaDeviceInfo>? devices;
  List<String> videoInputs = [];
  List<String> audioInputs = [];
  List<String> audioOutputs = [];
  String meetingId = '';
  Set<InMeetBrModel> breakoutRooms = {};
  String? selectedVideoInputId;
  String? selectedAudioInputDeviceId;

  InMeetClient._();
  static final instance = InMeetClient._();

  void init(
      {required String socketUrl,
      required String projectId,
      required String userName,
      required String userId,
      required InMeetClientEvents listener}) {
    if (socketUrl.isEmpty || projectId.isEmpty) {
      Exception('initializing values should not be empty');
    }
    peerId = getPeerId(8);
    this.socketUrl = socketUrl;
    this.projectId = projectId;
    this.userName = userName;
    this.userId = userId;
    _listeners = listener;
  }

  Future<Map<String, List<String>>> getAvailableDeviceInfo() async {
    try {
      devices = await navigator.mediaDevices.enumerateDevices();
    } on Exception catch (e) {
      throw Exception(e);
    }

    videoInputs.clear();
    audioInputs.clear();
    audioOutputs.clear();

    for (var device in devices!) {
      switch (device.kind) {
        case 'audioinput':
          audioInputs.add(device.label);
          break;
        case 'audiooutput':
          audioOutputs.add(device.label);
          break;
        case 'videoinput':
          videoInputs.add(device.label);
          break;
        default:
          break;
      }
    }
    return {
      'audioOutputDevices': audioOutputs,
      'audioInputDevices': audioInputs,
      'videoInputDevices': videoInputs
    };
  }

  Future<MediaStream> getVideoStream() async {
    localVideoStream = await _createVideoStream();
    return localVideoStream!;
  }

  void addModifiedStream(MediaStream stream) {
    localVideoStream = stream;
  }

  Future<RTCVideoRenderer> getPreviewRenderer([deviceName]) async {
    localVideoStream?.dispose();
    localVideoStream = null;
    MediaDeviceInfo? selectedDevice =
        devices!.firstWhereOrNull((element) => element.label == deviceName);
    if (selectedDevice != null) {
      localVideoStream ??= await _createVideoStream(selectedDevice.deviceId);
    } else {
      localVideoStream ??= await _createVideoStream();
    }
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = localVideoStream;
    return renderer;
  }

  void stopPreviewRenderer() {
    localVideoStream?.dispose();
    localVideoStream = null;
  }

  Future<void> resumeWebCam() async {
    await enableWebCam();
  }

  Future<void> pauseWebCam() async {
    await disableWebcam();
  }

  Future<bool> switchCamera() async {
    if (localVideoStream == null) {
      throw Exception('camera is off');
    }
    return Helper.switchCamera(localVideoStream!.getTracks().first);
  }

  Future<void> switchToSpecificCamera(String deviceName) async {
    if (devices == null) {
      throw Exception('device informations missing');
    }
    String? device =
        videoInputs.firstWhereOrNull((element) => element == deviceName);
    if (device != null) {
      MediaDeviceInfo? selectedDevice =
          devices!.firstWhereOrNull((element) => element.label == device);
      if (selectedDevice != null) {
        await createNewVideoStream(selectedDevice.deviceId);
      }
    }
  }

  Future<void> changeAudioOutput(String deviceName) async {
    if (devices == null) {
      throw Exception('device informations missing');
    }
    String? device =
        audioOutputs.firstWhereOrNull((element) => element == deviceName);
    if (device != null) {
      MediaDeviceInfo? selectedDevice =
          devices!.firstWhereOrNull((element) => element.label == device);
      if (selectedDevice != null) {
        Helper.selectAudioOutput(selectedDevice.deviceId);
      }
    }
  }

  Future<void> changeAudioInput(String deviceName) async {
    if (devices == null) {
      throw Exception('device informations missing');
    }
    String? device =
        audioInputs.firstWhereOrNull((element) => element == deviceName);
    if (device != null) {
      MediaDeviceInfo? selectedDevice =
          devices!.firstWhereOrNull((element) => element.label == device);
      if (selectedDevice != null) {
        Helper.selectAudioInput(selectedDevice.deviceId);
      }
    }
  }

  Future<void> createNewVideoStream(deviceId) async {
    if (localVideoStream != null) {
      await disableWebcam();
      localVideoStream?.dispose();
      webcam = null;
      localVideoStream = await _createVideoStream(deviceId);
      _enableWebcam('webcam');
    }
  }

  /// For join the meeting
  Future<void> join({required String sessionId}) async {
    if (_listeners == null) {
      throw Exception("listener is getting null");
    }
    roomId = sessionId;
    socketIo = InmeetSocketIO(
        socketUrl: socketUrl,
        projectId: projectId,
        userName: userName,
        userId: userId,
        roomID: sessionId,
        peerId: peerId,
        breakoutRooms: isBreakoutRooms,
        breakoutRoomId: breakoutRoomId);

    socketIo?.onOpen = () {
      _listeners!.onSocketConnect();
    };
    socketIo?.onFail = () {
      _listeners!.onSocketConnectionFail();
    };

    socketIo?.onDisconnected = (e) {
      _listeners!.onSocketDisconnect(e);

      if (sendTransport != null) {
        sendTransport!.close();
        sendTransport = null;
      }
      if (recvTransport != null) {
        recvTransport!.close();
        recvTransport = null;
      }
    };

    socketIo?.onClose = () {
      _listeners!.onSocketClose();

      exitMeeting();
    };

    /// Listen socket io client event.
    socketIo?.onNotification = (notification) async {
      final socketNotification =
          stringToSocketNotifications[notification['method']];
      log("$socketNotification ${notification['method']}",
          name: "Socket Nofitication");
      log("$socketNotification ${notification['data']}",
          name: "Socket Nofitication");
      if (socketNotification == null) return;

      switch (socketNotification) {
        case SocketNotifications.roomReady:
          {
            // meetingId = notification['data']['roomTemplate']['meetingDetails']
            //     ['meetingId'];
            await joinRoom();

            break;
          }
        case SocketNotifications.roomBack:
          {
            break;
          }

        case SocketNotifications.newConsumer:
          final bool isScreenshare =
              notification['data']['appData']['source'].toString() == "screen";
          var data = notification['data'];
          String peerId = data['peerId'];
          InMeetPeerModel? peer =
              peers.firstWhere((p) => p.id.contains(peerId));
          int peerIndex = peers.indexOf(peer);

          if (isScreenshare) {
            final InMeetPeerModel newPeer = InMeetPeerModel.fromMap({
              'id': notification['data']['peerId'],
              'displayName':
                  peers.contains(peer) ? peers[peerIndex].displayName : "",
              'raisedHand': false,
            });
            screenSharePeers.add(newPeer);
            screenShareConsumerIds
                .addAll({notification['data']['id']: newPeer.id});

            recvTransport!.consume(
              id: notification['data']['id'],
              producerId: notification['data']['producerId'],
              kind: RTCRtpMediaTypeExtension.fromString(
                  notification['data']['kind']),
              rtpParameters:
                  RtpParameters.fromMap(notification['data']['rtpParameters']),
              appData:
                  Map<String, dynamic>.from(notification['data']['appData']),
              peerId: notification['data']['peerId'],
            );
          } else if (notification['data']['appData']['source'].toString() ==
              "webcam") {
            recvTransport!.consume(
              id: notification['data']['id'],
              producerId: notification['data']['producerId'],
              kind: RTCRtpMediaTypeExtension.fromString(
                  notification['data']['kind']),
              rtpParameters:
                  RtpParameters.fromMap(notification['data']['rtpParameters']),
              appData:
                  Map<String, dynamic>.from(notification['data']['appData']),
              peerId: notification['data']['peerId'],
            );
          } else if (notification['data']['appData']['source'].toString() ==
              "mic") {
            final peerIndex = peers.indexWhere(
                (element) => element.id == notification['data']['peerId']);
            peers[peerIndex] =
                peers[peerIndex].setAudioId(notification['data']['id']);
            peers[peerIndex] = peers[peerIndex]
                .audioStatusChange(notification['data']['producerPaused']);

            recvTransport!.consume(
              id: notification['data']['id'],
              producerId: notification['data']['producerId'],
              kind: RTCRtpMediaTypeExtension.fromString(
                  notification['data']['kind']),
              rtpParameters:
                  RtpParameters.fromMap(notification['data']['rtpParameters']),
              appData:
                  Map<String, dynamic>.from(notification['data']['appData']),
              peerId: notification['data']['peerId'],
            );
          }
          break;
        case SocketNotifications.consumerClosed:
          String consumerId = notification['data']['consumerId'];
          if (screenShareConsumerIds.containsKey(consumerId)) {
            final screenSharePeer = screenSharePeers.firstWhere(
                (element) => element.id == screenShareConsumerIds[consumerId]);
            screenSharePeers.remove(screenSharePeer);
            screenShareConsumerIds.remove(consumerId);

            _listeners!.onScreenShareConsumerRemoved(screenSharePeer);
          }

          final InMeetPeerModel peer =
              peers.firstWhere((p) => p.consumers.contains(consumerId));
          final peerIndex = peers.indexOf(peer);
          if (peer.audio?.id == consumerId) {
            peers[peerIndex] = peers[peerIndex].removeAudio();

            _listeners!.onAudioConsumerRemoved(peers[peerIndex]);
          } else if (peer.video?.id == consumerId) {
            final consumer = peer.video;
            final renderer = peer.renderer;
            peers[peerIndex] = peers[peerIndex].removeVideoAndRenderer();

            consumer
                ?.close()
                .then((_) => Future.delayed(const Duration(microseconds: 300)))
                .then((_) async => await renderer?.dispose());

            _listeners!.onVideoConsumerRemoved(peers[peerIndex]);
          }

          break;

        case SocketNotifications.consumerPaused:
          {
            String consumerId = notification['data']['consumerId'];
            peerAudioPausedConsumer(consumerId, true);
            break;
          }
        case SocketNotifications.consumerResumed:
          {
            String consumerId = notification['data']['consumerId'];
            peerAudioPausedConsumer(consumerId, false);

            break;
          }

        case SocketNotifications.newPeer:
          {
            final Map<String, dynamic> newPeer =
                Map<String, dynamic>.from(notification['data']);
            log("this is the new peer data newPeer $newPeer");
            newPeer.addAll({});

            final InMeetPeerModel peer = InMeetPeerModel.fromMap(newPeer);
            peers.add(peer);

            if (notification['data']["roleType"] == "Host") {
              hosts.add(peer);
            }

            _listeners!.onNewPeerAdded(peer);

            break;
          }

        case SocketNotifications.peerClosed:
          {
            String peerId = notification['data']['peerId'];
            InMeetPeerModel peer =
                peers.where((p) => p.id.contains(peerId)).first;
            final peerIndex = peers.indexOf(peer);
            peers.removeAt(peerIndex);

            if (breakoutRooms.isNotEmpty) {
              _removeBreakOutPeer(peerId);
            }

            _listeners!.onPeerRemoved(peer);

            break;
          }
        case SocketNotifications.activeSpeaker:
          {
            if (notification['data']['peerId'] != null) {
              int peerIndex = peers.indexWhere((element) =>
                  element.id.contains(notification['data']['peerId']));
              if (peerIndex == -1) {
                break;
              }

              _listeners!.onActiveSpeakerChange(peers[peerIndex],
                  (notification["data"]["volume"]).toDouble());
            }

            break;
          }
        case SocketNotifications.sendPeerShareRequest:
          _listeners!.onScreenShareRequest(notification['data']['peerId']);
          break;
        case SocketNotifications.gotRole:
          participantsRolesChanging(notification["data"]["peerId"],
              notification["data"]["roleId"], true);
          break;
        case SocketNotifications.lostRole:
          participantsRolesChanging(notification["data"]["peerId"],
              notification["data"]["roleId"], false);
          break;
        case SocketNotifications.moderatorKick:
          exitMeeting();
          break;
        case SocketNotifications.cloudRecordingStatus:
          // _listeners!.onCloudRecordingUpdate(notification['data']['status']);

          break;
        case SocketNotifications.cloudRecordingError:
          // _listeners!.onCloudRecordingError();
          break;
        case SocketNotifications.breakoutJoin:
          breakoutRoomId = notification['data']['breakoutPeers']['id'];
          isBreakoutRooms = true;

          _listeners!.onBreakoutRoomStart(
              notification['data']['breakoutPeers']['roomName']);

          // clearingData();
          // join(sessionId: roomId);

          break;
        case SocketNotifications.handleBrToMrByHost:
          if (notification['data']['type'] == 'movePeerToBrToMr') {
            breakoutRoomId = null;
            isBreakoutRooms = false;
            clearingData();
            _listeners!.movingToMainRoom();
            // join(sessionId: roomId);
          } else {
            if (!(breakoutRoomId == notification['data']['data']['id'])) {
              breakoutRoomId = notification['data']['data']['id'];

              // clearingData();
              // join(sessionId: roomId);
              _listeners!
                  .movingBetweenRooms(notification['data']['data']['roomName']);
            }
          }

          break;
        case SocketNotifications.closeBreakoutRoomToMainRoom:
          breakoutRoomId = null;
          isBreakoutRooms = false;
          _listeners!.onBreakoutRoomEnd();
          // clearingData();
          // join(sessionId: roomId);
          break;
        case SocketNotifications.breakoutRoomIsStopped:
          _listeners!.onBreakoutRoomEnd();
          break;
        case SocketNotifications.setPeerToBrRoomList:
          final breakoutRoom = breakoutRooms.toList();
          final roomIndex = breakoutRoom.indexWhere((element) =>
              element.id == notification['data']['breakoutRoomId']);

          if (roomIndex != -1) {
            final participants = List<ParticipantsList>.from(
                breakoutRoom[roomIndex].participantsList);
            participants.add(
                ParticipantsList.fromJson(notification['data']['peerData']));
            breakoutRoom[roomIndex] = breakoutRoom[roomIndex]
                .copyWith(participantsList: participants);
            breakoutRooms = breakoutRoom.toSet();
            log(inMeetBrModelToJson(breakoutRoom), name: 'setPeerToBrRoomList');

            _listeners!.onPeerJoinedToBreakoutRoom(
                notification['data']['peerData']['id'],
                notification['data']['peerData']['displayName'],
                breakoutRoom[roomIndex].roomName);
          }
          break;
        case SocketNotifications.peerLeaveOrCloseInBrRoom:
          _removeBreakOutPeer(notification['data']['peerId']);
          _listeners!
              .onPeerLeavesFromBreakoutRoom(notification['data']['peerId']);
          break;
        case SocketNotifications.mainRoomPeerJoin:
          final data = {
            'id': notification['data']['id'],
            'displayName': notification['data']['displayName']
          };
          _listeners!.onNewPeerJoinsinMainRoom(data);
          break;
        default:
          break;
      }
    };
  }

  /// Join a room
  joinRoom() async {
    _listeners!.onConnectingToRoom();

    try {
      mediasoupDevice = Device();

      Map routerRtpCapabilities = await socketIo!.sendEventEmitterAck(
        'getRouterRtpCapabilities',
        {},
      );

      final rtpCapabilities = RtpCapabilities.fromMap(routerRtpCapabilities);
      rtpCapabilities.headerExtensions
          .removeWhere((he) => he.uri == 'urn:3gpp:video-orientation');
      await mediasoupDevice!.load(routerRtpCapabilities: rtpCapabilities);

      if (mediasoupDevice!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) ==
              true ||
          mediasoupDevice!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeVideo) ==
              true) {
        produce = true;
      }

      // Create a transport in the server via socket io client for sending our media through it.
      Map socketTransportInfo =
          await socketIo?.sendEventEmitterAck('createWebRtcTransport', {
        'forceTcp': false,
        'producing': true,
        'consuming': false,
        'sctpCapabilities': mediasoupDevice!.sctpCapabilities.toMap(),
      });
      /////('getted transportInfo: $transportInfo');
      ////("Before createsendTransport from map is triggering +++++++++++++++++++++++++++++++++++");

      sendTransport = mediasoupDevice!.createSendTransportFromMap(
        socketTransportInfo,
        producerCallback: _producerCallback,
      );

      // Set transport method "connect" event handler connectWebRtcTransport send via socket io client.
      // with params: transportId, dtlsParameters
      // Done in the server, tell our transport.
      // Something was wrong in server side.
      sendTransport!.on('connect', (Map data) async {
        await socketIo!
            .sendEventEmitter('connectWebRtcTransport', {
              'transportId': sendTransport!.id,
              'dtlsParameters': data['dtlsParameters'].toMap(),
            })
            .then(data['callback'])
            .catchError(data['errback']);
      });

      // Set transport "produce" event handler.
      // Here we must communicate our local parameters to our remote transport.
      // Done in the server, pass the response to our transport.
      // Something was wrong in server side.
      sendTransport!.on('produce', (Map data) async {
        try {
          Map response = await socketIo?.sendEventEmitterAck(
            'produce',
            {
              'transportId': sendTransport!.id,
              'kind': data['kind'],
              'rtpParameters': data['rtpParameters'].toMap(),
              if (data['appData'] != null)
                'appData': Map<String, dynamic>.from(data['appData'])
            },
          );

          data['callback'](response['id']);
        } catch (error) {
          data['errback'](error);
        }
      });

      // Set transport "producedata" event handler.
      // Here we must communicate our local parameters to our remote transport.
      // Done in the server, pass the response to our transport.
      // Something was wrong in server side.
      sendTransport!.on('producedata', (data) async {
        ////("send transport producedata is working $data");
        try {
          Map response = await socketIo?.sendEventEmitterAck('produceData', {
            'transportId': sendTransport!.id,
            'sctpStreamParameters': data['sctpStreamParameters'].toMap(),
            'label': data['label'],
            'protocol': data['protocol'],
            'appData': data['appData'],
          });

          data['callback'](response['id']);
        } catch (error) {
          data['errback'](error);
        }
      });

      // Create a transport in the server via socket io client for receiving our media through it.
      Map transportInfo = await socketIo?.sendEventEmitterAck(
        'createWebRtcTransport',
        {
          'forceTcp': false,
          'producing': false,
          'consuming': true,
          'sctpCapabilities': mediasoupDevice!.sctpCapabilities.toMap(),
        },
      );
      /////('getted consume transportInfo: $transportInfo');

      recvTransport = mediasoupDevice!.createRecvTransportFromMap(
        transportInfo,
        consumerCallback: _consumerCallback,
      );
      // Set transport method "connect" event handler connectWebRtcTransport send via socket io client.
      // with params: transportId, dtlsParameters
      // Done in the server, tell our transport.
      // Something was wrong in server side.
      recvTransport!.on(
        'connect',
        (data) {
          socketIo!
              .sendEventEmitter(
                'connectWebRtcTransport',
                {
                  'transportId': recvTransport!.id,
                  'dtlsParameters': data['dtlsParameters'].toMap(),
                },
              )
              .then(data['callback'])
              .catchError(data['errback']);
        },
      );

      // Request to join the room.
      // displayName: display name of the user.
      // device: device information.
      // rtpCapabilities: RTP capabilities of the user.
      // sctpCapabilities: SCTP capabilities of the user.
      // Response peers from the server.

      Map response = await socketIo?.sendEventEmitterAck('join', {
        'displayName': userName,
        'picture': '',
        'rtpCapabilities': mediasoupDevice!.rtpCapabilities.toMap(),
        'sctpCapabilities': mediasoupDevice!.sctpCapabilities.toMap(),
      });

      response['peers'].forEach((value) {
        InMeetPeerModel peer =
            InMeetPeerModel.fromMap(Map<String, dynamic>.from(value));
        peers.add(peer);
      });

      hostId = response['roomTemplate']['meetingDetails']['hostUid'];
      if (hostId == userId) {
        clientRole
            .addAll({ParticipantRoles.moderator, ParticipantRoles.presenter});
      }

      _listeners!.onRoomJoiningSuccess(peers, clientRole, hostId);

      if (breakoutRooms.isEmpty) {
        if (response['isBreakoutRoomStart'] == true) {
          isBreakoutRooms = true;

          for (int i = 0; i < response["breakoutRoomData"].length; i++) {
            final List<ParticipantsList> participantList = [];
            final responseParticipantList =
                (response["breakoutRoomData"][i]['participantsList']) as List;
            for (int j = 0; j < responseParticipantList.length; j++) {
              participantList.add(
                ParticipantsList(
                  id: responseParticipantList[j]['id'],
                  displayName: responseParticipantList[j]['displayName'],
                  isBreakoutRoom: responseParticipantList[j]['isBreakoutRoom'],
                ),
              );
            }
            breakoutRooms.add(
              InMeetBrModel(
                roomName: response["breakoutRoomData"][i]['roomName'],
                participantsList: participantList,
                roomnameeditable: false,
                id: response["breakoutRoomData"][i]['id'],
              ),
            );
          }
          _listeners!
              .onBreakoutRoomOngoingWhileJoin(response["breakoutRoomData"]);
        }
      }
    } on Exception catch (e) {
      _listeners!.onRoomJoiningFailed(e);
    }
  }

  Future<void> enableWebCam([String? deviceName]) async {
    MediaDeviceInfo? selectedDevice =
        devices!.firstWhereOrNull((element) => element.label == deviceName);
    if (selectedDevice != null) {
      localVideoStream ??= await _createVideoStream(selectedDevice.deviceId);
    } else {
      localVideoStream ??= await _createVideoStream();
    }
    await _enableWebcam('webcam');
  }

  void _producerCallback(Producer producer) async {
    if (producer.source == 'mic') {
      producer.on('transportclose', () {
        mic?.close();
        mic = null;
      });

      producer.on('trackended', () {});
    } else if (producer.source == 'webcam') {
      producer.on('transportclose', () {
        webcam?.close();
        webcam = null;
      });

      producer.on('trackended', () {});
    } else if (producer.source == 'screen') {
      producer.on('transportclose', () {
        //  scre
      });

      producer.on('trackended', () {});
    }

    switch (producer.source) {
      case 'mic':
        {
          mic = producer;
          break;
        }
      case 'webcam':
        {
          webcam = producer;
          RTCVideoRenderer renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.setSrcObject(
              stream: producer.stream, trackId: producer.track.id);

          _listeners!.onLocalRenderCreated(renderer);

          break;
        }
      case 'screen':
        {
          RTCVideoRenderer screenShareRender = RTCVideoRenderer();
          await screenShareRender.initialize();
          screenShareRender.setSrcObject(
            stream: producer.stream,
            trackId: producer.track.id,
          );
          localScreenShareProducer = producer;
          _listeners!.onSelfScreenShareStarted(screenShareRender);

          break;
        }

      default:
        break;
    }
  }

  Future<void> requestForScreenShare() async {
    socketIo?.sendEventEmitter(
        'shareSendRequest', {'peerId': peerId, "displayName": userName});
  }

  Future<void> startScreenShare() async {
    if (!clientRole.contains(ParticipantRoles.presenter)) {
      throw Exception("Participant can't share screen");
    }
    await createScreenShareStream();
  }

  Future<void> stopScreenShare() async {
    for (MediaStreamTrack track in localScreenShareStream!.getTracks()) {
      track.stop();
    }
// localScreenShareStream.id
    // Dispose the media stream
    socketIo?.sendEventEmitter(
        'closeProducer', {'producerId': localScreenShareProducer!.id});
    localScreenShareStream!.dispose();

    _listeners!.onSelfScreenShareStoped();
  }

  void _consumerCallback(Consumer consumer, [dynamic accept]) async {
    String peerId = consumer.peerId!;
    try {
      MediaStream stream = consumer.stream;
      stream.addTrack(consumer.track);
      consumer.pause();
      socketIo?.sendEventEmitter(
          'pauseConsumer', {'consumerId': consumer.id, 'peerId': peerId});
      InMeetPeerModel peer = peers.where((p) => p.id.contains(peerId)).first;
      int peerIndex = peers.indexOf(peer);
      if (consumer.appData['source'].toString() == "screen") {
        InMeetPeerModel screenSharePeer =
            screenSharePeers.where((p) => p.id.contains(peerId)).first;
        final screenSharePeerIndex = screenSharePeers.indexOf(screenSharePeer);
        if (consumer.kind == 'video') {
          consumer.resume();
          socketIo?.sendEventEmitter(
              'resumeConsumer', {'consumerId': consumer.id, 'peerId': peerId});
          screenShareConsumerIds.addAll({consumer.id: peerId});
          screenSharePeers[screenSharePeerIndex] =
              screenSharePeers[screenSharePeerIndex].copyWith(
            renderer: RTCVideoRenderer(),
            video: consumer,
          );

          await screenSharePeers[screenSharePeerIndex].renderer!.initialize();
          // newPeers[event.peerId]!.renderer!.audioOutput = selectedOutputId;
          screenSharePeers[screenSharePeerIndex]
              .renderer!
              .setSrcObject(stream: stream, trackId: consumer.track.id);
        } else {
          peers[peerIndex] = peers[peerIndex].copyWith(
            audio: consumer,
          );
        }

        _listeners!.onScreenShareConsumerRecieved(
            screenSharePeers[screenSharePeerIndex]);
      } else if (consumer.kind == 'video') {
        peers[peerIndex] = peers[peerIndex].copyWith(
          renderer: null,
          video: consumer,
          videoPaused: false,
        );

        _listeners!.onVideoConsumerRecieved(peers[peerIndex]);
      } else if (consumer.appData['source'].toString() == 'mic') {
        consumer.resume();

        socketIo?.sendEventEmitter(
            'resumeConsumer', {'consumerId': consumer.id, 'peerId': peerId});
        peers[peerIndex] =
            peers[peerIndex].copyWith(audio: consumer, audioMuted: false);

        _listeners!.onAudioConsumerRecieved(peers[peerIndex]);
      }
      // }
    } catch (error) {
      log("ERROR on Video consumer recieved $error");
    }
  }

  Future<MediaStream> _createAudioStream([deviceId]) async {
    if(deviceId != null){
      selectedAudioInputDeviceId = deviceId;
    }
    if (mediasoupDevice!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) ==
        true) {
      Map<String, dynamic> mediaConstraints = <String, dynamic>{
        'audio': {
          'mandatory': {
            'echoCancellation': true,
            'autoGainControl': true,
            'noiseSuppression': true,
          },
          'optional': [
            {if (selectedAudioInputDeviceId != null) 'sourceId': selectedAudioInputDeviceId},
          ],
        },
        'video': false
      };

      MediaStream stream =
          await nav.navigator.mediaDevices.getUserMedia(mediaConstraints);
      return stream;
    } else {
      throw Exception("Device can't produce audio");
    }
  }

  Future<MediaStream> _createVideoStream([deviceId]) async {
    if (deviceId != null) {
      selectedVideoInputId = deviceId;
    }
    Map<String, dynamic> mediaConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'optional': [
          {if (selectedVideoInputId != null) 'sourceId': selectedVideoInputId},
        ],
      },
    };

    MediaStream stream =
        await nav.navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }

  Future<void> createScreenShareStream() async {
    if (WebRTC.platformIsWindows) {
      await nav.desktopCapturer.getSources(types: [SourceType.Screen]);
    }
    final mediaConstraints1 = <String, dynamic>{
      'audio': true,
      'video': WebRTC.platformIsIOS ? {'deviceId': 'broadcast'} : true,
      'frameRate': 30
    };

    try {
      await navigator.mediaDevices
          .getDisplayMedia(mediaConstraints1)
          .then((value) {
        localScreenShareStream = value;
        _enableWebcam("screen");

        return value;
      });
    } catch (e) {
      log("ScreenShare failed $e");
      rethrow;
    }
  }

  Future<void> enableMic([deviceId]) async {
    if (mediasoupDevice!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) ==
        false) {
      return;
    }

    try {
      final MediaStreamTrack track = localAudioStream!.getAudioTracks().first;

      sendTransport!.produce(
        track: track,
        codecOptions: ProducerCodecOptions(opusStereo: 1, opusDtx: 1),
        stream: localAudioStream!,
        appData: {
          'source': 'mic',
        },
        source: 'mic',
      );
      _listeners!.onSelfMicrophoneStateChanged(false);
    } catch (error) {
      if (localAudioStream != null) {
        await localAudioStream!.dispose();
      }
    }
  }

  Future<void> _enableWebcam(String source) async {
    if (mediasoupDevice!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeVideo) ==
        false) {
      return;
    }
    try {
      RtpCodecCapability? codec = mediasoupDevice!.rtpCapabilities.codecs
          .firstWhere((RtpCodecCapability c) {
        return c.mimeType.toLowerCase() == 'video/vp9' ||
            c.mimeType.toLowerCase() == 'video/vp8';
      },
              orElse: () =>
                  throw 'desired vp9 codec+configuration is not supported');

      log("the codec is this ${codec.toMap()}");

      final MediaStreamTrack track;
      if (source == 'screen') {
        track = localScreenShareStream!.getVideoTracks().first;
      } else {
        track = localVideoStream!.getVideoTracks().first;
      }

      sendTransport!.produce(
        track: track,
        stream:
            source == "screen" ? localScreenShareStream! : localVideoStream!,
        codecOptions: ProducerCodecOptions(
          videoGoogleStartBitrate: 1000,
        ),
        appData: {'source': source},
        source: source,
        codec: codec,
      );
      if (source == 'webcam') {
        _listeners!.onSelfCameraStateChanged(true);
      }
    } catch (error) {
      log("ERROR $error");
    }
  }

  void peerAudioPausedConsumer(String consumerId, bool muted) {
    final peerIndex = peers.indexWhere((p) => p.audioId == consumerId);
    if (peerIndex != -1) {
      peers[peerIndex] = peers[peerIndex].audioStatusChange(muted);

      if (muted == true) {
        _listeners!.onAudioConsumerPaused(peers[peerIndex]);
      } else {
        _listeners!.onAudioConsumerResume(peers[peerIndex]);
      }
    }
  }

  /// Mute mic
  Future<void> muteMic() async {
    mic!.pause();

    try {
      socketIo?.sendEventEmitter('pauseProducer', {'producerId': mic?.id});
      _listeners!.onSelfMicrophoneStateChanged(true);
    } catch (error) {
      log("error while mute mic $error");
    }
  }

  // unMute mic
  Future<void> unmuteMic([deviceName]) async {
    if (mic == null) {
      MediaDeviceInfo? selectedDevice =
          devices!.firstWhereOrNull((element) => element.label == deviceName);
      if (selectedDevice != null) {
        localAudioStream ??= await _createAudioStream(selectedDevice.deviceId);
      } else {
        localAudioStream ??= await _createAudioStream();
      }
      await enableMic();
    }
    mic?.resume();
    try {
      socketIo?.sendEventEmitter('resumeProducer', {
        'producerId': mic?.id,
      });
      _listeners!.onSelfMicrophoneStateChanged(false);
    } catch (error) {
      log("unMute mic ERROR $error");
    }
  }

  Future<void> disableWebcam() async {
    String webcamId = webcam?.id ?? "";

    webcam = null;

    try {
      socketIo?.sendEventEmitter('closeProducer', {'producerId': webcamId});
      _listeners!.onSelfCameraStateChanged(false);
      _listeners!.onLocalRenderCreated(null);
    } catch (_) {}
  }

  // Future<void> startCloudRecording() async {
  //   Map<String, String> data = {
  //     "sessionId": roomId.toString(),
  //     "roomId": meetingId.toString(),
  //     "hostName": "wriety.inmeet.ai"
  //   };

  //   socketIo?.sendEventEmitterAck('startRecording', data);
  // }

  // Future<void> stopCloudRecording() async {
  //   Map<String, String> data = {
  //     "sessionId": roomId.toString(),
  //     "roomId": meetingId.toString()
  //   };

  //   socketIo?.sendEventEmitterAck('stopRecording', data);
  // }

  void participantsRolesChanging(
      String moderatorPeerId, moderatorRoleId, bool gotRole) {
    if (peerId == moderatorPeerId) {
      if (moderatorRoleId == 5337) {
        gotRole
            ? clientRole.add(ParticipantRoles.moderator)
            : clientRole.remove(ParticipantRoles.moderator);
        _listeners!.onSelfRoleChange(clientRole);
      } else if (moderatorRoleId == 9583) {
        gotRole
            ? clientRole.add(ParticipantRoles.presenter)
            : clientRole.remove(ParticipantRoles.presenter);
        _listeners!.onSelfRoleChange(clientRole);
      }
    } else {
      for (InMeetPeerModel item in peers) {
        if (moderatorPeerId == item.id) {
          if (moderatorRoleId == 5337) {
            gotRole
                ? item.role.add(ParticipantRoles.moderator)
                : item.role.remove(ParticipantRoles.moderator);

            _listeners!.onParticipantRoleChange(item, item.role);
          } else if (moderatorRoleId == 9583) {
            gotRole
                ? item.role.add(ParticipantRoles.presenter)
                : item.role.remove(ParticipantRoles.presenter);
            _listeners!.onParticipantRoleChange(item, item.role);
          }
        }
      }
    }
  }

  void endMeetingForAll() async {
    if (clientRole.contains(ParticipantRoles.moderator)) {
      await socketIo?.sendEventEmitter('moderator:closeMeeting', {});
      exitMeeting();
    } else {
      throw Exception('Moderator can only do endMeetingForAll');
    }
  }

  void giveRoleToParticipant(
      String participantPeerId, ParticipantRoles roleType) {
    if (!clientRole.contains(ParticipantRoles.moderator)) {
      throw Exception("Only host can give roles");
    }
    if (roleType == ParticipantRoles.moderator ||
        roleType == ParticipantRoles.presenter) {
      socketIo?.sendEventEmitter('moderator:giveRole', {
        'peerId': participantPeerId,
        'roleId': roleType == ParticipantRoles.moderator ? 5337 : 9583
      });
    }
  }

  void removeRoleFromParticipant(
      String participantPeerId, ParticipantRoles roleType) {
    if (!clientRole.contains(ParticipantRoles.moderator)) {
      throw Exception("Only host can remove roles");
    }
    if (roleType == ParticipantRoles.moderator ||
        roleType == ParticipantRoles.presenter) {
      socketIo?.sendEventEmitter('moderator:removeRole', {
        'peerId': participantPeerId,
        'roleId': roleType == ParticipantRoles.moderator ? 5337 : 9583
      });
    }
  }

  String getPeerId(int length) {
    var chars = 'abcdefghijklmnopqrstuvwxyz1234567890';
    math.Random rnd = math.Random();
    String dummyPeerId = String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return dummyPeerId;
  }

  RTCVideoRenderer disposeParticipantRenderer(
      String peerId, RTCVideoRenderer renderer) {
    InMeetPeerModel? peer =
        peers.firstWhereOrNull((element) => element.id == peerId);
    if (peer != null && peers[peers.indexOf(peer)].renderer != null) {
      peers[peers.indexOf(peer)].renderer!.dispose();
      renderer.dispose();
      peers[peers.indexOf(peer)].renderer = null;
      peers[peers.indexOf(peer)].video!.pause();
      socketIo?.sendEventEmitter('pauseConsumer', {
        'consumerId': peers[peers.indexOf(peer)].video!.id,
        'peerId': peerId
      });
    }
    return renderer;
  }

  Future<RTCVideoRenderer?> initializeParticipantRenderer(String peerId) async {
    InMeetPeerModel? peer =
        peers.firstWhereOrNull((element) => element.id == peerId);
    // InMeetPeerModel? screenSharePeer =
    //     screenSharePeers.firstWhereOrNull((element) => element.id == peerId);

    if (peer != null) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.setSrcObject(
          stream: peers[peers.indexOf(peer)].video!.stream,
          trackId: peers[peers.indexOf(peer)].video!.track.id!);
      peers[peers.indexOf(peer)].video!.resume();
      socketIo?.sendEventEmitter('resumeConsumer', {
        'consumerId': peers[peers.indexOf(peer)].video!.id,
        'peerId': peerId
      });
      return renderer;
    }
    return null;
  }

  void exitMeeting() async {
    await clearingData();
    _listeners!.onCallEnd();
  }

  Future<void> clearingData() async {
    socketIo?.close();
    socketIo = null;
    await sendTransport?.close();
    await recvTransport?.close();
    localVideoStream?.getTracks().forEach((element) => element.stop());
    await localAudioStream?.dispose();
    await localScreenShareStream?.dispose();
    webcam?.close();
    peers.clear();
    hosts.clear();
    screenSharePeers.clear();
    screenShareConsumerIds.clear();
  }

  // Breakout rooms

  dynamic startBreakoutRooms({
    required Map<String, dynamic> roomData,
  }) {
    // if (breakoutRooms.isEmpty) {
    breakoutRooms.clear();
    for (int i = 0; i < roomData.length; i++) {
      List<ParticipantsList> participants = [];
      for (int j = 0;
          j < (roomData[roomData.keys.elementAt(i)] as List).length;
          j++) {
        log("THE PEER ID IS ${(roomData[roomData.keys.elementAt(i)] as List<dynamic>)[j]}");
        final peer = peers.firstWhereOrNull((element) =>
            element.id ==
            (roomData[roomData.keys.elementAt(i)] as List<dynamic>)[j]['id']);
        if (peer != null) {
          participants.add(ParticipantsList(
              id: peer.id,
              displayName: peer.displayName,
              isBreakoutRoom: false));
        }
      }
      breakoutRooms.add(
        InMeetBrModel(
          roomName: roomData.keys.elementAt(i),
          participantsList: participants,
          roomnameeditable: false,
          id: "${InMeetHelpers.generatingBreakoutRoomId(8)}_$roomId",
        ),
      );
    }
    // }
    try {
      socketIo?.sendEventEmitterAck('startBreakoutRooms', {
        "breakoutRooms":
            json.decode(inMeetBrModelToJson(breakoutRooms.toList()))
      });
      socketIo?.sendEventEmitterAck(
          'setIsBreakoutRoomStart', {'isBreakoutRoomStart': true});

      socketIo?.sendEventEmitterAck('breakoutRoomData', {
        'breakoutRoomData':
            json.decode(inMeetBrModelToJson(breakoutRooms.toList()))
      });
      return json.decode(inMeetBrModelToJson(breakoutRooms.toList()));
    } on Exception catch (e) {
      throw Exception(e);
    }
  }

  void joinBreakoutRoom() async {
    clearingData();
    join(sessionId: roomId);
  }

  void moveParticipantToDiffRoom(
    String peerId,
    String movingRoomName,
  ) {
    // _removeBreakOutPeer(peerId);
    final movingRoomIndex = breakoutRooms
        .toList()
        .indexWhere((element) => element.roomName == movingRoomName);

    final value = _removingPeerDetails(peerId);
    _removeBreakOutPeer(peerId);
    if (value != null) {
      breakoutRooms.elementAt(movingRoomIndex).participantsList.add(value);
    }

    if (movingRoomIndex != -1) {
      socketIo?.sendEventEmitterAck('handleBrToMrByHost', {
        'peerId': peerId,
        "data": breakoutRooms.elementAt(movingRoomIndex).toJson(),
        "type": "movePeerBtBrRooms"
      });
      socketIo?.sendEventEmitterAck('breakoutRoomData', {
        'breakoutRoomData':
            json.decode(inMeetBrModelToJson(breakoutRooms.toList()))
      });
    } else {
      throw Exception('given moving room name incorrect');
    }
  }

  void moveToMainroom([String? peerId]) async {
    peerId ??= this.peerId;
    if (peerId == this.peerId) {
      await hostMovingToMainRoom();
    }
    _removeBreakOutPeer(peerId);

    socketIo?.sendEventEmitterAck('handleBrToMrByHost',
        {'peerId': peerId, 'data': null, "type": "movePeerToBrToMr"});

    socketIo?.sendEventEmitterAck('breakoutRoomData', {
      'breakoutRoomData':
          json.decode(inMeetBrModelToJson(breakoutRooms.toList()))
    });
  }

  Future<void> hostMovingToMainRoom() async {
    _removeBreakOutPeer(peerId);
    breakoutRoomId = null;
    isBreakoutRooms = false;
    await clearingData();

    // join(sessionId: roomId);
  }

  Future<void> hostMovingToDiffRoom(String movingRoomName) async {
    _removeBreakOutPeer(peerId);
    final movingRoomIndex = breakoutRooms.toList().indexWhere((element) =>
        element.roomName.toLowerCase() == movingRoomName.toLowerCase());

    socketIo?.sendEventEmitterAck('breakoutRoomData', {
      'breakoutRoomData':
          json.decode(inMeetBrModelToJson(breakoutRooms.toList()))
    });
    if (movingRoomIndex != -1) {
      breakoutRoomId = breakoutRooms.elementAt(movingRoomIndex).id;

      isBreakoutRooms = true;
      socketIo?.sendEventEmitterAck('hostJoinedBrRoom', {
        'breakoutRoomData':
            json.decode(inMeetBrModelToJson(breakoutRooms.toList())),
        "brId": breakoutRoomId,
        "currentRoomId": roomId,
        "type": "breakoutRoom"
      });
      await clearingData();
      // await join(sessionId: roomId);
    } else {
      throw Exception('given moving room name incorrect');
    }
  }

  void endBreakoutRooms() async {
    if (breakoutRooms.isEmpty) {
      return;
    }
    List<String> breakoutRoomIds = [];
    for (int i = 0; i < breakoutRooms.length; i++) {
      breakoutRoomIds.add(breakoutRooms.elementAt(i).id);
    }

    try {
      Map<String, dynamic> data = {
        "breakoutRoomData": breakoutRoomIds,
        "isCloseMeeting": false,
        "mainRoomId": roomId,
      };

      String jsonData = jsonEncode(data);

      final url = socketUrl.split(':');
      log("https:${url[1]}/auth/BreakoutRoomEnd");

      final response = await http.post(
        Uri.parse("https:${url[1]}/auth/BreakoutRoomEnd"),
        headers: {'Content-Type': 'application/json'},
        body: jsonData,
      );

      socketIo?.sendEventEmitterAck(
          'setIsBreakoutRoomStart', {"isBreakoutRoomStart": false});
      isBreakoutRooms = false;
      breakoutRoomId = null;
      breakoutRooms.clear();

      if (response.statusCode == 200) {
      } else {}
    } on HttpException catch (e) {
      log(e.toString());
    }
  }

  void _removeBreakOutPeer(String peerId) {
    for (var element in breakoutRooms) {
      element.participantsList.removeWhere((element) => element.id == peerId);
    }
  }

  ParticipantsList? _removingPeerDetails(String peerId) {
    ParticipantsList? value;
    for (var element in breakoutRooms) {
      value = element.participantsList
          .firstWhereOrNull((element) => element.id == peerId);
      if (value != null) {
        return value;
      }
    }

    final peer = peers.firstWhereOrNull((element) => element.id == peerId);
    if (peer != null) {
      value = ParticipantsList(
          id: peer.id, displayName: peer.displayName, isBreakoutRoom: false);
      return value;
    }
  }
}
