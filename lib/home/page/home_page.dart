import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  GlobalKey globalKey = GlobalKey();
  late AnimationController _controller;
  int frameCount = 0;
  bool isCapturing = false;
  late Directory framesDirectory;
  late Directory videosDirectory;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _initializeDirectories();
  }

  Future<void> _initializeDirectories() async {
    try {
      // Solicitar permissões de armazenamento no Android
      if (Platform.isAndroid) {
        if (!(await _requestStoragePermission())) {
          debugPrint('Permissões de armazenamento negadas.');
          return;
        }
      }

      Directory baseDir;
      // Obter o diretório base dependendo da plataforma
      if (Platform.isAndroid) {
        // Solicitar permissões de armazenamento no Android
        if (!(await _requestStoragePermission())) {
          debugPrint('Permissões de armazenamento negadas.');
          return;
        }

        // Tentar obter o diretório externo de escrita
        baseDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      } else {
        // Para iOS, usar o sandbox padrão
        baseDir = await getApplicationDocumentsDirectory();
      }

      // Verificar se o diretório base existe
      if (!baseDir.existsSync()) {
        debugPrint('Diretório base não encontrado: ${baseDir.path}');
        if (Platform.isAndroid) {
          // Usar um fallback para Android
          final Directory fallbackDir =
              await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
          debugPrint('Usando fallback para diretório: ${fallbackDir.path}');
          framesDirectory = Directory('${fallbackDir.path}/frames');
          videosDirectory = Directory('${fallbackDir.path}/videos');
        } else {
          throw Exception('Não foi possível acessar o diretório base.');
        }
      } else {
        // Criar subdiretórios
        framesDirectory = Directory('${baseDir.path}/frames');
        videosDirectory = Directory('${baseDir.path}/videos');
      }

      // Criar os diretórios se não existirem
      if (!framesDirectory.existsSync()) {
        framesDirectory.createSync(recursive: true);
      }
      if (!videosDirectory.existsSync()) {
        videosDirectory.createSync(recursive: true);
      }

      debugPrint('Diretório para frames: ${framesDirectory.path}');
      debugPrint('Diretório para vídeos: ${videosDirectory.path}');
    } catch (e) {
      debugPrint('Erro ao inicializar diretórios: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final PermissionStatus status = await Permission.storage.request();
      return status.isGranted;
    }
    return true; // No iOS, permissões de armazenamento não são necessárias
  }

  Future<void> _startCapture() async {
    setState(() {
      frameCount = 0;
      isCapturing = true;
    });

    _controller.repeat();
    _controller.addListener(() async {
      if (isCapturing) {
        await _captureFrame();
      }
    });
  }

  Future<void> _stopCapture() async {
    setState(() {
      isCapturing = false;
    });
    _controller.stop();
    debugPrint('Captura encerrada. Total de frames capturados: $frameCount');
  }

  Future<void> _captureFrame() async {
    try {
      final RenderRepaintBoundary boundary =
          globalKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final ui.Image image = await boundary.toImage();
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final String filePath =
          '${framesDirectory.path}/frame_${frameCount.toString().padLeft(4, '0')}.png';

      final File file = File(filePath);
      await file.writeAsBytes(pngBytes);

      frameCount++;
    } catch (e) {
      debugPrint('Erro ao capturar frame: $e');
    }
  }

  Future<void> _generateVideo() async {
    try {
      final String outputPath = '${videosDirectory.path}/output.mp4';

      debugPrint('Gerando vídeo em $outputPath...');

      // Verificar encoder disponível
      String encoder = await _getAvailableEncoder();

      // Comando FFmpeg para gerar o vídeo
      final String command =
          '-y -framerate 30 -i ${framesDirectory.path}/frame_%04d.png -c:v $encoder -pix_fmt yuv420p $outputPath';

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          debugPrint('Vídeo criado com sucesso em $outputPath');
        } else {
          final logs = await session.getAllLogs();
          for (var log in logs) {
            debugPrint('FFMPEG LOG: ${log.getMessage()}');
          }
          debugPrint('Erro ao criar vídeo.');
        }
      });
    } catch (e) {
      debugPrint('Erro ao gerar vídeo: $e');
    }
  }

  Future<String> _getAvailableEncoder() async {
    String encoder = 'mpeg4'; // Default encoder
    await FFmpegKit.execute('-encoders').then((session) async {
      final logs = await session.getAllLogs();
      for (var log in logs) {
        if (log.getMessage().contains('libx264')) {
          encoder = 'libx264';
          break;
        }
      }
    });
    debugPrint('Usando encoder: $encoder');
    return encoder;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture Frames')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RepaintBoundary(
            key: globalKey,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _controller.value * 2.0 * 3.141592653589793,
                  child: const Icon(Icons.star, size: 100, color: Colors.blue),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: isCapturing ? null : _startCapture,
                child: const Text('Iniciar Captura'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: isCapturing ? _stopCapture : null,
                child: const Text('Parar Captura'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !isCapturing && frameCount > 0 ? _generateVideo : null,
            child: const Text('Gerar Vídeo'),
          ),
        ],
      ),
    );
  }
}
