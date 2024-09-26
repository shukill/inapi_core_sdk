import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:inapi_core_sdk/src/enums/participant_roles.dart';

import 'models/inmeet_peer_model.dart';

abstract class InMeetClientEvents {
  /// meeting connection time this event will trigger.
  void onConnectingToRoom();

  /// Successful joining of meeting is indicated by '''onRoomJoiningSuccess''' callback and list of peers indicates number of participants present in the meeting.
  void onRoomJoiningSuccess(
      List<InMeetPeerModel> peers, Set<ParticipantRoles> selfRole, String hostId);

  /// fail case of joining
  void onRoomJoiningFailed(Exception e);

  /// Whenever a new participant joins this event will trigger, and it will give  participant details
  void onNewPeerAdded(InMeetPeerModel peer);

  /// Whenever any participant exit from the meet this method will trigger with exited participant details.
  void onPeerRemoved(InMeetPeerModel peer);

  void onParticipantRoleChange(
      InMeetPeerModel peer, Set<ParticipantRoles> availableRoles);

  void onSelfRoleChange(Set<ParticipantRoles> roles);

  /// on self camera disable/enable this method will trigger.
  void onSelfCameraStateChanged(bool isCameraEnabled);

  /// on self mic mute/unmute this method will trigger
  void onSelfMicrophoneStateChanged(bool micPaused);

  /// This method will trigger whenever participant enable the camera. if user joining with enable camera that time also this method will trigger
  void onVideoConsumerRecieved(InMeetPeerModel peer);

  /// Whenever participants disable the camera
  void onVideoConsumerRemoved(InMeetPeerModel peer);

  /// This method will trigger whenever participant enable the mic. if user joining with enable mic that time also this method will trigger
  void onAudioConsumerRecieved(InMeetPeerModel peer);

  /// triggering this method on participants mute their mic
  void onAudioConsumerPaused(InMeetPeerModel peer);

  /// triggering this method on participants unmute their mic
  void onAudioConsumerResume(InMeetPeerModel peer);

  /// after participant exit for their audio removal this event will trigger.
  void onAudioConsumerRemoved(InMeetPeerModel peer);

  /// after starting screen share from self side this method will trigger
  void onSelfScreenShareStarted(RTCVideoRenderer renderer);

  /// after stopping screen share from self side this method will trigger.
  void onSelfScreenShareStoped();

  // /// triggering updating cloud recording stat4e
  // void onCloudRecordingUpdate(isCloudRecording);

  // /// for cloud recording starting time error will trigger using this method.
  // void onCloudRecordingError();

  void onScreenShareRequest(String peerId);

  /// After participant start screen sharing, for that one new inMeetPeerModel will create in that render will come that will use for showing the coming screen share
  void onScreenShareConsumerRecieved(InMeetPeerModel peer);

  /// participants stop screen share this method will trigger from this method we will get the screen sharing peer details.
  void onScreenShareConsumerRemoved(InMeetPeerModel peer);

  /// After calling enabling the camera, camera will initialize. Once local camera is initialized, onLocalRenderCreate this method will trigger.  Here renderer will receive, create a render variable and assign the coming renderer. the created renderer will use for showing the local video.
  void onLocalRenderCreated(RTCVideoRenderer? renderer);

  /// on active speaker change
  void onActiveSpeakerChange(InMeetPeerModel peer, double volume);

  /// After connecting with the server this onSocketConnect method will trigger.
  void onSocketConnect();

  /// After socket disconnecting this onSocketDisconnect will trigger.
  void onSocketDisconnect(e);

  /// while trying to connect the server if any issue came onSocketConnectionFail will trigger.
  void onSocketConnectionFail();

  /// After closing the socket onSocketClose will trigger.
  void onSocketClose();

  /// After ending the call this method will trigger, in this method clear the self render variable.
  void onCallEnd();

  //Breakout rooms

  void onPeerJoinedToBreakoutRoom(
      String peerId, String displayName, String roomName);
  void onBreakoutRoomOngoingWhileJoin(List<dynamic> data);
  void onBreakoutRoomStart(String roomName);
  void onNewPeerJoinsinMainRoom(Map data);
  void movingBetweenRooms(String roomName);
  void movingToMainRoom();
  void onPeerLeavesFromBreakoutRoom(String peerId);
  void onBreakoutRoomEnd();
}
