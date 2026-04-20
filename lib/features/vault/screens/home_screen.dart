import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../core/theme.dart';
import '../../../core/autofill_service.dart';
import '../../../core/models/entry_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/vault_provider.dart';
import '../widgets/group_card.dart';
import '../widgets/entry_list_tile.dart';
import 'group_screen.dart';
import 'entry_edit_screen.dart';
import '../../generator/generator_screen.dart';
import '../../health/health_screen.dart';
import '../../backup/backup_screen.dart';
import '../../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Load vault first, then check for pending autofill saves so groups are
    // guaranteed to be available when the save handler runs.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<VaultProvider>().loadAll();
      await AutofillService.checkPendingSave();
    });

    // Listen for notification taps that request navigation to the Health tab.
    NotificationService.routeNotifier.addListener(_onNotificationRoute);
    _handlePendingRoute(NotificationService.routeNotifier.value);

    // Listen for autofill save requests (credentials captured from a login form).
    AutofillService.saveNotifier.addListener(_onAutofillSave);
  }

  @override
  void dispose() {
    NotificationService.routeNotifier.removeListener(_onNotificationRoute);
    AutofillService.saveNotifier.removeListener(_onAutofillSave);
    _searchController.dispose();
    super.dispose();
  }

  void _onNotificationRoute() {
    _handlePendingRoute(NotificationService.routeNotifier.value);
  }

  void _onAutofillSave() async {
    final data = AutofillService.saveNotifier.value;
    if (data == null) return;
    AutofillService.saveNotifier.value = null;
    if (!mounted) return;

    final vault = context.read<VaultProvider>();

    // Ensure vault data is loaded before saving.
    if (vault.groups.isEmpty) await vault.loadAll();
    if (!mounted || vault.groups.isEmpty) return;

    // Derive a sensible title from URL or package name.
    final rawTitle = (data['title'] ?? '').trim();
    final rawUrl   = (data['url']   ?? '').trim();
    final username = data['username'] ?? '';
    final password = data['password'] ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : rawUrl.isNotEmpty
            ? rawUrl.replaceAll(RegExp(r'^https?://'), '').split('/').first
            : 'Nueva entrada';

    // ── Browser fallback ────────────────────────────────────────────────────
    // Chrome/Brave don't expose manually-typed values to Android AutofillService.
    // If the password is empty we open the entry-creation screen pre-filled with
    // the domain so the user can enter the credentials once and save them.
    if (password.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EntryEditScreen(
            groupId:         vault.groups.first.id,
            initialTitle:    title,
            initialUsername: username,
            initialUrl:      rawUrl,
          ),
        ),
      );
      return;
    }

    // ── Auto-save when all values are available ─────────────────────────────
    final entry = EntryModel(
      groupId:  vault.groups.first.id,
      title:    title,
      username: username,
      password: password,
      url:      rawUrl,
    );

    await vault.addEntry(entry);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Contraseña guardada: $title',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: VoltTheme.success,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handlePendingRoute(String? route) {
    if (route == null) return;
    // Reset immediately so the listener doesn't fire again on re-render.
    NotificationService.routeNotifier.value = null;
    // Tab 3 is the Health / Seguridad screen.
    if (mounted) setState(() => _tabIndex = 3);
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    context.read<VaultProvider>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeSearch,
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: VoltTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Buscar entradas...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (q) => vault.search(q),
              )
            : _tabTitle(),
        actions: [
          if (!_searching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _openSearch,
            ),
          if (!_searching)
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/groups/icon_block.svg',
                width: 22,
                height: 22,
              ),
              onPressed: () {
                vault.clear();
                auth.lock();
              },
              tooltip: 'Bloquear',
            ),
        ],
      ),
      body: _searching
          ? _buildSearchResults(vault)
          : IndexedStack(
              index: _tabIndex,
              children: [
                _buildVaultTab(vault),
                _buildFavoritesTab(vault),
                const GeneratorScreen(),
                const HealthScreen(),
              ],
            ),
      floatingActionButton: (_tabIndex == 0 || _tabIndex == 1) && !_searching
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EntryEditScreen(
                    groupId: vault.groups.isNotEmpty
                        ? vault.groups.first.id
                        : '',
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Favoritos',
          ),
          NavigationDestination(
            icon: Icon(Icons.casino_outlined),
            selectedIcon: Icon(Icons.casino),
            label: 'Generador',
          ),
          NavigationDestination(
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety),
            label: 'Seguridad',
          ),
        ],
      ),
      drawer: _buildDrawer(context, vault, auth),
    );
  }

  Widget _tabTitle() {
    switch (_tabIndex) {
      case 0:
        return const Text('KMD Volt');
      case 1:
        return const Text('Favoritos');
      case 2:
        return const Text('Generador');
      case 3:
        return const Text('Seguridad');
      default:
        return const Text('KMD Volt');
    }
  }

  Widget _buildSearchResults(VaultProvider vault) {
    if (_searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Escribe para buscar',
          style: TextStyle(color: VoltTheme.textMuted),
        ),
      );
    }
    if (vault.searchResults.isEmpty) {
      return const Center(
        child: Text(
          'Sin resultados',
          style: TextStyle(color: VoltTheme.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: vault.searchResults.length,
      itemBuilder: (context, i) {
        final entry = vault.searchResults[i];
        return EntryListTile(
          entry: entry,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EntryEditScreen(entry: entry),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVaultTab(VaultProvider vault) {
    if (vault.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: vault.loadAll,
      color: VoltTheme.primary,
      child: CustomScrollView(
        slivers: [
          // Stats bar
          SliverToBoxAdapter(
            child: _buildStatsBar(vault),
          ),

          // Groups header
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(
                'CATEGORÍAS',
                style: TextStyle(
                  color: VoltTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          // Groups grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final group = vault.groups[i];
                  return GroupCard(
                    group: group,
                    count: vault.entryCountForGroup(group.id),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupScreen(group: group),
                      ),
                    ),
                  );
                },
                childCount: vault.groups.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
            ),
          ),

          // Recent header
          if (vault.entries.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
                child: Text(
                  'RECIENTES',
                  style: TextStyle(
                    color: VoltTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

          // Recent entries (last 5)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final entry = vault.entries
                    .take(5)
                    .toList()[i];
                return EntryListTile(
                  entry: entry,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntryEditScreen(entry: entry),
                    ),
                  ),
                );
              },
              childCount: vault.entries.take(5).length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildStatsBar(VaultProvider vault) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoltTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VoltTheme.border),
      ),
      child: Row(
        children: [
          _statItem(vault.entries.length.toString(), 'Entradas'),
          _divider(),
          _statItem(vault.groups.length.toString(), 'Grupos'),
          _divider(),
          _statItem(vault.favorites.length.toString(), 'Favoritos'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: VoltTheme.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: VoltTheme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 32,
      width: 1,
      color: VoltTheme.border,
    );
  }

  Widget _buildFavoritesTab(VaultProvider vault) {
    final favs = vault.favorites;
    if (favs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline, color: VoltTheme.textMuted, size: 48),
            SizedBox(height: 12),
            Text(
              'Sin favoritos',
              style: TextStyle(color: VoltTheme.textMuted, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Marca entradas con ★ para verlas aquí',
              style: TextStyle(color: VoltTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favs.length,
      itemBuilder: (context, i) => EntryListTile(
        entry: favs[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EntryEditScreen(entry: favs[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    VaultProvider vault,
    AuthProvider auth,
  ) {
    return Drawer(
      backgroundColor: VoltTheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: VoltTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: VoltTheme.primary.withOpacity(0.3)),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/groups/icon_block.svg',
                      width: 22,
                      height: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KMD Volt',
                        style: TextStyle(
                          color: VoltTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Gestor de contraseñas',
                        style: TextStyle(
                          color: VoltTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),

            _drawerItem(
              icon: Icons.backup_outlined,
              label: 'Respaldo y restaurar',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackupScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),

            const Spacer(),
            const Divider(),
            _drawerLockItem(
              onTap: () {
                Navigator.pop(context);
                vault.clear();
                auth.lock();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? VoltTheme.textSecondary, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? VoltTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _drawerLockItem({required VoidCallback onTap}) {
    return ListTile(
      leading: SvgPicture.asset(
        'assets/icons/groups/icon_block.svg',
        width: 22,
        height: 22,
      ),
      title: const Text(
        'Bloquear vault',
        style: TextStyle(
          color: VoltTheme.danger,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}
