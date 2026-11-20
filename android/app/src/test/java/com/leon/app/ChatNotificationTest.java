package com.leon.app;

import android.app.*;
import android.content.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
public class ChatNotificationTest {
    @Test public void localAlertsAreOptInAccountBoundAndDeduplicatedByMessage(){
        Context context=RuntimeEnvironment.getApplication();var preferences=context.getSharedPreferences("notifications",Context.MODE_PRIVATE);preferences.edit().clear().putString("account","user-1").commit();
        var manager=context.getSystemService(NotificationManager.class);manager.cancelAll();
        ChatNotifications.notify(context,"user-1","group:one",7,"Leon","new");assertEquals(0,Shadows.shadowOf(manager).size());
        preferences.edit().putBoolean("enabled",true).commit();
        ChatNotifications.notify(context,"user-2","group:one",7,"Leon","secret");assertEquals(0,Shadows.shadowOf(manager).size());
        ChatNotifications.notify(context,"user-1","group:one",7,"Leon","new");ChatNotifications.notify(context,"user-1","group:one",7,"Leon","new");
        assertEquals(1,Shadows.shadowOf(manager).size());var notification=Shadows.shadowOf(manager).getAllNotifications().get(0);
        assertEquals(Notification.VISIBILITY_PRIVATE,notification.visibility);assertEquals("chat_messages",notification.getChannelId());
        Intent intent=Shadows.shadowOf(notification.contentIntent).getSavedIntent();assertEquals("user-1",intent.getStringExtra("accountId"));assertEquals("group:one",intent.getStringExtra("roomId"));assertEquals(7,intent.getLongExtra("messageId",0));
        preferences.edit().clear().commit();manager.cancelAll();
    }
}
