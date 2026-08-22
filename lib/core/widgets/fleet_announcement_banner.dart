import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/iterable_extensions.dart';
import '../../shared/models/app_models.dart';
import '../../shared/services/app_providers.dart';
import 'corporate_ui.dart';

class FleetAnnouncementBanner extends ConsumerWidget {
  const FleetAnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final announcementsAsync = ref.watch(fleetAnnouncementsProvider);
    final announcements = announcementsAsync.valueOrNull ?? const <FleetAnnouncement>[];

    if (announcementsAsync.hasError) {
      return CorporateSurface(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.statusStopped),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nao foi possivel carregar tarefas.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (announcements.isEmpty || user == null) return const SizedBox.shrink();

    final visibleAnnouncements = announcements.where((announcement) => announcement.isVisibleTo(user)).toList();

    if (visibleAnnouncements.isEmpty) return const SizedBox.shrink();

    return Column(
      children: visibleAnnouncements
          .map((announcement) => _AnnouncementCard(announcement: announcement, user: user))
          .toList(),
    );
  }
}

class _AnnouncementCard extends ConsumerWidget {
  const _AnnouncementCard({required this.announcement, required this.user});

  final FleetAnnouncement announcement;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRespond = user.canRespondToFleetTasks &&
        announcement.isPendingResponse &&
        (announcement.isGroupTask || announcement.targetDriverId == user.id);

