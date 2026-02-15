import 'package:flutter/material.dart';

class ListIconOption {
  const ListIconOption({
    required this.key,
    required this.icon,
    required this.label,
  });

  final String key;
  final IconData icon;
  final String label;
}

class ListIconCategory {
  const ListIconCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.options,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<ListIconOption> options;
}

const List<ListIconCategory> listIconCategories = [
  ListIconCategory(
    id: 'general',
    label: 'General',
    icon: Icons.label,
    options: [
      ListIconOption(key: 'label', icon: Icons.label, label: 'General'),
      ListIconOption(key: 'current', icon: Icons.article, label: 'Actualidad'),
      ListIconOption(key: 'news', icon: Icons.article, label: 'Noticias'),
      ListIconOption(key: 'bookmark', icon: Icons.bookmark, label: 'Marcador'),
      ListIconOption(key: 'star', icon: Icons.star, label: 'Favoritos'),
      ListIconOption(key: 'flag', icon: Icons.flag, label: 'Objetivos'),
      ListIconOption(key: 'pin', icon: Icons.push_pin, label: 'Fijado'),
      ListIconOption(key: 'checklist', icon: Icons.checklist, label: 'Checklist'),
      ListIconOption(key: 'ideas', icon: Icons.lightbulb, label: 'Ideas'),
      ListIconOption(key: 'new', icon: Icons.new_releases, label: 'Novedades'),
      ListIconOption(key: 'event', icon: Icons.event, label: 'Eventos'),
      ListIconOption(key: 'favorite', icon: Icons.favorite, label: 'Favorito'),
    ],
  ),
  ListIconCategory(
    id: 'knowledge',
    label: 'Conocimiento',
    icon: Icons.school,
    options: [
      ListIconOption(key: 'school', icon: Icons.school, label: 'Educacion'),
      ListIconOption(key: 'book', icon: Icons.menu_book, label: 'Lecturas'),
      ListIconOption(key: 'history', icon: Icons.history_edu, label: 'Historia'),
      ListIconOption(key: 'science', icon: Icons.science, label: 'Ciencia'),
      ListIconOption(key: 'anatomia', icon: Icons.accessibility_new, label: 'Anatomia'),
      ListIconOption(key: 'english', icon: Icons.translate, label: 'Ingles'),
      ListIconOption(key: 'language', icon: Icons.language, label: 'Lenguas'),
      ListIconOption(key: 'math', icon: Icons.calculate, label: 'Matematicas'),
      ListIconOption(key: 'psychology', icon: Icons.psychology, label: 'Psicologia'),
      ListIconOption(key: 'world', icon: Icons.public, label: 'Mundo'),
      ListIconOption(key: 'fact', icon: Icons.fact_check, label: 'Datos'),
      ListIconOption(key: 'quiz', icon: Icons.quiz, label: 'Quiz'),
    ],
  ),
  ListIconCategory(
    id: 'technology',
    label: 'Tecnologia',
    icon: Icons.computer,
    options: [
      ListIconOption(key: 'technology', icon: Icons.computer, label: 'Tecnologia'),
      ListIconOption(key: 'code', icon: Icons.code, label: 'Codigo'),
      ListIconOption(key: 'ai', icon: Icons.smart_toy, label: 'IA'),
      ListIconOption(key: 'hardware', icon: Icons.memory, label: 'Hardware'),
      ListIconOption(key: 'devices', icon: Icons.devices, label: 'Dispositivos'),
      ListIconOption(key: 'phone', icon: Icons.phone_iphone, label: 'Movil'),
      ListIconOption(key: 'wifi', icon: Icons.wifi, label: 'WiFi'),
      ListIconOption(key: 'security', icon: Icons.security, label: 'Seguridad'),
      ListIconOption(key: 'cloud', icon: Icons.cloud, label: 'Cloud'),
      ListIconOption(key: 'storage', icon: Icons.storage, label: 'Datos'),
      ListIconOption(key: 'bug', icon: Icons.bug_report, label: 'Debug'),
      ListIconOption(key: 'build', icon: Icons.build, label: 'Build'),
    ],
  ),
  ListIconCategory(
    id: 'creativity',
    label: 'Creatividad',
    icon: Icons.palette,
    options: [
      ListIconOption(key: 'art', icon: Icons.palette, label: 'Arte'),
      ListIconOption(key: 'design', icon: Icons.design_services, label: 'Diseno'),
      ListIconOption(key: 'photography', icon: Icons.photo_camera, label: 'Fotografia'),
      ListIconOption(key: 'camera', icon: Icons.camera_alt, label: 'Camara'),
      ListIconOption(key: 'brush', icon: Icons.brush, label: 'Pintar'),
      ListIconOption(key: 'color', icon: Icons.color_lens, label: 'Color'),
      ListIconOption(key: 'edit', icon: Icons.edit, label: 'Edicion'),
      ListIconOption(key: 'draw', icon: Icons.draw, label: 'Dibujo'),
      ListIconOption(key: 'style', icon: Icons.style, label: 'Estilo'),
      ListIconOption(key: 'magic', icon: Icons.auto_awesome, label: 'Magic'),
      ListIconOption(key: '3d', icon: Icons.view_in_ar, label: '3D'),
      ListIconOption(key: 'design_tools', icon: Icons.auto_fix_high, label: 'Herramientas'),
    ],
  ),
  ListIconCategory(
    id: 'media',
    label: 'Media',
    icon: Icons.movie,
    options: [
      ListIconOption(key: 'movie', icon: Icons.movie, label: 'Cine'),
      ListIconOption(key: 'music', icon: Icons.music_note, label: 'Musica'),
      ListIconOption(key: 'music_theory', icon: Icons.graphic_eq, label: 'Teoria musical'),
      ListIconOption(key: 'podcast', icon: Icons.mic, label: 'Podcast'),
      ListIconOption(key: 'mic', icon: Icons.mic, label: 'Audio'),
      ListIconOption(key: 'tv', icon: Icons.live_tv, label: 'TV'),
      ListIconOption(key: 'headphones', icon: Icons.headphones, label: 'Audio pro'),
      ListIconOption(key: 'theater', icon: Icons.theaters, label: 'Teatro'),
      ListIconOption(key: 'play', icon: Icons.play_circle, label: 'Play'),
      ListIconOption(key: 'radio', icon: Icons.radio, label: 'Radio'),
      ListIconOption(key: 'video', icon: Icons.video_library, label: 'Video'),
      ListIconOption(key: 'camera_roll', icon: Icons.video_collection, label: 'Coleccion'),
    ],
  ),
  ListIconCategory(
    id: 'business',
    label: 'Negocios',
    icon: Icons.business_center,
    options: [
      ListIconOption(key: 'business', icon: Icons.business_center, label: 'Negocios'),
      ListIconOption(key: 'work', icon: Icons.work, label: 'Trabajo'),
      ListIconOption(key: 'analytics', icon: Icons.analytics, label: 'Analitica'),
      ListIconOption(key: 'trending', icon: Icons.trending_up, label: 'Tendencias'),
      ListIconOption(key: 'finance', icon: Icons.account_balance, label: 'Finanzas'),
      ListIconOption(key: 'store', icon: Icons.store, label: 'Tienda'),
      ListIconOption(key: 'shop', icon: Icons.shopping_bag, label: 'Ventas'),
      ListIconOption(key: 'money', icon: Icons.attach_money, label: 'Ingresos'),
      ListIconOption(key: 'invoice', icon: Icons.receipt_long, label: 'Facturas'),
      ListIconOption(key: 'briefcase', icon: Icons.work_outline, label: 'Profesional'),
      ListIconOption(key: 'presentation', icon: Icons.present_to_all, label: 'Presentaciones'),
      ListIconOption(key: 'strategy', icon: Icons.track_changes, label: 'Estrategia'),
    ],
  ),
  ListIconCategory(
    id: 'health',
    label: 'Salud',
    icon: Icons.local_hospital,
    options: [
      ListIconOption(key: 'health', icon: Icons.local_hospital, label: 'Salud'),
      ListIconOption(key: 'medical', icon: Icons.medical_services, label: 'Medico'),
      ListIconOption(key: 'fitness', icon: Icons.fitness_center, label: 'Fitness'),
      ListIconOption(key: 'body_mind', icon: Icons.self_improvement, label: 'Cuerpo y mente'),
      ListIconOption(key: 'spa', icon: Icons.spa, label: 'Spa'),
      ListIconOption(key: 'nutrition', icon: Icons.restaurant, label: 'Nutricion'),
      ListIconOption(key: 'heart', icon: Icons.favorite, label: 'Bienestar'),
      ListIconOption(key: 'medication', icon: Icons.medication, label: 'Medicacion'),
      ListIconOption(key: 'biotech', icon: Icons.biotech, label: 'Biotech'),
      ListIconOption(key: 'health_safe', icon: Icons.health_and_safety, label: 'Prevencion'),
    ],
  ),
  ListIconCategory(
    id: 'sports',
    label: 'Deportes',
    icon: Icons.sports_soccer,
    options: [
      ListIconOption(key: 'sports', icon: Icons.sports_soccer, label: 'Deportes'),
      ListIconOption(key: 'basketball', icon: Icons.sports_basketball, label: 'Basket'),
      ListIconOption(key: 'tennis', icon: Icons.sports_tennis, label: 'Tennis'),
      ListIconOption(key: 'mma', icon: Icons.sports_mma, label: 'MMA'),
      ListIconOption(key: 'esports', icon: Icons.sports_esports, label: 'eSports'),
      ListIconOption(key: 'run', icon: Icons.directions_run, label: 'Running'),
      ListIconOption(key: 'cycle', icon: Icons.directions_bike, label: 'Ciclismo'),
      ListIconOption(key: 'swim', icon: Icons.pool, label: 'Natacion'),
      ListIconOption(key: 'hike', icon: Icons.hiking, label: 'Senderismo'),
      ListIconOption(key: 'trophy', icon: Icons.emoji_events, label: 'Trofeos'),
    ],
  ),
  ListIconCategory(
    id: 'nature',
    label: 'Naturaleza',
    icon: Icons.eco,
    options: [
      ListIconOption(key: 'antamia', icon: Icons.eco, label: 'Hoja'),
      ListIconOption(key: 'nature', icon: Icons.park, label: 'Naturaleza'),
      ListIconOption(key: 'environment', icon: Icons.landscape, label: 'Medio Ambiente'),
      ListIconOption(key: 'mountain', icon: Icons.terrain, label: 'Montana'),
      ListIconOption(key: 'water', icon: Icons.water, label: 'Agua'),
      ListIconOption(key: 'sun', icon: Icons.wb_sunny, label: 'Sol'),
      ListIconOption(key: 'agriculture', icon: Icons.agriculture, label: 'Campo'),
      ListIconOption(key: 'forest', icon: Icons.park, label: 'Bosque'),
      ListIconOption(key: 'filter', icon: Icons.filter_hdr, label: 'Paisaje'),
      ListIconOption(key: 'eco_home', icon: Icons.energy_savings_leaf, label: 'Sostenible'),
    ],
  ),
  ListIconCategory(
    id: 'travel',
    label: 'Viajes',
    icon: Icons.flight_takeoff,
    options: [
      ListIconOption(key: 'travel', icon: Icons.flight_takeoff, label: 'Viajes'),
      ListIconOption(key: 'cars', icon: Icons.directions_car, label: 'Coches'),
      ListIconOption(key: 'map', icon: Icons.map, label: 'Mapa'),
      ListIconOption(key: 'place', icon: Icons.place, label: 'Lugar'),
      ListIconOption(key: 'train', icon: Icons.train, label: 'Tren'),
      ListIconOption(key: 'boat', icon: Icons.directions_boat, label: 'Barco'),
      ListIconOption(key: 'hotel', icon: Icons.hotel, label: 'Hotel'),
      ListIconOption(key: 'explore', icon: Icons.explore, label: 'Explorar'),
      ListIconOption(key: 'airport', icon: Icons.local_airport, label: 'Aeropuerto'),
      ListIconOption(key: 'beach', icon: Icons.beach_access, label: 'Playa'),
    ],
  ),
  ListIconCategory(
    id: 'food',
    label: 'Comida',
    icon: Icons.restaurant,
    options: [
      ListIconOption(key: 'food', icon: Icons.restaurant, label: 'Comida'),
      ListIconOption(key: 'cooking', icon: Icons.kitchen, label: 'Cocina'),
      ListIconOption(key: 'cafe', icon: Icons.local_cafe, label: 'Cafe'),
      ListIconOption(key: 'bar', icon: Icons.local_bar, label: 'Bar'),
      ListIconOption(key: 'pizza', icon: Icons.local_pizza, label: 'Pizza'),
      ListIconOption(key: 'dessert', icon: Icons.cake, label: 'Postres'),
      ListIconOption(key: 'dining', icon: Icons.restaurant_menu, label: 'Menu'),
      ListIconOption(key: 'breakfast', icon: Icons.free_breakfast, label: 'Desayuno'),
    ],
  ),
  ListIconCategory(
    id: 'gaming',
    label: 'Gaming',
    icon: Icons.videogame_asset,
    options: [
      ListIconOption(key: 'freak', icon: Icons.videogame_asset, label: 'Freak'),
      ListIconOption(key: 'gamepad', icon: Icons.gamepad, label: 'Gamepad'),
      ListIconOption(key: 'casino', icon: Icons.casino, label: 'Casino'),
      ListIconOption(key: 'fun', icon: Icons.emoji_emotions, label: 'Diversion'),
      ListIconOption(key: 'trophy_game', icon: Icons.emoji_events, label: 'Logros'),
      ListIconOption(key: 'vr', icon: Icons.vrpano, label: 'VR'),
    ],
  ),
  ListIconCategory(
    id: 'style',
    label: 'Estilo',
    icon: Icons.checkroom,
    options: [
      ListIconOption(key: 'fashion', icon: Icons.checkroom, label: 'Moda'),
      ListIconOption(key: 'weekend', icon: Icons.weekend, label: 'Lifestyle'),
      ListIconOption(key: 'coffee_break', icon: Icons.local_cafe, label: 'Pausa'),
      ListIconOption(key: 'shopping', icon: Icons.shopping_cart, label: 'Compras'),
      ListIconOption(key: 'home', icon: Icons.home, label: 'Hogar'),
      ListIconOption(key: 'cleaning', icon: Icons.cleaning_services, label: 'Limpieza'),
      ListIconOption(key: 'bed', icon: Icons.bed, label: 'Descanso'),
      ListIconOption(key: 'celebration', icon: Icons.celebration, label: 'Celebrar'),
    ],
  ),
];

final List<ListIconOption> listIconOptions = [
  for (final category in listIconCategories) ...category.options,
];

ListIconOption optionForListKey(String iconKey) {
  return listIconOptions.firstWhere(
    (item) => item.key == iconKey,
    orElse: () => listIconOptions.first,
  );
}

String labelForListKey(String iconKey) {
  return optionForListKey(iconKey).label;
}

IconData iconForListKey(String iconKey) {
  return optionForListKey(iconKey).icon;
}
