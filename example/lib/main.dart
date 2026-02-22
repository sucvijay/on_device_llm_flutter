import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:on_device_llm/on_device_llm.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: DemoHomePage());
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final OnDeviceLlm _llm = OnDeviceLlm();
  final TextEditingController _promptController = TextEditingController();

  String? _modelPath;
  String? _mmprojPath;
  String _output = '';
  String _status = 'Pick a GGUF model to begin.';

  @override
  void dispose() {
    _promptController.dispose();
    _llm.close();
    super.dispose();
  }

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _modelPath = path;
      _status = 'Model selected.';
    });
  }

  Future<void> _pickMmproj() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _mmprojPath = path;
      _status = 'mmproj selected.';
    });
  }

  Future<void> _loadModel() async {
    final modelPath = _modelPath;
    if (modelPath == null) {
      setState(() => _status = 'Please pick a GGUF model first.');
      return;
    }

    setState(() => _status = 'Loading model...');
    final loaded = await _llm.load(modelPath, mmprojPath: _mmprojPath);
    if (!mounted) return;
    setState(() {
      _status = loaded ? 'Model loaded.' : 'Failed to load model.';
    });
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _status = 'Enter a prompt first.');
      return;
    }

    setState(() {
      _status = 'Generating...';
      _output = '';
    });

    final response = await _llm.generate(prompt);
    if (!mounted) return;

    setState(() {
      _output = response ?? '';
      _status = 'Generate complete.';
    });
  }

  Future<void> _streamGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _status = 'Enter a prompt first.');
      return;
    }

    setState(() {
      _status = 'Streaming...';
      _output = '';
    });

    await for (final chunk in _llm.streamGenerate(prompt)) {
      if (!mounted) return;
      setState(() {
        _output += chunk;
      });
    }

    if (!mounted) return;
    setState(() {
      _status = 'Streaming complete.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OnDeviceLLM Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton(
              onPressed: _pickModel,
              child: Text(_modelPath == null ? 'Pick GGUF Model' : 'Model: $_modelPath'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickMmproj,
              child: Text(
                _mmprojPath == null ? 'Pick mmproj (optional)' : 'mmproj: $_mmprojPath',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadModel, child: const Text('Load Model')),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter prompt',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: _generate,
                    child: const Text('Generate'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _streamGenerate,
                    child: const Text('Stream'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_output.isEmpty ? 'Output will appear here.' : _output),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
