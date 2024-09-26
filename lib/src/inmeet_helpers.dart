import 'dart:math';

class InMeetHelpers {
 static String generatingBreakoutRoomId(int length) {
    var chars = 'abcdefghijklmnopqrstuvwxyz';
    Random rnd = Random();
   final localPeerId = String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return localPeerId;
  }
}