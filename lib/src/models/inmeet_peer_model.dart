import 'dart:convert';

import 'package:inapi_core_sdk/src/enums/participant_roles.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

class InMeetPeerModel {
  final Consumer? audio;
  final bool audioMuted;
  final bool videoPaused;
  final Consumer? video;
  final String displayName;
  Set<ParticipantRoles> role;
  final String id;
  final String userId;
  RTCVideoRenderer? renderer;
  final String? audioId;

  InMeetPeerModel({this.audio, this.video, this.renderer, required this.displayName, required this.role, required this.id, required this.audioMuted, required this.videoPaused, required this.audioId, required this.userId});

  InMeetPeerModel.fromMap(Map data)
      : id = data['id'],
        displayName = data['displayName'] ?? '',
        role = data['roleType'] == "participant"
            ? {ParticipantRoles.participant}
            : data['roleType'] == "Host"
                ? {ParticipantRoles.moderator}
                : {ParticipantRoles.presenter},
        userId = data['uid'] != null ? utf8.decode(base64.decode(data['uid'] + '==')) : "",
        audio = null,
        video = null,
        audioMuted = true,
        videoPaused = true,
        renderer = null,
        audioId = '';

  List<String> get consumers => [
        if (audio != null) audio!.id else "",
        if (video != null) video!.id else "",
      ];

  InMeetPeerModel copyWith({Consumer? audio, Consumer? video, RTCVideoRenderer? renderer, String? displayName, Set<ParticipantRoles>? role, String? id, bool? audioMuted, bool? isExtraVideo, bool? videoPaused, String? userId}) {
    return InMeetPeerModel(
        audio: audio ?? this.audio,
        video: video ?? this.video,
        renderer: renderer ?? this.renderer,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        videoPaused: videoPaused ?? this.audioMuted,
        id: id ?? this.id,
        audioMuted: audioMuted ?? this.audioMuted,
        audioId: audioId,
        userId: userId ?? this.userId);
  }

  InMeetPeerModel removeAudio({
    Consumer? video,
    RTCVideoRenderer? renderer,
    String? displayName,
    Set<ParticipantRoles>? role,
    String? id,
    bool? audioMuted,
  }) {
    return InMeetPeerModel(
        audio: null,
        video: video ?? this.video,
        renderer: renderer ?? this.renderer,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        videoPaused: video != null ? video.paused : true,
        id: id ?? this.id,
        audioMuted: audioMuted ?? this.audioMuted,
        audioId: audioId,
        userId: userId);
  }

  InMeetPeerModel removeVideo({
    Consumer? audio,
    RTCVideoRenderer? renderer,
    String? displayName,
    Set<ParticipantRoles>? role,
    String? id,
    bool? audioMuted,
    bool? isExtraVideo,
  }) {
    return InMeetPeerModel(
        audio: audio ?? this.audio,
        video: null,
        renderer: renderer ?? this.renderer,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        videoPaused: video != null ? video!.paused : true,
        id: id ?? this.id,
        audioMuted: audioMuted ?? this.audioMuted,
        audioId: audioId,
        userId: userId);
  }

  InMeetPeerModel removeAudioAndRenderer({
    Consumer? video,
    String? displayName,
    Set<ParticipantRoles>? role,
    String? id,
    bool? audioMuted,
  }) {
    return InMeetPeerModel(
        audio: null, video: video ?? this.video, renderer: null, displayName: displayName ?? this.displayName, role: role ?? this.role, videoPaused: video != null ? video.paused : true, id: id ?? this.id, audioMuted: audioMuted ?? this.audioMuted, audioId: audioId, userId: userId);
  }

  InMeetPeerModel removeVideoAndRenderer({
    Consumer? audio,
    String? displayName,
    Set<ParticipantRoles>? role,
    String? id,
    bool? audioMuted,
  }) {
    return InMeetPeerModel(audio: audio ?? this.audio, video: null, renderer: null, displayName: displayName ?? this.displayName, role: role ?? this.role, videoPaused: true, id: id ?? this.id, audioMuted: audioMuted ?? this.audioMuted, audioId: audioId, userId: userId);
  }

  InMeetPeerModel audioStatusChange(
    bool? muted, {
    Consumer? audio,
    String? displayName,
    Set<ParticipantRoles>? role,
    String? id,
  }) {
    return InMeetPeerModel(
        audio: audio ?? this.audio, video: video ?? video, renderer: renderer ?? renderer, displayName: displayName ?? this.displayName, role: role ?? this.role, videoPaused: video != null ? video!.paused : true, id: id ?? this.id, audioMuted: muted ?? audioMuted, audioId: audioId, userId: userId);
  }

  InMeetPeerModel setAudioId(dynamic audioId) {
    return InMeetPeerModel(audio: audio ?? audio, video: video ?? video, renderer: renderer ?? renderer, displayName: displayName, role: role, id: id, audioMuted: audioMuted, videoPaused: video != null ? video!.paused : true, audioId: audioId, userId: userId);
  }
}
