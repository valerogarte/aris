# ARIS

ARIS es una app Flutter para consultar tus suscripciones de YouTube, abrir el detalle de cada vídeo y generar resúmenes con IA, además de escuchar el contenido con un narrador (TTS).

**Funciones principales**
- Feed con el último vídeo de cada canal suscrito, ordenado por fecha.
- Detalle de vídeo con reproductor, transcripción, resumen IA y preguntas para profundizar.
- Narrador TTS configurable que lee resumen y preguntas.
- Página de canal con los últimos vídeos y paginación al hacer scroll.
- Listas locales de canales con iconos personalizados.
- Importar y exportar backups por SFTP en formato `.db`.

## Mapa visual de pantallas

```mermaid
flowchart TD
  A[Login] -->|Google Sign-In| B[Home / Tabs]
  B --> C[Suscripciones]
  B --> D[Explorar]
  B --> E[Canales]
  B --> I[Perfil]
  C --> F[Detalle de vídeo]
  F --> J[Canal]
  E --> G[Gestionar listas]
  E --> H[Asignar listas]
```

## Páginas (tabla rápida)

| Pantalla | Qué muestra | Acciones clave | Archivo |
| --- | --- | --- | --- |
| Login | Acceso con Google y estados de carga/error | Iniciar sesión | `lib/screens/login_screen.dart` |
| Home / Tabs | Contenedor con navegación y chips de cuota/coste | Cambiar pestañas, abrir perfil | `lib/main.dart` |
| Suscripciones | Lista de vídeos recientes | Refrescar, abrir detalle | `lib/screens/videos_screen.dart` |
| Detalle de vídeo | Reproductor + resumen IA + preguntas | Elegir pista, resumir, narrar | `lib/screens/video_detail_screen.dart` |
| Canal | Últimos vídeos de un canal | Scroll infinito | `lib/screens/channel_videos_screen.dart` |
| Canales | Suscripciones y listas locales | Crear/editar listas, asignar canales | `lib/screens/lists_screen.dart` |
| Explorar | Placeholder | Ninguna | `lib/screens/explore_screen.dart` |
| Perfil | Configuración IA, voz TTS y SFTP | Guardar claves, importar/exportar | `lib/screens/profile_screen.dart` |

## Persistencia de datos (local)

La app usa **SQLite** con un esquema clave‑valor. Toda la información se guarda en `aris.db`. El detalle de tablas y campos está en `docs/bbdd.md`.

## Backups

Los backups por SFTP exportan e importan el **archivo completo `.db`**. No se admiten JSONs.

## Cuota (estimada)

La app muestra una **cuota local estimada** para YouTube Data API. Es una referencia interna y no equivale a la cuota oficial de Google.

## Setup (Android)

1. Crea credenciales OAuth 2.0 para Android en Google Cloud Console. Usa el package name `com.aris` (o cambia `applicationId` en `android/app/build.gradle.kts`).
2. Obtén el SHA‑1 de tu keystore debug con:
   ```
   keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
3. Activa **YouTube Data API v3** en el mismo proyecto.
4. Descarga `google-services.json` y colócalo en `android/app/google-services.json`.
5. Crea un **Web OAuth Client ID** y, si quieres sobrescribir el ID embebido, ejecuta:
   ```
   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=TU_WEB_CLIENT_ID
   ```

## Run

```
flutter pub get
flutter run
```

## Notas

- Google Sign-In está soportado en Android/iOS/Web. Windows desktop no está soportado.
