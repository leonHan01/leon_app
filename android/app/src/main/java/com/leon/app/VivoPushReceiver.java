package com.leon.app;

import android.content.*;
import com.vivo.push.sdk.OpenClientPushMessageReceiver;
import com.vivo.push.model.UPSNotificationMessage;

public final class VivoPushReceiver extends OpenClientPushMessageReceiver {
    @Override public void onReceiveRegId(Context context,String token){if(token!=null&&!token.isEmpty())context.getSharedPreferences("notifications",Context.MODE_PRIVATE).edit().putString("vivoToken",token).apply();}
    @Override public void onForegroundMessageArrived(UPSNotificationMessage message){
        // Foreground messages are rendered by the authenticated inbox loop, which also suppresses the visible room.
    }
    @Override public void onNotificationMessageClicked(Context context,UPSNotificationMessage message){
        var params=message.getParams();if(params==null)return;String account=params.get("accountId"),room=params.get("roomId");long id;try{id=Long.parseLong(params.get("messageId"));}catch(Exception invalid){return;}
        var prefs=context.getSharedPreferences("notifications",Context.MODE_PRIVATE);if(!prefs.getBoolean("enabled",false)||!java.util.Objects.equals(account,prefs.getString("account","")))return;
        context.startActivity(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("accountId",account).putExtra("roomId",room).putExtra("messageId",id));
    }
}
