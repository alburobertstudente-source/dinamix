import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../profile/profile.dart';
import '../../brand/logo.dart';
import '../../widgets/effects.dart';

/// First-launch registration (specification §1): name, surname, age, all
/// required. Also used from the settings to edit the profile.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, this.editing = false});

  final bool editing;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _age;
  bool _saving = false;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileService>().profile;
    _first = TextEditingController(text: p?.firstName ?? '');
    _last = TextEditingController(text: p?.lastName ?? '');
    _age = TextEditingController(text: p == null ? '' : '${p.age}');
    for (final c in [_first, _last, _age]) {
      c.addListener(_revalidate);
    }
    _revalidate();
  }

  void _revalidate() {
    final ok = validateName(_first.text, 'nome') == null &&
        validateName(_last.text, 'cognome') == null &&
        validateAge(_age.text) == null;
    if (ok != _valid) setState(() => _valid = ok);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final profiles = context.read<ProfileService>();
    final navigator = Navigator.of(context);
    try {
      await profiles.saveProfile(UserProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        age: int.parse(_age.text.trim()),
      ));
      if (widget.editing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profilo aggiornato')));
        navigator.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Profilo non salvato: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: widget.editing ? null : Colors.transparent,
      appBar: widget.editing ? AppBar(title: const Text('Profilo')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.editing) ...[
                      const Center(child: DynamixMark(size: 84)),
                      const SizedBox(height: 18),
                      const Center(child: DynamixWordmark(height: 26)),
                      const SizedBox(height: 14),
                      Text(
                        'Analizza i movimenti con i sensori del telefono o della SensorTile e '
                        'riconosce gli urti potenzialmente pericolosi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, height: 1.35),
                      ),
                      const SizedBox(height: 28),
                    ],
                    TextFormField(
                      key: const Key('field_first'),
                      controller: _first,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => validateName(v, 'nome'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('field_last'),
                      controller: _last,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                      decoration: const InputDecoration(labelText: 'Cognome', prefixIcon: Icon(Icons.badge_outlined)),
                      validator: (v) => validateName(v, 'cognome'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('field_age'),
                      controller: _age,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _valid ? _submit() : null,
                      decoration: const InputDecoration(labelText: 'Età', prefixIcon: Icon(Icons.cake_outlined)),
                      validator: validateAge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'I dati restano solo su questo telefono, cifrati. Il nome serve al messaggio '
                      'per il contatto di emergenza, se lo configuri.',
                      style: TextStyle(color: muted, fontSize: 12.5, height: 1.35),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: _valid && !_saving ? 1 : 0.5,
                      child: IgnorePointer(
                        ignoring: !_valid || _saving,
                        child: GradientButton(
                          key: const Key('register_button'),
                          label: widget.editing ? 'Salva' : 'Registrati',
                          icon: widget.editing ? Icons.check_rounded : Icons.arrow_forward_rounded,
                          onPressed: _submit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
