# Estructura de la BBDD (SQLite)

La app usa **SQLite** con un esquema **clave‑valor**. No hay tablas relacionales adicionales.

**Archivo**
- Nombre: `aris.db`
- Ubicación: `getDatabasesPath()` (ruta interna del sistema)
- Versión de esquema: `1`

## Tablas

**Tabla: `kv`**  
Almacén clave‑valor único para todo el estado de la app.

Campos:
- `key` (TEXT, **PRIMARY KEY**)
- `value` (TEXT, **NOT NULL**)

## Convenciones de almacenamiento

El campo `value` siempre es un **String**.  
Cuando el dato es estructurado, se guarda como **JSON serializado**.

## Claves principales y formato

**`ai_provider_settings`**  
JSON con la configuración del proveedor de IA.
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
JSON con listas y asignaciones.
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

**`youtube_quota_state`**  
JSON con consumo de cuota diaria.
```json
{
  "date": "YYYY-MM-DD",
  "used": 123,
  "breakdown": {
    "videos.list": 50,
    "channels.list": 10
  }
}
```

**`ai_cost_state`**  
JSON con coste diario (micro‑unidades).
```json
{
  "date": "YYYY-MM-DD",
  "microCost": 123456,
  "breakdown": {
    "gpt-5-mini": 90000
  }
}
```

**`ai_cost_history`**  
JSON con histórico por fecha.
```json
{
  "YYYY-MM-DD": {
    "microCost": 123456,
    "breakdown": { "gpt-5-mini": 90000 }
  }
}
```

**`sftp_settings`**  
JSON con la configuración SFTP.
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
JSON con valor cacheado y expiración (epoch ms).
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
- El esquema es intencionadamente simple: toda la app persiste a través de `kv`.
- Los backups/importaciones por SFTP trabajan con el archivo `.db` completo.
