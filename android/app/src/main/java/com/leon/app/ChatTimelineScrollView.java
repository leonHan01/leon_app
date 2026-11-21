package com.leon.app;

import android.content.Context;
import android.view.MotionEvent;
import android.widget.ScrollView;

/** Cancel queued automatic positioning when the user begins reading history. */
final class ChatTimelineScrollView extends ScrollView {
    private final Runnable userScroll;
    ChatTimelineScrollView(Context context,Runnable userScroll){super(context);this.userScroll=userScroll;}
    @Override public boolean onTouchEvent(MotionEvent event){
        if(event.getActionMasked()==MotionEvent.ACTION_MOVE)userScroll.run();
        return super.onTouchEvent(event);
    }
    @Override public boolean onGenericMotionEvent(MotionEvent event){
        if(event.getActionMasked()==MotionEvent.ACTION_SCROLL)userScroll.run();
        return super.onGenericMotionEvent(event);
    }
}
