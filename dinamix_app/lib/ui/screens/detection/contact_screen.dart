import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/services.dart';
import '../../../profile/profile.dart';
import '../../../settings/app_settings.dart';
import '../../format.dart';
import '../../theme.dart';

/// "Emergency Contact" settings (specification §12): name, number, enable,
/// number check and a test message sent only after an explicit confirmation.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _number;
  bool _enabled = true;
  bool _busy = false;
  bool? _permission;

  @override
  void initState() {
    super.initState();
    final c = context.read<ProfileService>().contact;
    _name = TextEditingController(text: c?.name ?? '');
    _number = TextEditingController(text: c?.number ?? '');
    _enabled = c?.enabled ?? true;
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final p = await context.read<AppServices>().alerts.sms.hasPermission();
    if (mounted) setState(() => _permission = p);
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<bool> _save({bool quiet = false}) async {
    if (!(_form.currentState?.validate() ?? false)) return false;
    final profiles = context.read<ProfileService>();
    final sms = context.read<AppServices>().alerts.sms;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (_enabled && !await sms.hasPermission()) {
        final granted = await sms.requestPermission();
        if (!granted) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Senza il permesso SMS il messaggio non può partire. Puoi concederlo dalle impostazioni di Android.')));
        }
      }
      final old = profiles.contact;
      await profiles.saveContact(EmergencyContact(
        name: _name.text.trim(),
        number: normalizePhoneNumber(_number.text)!,
        enabled: _enabled,
        lastTestAtMs: old?.number == normalizePhoneNumber(_number.text) ? old?.lastTestAtMs : null,
        lastTestOk: old?.number == normalizePhoneNumber(_number.text) ? old?.lastTestOk : null,
      ));
      _number.text = profiles.contact!.number;
      if (!quiet) messenger.showSnackBar(const SnackBar(content: Text('Contatto salvato')));
      await _checkPermission();
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (!await _save(quiet: true) || !mounted) return;
    final services = context.read<AppServices>();
    final profiles = context.read<ProfileService>();
    final settings = context.read<AppSettings>();
    final contact = profiles.contact!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inviare un SMS di prova?'),
        content: Text('Verrà inviato un vero SMS a ${contact.name} (${contact.number}), con costo secondo il tuo '
            'piano tariffario:\n\n"${testMessage(profiles.profile)}"'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Invia prova')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (settings.smsDryRun) {
        messenger.showSnackBar(const SnackBar(content: Text('Modalità prova SMS attiva: nessun messaggio inviato.')));
        return;
      }
      final result = await services.alerts.sms.send(contact.number, testMessage(profiles.profile));
      await profiles.saveContact(contact.copyWith(
          lastTestAtMs: DateTime.now().millisecondsSinceEpoch, lastTestOk: result.ok));
      messenger.showSnackBar(SnackBar(
          content: Text(result.ok ? 'SMS di prova inviato.' : 'Invio non riuscito: $result')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final profiles = context.read<ProfileService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare il contatto?'),
        content: const Text('Senza contatto, l\'allarme suonerà ma nessun messaggio verrà inviato.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await profiles.deleteContact();
    _name.clear();
    _number.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileService>();
    final settings = context.watch<AppSettings>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = profiles.contact;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contact')),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Text('Se un evento pericoloso non viene annullato entro 60 secondi, DYNAMIX invia un SMS a questo contatto.',
                style: TextStyle(color: muted, height: 1.35)),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome del contatto', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => validateName(v, 'nome'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numero di telefono',
                hintText: '+39 333 123 4567',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: validatePhoneNumber,
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Attiva l\'invio automatico'),
              subtitle: const Text('Dopo 60 s senza annullamento'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusRow(
                      ok: _permission == true,
                      text: _permission == null
                          ? 'Controllo del permesso SMS…'
                          : _permission!
                              ? 'Permesso SMS concesso'
                              : 'Permesso SMS non concesso',
                    ),
                    _StatusRow(
                      ok: c?.lastTestOk == true,
                      text: c?.lastTestAtMs == null
                          ? 'Nessun SMS di prova inviato'
                          : 'Ultima prova ${formatRelative(c!.lastTestAtMs!)}: ${c.lastTestOk == true ? 'riuscita' : 'non riuscita'}',
                    ),
                    if (settings.smsDryRun)
                      const _StatusRow(ok: false, text: 'Modalità prova SMS attiva: nessun messaggio reale'),
                    const SizedBox(height: 6),
                    Text('La verifica del numero controlla solo il formato: il test d\'invio conferma il destinatario.',
                        style: TextStyle(color: muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salva'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Invia un SMS di prova'),
            ),
            if (c != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline, color: Palette.danger),
                label: const Text('Elimina contatto', style: TextStyle(color: Palette.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 18, color: ok ? Palette.ok : Palette.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
