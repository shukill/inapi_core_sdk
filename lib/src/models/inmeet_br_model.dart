import 'dart:convert';

List<InMeetBrModel> inMeetBrModelFromJson(String str) =>
    List<InMeetBrModel>.from(
        json.decode(str).map((x) => InMeetBrModel.fromJson(x)));

String inMeetBrModelToJson(List<InMeetBrModel> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class InMeetBrModel {
  String roomName;
  List<ParticipantsList> participantsList;
  bool roomnameeditable;
  String id;

  InMeetBrModel({
    required this.roomName,
    required this.participantsList,
    required this.roomnameeditable,
    required this.id,
  });

  InMeetBrModel copyWith(
      {String? roomName,
      List<ParticipantsList>? participantsList,
      bool? roomnameeditable,
      String? id,
      bool? isUserJoinApprovalNeeded}) {
    return InMeetBrModel(
      roomName: roomName ?? this.roomName,
      participantsList: participantsList ?? this.participantsList,
      id: id ?? this.id,
      roomnameeditable: roomnameeditable ?? this.roomnameeditable,
    );
  }

  factory InMeetBrModel.fromJson(Map<String, dynamic> json) => InMeetBrModel(
      roomName: json["roomName"],
      participantsList: json["participantsList"] == null
          ? []
          : List<ParticipantsList>.from(json["participantsList"]!
              .map((x) => ParticipantsList.fromJson(x))),
      roomnameeditable: json["roomnameeditable"],
      id: json["id"],);

  Map<String, dynamic> toJson() => {
        "roomName": roomName,
        "participantsList": participantsList == null
            ? []
            : List<dynamic>.from(participantsList.map((x) => x.toJson())),
        "roomnameeditable": roomnameeditable,
        "id": id,
      };
}

class ParticipantsList {
  String? id;
  String? displayName;
  bool? isBreakoutRoom;

  ParticipantsList({
    this.id,
    this.displayName,
    this.isBreakoutRoom,
  });

  ParticipantsList copyWith({
    String? id,
    String? displayName,
    bool? isBreakoutRoom,
  }) {
    return ParticipantsList(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        isBreakoutRoom: isBreakoutRoom ?? isBreakoutRoom);
  }

  factory ParticipantsList.fromJson(Map<String, dynamic> json) =>
      ParticipantsList(
        id: json["id"],
        displayName: json["displayName"],
        isBreakoutRoom: json["isBreakoutRoom"],
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "displayName": displayName,
        "isBreakoutRoom": isBreakoutRoom,
      };
}
