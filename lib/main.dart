import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // For MediaType
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Retrieve the list of available cameras.
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Realtime Leaf Prediction',
      home: PredictionPage(cameras: cameras),
    );
  }
}

class PredictionPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const PredictionPage({Key? key, required this.cameras}) : super(key: key);

  @override
  _PredictionPageState createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  CameraController? _controller;
  Timer? _timer;
  bool _isProcessing = false;
  String? _prediction = "Waiting for prediction...";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    // Request camera permission first.
    final permissionStatus = await Permission.camera.request();
    if (!permissionStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required')),
      );
      return;
    }

    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No camera found')),
      );
      return;
    }

    // Use the first camera (typically the back camera).
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});

    // Start a periodic timer (every 3 seconds) to capture and send an image.
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _captureAndPredict();
    });
  }

  Future<void> _captureAndPredict() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    try {
      setState(() {
        _isProcessing = true;
      });

      // Capture an image from the camera.
      final XFile file = await _controller!.takePicture();
      File imageFile = File(file.path);

      // Read image bytes.
      List<int> imageBytes = await imageFile.readAsBytes();

      // Decode the captured image using the image package.
      img.Image? capturedImage = img.decodeImage(imageBytes);
      if (capturedImage == null) {
        throw Exception("Could not decode captured image");
      }

      // Crop the image to a square (center crop) so it matches the 1:1 ratio.
      int width = capturedImage.width;
      int height = capturedImage.height;
      int squareSize = width < height ? width : height;
      int offsetX = ((width - squareSize) / 2).round();
      int offsetY = ((height - squareSize) / 2).round();
      img.Image croppedImage =
          img.copyCrop(capturedImage, offsetX, offsetY, squareSize, squareSize);

      // Resize the cropped image to 320x320 (matching the YOLO model input).
      img.Image resizedImage =
          img.copyResize(croppedImage, width: 320, height: 320);

      // Encode the image as JPEG.
      List<int> jpeg = img.encodeJpg(resizedImage);

      // Prepare HTTP multipart request.
      var uri = Uri.parse('http://192.168.100.7:5000/predict');
      var request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        jpeg,
        filename: 'captured.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));

      // Send the request.
      var response = await request.send();
      if (response.statusCode == 200) {
        String responseBody = await response.stream.bytesToString();
        var result = jsonDecode(responseBody);
        setState(() {
          if (result.containsKey("class") && result.containsKey("confidence")) {
            _prediction =
                "Class: ${result['class']}\nConfidence: ${result['confidence']}";
          } else if (result.containsKey("error")) {
            _prediction = "Error: ${result['error']}";
          } else {
            _prediction = "Unexpected response";
          }
        });
      } else {
        setState(() {
          _prediction = "Error: Server responded with ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _prediction = "Error: $e";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Display a square (1:1) camera preview.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Leaf Prediction'),
        centerTitle: true,
      ),
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // The preview is wrapped in an AspectRatio of 1 (square).
                AspectRatio(
                  aspectRatio: 1,
                  child: CameraPreview(_controller!),
                ),
                const SizedBox(height: 16),
                Text(
                  _prediction ?? "",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
    );
  }
}
