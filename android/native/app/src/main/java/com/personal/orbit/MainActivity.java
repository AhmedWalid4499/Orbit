package com.personal.orbit;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(OrbitNativePlugin.class);
        registerPlugin(GoodreadsPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
