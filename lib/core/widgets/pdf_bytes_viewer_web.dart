import 'dart:convert';
import 'dart:typed_data';

import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildPdfBytesViewer({
  required Uint8List bytes,
  required String fileName,
}) {
  return _WebPdfIframe(bytes: bytes, fileName: fileName);
}

class _WebPdfIframe extends StatefulWidget {
  const _WebPdfIframe({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  @override
  State<_WebPdfIframe> createState() => _WebPdfIframeState();
}

class _WebPdfIframeState extends State<_WebPdfIframe> {
  late final String _viewType;
  late final String _dataUrl;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdf-view-${widget.fileName.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _dataUrl = 'data:application/pdf;base64,${base64Encode(widget.bytes)}';
    _registerView();
  }

  void _registerView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.src = _dataUrl;
      iframe.style.border = 'none';
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
                  anchor.href = _dataUrl;
                  anchor.download = widget.fileName;
                  anchor.click();
                },
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Baixar'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: HtmlElementView(viewType: _viewType)),
      ],
    );
  }
}
