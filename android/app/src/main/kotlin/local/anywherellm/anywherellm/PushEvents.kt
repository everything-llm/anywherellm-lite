package local.anywherellm.anywherellm

import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Call
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_KEY_AUTH
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_KEY_PUBKEY
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_TEMP
import org.unifiedpush.flutter.connector.PLUGIN_ARG_ENDPOINT_URL
import org.unifiedpush.flutter.connector.PLUGIN_ARG_INSTANCE
import org.unifiedpush.flutter.connector.PLUGIN_ARG_REASON
import org.unifiedpush.flutter.connector.PLUGIN_CALL_NEW_ENDPOINT
import org.unifiedpush.flutter.connector.PLUGIN_CALL_REGISTRATION_FAILED
import org.unifiedpush.flutter.connector.PLUGIN_CALL_UNREGISTERED
import org.unifiedpush.flutter.connector.Plugin
import java.io.Serializable

/**
 * The distributor's events, in place of the Flutter plugin's own service, which starts a
 * Flutter engine for each push only when no plugin was ever made in the process, and so lets a
 * push wait unshown after the activity closed. A push is shown here, natively, as a
 * notification ([PushNotes]); the other events go to the plugin, which buffers them until the
 * Dart side listens.
 */
class PushEvents : PushService() {
    override fun onMessage(message: PushMessage, instance: String) {
        // A push the connector could not decrypt was not sent for this device.
        if (message.decrypted) PushNotes.show(this, instance, message.content)
    }

    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) = forward(
        PLUGIN_CALL_NEW_ENDPOINT,
        mapOf(
            PLUGIN_ARG_INSTANCE to instance,
            PLUGIN_ARG_ENDPOINT_URL to endpoint.url,
            PLUGIN_ARG_ENDPOINT_KEY_PUBKEY to endpoint.pubKeySet?.pubKey,
            PLUGIN_ARG_ENDPOINT_KEY_AUTH to endpoint.pubKeySet?.auth,
            PLUGIN_ARG_ENDPOINT_TEMP to endpoint.temporary,
        ),
    )

    override fun onRegistrationFailed(reason: FailedReason, instance: String) = forward(
        PLUGIN_CALL_REGISTRATION_FAILED,
        mapOf(PLUGIN_ARG_INSTANCE to instance, PLUGIN_ARG_REASON to reason.name),
    )

    override fun onUnregistered(instance: String) =
        forward(PLUGIN_CALL_UNREGISTERED, mapOf(PLUGIN_ARG_INSTANCE to instance))

    /** Hands an event to the plugin, which keeps the last 20 for a Dart side not listening yet. */
    private fun forward(method: String, data: Map<String, Serializable?>) {
        Plugin.calls.tryEmit(Call(method, data))
    }
}
