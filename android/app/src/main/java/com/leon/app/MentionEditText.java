package com.leon.app;

import android.content.Context;
import android.widget.EditText;

final class MentionEditText extends EditText {
    Runnable selectionChanged;
    interface ImageInput { void accept(android.net.Uri uri,Runnable release); }
    ImageInput imageInput;
    MentionEditText(Context context){super(context);}
    @Override protected void onSelectionChanged(int start,int end){
        super.onSelectionChanged(start,end);
        if(selectionChanged!=null)post(selectionChanged);
    }
    @Override public android.view.inputmethod.InputConnection onCreateInputConnection(android.view.inputmethod.EditorInfo info){
        var original=super.onCreateInputConnection(info);if(original==null)return null;
        info.contentMimeTypes=new String[]{"image/*"};
        return new android.view.inputmethod.InputConnectionWrapper(original,false){
            @Override public boolean commitContent(android.view.inputmethod.InputContentInfo content,int flags,android.os.Bundle options){
                if(imageInput==null||!content.getDescription().hasMimeType("image/*"))return super.commitContent(content,flags,options);
                boolean permission=(flags&android.view.inputmethod.InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION)!=0;
                try {
                    if(permission)content.requestPermission();
                    imageInput.accept(content.getContentUri(),()->{if(permission)content.releasePermission();});return true;
                }catch(SecurityException denied){if(permission)content.releasePermission();return false;}
            }
            @Override public boolean finishComposingText(){boolean result=super.finishComposingText();if(selectionChanged!=null)post(selectionChanged);return result;}
            @Override public boolean commitText(CharSequence text,int position){boolean result=super.commitText(text,position);if(selectionChanged!=null)post(selectionChanged);return result;}
        };
    }
    @Override public boolean onTextContextMenuItem(int id){
        if((id==android.R.id.paste||id==android.R.id.pasteAsPlainText)&&imageInput!=null){
            var clipboard=(android.content.ClipboardManager)getContext().getSystemService(Context.CLIPBOARD_SERVICE);
            var clip=clipboard.getPrimaryClip();boolean handled=false;
            if(clip!=null)for(int index=0;index<Math.min(clip.getItemCount(),5);index++){
                var uri=clip.getItemAt(index).getUri();
                if(uri!=null){
                    try {
                        String type=getContext().getContentResolver().getType(uri);
                        if(type!=null&&type.startsWith("image/")){imageInput.accept(uri,()->{});handled=true;}
                    } catch(SecurityException denied) {
                        if(clip.getDescription().hasMimeType("image/*")){imageInput.accept(uri,()->{});handled=true;}
                    }
                }
            }
            if(handled)return true;
        }
        return super.onTextContextMenuItem(id);
    }
}
