import 'dart:async';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:draggable_float_widget/draggable_float_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../consts.dart';
import '../common.dart';
import '../common/widgets/overlay.dart';
import '../main.dart';
import 'model.dart';

class MessageBody {
  ChatUser chatUser;
  List<ChatMessage> chatMessages;
  MessageBody(this.chatUser, this.chatMessages);

  void insert(ChatMessage cm) {
    chatMessages.insert(0, cm);
  }

  void clear() {
    chatMessages.clear();
  }
}

class ChatModel with ChangeNotifier {
  static final clientModeID = -1;

  OverlayEntry? chatIconOverlayEntry;
  OverlayEntry? chatWindowOverlayEntry;

  bool isConnManager = false;

  RxBool isWindowFocus = true.obs;
  BlockableOverlayState? _blockableOverlayState;
  final Rx<VoiceCallStatus> _voiceCallStatus = Rx(VoiceCallStatus.notStarted);

  Rx<VoiceCallStatus> get voiceCallStatus => _voiceCallStatus;

  TextEditingController textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  final ChatUser me = ChatUser(
    id: "",
    firstName: translate("Me"),
  );

  late final Map<int, MessageBody> _messages = {}..[clientModeID] =
      MessageBody(me, []);

  var _currentID = clientModeID;
  late bool _isShowCMChatPage = false;

  Map<int, MessageBody> get messages => _messages;

  int get currentID => _currentID;

  bool get isShowCMChatPage => _isShowCMChatPage;

  void setOverlayState(BlockableOverlayState blockableOverlayState) {
    _blockableOverlayState = blockableOverlayState;

    _blockableOverlayState!.addMiddleBlockedListener((v) {
      if (!v) {
        isWindowFocus.value = false;
        if (isWindowFocus.value) {
          isWindowFocus.toggle();
        }
      }
    });
  }

  final WeakReference<FFI> parent;

  late final SessionID sessionId;
  late FocusNode inputNode;

  ChatModel(this.parent) {
    sessionId = parent.target!.sessionId;
    inputNode = FocusNode(
      onKey: (_, event) {
        bool isShiftPressed = event.isKeyPressed(LogicalKeyboardKey.shiftLeft);
        bool isEnterPressed = event.isKeyPressed(LogicalKeyboardKey.enter);

        // don't send empty messages
        if (isEnterPressed && isEnterPressed && textController.text.isEmpty) {
          return KeyEventResult.handled;
        }

        if (isEnterPressed && !isShiftPressed) {
          final ChatMessage message = ChatMessage(
            text: textController.text,
            user: me,
            createdAt: DateTime.now(),
          );
          send(message);
          textController.clear();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
    );
  }

  ChatUser get currentUser {
    final user = messages[currentID]?.chatUser;
    if (user == null) {
      _currentID = clientModeID;
      return me;
    } else {
      return user;
    }
  }

  showChatIconOverlay({Offset offset = const Offset(200, 50)}) {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
    }
    // mobile check navigationBar
    final bar = navigationBarKey.currentWidget;
    if (bar != null) {
      if ((bar as BottomNavigationBar).currentIndex == 1) {
        return;
      }
    }

    final overlayState = _blockableOverlayState?.state;
    if (overlayState == null) return;

    final overlay = OverlayEntry(builder: (context) {
      return DraggableFloatWidget(
        config: DraggableFloatWidgetBaseConfig(
          initPositionYInTop: false,
          initPositionYMarginBorder: 100,
          borderTopContainTopBar: true,
        ),
        child: FloatingActionButton(
          onPressed: () {
            if (chatWindowOverlayEntry == null) {
              showChatWindowOverlay();
            } else {
              hideChatWindowOverlay();
            }
          },
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: SvgPicture.asset('assets/chat2.svg'),
        ),
      );
    });
    overlayState.insert(overlay);
    chatIconOverlayEntry = overlay;
  }

  hideChatIconOverlay() {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
      chatIconOverlayEntry = null;
    }
  }

  showChatWindowOverlay({Offset? chatInitPos}) {
    if (chatWindowOverlayEntry != null) return;
    isWindowFocus.value = true;
    _blockableOverlayState?.setMiddleBlocked(true);

    final overlayState = _blockableOverlayState?.state;
    if (overlayState == null) return;
    final overlay = OverlayEntry(builder: (context) {
      return Listener(
          onPointerDown: (_) {
            if (!isWindowFocus.value) {
              isWindowFocus.value = true;
              _blockableOverlayState?.setMiddleBlocked(true);
            }
          },
          child: DraggableChatWindow(
              position: chatInitPos ?? Offset(20, 80),
              width: 250,
              height: 350,
              chatModel: this));
    });
    overlayState.insert(overlay);
    chatWindowOverlayEntry = overlay;
    requestChatInputFocus();
  }

  hideChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) {
      _blockableOverlayState?.setMiddleBlocked(false);
      chatWindowOverlayEntry!.remove();
      chatWindowOverlayEntry = null;
      return;
    }
  }

  _isChatOverlayHide() => ((!isDesktop && chatIconOverlayEntry == null) ||
      chatWindowOverlayEntry == null);

  toggleChatOverlay({Offset? chatInitPos}) {
    if (_isChatOverlayHide()) {
      gFFI.invokeMethod("enable_soft_keyboard", true);
      if (!isDesktop) {
        showChatIconOverlay();
      }
      showChatWindowOverlay(chatInitPos: chatInitPos);
    } else {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  hideChatOverlay() {
    if (!_isChatOverlayHide()) {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  showChatPage(int id) async {
    if (isConnManager) {
      if (!_isShowCMChatPage) {
        await toggleCMChatPage(id);
      }
    } else {
      if (_isChatOverlayHide()) {
        await toggleChatOverlay();
      }
    }
  }

  toggleCMChatPage(int id) async {
    if (gFFI.chatModel.currentID != id) {
      gFFI.chatModel.changeCurrentID(id);
    }
    if (_isShowCMChatPage) {
      _isShowCMChatPage = !_isShowCMChatPage;
      notifyListeners();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    } else {
      requestChatInputFocus();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeOpenChat, Alignment.topRight);
      _isShowCMChatPage = !_isShowCMChatPage;
      notifyListeners();
    }
  }

  changeCurrentID(int id) {
    if (_messages.containsKey(id)) {
      _currentID = id;
      notifyListeners();
    } else {
      final client = parent.target?.serverModel.clients
          .firstWhere((client) => client.id == id);
      if (client == null) {
        return debugPrint(
            "Failed to changeCurrentID,remote user doesn't exist");
      }
      final chatUser = ChatUser(
        id: client.peerId,
        firstName: client.name,
      );
      _messages[id] = MessageBody(chatUser, []);
      _currentID = id;
      notifyListeners();
    }
  }

  receive(int id, String text) async {
    final session = parent.target;
    if (session == null) {
      debugPrint("Failed to receive msg, session state is null");
      return;
    }
    if (text.isEmpty) return;
    if (desktopType == DesktopType.cm) {
      await showCmWindow();
    }

    // mobile: first message show overlay icon
    if (!isDesktop && chatIconOverlayEntry == null) {
      showChatIconOverlay();
    }
    // show chat page
    await showChatPage(id);

    int toId = currentID;

    late final ChatUser chatUser;
    if (id == clientModeID) {
      chatUser = ChatUser(
        firstName: session.ffiModel.pi.username,
        id: session.id,
      );
      toId = id;
    } else {
      final client =
          session.serverModel.clients.firstWhere((client) => client.id == id);
      if (isDesktop) {
        window_on_top(null);
        // disable auto jumpTo other tab when hasFocus, and mark unread message
        final currentSelectedTab =
            session.serverModel.tabController.state.value.selectedTabInfo;
        if (currentSelectedTab.key != id.toString() && inputNode.hasFocus) {
          client.unreadChatMessageCount.value += 1;
        } else {
          parent.target?.serverModel.jumpTo(id);
          toId = id;
        }
      } else {
        toId = id;
      }
      chatUser = ChatUser(id: client.peerId, firstName: client.name);
    }

    if (!_messages.containsKey(id)) {
      _messages[id] = MessageBody(chatUser, []);
    }
    _messages[id]!.insert(
        ChatMessage(text: text, user: chatUser, createdAt: DateTime.now()));
    _currentID = toId;
    notifyListeners();
  }

  send(ChatMessage message) {
    String trimmedText = message.text.trim();
    if (trimmedText.isEmpty) {
      return;
    }
    message.text = trimmedText;
    _messages[_currentID]?.insert(message);
    if (_currentID == clientModeID && parent.target != null) {
      bind.sessionSendChat(sessionId: sessionId, text: message.text);
    } else {
      bind.cmSendChat(connId: _currentID, msg: message.text);
    }

    notifyListeners();
    inputNode.requestFocus();
  }

  close() {
    hideChatIconOverlay();
    hideChatWindowOverlay();
    notifyListeners();
  }

  resetClientMode() {
    _messages[clientModeID]?.clear();
  }

  void requestChatInputFocus() {
    Timer(Duration(milliseconds: 100), () {
      if (inputNode.hasListeners && inputNode.canRequestFocus) {
        inputNode.requestFocus();
      }
    });
  }

  void onVoiceCallWaiting() {
    _voiceCallStatus.value = VoiceCallStatus.waitingForResponse;
  }

  void onVoiceCallStarted() {
    _voiceCallStatus.value = VoiceCallStatus.connected;
  }

  void onVoiceCallClosed(String reason) {
    _voiceCallStatus.value = VoiceCallStatus.notStarted;
  }

  void onVoiceCallIncoming() {
    if (isConnManager) {
      _voiceCallStatus.value = VoiceCallStatus.incoming;
    }
  }

  void closeVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: sessionId);
  }
}

enum VoiceCallStatus {
  notStarted,
  waitingForResponse,
  connected,
  // Connection manager only.
  incoming
}
