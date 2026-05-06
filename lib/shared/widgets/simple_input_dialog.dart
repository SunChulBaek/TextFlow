import 'package:flutter/material.dart';

class SimpleInputDialog extends StatefulWidget {
  const SimpleInputDialog({
    super.key,
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  State<SimpleInputDialog> createState() => _SimpleInputDialogState();
}

class _SimpleInputDialogState extends State<SimpleInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('추가'),
        ),
      ],
    );
  }
}

