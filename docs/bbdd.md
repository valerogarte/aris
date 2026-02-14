# Estructura de la BBDD (SQLite)

La app usa **SQLite** con varias tablas especializadas. La configuración y cachés siguen en **clave‑valor**, mientras que costes, cuota y canales tienen tablas propias.

**Archivo**
- Nombre: `aris.db`
- Ubicación: `getDatabasesPath()` (ruta interna del sistema)
- Versión de esquema: `3`

## Extraer la BBDD por ADB (Android)

Ruta típica en el dispositivo:
- `/data/data/com.aris/databases/aris.db`

Pasos (PowerShell):
```powershell
adb devices
adb shell am force-stop com.aris
adb shell run-as com.aris cp /data/data/com.aris/databases/aris.db /sdcard/aris.db
adb pull /sdcard/aris.db e:\laragon\www\formarse\aris.db
```

Si quieres llevar también los WAL/SHM:
```powershell
adb shell run-as com.aris cp /data/data/com.aris/databases/aris.db-wal /sdcard/aris.db-wal
adb shell run-as com.aris cp /data/data/com.aris/databases/aris.db-shm /sdcard/aris.db-shm
adb pull /sdcard/aris.db-wal e:\laragon\www\formarse\aris.db-wal
adb pull /sdcard/aris.db-shm e:\laragon\www\formarse\aris.db-shm
```

Nota:
- `run-as` solo funciona en builds **debug** o si el dispositivo tiene **root**. Si falla, usa el export por SFTP.

## Tablas

### `kv`
Almacén clave‑valor para configuración y cachés.

Campos:
- `key` (TEXT, **PRIMARY KEY**)
- `value` (TEXT, **NOT NULL**)

### `ai_cost_daily`
Coste de IA por día.

Campos:
- `date` (TEXT, **PRIMARY KEY**, `YYYY-MM-DD`)
- `micro_cost` (INTEGER, **NOT NULL**)

### `ai_cost_breakdown`
Coste por modelo/proveedor y día.

Campos:
- `date` (TEXT, **NOT NULL**)
- `label` (TEXT, **NOT NULL**)
- `micro_cost` (INTEGER, **NOT NULL**)

Clave primaria compuesta: `(date, label)`.

### `youtube_quota_daily`
Consumo de cuota diaria de YouTube.

Campos:
- `date` (TEXT, **PRIMARY KEY**, `YYYY-MM-DD`)
- `used` (INTEGER, **NOT NULL**)

### `youtube_quota_breakdown`
Desglose de cuota por endpoint y día.

Campos:
- `date` (TEXT, **NOT NULL**)
- `label` (TEXT, **NOT NULL**)
- `units` (INTEGER, **NOT NULL**)

Clave primaria compuesta: `(date, label)`.

### `channels`
Información completa de canales suscritos.

Campos:
- `channel_id` (TEXT, **PRIMARY KEY**)
- `title` (TEXT, **NOT NULL**)
- `description` (TEXT)
- `thumbnail_url` (TEXT)
- `published_at` (TEXT)
- `custom_url` (TEXT)
- `country` (TEXT)
- `uploads_playlist_id` (TEXT)
- `subscriber_count` (INTEGER)
- `view_count` (INTEGER)
- `video_count` (INTEGER)
- `raw_json` (TEXT)
- `updated_at` (INTEGER, epoch ms)

### `history_videos`
Historial de vídeos reproducidos o con resumen solicitado.

Campos:
- `video_id` (TEXT, **PRIMARY KEY**)
- `title` (TEXT, **NOT NULL**)
- `channel_id` (TEXT)
- `channel_title` (TEXT)
- `thumbnail_url` (TEXT)
- `published_at` (TEXT)
- `duration_seconds` (INTEGER)
- `watched_at` (INTEGER, epoch ms)
- `summary_requested_at` (INTEGER, epoch ms)
- `last_activity_at` (INTEGER, **NOT NULL**, epoch ms)

## Convenciones de almacenamiento en `kv`

El campo `value` siempre es un **String**. Cuando el dato es estructurado, se guarda como **JSON serializado**.

### Claves principales

**`ai_provider_settings`**
```json
{
  "provider": "ChatGPT",
  "model": "gpt-5-mini",
  "apiKey": "...",
  "narratorVoiceName": "es-es-x-eed-network",
  "narratorVoiceLocale": "es-ES"
}
```

**`subscription_lists_state`**
```json
{
  "lists": [
    { "id": "listId", "name": "Nombre", "iconKey": "label" }
  ],
  "assignments": {
    "listId": ["channelId1", "channelId2"]
  }
}
```

**`sftp_settings`**
```json
{
  "host": "192.168.1.33",
  "port": 322,
  "username": "valerogarte",
  "password": "",
  "remotePath": "/home/Documentos/Aris/"
}
```

**`expiring_cache:<namespace>:<key>`**
```json
{
  "value": "<string>",
  "expiresAt": 1771445831845
}
```
Namespaces usados actualmente:
- `channel_avatars`
- `summaries`
- `transcripts`

## Notas
- Costes, cuota y canales están normalizados en tablas dedicadas.
- El resto de configuración/cachés vive en `kv`.
- Los backups/importaciones por SFTP trabajan con el archivo `.db` completo.
