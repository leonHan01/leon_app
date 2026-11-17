package com.leon.app;

import android.content.Context;
import android.widget.EditText;

final class MentionEditText extends EditText {
    Runnable selectionChanged;
    MentionEditText(Context context){super(context);}
    @Override protected void onSelectionChanged(int start,int end){
        super.onSelectionChanged(start,end);
        if(selectionChanged!=null)post(selectionChanged);
    }
    @Override public android.view.inputmethod.InputConnection onCreateInputConnection(android.view.inputmethod.EditorInfo info){
        var original=super.onCreateInputConnection(info);if(original==null)return null;
        return new android.view.inputmethod.InputConnectionWrapper(original,false){
            @Override public boolean finishComposingText(){boolean result=super.finishComposingText();if(selectionChanged!=null)post(selectionChanged);return result;}
            @Override public boolean commitText(CharSequence text,int position){boolean result=super.commitText(text,position);if(selectionChanged!=null)post(selectionChanged);return result;}
        };
    }
}
