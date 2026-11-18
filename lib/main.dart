import 'package:flutter/material.dart';

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

/// 대화 한 줄. 서버 없이 화면만 만들기 위한 최소 모델.
class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  // 누가 보낸 말인지 이름으로 드러나게
  const ChatMessage.user(this.text) : isUser = true;
  const ChatMessage.bot(this.text) : isUser = false;

  final String text;
  final bool isUser;
}

/// 실습 4 — 서버가 돌려준 HTTP 상태 코드를 담는 오류
class AiException implements Exception {
  const AiException(this.status);

  final int status; // 401, 429, 500 ...
}

/// AI 호출 담당. 아직 서버(프록시)가 없어서 1.5초 뒤 가짜 답을 돌려준다.
/// 나중에 실제 서버를 붙일 때는 chat() 안만 바꾸면 된다.
///
/// 실습 4 시험용 — 메시지에 아래 글자를 넣으면 그 오류를 흉내 낸다.
/// 처음 한 번만 실패하고, 다시 시도하면 성공한다.
///   /401  /429  /500  /timeout
class AiClient {
  final _failedOnce = <String>{}; // 이미 한 번 실패한 메시지

  Future<String> chat(String text) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final firstTry = _failedOnce.add(text); // 처음이면 true
    if (firstTry) {
      if (text.contains('/timeout')) {
        await Future.delayed(const Duration(seconds: 10)); // 응답 없음
      }
      for (final code in [401, 429, 500]) {
        if (text.contains('/$code')) throw AiException(code);
      }
    }
    return '"$text"에 대한 답변이에요.';
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 실습용 가짜 대화 — API를 붙이기 전까지 이 목록으로 화면을 만든다.
  final List<ChatMessage> _messages = [
    ChatMessage(text: '오늘 뭐 배워?', isUser: true),
    ChatMessage(text: 'AI 챗봇에 움직이는 응답을 붙입니다.', isUser: false),
    ChatMessage(text: '타이핑 점은 왜 필요해요?', isUser: true),
    ChatMessage(text: '응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다.', isUser: false),
  ];

  // TODO 3 — 입력창의 글자를 읽고 지우는 리모컨
  final _controller = TextEditingController();

  final _ai = AiClient();
  bool _sending = false; // 보내는 중 → 입력 잠금
  bool _typing = false; // AI가 답을 쓰는 중 → 점 3개

  // 실습 4
  String? _error; // 화면에 남길 오류 문구 (null이면 오류 없음)
  String? _lastText; // 다시 시도할 마지막 메시지

  @override
  void dispose() {
    // 화면이 사라질 때 컨트롤러도 정리 (메모리 누수 방지)
    _controller.dispose();
    super.dispose();
  }

  /// 내 메시지를 추가하고 AI에게 묻는다
  Future<void> _send() async {
    final text = _controller.text.trim();
    // 빈 칸이거나 이미 보내는 중이면 무시 → 연타해도 한 번만 전송
    if (text.isEmpty || _sending) return;
    _controller.clear();

    setState(() => _messages.add(ChatMessage.user(text)));
    await _ask(text);
  }

  /// 실습 4 — 3. 다시 시도는 마지막 메시지를 다시 보낸다
  /// (내 말풍선은 이미 있으니 또 추가하지 않는다)
  Future<void> _retry() async {
    final text = _lastText;
    if (text == null || _sending) return;
    await _ask(text);
  }

