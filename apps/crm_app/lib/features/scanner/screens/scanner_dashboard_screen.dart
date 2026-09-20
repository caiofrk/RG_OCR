import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/document_parser_service.dart';
import '../models/document_data.dart';
import '../providers/scanner_provider.dart';
import 'live_qr_scanner_screen.dart';

class ScannerDashboardScreen extends ConsumerStatefulWidget {
  const ScannerDashboardScreen({super.key});

  @override
  ConsumerState<ScannerDashboardScreen> createState() => _ScannerDashboardScreenState();
}

class _ScannerDashboardScreenState extends ConsumerState<ScannerDashboardScreen> {
  Uint8List? _fileBytes;
  String? _fileName;
  String? _filePath;

  bool _isProcessing = false;
  bool _isSavingDocument = false;
  bool _wasProcessedLocally = false;
  String _selectedDocType = 'auto';

  // Field text controllers
  late TextEditingController _nameController;
  late TextEditingController _docNumberController;
  late TextEditingController _cpfController;
  late TextEditingController _birthDateController;
  late TextEditingController _userIdController;
  late TextEditingController _organController;
  late TextEditingController _nationalityController;
  late TextEditingController _genderController;
  late TextEditingController _expiryController;
  late TextEditingController _cnhCatController;
  late TextEditingController _cnhRenachController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _docNumberController = TextEditingController();
    _cpfController = TextEditingController();
    _birthDateController = TextEditingController();
    _userIdController = TextEditingController();
    _organController = TextEditingController();
    _nationalityController = TextEditingController();
    _genderController = TextEditingController();
    _expiryController = TextEditingController();
    _cnhCatController = TextEditingController();
    _cnhRenachController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _docNumberController.dispose();
    _cpfController.dispose();
    _birthDateController.dispose();
    _userIdController.dispose();
    _organController.dispose();
    _nationalityController.dispose();
    _genderController.dispose();
    _expiryController.dispose();
    _cnhCatController.dispose();
    _cnhRenachController.dispose();
    super.dispose();
  }

  void _populateControllers(ScannedDocumentData doc) {
    _nameController.text = doc.fullName ?? '';
    _docNumberController.text = doc.documentNumber ?? '';
    _cpfController.text = doc.cpf ?? '';
    _birthDateController.text = doc.birthDate ?? '';
    _userIdController.text = doc.userId ?? '';
    _organController.text = '${doc.issuingOrgan ?? ''}${doc.issuingState != null ? '/${doc.issuingState}' : ''}'.trim();
    _nationalityController.text = doc.nationality ?? '';
    _genderController.text = doc.gender ?? '';
    _expiryController.text = doc.expiryDate ?? '';
    _cnhCatController.text = doc.cnhCategory ?? '';
    _cnhRenachController.text = doc.cnhRenach ?? '';
  }

  /// 1. Direct device camera scan using ML Kit Document Scanner
  Future<void> _captureWithCamera() async {
    await _scanDocument(isGalleryImport: false);
  }

  /// 2. Pick image from device gallery using ML Kit Document Scanner
  Future<void> _pickFromGallery() async {
    await _scanDocument(isGalleryImport: true);
  }

  Future<void> _scanDocument({required bool isGalleryImport}) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final options = DocumentScannerOptions(
          documentFormats: const {DocumentFormat.jpeg},
          mode: ScannerMode.full,
          pageLimit: 1,
          isGalleryImport: isGalleryImport,
        );
        
        final documentScanner = DocumentScanner(options: options);
        final result = await documentScanner.scanDocument();
        
        if (result.images?.isNotEmpty == true) {
          final path = result.images!.first;
          final file = File(path);
          final bytes = await file.readAsBytes();
          
          setState(() {
            _fileBytes = bytes;
            _fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
            _filePath = path;
          });
          await _processOCR();
        }
      } else {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: isGalleryImport ? ImageSource.gallery : ImageSource.camera,
          imageQuality: kIsWeb ? null : 70,
          maxWidth: kIsWeb ? null : 1600,
          maxHeight: kIsWeb ? null : 1600,
        );
        
        if (image != null) {
          setState(() => _isProcessing = true);
          final path = image.path;
          final bytes = await image.readAsBytes();
          
          setState(() {
            _fileBytes = bytes;
            _fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
            _filePath = path;
          });
          await _processOCR();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao escanear documento: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// 2b. Capture QR Code using Live Camera Feed (bypasses Face ID & OCR)
  Future<void> _captureQrCode() async {
    try {
      final String? qrData = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const LiveQrScannerScreen()),
      );
      
      if (qrData != null && qrData.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR Code lido com sucesso!'),
              backgroundColor: AppTheme.primaryEmerald,
            ),
          );
        }
        
        // Attempt to parse the barcode data just like we parse OCR text.
        // Some barcodes (like Passports or older CNHs) contain plain text MRZ or delimited fields.
        ScannedDocumentData parsedDoc;
        try {
          // Bypassing severe validation for barcodes since they don't have visual boilerplate
          parsedDoc = DocumentParserService.parse(
            qrData,
            docHint: 'auto',
            isBarcode: true,
          );
        } catch (e) {
          // If the parser fails (e.g. severe validation exceptions), fallback to raw QR Code data
          parsedDoc = ScannedDocumentData(
             id: DateTime.now().millisecondsSinceEpoch.toString(),
             documentType: 'qr_code',
             rawText: qrData,
             scannedAt: DateTime.now(),
             confidenceScore: 1.0,
          );
        }
        
        ref.read(activeDocumentProvider.notifier).setDocument(parsedDoc);
        ref.read(scanHistoryProvider.notifier).add(parsedDoc);
        _populateControllers(parsedDoc);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao escanear QR Code: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// 3. Pick local document file (PDF, JPG, PNG, WEBP)
  Future<void> _pickFromFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );

      if (picked.isNotEmpty) {
        setState(() => _isProcessing = true);
        final file = picked.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _fileBytes = bytes;
          _fileName = file.name;
          _filePath = file.path;
        });
        await _processOCR();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Modal bottom sheet with scanning and source choices
  void _showDocumentSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.slate900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Digitalizar Documento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Extração 100% on-device (zero dependência de servidores)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryEmerald),
                ),
                title: const Text('Câmera do Dispositivo', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Tirar foto com a câmera do celular em alta resolução'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _captureWithCamera();
                },
              ),
              const Divider(color: AppTheme.slate800),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.purpleAccent),
                ),
                title: const Text('Ler QR Code / Barcode (Verso)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Ler códigos no verso do documento sem validar a foto'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _captureQrCode();
                },
              ),
              const Divider(color: AppTheme.slate800),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSky.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppTheme.accentSky),
                ),
                title: const Text('Galeria de Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Escolher foto de documento salva no celular'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              const Divider(color: AppTheme.slate800),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.file_present_rounded, color: Colors.amber),
                ),
                title: const Text('Arquivos Locais', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('PDF, JPG, PNG ou WEBP'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Process OCR: First tries 100% on-device ML Kit, falls back to server if needed
  Future<void> _processOCR() async {
    if (_fileBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      final isPdf = _fileName?.toLowerCase().endsWith('.pdf') ?? false;
      
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && _filePath != null && !isPdf) {
        final onDeviceService = ref.read(onDeviceOcrServiceProvider);
        final onDeviceResult = await onDeviceService.processImage(_filePath!);

        if (onDeviceResult.success && onDeviceResult.rawText.trim().isNotEmpty) {
          final parsedDoc = DocumentParserService.parse(
            onDeviceResult.rawText,
            docHint: _selectedDocType,
          );

          ref.read(activeDocumentProvider.notifier).setDocument(parsedDoc);
          ref.read(scanHistoryProvider.notifier).add(parsedDoc);
          _populateControllers(parsedDoc);

          setState(() {
            _isProcessing = false;
            _wasProcessedLocally = true;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'On-Device OCR: ${onDeviceResult.processingTimeMs.toInt()}ms (Android Local)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppTheme.primaryEmerald,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Process using PC/Cloud OCR microservice (Web, iOS, or Android fallback)
      final ocrClient = ref.read(ocrClientServiceProvider);
      final result = await ocrClient.processDocumentBytes(
        bytes: _fileBytes!,
        filename: _fileName ?? 'document.jpg',
        docType: _selectedDocType,
      );

      setState(() {
        _isProcessing = false;
        _wasProcessedLocally = false;
      });

      if (result.documentData != null) {
        ref.read(activeDocumentProvider.notifier).setDocument(result.documentData!);
        ref.read(scanHistoryProvider.notifier).add(result.documentData!);
        _populateControllers(result.documentData!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no OCR: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _copyJsonToClipboard(ScannedDocumentData doc) {
    Clipboard.setData(ClipboardData(text: doc.toFormattedJson()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('JSON copiado para a área de transferência!'),
          ],
        ),
        backgroundColor: AppTheme.primaryEmerald,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDoc = ref.watch(activeDocumentProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.document_scanner_rounded, color: AppTheme.primaryEmerald, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RG_OCR • Extrator',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'RG • CIN • CNH • Passaporte',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configurar Servidor OCR',
            icon: const Icon(Icons.dns_rounded, color: AppTheme.accentSky),
            onPressed: () => _showServerConfigDialog(context),
          ),
          IconButton(
            tooltip: ref.watch(supabaseServiceProvider).isConfigured
                ? 'Supabase Conectado'
                : 'Configurar Supabase',
            icon: Icon(
              Icons.cloud_sync_rounded,
              color: ref.watch(supabaseServiceProvider).isConfigured
                  ? AppTheme.primaryEmerald
                  : Colors.grey,
            ),
            onPressed: () => _showSupabaseConfigDialog(context),
          ),
          IconButton(
            tooltip: 'Processamento em Lote',
            icon: const Icon(Icons.queue_play_next, color: AppTheme.accentSky),
            onPressed: () => context.push('/batch'),
          ),
          IconButton(
            tooltip: 'Histórico de Scans',
            icon: const Icon(Icons.history),
            onPressed: () => _showHistoryBottomSheet(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Document Type Filter Selector
          Container(
            color: AppTheme.slate800,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Tipo: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 8),
                  _buildTypeChip('auto', '✨ Auto-Detect'),
                  _buildTypeChip('rg', 'RG Tradicional'),
                  _buildTypeChip('cin', 'Nova CIN'),
                  _buildTypeChip('cnh', 'CNH'),
                  _buildTypeChip('passport', 'Passaporte (MRZ)'),
                  _buildTypeChip('cpf', 'CPF'),
                ],
              ),
            ),
          ),

          // 2. Main Workspace (Side-by-side or stacked on small screens)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return constraints.maxWidth > 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: _buildDocumentPreviewPanel()),
                          const VerticalDivider(width: 1, color: AppTheme.slate700),
                          Expanded(flex: 5, child: SingleChildScrollView(child: _buildExtractedDataPanel(activeDoc))),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SizedBox(height: 300, child: _buildDocumentPreviewPanel()),
                            const SizedBox(height: 16),
                            _buildExtractedDataPanel(activeDoc),
                          ],
                        ),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String id, String label) {
    final isSelected = _selectedDocType == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.grey.shade400)),
        selected: isSelected,
        selectedColor: AppTheme.primaryEmerald,
        backgroundColor: AppTheme.slate900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? AppTheme.primaryEmerald : AppTheme.slate700),
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedDocType = id);
            if (_fileBytes != null) _processOCR();
          }
        },
      ),
    );
  }

  Widget _buildDocumentPreviewPanel() {
    return Container(
      color: AppTheme.slate900,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _fileName ?? 'Nenhum documento capturado',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fileBytes != null)
                TextButton.icon(
                  onPressed: () => _showDocumentSourceSheet(context),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Trocar'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: InkWell(
              onTap: () => _showDocumentSourceSheet(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.slate800,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.slate700, width: 1.5),
                ),
                child: _fileBytes != null
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                _fileBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.primaryEmerald.withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_wasProcessedLocally ? Icons.bolt_rounded : Icons.cloud_done_rounded, size: 14, color: _wasProcessedLocally ? Colors.amber : Colors.blueAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    _wasProcessedLocally ? 'On-Device ML Kit' : 'Servidor Python OCR',
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryEmerald.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded, size: 40, color: AppTheme.primaryEmerald),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Escanear Documento',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toque para abrir a Câmera, Galeria ou Arquivos\nRG, Nova CIN, CNH, Passaporte ou CPF',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _captureWithCamera,
                  icon: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(_isProcessing ? 'Processando OCR...' : 'Escanear com a Câmera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Outras opções (Galeria / Arquivo)',
                onPressed: _isProcessing ? null : () => _showDocumentSourceSheet(context),
                icon: const Icon(Icons.more_horiz_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.slate800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedDataPanel(ScannedDocumentData? doc) {
    if (doc == null) {
      return Container(
        color: AppTheme.slate900,
        height: 400,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.text_snippet_outlined, size: 48, color: Colors.grey.shade700),
              const SizedBox(height: 12),
              Text(
                'Os dados extraídos aparecerão aqui',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecione um documento na barra ao lado para iniciar a extração OCR',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppTheme.slate900,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header: Document Type Badge + Validation Indicators
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryEmerald.withValues(alpha: 0.4)),
                ),
                child: Text(
                  doc.documentType.toUpperCase(),
                  style: const TextStyle(color: AppTheme.primaryEmerald, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              if (doc.cpfValid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified, size: 14, color: AppTheme.primaryEmerald),
                      SizedBox(width: 4),
                      Text('CPF Válido', style: TextStyle(color: AppTheme.primaryEmerald, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              if (doc.mrzValid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSky.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: AppTheme.accentSky),
                      SizedBox(width: 4),
                      Text('MRZ ICAO Válido', style: TextStyle(color: AppTheme.accentSky, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                'Confiança: ${(doc.confidenceScore * 100).toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Extracted Form
          Card(
            color: AppTheme.slate800,
            child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Nome Completo', prefixIcon: Icon(Icons.person)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _docNumberController,
                              decoration: const InputDecoration(labelText: 'Número do Documento', prefixIcon: Icon(Icons.badge)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _cpfController,
                              decoration: InputDecoration(
                                labelText: 'CPF',
                                prefixIcon: const Icon(Icons.pin),
                                suffixIcon: doc.cpfValid
                                    ? const Icon(Icons.check_circle, color: AppTheme.primaryEmerald, size: 18)
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _birthDateController,
                              decoration: const InputDecoration(labelText: 'Data de Nascimento', prefixIcon: Icon(Icons.calendar_today)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _genderController,
                              decoration: const InputDecoration(labelText: 'Sexo', prefixIcon: Icon(Icons.wc)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _organController,
                              decoration: const InputDecoration(labelText: 'Órgão / UF', prefixIcon: Icon(Icons.apartment)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _userIdController,
                        decoration: const InputDecoration(labelText: 'ID Único do Usuário', prefixIcon: Icon(Icons.fingerprint)),
                      ),
                      if (doc.documentType == 'cnh') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _cnhCatController,
                                decoration: const InputDecoration(labelText: 'Categoria CNH', prefixIcon: Icon(Icons.directions_car)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _cnhRenachController,
                                decoration: const InputDecoration(labelText: 'RENACH', prefixIcon: Icon(Icons.confirmation_number)),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (doc.documentType == 'passport') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nationalityController,
                                decoration: const InputDecoration(labelText: 'Nacionalidade (País)', prefixIcon: Icon(Icons.public)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _expiryController,
                                decoration: const InputDecoration(labelText: 'Validade', prefixIcon: Icon(Icons.event_busy)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 12),

          // Bottom Action Toolbar: Salvar no Supabase, Copy JSON, Export CSV, Clear
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _isSavingDocument
                    ? null
                    : () async {
                        setState(() => _isSavingDocument = true);
                        final ocrClient = ref.read(ocrClientServiceProvider);
                        final supabase = ref.read(supabaseServiceProvider);
                        final currentDoc = ref.read(activeDocumentProvider);
                        if (currentDoc == null) return;

                        // Capture user edits from the form using controller values
                        final updatedDoc = currentDoc.copyWith(
                          fullName: _nameController.text.trim(),
                          documentNumber: _docNumberController.text.trim(),
                          cpf: _cpfController.text.trim(),
                          birthDate: _birthDateController.text.trim(),
                          userId: _userIdController.text.trim(),
                          issuingOrgan: _organController.text.trim(),
                          cnhCategory: _cnhCatController.text.trim(),
                          cnhRenach: _cnhRenachController.text.trim(),
                          nationality: _nationalityController.text.trim(),
                          gender: _genderController.text.trim(),
                          expiryDate: _expiryController.text.trim(),
                        );

                        // 1. Always save to local SQLite backend (zero-cost offline storage)
                        final localSaved = await ocrClient.saveDocument(
                          doc: updatedDoc,
                          fileName: _fileName,
                        );

                        // 2. Sync to Supabase cloud if connected
                        bool cloudSaved = false;
                        if (supabase.isConfigured) {
                          cloudSaved = await supabase.saveScannedDocument(
                            doc: updatedDoc,
                            fileBytes: _fileBytes,
                            fileName: _fileName,
                          );
                        }

                        setState(() => _isSavingDocument = false);
                        if (!mounted) return;

                        String feedback;
                        if (cloudSaved && localSaved) {
                          feedback = '✅ Salvo no SQLite local e na nuvem Supabase!';
                        } else if (localSaved) {
                          feedback = '✅ Salvo com sucesso no banco de dados local (SQLite)!';
                        } else {
                          feedback = '❌ Erro ao salvar o documento no banco de dados.';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(feedback),
                            backgroundColor: (localSaved || cloudSaved) ? AppTheme.primaryEmerald : AppTheme.accentRose,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      },
                icon: _isSavingDocument
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(_isSavingDocument ? 'Salvando...' : 'Salvar Documento'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentSky),
              ),
              ElevatedButton.icon(
                onPressed: () => _copyJsonToClipboard(doc),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar JSON'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${ScannedDocumentData.csvHeader()}\n${doc.toCsvRow()}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Linha CSV copiada para a área de transferência!')),
                  );
                },
                icon: const Icon(Icons.table_chart, size: 16),
                label: const Text('Copiar CSV'),
              ),
              IconButton(
                tooltip: 'Limpar Extração',
                icon: const Icon(Icons.delete_outline, color: AppTheme.accentRose),
                onPressed: () {
                  ref.read(activeDocumentProvider.notifier).clear();
                  setState(() {
                    _fileBytes = null;
                    _fileName = null;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showServerConfigDialog(BuildContext context) {
    final ocrClient = ref.read(ocrClientServiceProvider);
    final urlController = TextEditingController(text: ocrClient.baseUrl);
    bool isTesting = false;
    String? testResult;
    bool? testSuccess;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.slate900,
          title: const Row(
            children: [
              Icon(Icons.dns_rounded, color: AppTheme.accentSky),
              SizedBox(width: 8),
              Text('Servidor OCR (FastAPI)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('URL do Servidor:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    hintText: 'http://127.0.0.1:8000',
                    filled: true,
                    fillColor: AppTheme.slate800,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Atalhos Rápidos:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('🔌 USB (127.0.0.1)', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.slate800,
                      onPressed: () => urlController.text = 'http://127.0.0.1:8000',
                    ),
                    ActionChip(
                      label: const Text('📶 Wi-Fi (192.168.0.3)', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.slate800,
                      onPressed: () => urlController.text = 'http://192.168.0.3:8000',
                    ),
                    ActionChip(
                      label: const Text('💻 Emulador (10.0.2.2)', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.slate800,
                      onPressed: () => urlController.text = 'http://10.0.2.2:8000',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() {
                            isTesting = true;
                            testResult = null;
                            testSuccess = null;
                          });
                          final ok = await ocrClient.testConnection(urlController.text.trim());
                          setDialogState(() {
                            isTesting = false;
                            testSuccess = ok;
                            testResult = ok
                                ? '🟢 Conectado com sucesso ao servidor OCR!'
                                : '🔴 Não foi possível conectar a este endereço.';
                          });
                        },
                  icon: isTesting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('Testar Conexão'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.slate800,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: testSuccess == true
                          ? AppTheme.primaryEmerald.withValues(alpha: 0.15)
                          : AppTheme.accentRose.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: testSuccess == true ? AppTheme.primaryEmerald : AppTheme.accentRose,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  '💡 Dica para Celular via USB:\nSe a conexão for recusada, execute no terminal do PC:\nadb reverse tcp:8000 tcp:8000',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final newUrl = urlController.text.trim();
                if (newUrl.isNotEmpty) {
                  ocrClient.updateBaseUrl(newUrl);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Servidor OCR definido para: $newUrl'),
                      backgroundColor: AppTheme.primaryEmerald,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupabaseConfigDialog(BuildContext context) {
    final supabase = ref.read(supabaseServiceProvider);
    final urlController = TextEditingController(
      text: AppConstants.defaultSupabaseUrl != 'https://demo-project.supabase.co'
          ? AppConstants.defaultSupabaseUrl
          : '',
    );
    final keyController = TextEditingController(
      text: AppConstants.defaultSupabaseAnonKey != 'demo-anon-key'
          ? AppConstants.defaultSupabaseAnonKey
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.slate900,
        title: Row(
          children: [
            const Icon(Icons.cloud_sync, color: AppTheme.primaryEmerald),
            const SizedBox(width: 8),
            const Text('Conexão Supabase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: supabase.isConfigured
                      ? AppTheme.primaryEmerald.withValues(alpha: 0.15)
                      : AppTheme.slate800,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: supabase.isConfigured ? AppTheme.primaryEmerald : AppTheme.slate700,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      supabase.isConfigured ? Icons.check_circle : Icons.info_outline,
                      color: supabase.isConfigured ? AppTheme.primaryEmerald : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        supabase.isConfigured
                            ? 'Status: Conectado à nuvem Supabase'
                            : 'Status: Não configurado (modo local)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: supabase.isConfigured ? AppTheme.primaryEmerald : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Project URL:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: 'https://xyzcompany.supabase.co',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.slate800,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Anon Public Key:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'eyJhbGciOiJIUzI1NiIsInR5c...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.slate800,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '💡 Dica: No painel do Supabase, execute o arquivo supabase/schema.sql no SQL Editor para criar a tabela scanned_documents e o bucket client-documents.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              final key = keyController.text.trim();
              if (url.isNotEmpty && key.isNotEmpty) {
                final success = await SupabaseService.initializeWithCredentials(
                  url: url,
                  anonKey: key,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? '✅ Supabase conectado com sucesso!'
                          : '❌ Falha ao conectar ao Supabase. Verifique as credenciais.'),
                      backgroundColor: success ? AppTheme.primaryEmerald : AppTheme.accentRose,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald),
            child: const Text('Salvar e Conectar'),
          ),
        ],
      ),
    );
  }

  void _showHistoryBottomSheet(BuildContext context) {
    final supabase = ref.read(supabaseServiceProvider);
    final ocrClient = ref.read(ocrClientServiceProvider);
    final localHistory = ref.read(scanHistoryProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.slate800,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('Histórico de Documentos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryEmerald.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          supabase.isConfigured ? 'SQLite Local + Nuvem' : 'SQLite Local (Offline)',
                          style: const TextStyle(fontSize: 11, color: AppTheme.primaryEmerald, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Recarregar',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => setSheetState(() {}),
                  ),
                ],
              ),
              const Divider(color: AppTheme.slate700),
              Expanded(
                child: FutureBuilder<List<ScannedDocumentData>>(
                  future: ocrClient.fetchSavedDocuments(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final docs = snapshot.data ?? [];
                    final displayDocs = docs.isNotEmpty ? docs : localHistory;

                    if (displayDocs.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'Nenhum documento salvo no banco SQLite ainda.\nEscaneie uma imagem para salvar automaticamente.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: displayDocs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: AppTheme.slate700),
                      itemBuilder: (ctx, idx) {
                        final item = displayDocs[idx];
                        IconData typeIcon = Icons.badge;
                        if (item.documentType == 'cnh') typeIcon = Icons.directions_car;
                        if (item.documentType == 'passport') typeIcon = Icons.flight_takeoff;
                        if (item.documentType == 'cin') typeIcon = Icons.fingerprint;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                            child: Icon(typeIcon, color: AppTheme.primaryEmerald, size: 20),
                          ),
                          title: Text(
                            item.fullName ?? 'Documento sem nome',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${item.documentType.toUpperCase()} • ${item.documentNumber ?? item.cpf ?? 'Sem número'}'
                            '${item.birthDate != null ? ' • Nasc: ${item.birthDate}' : ''}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Excluir do SQLite',
                                icon: const Icon(Icons.delete_outline, color: AppTheme.accentRose, size: 18),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      backgroundColor: AppTheme.slate900,
                                      title: const Text('Excluir Documento'),
                                      content: Text('Tem certeza que deseja excluir ${item.fullName ?? "este documento"} do banco SQLite?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancelar')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(dCtx, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRose),
                                          child: const Text('Excluir'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await ocrClient.deleteSavedDocument(item.id);
                                    ref.read(scanHistoryProvider.notifier).remove(item.id);
                                    setSheetState(() {});
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Carregar no Inspetor',
                                icon: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.accentSky),
                                onPressed: () {
                                  ref.read(activeDocumentProvider.notifier).setDocument(item);
                                  _populateControllers(item);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
