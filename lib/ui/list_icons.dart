import 'package:flutter/material.dart';

class ListIconOption {
  const ListIconOption({required this.key, required this.icon, required this.label});

  final String key;
  final IconData icon;
  final String label;
}

const List<ListIconOption> listIconOptions = [
  ListIconOption(key: '3d', icon: Icons.view_in_ar, label: '3D'),
  ListIconOption(key: 'current', icon: Icons.article, label: 'Actualidad'),
  ListIconOption(key: 'anatomia', icon: Icons.accessibility_new, label: 'Anatomia'),
  ListIconOption(key: 'art', icon: Icons.palette, label: 'Arte'),
  ListIconOption(key: 'science', icon: Icons.science, label: 'Ciencia'),
  ListIconOption(key: 'movie', icon: Icons.movie, label: 'Cine'),
  ListIconOption(key: 'cars', icon: Icons.directions_car, label: 'Coches'),
  ListIconOption(key: 'cooking', icon: Icons.kitchen, label: 'Cocina'),
  ListIconOption(key: 'code', icon: Icons.code, label: 'Codigo'),
  ListIconOption(key: 'food', icon: Icons.restaurant, label: 'Comida'),
  ListIconOption(key: 'body_mind', icon: Icons.self_improvement, label: 'Cuerpo y mente'),
  ListIconOption(key: 'sports', icon: Icons.sports_soccer, label: 'Deportes'),
  ListIconOption(key: 'design', icon: Icons.design_services, label: 'Diseño'),
  ListIconOption(key: 'school', icon: Icons.school, label: 'Educacion'),
  ListIconOption(key: 'fitness', icon: Icons.fitness_center, label: 'Fitness'),
  ListIconOption(key: 'photography', icon: Icons.photo_camera, label: 'Fotografia'),
  ListIconOption(key: 'freak', icon: Icons.videogame_asset, label: 'Freak'),
  ListIconOption(key: 'label', icon: Icons.label, label: 'General'),
  ListIconOption(key: 'history', icon: Icons.history_edu, label: 'Historia'),
  ListIconOption(key: 'antamia', icon: Icons.eco, label: 'Hoja'),
  ListIconOption(key: 'ai', icon: Icons.smart_toy, label: 'IA'),
  ListIconOption(key: 'english', icon: Icons.translate, label: 'Ingles'),
  ListIconOption(key: 'book', icon: Icons.menu_book, label: 'Lecturas'),
  ListIconOption(key: 'magic', icon: Icons.auto_awesome, label: 'Magic'),
  ListIconOption(key: 'environment', icon: Icons.landscape, label: 'Medio Ambiente'),
  ListIconOption(key: 'fashion', icon: Icons.checkroom, label: 'Moda'),
  ListIconOption(key: 'world', icon: Icons.public, label: 'Mundo'),
  ListIconOption(key: 'music', icon: Icons.music_note, label: 'Musica'),
  ListIconOption(key: 'nature', icon: Icons.park, label: 'Naturaleza'),
  ListIconOption(key: 'business', icon: Icons.business_center, label: 'Negocios'),
  ListIconOption(key: 'news', icon: Icons.article, label: 'Noticias'),
  ListIconOption(key: 'podcast', icon: Icons.mic, label: 'Podcast'),
  ListIconOption(key: 'health', icon: Icons.local_hospital, label: 'Salud'),
  ListIconOption(key: 'technology', icon: Icons.computer, label: 'Tecnologia'),
  ListIconOption(key: 'music_theory', icon: Icons.graphic_eq, label: 'Teoria musical'),
  ListIconOption(key: 'work', icon: Icons.work, label: 'Trabajo'),
  ListIconOption(key: 'travel', icon: Icons.flight_takeoff, label: 'Viajes'),
];

IconData iconForListKey(String iconKey) {
  final option = listIconOptions.firstWhere((item) => item.key == iconKey, orElse: () => listIconOptions.first);
  return option.icon;
}
