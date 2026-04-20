package com.kmd.kmd_volt

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.*
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray

@RequiresApi(Build.VERSION_CODES.O)
class VoltAutofillService : AutofillService() {

    companion object {
        const val PREFS_NAME = "kmd_volt_autofill"
        const val ENTRIES_KEY = "autofill_entries"
        const val LOCKED_KEY = "vault_locked"

        // Intent extras used to pass autofill field IDs to MainActivity so it can
        // complete the fill response automatically once the user authenticates.
        const val AUTOFILL_AUTH_KEY        = "autofill_auth"
        const val AUTOFILL_USERNAME_ID_KEY = "autofill_username_id"
        const val AUTOFILL_PASSWORD_ID_KEY = "autofill_password_id"
        const val AUTOFILL_WEB_DOMAIN_KEY  = "autofill_web_domain"
        const val AUTOFILL_PKG_NAME_KEY    = "autofill_pkg_name"

        // EncryptedSharedPreferences used to persist pending save data so that
        // the credentials survive process death between onSaveRequest and when
        // the Flutter engine is ready to consume them.
        const val PENDING_SAVE_PREFS = "kmd_volt_pending_save"
        const val PENDING_TITLE      = "pending_title"
        const val PENDING_USERNAME   = "pending_username"
        const val PENDING_PASSWORD   = "pending_password"
        const val PENDING_URL        = "pending_url"
        const val HAS_PENDING        = "has_pending"

        // Common field name substrings that indicate a username/email field
        val USERNAME_HINTS = setOf(
            "username", "user", "email", "login", "userid", "user_id",
            "account", "phone", "mobile", "correo", "usuario", "telefono",
            "identifier", "id"
        )

        // Common field name substrings that indicate a password field
        val PASSWORD_HINTS = setOf(
            "password", "passwd", "pass", "pwd", "secret", "pin",
            "contraseña", "clave", "passphrase"
        )
    }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
            ?: return callback.onSuccess(null)

        val parser = StructureParser(structure)
        parser.parse()

        val usernameId  = parser.usernameId
        val passwordId  = parser.passwordId
        val webDomain   = parser.webDomain
        val packageName = parser.packageName

        if (usernameId == null && passwordId == null) {
            return callback.onSuccess(null)
        }

        // Build a SaveInfo for every branch so Android always monitors these
        // fields for a save trigger. FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE fires
        // the save UI when the form disappears (i.e. after the user submits).
        val saveIds = listOfNotNull(usernameId, passwordId).toTypedArray()
        val saveInfo = if (saveIds.isNotEmpty()) {
            SaveInfo.Builder(
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                saveIds
            )
            .setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
            .build()
        } else null

        val prefs    = getEncryptedPrefs(this, PREFS_NAME)
        val isLocked = prefs.getBoolean(LOCKED_KEY, true)

