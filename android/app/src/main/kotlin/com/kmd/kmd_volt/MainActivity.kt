package com.kmd.kmd_volt

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import android.service.autofill.Dataset

class MainActivity : FlutterFragmentActivity() {

    private val AUTOFILL_CHANNEL   = "com.kmd.kmd_volt/autofill"
    private val SECURITY_CHANNEL   = "com.kmd.kmd_volt/security"
    private val CLIPBOARD_CHANNEL  = "com.kmd.kmd_volt/clipboard"
    private val SECURITY_PREFS     = "kmd_security_prefs"

    companion object {
        private const val REQ_NOTIFICATION_PERMISSION = 1001
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        // If this is an autofill authentication intent and the vault is already
        // unlocked (e.g. the app was running in the background), complete the fill
        // immediately without waiting for Flutter to call syncVaultEntries.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            intent.getBooleanExtra(VoltAutofillService.AUTOFILL_AUTH_KEY, false)
        ) {
            val prefs = getEncryptedPrefs(this, VoltAutofillService.PREFS_NAME)
            if (!prefs.getBoolean(VoltAutofillService.LOCKED_KEY, true)) {
                val entriesJson =
                    prefs.getString(VoltAutofillService.ENTRIES_KEY, "[]") ?: "[]"
                completeAutofillIfNeeded(entriesJson)
            }
            // If locked, Flutter will call syncVaultEntries after the user
            // authenticates, which in turn calls completeAutofillIfNeeded.
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Apply FLAG_SECURE on startup based on stored preference (default: enabled).
        // This prevents the vault from appearing in the recent-apps thumbnail and
        // blocks screenshots / screen recording at the OS level.
        val prefs = getEncryptedPrefs(this, SECURITY_PREFS)
        if (prefs.getBoolean("secure_screen", true)) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }

        // Request POST_NOTIFICATIONS permission on Android 13+ (API 33).
        // Without this permission, no notifications will be delivered on those devices.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATION_PERMISSION
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Autofill channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOFILL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Flutter calls this to push vault entries into SharedPreferences
                    // so the autofill service can read them without needing the app open.
                    // If the activity was launched via an autofill authentication PendingIntent
                    // (i.e. the "Unlock to fill" dataset was tapped while the vault was locked),
                    // we also complete the autofill response here so Android fills the target
                    // fields immediately without the user having to switch back manually.
                    "syncVaultEntries" -> {
                        val entriesJson = call.argument<String>("entries") ?: "[]"
                        val prefs = getEncryptedPrefs(
                            this, VoltAutofillService.PREFS_NAME
                        )
                        prefs.edit()
                            .putString(VoltAutofillService.ENTRIES_KEY, entriesJson)
                            .putBoolean(VoltAutofillService.LOCKED_KEY, false)
                            .apply()

                        // Complete the autofill authentication result if needed.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            completeAutofillIfNeeded(entriesJson)
                        }

