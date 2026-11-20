package com.leon.app;

import android.content.Context;
import com.vivo.push.*;
import com.vivo.push.listener.IPushQueryActionListener;

final class VivoPushBridge {
    private static boolean initialized;
    static void enable(Context context){
        var app=context.getApplicationContext();var prefs=app.getSharedPreferences("notifications",Context.MODE_PRIVATE);
        if(!BuildConfig.VIVO_PUSH_CONFIGURED||!prefs.getBoolean("enabled",false)||prefs.getString("account","").isEmpty())return;
        try {
            var client=PushClient.getInstance(app);
            if(!initialized){client.initialize(new PushConfig.Builder().agreePrivacyStatement(true).openMultiUserMode(true).build());initialized=true;}
            if(!client.isSupport()){prefs.edit().putString("vivoStatus","当前设备不支持 vivo 推送").apply();return;}
            client.turnOnPush(state->{if(state!=0){prefs.edit().putString("vivoStatus","vivo 注册未完成（"+state+"）").apply();return;}
                client.getRegId(new IPushQueryActionListener(){public void onSuccess(String token){if(token!=null&&!token.isEmpty()){prefs.edit().putString("vivoToken",token).putString("vivoStatus","vivo 设备已注册").apply();bindAccount(app);}}public void onFail(Integer code){prefs.edit().putString("vivoStatus","vivo 设备注册未完成").apply();}});
            });
        }catch(Exception ignored){prefs.edit().putString("vivoStatus","请检查 vivo 平台应用配置").apply();}
    }
    private static void bindAccount(Context context){
        var prefs=context.getSharedPreferences("notifications",Context.MODE_PRIVATE);String account=prefs.getString("account","");
        if(account.isEmpty()||account.equals(prefs.getString("vivoBoundAccount","")))return;
        var client=PushClient.getInstance(context);
        if(!client.isPushSupport(1<<2)||!client.isPushSupport(1<<9)){prefs.edit().putString("vivoStatus","当前系统不支持账号校验；使用应用运行时通知").apply();return;}
        client.deleteAllProfileId(new com.vivo.push.restructure.request.IPushRequestCallback<Integer>(){
            public void onSuccess(Integer value){if(!account.equals(prefs.getString("account","")))return;client.addProfileId(account,new com.vivo.push.restructure.request.IPushRequestCallback<Integer>(){public void onSuccess(Integer value){if(account.equals(prefs.getString("account","")))prefs.edit().putString("vivoBoundAccount",account).apply();}public void onError(int code){prefs.edit().putString("vivoStatus","vivo 账号绑定未完成").apply();}});}
            public void onError(int code){prefs.edit().putString("vivoStatus","vivo 账号校验未完成").apply();}
        });
    }
    static void disable(Context context){context.getSharedPreferences("notifications",Context.MODE_PRIVATE).edit().remove("vivoBoundAccount").apply();if(initialized)try{PushClient.getInstance(context.getApplicationContext()).turnOffPush(state->{});}catch(Exception ignored){}}
}
