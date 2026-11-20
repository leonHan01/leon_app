package com.leon.app;
public final class LeonApplication extends android.app.Application {
    @Override public void onCreate(){super.onCreate();VivoPushBridge.enable(this);}
}
