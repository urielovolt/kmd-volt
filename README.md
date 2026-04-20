<div align="center">
  <img src="assets/icons/app_icon.png" width="100" alt="KMD Volt Logo" />
  <h1>KMD Volt</h1>
  <p>Gestor de contraseñas de código abierto para Android</p>

  ![Android](https://img.shields.io/badge/Android-8.0%2B-brightgreen?logo=android)
  ![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
  ![License](https://img.shields.io/badge/Licencia-MIT-yellow)
  ![Release](https://img.shields.io/github/v/release/urielovolt/kmd-volt)
</div>

---

## ¿Qué es KMD Volt?

KMD Volt es un gestor de contraseñas local, seguro y de código abierto para Android. Almacena tus credenciales cifradas directamente en tu dispositivo, sin servidores externos, sin suscripciones, sin rastreo.

---

## Características

| | Funcionalidad |
|---|---|
| 🔐 | **Cifrado AES-256** a nivel de campo (GCM/CBC) con clave derivada por PBKDF2 |
| 🤳 | **Autenticación** por huella dactilar, PIN o contraseña maestra |
| 🤖 | **Autofill nativo** para Android — rellena formularios en apps y navegadores |
| 🎲 | **Generador de contraseñas** configurable (longitud, símbolos, números) |
| 🛡️ | **Pantalla de salud** — detecta contraseñas débiles, reutilizadas y antiguas |
| 💾 | **Respaldo y restauración** cifrada en formato JSON |
| 🔔 | **Notificaciones periódicas** para contraseñas que llevan mucho tiempo sin cambiar |
| 📋 | **Portapapeles seguro** con auto-limpieza automática |
| 🌙 | **Tema oscuro** con bloqueo de capturas de pantalla |

---

## Capturas de pantalla

> *Próximamente*

---

## Instalación

### Opción A — Descargar APK (recomendado)

1. Ve a [**Releases**](https://github.com/urielovolt/kmd-volt/releases)
2. Descarga el archivo `KMD-Volt-vX.X.X.apk`
3. En tu Android: **Ajustes → Seguridad → Instalar apps de fuentes desconocidas**
4. Abre el APK descargado e instala

### Opción B — Compilar desde el código fuente

**Requisitos previos:**
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x
- Android SDK (API 26+)
- Java 17+

```bash
# Clonar el repositorio
git clone https://github.com/urielovolt/kmd-volt.git
cd kmd-volt

# Instalar dependencias
flutter pub get

# Compilar APK de release
flutter build apk --release

# El APK estará en:
# build/app/outputs/flutter-apk/app-release.apk
```

---

## Configurar Autofill

Para que KMD Volt rellene contraseñas automáticamente en otras apps:

1. **Ajustes de Android** → **Administración general**
2. **Contraseñas y autocompletar** → **Servicio de autocompletar**
3. Selecciona **KMD Volt**

> Para navegadores basados en Chromium (Brave, Chrome), desactiva también el gestor de contraseñas interno del navegador en su configuración.

---

## Arquitectura

```
lib/
├── core/
│   ├── crypto/          # Cifrado AES-256, PBKDF2
│   ├── database/        # SQLite con cifrado a nivel de campo
│   ├── models/          # EntryModel, GroupModel
│   └── services/        # Autofill, Clipboard, Notifications
├── features/
│   ├── auth/            # Setup, Unlock (biometría + PIN)
│   ├── vault/           # Home, grupos, entradas
│   ├── generator/       # Generador de contraseñas
│   ├── health/          # Análisis de seguridad
│   ├── backup/          # Respaldo y restauración
│   └── settings/        # Configuración
├── providers/           # AuthProvider, VaultProvider
└── widgets/             # Componentes reutilizables

android/
└── app/src/main/kotlin/
    ├── MainActivity.kt          # MethodChannel Flutter ↔ Android
    └── VoltAutofillService.kt   # Android AutofillService
```

---

## Limitaciones conocidas

### Historial de portapapeles del teclado

Al copiar una contraseña, KMD Volt marca el contenido como **sensible** (`EXTRA_IS_SENSITIVE`, Android 13+) y lo borra automáticamente después de 12 segundos. Sin embargo, **algunos teclados de terceros** (como el teclado predeterminado de Xiaomi/HyperOS y otros fabricantes) mantienen su **propio historial de portapapeles independiente** del sistema Android y pueden ignorar esta señal, haciendo que la contraseña siga visible en su panel de "recientes".

Esto **no es un bug de KMD Volt** — es una limitación del sistema Android: no existe ninguna API pública que permita a una app borrar el historial interno de un teclado de terceros.

**Soluciones recomendadas:**

| Opción | Pasos |
|---|---|
| Desactivar historial del teclado | Teclado → ícono portapapeles → Configuración → desactivar "Historial del portapapeles" |
| Usar Gboard | Gboard (teclado de Google) sí respeta `EXTRA_IS_SENSITIVE` y no guarda contraseñas en su historial |
| Usar Autofill | La función de autocompletar de KMD Volt **nunca usa el portapapeles** — inyecta las credenciales directamente en el campo. Es la opción más segura. |

---

## Seguridad

- **Sin servidor**: todos los datos permanecen en el dispositivo
- **Cifrado de campo**: `password` y `notes` se cifran antes de escribirse en la base de datos
- **Android Keystore**: la clave maestra está protegida por el hardware del dispositivo
- **FLAG_SECURE**: el vault no aparece en la vista de apps recientes ni permite capturas de pantalla
- **Auto-bloqueo**: configurable por tiempo de inactividad

---

## Requisitos mínimos

- Android **8.0 (API 26)** o superior
- ~30 MB de espacio de almacenamiento

---

## Contribuir

Las contribuciones son bienvenidas. Por favor abre un *issue* antes de enviar un *pull request* para discutir los cambios propuestos.

1. Haz un fork del repositorio
2. Crea tu rama: `git checkout -b feature/nueva-funcionalidad`
3. Commit: `git commit -m "Agrega nueva funcionalidad"`
4. Push: `git push origin feature/nueva-funcionalidad`
5. Abre un Pull Request

---

## Licencia

Distribuido bajo la licencia **MIT**. Consulta el archivo [`LICENSE`](LICENSE) para más detalles.
