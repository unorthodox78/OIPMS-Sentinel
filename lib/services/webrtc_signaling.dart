import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCSignaling {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCDataChannel? _detectionsDc;
  StreamSubscription? _roomSub;
  StreamSubscription? _calleeCandidatesSub;
  StreamSubscription? _offerSub;
  DocumentReference<Map<String, dynamic>>? _roomRef;
  bool _isCaller = false;
  String? _lastOfferSdp;

  final RTCVideoRenderer localRenderer;
  final RTCVideoRenderer remoteRenderer;
  final void Function(List<Map<String, dynamic>> detections)? onDetections;
  final bool persistRoom;

  WebRTCSignaling({
    required this.localRenderer,
    required this.remoteRenderer,
    this.onDetections,
    this.persistRoom = false,
  });

  Future<void> _createPc() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    _pc = await createPeerConnection(configuration);

    // Remote track
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        remoteRenderer.srcObject = remoteStream;
      }
    };

    // Incoming data channels (used by viewer)
    _pc!.onDataChannel = (RTCDataChannel channel) {
      if (channel.label == 'detections') {
        _detectionsDc = channel;
        channel.onMessage = (RTCDataChannelMessage msg) {
          try {
            final obj = jsonDecode(msg.text);
            if (obj is Map && obj['type'] == 'detections') {
              final data = obj['data'];
              if (data is List) {
                final list = data
                    .map<Map<String, dynamic>>(
                      (e) => Map<String, dynamic>.from(e),
                    )
                    .toList();
                onDetections?.call(list);
              }
            }
          } catch (_) {}
        };
      }
    };

    // Data channel (caller creates)
    final dcInit = RTCDataChannelInit()..ordered = true;
    _detectionsDc = await _pc!.createDataChannel('detections', dcInit);

    // ICE candidates
    _pc!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (_roomRef == null) return;
      await _roomRef!.collection('callerCandidates').add(candidate.toMap());
    };
  }

  Future<void> _attachLocalStream() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'video': {
        'facingMode': 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 24},
      },
      'audio': false,
    });
    for (final t in localStream!.getTracks()) {
      await _pc!.addTrack(t, localStream!);
    }
    localRenderer.srcObject = localStream;
  }

  Future<String> createRoom() async {
    _isCaller = true;
    await _createPc();
    await _attachLocalStream();

    _roomRef = _db.collection('rooms').doc();

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await _roomRef!.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Listen for remote answer
    _roomSub = _roomRef!.snapshots().listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer != null) {
        final current = await _pc!.getRemoteDescription();
        if (current == null) {
          final sdp = RTCSessionDescription(answer['sdp'], answer['type']);
          await _pc!.setRemoteDescription(sdp);
        }
      }
    });

    // Listen for callee ICE candidates
    _calleeCandidatesSub = _roomRef!
        .collection('calleeCandidates')
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docChanges) {
            if (doc.type == DocumentChangeType.added) {
              final data = doc.doc.data();
              if (data == null) continue;
              final candidate = RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );
              await _pc!.addCandidate(candidate);
            }
          }
        });

    return _roomRef!.id;
  }

  Future<String> createOrReuseRoom({String? roomId}) async {
    _isCaller = true;
    await _createPc();
    await _attachLocalStream();

    if (roomId != null && roomId.isNotEmpty) {
      _roomRef = _db.collection('rooms').doc(roomId);
      final exists = await _roomRef!.get();
      if (!exists.exists) {
        await _roomRef!.set({'createdAt': FieldValue.serverTimestamp()});
      }
      // Clear previous candidates
      final callerQ = await _roomRef!.collection('callerCandidates').get();
      for (final d in callerQ.docs) {
        await d.reference.delete();
      }
      final calleeQ = await _roomRef!.collection('calleeCandidates').get();
      for (final d in calleeQ.docs) {
        await d.reference.delete();
      }
      // Remove previous answer
      await _roomRef!.set({
        'answer': FieldValue.delete(),
      }, SetOptions(merge: true));
    } else {
      _roomRef = _db.collection('rooms').doc();
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await _roomRef!.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Listen for remote answer
    _roomSub = _roomRef!.snapshots().listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer != null) {
        final current = await _pc!.getRemoteDescription();
        if (current == null) {
          final sdp = RTCSessionDescription(answer['sdp'], answer['type']);
          await _pc!.setRemoteDescription(sdp);
        }
      }
    });

    // Listen for callee ICE candidates
    _calleeCandidatesSub = _roomRef!
        .collection('calleeCandidates')
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docChanges) {
            if (doc.type == DocumentChangeType.added) {
              final data = doc.doc.data();
              if (data == null) continue;
              final candidate = RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );
              await _pc!.addCandidate(candidate);
            }
          }
        });

    return _roomRef!.id;
  }

  void sendDetections(List<Map<String, dynamic>> detectionsNorm) {
    if (_detectionsDc == null) return;
    final payload = jsonEncode({'type': 'detections', 'data': detectionsNorm});
    _detectionsDc!.send(RTCDataChannelMessage(payload));
  }

  Future<void> joinRoom(String roomId) async {
    _isCaller = false;
    final room = _db.collection('rooms').doc(roomId);
    final snap = await room.get();
    final data = snap.data();
    if (data == null) {
      throw Exception('Room not found');
    }

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    _pc = await createPeerConnection(configuration);

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        remoteRenderer.srcObject = remoteStream;
      }
    };

    _pc!.onDataChannel = (RTCDataChannel channel) {
      if (channel.label == 'detections') {
        _detectionsDc = channel;
        channel.onMessage = (RTCDataChannelMessage msg) {
          try {
            final obj = jsonDecode(msg.text);
            if (obj is Map && obj['type'] == 'detections') {
              final d = obj['data'];
              if (d is List) {
                final list = d
                    .map<Map<String, dynamic>>(
                      (e) => Map<String, dynamic>.from(e),
                    )
                    .toList();
                onDetections?.call(list);
              }
            }
          } catch (_) {}
        };
      }
    };

    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    _roomRef = room;

    _pc!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (_roomRef == null) return;
      await _roomRef!.collection('calleeCandidates').add(candidate.toMap());
    };

    final offer = data['offer'];
    final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
    _lastOfferSdp = offer['sdp'] as String?;
    await _pc!.setRemoteDescription(remoteDesc);

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _roomRef!.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    });

    _roomSub = _roomRef!.collection('callerCandidates').snapshots().listen((
      snapshot,
    ) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final m = change.doc.data();
          if (m == null) continue;
          final cand = RTCIceCandidate(
            m['candidate'],
            m['sdpMid'],
            m['sdpMLineIndex'],
          );
          await _pc!.addCandidate(cand);
        }
      }
    });

    // Watch for new offers in a persistent room and renegotiate automatically
    _offerSub = _roomRef!.snapshots().listen((doc) async {
      final d = doc.data();
      if (d == null) return;
      final newOffer = d['offer'];
      if (newOffer == null) return;
      final sdp = newOffer['sdp'] as String?;
      if (sdp == null || sdp == _lastOfferSdp) return;
      _lastOfferSdp = sdp;
      final desc = RTCSessionDescription(newOffer['sdp'], newOffer['type']);
      await _pc!.setRemoteDescription(desc);
      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      await _roomRef!.set({
        'answer': {'type': ans.type, 'sdp': ans.sdp},
      }, SetOptions(merge: true));
    });
  }

  Future<void> hangUp() async {
    try {
      await _calleeCandidatesSub?.cancel();
      await _roomSub?.cancel();
      await _offerSub?.cancel();
      if (_isCaller && !persistRoom) {
        await _roomRef?.collection('callerCandidates').get().then((q) async {
          for (final d in q.docs) {
            await d.reference.delete();
          }
        });
        await _roomRef?.collection('calleeCandidates').get().then((q) async {
          for (final d in q.docs) {
            await d.reference.delete();
          }
        });
        await _roomRef?.delete();
      }
    } catch (_) {}
    try {
      await _detectionsDc?.close();
      await _pc?.close();
    } catch (_) {}
    try {
      for (final t in localStream?.getTracks() ?? []) {
        await t.stop();
      }
      await localStream?.dispose();
    } catch (_) {}
    try {
      remoteRenderer.srcObject = null;
      localRenderer.srcObject = null;
    } catch (_) {}
  }
}
