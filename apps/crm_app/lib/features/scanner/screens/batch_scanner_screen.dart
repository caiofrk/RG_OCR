import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../models/document_data.dart';
import '../providers/scanner_provider.dart';

class BatchItem {
  final PlatformFile file;
  String status; // pending, processing, done, error
  ScannedDocumentData? result;
  String? errorMessage;

  BatchItem({
    required this.file,
    this.status = 'pending',
    this.result,
    this.errorMessage,
  });
}

class BatchScannerScreen extends ConsumerStatefulWidget {
  const BatchScannerScreen({super.key});

  @override
  ConsumerState<BatchScannerScreen> createState() => _BatchScannerScreenState();
}

class _BatchScannerScreenState extends ConsumerState<BatchScannerScreen> {
  final List<BatchItem> _queue = [];
  bool _isBatchProcessing = false;

  Future<void> _pickMultipleFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      // ignore: deprecated_member_use
      allowMultiple: true,
    );

    if (picked.isNotEmpty) {
      setState(() {
        for (final f in picked) {
          _queue.add(BatchItem(file: f));
        }
      });
    }
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) return;

    setState(() => _isBatchProcessing = true);
    final ocrClient = ref.read(ocrClientServiceProvider);

    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].status == 'done') continue;

      setState(() => _queue[i].status = 'processing');

      try {
        final bytes = await _queue[i].file.readAsBytes();
        final result = await ocrClient.processDocumentBytes(
          bytes: bytes,
          filename: _queue[i].file.name,
          docType: 'auto',
        );

        if (result.documentData != null) {
          setState(() {
            _queue[i].status = 'done';
            _queue[i].result = result.documentData;
          });
          ref.read(scanHistoryProvider.notifier).add(result.documentData!);
        } else {
          setState(() {
            _queue[i].status = 'error';
            _queue[i].errorMessage = result.message;
          });
        }
      } catch (e) {
        setState(() {
          _queue[i].status = 'error';
          _queue[i].errorMessage = e.toString();
        });
      }
    }

    setState(() => _isBatchProcessing = false);
  }

  void _exportAllAsCsv() {
    final completed = _queue.where((item) => item.result != null).map((item) => item.result!).toList();
    if (completed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum documento processado com sucesso ainda.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(ScannedDocumentData.csvHeader());
    for (final doc in completed) {
      buffer.writeln(doc.toCsvRow());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${completed.length} documentos exportados para CSV (copiado para a área de transferência)!'),
        backgroundColor: AppTheme.primaryEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Processamento em Lote (Batch OCR)'),
        actions: [
          if (_queue.isNotEmpty) ...[
            TextButton.icon(
              onPressed: _exportAllAsCsv,
              icon: const Icon(Icons.file_download, color: AppTheme.primaryEmerald),
              label: const Text('Exportar CSV', style: TextStyle(color: AppTheme.primaryEmerald)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.accentRose),
              tooltip: 'Limpar Fila',
              onPressed: () => setState(() => _queue.clear()),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: Container(
        color: AppTheme.slate900,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top action bar
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                ElevatedButton.icon(
                  onPressed: _isBatchProcessing ? null : _pickMultipleFiles,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Adicionar Arquivos'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slate800),
                ),
                ElevatedButton.icon(
                  onPressed: (_queue.isEmpty || _isBatchProcessing) ? null : _processQueue,
                  icon: _isBatchProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow),
                  label: Text(_isBatchProcessing ? 'Processando Fila...' : 'Iniciar Processamento (${_queue.length})'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Queue List
            Expanded(
              child: _queue.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: Colors.grey.shade700),
                          const SizedBox(height: 12),
                          const Text('A fila de processamento está vazia.', style: TextStyle(color: Colors.grey, fontSize: 15)),
                          const SizedBox(height: 4),
                          const Text('Clique em "Adicionar Arquivos" para selecionar múltiplos documentos.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _queue.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final item = _queue[idx];
                        final fileSize = (item.file.lengthSync() ?? 0) / 1024;

                        return Card(
                          color: AppTheme.slate800,
                          child: ListTile(
                            leading: Icon(
                              item.status == 'done'
                                  ? Icons.check_circle
                                  : (item.status == 'processing' ? Icons.sync : Icons.insert_drive_file),
                              color: item.status == 'done'
                                  ? AppTheme.primaryEmerald
                                  : (item.status == 'processing' ? AppTheme.accentSky : Colors.grey),
                            ),
                            title: Text(
                              item.file.name, 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: item.result != null
                                ? Text('${item.result!.documentType.toUpperCase()}: ${item.result!.fullName ?? "Sem nome"} • CPF: ${item.result!.cpf ?? "N/A"}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey))
                                : Text('Tamanho: ${fileSize.toStringAsFixed(1)} KB',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: _buildStatusChip(item.status),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = Colors.grey;
    String label = 'Aguardando';

    if (status == 'processing') {
      color = AppTheme.accentSky;
      label = 'Extraindo...';
    } else if (status == 'done') {
      color = AppTheme.primaryEmerald;
      label = 'Concluído';
    } else if (status == 'error') {
      color = AppTheme.accentRose;
      label = 'Falha';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