        if (isLocked) {
            // ── Locked path ─────────────────────────────────────────────────
            // Show a single "unlock to fill" dataset. The autofill field IDs
            // are embedded in the PendingIntent extras so MainActivity can
            // build and return the fill result after the user authenticates.
            //
            // IMPORTANT: do NOT add FLAG_ACTIVITY_NEW_TASK to the intent.
            // The autofill system fires this PendingIntent via startActivityForResult
            // so it can receive the fill result back.  FLAG_ACTIVITY_NEW_TASK starts
            // the activity in a new task which severs the result channel and causes
            // the app to open without ever filling the fields.
            val unlockIntent = Intent(this, MainActivity::class.java).apply {
                putExtra(AUTOFILL_AUTH_KEY, true)
                if (usernameId != null) putExtra(AUTOFILL_USERNAME_ID_KEY, usernameId)
                if (passwordId != null) putExtra(AUTOFILL_PASSWORD_ID_KEY, passwordId)
                putExtra(AUTOFILL_WEB_DOMAIN_KEY, webDomain ?: "")
                putExtra(AUTOFILL_PKG_NAME_KEY,   packageName ?: "")
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                1001,
                unlockIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val presentation = RemoteViews(this.packageName, R.layout.autofill_item).apply {
                setTextViewText(R.id.autofill_title, "KMD Volt")
                setTextViewText(R.id.autofill_subtitle, "Desbloquear para ver contraseñas")
                setImageViewResource(R.id.autofill_icon, R.drawable.ic_volt)
            }

            val dataSet = Dataset.Builder()
            if (usernameId != null) {
                dataSet.setValue(usernameId, AutofillValue.forText(""), presentation)
            }
            if (passwordId != null) {
                dataSet.setValue(passwordId, AutofillValue.forText(""), presentation)
            }
            dataSet.setAuthentication(pendingIntent.intentSender)

            val responseBuilder = FillResponse.Builder().addDataset(dataSet.build())
            if (saveInfo != null) responseBuilder.setSaveInfo(saveInfo)
            return callback.onSuccess(responseBuilder.build())
        }

        // ── Unlocked path ────────────────────────────────────────────────────
        val entriesJson = prefs.getString(ENTRIES_KEY, "[]") ?: "[]"
        val entries = parseEntries(entriesJson)
        if (entries.isEmpty()) return callback.onSuccess(null)

        // Match entries by web domain, package name, or title — most specific first
        val matching = when {
            webDomain != null -> entries.filter {
                it.url.contains(webDomain, ignoreCase = true) ||
                it.title.contains(webDomain, ignoreCase = true)
            }.ifEmpty {
                if (packageName != null) {
                    val stem = packageName.substringAfterLast('.')
                    entries.filter {
                        it.title.contains(stem, ignoreCase = true) ||
                        it.url.contains(stem, ignoreCase = true)
                    }.ifEmpty { entries }
                } else entries
            }
            packageName != null -> {
                val stem = packageName.substringAfterLast('.')
                entries.filter {
                    it.title.contains(stem, ignoreCase = true) ||
                    it.url.contains(stem, ignoreCase = true) ||
                    it.url.contains(packageName, ignoreCase = true)
                }.ifEmpty { entries }
            }
            else -> entries
        }

        val responseBuilder = FillResponse.Builder()
        var added = 0

        for (entry in matching.take(5)) {
            val presentation = RemoteViews(this.packageName, R.layout.autofill_item).apply {
                setTextViewText(R.id.autofill_title, entry.title)
                setTextViewText(
                    R.id.autofill_subtitle,
                    entry.username.ifEmpty { "Sin usuario" }
                )
                setImageViewResource(R.id.autofill_icon, R.drawable.ic_volt)
            }

            val dataSet = Dataset.Builder()
            if (usernameId != null) {
                dataSet.setValue(
                    usernameId,
                    AutofillValue.forText(entry.username),
                    presentation
                )
            }
            if (passwordId != null) {
                dataSet.setValue(
                    passwordId,
                    AutofillValue.forText(entry.password),
                    presentation
                )
            }

            try {
                responseBuilder.addDataset(dataSet.build())
                added++
            } catch (e: Exception) { /* skip invalid dataset */ }
        }

        if (added == 0) return callback.onSuccess(null)

        if (saveInfo != null) {
            try {
                responseBuilder.setSaveInfo(saveInfo)
            } catch (e: Exception) { /* save info is optional */ }
        }

        callback.onSuccess(responseBuilder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        var username  = ""
        var password  = ""
        var webDomain = ""
        var appTitle  = ""

        // Scan ALL fill contexts from last to first.  For browser web forms the
        // values typed by the user are in a snapshot taken just before the save UI
        // appeared; iterating all contexts maximises the chance of finding them.
        for (ctx in request.fillContexts.asReversed()) {
            val structure = ctx.structure ?: continue
            val parser = StructureParser(structure)
            parser.parse()

            // Capture field meta from the first context that has field IDs.
            if (webDomain.isEmpty()) webDomain = parser.webDomain ?: ""
            if (appTitle.isEmpty()) appTitle = webDomain.ifEmpty {
                parser.packageName?.substringAfterLast('.') ?: ""
            }

            // 1st pass: values captured inline by the parser (same traversal).
            if (username.isEmpty()) username = parser.usernameValue
            if (password.isEmpty()) password = parser.passwordValue

            // 2nd pass: secondary extractor by autofillId.
            if (username.isEmpty()) username = extractTextValue(structure, parser.usernameId)
            if (password.isEmpty()) password = extractTextValue(structure, parser.passwordId)

            // 3rd pass: brute-force by inputType only (no hints, no IDs required).
            // Handles Chrome/Brave web forms where nodes may lack autofillId or
            // HTML attributes in the save-time snapshot.
            if (username.isEmpty() || password.isEmpty()) {
                parser.bruteForceScan(structure)
                if (username.isEmpty()) username = parser.usernameValue
                if (password.isEmpty()) password = parser.passwordValue
            }

            if (username.isNotEmpty() || password.isNotEmpty()) break
        }

        // Skip only if there is literally nothing to save — not even a domain.
        // When a browser can't expose typed values (Chrome/Brave limitation),
        // we still persist the domain so Flutter can open the entry-creation
        // screen pre-filled and let the user complete the credentials manually.
        if (username.isEmpty() && password.isEmpty() && webDomain.isEmpty() && appTitle.isEmpty()) {
            callback.onSuccess()
            return
        }

        // 1) Persist to pending-save prefs so Flutter picks it up on next open
        //    and writes it to the encrypted database.
        val pendingPrefs = getEncryptedPrefs(this, PENDING_SAVE_PREFS)
        pendingPrefs.edit()
            .putString(PENDING_TITLE,    appTitle)
            .putString(PENDING_USERNAME, username)
            .putString(PENDING_PASSWORD, password)
            .putString(PENDING_URL,      webDomain)
            .putBoolean(HAS_PENDING,     true)
            .apply()

        // 2) Also inject the new entry directly into the autofill cache so that
        //    the suggestion appears immediately the next time the user visits the
        //    same login form — without needing to open KMD Volt first.
        try {
            val autofillPrefs = getEncryptedPrefs(this, PREFS_NAME)
            val existing = autofillPrefs.getString(ENTRIES_KEY, "[]") ?: "[]"
            val arr = org.json.JSONArray(existing)
            val obj = org.json.JSONObject().apply {
                put("title",    appTitle)
                put("username", username)
                put("password", password)
                put("url",      webDomain)
            }
            arr.put(obj)
            autofillPrefs.edit()
                .putString(ENTRIES_KEY, arr.toString())
                .putBoolean(LOCKED_KEY, false)
                .apply()
        } catch (_: Exception) { /* best-effort — Flutter will re-sync on next open */ }

        // Do NOT open the app — the save is durable and will be written to the
        // database the next time the user opens KMD Volt.
        callback.onSuccess()
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /**
     * Safely reads the text value from a [ViewNode].
     * Checks [AutofillValue.isText] before calling [AutofillValue.textValue] to
     * avoid the [IllegalStateException] thrown on non-text values.  Falls back to
     * [ViewNode.text] (the visible display text) when autofillValue is absent.
     */
    private fun nodeTextValue(node: AssistStructure.ViewNode): String {
        val av = node.autofillValue
        if (av != null && av.isText) {
            val t = av.textValue?.toString() ?: ""
            if (t.isNotEmpty()) return t
        }
        return node.text?.toString() ?: ""
    }

    /** Walk the structure to read the current text of the node with [targetId]. */
    private fun extractTextValue(structure: AssistStructure, targetId: AutofillId?): String {
        if (targetId == null) return ""
        for (i in 0 until structure.windowNodeCount) {
            val result = findValueInNode(structure.getWindowNodeAt(i).rootViewNode, targetId)
            if (result != null) return result
        }
        return ""
    }

    private fun findValueInNode(node: AssistStructure.ViewNode, targetId: AutofillId): String? {
        if (node.autofillId == targetId) return nodeTextValue(node)
        for (i in 0 until node.childCount) {
            val result = findValueInNode(node.getChildAt(i), targetId)
            if (result != null) return result
        }
        return null
    }

    // ─── Data class ───────────────────────────────────────────────────────────

    private data class Entry(
        val title: String,
        val username: String,
        val password: String,
        val url: String
    )

    private fun parseEntries(json: String): List<Entry> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                Entry(
                    title    = obj.optString("title"),
                    username = obj.optString("username"),
                    password = obj.optString("password"),
                    url      = obj.optString("url"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}

// ─── EncryptedSharedPreferences helper ───────────────────────────────────────

/**
 * Returns an [EncryptedSharedPreferences] instance backed by AES-256-GCM
 * (values) and AES-256-SIV (keys) using a master key stored in the Android
 * Keystore.  Drop-in replacement for [Context.getSharedPreferences].
 */
internal fun getEncryptedPrefs(context: Context, name: String): SharedPreferences {
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

// ─── Structure Parser ─────────────────────────────────────────────────────────

@RequiresApi(Build.VERSION_CODES.O)
internal class StructureParser(private val structure: AssistStructure) {
    var usernameId:    AutofillId? = null
    var passwordId:    AutofillId? = null
    var usernameValue: String = ""   // value typed/filled in the username field
    var passwordValue: String = ""   // value typed/filled in the password field
    var webDomain:     String? = null
    var packageName:   String? = null

    fun parse() {
        for (i in 0 until structure.windowNodeCount) {
            val windowNode = structure.getWindowNodeAt(i)
            if (packageName == null) {
                packageName = windowNode.title?.toString()?.substringBefore('/')
            }
            parseNode(windowNode.rootViewNode)
        }
    }

    private fun parseNode(node: AssistStructure.ViewNode) {
        val hints       = node.autofillHints ?: emptyArray()
        val inputType   = node.inputType
        val htmlAttrs   = node.htmlInfo?.attributes
        val viewId      = node.idEntry?.lowercase() ?: ""
        val viewHint    = node.hint?.lowercase() ?: ""
        val contentDesc = node.contentDescription?.toString()?.lowercase() ?: ""

        // Pull HTML name/id/autocomplete/placeholder attributes — browsers expose
        // these and they are often more reliable than inputType for web fields.
        val htmlType         = htmlAttrs?.firstOrNull { it.first == "type"         }?.second?.lowercase() ?: ""
        val htmlName         = htmlAttrs?.firstOrNull { it.first == "name"         }?.second?.lowercase() ?: ""
        val htmlId           = htmlAttrs?.firstOrNull { it.first == "id"           }?.second?.lowercase() ?: ""
        val htmlAutocomplete = htmlAttrs?.firstOrNull { it.first == "autocomplete" }?.second?.lowercase() ?: ""
        val htmlPlaceholder  = htmlAttrs?.firstOrNull { it.first == "placeholder"  }?.second?.lowercase() ?: ""

        // All text signals combined into one string for hint matching.
        val allText = "$viewId $viewHint $contentDesc $htmlName $htmlId $htmlPlaceholder"

        // ── Detect password field ────────────────────────────────────────────
        val isPasswordByHint = View.AUTOFILL_HINT_PASSWORD in hints
        val isPasswordByInputType =
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        val isPasswordByHtml = htmlType == "password" ||
            htmlAutocomplete.contains("password") ||
            htmlAutocomplete == "current-password" ||
            htmlAutocomplete == "new-password"
        val isPasswordByName = VoltAutofillService.PASSWORD_HINTS.any { hint ->
            allText.contains(hint)
        }

        val isPassword = isPasswordByHint || isPasswordByInputType ||
                isPasswordByHtml || isPasswordByName

        // ── Detect username / email field ────────────────────────────────────
        val isUsernameByHint =
            View.AUTOFILL_HINT_USERNAME in hints ||
            View.AUTOFILL_HINT_EMAIL_ADDRESS in hints
        val isUsernameByInputType =
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS
        val isUsernameByHtml =
            htmlType == "email" ||
            htmlType == "tel" ||
            htmlAutocomplete == "username" ||
            htmlAutocomplete == "email" ||
            (htmlType == "text" && VoltAutofillService.USERNAME_HINTS.any { hint ->
                htmlName.contains(hint) || htmlId.contains(hint) || htmlPlaceholder.contains(hint)
            })
        val isUsernameByName = VoltAutofillService.USERNAME_HINTS.any { hint ->
            allText.contains(hint)
        }

        val isUsername = (isUsernameByHint || isUsernameByInputType ||
                isUsernameByHtml || isUsernameByName) && !isPassword

        // ── Assign first match (capture value inline — same node, same traversal) ─
        // Note: autofillId CAN be null for web-form nodes in Chrome/Brave; we
        // still capture the value even when the ID is absent.
        if (isPassword && passwordValue.isEmpty()) {
            if (passwordId == null) passwordId = node.autofillId  // may stay null
            val v = safeNodeText(node)
            if (v.isNotEmpty()) passwordValue = v
        } else if (isUsername && usernameValue.isEmpty()) {
            if (usernameId == null) usernameId = node.autofillId  // may stay null
            val v = safeNodeText(node)
            if (v.isNotEmpty()) usernameValue = v
        }

        // ── Capture web domain ───────────────────────────────────────────────
        if (webDomain == null && node.webDomain != null) {
            webDomain = node.webDomain
        }

        // ── Recurse into children ────────────────────────────────────────────
        for (i in 0 until node.childCount) {
            parseNode(node.getChildAt(i))
        }
    }

    /**
     * Safely extracts the text value from a [ViewNode] without risking the
     * [IllegalStateException] thrown by [AutofillValue.textValue] on non-text types.
     */
    private fun safeNodeText(node: AssistStructure.ViewNode): String {
        try {
            val av = node.autofillValue
            if (av != null && av.isText) {
                val t = av.textValue?.toString() ?: ""
                if (t.isNotEmpty()) return t
            }
        } catch (_: Exception) { /* ignore non-text autofill values */ }
        return node.text?.toString() ?: ""
    }

    /**
     * Last-resort brute-force credential scan used in [onSaveRequest] when the
     * normal parser finds no values (common in Chrome/Brave web forms where nodes
     * may lack autofillId or HTML attributes in the save-time snapshot).
     *
     * Walks every node and collects the first non-empty value found in a field
     * that looks like a password or username by inputType alone.
     */
    fun bruteForceScan(structure: AssistStructure) {
        for (i in 0 until structure.windowNodeCount) {
            scanNodeBrute(structure.getWindowNodeAt(i).rootViewNode)
        }
    }

    private fun scanNodeBrute(node: AssistStructure.ViewNode) {
        val inputType = node.inputType
        val htmlAttrs = node.htmlInfo?.attributes
        val htmlType  = htmlAttrs?.firstOrNull { it.first == "type" }?.second?.lowercase() ?: ""

        val isPwd = htmlType == "password" ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD

        val isUser = !isPwd && (
            htmlType == "email" || htmlType == "tel" ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
            inputType and android.text.InputType.TYPE_MASK_VARIATION ==
                android.text.InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS
        )

        val value = safeNodeText(node)

        if (isPwd  && passwordValue.isEmpty() && value.isNotEmpty()) passwordValue = value
        if (isUser && usernameValue.isEmpty() && value.isNotEmpty()) usernameValue = value

        for (i in 0 until node.childCount) scanNodeBrute(node.getChildAt(i))
    }
}