    return CorporateSurface(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.task_alt_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.isGroupTask
                          ? 'Tarefa para todos'
                          : 'Tarefa para ${announcement.targetDriverName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(announcement.message, style: const TextStyle(fontSize: 14, height: 1.35)),
                    const SizedBox(height: 6),
                    Text(
                      '${announcement.createdByName} • ${formatDateTime(announcement.createdAt)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (announcement.expiresAt != null)
                      Text(
                        'Valido ate ${formatDate(announcement.expiresAt)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    if (announcement.isGroupTask && user.canRespondToFleetTasks)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Visivel para todos os motoristas cadastrados. O primeiro que concluir remove para todos.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (announcement.responseStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _ResponseBadge(
                          status: announcement.responseStatus!,
                          respondedByName: announcement.respondedByName,
                          respondedAt: announcement.respondedAt,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (canRespond) ...[
            const SizedBox(height: 12),
            if (announcement.isGroupTask)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusMoving,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _respond(context, ref, AnnouncementResponseStatus.completed),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('CONCLUIR'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusMoving,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _respond(context, ref, AnnouncementResponseStatus.completed),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('CONCLUIDO'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _respond(context, ref, AnnouncementResponseStatus.rejected),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('RECUSADO'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _respond(BuildContext context, WidgetRef ref, AnnouncementResponseStatus status) async {
    String? rejectionReason;
    if (status == AnnouncementResponseStatus.rejected) {
      rejectionReason = await _askRejectionReason(context);
      if (rejectionReason == null) return;
    }

    final error = await ref.read(repositoryProvider).respondToAnnouncement(
          user,
          announcement.id,
          status,
          rejectionReason: rejectionReason,
        );
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final label = status == AnnouncementResponseStatus.completed ? 'concluida' : 'recusada';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tarefa marcada como $label.')));
  }

  Future<String?> _askRejectionReason(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Justificativa obrigatoria'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Motivo da recusa',
            hintText: 'Descreva por que nao pode concluir a tarefa',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Informe a justificativa para recusar.')),
                );
                return;
              }
              Navigator.pop(context, text);
            },
            child: const Text('Enviar recusa'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _ResponseBadge extends StatelessWidget {
  const _ResponseBadge({
    required this.status,
    required this.respondedByName,
    required this.respondedAt,
  });

  final AnnouncementResponseStatus status;
  final String? respondedByName;
  final DateTime? respondedAt;

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == AnnouncementResponseStatus.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.statusMovingBg : AppColors.statusStopped.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${isCompleted ? 'Concluida' : 'Recusada'}'
        '${respondedByName == null ? '' : ' por $respondedByName'}'
        '${respondedAt == null ? '' : ' • ${formatDateTime(respondedAt)}'}',
        style: TextStyle(
          color: isCompleted ? AppColors.statusMovingDark : AppColors.statusStopped,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class FleetAnnouncementEditor extends ConsumerStatefulWidget {
  const FleetAnnouncementEditor({super.key, required this.admin});

  final AppUser admin;

  @override
  ConsumerState<FleetAnnouncementEditor> createState() => _FleetAnnouncementEditorState();
}

class _FleetAnnouncementEditorState extends ConsumerState<FleetAnnouncementEditor> {
  final _controller = TextEditingController();
  bool _publishing = false;
  DateTime? _expiresAt;
  String? _targetDriverId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Data de validade',
    );
    if (picked == null || !mounted) return;
    setState(() => _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);

    final drivers = (ref.read(usersProvider).valueOrNull ?? [])
        .where((user) => user.role == UserRole.driver)
        .toList();
    final selectedDriver = _targetDriverId == null
        ? null
        : drivers.where((driver) => driver.id == _targetDriverId).firstOrNull;

    final error = await ref.read(repositoryProvider).publishAnnouncement(
          widget.admin,
          message: _controller.text,
          expiresAt: _expiresAt,
          targetDriverId: selectedDriver?.id,
          targetDriverName: selectedDriver?.name,
        );
    if (!mounted) return;
    setState(() => _publishing = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _controller.clear();
    setState(() {
      _expiresAt = null;
      _targetDriverId = null;
    });
    final targetLabel = selectedDriver == null ? 'todos os motoristas' : selectedDriver.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tarefa publicada para $targetLabel.')),
    );
  }

  Future<void> _delete(String announcementId) async {
    setState(() => _publishing = true);
    final error = await ref.read(repositoryProvider).deleteAnnouncement(widget.admin, announcementId);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarefa removida.')));
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(fleetAnnouncementsProvider).valueOrNull ?? const <FleetAnnouncement>[];
    final drivers = (ref.watch(usersProvider).valueOrNull ?? [])
        .where((user) => user.role == UserRole.driver)
        .toList();

    return CorporateSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CorporateSectionTitle(title: 'Tarefas para motoristas'),
          const Text(
            'Para todos os motoristas cadastrados: so Concluir — o primeiro que concluir remove para todos. '
            'Para um motorista especifico: Concluido ou Recusado com notificacao instantanea.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (current.isNotEmpty) ...[
            ...current.map(
              (announcement) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.isGroupTask
                          ? 'Tarefa para todos'
                          : 'Para ${announcement.targetDriverName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(announcement.message),
                    if (announcement.responseStatus != null) ...[
                      const SizedBox(height: 6),
                      _ResponseBadge(
                        status: announcement.responseStatus!,
                        respondedByName: announcement.respondedByName,
                        respondedAt: announcement.respondedAt,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Publicado em ${formatDateTime(announcement.createdAt)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _publishing ? null : () => _delete(announcement.id),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remover'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nova tarefa',
              hintText: 'Ex.: Amanha manutencao do Fiorino 01',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _targetDriverId,
            decoration: const InputDecoration(
              labelText: 'Destinar para',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Todos os motoristas cadastrados'),
              ),
              ...drivers.map(
                (driver) => DropdownMenuItem<String?>(
                  value: driver.id,
                  child: Text(driver.name),
                ),
              ),
            ],
            onChanged: _publishing ? null : (value) => setState(() => _targetDriverId = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _publishing ? null : _pickExpiryDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_expiresAt == null ? 'Data de validade (opcional)' : formatDate(_expiresAt)),
                ),
              ),
              if (_expiresAt != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _publishing ? null : () => setState(() => _expiresAt = null),
                  icon: const Icon(Icons.clear),
                  tooltip: 'Remover validade',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: const Icon(Icons.task_alt_outlined),
            label: Text(_publishing ? 'Publicando...' : 'PUBLICAR TAREFA'),
          ),
        ],
      ),
    );
  }
}
