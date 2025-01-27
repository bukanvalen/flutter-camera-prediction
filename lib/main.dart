import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite/tflite.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PredictionPage(),
    );
  }
}

class PredictionPage extends StatefulWidget {
  @override
  _PredictionPageState createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  File? _image;
  String? _prediction;
  bool _loading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  Future<void> loadModel() async {
    String? result = await Tflite.loadModel(
      model: "assets/models/model.tflite",
    );
    print("Model loaded: $result");
  }

  Future<void> _pickImage() async {
    final permissionStatus = await Permission.camera.request();
    if (!permissionStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required')),
      );
      return;
    }

    final pickedFile = await _picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _predictImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image selected')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final predictions = await Tflite.runModelOnImage(
        path: _image!.path, // Path to the image
        imageMean: 0.0,
        imageStd: 255.0,
        numResults: 5,
        threshold: 0.5,
      );

      if (predictions != null && predictions.isNotEmpty) {
        setState(() {
          _prediction = predictions
              .map((p) =>
                  "${p['label']} (${(p['confidence'] * 100).toStringAsFixed(2)}%)")
              .join("\n");
        });
      } else {
        setState(() {
          _prediction = "No prediction made.";
        });
      }
    } catch (e) {
      setState(() {
        _prediction = "Error: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Prediction'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _image != null
                  ? Image.file(_image!, height: 200)
                  : const Text('No image selected'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Capture Image'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _predictImage,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Predict'),
              ),
              const SizedBox(height: 20),
              if (_prediction != null)
                Text(
                  _prediction!,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