                        result.success(true)
                    }

                    // Flutter calls this on lock to mark vault as locked
                    "lockVault" -> {
                        val prefs = getEncryptedPrefs(
                            this, VoltAutofillService.PREFS_NAME
                        )
                        prefs.edit()
                            .putBoolean(VoltAutofillService.LOCKED_KEY, true)
                            .remove(VoltAutofillService.ENTRIES_KEY)
                            .apply()
                        result.success(true)
                    }

                    // Check if KMD Volt is set as the system autofill provider
                    "isAutofillEnabled" -> {
                        val enabled = isAutofillServiceEnabled()
                        result.success(enabled)
                    }

                    // Open Android autofill settings so user can select KMD Volt
                    "openAutofillSettings" -> {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE
                        ).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    // Flutter calls this on startup / resume to retrieve pending
                    // autofill save data (credentials captured by onSaveRequest).
                    // Data is persisted in EncryptedSharedPreferences so it
                    // survives process death between the service callback and the
                    // Flutter engine becoming ready.
                    // Returns a non-null map when a save is pending, null otherwise.
                    "getPendingAutofillSave" -> {
                        val savePrefs = getEncryptedPrefs(
                            this, VoltAutofillService.PENDING_SAVE_PREFS
                        )
                        if (savePrefs.getBoolean(VoltAutofillService.HAS_PENDING, false)) {
                            val data = mapOf(
                                "title"    to (savePrefs.getString(VoltAutofillService.PENDING_TITLE,    "") ?: ""),
                                "username" to (savePrefs.getString(VoltAutofillService.PENDING_USERNAME, "") ?: ""),
                                "password" to (savePrefs.getString(VoltAutofillService.PENDING_PASSWORD, "") ?: ""),
                                "url"      to (savePrefs.getString(VoltAutofillService.PENDING_URL,      "") ?: ""),
                            )
                            // Clear after delivery so it is only consumed once.
                            savePrefs.edit()
                                .remove(VoltAutofillService.PENDING_TITLE)
                                .remove(VoltAutofillService.PENDING_USERNAME)
                                .remove(VoltAutofillService.PENDING_PASSWORD)
                                .remove(VoltAutofillService.PENDING_URL)
                                .putBoolean(VoltAutofillService.HAS_PENDING, false)
                                .apply()
                            result.success(data)
                        } else {
                            result.success(null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Security channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Enable or disable FLAG_SECURE (prevent screenshots)
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val prefs = getEncryptedPrefs(this, SECURITY_PREFS)
                        prefs.edit().putBoolean("secure_screen", enabled).apply()
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }

                    // Query the current FLAG_SECURE state
                    "isSecureScreen" -> {
                        val prefs = getEncryptedPrefs(this, SECURITY_PREFS)
                        result.success(prefs.getBoolean("secure_screen", true))
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Clipboard channel ─────────────────────────────────────────────────
        // Provides a real clearPrimaryClip() call rather than the Flutter
        // workaround of writing an empty string (which leaves a visible blank
        // entry in clipboard history managers).
        // Also provides copySecure() which marks content as sensitive so that
        // keyboard apps (Gboard etc.) hide it from their clipboard history.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                when (call.method) {
                    "clearClipboard" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            cm.clearPrimaryClip()
                        } else {
                            cm.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                        result.success(true)
                    }

                    // Copies [text] to the clipboard and marks it as sensitive.
                    // On Android 13+ (API 33) the ClipDescription.EXTRA_IS_SENSITIVE
                    // flag tells keyboard apps and the system clipboard UI to hide
                    // the content from history / previews.
                    // On older API levels a normal copy is performed (no workaround
                    // exists for keyboard clipboard history on those versions).
                    "copySecure" -> {
                        val text = call.argument<String>("text") ?: ""
                        val clip = ClipData.newPlainText("", text)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            clip.description.extras =
                                android.os.PersistableBundle().apply {
                                    putBoolean(
                                        android.content.ClipDescription.EXTRA_IS_SENSITIVE,
                                        true
                                    )
                                }
                        }
                        cm.setPrimaryClip(clip)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isAutofillServiceEnabled(): Boolean {
        return try {
            val afm = getSystemService(AutofillManager::class.java)
            afm?.hasEnabledAutofillServices() == true
        } catch (e: Exception) {
            false
        }
    }

    // ── Autofill authentication result ────────────────────────────────────────

    /**
     * Called after [syncVaultEntries] when the vault has just been unlocked.
     *
     * If this Activity was started by the autofill service's authentication
     * PendingIntent (i.e. the user tapped "Unlock to fill"), the launching
     * intent contains the target [AutofillId]s and context extras.  We build
     * a filled [Dataset] and return it via [setResult] so that Android can
     * immediately inject the credentials into the requesting app.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun completeAutofillIfNeeded(entriesJson: String) {
        val extras = intent?.extras ?: return
        if (!extras.getBoolean(VoltAutofillService.AUTOFILL_AUTH_KEY, false)) return

        // Retrieve the parcelable AutofillId extras (API changed in API 33).
        val usernameId: AutofillId? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(
                    VoltAutofillService.AUTOFILL_USERNAME_ID_KEY,
                    AutofillId::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable(VoltAutofillService.AUTOFILL_USERNAME_ID_KEY)
            }
        val passwordId: AutofillId? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(
                    VoltAutofillService.AUTOFILL_PASSWORD_ID_KEY,
                    AutofillId::class.java
                )
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable(VoltAutofillService.AUTOFILL_PASSWORD_ID_KEY)
            }

        // Nothing to fill if no field IDs were provided.
        if (usernameId == null && passwordId == null) return

        val webDomain = extras.getString(VoltAutofillService.AUTOFILL_WEB_DOMAIN_KEY, "") ?: ""
        val pkgName   = extras.getString(VoltAutofillService.AUTOFILL_PKG_NAME_KEY,   "") ?: ""

        // Pick the best matching vault entry for the target app/site.
        val entry = findBestAutofillEntry(entriesJson, webDomain, pkgName)

        // Build a presentation label shown briefly while the value is injected.
        val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_title,    entry?.title    ?: "KMD Volt")
            setTextViewText(R.id.autofill_subtitle, entry?.username ?: "")
            setImageViewResource(R.id.autofill_icon, R.drawable.ic_volt)
        }

        val datasetBuilder = Dataset.Builder()
        if (usernameId != null) {
            datasetBuilder.setValue(
                usernameId,
                AutofillValue.forText(entry?.username ?: ""),
                presentation
            )
        }
        if (passwordId != null) {
            datasetBuilder.setValue(
                passwordId,
                AutofillValue.forText(entry?.password ?: ""),
                presentation
            )
        }

        val replyIntent = Intent()
            .putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, datasetBuilder.build())
        setResult(RESULT_OK, replyIntent)
        finish()
    }

    /** Simple data holder for a vault entry used during autofill result construction. */
    private data class AutofillEntry(
        val title: String,
        val username: String,
        val password: String,
        val url: String
    )

    // ── Encrypted prefs helper ────────────────────────────────────────────────

    /**
     * Returns an [EncryptedSharedPreferences] instance backed by AES-256-GCM
     * (values) and AES-256-SIV (keys), using a master key held in the Android
     * Keystore.  Drop-in replacement for [getSharedPreferences].
     */
    private fun getEncryptedPrefs(
        context: Context,
        name: String
    ): android.content.SharedPreferences {
        val masterKey = MasterKey.Builder(context, "kmd_volt_master_key")
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            name,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    /**
     * Parses [json] (same format written by [syncVaultEntries]) and returns the
     * entry that best matches [webDomain] / [pkgName], or the first entry if
     * nothing matches.
     */
    private fun findBestAutofillEntry(
        json: String,
        webDomain: String,
        pkgName: String
    ): AutofillEntry? {
        return try {
            val arr = JSONArray(json)
            val entries = (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                AutofillEntry(
                    title    = obj.optString("title"),
                    username = obj.optString("username"),
                    password = obj.optString("password"),
                    url      = obj.optString("url"),
                )
            }
            if (entries.isEmpty()) return null

            when {
                webDomain.isNotEmpty() -> {
                    // Prefer an entry whose stored URL or title mentions the domain.
                    entries.firstOrNull {
                        it.url.contains(webDomain, ignoreCase = true) ||
                        it.title.contains(webDomain, ignoreCase = true)
                    } ?: run {
                        // Fall back to package-name stem match, then first entry.
                        if (pkgName.isNotEmpty()) {
                            val stem = pkgName.substringAfterLast('.')
                            entries.firstOrNull {
                                it.title.contains(stem, ignoreCase = true) ||
                                it.url.contains(stem, ignoreCase = true)
                            }
                        } else null
                    } ?: entries.first()
                }
                pkgName.isNotEmpty() -> {
                    val stem = pkgName.substringAfterLast('.')
                    entries.firstOrNull {
                        it.title.contains(stem,    ignoreCase = true) ||
                        it.url.contains(stem,      ignoreCase = true) ||
                        it.url.contains(pkgName,   ignoreCase = true)
                    } ?: entries.first()
                }
                else -> entries.first()
            }
        } catch (e: Exception) {
            null
        }
    }
}