  /// AI에게 묻고, 성공하면 AI 말풍선, 실패하면 오류 문구를 남긴다
  Future<void> _ask(String text) async {
    _lastText = text;
    setState(() {
      _sending = true;
      _typing = true;
      _error = null; // 새로 시도하니 이전 오류는 지운다
    });

    try {
      // timeout: 5초 안에 답이 없으면 TimeoutException
      final answer =
          await _ai.chat(text).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage.bot(answer)));
    } on AiException catch (e) {
      // 서버가 상태 코드로 실패를 알린 경우
      if (mounted) setState(() => _error = _errorMessage(e.status));
    } catch (_) {
      // 시간 초과, 네트워크 끊김 등 — 상태 코드가 없는 경우
      if (mounted) setState(() => _error = _errorMessage(null));
    } finally {
      // 성공이든 실패든 잠금 해제 → 오류 뒤에도 입력이 된다
      if (mounted) {
        setState(() {
          _sending = false;
          _typing = false;
        });
      }
    }
  }

  /// 실습 4 — 1. 401, 429, 500, timeout을 사용자가 할 일이 보이는 한 문장으로
  String _errorMessage(int? status) => switch (status) {
        401 => '키/권한을 확인해 주세요',
        429 => '잠시 후 다시 시도해 주세요',
        500 => '응답을 받지 못했습니다',
        _ => '네트워크를 확인해 주세요',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // TODO 5 — 키보드가 입력창을 가리지 않게
      // 키보드가 올라오면 body 높이를 그만큼 줄인다 → 입력창이 키보드 위로 밀려 올라감
      // (기본값이 true지만, 의도를 드러내려고 명시)
      resizeToAvoidBottomInset: true,
      // body는 아래 SafeArea로 감싸 홈 인디케이터와 노치를 피한다.
      appBar: AppBar(title: const Text('AI Chat — 실습 1')),
      body: SafeArea(
        child: Column(
          children: [
            // ─────────────────────────────────────────────────────────
            // ✅ 할 일 1 — 완료된 부분
            //    ListView.builder + reverse: true
            //    · reverse:true면 index 0이 화면 맨 아래(최신)다.
            //    · 그래서 _messages[length - 1 - i]로 거꾸로 꺼낸다.
            // ─────────────────────────────────────────────────────────
            Expanded(
              // TODO 4 — 목록 위에 빈 상태 문구를 겹쳐 놓는다
              child: Stack(
                children: [
                  ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // AI가 답을 쓰는 중이면 맨 아래(index 0)에 점 3개 한 칸 추가
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_typing) {
                        if (index == 0) return const TypingDots();
                        index -= 1; // 점 3개 자리만큼 한 칸 밀기
                      }
                      final message =
                          _messages[_messages.length - 1 - index];
                      return _Bubble(message: message);
                    },
                  ),
                  // 목록이 비었을 때만 가운데에 보인다
                  if (_messages.isEmpty && !_typing)
                    Center(
                      child: Text(
                        '무엇이든 물어보세요',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ─────────────────────────────────────────────────────────
            // TODO 4 — 빈 상태
            // TIP: ListView를 Stack으로 감싸고, 목록이 비었을 때만
            //      Center(child: Text('무엇이든 물어보세요'))를 위에 띄운다.
            //      지금은 목록에 가짜 대화가 있어 빈 상태가 보이지 않는다.
            //      _messages를 비우고 확인해 보자.
            // ─────────────────────────────────────────────────────────

            // ─────────────────────────────────────────────────────────
            // TODO 3 — 입력창 (TextField + 전송 버튼)
            // TIP:
            //  · final _controller = TextEditingController(); 를 State에 둔다.
            //  · Row(children: [Expanded(TextField(...)), IconButton.filled(...)])
            //  · TextField(textInputAction: TextInputAction.send,
            //             onSubmitted: (_) => _send())
            //  · 보낼 때 _controller.clear() 하고 setState로 목록에 추가한다.
            //  · dispose()에서 _controller.dispose()를 잊지 않는다.
            // ─────────────────────────────────────────────────────────
            // 실습 4 — 4. 오류 말풍선이 부드럽게 나타나고 사라진다
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _error == null
                  ? const SizedBox.shrink()
                  : _ErrorBubble(
                      key: ValueKey(_error),
                      message: _error!,
                      onRetry: _retry,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending, // 보내는 중에는 입력 잠금
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '메시지를 입력하세요',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    // null이면 버튼이 회색으로 비활성
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────────────────────────────────────────────────
/// TODO 2 — 말풍선 2종 (사용자 오른쪽 / AI 왼쪽)
///
/// 지금은 글자만 보이는 상자다. 다음을 채워 넣자.
///
/// TIP:
///  · Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft)
///  · Container(
///      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
///      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
///      constraints: BoxConstraints(maxWidth: 420),
///      decoration: BoxDecoration(
///        color: isUser ? colorScheme.primaryContainer
///                      : colorScheme.surfaceContainerHighest,
///        borderRadius: BorderRadius.circular(14),
///      ),
///    )
///  · 색은 Theme.of(context).colorScheme에서 꺼내면 다크 모드에서도 안전하다.
///  · 긴 글은 자동으로 줄바꿈된다. maxWidth만 잡아 주면 된다.
/// ───────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    // 사용자는 오른쪽, AI는 왼쪽
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // 긴 글은 이 폭에서 자동 줄바꿈
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// AI가 답을 쓰는 동안 왼쪽에 뜨는 점 3개
/// 점이 200ms 간격으로 하나씩 차례로 진해진다
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  // 0 → 1을 600ms 동안 반복하는 시계 (점 하나에 200ms × 3개)
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        // 시계 값이 바뀔 때마다 점만 다시 그린다
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            // 지금 진해질 점 번호: 0 → 1 → 2 → 0 ...
            final active = (_anim.value * 3).floor() % 3;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Opacity(
                    opacity: i == active ? 1.0 : 0.3,
                    child: CircleAvatar(
                      radius: 4,
                      backgroundColor: colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// 실습 4 — 2. 오류 말풍선 + 다시 시도
class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 18, color: colorScheme.onErrorContainer),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
