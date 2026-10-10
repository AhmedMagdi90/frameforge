import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/ai_video.dart';
import '../models/project.dart';
import '../services/ai_client.dart';
import '../services/ai_project_importer.dart';
import '../services/project_library.dart';
import '../theme.dart';
import 'editor_screen.dart';

class AiStudioScreen extends StatefulWidget {
  const AiStudioScreen({super.key, required this.library, this.client});
  final ProjectLibrary library;
  final AiClient? client;
  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  late final AiClient _client;
  final _prompt = TextEditingController();
  final _conversation = <Map<String, String>>[];
  CanvasRatio _ratio = CanvasRatio.portrait;
  int _seconds = 30;
  String _voice = 'coral';
  AiVideoPlan? _plan;
  AiJob? _job;
  List<AiJob> _history = [];
  String? _error, _requestKey;
  bool _busy = true, _importing = false, _polling = false;
  Timer? _timer;
  @override
  void initState() { super.initState(); _client = widget.client ?? AiClient(); _restore(); }
  @override
  void dispose() { _timer?.cancel(); _prompt.dispose(); if (widget.client == null) _client.close(); super.dispose(); }
  Future<void> _restore() async {
    await _run(() async { await _client.restore(); await _loadHistory(); });
  }
  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() { _busy = true; _error = null; });
    try { await action(); }
    catch (error) { if (mounted) setState(() => _error = '$error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _loadHistory() async {
    if (_client.account == null) return;
    final history = await _client.jobs();
    if (!mounted) return;
    setState(() => _history = history);
    final active = history.where((job) => job.active);
    if (_job == null && active.isNotEmpty) _select(active.first);
  }
  void _select(AiJob job) {
    _timer?.cancel();
    setState(() { _job = job; _plan = job.plan; _ratio = job.plan.ratio; _requestKey = null; _error = null; });
    if (job.active) _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }
  Future<void> _poll() async {
    if (_polling || _busy || _job?.active != true) return;
    _polling = true;
    final id = _job!.id;
    try {
      final next = await _client.job(id);
      if (!mounted || _job?.id != id) return;
      setState(() { _job = next; _error = null; });
      if (!next.active) { _timer?.cancel(); await _loadHistory(); }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      // Keep server jobs running; the user can reconnect after a network failure.
      if (_client.account == null) _timer?.cancel();
    } finally { _polling = false; }
  }
  Future<void> _service() async {
    final controller = TextEditingController(text: _client.serviceUrl);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Connect AI service'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter the service address provided by your app administrator.'), const SizedBox(height: 16),
        TextField(controller: controller, keyboardType: TextInputType.url, autocorrect: false,
          decoration: const InputDecoration(labelText: 'Service address', hintText: 'https://ai.example.com')),
      ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Connect'))]));
    controller.dispose();
    if (value == null || !mounted) return;
    await _run(() async {
      final previous = _client.serviceUrl;
      await _client.connect(value);
      if (_client.serviceUrl != previous) _clearWorkspace();
      await _client.refresh(); await _loadHistory();
    });
  }
  void _clearWorkspace() {
    _timer?.cancel(); _conversation.clear(); _prompt.clear();
    if (mounted) setState(() { _plan = null; _job = null; _history = []; _requestKey = null; });
  }
  Future<void> _signIn() async => _run(() async { await _client.signIn(); _clearWorkspace(); await _loadHistory(); });
  Future<void> _signOut() async => _run(() async {
    try { await _client.signOut(); } finally { _clearWorkspace(); }
  });
  Future<void> _makePlan() async {
    final idea = _prompt.text.trim();
    if (idea.isEmpty) { setState(() => _error = 'Describe your video idea first.'); return; }
    await _run(() async {
      final context = [..._conversation];
      if (_plan != null) {
        final draft = jsonEncode(_plan!.toJson());
        context.add({'role': 'assistant', 'content': draft.length > 6500 ? draft.substring(0, 6500) : draft});
      }
      context.add({'role': 'user', 'content': idea});
      final messages = context.length > 10 ? context.sublist(context.length - 10) : context;
      final result = await _client.plan(messages, _ratio, _seconds);
      if (!mounted) return;
      _conversation..clear()..addAll(messages);
      _prompt.clear();
      setState(() { _plan = result; _job = null; _requestKey = null; });
    });
  }
  Future<void> _editScene(int index) async {
    final original = _plan!.scenes[index];
    final visual = TextEditingController(text: original.imagePrompt);
    final narration = TextEditingController(text: original.narration);
    final caption = TextEditingController(text: original.caption);
    var seconds = original.seconds;
    final result = await showDialog<AiScene>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text('Scene ${index + 1}'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: visual, onChanged: (_) => update(() {}), maxLength: 2500, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Visual description')),
        TextField(controller: narration, onChanged: (_) => update(() {}), maxLength: 500, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'AI narration')),
        TextField(controller: caption, onChanged: (_) => update(() {}), maxLength: 250, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'On-screen caption')),
        Row(children: [Text('At least $seconds seconds'), Expanded(child: Slider(value: seconds.toDouble(), min: 2, max: 20,
          divisions: 18, onChanged: (value) => update(() => seconds = value.round()))) ]),
        const Text('Longer narration may extend the scene.', style: TextStyle(color: muted, fontSize: 12)),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: visual.text.trim().length < 10 || narration.text.trim().isEmpty || caption.text.trim().isEmpty ? null : () =>
          Navigator.pop(context, AiScene(imagePrompt: visual.text.trim(), narration: narration.text.trim(), caption: caption.text.trim(), seconds: seconds)),
          child: const Text('Save'))],
    )));
    visual.dispose(); narration.dispose(); caption.dispose();
    if (result != null && mounted) setState(() { _plan = _plan!.replacingScene(index, result); _job = null; _requestKey = null; });
  }
  Future<void> _generate() async => _run(() async {
    // Keep this key on a transport failure so a retry cannot purchase a duplicate job.
    _requestKey ??= AiClient.requestKey();
    final job = await _client.generate(_plan!, _voice, _requestKey!);
    if (mounted) { _select(job); await _loadHistory(); }
  });
  Future<void> _cancel() async => _run(() async {
    final result = await _client.cancel(_job!.id);
    if (mounted) _select(result);
    await _loadHistory();
  });
  Future<void> _openEditor() async {
    setState(() => _importing = true);
    await _run(() async {
      final project = await AiProjectImporter(widget.library, _client).importVideo(_job!);
      if (!mounted) return;
      setState(() => _importing = false);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditorScreen(project: project, library: widget.library)));
    });
    if (mounted) setState(() => _importing = false);
  }
  @override
  Widget build(BuildContext context) {
    final signedIn = _client.account != null;
    final active = _job?.active == true;
    final editable = !_busy && !active && _requestKey == null;
    return PopScope(canPop: !_importing, child: Scaffold(
      appBar: AppBar(title: const Text('AI studio'), actions: [IconButton(tooltip: 'AI service settings', onPressed: _busy || active ? null : _service, icon: const Icon(Icons.settings_outlined))]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40), children: [
        const Icon(Icons.auto_awesome_rounded, color: violet, size: 42), const SizedBox(height: 18),
        const Text('An idea. A story.\nA video of your own.', style: TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('Describe your idea, shape the scene plan, then create a narrated video with AI images and gentle camera motion.', style: TextStyle(color: muted, height: 1.5)),
        const SizedBox(height: 24),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        if (!_client.configured) _panel([
          const Text('Connect your AI service to get started.'), const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _service, child: const Text('Connect AI service')),
        ]) else _panel([
          Row(children: [const Icon(Icons.account_circle_outlined, color: mint), const SizedBox(width: 12),
            Expanded(child: Text(signedIn ? _client.account!.name : 'Your ChatGPT account', style: const TextStyle(fontWeight: FontWeight.w600))),
            if (signedIn) TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out'))]),
          if (!signedIn) ...[const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy || _client.capabilities['sign_in_configured'] != true ? null : _signIn,
              icon: const Icon(Icons.login_rounded), label: const Text('Continue with ChatGPT')),
            if (_client.capabilities['sign_in_configured'] != true) const Padding(padding: EdgeInsets.only(top: 10),
              child: Text('ChatGPT sign-in is not available on this service yet. Contact your app administrator.', style: TextStyle(color: muted))),
          ],
          const SizedBox(height: 10),
          const Text('Generation uses this service’s API billing, separately from your ChatGPT subscription. Images and voice are AI-generated.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        ]),
        if (_client.configured && !signedIn && !_busy) Align(alignment: Alignment.centerLeft,
          child: TextButton(onPressed: _restore, child: const Text('Reconnect'))),
        if (signedIn) ...[
          const SizedBox(height: 24),
          TextField(controller: _prompt, enabled: editable, minLines: 3, maxLines: 7, maxLength: 3000,
            decoration: InputDecoration(labelText: _plan == null ? 'Describe your video idea' : 'Refine your idea',
              hintText: 'A 30-second story about a small coffee shop, warm morning light, with a friendly voice…', border: const OutlineInputBorder())),
          Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<CanvasRatio>(value: _ratio, items: CanvasRatio.values.map((value) => DropdownMenuItem(value: value, child: Text(value.label))).toList(),
              onChanged: editable ? (value) => setState(() => _ratio = value!) : null),
            DropdownButton<int>(value: _seconds, items: [15, 30, 60].map((value) => DropdownMenuItem(value: value, child: Text('About ${value}s'))).toList(),
              onChanged: editable ? (value) => setState(() => _seconds = value!) : null),
            DropdownButton<String>(value: _voice, items: ['coral', 'alloy', 'nova', 'sage', 'shimmer'].map((value) => DropdownMenuItem(value: value, child: Text('Voice: $value'))).toList(),
              onChanged: editable ? (value) => setState(() => _voice = value!) : null),
          ]),
          FilledButton.tonalIcon(onPressed: editable && _client.capabilities['planning_configured'] == true ? _makePlan : null,
            icon: const Icon(Icons.chat_bubble_outline), label: Text(_plan == null ? 'Make scene plan' : 'Update scene plan')),
          if (_client.capabilities['planning_configured'] != true) const Text('AI generation is not configured on this service.', style: TextStyle(color: muted)),
        ],
        if (signedIn && _plan != null) ...[
          const SizedBox(height: 28), Text(_plan!.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8), Text(_plan!.summary, style: const TextStyle(color: muted)),
          const SizedBox(height: 16),
          for (var index = 0; index < _plan!.scenes.length; index++) Padding(padding: const EdgeInsets.only(bottom: 12), child: _panel([
            Row(children: [Text('SCENE ${index + 1}', style: const TextStyle(color: violet, fontSize: 11, letterSpacing: 1.5)), const Spacer(),
              Text('${_plan!.scenes[index].seconds}s+', style: const TextStyle(color: muted)),
              IconButton(tooltip: 'Edit scene', onPressed: editable ? () => _editScene(index) : null, icon: const Icon(Icons.edit_outlined, size: 18))]),
            Text(_plan!.scenes[index].imagePrompt, style: const TextStyle(color: muted, height: 1.4)), const SizedBox(height: 12),
            Text(_plan!.scenes[index].narration, style: const TextStyle(height: 1.5)), const SizedBox(height: 8),
            Text('Caption: ${_plan!.scenes[index].caption}', style: const TextStyle(color: mint, fontSize: 12)),
          ])),
          if (!active && _job?.status != 'completed') FilledButton.icon(
            onPressed: _busy || _client.capabilities['generation_configured'] != true ? null : _generate,
            icon: const Icon(Icons.movie_creation_outlined), label: Text(_requestKey == null ? 'Generate video' : 'Retry generation request')),
          if (_requestKey != null && _job == null) TextButton(onPressed: _busy ? null : () => _run(_loadHistory), child: const Text('Check video history')),
        ],
        if (signedIn && _job != null) Padding(padding: const EdgeInsets.only(top: 24), child: _panel([
          Text(_job!.message, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 12),
          if (active) ...[LinearProgressIndicator(value: _job!.progress), const SizedBox(height: 10),
            const Text('You can leave this screen and return to your video history.', style: TextStyle(color: muted, fontSize: 12)),
            TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel generation')),
            const Text('Already-started AI requests may still incur usage.', style: TextStyle(color: muted, fontSize: 11))],
          if (_job!.error != null) Text(_job!.error!, style: const TextStyle(color: Colors.redAccent)),
          if (_job!.status == 'completed') ...[
            const Text('Your MP4 is ready. Open it as an editable draft with scene clips and captions.', style: TextStyle(color: muted)), const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _openEditor, icon: const Icon(Icons.content_cut_rounded), label: Text(_importing ? 'Downloading scenes…' : 'Open in editor')),
          ],
        ])),
        if (signedIn && _history.isNotEmpty) ...[const SizedBox(height: 28),
          Row(children: [const Text('Your AI videos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const Spacer(),
            IconButton(tooltip: 'Refresh video history', onPressed: _busy ? null : () => _run(_loadHistory), icon: const Icon(Icons.refresh_rounded))]),
          for (final job in _history) ListTile(contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.movie_outlined, color: violet), title: Text(job.plan.title), subtitle: Text(job.status),
            onTap: _busy ? null : () => _select(job), trailing: const Icon(Icons.chevron_right_rounded)),
        ],
      ])))),
    ));
  }
  Widget _panel(List<Widget> children) => Container(padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
}
