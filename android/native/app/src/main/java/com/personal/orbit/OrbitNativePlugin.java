package com.personal.orbit;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.util.Base64;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.ArrayList;
import java.util.Locale;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * The Android pieces Joshu's web code can't do itself: an encrypted secret store (the Mac's Keychain),
 * the loopback listener for Google sign-in, reading bank texts, and speech in and out.
 */
@CapacitorPlugin(
    name = "OrbitNative",
    permissions = {
        @Permission(alias = "sms", strings = { Manifest.permission.READ_SMS }),
        @Permission(alias = "microphone", strings = { Manifest.permission.RECORD_AUDIO }),
    }
)
public class OrbitNativePlugin extends Plugin {
    private static final String KEY_ALIAS = "orbit-secrets";
    private static final String PREFS = "orbit-secure";

    // MARK: Secrets (AES-256-GCM with a key that never leaves the Android Keystore)

    private SecretKey secretKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(KEY_ALIAS)) return ((KeyStore.SecretKeyEntry) ks.getEntry(KEY_ALIAS, null)).getSecretKey();
        KeyGenerator gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        gen.init(new KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build());
        return gen.generateKey();
    }

    private SharedPreferences prefs() { return getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE); }

    @PluginMethod
    public void loadSecrets(PluginCall call) {
        JSObject ret = new JSObject();
        try {
            String box = prefs().getString("box", null);
            if (box == null) { ret.put("json", ""); call.resolve(ret); return; }
            byte[] all = Base64.decode(box, Base64.NO_WRAP);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, secretKey(), new GCMParameterSpec(128, all, 0, 12));
            byte[] plain = c.doFinal(all, 12, all.length - 12);
            ret.put("json", new String(plain, StandardCharsets.UTF_8));
            call.resolve(ret);
        } catch (Exception e) {
            ret.put("json", "");
            call.resolve(ret);
        }
    }

    @PluginMethod
    public void saveSecrets(PluginCall call) {
        try {
            String json = call.getString("json", "{}");
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, secretKey());
            byte[] iv = c.getIV();
            byte[] body = c.doFinal(json.getBytes(StandardCharsets.UTF_8));
            byte[] all = new byte[iv.length + body.length];
            System.arraycopy(iv, 0, all, 0, iv.length);
            System.arraycopy(body, 0, all, iv.length, body.length);
            prefs().edit().putString("box", Base64.encodeToString(all, Base64.NO_WRAP)).apply();
            call.resolve();
        } catch (Exception e) {
            call.reject("Couldn't save to the secure store: " + e.getMessage());
        }
    }

    // MARK: Google sign-in loopback (http://127.0.0.1:<port>, as for Google's desktop clients)

    private ServerSocket loopback;

    @PluginMethod
    public void startLoopback(PluginCall call) {
        try {
            if (loopback != null) try { loopback.close(); } catch (Exception ignored) {}
            loopback = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"));
            loopback.setSoTimeout(300_000);
            JSObject ret = new JSObject();
            ret.put("port", loopback.getLocalPort());
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Couldn't start sign-in: " + e.getMessage());
        }
    }

    @PluginMethod
    public void waitLoopback(PluginCall call) {
        final ServerSocket server = loopback;
        if (server == null) { call.reject("Sign-in wasn't started."); return; }
        new Thread(() -> {
            try {
                while (true) {
                    try (Socket s = server.accept()) {
                        BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
                        String line = in.readLine();
                        if (line == null) continue;
                        String[] parts = line.split(" ");
                        String path = parts.length > 1 ? parts[1] : "/";
                        int q = path.indexOf('?');
                        String query = q >= 0 ? path.substring(q + 1) : "";
                        boolean done = query.contains("code=") || query.contains("error=");
                        String html = done
                            ? "<html><head><meta name=viewport content='width=device-width'></head><body style=\"font-family:sans-serif;background:#111;color:#f4f4f5;display:flex;align-items:center;justify-content:center;height:90vh;margin:0;text-align:center\"><div><h1 style=\"font-family:Georgia,serif\">"
                                + (query.contains("code=") ? "You're connected." : "Sign-in was cancelled.")
                                + "</h1><p>Going back to Joshu…</p></div></body></html>"
                            : "Not found";
                        byte[] body = html.getBytes(StandardCharsets.UTF_8);
                        OutputStream out = s.getOutputStream();
                        out.write(((done ? "HTTP/1.1 200 OK" : "HTTP/1.1 404 Not Found") + "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                        out.write(body);
                        out.flush();
                        if (!done) continue;
                        JSObject ret = new JSObject();
                        ret.put("query", query);
                        call.resolve(ret);
                        break;
                    }
                }
            } catch (Exception e) {
                call.reject("Google sign-in timed out or was cancelled.");
            } finally {
                try { server.close(); } catch (Exception ignored) {}
            }
        }).start();
    }

    /** Back to Joshu from the browser tab (closes the Custom Tab that sits above the app). */
    @PluginMethod
    public void bringToFront(PluginCall call) {
        Intent i = new Intent(getContext(), MainActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(i);
        call.resolve();
    }

    // MARK: Bank texts

    @PluginMethod
    public void smsPermission(PluginCall call) {
        if (getPermissionState("sms") == PermissionState.GRANTED || !call.getBoolean("request", false)) {
            JSObject ret = new JSObject();
            ret.put("granted", getPermissionState("sms") == PermissionState.GRANTED);
            call.resolve(ret);
        } else {
            requestPermissionForAlias("sms", call, "smsPermissionDone");
        }
    }

    @PermissionCallback
    private void smsPermissionDone(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("granted", getPermissionState("sms") == PermissionState.GRANTED);
        call.resolve(ret);
    }

    @PluginMethod
    public void readSms(PluginCall call) {
        if (getPermissionState("sms") != PermissionState.GRANTED) { call.reject("No permission to read SMS."); return; }
        long since = call.getLong("since", 0L);
        int limit = call.getInt("limit", 200);
        JSArray list = new JSArray();
        try (Cursor c = getContext().getContentResolver().query(Uri.parse("content://sms/inbox"),
                new String[] { "_id", "address", "body", "date" }, "date > ?", new String[] { String.valueOf(since) }, "date DESC")) {
            if (c != null) {
                while (c.moveToNext() && list.length() < limit) {
                    JSObject m = new JSObject();
                    m.put("id", c.getString(0));
                    m.put("address", c.getString(1) == null ? "" : c.getString(1));
                    m.put("body", c.getString(2) == null ? "" : c.getString(2));
                    m.put("date", c.getLong(3));
                    list.put(m);
                }
            }
        } catch (Exception e) {
            call.reject("Couldn't read SMS: " + e.getMessage());
            return;
        }
        JSObject ret = new JSObject();
        ret.put("messages", list);
        call.resolve(ret);
    }

    // MARK: Streaming HTTP (Joshu's AI server, which a web page can't call directly)

    /** POSTs `body` to `url` and streams the answer back: a "head" event (status), "chunk" events (base64), then resolves. */
    @PluginMethod
    public void httpStream(PluginCall call) {
        final String id = call.getString("id", "");
        final String url = call.getString("url", "");
        final String body = call.getString("body", "");
        final JSObject headers = call.getObject("headers", new JSObject());
        new Thread(() -> {
            java.net.HttpURLConnection conn = null;
            try {
                conn = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                conn.setRequestMethod("POST");
                conn.setDoOutput(true);
                conn.setConnectTimeout(30_000);
                conn.setReadTimeout(300_000);
                java.util.Iterator<String> keys = headers.keys();
                while (keys.hasNext()) { String k = keys.next(); conn.setRequestProperty(k, headers.getString(k)); }
                try (OutputStream out = conn.getOutputStream()) { out.write(body.getBytes(StandardCharsets.UTF_8)); }
                int status = conn.getResponseCode();
                JSObject head = new JSObject();
                head.put("id", id);
                head.put("status", status);
                head.put("contentType", conn.getContentType() == null ? "application/json" : conn.getContentType());
                notifyListeners("head", head);
                java.io.InputStream in = status >= 400 ? conn.getErrorStream() : conn.getInputStream();
                if (in != null) {
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        JSObject c = new JSObject();
                        c.put("id", id);
                        c.put("data", Base64.encodeToString(buf, 0, n, Base64.NO_WRAP));
                        notifyListeners("chunk", c);
                    }
                    in.close();
                }
                call.resolve();
            } catch (Exception e) {
                call.reject("Network problem: " + e.getMessage());
            } finally {
                if (conn != null) conn.disconnect();
            }
        }).start();
    }

    // MARK: Speech in (Android's speech recognizer) and out (text to speech)

    private SpeechRecognizer recognizer;
    private TextToSpeech tts;
    private boolean ttsReady = false;
    private final Handler main = new Handler(Looper.getMainLooper());

    @PluginMethod
    public void listen(PluginCall call) {
        if (getPermissionState("microphone") != PermissionState.GRANTED) {
            requestPermissionForAlias("microphone", call, "micPermissionDone");
            return;
        }
        startListening(call);
    }

    @PermissionCallback
    private void micPermissionDone(PluginCall call) {
        if (getPermissionState("microphone") == PermissionState.GRANTED) startListening(call);
        else call.reject("Joshu needs the microphone to hear you.");
    }

    private final int[] quietStreams = { android.media.AudioManager.STREAM_MUSIC, android.media.AudioManager.STREAM_NOTIFICATION, android.media.AudioManager.STREAM_SYSTEM };
    private boolean muted = false;

    /** Listening for "Hey Joshu" restarts the recogniser often: silence its start beep while it does. */
    private void mute(boolean on) {
        if (muted == on) return;
        muted = on;
        android.media.AudioManager am = (android.media.AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        if (am == null) return;
        for (int stream : quietStreams) {
            try { am.adjustStreamVolume(stream, on ? android.media.AudioManager.ADJUST_MUTE : android.media.AudioManager.ADJUST_UNMUTE, 0); } catch (Exception ignored) {}
        }
    }

    private void startListening(PluginCall call) {
        final boolean quiet = call.getBoolean("quiet", false);
        main.post(() -> {
            if (quiet) mute(true);
            if (!SpeechRecognizer.isRecognitionAvailable(getContext())) { call.reject("Speech recognition isn't available on this phone."); return; }
            if (recognizer != null) recognizer.destroy();
            recognizer = SpeechRecognizer.createSpeechRecognizer(getContext());
            recognizer.setRecognitionListener(new RecognitionListener() {
                boolean finished = false;
                @Override public void onReadyForSpeech(Bundle b) { if (quiet) main.postDelayed(() -> mute(false), 350); }
                @Override public void onBeginningOfSpeech() {}
                @Override public void onRmsChanged(float rms) {
                    JSObject d = new JSObject(); d.put("level", rms); notifyListeners("level", d);
                }
                @Override public void onBufferReceived(byte[] b) {}
                @Override public void onEndOfSpeech() {}
                @Override public void onError(int error) {
                    mute(false);
                    if (finished) return;
                    finished = true;
                    call.reject(error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ? "No match" : "Speech error " + error);
                }
                @Override public void onResults(Bundle results) {
                    mute(false);
                    if (finished) return;
                    finished = true;
                    ArrayList<String> r = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    JSObject ret = new JSObject();
                    ret.put("text", r != null && !r.isEmpty() ? r.get(0) : "");
                    call.resolve(ret);
                }
                @Override public void onPartialResults(Bundle partial) {
                    ArrayList<String> r = partial.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    if (r != null && !r.isEmpty()) { JSObject d = new JSObject(); d.put("text", r.get(0)); notifyListeners("partial", d); }
                }
                @Override public void onEvent(int type, Bundle b) {}
            });
            Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            String lang = call.getString("lang");
            if (lang != null && !lang.isEmpty()) i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang);
            i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L);
            recognizer.startListening(i);
        });
    }

    @PluginMethod
    public void stopListening(PluginCall call) {
        main.post(() -> { if (recognizer != null) recognizer.stopListening(); call.resolve(); });
    }

    @PluginMethod
    public void speak(PluginCall call) {
        String text = call.getString("text", "");
        String lang = call.getString("lang");
        Runnable say = () -> {
            // Arabic text is read with an Arabic voice; everything else with the phone's language.
            Locale locale = lang != null && !lang.isEmpty() ? Locale.forLanguageTag(lang)
                : text.matches("(?s).*[\\u0600-\\u06FF].*") ? new Locale("ar") : Locale.getDefault();
            tts.setLanguage(locale);
            tts.setOnUtteranceProgressListener(new android.speech.tts.UtteranceProgressListener() {
                @Override public void onStart(String id) {}
                @Override public void onDone(String id) { call.resolve(); }
                @Override public void onError(String id) { call.resolve(); }
                @Override public void onStop(String id, boolean interrupted) { call.resolve(); }
            });
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "joshu-" + System.currentTimeMillis());
        };
        if (tts != null && ttsReady) { say.run(); return; }
        tts = new TextToSpeech(getContext(), status -> {
            ttsReady = status == TextToSpeech.SUCCESS;
            if (ttsReady) say.run(); else call.reject("Text to speech isn't available.");
        });
    }

    @PluginMethod
    public void stopSpeaking(PluginCall call) {
        if (tts != null) tts.stop();
        call.resolve();
    }

    @Override
    protected void handleOnDestroy() {
        mute(false);
        if (recognizer != null) recognizer.destroy();
        if (tts != null) tts.shutdown();
        if (loopback != null) try { loopback.close(); } catch (Exception ignored) {}
    }
}
