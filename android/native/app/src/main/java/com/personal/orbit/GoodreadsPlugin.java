package com.personal.orbit;

import android.annotation.SuppressLint;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * Goodreads updates, as GoodreadsSync.swift does on the Mac: Goodreads closed its public API in 2020, so you sign in
 * to Goodreads once inside Joshu (a visible WebView), and Joshu then posts progress, shelves and reviews through that
 * sign-in from a hidden WebView that shares its cookies (android.webkit.CookieManager is per app).
 *
 * The steps themselves (which page to open, which form to post) live in android/src/lib/goodreads.ts; this plugin
 * only provides the browser: signIn, load, run (async JavaScript in the loaded page), fetchText and signOut.
 */
@CapacitorPlugin(name = "Goodreads")
public class GoodreadsPlugin extends Plugin {
    private static final String SIGN_IN_URL = "https://www.goodreads.com/user/sign_in";
    private static final long LOAD_TIMEOUT_MS = 30_000;
    private static final long RUN_TIMEOUT_MS = 30_000;

    private final Handler main = new Handler(Looper.getMainLooper());

    // The hidden browser.
    private WebView hidden;
    private PluginCall pendingLoad;
    private int loadToken = 0;
    private int runCounter = 0;

    // The sign-in sheet.
    private Dialog signInDialog;
    private PluginCall pendingSignIn;

    // MARK: Shared WebView setup

    @SuppressLint("SetJavaScriptEnabled")
    private void configure(WebView w) {
        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        // Sign-in pages (Goodreads, Amazon) sometimes refuse browsers that call themselves a WebView.
        String ua = s.getUserAgentString();
        if (ua != null) s.setUserAgentString(ua.replace("; wv", ""));
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(w, true);
    }

    // MARK: Sign in (visible)

    /** Shows Goodreads' own sign-in page; resolves { signedIn } when you're in, or false if you cancel. */
    @PluginMethod
    public void signIn(PluginCall call) {
        main.post(() -> {
            if (pendingSignIn != null) pendingSignIn.resolve(result("signedIn", false));
            pendingSignIn = call;
            if (signInDialog != null) { signInDialog.dismiss(); signInDialog = null; }
            showSignIn();
        });
    }

    private void showSignIn() {
        Dialog d = new Dialog(getActivity(), android.R.style.Theme_DeviceDefault_Light_NoActionBar);
        d.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout root = new LinearLayout(getContext());
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        LinearLayout bar = new LinearLayout(getContext());
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        int pad = dp(14);
        bar.setPadding(pad, dp(8), dp(8), dp(8));

        TextView title = new TextView(getContext());
        title.setText("Sign in to Goodreads");
        title.setTextColor(0xFF111111);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        bar.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        Button cancel = new Button(getContext());
        cancel.setText("Cancel");
        cancel.setAllCaps(false);
        cancel.setOnClickListener(v -> d.cancel());
        bar.addView(cancel, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        root.addView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        WebView web = new WebView(getContext());
        configure(web);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                // Watches the sign-in page: once Goodreads moves on to your home page, you're signed in (LoginWatcher).
                if (url == null) return;
                Uri u = Uri.parse(url);
                String host = u.getHost();
                if (host == null || !host.contains("goodreads.com")) return;
                String path = u.getPath() == null ? "" : u.getPath();
                boolean stillSigningIn = path.contains("sign_in") || path.contains("/user/new") || path.contains("/ap/")
                    || (path.isEmpty() && u.getQuery() != null);
                if (!stillSigningIn && !path.contains("sign_up")) finishSignIn(true);
            }
        });
        root.addView(web, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        // Keep the bar clear of the status bar and the page clear of the keyboard and navigation bar.
        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets i = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.ime());
            v.setPadding(i.left, i.top, i.right, i.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        d.setContentView(root);
        d.setOnKeyListener((dialog, keyCode, event) -> {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_UP && web.canGoBack()) {
                web.goBack();
                return true;
            }
            return keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_DOWN && web.canGoBack();
        });
        d.setOnCancelListener(dialog -> finishSignIn(false));
        d.setOnDismissListener(dialog -> {
            web.stopLoading();
            main.post(web::destroy); // not from inside the WebView's own callback
            if (signInDialog == d) signInDialog = null;
        });
        signInDialog = d;
        d.show();
        Window w = d.getWindow();
        if (w != null) {
            w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        }
        web.loadUrl(SIGN_IN_URL);
    }

    private void finishSignIn(boolean signedIn) {
        if (signedIn) CookieManager.getInstance().flush();
        PluginCall call = pendingSignIn;
        pendingSignIn = null;
        if (call != null) call.resolve(result("signedIn", signedIn));
        Dialog d = signInDialog;
        signInDialog = null;
        if (d != null && d.isShowing()) d.dismiss();
    }

    // MARK: The hidden browser

    private WebView hiddenWeb() {
        if (hidden != null) return hidden;
        WebView w = new WebView(getContext());
        configure(w);
        // Never attached to the window; give it a desktop-ish size like the Mac's 800×600 so pages lay out.
        w.layout(0, 0, 800, 600);
        w.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                finishLoad(url);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) finishLoad(null);
            }
        });
        hidden = w;
        return w;
    }

    /** Loads a Goodreads page in the background; resolves { url } with where it ended up (null when it failed). */
    @PluginMethod
    public void load(PluginCall call) {
        String url = call.getString("url");
        if (url == null || !url.startsWith("https://www.goodreads.com/")) {
            call.reject("Only Goodreads pages can be opened.");
            return;
        }
        main.post(() -> {
            WebView w = hiddenWeb();
            if (pendingLoad != null) finishLoad(null);
            pendingLoad = call;
            final int token = ++loadToken;
            main.postDelayed(() -> { if (token == loadToken && pendingLoad != null) finishLoad(null); }, LOAD_TIMEOUT_MS);
            w.loadUrl(url);
        });
    }

    private void finishLoad(String url) {
        PluginCall call = pendingLoad;
        pendingLoad = null;
        if (call == null) return;
        JSObject ret = new JSObject();
        ret.put("url", url == null ? JSONObject.NULL : url);
        call.resolve(ret);
    }

    /**
     * Runs `script` (a JavaScript expression that evaluates to an async function) with `args` in the loaded page,
     * like WKWebView.callAsyncJavaScript, and resolves { value } with what it returned (or rejects with its error).
     */
    @PluginMethod
    public void run(PluginCall call) {
        String script = call.getString("script");
        JSObject args = call.getObject("args", new JSObject());
        if (script == null) { call.reject("No script."); return; }
        main.post(() -> {
            if (hidden == null) { call.reject("No Goodreads page is loaded."); return; }
            final String id = "r" + (++runCounter);
            String js = "(function(){window.__joshuGR=window.__joshuGR||{};"
                + "Promise.resolve().then(function(){return (" + script + ")(" + args.toString() + ");})"
                + ".then(function(v){window.__joshuGR['" + id + "']=JSON.stringify({ok:true,value:(v===undefined?null:v)});},"
                + "function(e){window.__joshuGR['" + id + "']=JSON.stringify({ok:false,error:String((e&&e.message)||e)});});"
                + "return true;})()";
            hidden.evaluateJavascript(js, null);
            poll(call, id, System.currentTimeMillis() + RUN_TIMEOUT_MS);
        });
    }

    private void poll(PluginCall call, String id, long deadline) {
        main.postDelayed(() -> {
            if (hidden == null) { call.reject("The Goodreads page went away."); return; }
            String read = "(function(){var s=window.__joshuGR&&window.__joshuGR['" + id + "'];"
                + "if(s!==undefined){delete window.__joshuGR['" + id + "'];return s;}return null;})()";
            hidden.evaluateJavascript(read, raw -> {
                String json = decode(raw);
                if (json == null) {
                    if (System.currentTimeMillis() > deadline) call.reject("Goodreads didn't answer.");
                    else poll(call, id, deadline);
                    return;
                }
                try {
                    JSONObject o = new JSONObject(json);
                    if (o.optBoolean("ok")) {
                        JSObject ret = new JSObject();
                        ret.put("value", o.opt("value"));
                        call.resolve(ret);
                    } else {
                        call.reject(o.optString("error", "Script failed."));
                    }
                } catch (Exception e) {
                    call.reject("Unreadable answer from Goodreads.", e);
                }
            });
        }, 150);
    }

    /** evaluateJavascript hands back the result JSON-encoded: a quoted string, or "null". */
    private static String decode(String raw) {
        if (raw == null || raw.equals("null") || raw.equals("undefined")) return null;
        try {
            Object v = new JSONTokener(raw).nextValue();
            return v instanceof String ? (String) v : null;
        } catch (Exception e) {
            return null;
        }
    }

    // MARK: Plain requests (no cookies, like URLSession.shared on the Mac)

    /** GETs a Goodreads URL without the sign-in (used for book search); resolves { status, text }. */
    @PluginMethod
    public void fetchText(PluginCall call) {
        String address = call.getString("url");
        if (address == null || !address.startsWith("https://www.goodreads.com/")) {
            call.reject("Only Goodreads addresses can be fetched.");
            return;
        }
        new Thread(() -> {
            HttpURLConnection c = null;
            try {
                c = (HttpURLConnection) new URL(address).openConnection();
                c.setConnectTimeout(15_000);
                c.setReadTimeout(20_000);
                c.setRequestProperty("Accept", "application/json, text/plain, */*");
                int status = c.getResponseCode();
                InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
                String text = "";
                if (in != null) {
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                    in.close();
                    text = new String(out.toByteArray(), StandardCharsets.UTF_8);
                }
                JSObject ret = new JSObject();
                ret.put("status", status);
                ret.put("text", text);
                call.resolve(ret);
            } catch (Exception e) {
                call.reject("Couldn't reach Goodreads: " + e.getMessage(), e);
            } finally {
                if (c != null) c.disconnect();
            }
        }).start();
    }

    // MARK: Sign out

    /** Removes Goodreads' cookies (only Goodreads'; the rest of the app's web data stays). */
    @PluginMethod
    public void signOut(PluginCall call) {
        main.post(() -> {
            CookieManager cm = CookieManager.getInstance();
            String[] urls = { "https://www.goodreads.com", "https://goodreads.com" };
            for (String url : urls) {
                String all = cm.getCookie(url);
                if (all == null) continue;
                for (String part : all.split(";")) {
                    int eq = part.indexOf('=');
                    String name = (eq >= 0 ? part.substring(0, eq) : part).trim();
                    if (name.isEmpty()) continue;
                    String gone = name + "=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/";
                    cm.setCookie(url, gone);
                    cm.setCookie(url, gone + "; Domain=.goodreads.com");
                    cm.setCookie(url, gone + "; Domain=www.goodreads.com");
                }
            }
            cm.flush();
            if (hidden != null) {
                hidden.stopLoading();
                hidden.clearCache(false);
                hidden.loadUrl("about:blank");
            }
            call.resolve();
        });
    }

    /** Whether Goodreads cookies are present at all (a hint; the session may still have run out). */
    @PluginMethod
    public void hasCookies(PluginCall call) {
        main.post(() -> {
            String c = CookieManager.getInstance().getCookie("https://www.goodreads.com");
            call.resolve(result("present", c != null && !c.trim().isEmpty()));
        });
    }

    @Override
    protected void handleOnDestroy() {
        main.post(() -> {
            if (hidden != null) { hidden.destroy(); hidden = null; }
            if (signInDialog != null) { signInDialog.dismiss(); signInDialog = null; }
        });
    }

    // MARK: Helpers

    private JSObject result(String key, boolean value) {
        JSObject o = new JSObject();
        o.put(key, value);
        return o;
    }

    private int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getContext().getResources().getDisplayMetrics()));
    }
}
